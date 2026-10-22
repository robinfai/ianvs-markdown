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

enum DocumentExportFileWriter {
  static func validate(_ url: URL, format: String, sourcePath: String?, protectedPaths: [String] = []) throws {
    guard url.isFileURL, url.pathExtension.lowercased() == format,
          ["html", "pdf"].contains(format) else {
      throw DocumentExportError(message: "Use a .\(format) filename. Markdown files are never replaced by export.")
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

  static func write(_ bytes: Data, to url: URL, format: String, sourcePath: String?, expected: ExportDestinationVersion?, protectedPaths: [String] = []) throws {
    guard !bytes.isEmpty, bytes.count <= 64 * 1024 * 1024 else {
      throw DocumentExportError(message: "The output is empty or exceeds the export size limit.")
    }
    var coordinationError: NSError?
    var result: Result<Void, Error> = .failure(DocumentExportError(message: "The destination could not be coordinated."))
    NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
      result = Result {
        try validate(url, format: format, sourcePath: sourcePath, protectedPaths: protectedPaths)
        try validate(target, format: format, sourcePath: sourcePath, protectedPaths: protectedPaths)
        guard try ExportDestinationVersion.read(url) == expected,
              try ExportDestinationVersion.read(target) == expected else {
          throw DocumentExportError(message: "The destination changed while exporting. Nothing was replaced; export again.")
        }
        // A newly appeared name must fail rather than silently overwrite.
        try bytes.write(to: target, options: expected == nil ? .withoutOverwriting : .atomic)
      }
    }
    if let coordinationError { throw coordinationError }
    try result.get()
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
          : "PDF output timed out and was cancelled. No destination was written."
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
    defer { cleanUpIfTerminal() }
    guard lifecycle?.isActive == true else { return }
    if success, let destination = pdfDestination {
      guard let document = PDFDocument(url: destination), document.pageCount > 0 else {
        finish(.failure(DocumentExportError(message: "The print system did not produce a readable PDF.")))
        return
      }
    }
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
    webView?.stopLoading()
    webView?.navigationDelegate = nil
    webView = nil
    // A timed-out job cannot commit the user destination. AppKit may still be
    // unwinding; retain its delegate until its late callback, which is ignored.
    if retainedUntilPrintReturn == nil { operation = nil }
  }
}

@MainActor
final class DocumentExportCoordinator {
  private weak var window: NSWindow?
  private var job: OfflineDocumentPrintJob?
  private var busy = false

  init(window: NSWindow) { self.window = window }

  func perform(_ action: String, arguments: [String: Any], completion: @escaping (Result<Bool, Error>) -> Void) {
    guard !busy, let window, ["html", "pdf", "print"].contains(action),
          let html = arguments["html"] as? String, html.utf8.count <= 32 * 1024 * 1024,
          let title = arguments["title"] as? String else {
      completion(.failure(DocumentExportError(message: "Export is unavailable or already in progress.")))
      return
    }
    busy = true
    let complete: (Result<Bool, Error>) -> Void = { [weak self] value in
      self?.job = nil
      self?.busy = false
      completion(value)
    }
    if action == "print" {
      let job = OfflineDocumentPrintJob()
      self.job = job
      job.run(html: html, window: window, pdfDestination: nil, completion: complete)
      return
    }
    let panel = NSSavePanel()
    panel.title = "Export \(action.uppercased())"
    panel.allowedContentTypes = action == "html" ? [.html] : [.pdf]
    panel.allowsOtherFileTypes = false
    panel.canCreateDirectories = true
    let basename = URL(fileURLWithPath: title).deletingPathExtension().lastPathComponent
    panel.nameFieldStringValue = (basename.isEmpty ? "Document" : basename) + "." + action
    // AppKit performs the existing-file replacement confirmation. Never pass
    // an overwrite flag or suppress this native confirmation.
    panel.beginSheetModal(for: window) { [weak self] response in
      guard let self else { return }
      guard response == .OK, let url = panel.url else { complete(.success(false)); return }
      let scoped = url.startAccessingSecurityScopedResource()
      let done: (Result<Bool, Error>) -> Void = { value in
        if scoped { url.stopAccessingSecurityScopedResource() }
        complete(value)
      }
      let sourcePath = arguments["sourcePath"] as? String
      let protectedPaths = arguments["protectedPaths"] as? [String] ?? []
      do {
        try DocumentExportFileWriter.validate(url, format: action, sourcePath: sourcePath, protectedPaths: protectedPaths)
        let expected = try ExportDestinationVersion.read(url)
        if action == "html" {
          try DocumentExportFileWriter.write(Data(html.utf8), to: url, format: action, sourcePath: sourcePath, expected: expected, protectedPaths: protectedPaths)
          done(.success(true))
        } else {
          // No destination write until native printing and PDF parsing succeed.
          let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("linefold-export-\(UUID().uuidString)", isDirectory: true)
          try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
          let output = temporary.appendingPathComponent("document.pdf")
          let job = OfflineDocumentPrintJob()
          self.job = job
          job.run(html: html, window: window, pdfDestination: output, terminalCleanup: {
            try? FileManager.default.removeItem(at: temporary)
          }) { result in
            do {
              guard try result.get() else { done(.success(false)); return }
              let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
              guard let size = attributes[.size] as? NSNumber, size.intValue <= 64 * 1024 * 1024 else {
                throw DocumentExportError(message: "PDF exceeds the export size limit.")
              }
              let bytes = try Data(contentsOf: output)
              try DocumentExportFileWriter.write(bytes, to: url, format: "pdf", sourcePath: sourcePath, expected: expected, protectedPaths: protectedPaths)
              done(.success(true))
            } catch { done(.failure(error)) }
          }
        }
      } catch { done(.failure(error)) }
    }
  }
}
