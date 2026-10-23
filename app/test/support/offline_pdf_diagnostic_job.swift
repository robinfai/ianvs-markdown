// Test-only renderer preserved from the parked PDF/Print WIP (6a571f9).
// Not included in the app target. No user destination, SavePanel or product API.
// Keep worker-thread completion, lease-before-factory and late cleanup intact.
import AppKit
import ApplicationServices
import PDFKit
import WebKit

struct DocumentExportError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
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

