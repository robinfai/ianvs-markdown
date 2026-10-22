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
    try verifyWorkspaceText(fixture: fixture)
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

  static func verifyWorkspaceText(fixture: URL) throws {
    let manager = FileManager.default
    let root = fixture.appendingPathComponent("workspace-text")
    let outside = fixture.appendingPathComponent("text-outside")
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    try manager.createDirectory(at: outside, withIntermediateDirectories: true)
    func write(_ relative: String, _ data: Data = Data("note".utf8)) throws {
      let target = root.appendingPathComponent(relative)
      try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: target)
    }
    func rejects(_ expected: AttachmentError, _ body: () throws -> Void) {
      do { try body(); preconditionFailure("Expected text error \(expected.code)") }
      catch let error as AttachmentError { precondition(error == expected, "Expected \(expected.code), got \(error.code)") }
      catch { preconditionFailure("Unmapped text error: \(error)") }
    }
    func read(_ relative: String, maximum: Int = WorkspaceTextScope.maximumTextBytes) throws -> WorkspaceTextBytes {
      try CloudWorkspace.readWorkspaceTextBytes(root, relativePath: relative, maximumBytes: maximum)
    }
    let source = Data("\u{FEFF}# 中文 👩🏽‍💻\r\nExact source.\r\n".utf8)
    try write("中文.md", source)
    try write("empty.md", Data())
    try write("invalid-utf8.md", Data([0xff, 0, 0xc0]))
    for name in ["UPPER.MARKDOWN", "plain.txt", "short.mkd", "down.mdown", "nested/child.md", "image.png",
                 ".private/secret.md", ".obsidian/app.json", "newline\n.md", "tab\t.md"] { try write(name) }
    try write(".remote.md.icloud", Data("synthetic stub".utf8))
    try write(".中文.md.icloud", Data("redundant stub".utf8))
    try manager.createDirectory(at: root.appendingPathComponent("directory.md"), withIntermediateDirectories: true)
    try Data("outside secret".utf8).write(to: outside.appendingPathComponent("secret.md"))
    try manager.createSymbolicLink(at: root.appendingPathComponent("linked.md"), withDestinationURL: outside.appendingPathComponent("secret.md"))
    try manager.createSymbolicLink(at: root.appendingPathComponent("linked-dir"), withDestinationURL: outside)
    try manager.createSymbolicLink(at: root.appendingPathComponent("dangling.md"), withDestinationURL: outside.appendingPathComponent("missing.md"))
    precondition(mkfifo(root.appendingPathComponent("pipe.md").path, 0o600) == 0)
    let catalog = try CloudWorkspace.listWorkspaceDirectory(root, relativePath: "")
    precondition(catalog["complete"] as? Bool == true && catalog["reason"] == nil)
    let rows = catalog["entries"] as! [[String: Any]]
    let paths = rows.map { $0["relativePath"] as! String }
    precondition(Set(paths) == Set(["中文.md", "empty.md", "invalid-utf8.md", "UPPER.MARKDOWN", "plain.txt", "short.mkd", "down.mdown", "nested", "directory.md", "remote.md"]))
    precondition(paths == paths.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) })
    precondition(!paths.contains("nested/child.md"), "Catalog must only enumerate the requested directory")
    let nested = try CloudWorkspace.listWorkspaceDirectory(root, relativePath: "nested")["entries"] as! [[String: Any]]
    precondition(nested.count == 1 && nested[0]["relativePath"] as? String == "nested/child.md")
    let scope = try WorkspaceTextScope(root)
    // The shared descriptor core also rejects malformed components directly;
    // policy callers cannot accidentally turn a component into an extra path.
    rejects(.invalid) { _ = try scope.directoryDescriptor([".."]) }
    rejects(.invalid) { _ = try scope.directoryDescriptor(["nested/.."]) }
    rejects(.invalid) { _ = try scope.parentDescriptor(["../secret.md"]) }
    rejects(.invalid) { _ = try scope.readLocalBytes(components: ["nested/child.md"], maximumBytes: 10, verifyRevision: true) }
    let first = try scope.listDirectory(relativePath: "")["entries"] as! [[String: Any]]
    let again = try scope.listDirectory(relativePath: "")["entries"] as! [[String: Any]]
    precondition(first.map { $0["relativePath"] as! String } == again.map { $0["relativePath"] as! String })
    let local = rows.first { $0["relativePath"] as? String == "中文.md" }!
    precondition(local["local"] as? Bool == true && local["size"] as? Int64 == Int64(source.count))
    let bytes = try read("中文.md")
    precondition(bytes.bytes == source && bytes.revision == local["revision"] as? String)
    precondition(bytes.revision.split(separator: ":").count == 7)
    let empty = try read("empty.md")
    precondition(empty.bytes.isEmpty)
    let invalidUTF8 = try read("invalid-utf8.md")
    precondition(invalidUTF8.bytes == Data([0xff, 0, 0xc0]), "Dart owns UTF-8 validation; native must preserve bytes")
    let remote = rows.first { $0["relativePath"] as? String == "remote.md" }!
    precondition(remote["local"] as? Bool == false && remote["size"] as? Int64 == 0)
    let policy = getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
    rejects(.offline) { _ = try read("remote.md") }
    precondition(getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD) == policy)
    precondition(!manager.fileExists(atPath: root.appendingPathComponent("remote.md").path))
    let stub = try Data(contentsOf: root.appendingPathComponent(".remote.md.icloud"))
    precondition(stub == Data("synthetic stub".utf8), "Search must not materialize or modify an offline stub")
    rejects(.missing) { _ = try read("missing.md") }
    rejects(.tooLarge) { _ = try read("中文.md", maximum: 1) }
    for maximum in [0, -1] { rejects(.invalid) { _ = try read("中文.md", maximum: maximum) } }
    for path in ["", "/secret.md", "../text-outside/secret.md", "nested/../../secret.md", "nested/../中文.md", "./中文.md",
                 "nested//child.md", "nested\\child.md", "file:///secret.md", "name.md\0", "newline\n.md", "tab\t.md",
                 ".private/secret.md", ".obsidian/app.json", "image.png", "linked.md", "linked-dir/secret.md", "dangling.md", "directory.md", "pipe.md"] {
      rejects(.invalid) { _ = try read(path) }
    }
    for path in ["/", "..", "nested/..", ".private", "linked-dir", "nested//child", "nested\\child", "nested/"] {
      rejects(.invalid) { _ = try CloudWorkspace.listWorkspaceDirectory(root, relativePath: path) }
    }
    rejects(.invalid) { _ = try WorkspaceTextScope.textComponents(Array(repeating: "d", count: 65).joined(separator: "/"), directory: true) }
    rejects(.invalid) { _ = try WorkspaceTextScope.textComponents(Array(repeating: "d", count: 65).joined(separator: "/") + "/note.md", directory: false) }
    rejects(.invalid) { _ = try WorkspaceTextScope.textComponents(String(repeating: "x", count: 4097) + ".md", directory: false) }
    let alias = fixture.appendingPathComponent("text-parent-alias")
    try manager.createSymbolicLink(at: alias, withDestinationURL: fixture)
    let aliasRead = try CloudWorkspace.readWorkspaceTextBytes(alias.appendingPathComponent("workspace-text"), relativePath: "中文.md")
    precondition(aliasRead.bytes == source)
    let rootLink = fixture.appendingPathComponent("text-root-link")
    try manager.createSymbolicLink(at: rootLink, withDestinationURL: root)
    rejects(.invalid) { _ = try CloudWorkspace.listWorkspaceDirectory(rootLink, relativePath: "") }
    rejects(.invalid) { _ = try CloudWorkspace.readWorkspaceTextBytes(rootLink, relativePath: "中文.md") }
    if getuid() != 0 {
      try write("denied.md")
      let denied = root.appendingPathComponent("denied.md")
      try manager.setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)
      rejects(.denied) { _ = try read("denied.md") }
      try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: denied.path)
      let deniedDirectory = root.appendingPathComponent("denied-directory")
      try manager.createDirectory(at: deniedDirectory, withIntermediateDirectories: true)
      try manager.setAttributes([.posixPermissions: 0], ofItemAtPath: deniedDirectory.path)
      let parentCatalog = try CloudWorkspace.listWorkspaceDirectory(root, relativePath: "")
      precondition(parentCatalog["complete"] as? Bool == true, "Parent catalog must not descend into unreadable folders")
      rejects(.denied) { _ = try CloudWorkspace.listWorkspaceDirectory(root, relativePath: "denied-directory") }
      try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: deniedDirectory.path)
    }
    try write("limit.md")
    let limitHandle = try FileHandle(forWritingTo: root.appendingPathComponent("limit.md"))
    try limitHandle.truncate(atOffset: UInt64(WorkspaceTextScope.maximumTextBytes))
    let exactLimit = try read("limit.md", maximum: Int.max)
    precondition(exactLimit.bytes.count == WorkspaceTextScope.maximumTextBytes)
    try limitHandle.truncate(atOffset: UInt64(WorkspaceTextScope.maximumTextBytes + 1))
    try limitHandle.close()
    rejects(.tooLarge) { _ = try read("limit.md", maximum: Int.max) }
    let limited = try scope.listDirectory(relativePath: "", entryLimit: 1)
    precondition(limited["complete"] as? Bool == false && limited["reason"] as? String == AttachmentError.indexLimit.code)
    precondition((limited["entries"] as! [[String: Any]]).count <= 1)
    let visited = try scope.listDirectory(relativePath: "", visitedLimit: 1)
    precondition(visited["complete"] as? Bool == false && visited["reason"] as? String == AttachmentError.indexLimit.code)
    let expired = try scope.listDirectory(relativePath: "", deadline: DispatchTime(uptimeNanoseconds: 1))
    precondition(expired["complete"] as? Bool == false && expired["reason"] as? String == AttachmentError.indexLimit.code)
    precondition((expired["entries"] as! [[String: Any]]).isEmpty)

    // Exercise the exact post-read validator deterministically, not a lucky race.
    let target = root.appendingPathComponent("changing.md")
    try write("changing.md", Data("old".utf8))
    let descriptor = open(target.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    precondition(descriptor >= 0)
    defer { close(descriptor) }
    var original = stat()
    precondition(fstat(descriptor, &original) == 0)
    try scope.verifyReadRevision(descriptor: descriptor, components: ["changing.md"], original: original, byteCount: 3)
    rejects(.unavailable) { try scope.verifyReadRevision(descriptor: descriptor, components: ["changing.md"], original: original, byteCount: 2) }
    try Data("new".utf8).write(to: target, options: .atomic)
    let times = [original.st_atimespec, original.st_mtimespec]
    precondition(times.withUnsafeBufferPointer { utimensat(AT_FDCWD, target.path, $0.baseAddress!, 0) } == 0)
    rejects(.unavailable) { try scope.verifyReadRevision(descriptor: descriptor, components: ["changing.md"], original: original, byteCount: 3) }
    let replacement = try read("changing.md")
    precondition(replacement.bytes == Data("new".utf8) && replacement.revision != WorkspaceFileScope.revision(original))
    let inPlace = try FileHandle(forUpdating: target)
    defer { try? inPlace.close() }
    var inPlaceBefore = stat()
    precondition(fstat(inPlace.fileDescriptor, &inPlaceBefore) == 0)
    try inPlace.truncate(atOffset: 1)
    rejects(.unavailable) { try scope.verifyReadRevision(descriptor: inPlace.fileDescriptor, components: ["changing.md"], original: inPlaceBefore, byteCount: 3) }
    let child = root.appendingPathComponent("nested/child.md")
    let childDescriptor = open(child.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    precondition(childDescriptor >= 0)
    defer { close(childDescriptor) }
    var childBefore = stat()
    precondition(fstat(childDescriptor, &childBefore) == 0)
    let nestedBefore = root.appendingPathComponent("nested-before")
    try manager.moveItem(at: root.appendingPathComponent("nested"), to: nestedBefore)
    try write("nested/child.md")
    rejects(.unavailable) {
      try scope.verifyReadRevision(descriptor: childDescriptor, components: ["nested", "child.md"], original: childBefore, byteCount: 4)
    }
    try manager.removeItem(at: root.appendingPathComponent("nested"))
    try manager.moveItem(at: nestedBefore, to: root.appendingPathComponent("nested"))
    try manager.moveItem(at: root.appendingPathComponent("nested"), to: nestedBefore)
    try manager.createSymbolicLink(at: root.appendingPathComponent("nested"), withDestinationURL: outside)
    rejects(.invalid) { _ = try scope.readText(relativePath: "nested/secret.md") }
    rejects(.invalid) { _ = try scope.listDirectory(relativePath: "nested") }
    try manager.removeItem(at: root.appendingPathComponent("nested"))
    try manager.moveItem(at: nestedBefore, to: root.appendingPathComponent("nested"))
    let oldRoot = fixture.appendingPathComponent("text-root-before")
    try manager.moveItem(at: root, to: oldRoot)
    try manager.createSymbolicLink(at: root, withDestinationURL: outside)
    rejects(.invalid) { _ = try scope.readText(relativePath: "secret.md") }
    rejects(.invalid) { _ = try scope.listDirectory(relativePath: "") }
    try manager.removeItem(at: root)
    try manager.moveItem(at: oldRoot, to: root)
    print("PASS: local-only text metadata, exact bytes/revisions, offline stubs, no-follow scope, partial limits and replacement checks")
  }

}
