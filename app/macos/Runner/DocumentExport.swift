import AppKit
import UniformTypeIdentifiers

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
          ["html", "md"].contains(format) else {
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
  var dismissSelection: (() -> Void)?
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
    if dismiss { closePanel?() }
    scope = nil
    completion(result)
  }
}

/// No WebView, JavaScript, PDF or printing API is present in this stage. The
/// native SavePanel chooses a destination; Dart then approves the same operation
/// against current tab/root state before native revalidates and commits it.
@MainActor
final class DocumentExportCoordinator {
  typealias DestinationPicker = @MainActor (NSWindow, String, String, @escaping (URL?) -> Void) -> (() -> Void)
  typealias CommitApproval = @MainActor (String, @escaping (Bool) -> Void) -> Void
  private weak var window: NSWindow?
  private let pickDestination: DestinationPicker
  private let approveCommit: CommitApproval
  private let approvalTimeout: TimeInterval
  private var pending: PendingDocumentExport?

  init(window: NSWindow, approvalTimeout: TimeInterval = 5,
       pickDestination: DestinationPicker? = nil, approveCommit: @escaping CommitApproval) {
    self.window = window
    self.approvalTimeout = approvalTimeout
    self.approveCommit = approveCommit
    self.pickDestination = pickDestination ?? { window, title, format, selected in
      let panel = NSSavePanel()
      panel.title = format == "md" ? "Export Markdown Copy" : "Export HTML"
      panel.allowedContentTypes = format == "html" ? [.html] :
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
    guard pending == nil, let window, ["html", "markdown"].contains(action),
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
    let format = action == "markdown" ? "md" : "html"
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
        request.awaitApproval(seconds: self.approvalTimeout)
        self.approveCommit(id) { [weak self, weak request] approved in
          guard let self, let request, !request.finished, self.pending === request, request.acceptApproval() else { return }
          guard approved else { request.finish(.success(false)); return }
          request.beginCommit()
          do {
            try DocumentExportFileWriter.write(Data(content.utf8), to: url, format: format,
              sourcePath: sourcePath, expected: expected, protectedPaths: protectedPaths,
              canCommit: { !request.finished && self.pending === request })
            request.finish(.success(true))
          } catch { request.finish(.failure(error)) }
        }
      } catch { request.finish(.failure(error)) }
    }
    if !request.finished { request.dismissSelection = dismiss }
  }
}
