import AppKit
import CryptoKit

/// Deliberately withholds the writer handoff on its own operation queue. This
/// exercises real NSFileCoordinator waiting/cancel, not just a mocked gate.
private final class WaitingExportPresenter: NSObject, NSFilePresenter {
  let presentedItemURL: URL?
  let presentedItemOperationQueue = OperationQueue()
  let entered = DispatchSemaphore(value: 0)
  let release = DispatchSemaphore(value: 0)
  init(url: URL) { presentedItemURL = url.resolvingSymlinksInPath(); super.init() }
  func relinquishPresentedItem(toWriter writer: @escaping ((() -> Void)?) -> Void) {
    entered.signal()
    release.wait()
    writer(nil)
  }
}

@main
struct NativeDocumentExportAcceptance {
  @MainActor
  static func main() throws {
    func phase(_ name: String) {
      FileHandle.standardOutput.write(Data("PHASE: \(name)\n".utf8))
    }
    phase("destination safety and source preservation")
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("linefold-export-tests-\(UUID().uuidString)")
    try fm.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: root) }
    let source = root.appendingPathComponent("原稿.md")
    let original = Data("# 原稿\r\n\nUnchanged 😀".utf8)
    try original.write(to: source)
    let originalHash = SHA256.hash(data: original)
    func rejects(_ body: () throws -> Void) {
      do { try body(); fatalError("Expected operation to be rejected") } catch { }
    }
    let html = root.appendingPathComponent("文档.html")
    let bytes = Data("<!doctype html><p>中文</p>".utf8)
    try DocumentExportFileWriter.write(bytes, to: html, format: "html", sourcePath: source.path, expected: nil)
    rejects { try DocumentExportFileWriter.write(bytes, to: html, format: "html", sourcePath: source.path, expected: nil) }
    rejects { try DocumentExportFileWriter.validate(html, format: "html", sourcePath: source.path, protectedPaths: [html.path]) }
    let approved = try ExportDestinationVersion.read(html)
    try DocumentExportFileWriter.write(Data("replacement".utf8), to: html, format: "html", sourcePath: source.path, expected: approved)
    rejects { try DocumentExportFileWriter.write(bytes, to: html, format: "html", sourcePath: source.path, expected: approved) }
    rejects { try DocumentExportFileWriter.write(bytes, to: source, format: "html", sourcePath: source.path, expected: nil) }
    let alias = root.appendingPathComponent("alias.html")
    try fm.linkItem(at: source, to: alias)
    rejects { try DocumentExportFileWriter.validate(alias, format: "html", sourcePath: source.path) }
    let symlink = root.appendingPathComponent("link.html")
    try fm.createSymbolicLink(at: symlink, withDestinationURL: source)
    rejects { try DocumentExportFileWriter.validate(symlink, format: "html", sourcePath: source.path) }
    let sourceSymlink = root.appendingPathComponent("source-alias.md")
    try fm.createSymbolicLink(at: sourceSymlink, withDestinationURL: source)
    rejects { try DocumentExportFileWriter.validate(alias, format: "html", sourcePath: sourceSymlink.path) }
    let missing = root.appendingPathComponent("missing-parent/file.html")
    rejects { try DocumentExportFileWriter.write(bytes, to: missing, format: "html", sourcePath: source.path, expected: nil) }
    let protected = root.appendingPathComponent("protected", isDirectory: true)
    try fm.createDirectory(at: protected, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o500])
    rejects { try DocumentExportFileWriter.write(bytes, to: protected.appendingPathComponent("denied.html"), format: "html", sourcePath: source.path, expected: nil) }
    try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: protected.path)
    let cloud = root.appendingPathComponent("offline.html")
    try Data().write(to: root.appendingPathComponent(".offline.html.icloud"))
    rejects { _ = try ExportDestinationVersion.read(cloud) }
    let sourceHash = SHA256.hash(data: try Data(contentsOf: source))
    assert(sourceHash == originalHash)

    phase("Markdown copy, empty copy and source aliases")
    let copy = root.appendingPathComponent("副本.md")
    try DocumentExportFileWriter.write(original, to: copy, format: "md", sourcePath: source.path, expected: nil)
    assert((try? Data(contentsOf: copy)) == original)
    rejects { try DocumentExportFileWriter.write(original, to: source, format: "md", sourcePath: source.path, expected: try ExportDestinationVersion.read(source)) }
    rejects { try DocumentExportFileWriter.validate(copy, format: "md", sourcePath: source.path, protectedPaths: [copy.path]) }
    let markdownAlias = root.appendingPathComponent("hardlink.md")
    try fm.linkItem(at: source, to: markdownAlias)
    rejects { try DocumentExportFileWriter.validate(markdownAlias, format: "md", sourcePath: sourceSymlink.path) }
    let cancelledDestination = root.appendingPathComponent("cancelled-before-write.md")
    rejects { try DocumentExportFileWriter.write(original, to: cancelledDestination, format: "md", sourcePath: source.path, expected: nil, canCommit: { false }) }
    assert(!fm.fileExists(atPath: cancelledDestination.path))
    let blank = root.appendingPathComponent("blank.md")
    try DocumentExportFileWriter.write(Data(), to: blank, format: "md", sourcePath: source.path, expected: nil)
    assert((try? Data(contentsOf: blank))?.isEmpty == true)
    rejects { try DocumentExportFileWriter.validate(root.appendingPathComponent("not-delivered.pdf"), format: "pdf", sourcePath: source.path) }

    phase("coordination deadline and non-cancellable commit authorization")
    let expired = ExportCoordinationDeadline()
    assert(expired.expire() && expired.didExpire)
    assert(!expired.beginAccessor() && !expired.expire() && expired.needsCancellation)
    expired.finish()
    assert(!expired.needsCancellation && expired.didExpire)
    let writing = ExportCoordinationDeadline()
    assert(writing.beginAccessor())
    assert(!writing.expire() && !writing.didExpire && !writing.beginAccessor())
    let finished = ExportCoordinationDeadline()
    finished.finish()
    assert(!finished.expire() && !finished.beginAccessor())
    var committedResults = [Result<Bool, Error>]()
    let commitState = PendingDocumentExport(id: "commit-authorized") { committedResults.append($0) }
    commitState.awaitApproval(seconds: 5)
    assert(commitState.acceptApproval())
    commitState.beginCommit()
    assert(!commitState.cancelBeforeCommit() && committedResults.isEmpty)
    commitState.finish(.success(true))
    assert(committedResults.count == 1 && (try? committedResults[0].get()) == true)
    assert(!commitState.cancelBeforeCommit() && committedResults.count == 1)

    phase("real blocked file presenter coordination expires without a write")
    let contested = root.appendingPathComponent("contested.md")
    try original.write(to: contested)
    let contestedVersion = try ExportDestinationVersion.read(contested)
    let presenter = WaitingExportPresenter(url: contested)
    NSFileCoordinator.addFilePresenter(presenter)
    do {
      defer {
        presenter.release.signal()
        NSFileCoordinator.removeFilePresenter(presenter)
      }
      do {
        try DocumentExportFileWriter.write(Data("must not replace".utf8), to: contested,
          format: "md", sourcePath: source.path, expected: contestedVersion, coordinationTimeout: 2)
        fatalError("Blocked coordination must fail closed at its deadline")
      } catch let error as DocumentExportError {
        assert(error.message.contains("Timed out waiting for access"))
      }
      assert(presenter.entered.wait(timeout: .now()) == .success, "The actual presenter handoff must have blocked")
      assert((try? Data(contentsOf: contested)) == original)
    }
    presenter.presentedItemOperationQueue.waitUntilAllOperationsAreFinished()
    assert((try? Data(contentsOf: contested)) == original, "No late accessor may write after cancellation")

    phase("native destination cancellation, single completion and unavailable commands")
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
    var choices = 0
    var selection: ((URL?) -> Void)?
    let coordinator = DocumentExportCoordinator(window: window, pickDestination: { _, _, _, selected in
      choices += 1
      selection = selected
      return {}
    }, approveCommit: { _, approved in approved(true) })
    let arguments: [String: Any] = ["operationId": "basic", "content": "# Unsaved 中文😀\r\n", "title": "原稿.md", "sourcePath": source.path, "protectedPaths": [source.path]]
    var results = [Result<Bool, Error>]()
    coordinator.perform("markdown", arguments: arguments) { results.append($0) }
    assert(choices == 1 && results.isEmpty)
    coordinator.perform("html", arguments: arguments) { results.append($0) }
    assert(choices == 1 && results.count == 1 && (try? results[0].get()) == nil)
    selection?(nil)
    assert(results.count == 2 && (try? results[1].get()) == false)
    selection?(copy) // A late duplicate selection cannot write or complete twice.
    assert(results.count == 2 && (try? Data(contentsOf: copy)) == original)
    for unsupported in ["pdf", "print"] {
      coordinator.perform(unsupported, arguments: arguments) { results.append($0) }
    }
    assert(choices == 1 && results.count == 4)
    assert((try? results[2].get()) == nil && (try? results[3].get()) == nil)
    coordinator.perform("markdown", arguments: arguments) { results.append($0) }
    selection?(source)
    assert(results.count == 5 && (try? results[4].get()) == nil)
    coordinator.perform("markdown", arguments: arguments) { results.append($0) }
    let chosen = root.appendingPathComponent("chosen.md")
    selection?(chosen)
    assert(results.count == 6 && (try? results[5].get()) == true)
    assert((try? String(contentsOf: chosen, encoding: .utf8)) == arguments["content"] as? String)

    phase("scope approval, cancellation identity, timeout and late callbacks")
    var approve: ((Bool) -> Void)?
    var approvals = 0
    var dismissals = 0
    var guardedResults = [Result<Bool, Error>]()
    let guarded = DocumentExportCoordinator(window: window, approvalTimeout: 0.02,
      pickDestination: { _, _, _, selected in
        selection = selected
        return { dismissals += 1 }
      }, approveCommit: { _, reply in approvals += 1; approve = reply })
    func start(_ id: String) {
      var payload = arguments
      payload["operationId"] = id
      guarded.perform("markdown", arguments: payload) { guardedResults.append($0) }
    }
    func cancel(_ id: String, expected: Bool = true) {
      guarded.perform("cancel", arguments: ["operationId": id]) { value in assert((try? value.get()) == expected) }
    }
    let deferred = root.appendingPathComponent("deferred.md")
    start("first")
    selection?(deferred)
    selection?(copy)
    assert(approvals == 1 && !fm.fileExists(atPath: deferred.path), "Selection must not write before final approval")
    let oldApproval = approve
    cancel("first")
    assert(dismissals == 1 && guardedResults.count == 1 && (try? guardedResults[0].get()) == false)
    oldApproval?(true)
    assert(!fm.fileExists(atPath: deferred.path))
    start("second")
    cancel("first", expected: false) // A delayed cancellation must not dismiss the new panel.
    oldApproval?(true)
    assert(dismissals == 1 && guardedResults.count == 1)
    selection?(deferred)
    let outsider = Data("new destination from another writer".utf8)
    try outsider.write(to: deferred)
    approve?(true)
    assert(guardedResults.count == 2 && (try? guardedResults[1].get()) == nil)
    assert((try? Data(contentsOf: deferred)) == outsider, "Approval await must preserve expected destination version")
    let denied = root.appendingPathComponent("denied-approval.md")
    start("denied")
    selection?(denied)
    approve?(false)
    assert(guardedResults.count == 3 && (try? guardedResults[2].get()) == false)
    assert(!fm.fileExists(atPath: denied.path))
    start("timeout")
    selection?(denied)
    let lateTimeout = approve
    let deadline = Date().addingTimeInterval(2)
    while guardedResults.count < 4 && Date() < deadline {
      RunLoop.main.run(until: Date().addingTimeInterval(0.005))
    }
    assert(guardedResults.count == 4 && (try? guardedResults[3].get()) == nil)
    lateTimeout?(true)
    assert(!fm.fileExists(atPath: denied.path) && guardedResults.count == 4)
    start("after-timeout")
    selection?(denied)
    lateTimeout?(true)
    assert(guardedResults.count == 4)
    approve?(true)
    assert(guardedResults.count == 5 && (try? guardedResults[4].get()) == true)

    phase("production HTML and Markdown fixture round-trip")
    guard CommandLine.arguments.count == 4 else { fatalError("Expected generated HTML, Markdown and evidence folder") }
    let evidence = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
    try fm.createDirectory(at: evidence, withIntermediateDirectories: true)
    for (argument, format) in [(1, "html"), (2, "md")] {
      let fixture = URL(fileURLWithPath: CommandLine.arguments[argument])
      let input = try Data(contentsOf: fixture)
      let exported = evidence.appendingPathComponent("document.\(format)")
      try DocumentExportFileWriter.write(input, to: exported, format: format, sourcePath: fixture.path,
        expected: try ExportDestinationVersion.read(exported))
      let actual = try Data(contentsOf: exported)
      assert(SHA256.hash(data: actual) == SHA256.hash(data: input))
      assert((try? String(contentsOf: exported, encoding: .utf8))?.contains("CELL_149_D") == true)
    }
    let finalSourceHash = SHA256.hash(data: try Data(contentsOf: source))
    assert(finalSourceHash == originalHash)
    print("PASS: exact HTML/Markdown UTF-8 copies, source hash, empty Markdown, cancellation/once-only completion, unsupported PDF/Print, explicit replacement, racing collision, hard-link/symlink, permissions and offline placeholders.")
    window.orderOut(nil)
  }
}
