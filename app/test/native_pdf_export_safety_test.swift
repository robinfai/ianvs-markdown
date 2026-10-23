import AppKit
import PDFKit
import WebKit

/// A renderer deliberately keeps its terminal callback separate from its result:
/// cancellation can finish the Flutter request while native output is unwinding.
@MainActor
private final class DeferredPDFRender {
  let url: URL
  var cancellationCount = 0
  private let completion: (Result<Bool, Error>) -> Void
  private var cleanup: (() -> Void)?

  init(url: URL, cleanup: @escaping () -> Void, completion: @escaping (Result<Bool, Error>) -> Void) {
    self.url = url
    self.cleanup = cleanup
    self.completion = completion
  }
  func cancel() { cancellationCount += 1 }
  func report(_ result: Result<Bool, Error>) { completion(result) }
  func terminate() {
    let callback = cleanup
    cleanup = nil
    callback?()
  }
}

@MainActor
private final class PDFExportHarness {
  private(set) var coordinator: DocumentExportCoordinator!
  var selection: ((URL?) -> Void)?
  var renders = [DeferredPDFRender]()
  var approvals = [(String, (Bool) -> Void)]()
  var results = [Result<Bool, Error>]()
  var dismissals = 0
  var formats = [String]()

  init(window: NSWindow, approvalTimeout: TimeInterval = 5) {
    coordinator = DocumentExportCoordinator(window: window, approvalTimeout: approvalTimeout,
      pickDestination: { [weak self] _, _, format, selected in
        self?.selection = selected
        self?.formats.append(format)
        return { self?.dismissals += 1 }
      }, renderPDF: { [weak self] _, _, temporary, cleanup, completion in
        let render = DeferredPDFRender(url: temporary, cleanup: cleanup, completion: completion)
        self?.renders.append(render)
        return { render.cancel() }
      }, approveCommit: { [weak self] id, approved in self?.approvals.append((id, approved)) })
  }

  @discardableResult
  func start(_ id: String, destination: URL, source: URL? = nil, protected: [URL] = []) -> DeferredPDFRender {
    var arguments: [String: Any] = ["operationId": id, "title": "Unsaved.md",
      "content": "<!doctype html><p>Unsaved 中文</p>", "protectedPaths": protected.map { $0.path }]
    if let source { arguments["sourcePath"] = source.path }
    let count = renders.count
    coordinator.perform("pdf", arguments: arguments) { [weak self] in self?.results.append($0) }
    selection?(destination)
    precondition(renders.count == count + 1, "Expected a private PDF render")
    precondition(formats.last == "pdf")
    return renders.last!
  }

  func cancel(_ id: String, expected: Bool = true) {
    coordinator.perform("cancel", arguments: ["operationId": id]) { result in
      precondition((try? result.get()) == expected)
    }
  }
}

enum NativePDFExportSafetyTests {
  @MainActor
  static func run(window: NSWindow) throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("linefold-pdf-safety-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: root) }
    func phase(_ value: String) { FileHandle.standardOutput.write(Data("PHASE: \(value)\n".utf8)) }
    func rejects(_ body: () throws -> Void) {
      do { try body(); preconditionFailure("Expected the PDF operation to fail closed") } catch { }
    }
    func spin(seconds: TimeInterval, until done: () -> Bool = { false }) {
      let end = Date().addingTimeInterval(seconds)
      while !done(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
    }
    func pdfBytes(pages: Int = 1) -> Data {
      let data = NSMutableData()
      let consumer = CGDataConsumer(data: data)!
      var bounds = CGRect(x: 0, y: 0, width: 595.276, height: 841.89)
      let context = CGContext(consumer: consumer, mediaBox: &bounds, nil)!
      for _ in 0..<pages {
        context.beginPDFPage(nil)
        context.stroke(CGRect(x: 40, y: 40, width: 100, height: 100))
        context.endPDFPage()
      }
      context.closePDF()
      return data as Data
    }
    let valid = pdfBytes()
    let source = root.appendingPathComponent("source.md")
    let original = Data("# Never replace this source\r\n中文😀".utf8)
    try original.write(to: source)

    phase("PDF cancellation, stale render results and terminal-only temp cleanup")
    let cancelled = PDFExportHarness(window: window)
    let destination = root.appendingPathComponent("cancelled.pdf")
    let first = cancelled.start("first", destination: destination, source: source)
    let firstDirectory = first.url.deletingLastPathComponent()
    let attributes = try fm.attributesOfItem(atPath: firstDirectory.path)
    precondition((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    cancelled.cancel("different-operation", expected: false)
    precondition(first.cancellationCount == 0 && cancelled.results.isEmpty)
    cancelled.cancel("first")
    precondition(first.cancellationCount == 1 && cancelled.results.count == 1)
    precondition((try? cancelled.results[0].get()) == false)
    precondition(fm.fileExists(atPath: firstDirectory.path), "Logical cancellation cannot remove an active output")
    let secondDestination = root.appendingPathComponent("second.pdf")
    let second = cancelled.start("second", destination: secondDestination, source: source)
    cancelled.cancel("first", expected: false)
    try valid.write(to: first.url)
    first.report(.success(true))
    first.report(.failure(DocumentExportError(message: "late failure")))
    precondition(cancelled.approvals.isEmpty && cancelled.results.count == 1)
    precondition(second.cancellationCount == 0 && !fm.fileExists(atPath: destination.path))
    first.terminate()
    first.terminate()
    precondition(!fm.fileExists(atPath: firstDirectory.path))
    cancelled.cancel("second")
    second.terminate()

    phase("PDF final approval follows bounded read, survives temp cleanup, and writes once")
    let approved = PDFExportHarness(window: window)
    let approvedDestination = root.appendingPathComponent("approved.pdf")
    let completed = approved.start("approved", destination: approvedDestination, source: source)
    precondition(approved.approvals.isEmpty && !fm.fileExists(atPath: approvedDestination.path))
    try valid.write(to: completed.url)
    completed.report(.success(true))
    precondition(approved.approvals.count == 1 && approved.results.isEmpty)
    precondition(!fm.fileExists(atPath: approvedDestination.path), "Rendering is not write authorization")
    completed.report(.success(true))
    precondition(approved.approvals.count == 1, "Duplicate render callbacks cannot request approval twice")
    completed.terminate() // AppKit deletes its private output before Dart replies.
    precondition(!fm.fileExists(atPath: completed.url.path))
    approved.approvals[0].1(true)
    approved.approvals[0].1(true)
    precondition(approved.results.count == 1 && (try? approved.results[0].get()) == true)
    precondition((try? Data(contentsOf: approvedDestination)) == valid)
    approved.cancel("approved", expected: false)

    phase("PDF cancellation, denial and timeout while awaiting final approval")
    for reason in ["cancel", "deny", "timeout"] {
      let pending = PDFExportHarness(window: window, approvalTimeout: 0.02)
      let output = root.appendingPathComponent("approval-\(reason).pdf")
      let render = pending.start(reason, destination: output)
      try valid.write(to: render.url)
      render.report(.success(true))
      render.terminate()
      precondition(pending.approvals.count == 1)
      let lateApproval = pending.approvals[0].1
      switch reason {
      case "cancel": pending.cancel(reason)
      case "deny": lateApproval(false)
      default: spin(seconds: 2, until: { !pending.results.isEmpty })
      }
      precondition(pending.results.count == 1)
      precondition((try? pending.results[0].get()) == (reason == "timeout" ? nil : false))
      lateApproval(true)
      precondition(pending.results.count == 1 && !fm.fileExists(atPath: output.path))
      let newerOutput = root.appendingPathComponent("after-\(reason).pdf")
      let newer = pending.start("newer", destination: newerOutput)
      lateApproval(true)
      precondition(pending.results.count == 1 && newer.cancellationCount == 0)
      pending.cancel("newer")
      newer.terminate()
    }

    phase("PDF expected destination identity spans rendering and approval")
    for existing in [false, true] {
      let racing = PDFExportHarness(window: window)
      let target = root.appendingPathComponent(existing ? "replaced.pdf" : "appeared.pdf")
      if existing { try Data("Original destination".utf8).write(to: target) }
      let render = racing.start("race", destination: target, source: source)
      let outsider = Data("New bytes from another writer during rendering".utf8)
      try outsider.write(to: target, options: existing ? .atomic : .withoutOverwriting)
      try valid.write(to: render.url)
      render.report(.success(true))
      render.terminate()
      racing.approvals[0].1(true)
      precondition(racing.results.count == 1 && (try? racing.results[0].get()) == nil)
      precondition((try? Data(contentsOf: target)) == outsider)
    }
    let approvalRace = PDFExportHarness(window: window)
    let approvalTarget = root.appendingPathComponent("appeared-during-approval.pdf")
    let approvalRender = approvalRace.start("approval-race", destination: approvalTarget)
    try valid.write(to: approvalRender.url)
    approvalRender.report(.success(true)); approvalRender.terminate()
    let approvalOutsider = Data("New bytes while waiting for approval".utf8)
    try approvalOutsider.write(to: approvalTarget)
    approvalRace.approvals[0].1(true)
    precondition((try? approvalRace.results[0].get()) == nil)
    precondition((try? Data(contentsOf: approvalTarget)) == approvalOutsider)

    phase("PDF source aliases and protected-path writer guards")
    let hardLink = root.appendingPathComponent("source-hardlink.pdf")
    try fm.linkItem(at: source, to: hardLink)
    rejects { try DocumentExportFileWriter.write(valid, to: hardLink, format: "pdf",
      sourcePath: source.path, expected: try ExportDestinationVersion.read(hardLink)) }
    let sourceAlias = root.appendingPathComponent("source-symlink.md")
    try fm.createSymbolicLink(at: sourceAlias, withDestinationURL: source)
    rejects { try DocumentExportFileWriter.validate(hardLink, format: "pdf", sourcePath: sourceAlias.path) }
    let symbolic = root.appendingPathComponent("source-symlink.pdf")
    try fm.createSymbolicLink(at: symbolic, withDestinationURL: source)
    rejects { try DocumentExportFileWriter.validate(symbolic, format: "pdf", sourcePath: source.path) }
    rejects { try DocumentExportFileWriter.validate(approvedDestination, format: "pdf", sourcePath: nil,
      protectedPaths: [approvedDestination.path]) }
    rejects { try DocumentExportFileWriter.write(valid, to: source, format: "pdf",
      sourcePath: source.path, expected: try ExportDestinationVersion.read(source)) }
    let protectedPDF = PDFExportHarness(window: window)
    let protectedRender = protectedPDF.start("protected-pdf", destination: hardLink, protected: [source])
    try valid.write(to: protectedRender.url)
    protectedRender.report(.success(true)); protectedRender.terminate()
    protectedPDF.approvals[0].1(true)
    precondition((try? protectedPDF.results[0].get()) == nil)
    precondition((try? Data(contentsOf: source)) == original)

    phase("PDF file type, private-file alias, byte and page bounds before approval")
    for invalid in ["missing", "empty", "garbage", "oversized", "symlink", "hardlink", "directory", "fifo", "pages"] {
      let bounded = PDFExportHarness(window: window)
      let output = root.appendingPathComponent("invalid-\(invalid).pdf")
      let render = bounded.start("invalid-\(invalid)", destination: output)
      switch invalid {
      case "missing": break
      case "empty": try Data().write(to: render.url)
      case "garbage": try Data("not a PDF".utf8).write(to: render.url)
      case "oversized":
        precondition(fm.createFile(atPath: render.url.path, contents: nil))
        let file = try FileHandle(forWritingTo: render.url)
        try file.truncate(atOffset: UInt64(DocumentExportPDFReader.maximumBytes + 1))
        try file.close()
      case "symlink": try fm.createSymbolicLink(at: render.url, withDestinationURL: approvedDestination)
      case "hardlink": try fm.linkItem(at: approvedDestination, to: render.url)
      case "directory": try fm.createDirectory(at: render.url, withIntermediateDirectories: false)
      case "fifo": precondition(mkfifo(render.url.path, 0o600) == 0)
      default: try pdfBytes(pages: DocumentExportPDFReader.maximumPages + 1).write(to: render.url)
      }
      render.report(.success(true))
      precondition(bounded.approvals.isEmpty && bounded.results.count == 1)
      precondition((try? bounded.results[0].get()) == nil && !fm.fileExists(atPath: output.path))
      render.report(.success(true))
      render.terminate()
      precondition(bounded.results.count == 1)
    }
    let maxPageOutput = root.appendingPathComponent("maximum-pages.pdf")
    try pdfBytes(pages: DocumentExportPDFReader.maximumPages).write(to: maxPageOutput)
    _ = try DocumentExportPDFReader.read(maxPageOutput)
    let overLimitBytes = Data(count: DocumentExportPDFReader.maximumBytes + 1)
    rejects { try DocumentExportFileWriter.write(overLimitBytes, to: root.appendingPathComponent("writer-limit.pdf"),
      format: "pdf", sourcePath: nil, expected: nil) }

    phase("PDF loading/output deadlines, native cancellation, and owner-token leases")
    var completions = 0
    var cancellations = 0
    let loading = DocumentExportLifecycle(loadingTimeout: 0.01, outputTimeout: 0.01,
      cancelOutput: { cancellations += 1 }) { _ in completions += 1 }
    spin(seconds: 2, until: { !loading.isActive })
    precondition(completions == 1 && cancellations == 0 && !loading.isActive)
    loading.finish(.success(true))
    precondition(completions == 1)
    let output = DocumentExportLifecycle(loadingTimeout: 2, outputTimeout: 0.01,
      cancelOutput: { cancellations += 1 }) { result in
        precondition((try? result.get()) == nil)
        completions += 1
      }
    output.beginPrinting(interactive: false)
    spin(seconds: 2, until: { !output.isActive })
    precondition(completions == 2 && cancellations == 1 && !output.isActive)
    output.finish(.success(true))
    precondition(completions == 2)

    for timedOut in [false, true] {
      var cleaned = 0
      var callbacks = 0
      var compilerCallback: ((WKContentRuleList?, Error?) -> Void)?
      var job: OfflineDocumentPrintJob? = OfflineDocumentPrintJob(loadingTimeout: 0.01,
        compileRules: { _, callback in compilerCallback = callback })
      weak var releasedJob = job
      job!.run(html: "<p>not loaded</p>", window: window, pdfDestination: root.appendingPathComponent("unused.pdf"),
        terminalCleanup: { cleaned += 1 }) { result in
          precondition((try? result.get()) == (timedOut ? nil : false))
          callbacks += 1
          job = nil
        }
      if timedOut { spin(seconds: 2, until: { callbacks > 0 }) } else { job?.cancel() }
      compilerCallback?(nil, DocumentExportError(message: "late compile callback"))
      spin(seconds: 0.02)
      precondition(callbacks == 1 && cleaned == 1 && releasedJob == nil)
    }

    let lease = DocumentExportPrintLease()
    let owner = UUID(), next = UUID()
    precondition(lease.acquire(owner) && !lease.acquire(next))
    lease.release(next)
    precondition(!lease.acquire(next))
    lease.release(owner)
    precondition(lease.acquire(next))
    lease.release(owner)
    precondition(!lease.acquire(owner))
    lease.release(next)

    phase("PDF held worker lease rejects before invoking stateful print factory")
    precondition(NSPrintOperation.current == nil)
    let heldToken = UUID()
    precondition(DocumentExportPrintLease.shared.acquire(heldToken))
    defer { DocumentExportPrintLease.shared.release(heldToken) }
    var factoryCalls = 0
    var rejected: Result<Bool, Error>?
    let blockedJob = OfflineDocumentPrintJob(compileRules: { _, _ in }, makePrintOperation: { view, info in
      factoryCalls += 1
      return view.printOperation(with: info)
    })
    blockedJob.run(html: "<p>not printed</p>", window: window, pdfDestination: root.appendingPathComponent("blocked.pdf")) { rejected = $0 }
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    let view = WKWebView(frame: .zero, configuration: configuration)
    blockedJob.webView(view, didFinish: nil)
    precondition(rejected != nil && (try? rejected!.get()) == nil)
    precondition(factoryCalls == 0 && NSPrintOperation.current == nil)
    precondition((try? Data(contentsOf: source)) == original)
    phase("PDF safety checks passed without invoking a real print operation")
  }
}
