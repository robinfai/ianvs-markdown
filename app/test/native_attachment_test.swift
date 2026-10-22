import Foundation
import Darwin

@main
struct AttachmentTests {
  static func main() throws {
    let manager = FileManager.default
    let fixture = manager.temporaryDirectory.appendingPathComponent("linefold-attachments-\(UUID().uuidString)")
    try manager.createDirectory(at: fixture, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: fixture) }
    let root = fixture.appendingPathComponent("vault")
    let outside = fixture.appendingPathComponent("outside")
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    try manager.createDirectory(at: outside, withIntermediateDirectories: true)
    let bytes = Data([0x89, 0x50, 0, 0xff, 0xfe, 0x0a])
    func write(_ relative: String, _ data: Data = Data([0])) throws {
      let target = root.appendingPathComponent(relative)
      try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: target)
    }
    func rejects(_ code: AttachmentError, _ body: () throws -> Void) {
      do { try body(); preconditionFailure("Expected \(code.code)") }
      catch let error as AttachmentError { precondition(error == code, "Expected \(code.code), got \(error.code)") }
      catch { preconditionFailure("Unmapped error: \(error)") }
    }
    func read(_ relative: String, maximum: Int = AttachmentScope.maximumImageBytes) throws -> Data {
      try CloudWorkspace.readAttachmentBytes(root, relativePath: relative, maximumBytes: maximum)
    }
    try write("assets/中文 🖼️.PNG", bytes)
    try write("assets/图表.jpeg", Data([0xff, 0]))
    try write("second/中文 🖼️.PNG", bytes)
    try write("GIF.gif")
    try write("WEBP.webp")
    try write("bitmap.bmp")
    try write("photo.jpg")
    try write("not-an-image.svg")
    try write("unsupported.avif")
    try write("notes.md")
    try write("newline\n.png")
    try write("tab\t.png")
    try write("control\u{001F}/hidden.png")
    try write(".private/secret.png")
    try write(".obsidian/private.png")
    try write(".obsidian/app.json", Data("{\"attachmentFolderPath\":\"assets\"}".utf8))
    try write(".obsidian/other.json", Data("private".utf8))
    try write("assets/.remote.png.icloud", Data("synthetic iCloud stub".utf8))
    try write("assets/.中文 🖼️.PNG.icloud", Data("redundant stub".utf8))
    try Data("outside secret".utf8).write(to: outside.appendingPathComponent("secret.png"))
    try manager.createSymbolicLink(at: root.appendingPathComponent("linked.png"), withDestinationURL: outside.appendingPathComponent("secret.png"))
    try manager.createSymbolicLink(at: root.appendingPathComponent("linked-dir"), withDestinationURL: outside)
    try manager.createSymbolicLink(at: root.appendingPathComponent("dangling.png"), withDestinationURL: outside.appendingPathComponent("missing.png"))
    try manager.createDirectory(at: root.appendingPathComponent("directory.png"), withIntermediateDirectories: true)

    let index = try CloudWorkspace.listAttachments(root)
    let repeatedScope = try AttachmentScope(root)
    let firstListing = try repeatedScope.list().compactMap { $0["relativePath"] as? String }
    let secondListing = try repeatedScope.list().compactMap { $0["relativePath"] as? String }
    precondition(firstListing == secondListing && !secondListing.isEmpty)
    let paths = index.compactMap { $0["relativePath"] as? String }
    let expected = ["assets/中文 🖼️.PNG", "assets/图表.jpeg", "second/中文 🖼️.PNG", "GIF.gif", "WEBP.webp", "bitmap.bmp", "photo.jpg", "assets/remote.png"]
    precondition(Set(paths) == Set(expected), "Unexpected indexed paths: \(paths)")
    precondition(paths == paths.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) })
    for row in index {
      let path = row["relativePath"] as! String
      precondition(row["comparisonPath"] as? String == path.precomposedStringWithCanonicalMapping.lowercased())
      precondition(row["size"] is Int64 && row["modified"] is Int64)
      precondition((row["revision"] as? String)?.split(separator: ":").count == 7)
    }
    precondition(index.first { $0["relativePath"] as? String == "assets/remote.png" }?["size"] as? Int64 == 0)
    precondition(index.first { $0["relativePath"] as? String == "assets/中文 🖼️.PNG" }?["size"] as? Int64 == Int64(bytes.count))
    let actualBytes = try read("assets/中文 🖼️.PNG")
    precondition(actualBytes == bytes, "Binary contents must not pass through UTF-8 decoding")
    let settings = try read(".obsidian/app.json")
    precondition(settings == Data("{\"attachmentFolderPath\":\"assets\"}".utf8))
    rejects(.tooLarge) { _ = try read("assets/中文 🖼️.PNG", maximum: 3) }
    rejects(.invalid) { _ = try read("photo.jpg", maximum: 0) }
    rejects(.invalid) { _ = try read("photo.jpg", maximum: -1) }
    rejects(.missing) { _ = try read("missing.png") }
    for path in ["newline\n.png", "tab\t.png", "control\u{001F}/hidden.png"] {
      rejects(.invalid) { _ = try read(path) }
    }
    rejects(.offline) { _ = try read("assets/remote.png") }
    for path in ["", "/secret.png", "../outside/secret.png", "assets/../../outside/secret.png", "assets/../photo.jpg", "./photo.jpg", "assets//photo.jpg", "https://example.test/image.png", "file:///tmp/image.png", "C:/image.png", "assets\\photo.jpg", "photo.jpg\0.png", ".private/secret.png", ".obsidian/private.png", ".obsidian/other.json", "notes.md", "not-an-image.svg", "unsupported.avif", "linked.png", "linked-dir/secret.png", "dangling.png", "directory.png"] {
      rejects(.invalid) { _ = try read(path) }
    }

    let normalized = try CloudWorkspace.normalizeAttachmentPaths(["Cafe\u{0301}/IMG.PNG", "中文/图.JPG"])
    precondition(normalized == ["café/img.png", "中文/图.jpg"])
    let emptyNormalization = try CloudWorkspace.normalizeAttachmentPaths([])
    precondition(emptyNormalization.isEmpty)
    rejects(.invalid) { _ = try CloudWorkspace.normalizeAttachmentPaths(Array(repeating: "x", count: 33)) }
    rejects(.invalid) { _ = try CloudWorkspace.normalizeAttachmentPaths([String(repeating: "x", count: 4097)]) }
    // One grapheme can contain thousands of scalars; bound UTF-16, not .count.
    rejects(.invalid) { _ = try CloudWorkspace.normalizeAttachmentPaths(["a" + String(repeating: "\u{0301}", count: 4096)]) }
    rejects(.invalid) { _ = try CloudWorkspace.normalizeAttachmentPaths([1, 2]) }
    rejects(.invalid) { _ = try CloudWorkspace.normalizeAttachmentPaths(nil) }

    // Both the config leaf and its parent are subject to the no-symlink rule.
    let config = root.appendingPathComponent(".obsidian/app.json")
    try manager.removeItem(at: config)
    try manager.createSymbolicLink(at: config, withDestinationURL: outside.appendingPathComponent("secret.png"))
    rejects(.invalid) { _ = try read(".obsidian/app.json") }
    try manager.removeItem(at: root.appendingPathComponent(".obsidian"))
    try manager.createSymbolicLink(at: root.appendingPathComponent(".obsidian"), withDestinationURL: outside)
    rejects(.invalid) { _ = try read(".obsidian/app.json") }
    try manager.removeItem(at: root.appendingPathComponent(".obsidian"))
    try write(".obsidian/app.json", Data(repeating: 0, count: AttachmentScope.maximumSettingsBytes + 1))
    rejects(.tooLarge) { _ = try read(".obsidian/app.json", maximum: Int.max) }
    try write("oversized.png")
    let oversizeHandle = try FileHandle(forWritingTo: root.appendingPathComponent("oversized.png"))
    try oversizeHandle.truncate(atOffset: UInt64(AttachmentScope.maximumImageBytes + 1))
    try oversizeHandle.close()
    rejects(.tooLarge) { _ = try read("oversized.png", maximum: Int.max) }

    // Named pipes must neither block the reader nor be indexed as raster files.
    precondition(mkfifo(root.appendingPathComponent("pipe.png").path, 0o600) == 0)
    rejects(.invalid) { _ = try read("pipe.png") }
    let pipeIndex = try CloudWorkspace.listAttachments(root)
    precondition(!pipeIndex.contains { $0["relativePath"] as? String == "pipe.png" })
    if getuid() != 0 {
      try write("unreadable.png")
      try manager.setAttributes([.posixPermissions: 0], ofItemAtPath: root.appendingPathComponent("unreadable.png").path)
      rejects(.denied) { _ = try read("unreadable.png") }
      try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: root.appendingPathComponent("unreadable.png").path)
    }

    let alias = fixture.appendingPathComponent("vault-parent-alias")
    try manager.createSymbolicLink(at: alias, withDestinationURL: fixture)
    let aliasRead = try CloudWorkspace.readAttachmentBytes(alias.appendingPathComponent("vault"), relativePath: "photo.jpg", maximumBytes: 10)
    precondition(aliasRead == Data([0]))
    let rootLink = fixture.appendingPathComponent("vault-link")
    try manager.createSymbolicLink(at: rootLink, withDestinationURL: root)
    rejects(.invalid) { _ = try CloudWorkspace.listAttachments(rootLink) }
    rejects(.invalid) { _ = try CloudWorkspace.readAttachmentBytes(rootLink, relativePath: "photo.jpg", maximumBytes: 10) }

    let policyBefore = getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
    rejects(.missing) {
      try AttachmentScope.withoutMaterialization {
        precondition(getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD) == IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
        throw AttachmentError.missing
      }
    }
    precondition(getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD) == policyBefore)
    precondition(AttachmentError.posix(EACCES) == .denied && AttachmentError.posix(EPERM) == .denied)
    precondition(AttachmentError.posix(EDEADLK) == .offline)
    precondition(AttachmentError.classify(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)) == .denied)
    try verifyCoordinationTimeout(root: root)
    try verifyRevisionIdentity(root: root)
    try verifyReplacementChecks(root: root, outside: outside)
    try verifyIndexLimits(fixture: fixture)
    // Preserve the older document byte/BOM contract while adding binary access.
    let document = root.appendingPathComponent("document.md")
    let source = "\u{FEFF}# 原文\r\n"
    try Data(source.utf8).write(to: document)
    let documentRead = try CloudWorkspace.read(document)
    precondition(Data(documentRead.utf8) == Data(source.utf8))
    print("PASS: scoped binary reads, metadata index, Unicode, iCloud stubs, config scope, symlinks, limits, permissions and replacement checks")
  }

  static func verifyCoordinationTimeout(root: URL) throws {
    let target = root.appendingPathComponent("photo.jpg")
    let writerEntered = DispatchSemaphore(value: 0)
    let releaseWriter = DispatchSemaphore(value: 0)
    let writerFinished = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
      var error: NSError?
      NSFileCoordinator().coordinate(writingItemAt: target, options: [], error: &error) { _ in
        writerEntered.signal()
        precondition(releaseWriter.wait(timeout: .now() + 15) == .success)
      }
      precondition(error == nil)
      writerFinished.signal()
    }
    precondition(writerEntered.wait(timeout: .now() + 10) == .success)
    defer {
      releaseWriter.signal()
      precondition(writerFinished.wait(timeout: .now() + 10) == .success)
    }
    let started = Date()
    do {
      _ = try CloudWorkspace.readAttachmentBytes(root, relativePath: "photo.jpg", maximumBytes: 10)
      preconditionFailure("A held writer must not be bypassed")
    } catch let error as AttachmentError { precondition(error == .unavailable) }
    precondition(Date().timeIntervalSince(started) < 10, "File coordination must have a bounded waiting time")
  }

  static func verifyRevisionIdentity(root: URL) throws {
    let target = root.appendingPathComponent("photo.jpg")
    let before = try CloudWorkspace.listAttachments(root).first { $0["relativePath"] as? String == "photo.jpg" }!
    var attributes = stat()
    precondition(lstat(target.path, &attributes) == 0)
    try Data([2]).write(to: target, options: .atomic)
    let times = [attributes.st_atimespec, attributes.st_mtimespec]
    let status = times.withUnsafeBufferPointer { utimensat(AT_FDCWD, target.path, $0.baseAddress!, 0) }
    precondition(status == 0)
    let after = try CloudWorkspace.listAttachments(root).first { $0["relativePath"] as? String == "photo.jpg" }!
    precondition(before["modified"] as? Int64 == after["modified"] as? Int64)
    precondition(before["size"] as? Int64 == after["size"] as? Int64)
    precondition(before["revision"] as? String != after["revision"] as? String,
                 "Timestamp-preserving atomic replacement must change the cache revision")
  }

  static func verifyReplacementChecks(root: URL, outside: URL) throws {
    let manager = FileManager.default
    let scope = try AttachmentScope(root)
    let image = scope.rootURL.appendingPathComponent("assets/中文 🖼️.PNG")
    func rejects(_ body: () throws -> Data) {
      do { _ = try body(); preconditionFailure("Replacement/redirect must fail closed") }
      catch let error as AttachmentError { precondition(error == .invalid) }
      catch { preconditionFailure("Unexpected replacement error: \(error)") }
    }
    rejects { try scope.readCoordinated(outside.appendingPathComponent("secret.png"), relativePath: "assets/中文 🖼️.PNG", maximumBytes: 1024) }
    rejects { try scope.readCoordinated(scope.rootURL.appendingPathComponent("photo.jpg"), relativePath: "assets/中文 🖼️.PNG", maximumBytes: 1024) }
    // Simulate a directory replaced after preflight but before the accessor.
    let assets = root.appendingPathComponent("assets")
    let moved = root.appendingPathComponent("assets-before-replacement")
    try manager.moveItem(at: assets, to: moved)
    try manager.createSymbolicLink(at: assets, withDestinationURL: outside)
    rejects { try scope.readCoordinated(image, relativePath: "assets/中文 🖼️.PNG", maximumBytes: 1024) }
    try manager.removeItem(at: assets)
    try manager.moveItem(at: moved, to: assets)
    // Simulate the selected root itself being replaced, without reading outside.
    let oldRoot = root.deletingLastPathComponent().appendingPathComponent("old-vault")
    try manager.moveItem(at: root, to: oldRoot)
    try manager.createSymbolicLink(at: root, withDestinationURL: outside)
    rejects { try scope.readCoordinated(image, relativePath: "assets/中文 🖼️.PNG", maximumBytes: 1024) }
    try manager.removeItem(at: root)
    try manager.moveItem(at: oldRoot, to: root)
  }

  static func verifyIndexLimits(fixture: URL) throws {
    let manager = FileManager.default
    let many = fixture.appendingPathComponent("many")
    try manager.createDirectory(at: many, withIntermediateDirectories: true)
    for number in 0...AttachmentScope.maximumEntries {
      precondition(manager.createFile(atPath: many.appendingPathComponent("\(number).png").path, contents: Data()))
    }
    do { _ = try CloudWorkspace.listAttachments(many); preconditionFailure("Must reject an incomplete oversized index") }
    catch let error as AttachmentError { precondition(error == .indexLimit) }
    let deep = fixture.appendingPathComponent("deep")
    var directory = deep
    for _ in 0...AttachmentScope.maximumDepth { directory.appendPathComponent("d") }
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    do { _ = try CloudWorkspace.listAttachments(deep); preconditionFailure("Must bound traversal depth") }
    catch let error as AttachmentError { precondition(error == .indexLimit) }
  }
}
