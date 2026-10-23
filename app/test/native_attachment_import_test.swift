import Foundation
import Darwin
import ImageIO
import CoreGraphics
import FlutterMacOS

@main
struct AttachmentImportTests {
  static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String = "") rethrows {
    let result = try condition()
    precondition(result, message)
  }

  static func rejects(_ expected: AttachmentError, _ body: () throws -> Void) {
    do { try body(); preconditionFailure("Expected \(expected.code)") }
    catch let error as AttachmentImportWriteFailure {
      precondition(error.failure == expected, "Expected \(expected.code), got \(error.failure.code)")
      precondition(!error.relativePath.isEmpty)
    }
    catch let error as AttachmentError { precondition(error == expected, "Expected \(expected.code), got \(error.code)") }
    catch { preconditionFailure("Unexpected error: \(error)") }
  }

  static func raster(_ type: String = "public.png") -> Data {
    let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination))
    return data as Data
  }

  static func main() throws {
    let manager = FileManager.default
    let fixture = manager.temporaryDirectory.appendingPathComponent("linefold-attachment-import-\(UUID().uuidString)")
    let root = fixture.appendingPathComponent("vault")
    let outside = fixture.appendingPathComponent("outside")
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    try manager.createDirectory(at: outside, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: fixture) }
    let png = raster()
    let tiff = raster("public.tiff")
    try testRasterPolicy(png: png, tiff: tiff)
    try testSyntheticClipboard(png: png, tiff: tiff)

    func create(_ directory: String, _ filename: String = "image-1.png", _ bytes: Data? = nil) throws -> String {
      try CloudWorkspace.createWorkspaceAttachment(root, relativeDirectory: directory, filename: filename, bytes: bytes ?? png)
    }
    let rootPath = try create("")
    precondition(rootPath == "image-1.png")
    try expect(try Data(contentsOf: root.appendingPathComponent(rootPath)) == png)
    let nested = try create("附件/截图 assets")
    precondition(nested == "附件/截图 assets/image-1.png")
    try expect(try Data(contentsOf: root.appendingPathComponent(nested)) == png)
    rejects(.collision) { _ = try create("") }
    rejects(.collision) { _ = try create("附件/截图 assets") }
    try expect(try Data(contentsOf: root.appendingPathComponent(rootPath)) == png)
    let canonicalFilename = "image-alias.png"
    try png.write(to: root.appendingPathComponent(canonicalFilename.uppercased()))
    rejects(.collision) { _ = try create("", canonicalFilename) }
    try png.write(to: root.appendingPathComponent(".remote.png.icloud"))
    rejects(.offline) { _ = try create("", "remote.png") }
    try png.write(to: root.appendingPathComponent(".remote-assets.icloud"))
    rejects(.offline) { _ = try create("remote-assets") }
    precondition(!manager.fileExists(atPath: root.appendingPathComponent("remote-assets").path))
    for directory in ["/tmp", ".", "..", "../outside", ".private", ".obsidian/images", "a/../b", "a//b", "a\\b", "a:\\b", "https://example.test/a", "a\nb", "a/\u{0000}b"] {
      rejects(.invalid) { _ = try create(directory, "invalid.png") }
    }
    for filename in ["../x.png", ".secret.png", "a/b.png", "a\\b.png", "a\nb.png", "a.png\0", "a.svg", "a.tiff", "a.JPG", "a.png.exe", "-a.png", "a b.png", "a..png"] {
      rejects(.invalid) { _ = try create("", filename) }
    }
    rejects(.invalid) { _ = try create("new-invalid-dir", "mismatch.jpg") }
    rejects(.unsupported) { _ = try create("new-invalid-dir", "text.png", Data("not a raster".utf8)) }
    rejects(.tooLarge) { _ = try create("new-invalid-dir", "huge.png", Data(repeating: 0, count: AttachmentScope.maximumImageBytes + 1)) }
    precondition(!manager.fileExists(atPath: root.appendingPathComponent("new-invalid-dir").path))

    try png.write(to: outside.appendingPathComponent("existing.png"))
    try manager.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: outside)
    rejects(.invalid) { _ = try create("linked", "injected.png") }
    precondition(!manager.fileExists(atPath: outside.appendingPathComponent("injected.png").path))
    try manager.createSymbolicLink(at: root.appendingPathComponent("link.png"), withDestinationURL: outside.appendingPathComponent("existing.png"))
    rejects(.collision) { _ = try create("", "link.png") }
    try expect(try Data(contentsOf: outside.appendingPathComponent("existing.png")) == png)
    let rootLink = fixture.appendingPathComponent("root-link")
    try manager.createSymbolicLink(at: rootLink, withDestinationURL: root)
    rejects(.invalid) {
      _ = try CloudWorkspace.createWorkspaceAttachment(rootLink, relativeDirectory: "", filename: "new.png", bytes: png)
    }
    let readonly = root.appendingPathComponent("readonly")
    try manager.createDirectory(at: readonly, withIntermediateDirectories: false)
    try manager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readonly.path)
    rejects(.denied) { _ = try create("readonly", "blocked.png") }
    try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: readonly.path)
    precondition(!manager.fileExists(atPath: readonly.appendingPathComponent("blocked.png").path))
    try manager.createDirectory(at: root.appendingPathComponent("hidden-flag"), withIntermediateDirectories: false)
    precondition(chflags(root.appendingPathComponent("hidden-flag").path, UInt32(UF_HIDDEN)) == 0)
    rejects(.invalid) { _ = try create("hidden-flag", "blocked.png") }
    precondition(chflags(root.appendingPathComponent("hidden-flag").path, 0) == 0)

    try testImportSettings(fixture: fixture)
    try testSourceReads(fixture: fixture, png: png)
    try testWriterRaces(root: root, outside: outside, png: png)
    precondition(AttachmentError.posix(EROFS) == .denied)
    print("PASS: explicit image import policy, real format metadata, TIFF conversion, synthetic clipboard, bounded source reads, exclusive scoped writes, Unicode directories, collision/placeholder/permission rejection and replacement checks")
  }

  static func testRasterPolicy(png: Data, tiff: Data) throws {
    let detected = try AttachmentImportImage.inspect(png, allowTIFF: false)
    precondition(detected.extensionName == "png")
    let prepared = try AttachmentImportImage.prepare(png, suggestedName: "misleading.jpg")
    precondition(prepared["extension"] as? String == "png")
    precondition((prepared["bytes"] as? FlutterStandardTypedData)?.data == png)
    let converted = try AttachmentImportImage.prepare(tiff, suggestedName: "Screenshot.tiff")
    precondition(converted["extension"] as? String == "png")
    let convertedBytes = (converted["bytes"] as! FlutterStandardTypedData).data
    try expect(try AttachmentImportImage.inspect(convertedBytes, allowTIFF: false).extensionName == "png")
    rejects(.unsupported) { _ = try AttachmentImportImage.inspect(tiff, allowTIFF: false) }
    rejects(.unsupported) { _ = try AttachmentImportImage.inspect(Data("<svg xmlns='http://www.w3.org/2000/svg'/>".utf8), allowTIFF: true) }
    rejects(.unsupported) { _ = try AttachmentImportImage.inspect(Data(png.prefix(12)), allowTIFF: true) }
    rejects(.tooLarge) { try AttachmentImportImage.validateDimensions(width: 65_536, height: 65_536) }
    rejects(.tooLarge) { try AttachmentImportImage.validateDimensions(width: Double.greatestFiniteMagnitude, height: 2) }
    rejects(.unsupported) { try AttachmentImportImage.validateDimensions(width: .infinity, height: 1) }
    rejects(.unsupported) { try AttachmentImportImage.validateDimensions(width: 0, height: 1) }
    rejects(.unsupported) { try AttachmentImportImage.validateDimensions(width: 1.5, height: 1) }
    try AttachmentImportImage.validateDimensions(width: 8192, height: 4096)
    try AttachmentImportImage.validateTIFFDimensions(width: 4096, height: 2048)
    rejects(.tooLarge) { try AttachmentImportImage.validateTIFFDimensions(width: 8192, height: 4096) }
    rejects(.tooLarge) { try AttachmentImportImage.validateTIFFDimensions(width: 1, height: 8_388_608) }
  }

  static func testSyntheticClipboard(png: Data, tiff: Data) throws {
    var requested: [String] = []
    let result = try AttachmentClipboardImage.read(types: ["public.utf8-plain-text", "public.tiff", "public.png", "public.file-url"]) { type in
      requested.append(type)
      return type == "public.png" ? png : tiff
    }
    precondition(result == png && requested == ["public.png"])
    requested.removeAll()
    let textOnly = try AttachmentClipboardImage.read(types: ["public.utf8-plain-text", "public.file-url", "public.url"]) { type in
      requested.append(type)
      return png
    }
    precondition(textOnly == nil && requested.isEmpty, "Never read text, remote URLs or file URLs")
    rejects(.unsupported) {
      _ = try AttachmentClipboardImage.read(types: ["public.svg-image"]) { _ in preconditionFailure("Do not read unsupported image bytes") }
    }
    rejects(.unavailable) { _ = try AttachmentClipboardImage.read(types: ["public.png"]) { _ in nil } }
    rejects(.tooLarge) {
      _ = try AttachmentClipboardImage.read(types: ["public.png"]) { _ in Data(repeating: 0, count: AttachmentScope.maximumImageBytes + 1) }
    }
    let syntheticTIFF = try AttachmentClipboardImage.read(types: ["public.tiff"]) { _ in tiff }
    precondition(syntheticTIFF == tiff)
  }

  static func testImportSettings(fixture: URL) throws {
    let manager = FileManager.default
    let root = fixture.appendingPathComponent("settings-vault")
    let outside = fixture.appendingPathComponent("outside-config.json")
    let directory = root.appendingPathComponent(".obsidian")
    let config = directory.appendingPathComponent("app.json")
    let stub = directory.appendingPathComponent(".app.json.icloud")
    let original = Data("{\"attachmentFolderPath\":\"附件/截图\"}".utf8)
    try manager.createDirectory(at: root, withIntermediateDirectories: false)
    rejects(.missing) { _ = try CloudWorkspace.readAttachmentImportSettings(root) }
    precondition(!manager.fileExists(atPath: directory.path), "A settings read must not create .obsidian")
    rejects(.unavailable) { _ = try CloudWorkspace.readAttachmentImportSettings(fixture.appendingPathComponent("missing-vault")) }
    let parentStub = root.appendingPathComponent("..obsidian.icloud")
    try original.write(to: parentStub)
    rejects(.offline) { _ = try CloudWorkspace.readAttachmentImportSettings(root) }
    try manager.removeItem(at: parentStub)
    try manager.createSymbolicLink(at: parentStub, withDestinationURL: outside)
    rejects(.invalid) { _ = try CloudWorkspace.readAttachmentImportSettings(root) }
    try manager.removeItem(at: parentStub)
    try original.write(to: directory)
    rejects(.invalid) { _ = try CloudWorkspace.readAttachmentImportSettings(root) }
    try manager.removeItem(at: directory)
    try manager.createDirectory(at: directory, withIntermediateDirectories: false)
    try original.write(to: parentStub)
    rejects(.offline) { _ = try CloudWorkspace.readAttachmentImportSettings(root) }
    try manager.removeItem(at: parentStub)
    var parentState = stat()
    parentState.st_mode = mode_t(S_IFDIR) | mode_t(0o700)
    parentState.st_flags = UInt32(SF_DATALESS)
    rejects(.offline) { try AttachmentImportSettingsScope.requireLocalDirectory(parentState) }
    parentState.st_flags = UInt32(UF_HIDDEN)
    try AttachmentImportSettingsScope.requireLocalDirectory(parentState)
    rejects(.missing) { _ = try CloudWorkspace.readAttachmentImportSettings(root) }
    try original.write(to: config)
    try expect(try CloudWorkspace.readAttachmentImportSettings(root) == original)
    try expect(try Data(contentsOf: config) == original)
    precondition(chflags(directory.path, UInt32(UF_HIDDEN)) == 0)
    precondition(chflags(config.path, UInt32(UF_HIDDEN)) == 0)
    try expect(try CloudWorkspace.readAttachmentImportSettings(root) == original)
    precondition(chflags(config.path, 0) == 0)
    precondition(chflags(directory.path, 0) == 0)
    try original.write(to: outside)

    let rootLink = fixture.appendingPathComponent("settings-root-link")
    try manager.createSymbolicLink(at: rootLink, withDestinationURL: root)
    rejects(.invalid) { _ = try CloudWorkspace.readAttachmentImportSettings(rootLink) }
    try manager.removeItem(at: config)
    try manager.createSymbolicLink(at: config, withDestinationURL: outside)
    rejects(.invalid) { _ = try CloudWorkspace.readAttachmentImportSettings(root) }
    try manager.removeItem(at: config)
    try original.write(to: stub)
    let policyBefore = getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
    rejects(.offline) { _ = try CloudWorkspace.readAttachmentImportSettings(root) }
    precondition(getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD) == policyBefore)
    precondition(!manager.fileExists(atPath: config.path), "Never materialize a config placeholder")
    try expect(try Data(contentsOf: stub) == original)
    try manager.removeItem(at: stub)
    precondition(mkfifo(config.path, 0o600) == 0)
    rejects(.invalid) { _ = try CloudWorkspace.readAttachmentImportSettings(root) }
    try manager.removeItem(at: config)

    let boundary = Data(repeating: 32, count: AttachmentScope.maximumSettingsBytes)
    try boundary.write(to: config)
    try expect(try CloudWorkspace.readAttachmentImportSettings(root) == boundary)
    try Data(repeating: 32, count: AttachmentScope.maximumSettingsBytes + 1).write(to: config)
    rejects(.tooLarge) { _ = try CloudWorkspace.readAttachmentImportSettings(root) }
    try original.write(to: config)
    if getuid() != 0 {
      try manager.setAttributes([.posixPermissions: 0], ofItemAtPath: config.path)
      rejects(.denied) { _ = try CloudWorkspace.readAttachmentImportSettings(root) }
      try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
      try manager.setAttributes([.posixPermissions: 0], ofItemAtPath: directory.path)
      rejects(.denied) { _ = try CloudWorkspace.readAttachmentImportSettings(root) }
      try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
    try testImportSettingsWithoutCoordination(root: root, config: config, expected: original)
    try testImportSettingsReplacement(root: root, config: config, expected: original)
    let movedDirectory = root.appendingPathComponent("saved-settings")
    try manager.moveItem(at: directory, to: movedDirectory)
    try manager.createSymbolicLink(at: directory, withDestinationURL: movedDirectory)
    rejects(.invalid) { _ = try CloudWorkspace.readAttachmentImportSettings(root) }
    try expect(try Data(contentsOf: outside) == original)
  }

  static func testImportSettingsReplacement(root: URL, config: URL, expected: Data) throws {
    let manager = FileManager.default
    rejects(.unavailable) {
      _ = try CloudWorkspace.readAttachmentImportSettings(root, beforeLocalRead: {
        try manager.removeItem(at: config)
      })
    }
    try expected.write(to: config)
    rejects(.unavailable) {
      _ = try CloudWorkspace.readAttachmentImportSettings(root, beforeLocalRead: {
        try expected.write(to: config, options: .atomic)
      })
    }
    rejects(.unavailable) {
      _ = try CloudWorkspace.readAttachmentImportSettings(root, afterLocalRead: {
        try manager.removeItem(at: config)
      })
    }
    try expected.write(to: config)
    let parent = config.deletingLastPathComponent()
    let movedParent = root.appendingPathComponent("observed-settings")
    rejects(.unavailable) {
      _ = try CloudWorkspace.readAttachmentImportSettings(root, afterLocalRead: {
        try manager.moveItem(at: parent, to: movedParent)
        try manager.createDirectory(at: parent, withIntermediateDirectories: false)
      })
    }
    try manager.removeItem(at: parent)
    try manager.moveItem(at: movedParent, to: parent)
    let movedRoot = root.deletingLastPathComponent().appendingPathComponent("observed-settings-root")
    rejects(.unavailable) {
      _ = try CloudWorkspace.readAttachmentImportSettings(root, afterLocalRead: {
        try manager.moveItem(at: root, to: movedRoot)
      })
    }
    try manager.moveItem(at: movedRoot, to: root)
    try expect(try CloudWorkspace.readAttachmentImportSettings(root) == expected)
  }

  static func testImportSettingsWithoutCoordination(root: URL, config: URL, expected: Data) throws {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let finished = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
      var error: NSError?
      NSFileCoordinator().coordinate(writingItemAt: config, options: [], error: &error) { _ in
        entered.signal()
        precondition(release.wait(timeout: .now() + 15) == .success)
      }
      precondition(error == nil)
      finished.signal()
    }
    precondition(entered.wait(timeout: .now() + 10) == .success)
    defer {
      release.signal()
      precondition(finished.wait(timeout: .now() + 10) == .success)
    }
    let started = Date()
    try expect(try CloudWorkspace.readAttachmentImportSettings(root) == expected)
    precondition(Date().timeIntervalSince(started) < 2, "Import config must not wait for a file-coordinator claim")
  }

  static func testSourceReads(fixture: URL, png: Data) throws {
    let manager = FileManager.default
    let source = fixture.appendingPathComponent("source")
    try manager.createDirectory(at: source, withIntermediateDirectories: false)
    let selected = source.appendingPathComponent("source.png")
    try png.write(to: selected)
    try expect(try CloudWorkspace.readPickedAttachmentImage(selected) == png)
    let canonical = selected.resolvingSymlinksInPath()
    let bookmark = try canonical.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    // Diagnose only this synthetic temporary fixture. Foundation can rewrite
    // macOS /private paths; never log user-selected paths in production.
    var bookmarkIsStale = false
    do {
      let resolved = try URL(resolvingBookmarkData: bookmark,
        options: [.withSecurityScope, .withoutUI, .withoutMounting],
        relativeTo: nil, bookmarkDataIsStale: &bookmarkIsStale)
      let diagnostic = "Drop fixture: canonical=\(canonical.path), standardized=\(canonical.standardizedFileURL.path), resolved=\(resolved.path), stale=\(bookmarkIsStale)\n"
      FileHandle.standardError.write(Data(diagnostic.utf8))
    } catch {
      FileHandle.standardError.write(Data("Drop fixture bookmark resolution failed: \(error)\n".utf8))
      throw error
    }
    let dropped = try CloudWorkspace.droppedAttachmentURL(path: canonical.path, bookmark: bookmark)
    expect(dropped.path == canonical.path)
    try expect(try CloudWorkspace.readPickedAttachmentImage(dropped) == png)
    rejects(.invalid) { _ = try CloudWorkspace.droppedAttachmentURL(path: canonical.path, bookmark: nil) }
    rejects(.invalid) { _ = try CloudWorkspace.droppedAttachmentURL(path: canonical.path, bookmark: Data()) }
    rejects(.invalid) { _ = try CloudWorkspace.droppedAttachmentURL(path: canonical.path, bookmark: Data(repeating: 1, count: 1024 * 1024 + 1)) }
    rejects(.invalid) { _ = try CloudWorkspace.droppedAttachmentURL(path: canonical.path, bookmark: Data([1, 2, 3])) }
    rejects(.invalid) { _ = try CloudWorkspace.droppedAttachmentURL(path: canonical.path + "-different.png", bookmark: bookmark) }
    rejects(.invalid) { _ = try CloudWorkspace.droppedAttachmentURL(path: "relative.png", bookmark: bookmark) }
    rejects(.invalid) { _ = try CloudWorkspace.droppedAttachmentURL(path: canonical.path + "/../source.png", bookmark: bookmark) }
    rejects(.invalid) { _ = try CloudWorkspace.droppedAttachmentURL(path: canonical.path + "\0", bookmark: bookmark) }

    try expect(try Data(contentsOf: selected) == png, "Picking must not move, delete, or rewrite the source")
    let link = source.appendingPathComponent("link.png")
    try manager.createSymbolicLink(at: link, withDestinationURL: selected)
    rejects(.invalid) { _ = try CloudWorkspace.readPickedAttachmentImage(link) }
    try png.write(to: source.appendingPathComponent(".offline.png.icloud"))
    rejects(.offline) { _ = try CloudWorkspace.readPickedAttachmentImage(source.appendingPathComponent("offline.png")) }
    let oversized = source.appendingPathComponent("huge.png")
    precondition(manager.createFile(atPath: oversized.path, contents: nil))
    let handle = try FileHandle(forWritingTo: oversized)
    try handle.truncate(atOffset: UInt64(AttachmentScope.maximumImageBytes + 1))
    try handle.close()
    rejects(.tooLarge) { _ = try CloudWorkspace.readPickedAttachmentImage(oversized) }
    let fifo = source.appendingPathComponent("fifo.png")
    precondition(mkfifo(fifo.path, 0o600) == 0)
    rejects(.invalid) { _ = try CloudWorkspace.readPickedAttachmentImage(fifo) }
    rejects(.invalid) { _ = try CloudWorkspace.readPickedAttachmentImage(URL(string: "https://example.test/image.png")!) }
  }

  static func testWriterRaces(root: URL, outside: URL, png: Data) throws {
    let manager = FileManager.default
    let scope = try AttachmentImportScope(root)
    let competitor = Data("concurrent user data".utf8)
    rejects(.unavailable) {
      _ = try scope.create(relativeDirectory: "mkdir-race", filename: "not-created.png", bytes: png, beforeDirectoryCreate: { path in
        precondition(path == "mkdir-race")
        try manager.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: false)
        try competitor.write(to: root.appendingPathComponent(path).appendingPathComponent("keep.txt"))
      })
    }
    try expect(try Data(contentsOf: root.appendingPathComponent("mkdir-race/keep.txt")) == competitor)
    precondition(!manager.fileExists(atPath: root.appendingPathComponent("mkdir-race/not-created.png").path),
                 "Do not adopt a concurrently created directory")
    rejects(.collision) {
      _ = try scope.create(relativeDirectory: "", filename: "race.png", bytes: png, beforeExclusiveCreate: {
        try competitor.write(to: root.appendingPathComponent("race.png"), options: .withoutOverwriting)
      })
    }
    try expect(try Data(contentsOf: root.appendingPathComponent("race.png")) == competitor)
    rejects(.unavailable) {
      _ = try scope.create(relativeDirectory: "", filename: "replacement.png", bytes: png, afterExclusiveCreate: {
        try competitor.write(to: root.appendingPathComponent("replacement.png"), options: .atomic)
      })
    }
    try expect(try Data(contentsOf: root.appendingPathComponent("replacement.png")) == competitor,
                 "Do not roll back/delete a concurrent replacement")
    let parent = root.appendingPathComponent("parent-race")
    let moved = outside.appendingPathComponent("moved-parent")
    rejects(.unavailable) {
      _ = try scope.create(relativeDirectory: "parent-race", filename: "moved.png", bytes: png, afterExclusiveCreate: {
        try manager.moveItem(at: parent, to: moved)
        try manager.createDirectory(at: parent, withIntermediateDirectories: false)
        try competitor.write(to: parent.appendingPathComponent("moved.png"))
      })
    }
    try expect(try Data(contentsOf: parent.appendingPathComponent("moved.png")) == competitor)
    try expect(try Data(contentsOf: moved.appendingPathComponent("moved.png")) == png)
    let beforeParent = root.appendingPathComponent("before-race")
    let movedBefore = outside.appendingPathComponent("before-parent")
    rejects(.invalid) {
      _ = try scope.create(relativeDirectory: "before-race", filename: "not-created.png", bytes: png, beforeExclusiveCreate: {
        try manager.moveItem(at: beforeParent, to: movedBefore)
        try manager.createSymbolicLink(at: beforeParent, withDestinationURL: outside)
      })
    }
    precondition(!manager.fileExists(atPath: outside.appendingPathComponent("not-created.png").path))
    precondition(!manager.fileExists(atPath: movedBefore.appendingPathComponent("not-created.png").path))
    let movedRoot = root.deletingLastPathComponent().appendingPathComponent("old-vault")
    rejects(.invalid) {
      _ = try scope.create(relativeDirectory: "", filename: "root-race.png", bytes: png, beforeExclusiveCreate: {
        try manager.moveItem(at: root, to: movedRoot)
        try manager.createSymbolicLink(at: root, withDestinationURL: outside)
      })
    }
    try manager.removeItem(at: root)
    try manager.moveItem(at: movedRoot, to: root)
    precondition(!manager.fileExists(atPath: outside.appendingPathComponent("root-race.png").path))
  }
}
