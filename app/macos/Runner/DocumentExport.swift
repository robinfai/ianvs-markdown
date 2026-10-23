import AppKit
import ApplicationServices
import PDFKit
import UniformTypeIdentifiers
import WebKit

struct DocumentExportError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

/// Metadata only: never opens or downloads the original document or a cloud
/// destination in order to export. SavePanel is the authority for the output.
struct ExportDestinationVersion: Equatable {
  let device: UInt64
  let inode: UInt64
  let size: Int64
  let modifiedSeconds: Int64
  let modifiedNanoseconds: Int64

  static func read(_ url: URL) throws -> Self? {
    var value = stat()
    guard lstat(url.path, &value) == 0 else {
      if errno == ENOENT {
        let placeholder = url.deletingLastPathComponent()
          .appendingPathComponent(".\(url.lastPathComponent).icloud")
        var cloud = stat()
        if lstat(placeholder.path, &cloud) == 0 {
          throw DocumentExportError(message: "The destination is not available offline. Choose another name.")
        }
        guard errno == ENOENT else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        return nil
      }
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    guard value.st_mode & S_IFMT == S_IFREG else {
      throw DocumentExportError(message: "Choose a regular output file, not a folder or symbolic link.")
    }
    return Self(device: UInt64(value.st_dev), inode: UInt64(value.st_ino), size: Int64(value.st_size),
      modifiedSeconds: Int64(value.st_mtimespec.tv_sec), modifiedNanoseconds: Int64(value.st_mtimespec.tv_nsec))
  }
}

/// The deadline bounds coordination wait, never a write already in progress.
/// NSFileCoordinator.cancel() is explicitly safe from any thread; the locked
/// transition prevents an expired accessor from writing after cancellation.
final class ExportCoordinationDeadline: @unchecked Sendable {
  private let lock = NSLock()
  private var waiting = true
  private var expired = false
  private var finished = false
  func beginAccessor() -> Bool {
    lock.lock(); defer { lock.unlock() }
    guard waiting, !expired else { return false }
    waiting = false
    return true
  }
  func expire() -> Bool {
    lock.lock(); defer { lock.unlock() }
    guard waiting, !expired else { return false }
    expired = true
    waiting = false
    return true
  }
  var didExpire: Bool {
    lock.lock(); defer { lock.unlock() }
    return expired
  }
  var needsCancellation: Bool {
    lock.lock(); defer { lock.unlock() }
    return expired && !finished
  }
  func finish() {
    lock.lock(); defer { lock.unlock() }
    waiting = false
    finished = true
  }
}

enum DocumentExportFileWriter {
  static func validate(_ url: URL, format: String, sourcePath: String?, protectedPaths: [String] = []) throws {
    guard url.isFileURL, url.pathExtension.lowercased() == format,
          ["html", "md", "pdf"].contains(format) else {
      throw DocumentExportError(message: "Use a .\(format) filename. Open source documents cannot be replaced by export.")
    }
    _ = try ExportDestinationVersion.read(url)
    let protected = Set(protectedPaths + [sourcePath].compactMap { $0 })
    for sourcePath in protected {
      let source = URL(fileURLWithPath: sourcePath).resolvingSymlinksInPath().standardizedFileURL
      guard source.resolvingSymlinksInPath().standardizedFileURL != url.resolvingSymlinksInPath().standardizedFileURL else {
        throw DocumentExportError(message: "Export cannot replace an open source document.")
      }
      // Hard-link aliases can have a different extension and pathname.
      if let target = try ExportDestinationVersion.read(url),
         let original = try ExportDestinationVersion.read(source),
         target.device == original.device, target.inode == original.inode {
        throw DocumentExportError(message: "Export cannot replace an alias of an open source document.")
      }
    }
  }

  static func write(_ bytes: Data, to url: URL, format: String, sourcePath: String?, expected: ExportDestinationVersion?, protectedPaths: [String] = [], canCommit: @escaping () -> Bool = { true }, coordinationTimeout: TimeInterval = 15) throws {
    guard (format == "md" || !bytes.isEmpty), bytes.count <= 32 * 1024 * 1024 else {
      throw DocumentExportError(message: "The output is empty or exceeds the export size limit.")
    }
    var coordinationError: NSError?
    var result: Result<Void, Error> = .failure(DocumentExportError(message: "The destination could not be coordinated."))
    let coordinator = NSFileCoordinator()
    let deadline = ExportCoordinationDeadline()
    let timeout = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
    // Repeat only while expired and still awaiting coordination. This also
    // covers preemption between arming the timer and entering coordinate():
    // cancel() must not be assumed to cancel a future, not-yet-active call.
    timeout.schedule(deadline: .now() + coordinationTimeout, repeating: .milliseconds(100))
    timeout.setEventHandler {
      if deadline.expire() || deadline.needsCancellation { coordinator.cancel() }
    }
    timeout.resume()
    defer { deadline.finish(); timeout.cancel() }
    coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
      guard deadline.beginAccessor() else { return }
      timeout.cancel()
      result = Result {
        guard canCommit() else { throw DocumentExportError(message: "Export was cancelled before writing.") }
        try validate(url, format: format, sourcePath: sourcePath, protectedPaths: protectedPaths)
        try validate(target, format: format, sourcePath: sourcePath, protectedPaths: protectedPaths)
        guard try ExportDestinationVersion.read(url) == expected,
              try ExportDestinationVersion.read(target) == expected else {
          throw DocumentExportError(message: "The destination changed while exporting. Nothing was replaced; export again.")
        }
        guard canCommit() else { throw DocumentExportError(message: "Export was cancelled before writing.") }
        // A newly appeared name must fail rather than silently overwrite.
        try bytes.write(to: target, options: expected == nil ? .withoutOverwriting : .atomic)
      }
    }
    if deadline.didExpire {
      throw DocumentExportError(message: "Timed out waiting for access to the destination. No file was written; export again.")
    }
    if let coordinationError { throw coordinationError }
    try result.get()
  }
}

/// Reads only the app's completed private output. Reject special files, aliases
/// and oversized output before any allocation proportional to file size or
/// PDFKit parsing. A bounded read also catches growth after the initial stat.
enum DocumentExportPDFReader {
  static let maximumBytes = 32 * 1024 * 1024
  static let maximumPages = 256

  static func read(_ url: URL) throws -> Data {
    guard url.isFileURL, let expected = try ExportDestinationVersion.read(url),
          expected.size > 0, expected.size <= Int64(maximumBytes) else {
      throw DocumentExportError(message: "The PDF is empty or exceeds the 32 MiB export limit.")
    }
    let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? handle.close() }
    func matchesExpected() -> Bool {
      var value = stat()
      return fstat(descriptor, &value) == 0 && value.st_mode & S_IFMT == S_IFREG &&
        value.st_nlink == 1 && UInt64(value.st_dev) == expected.device &&
        UInt64(value.st_ino) == expected.inode && Int64(value.st_size) == expected.size &&
        Int64(value.st_mtimespec.tv_sec) == expected.modifiedSeconds &&
        Int64(value.st_mtimespec.tv_nsec) == expected.modifiedNanoseconds
    }
    guard matchesExpected() else {
      throw DocumentExportError(message: "The private PDF output changed or is not a regular private file.")
    }
    var bytes = Data()
    while true {
      let amount = min(64 * 1024, maximumBytes + 1 - bytes.count)
      guard amount > 0 else { throw DocumentExportError(message: "The PDF exceeds the 32 MiB export limit.") }
      guard let chunk = try handle.read(upToCount: amount), !chunk.isEmpty else { break }
      bytes.append(chunk)
      guard bytes.count <= maximumBytes else { throw DocumentExportError(message: "The PDF exceeds the 32 MiB export limit.") }
    }
    guard matchesExpected(), bytes.count == Int(expected.size) else {
      throw DocumentExportError(message: "The private PDF output changed while reading it.")
    }
    guard let document = PDFDocument(data: bytes), !document.isLocked,
          document.pageCount > 0, document.pageCount <= maximumPages else {
      throw DocumentExportError(message: "The print system did not produce a readable PDF within the 256-page export limit. Nothing was exported; output is never truncated.")
    }
    return bytes
  }
}

/// A phase-aware, one-shot completion gate. Native callbacks after a timeout
/// cannot publish a PDF or complete the Flutter result a second time.
@MainActor
final class DocumentExportLifecycle {
  enum Phase: Equatable { case loading, output, interactive, finished }
  private(set) var phase = Phase.loading
  private var timer: Timer?
  private var completion: ((Result<Bool, Error>) -> Void)?
  private let outputTimeout: TimeInterval
  private let cancelOutput: () -> Void
  var isActive: Bool { completion != nil }

  init(loadingTimeout: TimeInterval = 30, outputTimeout: TimeInterval = 60,
       cancelOutput: @escaping () -> Void, completion: @escaping (Result<Bool, Error>) -> Void) {
    self.outputTimeout = outputTimeout
    self.cancelOutput = cancelOutput
    self.completion = completion
    arm(seconds: loadingTimeout, phase: .loading)
  }

  func beginPrinting(interactive: Bool) {
    guard isActive, phase == .loading else { return }
    timer?.invalidate()
    timer = nil
    phase = interactive ? .interactive : .output
    // User-controlled print panels must never expire while choosing options.
    if !interactive { arm(seconds: outputTimeout, phase: .output) }
  }

  func finish(_ result: Result<Bool, Error>, cancelActiveOutput: Bool = false) {
    guard let callback = completion else { return }
    completion = nil
    phase = .finished
    timer?.invalidate()
    timer = nil
    if cancelActiveOutput { cancelOutput() }
    callback(result)
  }

  private func arm(seconds: TimeInterval, phase expectedPhase: Phase) {
    let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, self.isActive, self.phase == expectedPhase else { return }
        let message = expectedPhase == .loading
          ? "Offline document rendering timed out. No destination was written."
          : "PDF output timed out. Cancellation was requested; no destination was written."
        self.finish(.failure(DocumentExportError(message: message)), cancelActiveOutput: expectedPhase == .output)
      }
    }
    self.timer = timer
    RunLoop.main.add(timer, forMode: .common)
  }
}

/// NSPrintOperation.current is thread-local. Once WebKit prints on its worker
/// thread, keep a main-actor lease until the actual terminal callback, including
/// after timeout. A stale callback must never release a newer operation's lease.
@MainActor
final class DocumentExportPrintLease {
  static let shared = DocumentExportPrintLease()
  private var owner: UUID?

  func acquire(_ token: UUID) -> Bool {
    guard owner == nil else { return false }
    owner = token
    return true
  }

  func release(_ token: UUID) {
    if owner == token { owner = nil }
  }
}

/// One transient, offline rendering job. No scripts, file URL load, browser
/// profile, arbitrary URL navigation, or user-document read is permitted.
@MainActor
final class OfflineDocumentPrintJob: NSObject, WKNavigationDelegate {
  typealias RuleCompiler = (String, @escaping (WKContentRuleList?, Error?) -> Void) -> Void
  typealias PrintOperationFactory = @MainActor (WKWebView, NSPrintInfo) -> NSPrintOperation
  private let loadingTimeout: TimeInterval
  private let outputTimeout: TimeInterval
  private let compileRules: RuleCompiler
  private let makePrintOperation: PrintOperationFactory

  init(loadingTimeout: TimeInterval = 30, outputTimeout: TimeInterval = 60,
       compileRules: RuleCompiler? = nil, makePrintOperation: PrintOperationFactory? = nil) {
    self.loadingTimeout = loadingTimeout
    self.outputTimeout = outputTimeout
    self.compileRules = compileRules ?? { rules, callback in
      WKContentRuleListStore.default().compileContentRuleList(
        forIdentifier: "linefold-offline-export-v1", encodedContentRuleList: rules, completionHandler: callback)
    }
    self.makePrintOperation = makePrintOperation ?? { view, info in view.printOperation(with: info) }
    super.init()
  }

  private weak var window: NSWindow?
  private var webView: WKWebView?
  private var operation: NSPrintOperation?
  private let printLeaseToken = UUID()
  private var lifecycle: DocumentExportLifecycle?
  // AppKit uses a delegate callback. Keep that delegate alive while cancellation
  // unwinds; never destroy an in-flight print context or call private APIs.
  private var retainedUntilPrintReturn: OfflineDocumentPrintJob?
  private var terminalCleanup: (() -> Void)?
  private var pdfDestination: URL?
  private var didBeginPrint = false

  func run(html: String, window: NSWindow, pdfDestination: URL?, terminalCleanup: @escaping () -> Void = {}, completion: @escaping (Result<Bool, Error>) -> Void) {
    guard lifecycle == nil, html.utf8.count <= 32 * 1024 * 1024 else {
      completion(.failure(DocumentExportError(message: "Export is busy or exceeds the size limit.")))
      terminalCleanup()
      return
    }
    self.window = window
    self.pdfDestination = pdfDestination
    self.terminalCleanup = terminalCleanup
    lifecycle = DocumentExportLifecycle(loadingTimeout: loadingTimeout, outputTimeout: outputTimeout, cancelOutput: { [weak self] in
      self?.cancelPrinting()
    }, completion: { [weak self] result in
      guard let self else { completion(result); return }
      self.releaseResources()
      completion(result)
      self.cleanUpIfTerminal()
    })
    let rules = #"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}},{"trigger":{"url-filter":"^data:image/png;base64,"},"action":{"type":"ignore-previous-rules"}},{"trigger":{"url-filter":"^about:blank$"},"action":{"type":"ignore-previous-rules"}}]"#
    compileRules(rules) { [weak self] list, error in
      Task { @MainActor [weak self] in
        guard let self, self.lifecycle?.isActive == true else { return }
        guard let list, error == nil else {
          self.finish(.failure(error ?? DocumentExportError(message: "Offline resource protection could not be installed.")))
          return
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.add(list)
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 660, height: 900), configuration: configuration)
        view.navigationDelegate = self
        self.webView = view
        view.loadHTMLString(html, baseURL: nil)
      }
    }
  }

  /// Completion is immediate and one-shot, but AppKit's output may still be
  /// unwinding. Keep its job, lease and private temporary directory alive until
  /// the real terminal delegate callback, even after cancellation or timeout.
  func cancel() {
    lifecycle?.finish(.success(false), cancelActiveOutput: operation != nil)
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    let url = navigationAction.request.url
    let initial = !didBeginPrint && navigationAction.navigationType == .other &&
      (url == nil || url?.absoluteString == "about:blank")
    decisionHandler(initial ? .allow : .cancel)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard !didBeginPrint, let window, lifecycle?.isActive == true else { return }
    didBeginPrint = true
    lifecycle?.beginPrinting(interactive: pdfDestination == nil)
    guard NSPrintOperation.current == nil else {
      finish(.failure(DocumentExportError(message: "A previous print operation is still stopping. Retry, or restart the app if it does not stop.")))
      return
    }
    // NSPrintOperation's factory changes the current operation on this thread.
    // Reject a held worker lease BEFORE invoking that stateful factory.
    guard DocumentExportPrintLease.shared.acquire(printLeaseToken) else {
      finish(.failure(DocumentExportError(message: "A previous print operation is still stopping. Retry, or restart the app if it does not stop.")))
      return
    }
    let info = NSPrintInfo()
    info.paperSize = NSSize(width: 595.276, height: 841.89)
    info.topMargin = 51.024
    info.bottomMargin = 51.024
    info.leftMargin = 51.024
    info.rightMargin = 51.024
    info.horizontalPagination = .fit
    info.verticalPagination = .automatic
    info.isHorizontallyCentered = false
    info.isVerticallyCentered = false
    if let destination = pdfDestination {
      info.jobDisposition = .save
      info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = destination
    }
    // Unlike WKWebView.createPDF's rectangular snapshot, AppKit's print
    // operation applies paged print CSS and produces actual paper-sized pages.
    let operation = makePrintOperation(webView, info)
    operation.view?.frame = NSRect(origin: .zero, size: info.paperSize)
    operation.showsPrintPanel = pdfDestination == nil
    operation.showsProgressPanel = pdfDestination == nil
    // WebKit configures this true: its secondary-thread path prepares the full
    // paginated PDF, while the main-thread path is asynchronous print preview.
    // Do not force final output down the preview path.
    operation.canSpawnSeparateThread = true
    self.operation = operation
    retainedUntilPrintReturn = self
    operation.runModal(for: window, delegate: self,
      didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
  }

  @objc nonisolated private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
    // AppKit may invoke this delegate on the spawned printing thread. Carry only
    // the result across actors, not its non-Sendable operation/context pointer.
    // The task strongly owns this delegate until terminal cleanup finishes.
    Task { @MainActor [self] in completePrinting(success: success) }
  }

  private func completePrinting(success: Bool) {
    DocumentExportPrintLease.shared.release(printLeaseToken)
    retainedUntilPrintReturn = nil
    self.operation = nil
    defer { releaseResources(); cleanUpIfTerminal() }
    guard lifecycle?.isActive == true else { return }
    // The coordinator synchronously checks file type and byte limits before
    // parsing PDF data. Never let PDFKit read an unbounded output URL here.
    finish(.success(success))
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { finish(.failure(DocumentExportError(message: "Offline rendering stopped unexpectedly."))) }

  private func cancelPrinting() {
    if let operation {
      let session = PMPrintSession(operation.printInfo.pmPrintSession())
      _ = PMSessionSetError(session, OSStatus(kPMCancel))
    }
  }

  private func finish(_ result: Result<Bool, Error>) {
    if case .failure = result {
      lifecycle?.finish(result, cancelActiveOutput: operation != nil)
    } else {
      lifecycle?.finish(result)
    }
  }

  private func cleanUpIfTerminal() {
    guard retainedUntilPrintReturn == nil else { return }
    let cleanup = terminalCleanup
    terminalCleanup = nil
    cleanup?()
  }

  private func releaseResources() {
    // Cancellation is a request, not proof that the worker stopped. Its view,
    // operation and lease remain alive until the actual terminal callback.
    guard retainedUntilPrintReturn == nil else { return }
    webView?.stopLoading()
    webView?.navigationDelegate = nil
    webView = nil
    operation = nil
  }
}

final class DocumentExportScope {
  let url: URL
  private let accessing: Bool
  init(_ url: URL) { self.url = url; accessing = url.startAccessingSecurityScopedResource() }
  deinit { if accessing { url.stopAccessingSecurityScopedResource() } }
}

/// Owns one selection and its scope through final approval. Late callbacks may
/// not write, complete twice, or release a subsequent operation's busy state.
@MainActor
final class PendingDocumentExport {
  let id: String
  private(set) var finished = false
  private(set) var committing = false
  private var selectionHandled = false
  private var awaitingApproval = false
  private(set) var hasHandledRenderResult = false
  var dismissSelection: (() -> Void)?
  var cancelRendering: (() -> Void)?
  var scope: DocumentExportScope?
  private var timer: Timer?
  private let completion: (Result<Bool, Error>) -> Void
  init(id: String, completion: @escaping (Result<Bool, Error>) -> Void) {
    self.id = id; self.completion = completion
  }
  func acceptSelection() -> Bool {
    guard !finished, !selectionHandled else { return false }
    selectionHandled = true
    return true
  }
  func acceptRenderResult() -> Bool {
    guard !finished, !hasHandledRenderResult else { return false }
    hasHandledRenderResult = true
    return true
  }
  func awaitApproval(seconds: TimeInterval) {
    awaitingApproval = true
    let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, self.awaitingApproval else { return }
        self.finish(.failure(DocumentExportError(message: "Export approval timed out. No file was written; export again.")))
      }
    }
    self.timer = timer
    RunLoop.main.add(timer, forMode: .common)
  }
  func acceptApproval() -> Bool {
    guard !finished, awaitingApproval else { return false }
    awaitingApproval = false
    timer?.invalidate(); timer = nil
    return true
  }
  // Final Dart approval is the commit authorization point. Once granted,
  // never report a later cancellation as if it had recalled an in-flight write.
  func beginCommit() { committing = true }
  @discardableResult
  func cancelBeforeCommit() -> Bool {
    guard !finished, !committing else { return false }
    finish(.success(false), dismiss: true)
    return true
  }
  func finish(_ result: Result<Bool, Error>, dismiss: Bool = false) {
    guard !finished else { return }
    finished = true
    awaitingApproval = false
    timer?.invalidate(); timer = nil
    let closePanel = dismissSelection
    dismissSelection = nil
    let cancelRender = cancelRendering
    cancelRendering = nil
    cancelRender?()
    if dismiss { closePanel?() }
    scope = nil
    completion(result)
  }
}

/// SavePanel chooses the destination; PDF renders only to an app-owned temporary
/// file. Dart then approves the same operation against current tab/root state
/// before the existing guarded writer revalidates and commits the final bytes.
@MainActor
final class DocumentExportCoordinator {
  typealias DestinationPicker = @MainActor (NSWindow, String, String, @escaping (URL?) -> Void) -> (() -> Void)
  typealias CommitApproval = @MainActor (String, @escaping (Bool) -> Void) -> Void
  // The renderer calls terminalCleanup only when no native output can still
  // touch the temporary path. Its result can precede that point on cancellation.
  typealias PDFRenderer = @MainActor (String, NSWindow, URL, @escaping () -> Void,
    @escaping (Result<Bool, Error>) -> Void) -> (() -> Void)
  private weak var window: NSWindow?
  private let pickDestination: DestinationPicker
  private let approveCommit: CommitApproval
  private let renderPDF: PDFRenderer
  private let approvalTimeout: TimeInterval
  private var pending: PendingDocumentExport?

  init(window: NSWindow, approvalTimeout: TimeInterval = 5,
       pickDestination: DestinationPicker? = nil, renderPDF: PDFRenderer? = nil,
       approveCommit: @escaping CommitApproval) {
    self.window = window
    self.approvalTimeout = approvalTimeout
    self.approveCommit = approveCommit
    self.renderPDF = renderPDF ?? { html, window, temporary, terminalCleanup, completion in
      let job = OfflineDocumentPrintJob()
      job.run(html: html, window: window, pdfDestination: temporary,
        terminalCleanup: terminalCleanup, completion: completion)
      return { job.cancel() }
    }
    self.pickDestination = pickDestination ?? { window, title, format, selected in
      let panel = NSSavePanel()
      panel.title = format == "md" ? "Export Markdown Copy" : format == "pdf" ? "Export PDF" : "Export HTML"
      panel.allowedContentTypes = format == "html" ? [.html] : format == "pdf" ? [.pdf] :
        [UTType(filenameExtension: "md") ?? UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)]
      panel.allowsOtherFileTypes = false
      panel.canCreateDirectories = true
      let basename = URL(fileURLWithPath: title).deletingPathExtension().lastPathComponent
      panel.nameFieldStringValue = (basename.isEmpty ? "Document" : basename) + "." + format
      // AppKit owns replacement confirmation. Never suppress it, or treat it
      // as permission to overwrite any open source document.
      panel.beginSheetModal(for: window) { response in
        selected(response == .OK ? panel.url : nil)
      }
      return { panel.cancel(nil) }
    }
  }

  func perform(_ action: String, arguments: [String: Any], completion: @escaping (Result<Bool, Error>) -> Void) {
    guard let id = arguments["operationId"] as? String, !id.isEmpty, id.count <= 128 else {
      completion(.failure(DocumentExportError(message: "Missing export operation identity.")))
      return
    }
    if action == "cancel" {
      let cancelled = pending?.id == id ? pending?.cancelBeforeCommit() ?? false : false
      completion(.success(cancelled))
      return
    }
    guard pending == nil, let window, ["html", "markdown", "pdf"].contains(action),
          let content = arguments["content"] as? String, content.utf8.count <= 32 * 1024 * 1024,
          let title = arguments["title"] as? String else {
      completion(.failure(DocumentExportError(message: "Export is unavailable or already in progress.")))
      return
    }
    let request = PendingDocumentExport(id: id) { [weak self] value in
      if self?.pending?.id == id { self?.pending = nil }
      completion(value)
    }
    pending = request
    let format = action == "markdown" ? "md" : action
    let dismiss = pickDestination(window, title, format) { [weak self, weak request] url in
      guard let self, let request, !request.finished, self.pending === request, request.acceptSelection() else { return }
      guard let url else { request.finish(.success(false)); return }
      // Keep the exact authorized URL and metadata across the approval await.
      // Never rebuild a path or reopen the source to authorize an export.
      request.scope = DocumentExportScope(url)
      do {
        let sourcePath = arguments["sourcePath"] as? String
        let protectedPaths = arguments["protectedPaths"] as? [String] ?? []
        // Only chosen-target metadata is inspected before the Dart approval;
        // protected source identities are checked inside the eventual write.
        let expected = try ExportDestinationVersion.read(url)
        if action == "pdf" {
          let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("linefold-pdf-\(UUID().uuidString)", isDirectory: true)
          try FileManager.default.createDirectory(at: temporaryDirectory,
            withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
          let temporary = temporaryDirectory.appendingPathComponent("output.pdf")
          let cancel = self.renderPDF(content, window, temporary, {
            // This closure is owned by the renderer until its actual terminal
            // callback. A logical cancellation must not remove an active output.
            try? FileManager.default.removeItem(at: temporaryDirectory)
          }) { [weak self, weak request] rendered in
            guard let self, let request, !request.finished, self.pending === request,
                  request.acceptRenderResult() else { return }
            request.cancelRendering = nil
            do {
              guard try rendered.get() else { request.finish(.success(false)); return }
              // This must happen inside the renderer callback: its terminal
              // cleanup can remove the private output as soon as we return.
              let bytes = try DocumentExportPDFReader.read(temporary)
              self.requestApproval(request, bytes: bytes, url: url, format: format,
                sourcePath: sourcePath, protectedPaths: protectedPaths, expected: expected)
            } catch { request.finish(.failure(error)) }
          }
          // A test renderer may complete synchronously. Never install a stale
          // cancellation closure after its result has already been handled.
          if !request.finished && !request.hasHandledRenderResult { request.cancelRendering = cancel }
        } else {
          self.requestApproval(request, bytes: Data(content.utf8), url: url, format: format,
            sourcePath: sourcePath, protectedPaths: protectedPaths, expected: expected)
        }
      } catch { request.finish(.failure(error)) }
    }
    if !request.finished { request.dismissSelection = dismiss }
  }

  private func requestApproval(_ request: PendingDocumentExport, bytes: Data,
    url: URL, format: String, sourcePath: String?, protectedPaths: [String],
    expected: ExportDestinationVersion?) {
    request.awaitApproval(seconds: approvalTimeout)
    approveCommit(request.id) { [weak self, weak request] approved in
      guard let self, let request, !request.finished, self.pending === request, request.acceptApproval() else { return }
      guard approved else { request.finish(.success(false)); return }
      request.beginCommit()
      do {
        try DocumentExportFileWriter.write(bytes, to: url, format: format,
          sourcePath: sourcePath, expected: expected, protectedPaths: protectedPaths,
          canCommit: { !request.finished && self.pending === request })
        request.finish(.success(true))
      } catch { request.finish(.failure(error)) }
    }
  }

}
