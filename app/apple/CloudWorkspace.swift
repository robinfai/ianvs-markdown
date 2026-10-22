import Foundation
import Darwin
import CoreFoundation
import ImageIO
import CoreGraphics
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif
#if os(iOS)
import Flutter
#else
import FlutterMacOS
#endif

/// Both applications use this exact ubiquity container, never a guessed path in
/// Mobile Documents. All coordination and container lookup runs off the UI thread.
final class CloudWorkspace {
  static let shared = CloudWorkspace()
  static let identifier = "iCloud.work.ianvs.linefold"
  static let extensions: Set<String> = ["md", "markdown", "mdown", "mkd", "txt"]
  private let queue = DispatchQueue(label: "work.ianvs.linefold.workspace", qos: .userInitiated)
  private let attachmentQueue = DispatchQueue(label: "work.ianvs.linefold.attachments", qos: .userInitiated)
  private let noteWriteQueue = DispatchQueue(label: "work.ianvs.linefold.note-create", qos: .userInitiated)
  private let readScheduler = WorkspaceReadScheduler()
  private let transactionQueue = DispatchQueue(label: "work.ianvs.linefold.note-move", qos: .userInitiated)
  private let searchQueue = DispatchQueue(label: "work.ianvs.linefold.search", qos: .utility)
  private var channel: FlutterMethodChannel?
  private var query: NSMetadataQuery?
  private var observers: [NSObjectProtocol] = []
  private var monitoredRoot: URL?

  func defaultDirectory() throws -> URL {
    if Bundle.main.object(forInfoDictionaryKey: "LinefoldCloudEnabled") as? String == "NO" {
      throw WorkspaceError.notConfigured
    }
    guard let container = FileManager.default.url(forUbiquityContainerIdentifier: Self.identifier) else {
      throw WorkspaceError.unavailable
    }
    let documents = container.appendingPathComponent("Documents", isDirectory: true)
    try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
    DispatchQueue.main.async { self.monitor(documents) }
    return documents
  }

  func attach(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "work.ianvs.linefold/workspace", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      let arguments = call.arguments as? [String: Any] ?? [:]
      let method = call.method
      if WorkspaceNoteTransaction.methods.contains(method) {
        self.transactionQueue.async {
          let value = WorkspaceNoteTransaction.shared.perform(method, arguments: arguments)
          DispatchQueue.main.async { result(value) }
        }
        return
      }
      #if os(macOS)
      // No clipboard observation/polling. These two entry points are called only
      // from the editor's explicit Insert Image and Paste actions.
      if method == "pickAttachmentImage" {
        self.pickAttachmentImage(result: result)
        return
      }
      if method == "readClipboardAttachmentImage" {
        self.readClipboardAttachmentImage(result: result)
        return
      }
      #endif
      guard ["defaultDirectory", "listDirectory", "readDocument", "readDocumentBytes", "writeDocument", "writeDocumentGuarded",
             "listAttachments", "readAttachmentBytes", "readAttachmentImportSettings", "normalizeAttachmentPaths", "createWorkspaceAttachment",
             "listWorkspaceDirectory", "readWorkspaceTextBytes", "createWorkspaceNote", "resolveWorkspacePath", "readDocumentSyncMetadata"].contains(method) else {
        result(FlutterMethodNotImplemented)
        return
      }
      if let readKind = WorkspaceReadScheduler.Kind(method: method) {
        // The channel handler runs on the platform/main thread. Snapshot only
        // immutable request values here; readers never consult container,
        // security-scope or monitor state on their independent worker queues.
        guard let path = arguments["path"] as? String, path.hasPrefix("/") else {
          result(FlutterError(code: "workspace_unavailable", message: WorkspaceError.invalidPath.localizedDescription, details: nil))
          return
        }
        let recursive = arguments["recursive"] as? Bool ?? false
        let maximumBytes = arguments["maximumBytes"] as? Int
        self.readScheduler.execute(kind: readKind, operation: { () throws -> Any in
          // URL(fileURLWithPath:) may query the filesystem to infer whether the
          // path is a directory. Construct it only after worker admission, not
          // on main and not for rejected requests.
          let url = URL(fileURLWithPath: path)
          switch readKind {
          case .directory:
            return try Self.list(url, recursive: recursive)
          case .metadata:
            return try Self.readSyncMetadata(url)
          case .body:
            let contents = try Self.read(url, maximumBytes: maximumBytes)
            if method == "readDocumentBytes" {
              return FlutterStandardTypedData(bytes: Data(contents.utf8))
            }
            return contents
          }
        }, completion: { outcome in
          // The scheduler completes every admitted/rejected request once on
          // main. Dart may already have discarded a timed-out or stale result.
          switch outcome {
          case .success(let value):
            result(value)
          case .failure(let error):
            if error as? WorkspaceReadQueueError == .busy {
              result(FlutterError(code: "workspace_busy", message: "Workspace reads are busy. Retry after an earlier read finishes.", details: ["retryable": true]))
            } else {
              result(FlutterError(code: "workspace_unavailable", message: error.localizedDescription, details: nil))
            }
          }
        })
        return
      }
      let isSearch = method == "listWorkspaceDirectory" || method == "readWorkspaceTextBytes" || method == "createWorkspaceNote" || method == "resolveWorkspacePath"
      let isAttachment = method == "listAttachments" || method == "readAttachmentBytes" || method == "readAttachmentImportSettings" || method == "createWorkspaceAttachment"
      let workQueue = method == "createWorkspaceNote" ? self.noteWriteQueue : (isSearch ? self.searchQueue : (isAttachment ? self.attachmentQueue : self.queue))
      workQueue.async {
        do {
          let value: Any
          if method == "normalizeAttachmentPaths" {
            value = try Self.normalizeAttachmentPaths(arguments["values"])
          } else if method == "defaultDirectory" {
            value = try self.defaultDirectory().path
          } else {
            guard let path = arguments["path"] as? String, path.hasPrefix("/") else {
              if isAttachment || isSearch {
                throw AttachmentError.invalid
              }
              throw WorkspaceError.invalidPath
            }
            if (isAttachment || isSearch) && path.contains("\0") {
              throw AttachmentError.invalid
            }
            let url = URL(fileURLWithPath: path)
            switch method {
            case "resolveWorkspacePath":
              guard let relativePath = arguments["relativePath"] as? String else { throw AttachmentError.invalid }
              value = try Self.resolveWorkspacePath(url, relativePath: relativePath)
            case "createWorkspaceNote":
              guard let relativePath = arguments["relativePath"] as? String else { throw AttachmentError.invalid }
              try Self.createWorkspaceNote(url, relativePath: relativePath)
              value = true
            case "listWorkspaceDirectory":
              guard let relativePath = arguments["relativePath"] as? String else { throw AttachmentError.invalid }
              value = try Self.listWorkspaceDirectory(url, relativePath: relativePath)
            case "readWorkspaceTextBytes":
              guard let relativePath = arguments["relativePath"] as? String,
                    let number = arguments["maximumBytes"] as? NSNumber,
                    CFGetTypeID(number) != CFBooleanGetTypeID(),
                    let maximumBytes = arguments["maximumBytes"] as? Int else {
                throw AttachmentError.invalid
              }
              let contents = try Self.readWorkspaceTextBytes(url, relativePath: relativePath, maximumBytes: maximumBytes)
              value = ["bytes": FlutterStandardTypedData(bytes: contents.bytes), "revision": contents.revision]
            case "createWorkspaceAttachment":
              guard let directory = arguments["relativeDirectory"] as? String,
                    let filename = arguments["filename"] as? String,
                    let bytes = arguments["bytes"] as? FlutterStandardTypedData,
                    bytes.elementSize == 1 else { throw AttachmentError.invalid }
              value = ["relativePath": try Self.createWorkspaceAttachment(
                url, relativeDirectory: directory, filename: filename, bytes: bytes.data
              )]
            case "readAttachmentImportSettings":
              value = FlutterStandardTypedData(bytes: try Self.readAttachmentImportSettings(url))
            case "listAttachments":
              value = try Self.listAttachments(url)
            case "readAttachmentBytes":
              guard let relativePath = arguments["relativePath"] as? String,
                    let number = arguments["maximumBytes"] as? NSNumber,
                    CFGetTypeID(number) != CFBooleanGetTypeID(),
                    let maximumBytes = arguments["maximumBytes"] as? Int else {
                throw AttachmentError.invalid
              }
              value = FlutterStandardTypedData(bytes: try Self.readAttachmentBytes(
                url, relativePath: relativePath, maximumBytes: maximumBytes
              ))
            case "writeDocumentGuarded":
              try Self.writeGuarded(url, arguments: arguments)
              value = true
            default:
              guard let contents = arguments["contents"] as? String else { throw WorkspaceError.invalidPath }
              try Self.write(url, contents: contents)
              value = true
            }
          }
          DispatchQueue.main.async { result(value) }
        } catch let error as AttachmentImportWriteFailure {
          DispatchQueue.main.async {
            result(FlutterError(code: error.failure.code, message: error.localizedDescription,
                                details: ["relativePath": error.relativePath, "fileMayRemain": true]))
          }
        } catch let error as AttachmentError {
          DispatchQueue.main.async {
            result(FlutterError(code: error.code, message: error.localizedDescription, details: nil))
          }
        } catch let conflict as WorkspaceSaveConflict {
          DispatchQueue.main.async {
            result(FlutterError(
              code: "workspace_save_conflict",
              message: conflict.localizedDescription,
              details: [
                "path": conflict.path,
                "currentContentsBytes": conflict.currentContents.map {
                  FlutterStandardTypedData(bytes: Data($0.utf8)) as Any
                } ?? NSNull(),
              ]
            ))
          }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "workspace_unavailable", message: error.localizedDescription, details: nil))
          }
        }
      }
    }
  }

  private func monitor(_ root: URL) {
    guard monitoredRoot != root else { return }
    query?.stop()
    observers.forEach { NotificationCenter.default.removeObserver($0) }
    observers.removeAll()
    monitoredRoot = root
    let query = NSMetadataQuery()
    query.notificationBatchingInterval = 0.5
    query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
    query.predicate = NSPredicate(format: "%K BEGINSWITH %@", NSMetadataItemPathKey, root.path + "/")
    for name in [NSNotification.Name.NSMetadataQueryDidFinishGathering, NSNotification.Name.NSMetadataQueryDidUpdate] {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
        self?.channel?.invokeMethod("workspaceChanged", arguments: nil)
      })
    }
    self.query = query
    query.start()
  }

  /// Read only the requested document's resource metadata. Do not coordinate a
  /// content read, call startDownloadingUbiquitousItem, list a directory, request
  /// nonlocal versions, or establish a new container/security scope here.
  /// isUploaded describes an OS observation, not completion of our local write.
  static func readSyncMetadata(_ source: URL) throws -> [String: Any] {
    guard source.isFileURL, !source.path.contains("\0"),
          extensions.contains(source.pathExtension.lowercased()) else {
      throw WorkspaceError.invalidPath
    }
    var url = source
    url.removeAllCachedResourceValues()
    let keys: Set<URLResourceKey> = [
      .isSymbolicLinkKey, .isDirectoryKey, .isUbiquitousItemKey,
      .ubiquitousItemIsUploadedKey, .ubiquitousItemIsUploadingKey,
      .ubiquitousItemIsDownloadingKey, .ubiquitousItemDownloadingStatusKey,
      .ubiquitousItemUploadingErrorKey, .ubiquitousItemDownloadingErrorKey,
      .ubiquitousItemHasUnresolvedConflictsKey,
    ]
    let values = try url.resourceValues(forKeys: keys)
    guard values.isSymbolicLink != true, values.isDirectory != true else {
      throw WorkspaceError.invalidPath
    }
    var observation = WorkspaceSyncObservation(
      isUbiquitous: values.isUbiquitousItem,
      isUploaded: values.ubiquitousItemIsUploaded,
      isUploading: values.ubiquitousItemIsUploading,
      isDownloading: values.ubiquitousItemIsDownloading,
      downloadingStatus: values.ubiquitousItemDownloadingStatus,
      uploadError: values.ubiquitousItemUploadingError?.localizedDescription,
      downloadError: values.ubiquitousItemDownloadingError?.localizedDescription,
      hasUnresolvedConflicts: values.ubiquitousItemHasUnresolvedConflicts
    )
    if values.isUbiquitousItem == true && values.ubiquitousItemHasUnresolvedConflicts == true,
       let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) {
      observation.conflictsAvailable = true
      observation.conflicts = versions.prefix(50).map { version in
        var record: [String: Any] = ["name": version.localizedName ?? "Conflicting version"]
        if let modified = version.modificationDate {
          record["modified"] = modified.timeIntervalSince1970 * 1000
        }
        return record
      }
    }
    return observation.dictionary(observedAt: Date())
  }

  static func list(_ root: URL, recursive: Bool) throws -> [[String: Any]] {
    let manager = FileManager.default
    let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]
    var result: [[String: Any]] = []
    func visit(_ directory: URL) throws {
      for item in try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) {
        let values = try item.resourceValues(forKeys: keys)
        if values.isSymbolicLink == true { continue }
        var url = item
        let name = item.lastPathComponent
        // iCloud's not-yet-downloaded files are represented by hidden stubs.
        if name.hasPrefix("."), name.hasSuffix(".icloud") {
          url = item.deletingLastPathComponent().appendingPathComponent(String(name.dropFirst().dropLast(7)))
        } else if name.hasPrefix(".") { continue }
        let directory = values.isDirectory == true
        if !directory && values.isRegularFile != true { continue }
        if directory && recursive { try visit(item); continue }
        if !directory && !extensions.contains(url.pathExtension.lowercased()) { continue }
        result.append([
          "path": url.path, "name": url.lastPathComponent, "isDirectory": directory,
          "modified": (values.contentModificationDate ?? .distantPast).timeIntervalSince1970 * 1000,
        ])
      }
    }
    try visit(root)
    return result
  }

  static func read(_ url: URL, maximumBytes: Int? = nil) throws -> String {
    if (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true {
      try FileManager.default.startDownloadingUbiquitousItem(at: url)
    }
    var coordinationError: NSError?
    var outcome: Result<String, Error> = .failure(WorkspaceError.unavailable)
    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinated in
      outcome = Result {
        let values = try coordinated.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { throw WorkspaceError.invalidPath }
        let handle = try FileHandle(forReadingFrom: coordinated)
        defer { try? handle.close() }
        let data: Data
        if let maximumBytes {
          data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
          guard data.count <= maximumBytes else { throw WorkspaceError.tooLarge }
        } else {
          data = try handle.readToEnd() ?? Data()
        }
        return try decodeText(data)
      }
    }
    if let coordinationError { throw coordinationError }
    return try outcome.get()
  }

  static func write(_ url: URL, contents: String) throws {
    try coordinatedWrite(url, contents: contents)
  }

  /// Source travels as bytes because StandardMethodCodec's Dart String decoder
  /// strips a leading BOM. Missing/malformed baselines must never grant a write.
  static func writeGuarded(_ url: URL, arguments: [String: Any]) throws {
    guard let contentsBytes = arguments["contentsBytes"],
          let expectedBytes = arguments["expectedContentsBytes"] else { throw WorkspaceError.invalidPath }
    let contents = try decodeChannelBytes(contentsBytes)
    let expectedContents: String?
    if expectedBytes is NSNull { expectedContents = nil }
    else { expectedContents = try decodeChannelBytes(expectedBytes) }
    try writeGuarded(url, contents: contents, expectedContents: expectedContents)
  }

  /// Compares and replaces inside one file-coordinator claim. The caller may
  /// approve only the exact observed version, never a blanket "overwrite" flag.
  static func writeGuarded(_ url: URL, contents: String, expectedContents: String?) throws {
    // Coordination may provide a different URL. Check the requested leaf as
    // well, without following links or reusing cached URL resource metadata.
    try rejectSymbolicLink(url)
    if (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true {
      try FileManager.default.startDownloadingUbiquitousItem(at: url)
    }
    // A modification claim needs the old bytes, unlike a replacement-only
    // claim, so iCloud can materialize the existing document for validation.
    try coordinatedWrite(url, contents: contents, options: []) { coordinated in
      try rejectSymbolicLink(url)
      let current = try currentContents(coordinated)
      // Swift String equality normalizes Unicode. Compare UTF-8 instead: source
      // edits, including normalization, BOM and line endings, are significant.
      guard current.map({ Data($0.utf8) }) == expectedContents.map({ Data($0.utf8) }) else {
        throw WorkspaceSaveConflict(
          path: url.path, expectedContents: expectedContents, currentContents: current
        )
      }
    }
  }

  private static func coordinatedWrite(
    _ url: URL, contents: String, options: NSFileCoordinator.WritingOptions = .forReplacing,
    validate: ((URL) throws -> Void)? = nil
  ) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var coordinationError: NSError?
    // Follow the coordinator's failure-sentinel contract: success must come
    // from a completed accessor, never merely from an empty NSError slot.
    var outcome: Result<Void, Error> = .failure(WorkspaceError.unavailable)
    NSFileCoordinator().coordinate(writingItemAt: url, options: options, error: &coordinationError) { coordinated in
      outcome = Result {
        try validate?(coordinated)
        try Data(contents.utf8).write(to: coordinated, options: .atomic)
      }
    }
    if let coordinationError { throw coordinationError }
    try outcome.get()
  }

  private static func rejectSymbolicLink(_ url: URL) throws {
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else { throw WorkspaceError.invalidPath }
    } catch let error as NSError {
      // A missing logical iCloud URL may materialize during coordination; do
      // not require it to exist here. Other metadata failures must fail closed.
      guard error.domain == NSCocoaErrorDomain,
            error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError else { throw error }
    }
  }

  private static func currentContents(_ url: URL) throws -> String? {
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      guard attributes[.type] as? FileAttributeType == .typeRegular else { throw WorkspaceError.invalidPath }
      return try decodeText(Data(contentsOf: url))
    } catch let error as NSError {
      // fileExists can turn access errors into false. Only a real missing-file
      // error means deletion; unreadable and invalid UTF-8 destinations fail.
      guard error.domain == NSCocoaErrorDomain,
            error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError else { throw error }
      // A dangling symlink is not an absent destination that may be replaced.
      if (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil {
        throw WorkspaceError.invalidPath
      }
      // An evicted iCloud document is not a deletion. If its bytes still are not
      // available, refuse to grant an absent-file baseline and let the user
      // retry after download rather than overwrite an unseen remote version.
      let placeholder = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
      do {
        _ = try FileManager.default.attributesOfItem(atPath: placeholder.path)
      } catch let placeholderError as NSError {
        guard placeholderError.domain == NSCocoaErrorDomain,
              placeholderError.code == NSFileReadNoSuchFileError || placeholderError.code == NSFileNoSuchFileError else {
          throw placeholderError
        }
        return nil
      }
      throw WorkspaceError.unavailable
    }
  }

  private static func decodeText(_ data: Data) throws -> String {
    guard String(data: data, encoding: .utf8) != nil, !data.contains(0) else { throw WorkspaceError.invalidText }
    // Decode the validated bytes without NSString's BOM handling so that a BOM
    // remains part of the exact source and the next save preserves it.
    return String(decoding: data, as: UTF8.self)
  }

  private static func decodeChannelBytes(_ value: Any) throws -> String {
    // UInt8 is the codec's only one-byte element type. Reject lists, strings,
    // and other typed buffers instead of reinterpreting malformed arguments.
    guard let typed = value as? FlutterStandardTypedData, typed.elementSize == 1 else {
      throw WorkspaceError.invalidText
    }
    return try decodeText(typed.data)
  }
}

struct WorkspaceSaveConflict: LocalizedError {
  let path: String
  let expectedContents: String?
  let currentContents: String?
  var errorDescription: String? { "The file changed on disk: \(path)" }
}

enum WorkspaceError: LocalizedError {
  case unavailable, notConfigured, invalidPath, tooLarge, invalidText
  var errorDescription: String? {
    switch self {
    case .unavailable: return "iCloud Drive 暂不可用，请检查 Apple 账户和 iCloud Drive 设置，或手动选择文件夹。"
    case .notConfigured: return "iCloud 自动同步尚未启用。仍可手动打开 iCloud Drive 文件夹。"
    case .invalidPath: return "文件或文件夹不可用，请重新选择。"
    case .tooLarge: return "文档超过 5 MB，暂时无法预览。"
    case .invalidText: return "无法读取文档，请使用 UTF-8 编码的 Markdown 文件。"
    }
  }
}

// Automatic attachment and search IO never reuse the downloading document
// reader. The explicit root is the authority, not a concatenated absolute file
// URL; every descendant is opened relative to a pinned descriptor without links.
extension CloudWorkspace {
  static func resolveWorkspacePath(_ root: URL, relativePath: String) throws -> [String: String] {
    do {
      return try WorkspaceFileScope.withoutMaterialization {
        try WorkspaceTextScope(root).resolvePath(relativePath: relativePath)
      }
    } catch { throw AttachmentError.classify(error) }
  }

  static func createWorkspaceNote(_ root: URL, relativePath: String) throws {
    do {
      try WorkspaceFileScope.withoutMaterialization {
        let scope = try WorkspaceTextScope(root)
        _ = try WorkspaceTextScope.textComponents(relativePath, directory: false)
        let target = scope.rootURL.appendingPathComponent(relativePath)
        var coordinationError: NSError?
        var outcome: Result<Void, Error> = .failure(AttachmentError.unavailable)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        let deadline = DispatchTime.now() + WorkspaceTextScope.coordinationTimeout
        let timeout = DispatchWorkItem { coordinator.cancel() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: deadline, execute: timeout)
        defer { timeout.cancel() }
        coordinator.coordinate(writingItemAt: target, options: [], error: &coordinationError) { coordinated in
          outcome = Result {
            guard DispatchTime.now().uptimeNanoseconds < deadline.uptimeNanoseconds,
                  coordinated.standardizedFileURL.path == target.standardizedFileURL.path else {
              throw AttachmentError.unavailable
            }
            try scope.createNote(relativePath: relativePath)
          }
        }
        if let error = coordinationError { throw error }
        try outcome.get()
      }
    } catch { throw AttachmentError.classify(error) }
  }

  static func listWorkspaceDirectory(_ root: URL, relativePath: String) throws -> [String: Any] {
    do {
      return try WorkspaceFileScope.withoutMaterialization {
        try WorkspaceTextScope(root).listDirectory(relativePath: relativePath)
      }
    } catch { throw AttachmentError.classify(error) }
  }

  static func readWorkspaceTextBytes(
    _ root: URL, relativePath: String, maximumBytes: Int = WorkspaceTextScope.maximumTextBytes
  ) throws -> WorkspaceTextBytes {
    do {
      return try WorkspaceFileScope.withoutMaterialization {
        try WorkspaceTextScope(root).readText(relativePath: relativePath, maximumBytes: maximumBytes)
      }
    } catch { throw AttachmentError.classify(error) }
  }

  static func normalizeAttachmentPaths(_ value: Any?) throws -> [String] {
    guard let paths = value as? [String], paths.count <= 32,
          paths.allSatisfy({ $0.utf16.count <= 4096 }) else { throw AttachmentError.invalid }
    return paths.map { $0.precomposedStringWithCanonicalMapping.lowercased() }
  }

  static func listAttachments(_ root: URL) throws -> [[String: Any]] {
    do { return try AttachmentScope.withoutMaterialization { try AttachmentScope(root).list() } }
    catch { throw AttachmentError.classify(error) }
  }

  /// Import destination policy may inspect only already-local Obsidian config.
  /// Deliberately bypass AttachmentScope.read: preview can request a download,
  /// whereas imports must not coordinate with or materialize provider content.
  static func readAttachmentImportSettings(
    _ root: URL, beforeLocalRead: (() throws -> Void)? = nil, afterLocalRead: (() throws -> Void)? = nil
  ) throws -> Data {
    do {
      return try WorkspaceFileScope.withoutMaterialization {
        try AttachmentImportSettingsScope(root).read(beforeLocalRead: beforeLocalRead, afterLocalRead: afterLocalRead)
      }
    } catch is AttachmentImportSettingsAbsence {
      // This is the only state that permits Dart to default to the vault root.
      throw AttachmentError.missing
    } catch {
      let failure = AttachmentError.classify(error)
      // A disappeared root/observed parent/observed leaf is not an absent config.
      throw failure == .missing ? AttachmentError.unavailable : failure
    }
  }

  static func readAttachmentBytes(_ root: URL, relativePath: String, maximumBytes: Int) throws -> Data {
    do {
      return try AttachmentScope.withoutMaterialization {
        try AttachmentScope(root).read(relativePath: relativePath, maximumBytes: maximumBytes)
      }
    }
    catch { throw AttachmentError.classify(error) }
  }
}

enum AttachmentError: LocalizedError, Equatable {
  case missing, offline, denied, invalid, tooLarge, indexLimit, unavailable, collision, unsupported

  var code: String {
    switch self {
    case .missing: return "attachment_missing"
    case .offline: return "attachment_offline"
    case .denied: return "attachment_denied"
    case .invalid: return "attachment_invalid"
    case .tooLarge: return "attachment_too_large"
    case .indexLimit: return "attachment_index_limit"
    case .unavailable: return "attachment_unavailable"
    case .collision: return "attachment_collision"
    case .unsupported: return "attachment_unsupported"
    }
  }

  var errorDescription: String? {
    switch self {
    case .missing: return "The attachment is missing."
    case .offline: return "The attachment is not available locally. Download it in iCloud Drive and retry."
    case .denied: return "Permission to access the attachment was denied."
    case .invalid: return "The attachment path or file type is not allowed."
    case .tooLarge: return "The attachment exceeds the permitted size."
    case .indexLimit: return "The vault exceeds attachment indexing limits. No partial index was returned."
    case .unavailable: return "The attachment operation could not be completed. Please retry."
    case .collision: return "An attachment already uses that name. Nothing was overwritten."
    case .unsupported: return "This image format is not supported."
    }
  }

  static func posix(_ code: Int32 = errno) -> AttachmentError {
    switch code {
    case ENOENT: return .missing
    case EACCES, EPERM, EROFS: return .denied
    case ELOOP, ENOTDIR, EINVAL, ENAMETOOLONG: return .invalid
    case EFBIG: return .tooLarge
    case ENETDOWN, ENETUNREACH, EHOSTUNREACH, ETIMEDOUT, ENXIO, EDEADLK: return .offline
    default: return .unavailable
    }
  }

  static func classify(_ error: Error, placeholder: Bool = false) -> AttachmentError {
    if let error = error as? AttachmentError {
      return placeholder && error == .missing ? .offline : error
    }
    let error = error as NSError
    if error.domain == NSPOSIXErrorDomain {
      let mapped = posix(Int32(error.code))
      return placeholder && mapped == .missing ? .offline : mapped
    }
    if error.domain == NSCocoaErrorDomain {
      switch error.code {
      case NSFileReadNoPermissionError, NSFileWriteNoPermissionError: return .denied
      case NSFileReadNoSuchFileError, NSFileNoSuchFileError: return placeholder ? .offline : .missing
      // Foundation's ubiquitous-file-unavailable / ubiquity-server-unavailable.
      case 4353, 4355: return .offline
      default: break
      }
    }
    if error.domain == NSURLErrorDomain,
       [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
        NSURLErrorCannotConnectToHost, NSURLErrorTimedOut].contains(error.code) { return .offline }
    if let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error {
      return classify(underlying, placeholder: placeholder)
    }
    return .unavailable
  }
}

struct WorkspaceTextBytes {
  let bytes: Data
  let revision: String
}

/// Shared descriptor authority, not a document/image policy. Only the selected
/// root is opened by absolute path; descendants always use no-follow openat.
class WorkspaceFileScope {
  static let maximumPathDepth = 64
  static let readTimeout: TimeInterval = 5

  /// Apple TN3150: do not implicitly fetch dataless files, even when eviction
  /// races a prior metadata check. Restore the worker thread's original policy.
  static func withoutMaterialization<T>(_ body: () throws -> T) throws -> T {
    let policy = getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
    guard policy >= 0 else { throw AttachmentError.unavailable }
    guard setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD,
                        IOPOL_MATERIALIZE_DATALESS_FILES_OFF) == 0 else { throw AttachmentError.unavailable }
    defer { _ = setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD, policy) }
    return try body()
  }
  let rootURL: URL
  fileprivate let rootDescriptor: Int32
  private let identity: stat

  init(_ root: URL) throws {
    guard root.isFileURL, root.path.hasPrefix("/"), !root.path.contains("\0") else {
      throw AttachmentError.invalid
    }
    // Ancestors can contain platform aliases such as /var -> /private/var.
    // The selected root itself, and every descendant, must not be a symlink.
    let descriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else { throw AttachmentError.posix() }
    var attributes = stat()
    guard fstat(descriptor, &attributes) == 0 else {
      let error = AttachmentError.posix()
      close(descriptor)
      throw error
    }
    var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    let status = path.withUnsafeMutableBufferPointer { fcntl(descriptor, F_GETPATH, $0.baseAddress!) }
    guard status == 0 else {
      let error = AttachmentError.posix()
      close(descriptor)
      throw error
    }
    rootDescriptor = descriptor
    identity = attributes
    rootURL = URL(fileURLWithPath: String(cString: path), isDirectory: true)
  }

  deinit { close(rootDescriptor) }

  static func relativeComponents(_ path: String) throws -> [String] {
    guard !path.isEmpty, path.utf16.count <= 4096, !path.hasPrefix("/"),
          !path.contains("\\"), !path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }), !path.contains(":") else {
      throw AttachmentError.invalid
    }
    let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard components.count <= maximumPathDepth + 1,
          components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
      throw AttachmentError.invalid
    }
    return components
  }

  func parentDescriptor(_ components: [String]) throws -> Int32 {
    guard try Self.relativeComponents(components.joined(separator: "/")) == components else {
      throw AttachmentError.invalid
    }
    return try directoryDescriptor(Array(components.dropLast()))
  }

  func directoryDescriptor(_ components: [String]) throws -> Int32 {
    guard components.count <= Self.maximumPathDepth else { throw AttachmentError.invalid }
    if !components.isEmpty {
      guard try Self.relativeComponents(components.joined(separator: "/")) == components else {
        throw AttachmentError.invalid
      }
    }
    var current = dup(rootDescriptor)
    guard current >= 0 else { throw AttachmentError.posix() }
    for name in components {
      let next = openat(current, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      let failure = errno
      close(current)
      guard next >= 0 else { throw AttachmentError.posix(failure) }
      current = next
    }
    return current
  }

  func verifyRootLocation() throws {
    let descriptor = open(rootURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else { throw AttachmentError.posix() }
    defer { close(descriptor) }
    var current = stat()
    guard fstat(descriptor, &current) == 0 else { throw AttachmentError.posix() }
    guard current.st_dev == identity.st_dev, current.st_ino == identity.st_ino else {
      throw AttachmentError.invalid
    }
  }

  func isPlaceholder(_ components: [String]) throws -> Bool {
    let parent = try parentDescriptor(components)
    defer { close(parent) }
    let name = components.last!
    var attributes = stat()
    if fstatat(parent, name, &attributes, AT_SYMLINK_NOFOLLOW) == 0 {
      guard attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw AttachmentError.invalid }
      return attributes.st_flags & UInt32(SF_DATALESS) != 0
    }
    guard errno == ENOENT else { throw AttachmentError.posix() }
    guard fstatat(parent, ".\(name).icloud", &attributes, AT_SYMLINK_NOFOLLOW) == 0 else {
      throw AttachmentError.posix()
    }
    guard attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw AttachmentError.invalid }
    return true
  }

  static func revision(_ attributes: stat) -> String {
    "\(attributes.st_dev):\(attributes.st_ino):\(attributes.st_size):" +
      "\(attributes.st_mtimespec.tv_sec):\(attributes.st_mtimespec.tv_nsec):" +
      "\(attributes.st_ctimespec.tv_sec):\(attributes.st_ctimespec.tv_nsec)"
  }

  /// Both consumers use this descriptor-only byte reader. The image policy can
  /// request materialization before it gets here; search must never do so.
  func readLocalBytes(components: [String], maximumBytes: Int, verifyRevision: Bool) throws -> WorkspaceTextBytes {
    guard maximumBytes > 0, !components.isEmpty else { throw AttachmentError.invalid }
    try verifyRootLocation()
    let parent = try parentDescriptor(components)
    defer { close(parent) }
    let descriptor = openat(parent, components.last!, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    guard descriptor >= 0 else { throw AttachmentError.posix() }
    defer { close(descriptor) }
    var attributes = stat()
    guard fstat(descriptor, &attributes) == 0 else { throw AttachmentError.posix() }
    guard attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw AttachmentError.invalid }
    guard attributes.st_flags & UInt32(SF_DATALESS) == 0 else { throw AttachmentError.offline }
    guard attributes.st_size >= 0, attributes.st_size <= Int64(maximumBytes) else { throw AttachmentError.tooLarge }
    let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(Self.readTimeout * 1_000_000_000)
    var bytes = Data()
    var chunk = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
      guard DispatchTime.now().uptimeNanoseconds < deadline else { throw AttachmentError.unavailable }
      let requested = min(chunk.count, maximumBytes - bytes.count + 1)
      let count = chunk.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress!, requested) }
      if count < 0 {
        if errno == EINTR { continue }
        throw AttachmentError.posix()
      }
      if count == 0 { break }
      guard bytes.count + count <= maximumBytes else { throw AttachmentError.tooLarge }
      bytes.append(contentsOf: chunk.prefix(count))
    }
    if verifyRevision {
      try verifyReadRevision(descriptor: descriptor, components: components, original: attributes, byteCount: bytes.count)
    }
    return WorkspaceTextBytes(bytes: bytes, revision: Self.revision(attributes))
  }

  /// Check the opened file AND a fresh walk from the pinned root. fstat alone
  /// would miss an atomic replacement of the leaf or one of its parents.
  func verifyReadRevision(descriptor: Int32, components: [String], original: stat, byteCount: Int) throws {
    try verifyRootLocation()
    var after = stat()
    guard fstat(descriptor, &after) == 0 else { throw AttachmentError.posix() }
    let parent = try parentDescriptor(components)
    defer { close(parent) }
    var current = stat()
    guard fstatat(parent, components.last!, &current, AT_SYMLINK_NOFOLLOW) == 0 else { throw AttachmentError.posix() }
    guard current.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw AttachmentError.invalid }
    guard after.st_flags & UInt32(SF_DATALESS) == 0, current.st_flags & UInt32(SF_DATALESS) == 0 else {
      throw AttachmentError.offline
    }
    guard Self.revision(original) == Self.revision(after), Self.revision(original) == Self.revision(current),
          Int64(byteCount) == original.st_size else { throw AttachmentError.unavailable }
  }
}

/// Internal to the native bridge, also exercised by the synthetic macOS tests.
final class AttachmentScope: WorkspaceFileScope {
  static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp"]
  static let maximumImageBytes = 32 * 1024 * 1024
  static let maximumSettingsBytes = 64 * 1024
  static let maximumEntries = 10_000
  static let maximumVisitedEntries = 50_000
  static let maximumDepth = 64
  static let coordinationTimeout: TimeInterval = 5

  static func components(_ path: String) throws -> [String] {
    let components = try relativeComponents(path)
    if path == ".obsidian/app.json" { return components }
    guard !components.contains(where: { $0.hasPrefix(".") }),
          imageExtensions.contains((path as NSString).pathExtension.lowercased()) else {
      throw AttachmentError.invalid
    }
    return components
  }

  /// Descriptor-based, metadata-only enumeration: no image/config bytes, file
  /// coordination, downloading, or symlink traversal occurs while indexing.
  func list() throws -> [[String: Any]] {
    try verifyRootLocation()
    struct Entry {
      let relativePath: String
      let size: Int64
      let modified: Int64
      let revision: String
      let placeholder: Bool
    }
    var entries: [Data: Entry] = [:]
    var visited = 0
    func visit(_ descriptor: Int32, prefix: String, depth: Int) throws {
      // dup() shares a directory's seek offset. Open "." relative to the
      // descriptor so repeated enumeration never inherits an exhausted offset.
      let duplicate = openat(descriptor, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      guard duplicate >= 0 else { throw AttachmentError.posix() }
      guard let directory = fdopendir(duplicate) else {
        let error = AttachmentError.posix()
        close(duplicate)
        throw error
      }
      defer { closedir(directory) }
      while true {
        errno = 0
        guard let entry = readdir(directory) else {
          if errno != 0 { throw AttachmentError.posix() }
          break
        }
        let capacity = Int(entry.pointee.d_namlen) + 1
        let name = withUnsafePointer(to: &entry.pointee.d_name) {
          $0.withMemoryRebound(to: CChar.self, capacity: capacity) { String(validatingUTF8: $0) }
        }
        guard let name else { throw AttachmentError.invalid }
        if name == "." || name == ".." { continue }
        visited += 1
        guard visited <= Self.maximumVisitedEntries else { throw AttachmentError.indexLimit }
        let placeholder = name.hasPrefix(".") && name.hasSuffix(".icloud")
        if name.hasPrefix(".") && !placeholder { continue }
        // Unsupported names must not poison the complete Dart index or cause
        // traversal of directories the resolver cannot address.
        if name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) ||
           name.contains("\\") || name.contains(":") { continue }
        var attributes = stat()
        guard fstatat(descriptor, name, &attributes, AT_SYMLINK_NOFOLLOW) == 0 else {
          throw AttachmentError.posix()
        }
        let type = attributes.st_mode & mode_t(S_IFMT)
        if type == mode_t(S_IFLNK) { continue }
        if type == mode_t(S_IFDIR) {
          // Hidden directories are never traversed, including stub-like names.
          if name.hasPrefix(".") { continue }
          guard depth < Self.maximumDepth else { throw AttachmentError.indexLimit }
          let child = openat(descriptor, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
          guard child >= 0 else { throw AttachmentError.posix() }
          defer { close(child) }
          try visit(child, prefix: prefix + name + "/", depth: depth + 1)
          continue
        }
        guard type == mode_t(S_IFREG) else { continue }
        let logicalName = placeholder ? String(name.dropFirst().dropLast(7)) : name
        let relativePath = prefix + logicalName
        guard relativePath.utf16.count <= 4096 else { throw AttachmentError.indexLimit }
        guard !logicalName.isEmpty, !logicalName.hasPrefix("."),
              Self.imageExtensions.contains((logicalName as NSString).pathExtension.lowercased()),
              !relativePath.contains("\\"), !relativePath.contains(":") else { continue }
        // A real file wins if an iCloud provider temporarily leaves both forms.
        let identity = Data(relativePath.utf8)
        if entries[identity]?.placeholder == false && placeholder { continue }
        entries[identity] = Entry(
          relativePath: relativePath,
          size: placeholder ? 0 : Int64(attributes.st_size),
          modified: Int64(attributes.st_mtimespec.tv_sec) * 1000 + Int64(attributes.st_mtimespec.tv_nsec) / 1_000_000,
          revision: Self.revision(attributes),
          placeholder: placeholder
        )
        guard entries.count <= Self.maximumEntries else { throw AttachmentError.indexLimit }
      }
    }
    try visit(rootDescriptor, prefix: "", depth: 0)
    try verifyRootLocation()
    return entries.values.sorted { $0.relativePath.utf8.lexicographicallyPrecedes($1.relativePath.utf8) }.map { entry in
      let path = entry.relativePath
      return [
        "relativePath": path,
        "comparisonPath": path.precomposedStringWithCanonicalMapping.lowercased(),
        "size": entry.size,
        "modified": entry.modified,
        "revision": entry.revision,
      ]
    }
  }

  func read(relativePath: String, maximumBytes: Int) throws -> Data {
    let components = try Self.components(relativePath)
    guard maximumBytes > 0 else { throw AttachmentError.invalid }
    let hardLimit = relativePath == ".obsidian/app.json" ? Self.maximumSettingsBytes : Self.maximumImageBytes
    let limit = min(maximumBytes, hardLimit)
    try verifyRootLocation()
    let placeholder = try isPlaceholder(components)
    let target = rootURL.appendingPathComponent(relativePath)
    if placeholder {
      // Request only this logical file, then let the UI retry. Never wait for an
      // offline provider's download on the serialized attachment queue.
      do { try FileManager.default.startDownloadingUbiquitousItem(at: target) }
      catch {
        let mapped = AttachmentError.classify(error, placeholder: true)
        if mapped == .denied || mapped == .invalid { throw mapped }
      }
      throw AttachmentError.offline
    }
    var coordinationError: NSError?
    var outcome: Result<Data, Error> = .failure(AttachmentError.unavailable)
    // A stalled file presenter must not indefinitely block subsequent images.
    // cancel() aborts the waiting coordination claim; the accessor still checks
    // dataless state and uses only bounded, descriptor-scoped local reads.
    let coordinator = NSFileCoordinator()
    let timeout = DispatchWorkItem { coordinator.cancel() }
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.coordinationTimeout, execute: timeout)
    defer { timeout.cancel() }
    coordinator.coordinate(readingItemAt: target, options: [], error: &coordinationError) { coordinated in
      outcome = Result {
        try self.readCoordinated(coordinated, relativePath: relativePath, maximumBytes: limit)
      }
    }
    if let coordinationError { throw AttachmentError.classify(coordinationError, placeholder: placeholder) }
    do { return try outcome.get() }
    catch { throw AttachmentError.classify(error, placeholder: placeholder) }
  }

  /// Kept separate so the production accessor's redirect and replacement checks
  /// can be tested deterministically, without relying on a winning race.
  func readCoordinated(_ coordinated: URL, relativePath: String, maximumBytes: Int) throws -> Data {
    try Self.withoutMaterialization {
      try readLocal(coordinated, relativePath: relativePath, maximumBytes: maximumBytes)
    }
  }

  private func readLocal(_ coordinated: URL, relativePath: String, maximumBytes: Int) throws -> Data {
    let components = try Self.components(relativePath)
    let hardLimit = relativePath == ".obsidian/app.json" ? Self.maximumSettingsBytes : Self.maximumImageBytes
    guard maximumBytes > 0 else { throw AttachmentError.invalid }
    let limit = min(maximumBytes, hardLimit)
    let expected = rootURL.appendingPathComponent(relativePath)
    guard coordinated.isFileURL, Data(coordinated.path.utf8) == Data(expected.path.utf8) else { throw AttachmentError.invalid }
    return try readLocalBytes(components: components, maximumBytes: limit, verifyRevision: false).bytes
  }
}

/// Search has a separate allow-list and never requests iCloud materialization.
/// It shares authority and byte IO with images, not their download/config policy.
final class WorkspaceTextScope: WorkspaceFileScope {
  static let coordinationTimeout: TimeInterval = 5
  static let maximumTextBytes = 5 * 1024 * 1024
  static let maximumDirectoryEntries = 50_000
  static let maximumVisitedDirectoryEntries = 100_000
  static let directoryTimeout: TimeInterval = 1

  static func textComponents(_ path: String, directory: Bool) throws -> [String] {
    if directory && path.isEmpty { return [] }
    let components = try relativeComponents(path)
    guard !components.contains(where: { $0.hasPrefix(".") }),
          !directory || components.count <= maximumPathDepth,
          directory || CloudWorkspace.extensions.contains((path as NSString).pathExtension.lowercased()) else {
      throw AttachmentError.invalid
    }
    return components
  }

  /// Metadata only, one directory, bounded on every call. A partial catalog must
  /// be visibly incomplete; it must never become evidence that a file is absent.
  /// Smaller test budgets exercise real bounds without huge temporary fixtures.
  func listDirectory(
    relativePath: String,
    entryLimit: Int = WorkspaceTextScope.maximumDirectoryEntries,
    visitedLimit: Int = WorkspaceTextScope.maximumVisitedDirectoryEntries,
    deadline: DispatchTime? = nil
  ) throws -> [String: Any] {
    let components = try Self.textComponents(relativePath, directory: true)
    guard entryLimit > 0, visitedLimit > 0 else { throw AttachmentError.invalid }
    let entryLimit = min(entryLimit, Self.maximumDirectoryEntries)
    let visitedLimit = min(visitedLimit, Self.maximumVisitedDirectoryEntries)
    let end = deadline?.uptimeNanoseconds ??
      (DispatchTime.now().uptimeNanoseconds + UInt64(Self.directoryTimeout * 1_000_000_000))
    try verifyRootLocation()
    let descriptor = try directoryDescriptor(components)
    defer { close(descriptor) }
    var before = stat()
    guard fstat(descriptor, &before) == 0 else { throw AttachmentError.posix() }
    guard before.st_flags & UInt32(SF_DATALESS) == 0 else { throw AttachmentError.offline }
    // A distinct open file description avoids sharing an exhausted readdir offset.
    let duplicate = openat(descriptor, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard duplicate >= 0 else { throw AttachmentError.posix() }
    guard let directory = fdopendir(duplicate) else {
      let error = AttachmentError.posix()
      close(duplicate)
      throw error
    }
    defer { closedir(directory) }
    struct Entry {
      let relativePath: String
      let name: String
      let directory: Bool
      let attributes: stat
      let placeholder: Bool
    }
    var entries: [Data: Entry] = [:]
    var visited = 0
    var reason: AttachmentError?
    let prefix = relativePath.isEmpty ? "" : relativePath + "/"
    while true {
      guard DispatchTime.now().uptimeNanoseconds < end else { reason = .indexLimit; break }
      errno = 0
      guard let entry = readdir(directory) else {
        if errno != 0 { reason = AttachmentError.posix() }
        break
      }
      let capacity = Int(entry.pointee.d_namlen) + 1
      let name = withUnsafePointer(to: &entry.pointee.d_name) {
        $0.withMemoryRebound(to: CChar.self, capacity: capacity) { String(validatingUTF8: $0) }
      }
      guard let name else { reason = .invalid; break }
      if name == "." || name == ".." { continue }
      visited += 1
      guard visited <= visitedLimit else { reason = .indexLimit; break }
      let placeholder = name.hasPrefix(".") && name.hasSuffix(".icloud")
      if name.hasPrefix(".") && !placeholder { continue }
      if name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) ||
         name.contains("\\") || name.contains(":") { continue }
      var attributes = stat()
      guard fstatat(descriptor, name, &attributes, AT_SYMLINK_NOFOLLOW) == 0 else {
        reason = AttachmentError.posix()
        break
      }
      let type = attributes.st_mode & mode_t(S_IFMT)
      let isDirectory = type == mode_t(S_IFDIR)
      guard isDirectory || type == mode_t(S_IFREG) else { continue }
      // A stub-looking directory is not a logical, visible folder.
      if isDirectory && name.hasPrefix(".") { continue }
      let logicalName = placeholder ? String(name.dropFirst().dropLast(7)) : name
      guard !logicalName.isEmpty, !logicalName.hasPrefix("."),
            isDirectory || CloudWorkspace.extensions.contains((logicalName as NSString).pathExtension.lowercased()) else {
        continue
      }
      let path = prefix + logicalName
      guard path.utf16.count <= 4096 else { reason = .indexLimit; break }
      if isDirectory && components.count >= Self.maximumPathDepth { reason = .indexLimit; break }
      let identity = Data(path.utf8)
      // If a provider leaves both forms behind, prefer the actual file.
      if entries[identity]?.placeholder == false && placeholder { continue }
      if entries[identity] == nil && entries.count >= entryLimit { reason = .indexLimit; break }
      entries[identity] = Entry(
        relativePath: path, name: logicalName, directory: isDirectory,
        attributes: attributes, placeholder: placeholder
      )
    }
    try verifyRootLocation()
    let current = try directoryDescriptor(components)
    defer { close(current) }
    var after = stat()
    guard fstat(current, &after) == 0 else { throw AttachmentError.posix() }
    if Self.revision(before) != Self.revision(after) { reason = reason ?? .unavailable }
    let rows: [[String: Any]] = entries.values.sorted {
      $0.relativePath.utf8.lexicographicallyPrecedes($1.relativePath.utf8)
    }.map { entry in
      let attributes = entry.attributes
      return [
        "relativePath": entry.relativePath,
        "comparisonPath": entry.relativePath.precomposedStringWithCanonicalMapping.lowercased(),
        "name": entry.name,
        "isDirectory": entry.directory,
        "size": entry.placeholder ? Int64(0) : Int64(attributes.st_size),
        "modified": Int64(attributes.st_mtimespec.tv_sec) * 1000 + Int64(attributes.st_mtimespec.tv_nsec) / 1_000_000,
        "revision": Self.revision(attributes),
        "local": !entry.placeholder && attributes.st_flags & UInt32(SF_DATALESS) == 0,
      ]
    }
    var result: [String: Any] = ["entries": rows, "complete": reason == nil]
    if let reason { result["reason"] = reason.code }
    return result
  }

  /// Ask the filesystem, not a lowercase/NFC guess. Two distinct files on a
  /// case-sensitive volume keep distinct identities and stored spellings.
  func resolvePath(relativePath: String) throws -> [String: String] {
    let components = try Self.textComponents(relativePath, directory: false)
    try verifyRootLocation()
    let parent = try parentDescriptor(components)
    defer { close(parent) }
    let descriptor = openat(parent, components.last!, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    guard descriptor >= 0 else { throw AttachmentError.posix() }
    defer { close(descriptor) }
    var attributes = stat()
    guard fstat(descriptor, &attributes) == 0 else { throw AttachmentError.posix() }
    guard attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw AttachmentError.invalid }
    var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    guard path.withUnsafeMutableBufferPointer({ fcntl(descriptor, F_GETPATH, $0.baseAddress!) }) == 0 else {
      throw AttachmentError.posix()
    }
    let actual = String(cString: path)
    let prefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
    guard actual.utf8.starts(with: prefix.utf8) else { throw AttachmentError.invalid }
    let relative = String(decoding: actual.utf8.dropFirst(prefix.utf8.count), as: UTF8.self)
    _ = try Self.textComponents(relative, directory: false)
    try verifyRootLocation()
    let currentParent = try parentDescriptor(components)
    defer { close(currentParent) }
    var current = stat()
    guard fstatat(currentParent, components.last!, &current, AT_SYMLINK_NOFOLLOW) == 0 else { throw AttachmentError.posix() }
    guard current.st_dev == attributes.st_dev && current.st_ino == attributes.st_ino else {
      throw AttachmentError.unavailable
    }
    return ["relativePath": relative, "identity": "\(attributes.st_dev):\(attributes.st_ino)"]
  }

  /// Explicit create only. No recursive mkdir, absolute-path fallback, provider
  /// download, or replacing rename. Subsequent edits use guarded document saves.
  func createNote(
    relativePath: String,
    beforeExclusiveCreate: (() throws -> Void)? = nil,
    afterExclusiveCreate: (() throws -> Void)? = nil
  ) throws {
    let components = try Self.textComponents(relativePath, directory: false)
    guard relativePath.lowercased().hasSuffix(".md"), let name = components.last else {
      throw AttachmentError.invalid
    }
    try verifyRootLocation()
    let parent = try parentDescriptor(components)
    defer { close(parent) }
    var attributes = stat()
    guard fstat(parent, &attributes) == 0 else { throw AttachmentError.posix() }
    guard attributes.st_flags & UInt32(SF_DATALESS) == 0 else { throw AttachmentError.offline }
    // Reject known case/NFC collisions and provider placeholders before the
    // exclusive final open. A partial listing is not evidence of absence.
    let parentPath = components.dropLast().joined(separator: "/")
    let listing = try listDirectory(relativePath: parentPath)
    guard listing["complete"] as? Bool == true,
          let rows = listing["entries"] as? [[String: Any]] else { throw AttachmentError.unavailable }
    let comparison = relativePath.precomposedStringWithCanonicalMapping.lowercased()
    guard !rows.contains(where: { $0["comparisonPath"] as? String == comparison }) else {
      throw AttachmentError.unavailable
    }
    let currentParent = try parentDescriptor(components)
    defer { close(currentParent) }
    var current = stat()
    guard fstat(currentParent, &current) == 0 else { throw AttachmentError.posix() }
    guard current.st_dev == attributes.st_dev && current.st_ino == attributes.st_ino else {
      throw AttachmentError.unavailable
    }
    try verifyRootLocation()
    // Test hooks exercise deterministic uncoordinated writers. They are never
    // exposed through the channel or invoked by production callers.
    try beforeExclusiveCreate?()
    let descriptor = openat(parent, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { throw AttachmentError.posix() }
    defer { close(descriptor) }
    var created = stat()
    guard fstat(descriptor, &created) == 0 else { throw AttachmentError.posix() }
    // After a failed flush the exclusive empty file can exist. Never retry or
    // delete it automatically: a later user retry sees the occupied path.
    guard fsync(descriptor) == 0 else { throw AttachmentError.posix() }
    try afterExclusiveCreate?()
    try verifyRootLocation()
    let finalParent = try parentDescriptor(components)
    defer { close(finalParent) }
    var finalDirectory = stat()
    var finalTarget = stat()
    guard fstat(finalParent, &finalDirectory) == 0,
          fstatat(finalParent, name, &finalTarget, AT_SYMLINK_NOFOLLOW) == 0 else { throw AttachmentError.posix() }
    guard finalDirectory.st_dev == attributes.st_dev && finalDirectory.st_ino == attributes.st_ino,
          finalTarget.st_dev == created.st_dev && finalTarget.st_ino == created.st_ino,
          finalTarget.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
          Self.revision(finalTarget) == Self.revision(created), created.st_size == 0 else {
      // Do not unlink: an uncoordinated writer may now own the pathname. A
      // renamed authorized parent can retain our empty file outside the vault;
      // this is a reported failure, never a successful navigation or retry.
      throw AttachmentError.unavailable
    }
  }

  func readText(relativePath: String, maximumBytes: Int = WorkspaceTextScope.maximumTextBytes) throws -> WorkspaceTextBytes {
    let components = try Self.textComponents(relativePath, directory: false)
    guard maximumBytes > 0 else { throw AttachmentError.invalid }
    try verifyRootLocation()
    guard try !isPlaceholder(components) else { throw AttachmentError.offline }
    // No file coordination or download request: preserve bytes exactly, then
    // let Dart validate UTF-8 and match this revision against catalog metadata.
    return try readLocalBytes(
      components: components, maximumBytes: min(maximumBytes, Self.maximumTextBytes), verifyRevision: true
    )
  }
}

/// Only a positively confirmed absence may select the default import folder.
/// Ordinary ENOENT from an observed object or its selected root is an error.
private enum AttachmentImportSettingsAbsence: Error { case confirmed }

final class AttachmentImportSettingsScope: WorkspaceFileScope {
  static func requireLocalDirectory(_ attributes: stat) throws {
    guard attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { throw AttachmentError.invalid }
    guard attributes.st_flags & UInt32(SF_DATALESS) == 0 else { throw AttachmentError.offline }
    // UF_HIDDEN is deliberately allowed for the selected vault and this known
    // .obsidian directory. Visibility is not authority to follow another path.
  }

  private func state(_ parent: Int32, _ name: String) throws -> stat? {
    var attributes = stat()
    if fstatat(parent, name, &attributes, AT_SYMLINK_NOFOLLOW) == 0 { return attributes }
    guard errno == ENOENT else { throw AttachmentError.posix() }
    return nil
  }

  private func rejectPlaceholder(_ parent: Int32, _ name: String) throws {
    if let marker = try state(parent, ".\(name).icloud") {
      let kind = marker.st_mode & mode_t(S_IFMT)
      guard kind == mode_t(S_IFREG) || kind == mode_t(S_IFDIR) else { throw AttachmentError.invalid }
      throw AttachmentError.offline
    }
  }

  private func verifyLocalRoot() throws {
    try verifyRootLocation()
    var attributes = stat()
    guard fstat(rootDescriptor, &attributes) == 0 else { throw AttachmentError.posix() }
    try Self.requireLocalDirectory(attributes)
  }

  private func verifyParent(_ descriptor: Int32, original: stat) throws {
    try verifyLocalRoot()
    guard let current = try state(rootDescriptor, ".obsidian") else { throw AttachmentError.unavailable }
    var opened = stat()
    guard fstat(descriptor, &opened) == 0 else { throw AttachmentError.posix() }
    try Self.requireLocalDirectory(current)
    try Self.requireLocalDirectory(opened)
    guard current.st_dev == original.st_dev, current.st_ino == original.st_ino,
          opened.st_dev == original.st_dev, opened.st_ino == original.st_ino else { throw AttachmentError.unavailable }
    try rejectPlaceholder(rootDescriptor, ".obsidian")
  }

  func read(beforeLocalRead: (() throws -> Void)? = nil, afterLocalRead: (() throws -> Void)? = nil) throws -> Data {
    try verifyLocalRoot()
    try rejectPlaceholder(rootDescriptor, ".obsidian")
    guard let observedParent = try state(rootDescriptor, ".obsidian") else {
      // Recheck the root, literal parent path and its logical placeholder before
      // distinguishing true absence from nonlocal or changing provider state.
      try verifyLocalRoot()
      guard try state(rootDescriptor, ".obsidian") == nil else { throw AttachmentError.unavailable }
      try rejectPlaceholder(rootDescriptor, ".obsidian")
      throw AttachmentImportSettingsAbsence.confirmed
    }
    try Self.requireLocalDirectory(observedParent)
    let parent = openat(rootDescriptor, ".obsidian", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard parent >= 0 else { throw AttachmentError.posix() }
    defer { close(parent) }
    try verifyParent(parent, original: observedParent)
    try rejectPlaceholder(parent, "app.json")
    guard let observedLeaf = try state(parent, "app.json") else {
      try verifyParent(parent, original: observedParent)
      guard try state(parent, "app.json") == nil else { throw AttachmentError.unavailable }
      try rejectPlaceholder(parent, "app.json")
      try verifyParent(parent, original: observedParent)
      throw AttachmentImportSettingsAbsence.confirmed
    }
    guard observedLeaf.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw AttachmentError.invalid }
    guard observedLeaf.st_flags & UInt32(SF_DATALESS) == 0 else { throw AttachmentError.offline }
    // UF_HIDDEN is also allowed on app.json: this exact, intentionally hidden
    // configuration leaf is the only hidden-file exception, never arbitrary IO.
    try beforeLocalRead?() // Deterministic test hook, never a channel argument.
    try verifyParent(parent, original: observedParent)
    let result = try readLocalBytes(
      components: [".obsidian", "app.json"], maximumBytes: AttachmentScope.maximumSettingsBytes, verifyRevision: true
    )
    try afterLocalRead?()
    try verifyParent(parent, original: observedParent)
    try rejectPlaceholder(parent, "app.json")
    guard let current = try state(parent, "app.json"),
          current.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
          Self.revision(current) == Self.revision(observedLeaf),
          result.revision == Self.revision(observedLeaf) else { throw AttachmentError.unavailable }
    guard current.st_flags & UInt32(SF_DATALESS) == 0 else { throw AttachmentError.offline }
    return result.bytes
  }
}

/// Explicit imports share the read-side descriptor authority, but never download
/// provider content, follow file URLs from the clipboard, or replace a file.
extension CloudWorkspace {
  static func createWorkspaceAttachment(
    _ root: URL, relativeDirectory: String, filename: String, bytes: Data
  ) throws -> String {
    do {
      return try WorkspaceFileScope.withoutMaterialization {
        try AttachmentImportScope.validate(relativeDirectory: relativeDirectory, filename: filename, bytes: bytes)
        let scope = try AttachmentImportScope(root)
        try scope.checkWritableDirectory(scope.rootDescriptor)
        var coordinationError: NSError?
        var outcome: Result<String, Error> = .failure(AttachmentError.unavailable)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        let deadline = DispatchTime.now() + AttachmentScope.coordinationTimeout
        let timeout = DispatchWorkItem { coordinator.cancel() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: deadline, execute: timeout)
        defer { timeout.cancel() }
        // Coordinate the existing root, not an absent directory or provider
        // placeholder. Recursive mkdir is confined to this explicit operation.
        coordinator.coordinate(writingItemAt: scope.rootURL, options: .forMerging, error: &coordinationError) { coordinated in
          outcome = Result {
            guard DispatchTime.now().uptimeNanoseconds < deadline.uptimeNanoseconds,
                  Data(coordinated.path.utf8) == Data(scope.rootURL.path.utf8) else {
              throw AttachmentError.unavailable
            }
            return try scope.create(relativeDirectory: relativeDirectory, filename: filename, bytes: bytes)
          }
        }
        if let error = coordinationError {
          if let path = scope.createdRelativePath {
            throw AttachmentImportWriteFailure(failure: AttachmentError.classify(error), relativePath: path)
          }
          throw error
        }
        return try outcome.get()
      }
    } catch let error as AttachmentImportWriteFailure { throw error }
    catch { throw AttachmentError.classify(error) }
  }
}

struct AttachmentImportWriteFailure: LocalizedError {
  let failure: AttachmentError
  let relativePath: String
  var errorDescription: String? {
    "The import could not be verified. A file may remain at \(relativePath); nothing was removed or overwritten automatically."
  }
}

final class AttachmentImportScope: WorkspaceFileScope {
  private(set) var createdRelativePath: String?

  static func directoryComponents(_ path: String) throws -> [String] {
    if path.isEmpty { return [] }
    let components = try relativeComponents(path)
    guard components.count <= maximumPathDepth,
          components.allSatisfy({ !$0.hasPrefix(".") && $0.utf8.count <= 255 }) else {
      throw AttachmentError.invalid
    }
    return components
  }

  static func validate(relativeDirectory: String, filename: String, bytes: Data) throws {
    let directory = try directoryComponents(relativeDirectory)
    _ = try AttachmentScope.components((directory + [filename]).joined(separator: "/"))
    let suffix = (filename as NSString).pathExtension
    let stem = (filename as NSString).deletingPathExtension
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
    guard !stem.isEmpty, stem.utf8.count <= 120,
          stem.unicodeScalars.allSatisfy({ allowed.contains($0) }),
          !stem.hasPrefix("-"), !stem.hasPrefix("_"),
          AttachmentScope.imageExtensions.contains(suffix),
          filename == stem + "." + suffix else { throw AttachmentError.invalid }
    let image = try AttachmentImportImage.inspect(bytes, allowTIFF: false)
    guard suffix == image.extensionName || (suffix == "jpeg" && image.extensionName == "jpg") else {
      throw AttachmentError.invalid
    }
  }

  @discardableResult
  func checkWritableDirectory(_ descriptor: Int32) throws -> stat {
    var attributes = stat()
    guard fstat(descriptor, &attributes) == 0 else { throw AttachmentError.posix() }
    guard attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
          attributes.st_flags & UInt32(UF_HIDDEN) == 0 else { throw AttachmentError.invalid }
    guard attributes.st_flags & UInt32(SF_DATALESS) == 0 else { throw AttachmentError.offline }
    guard attributes.st_mode & mode_t(0o222) != 0,
          attributes.st_flags & UInt32(UF_IMMUTABLE | SF_IMMUTABLE | UF_APPEND | SF_APPEND) == 0 else {
      throw AttachmentError.denied
    }
    var volume = statfs()
    guard fstatfs(descriptor, &volume) == 0 else { throw AttachmentError.posix() }
    guard volume.f_flags & UInt32(MNT_RDONLY) == 0 else { throw AttachmentError.denied }
    guard faccessat(descriptor, ".", W_OK | X_OK, 0) == 0 else { throw AttachmentError.posix() }
    return attributes
  }

  /// Reject case/NFC aliases and logical iCloud placeholders before creating a
  /// new basename. This bounded listing is metadata-only and never follows links.
  private func rejectOccupiedName(_ descriptor: Int32, name: String) throws {
    let duplicate = openat(descriptor, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard duplicate >= 0 else { throw AttachmentError.posix() }
    guard let directory = fdopendir(duplicate) else {
      let error = AttachmentError.posix()
      close(duplicate)
      throw error
    }
    defer { closedir(directory) }
    let comparison = name.precomposedStringWithCanonicalMapping.lowercased()
    let placeholder = "." + comparison + ".icloud"
    var count = 0
    while true {
      errno = 0
      guard let entry = readdir(directory) else {
        if errno != 0 { throw AttachmentError.posix() }
        return
      }
      count += 1
      guard count <= AttachmentScope.maximumVisitedEntries else { throw AttachmentError.indexLimit }
      let candidate = withUnsafePointer(to: &entry.pointee.d_name) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
          String(validatingUTF8: $0)
        }
      }
      guard let candidate else { throw AttachmentError.invalid }
      let normalized = candidate.precomposedStringWithCanonicalMapping.lowercased()
      if normalized == placeholder { throw AttachmentError.offline }
      if normalized == comparison { throw AttachmentError.collision }
    }
  }

  private func verifyDirectories(_ components: [String], identities: [stat]) throws {
    try verifyRootLocation()
    var current = dup(rootDescriptor)
    guard current >= 0 else { throw AttachmentError.posix() }
    defer { close(current) }
    for depth in 0...components.count {
      if depth > 0 {
        let next = openat(current, components[depth - 1], O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard next >= 0 else { throw AttachmentError.posix() }
        close(current)
        current = next
      }
      let attributes = try checkWritableDirectory(current)
      guard attributes.st_dev == identities[depth].st_dev,
            attributes.st_ino == identities[depth].st_ino else { throw AttachmentError.unavailable }
    }
  }

  func create(
    relativeDirectory: String, filename: String, bytes: Data,
    beforeDirectoryCreate: ((String) throws -> Void)? = nil,
    beforeExclusiveCreate: (() throws -> Void)? = nil,
    afterExclusiveCreate: (() throws -> Void)? = nil
  ) throws -> String {
    try Self.validate(relativeDirectory: relativeDirectory, filename: filename, bytes: bytes)
    let components = try Self.directoryComponents(relativeDirectory)
    try verifyRootLocation()
    var parent = dup(rootDescriptor)
    guard parent >= 0 else { throw AttachmentError.posix() }
    defer { close(parent) }
    var identities = [try checkWritableDirectory(parent)]
    for (depth, name) in components.enumerated() {
      try verifyDirectories(Array(components.prefix(depth)), identities: identities)
      var placeholder = stat()
      if fstatat(parent, ".\(name).icloud", &placeholder, AT_SYMLINK_NOFOLLOW) == 0 {
        throw AttachmentError.offline
      }
      guard errno == ENOENT else { throw AttachmentError.posix() }
      var child = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      if child < 0 {
        guard errno == ENOENT else { throw AttachmentError.posix() }
        try rejectOccupiedName(parent, name: name)
        try beforeDirectoryCreate?(Array(components.prefix(depth + 1)).joined(separator: "/"))
        try verifyDirectories(Array(components.prefix(depth)), identities: identities)
        // A concurrently won directory is not ours to adopt. Fail closed,
        // retaining it and all existing contents without rollback or retry.
        guard mkdirat(parent, name, 0o700) == 0 else {
          if errno == EEXIST { throw AttachmentError.unavailable }
          throw AttachmentError.posix()
        }
        child = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      }
      guard child >= 0 else { throw AttachmentError.posix() }
      close(parent)
      parent = child
      identities.append(try checkWritableDirectory(parent))
    }
    try rejectOccupiedName(parent, name: filename)
    // Hooks are test-only and never accepted through the channel.
    try beforeExclusiveCreate?()
    try verifyDirectories(components, identities: identities)
    // Check again after the hook; O_EXCL remains the final authority for a race
    // after this metadata check, including a symlink or a same-basename create.
    try rejectOccupiedName(parent, name: filename)
    let descriptor = openat(parent, filename, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else {
      if errno == EEXIST { throw AttachmentError.collision }
      throw AttachmentError.posix()
    }
    defer { close(descriptor) }
    let relativePath = (components + [filename]).joined(separator: "/")
    createdRelativePath = relativePath
    do {
      let deadline = DispatchTime.now() + Self.readTimeout
      try bytes.withUnsafeBytes { buffer in
        var offset = 0
        while offset < buffer.count {
          guard DispatchTime.now().uptimeNanoseconds < deadline.uptimeNanoseconds else { throw AttachmentError.unavailable }
          let written = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), min(64 * 1024, buffer.count - offset))
          if written < 0 {
            if errno == EINTR { continue }
            throw AttachmentError.posix()
          }
          guard written > 0 else { throw AttachmentError.unavailable }
          offset += written
        }
      }
      guard fsync(descriptor) == 0 else { throw AttachmentError.posix() }
      var written = stat()
      guard fstat(descriptor, &written) == 0 else { throw AttachmentError.posix() }
      try afterExclusiveCreate?()
      try verifyDirectories(components, identities: identities)
      let finalParent = try directoryDescriptor(components)
      defer { close(finalParent) }
      var finalTarget = stat()
      var finalOpened = stat()
      guard fstatat(finalParent, filename, &finalTarget, AT_SYMLINK_NOFOLLOW) == 0,
            fstat(descriptor, &finalOpened) == 0 else { throw AttachmentError.posix() }
      guard finalTarget.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
            finalTarget.st_flags & UInt32(SF_DATALESS | UF_HIDDEN) == 0,
            finalTarget.st_nlink == 1, written.st_size == Int64(bytes.count),
            Self.revision(finalTarget) == Self.revision(written),
            Self.revision(finalOpened) == Self.revision(written) else { throw AttachmentError.unavailable }
      // A concurrent uncoordinated rename can move a pinned parent outside the
      // root during IO. Checks detect observed replacement, not absolute race
      // immunity. On any error retain uncertain files; never unlink someone else's
      // path or report a successful import. Dart inserts markup only on success.
      return relativePath
    } catch {
      throw AttachmentImportWriteFailure(failure: AttachmentError.classify(error), relativePath: relativePath)
    }
  }
}

/// Metadata is inspected without decoding first. The only native pixel decode is
/// explicit TIFF-to-PNG conversion for screenshots; all other formats retain
/// their original bytes. Neither the advertised UTI nor the extension is trusted.
enum AttachmentImportImage {
  static let maximumPixels = 32 * 1024 * 1024
  // TIFF requires native pixel decode and PNG encoding before Dart validation.
  // Keep it below the generic raster cap: two 32 MiB encoded copies + three
  // 4-byte/pixel working buffers + a 32 MiB output fit within 256 MiB at 8 Mpx.
  static let maximumTIFFPixels = 8 * 1024 * 1024
  static let maximumFrames = 256
  struct Information {
    let source: CGImageSource
    let extensionName: String
  }

  static func inspect(_ bytes: Data, allowTIFF: Bool) throws -> Information {
    guard !bytes.isEmpty else { throw AttachmentError.unsupported }
    guard bytes.count <= AttachmentScope.maximumImageBytes else { throw AttachmentError.tooLarge }
    guard let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
          let type = CGImageSourceGetType(source) else { throw AttachmentError.unsupported }
    let extensionName: String
    switch type as String {
    case "public.png": extensionName = "png"
    case "public.jpeg": extensionName = "jpg"
    case "com.compuserve.gif": extensionName = "gif"
    case "org.webmproject.webp": extensionName = "webp"
    case "com.microsoft.bmp": extensionName = "bmp"
    case "public.tiff" where allowTIFF: extensionName = "tiff"
    default: throw AttachmentError.unsupported
    }
    let frames = CGImageSourceGetCount(source)
    guard frames > 0 else { throw AttachmentError.unsupported }
    guard frames <= maximumFrames else { throw AttachmentError.tooLarge }
    for index in 0..<frames {
      guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, [kCGImageSourceShouldCache: false] as CFDictionary) as? [String: Any],
            let width = properties[kCGImagePropertyPixelWidth as String] as? NSNumber,
            let height = properties[kCGImagePropertyPixelHeight as String] as? NSNumber else { throw AttachmentError.unsupported }
      try validateDimensions(width: width.doubleValue, height: height.doubleValue)
      if extensionName == "tiff" {
        try validateTIFFDimensions(width: width.doubleValue, height: height.doubleValue)
        guard let depth = properties[kCGImagePropertyDepth as String] as? NSNumber,
              depth.intValue > 0, depth.intValue <= 8 else { throw AttachmentError.unsupported }
      }
    }
    guard CGImageSourceGetStatus(source) == .statusComplete else { throw AttachmentError.unsupported }
    return Information(source: source, extensionName: extensionName)
  }

  static func validateDimensions(width: Double, height: Double) throws {
    guard width.isFinite, height.isFinite, width >= 1, height >= 1,
          width.rounded(.down) == width, height.rounded(.down) == height else { throw AttachmentError.unsupported }
    guard width <= Double(maximumPixels) / height else { throw AttachmentError.tooLarge }
  }

  static func validateTIFFDimensions(width: Double, height: Double) throws {
    try validateDimensions(width: width, height: height)
    // Also exclude extremely narrow/tall rasters whose per-row alignment can
    // multiply allocation despite a small pixel count.
    guard width <= 16_384, height <= 16_384,
          width <= Double(maximumTIFFPixels) / height else { throw AttachmentError.tooLarge }
  }

  static func prepare(_ bytes: Data, suggestedName: String) throws -> [String: Any] {
    let image = try inspect(bytes, allowTIFF: true)
    var output = bytes
    var suffix = image.extensionName
    if suffix == "tiff" {
      guard let decoded = CGImageSourceCreateImageAtIndex(image.source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
        throw AttachmentError.unsupported
      }
      let sink = BoundedImageOutput()
      var callbacks = CGDataConsumerCallbacks(putBytes: { info, buffer, count in
        guard let info else { return 0 }
        let sink = Unmanaged<BoundedImageOutput>.fromOpaque(info).takeUnretainedValue()
        guard count <= AttachmentScope.maximumImageBytes - sink.data.count else {
          sink.exceeded = true
          return 0
        }
        sink.data.append(buffer.assumingMemoryBound(to: UInt8.self), count: count)
        return count
      }, releaseConsumer: nil)
      guard let consumer = CGDataConsumer(info: Unmanaged.passUnretained(sink).toOpaque(), cbks: &callbacks),
            let destination = CGImageDestinationCreateWithDataConsumer(consumer, "public.png" as CFString, 1, nil) else {
        throw AttachmentError.unavailable
      }
      CGImageDestinationAddImage(destination, decoded, nil)
      let finalized = CGImageDestinationFinalize(destination)
      if sink.exceeded { throw AttachmentError.tooLarge }
      guard finalized else { throw AttachmentError.unavailable }
      output = sink.data
      suffix = "png"
      _ = try inspect(output, allowTIFF: false)
    }
    return ["bytes": FlutterStandardTypedData(bytes: output), "extension": suffix, "suggestedName": suggestedName]
  }
}

private final class BoundedImageOutput {
  var data = Data()
  var exceeded = false
}

#if os(macOS)
/// No NSPasteboard dependency in this policy helper: tests inject synthetic
/// advertised UTIs and bytes, never the real clipboard or file URLs.
enum AttachmentClipboardImage {
  static let preferredTypes = ["public.png", "public.jpeg", "com.compuserve.gif", "org.webmproject.webp", "com.microsoft.bmp", "public.tiff"]

  static func read(types: [String], dataForType: (String) -> Data?) throws -> Data? {
    guard let chosen = preferredTypes.first(where: { types.contains($0) }) else {
      if types.contains(where: { UTType($0)?.conforms(to: .image) == true }) { throw AttachmentError.unsupported }
      return nil
    }
    guard let bytes = dataForType(chosen) else { throw AttachmentError.unavailable }
    guard bytes.count <= AttachmentScope.maximumImageBytes else { throw AttachmentError.tooLarge }
    return bytes
  }
}

extension CloudWorkspace {
  private func completeAttachmentImport(_ result: @escaping FlutterResult, operation: @escaping () throws -> [String: Any]?) {
    attachmentQueue.async {
      do {
        let value = try operation()
        DispatchQueue.main.async { result(value) }
      } catch {
        let failure = AttachmentError.classify(error)
        DispatchQueue.main.async { result(FlutterError(code: failure.code, message: failure.localizedDescription, details: nil)) }
      }
    }
  }

  private func pickAttachmentImage(result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.title = "Insert Image"
    panel.prompt = "Insert"
    panel.allowedContentTypes = AttachmentClipboardImage.preferredTypes.compactMap { UTType($0) }
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = false
    panel.begin { response in
      guard response == .OK, let selected = panel.url else { result(nil); return }
      self.completeAttachmentImport(result) {
        let accessing = selected.startAccessingSecurityScopedResource()
        defer { if accessing { selected.stopAccessingSecurityScopedResource() } }
        let bytes = try Self.readPickedAttachmentImage(selected)
        return try AttachmentImportImage.prepare(bytes, suggestedName: selected.lastPathComponent)
      }
    }
  }

  static func readPickedAttachmentImage(_ selected: URL) throws -> Data {
    try WorkspaceFileScope.withoutMaterialization {
      guard selected.isFileURL, selected.path.hasPrefix("/"), !selected.path.contains("\0"),
            !selected.lastPathComponent.hasPrefix(".") else { throw AttachmentError.invalid }
      // A file-selection security scope may not grant access to its parent
      // directory. Open only the selected leaf, no-follow, while holding that
      // scope; never widen the grant by requesting/enumerating its directory.
      var before = stat()
      if lstat(selected.path, &before) != 0 {
        guard errno == ENOENT else { throw AttachmentError.posix() }
        let placeholder = selected.deletingLastPathComponent().appendingPathComponent(".\(selected.lastPathComponent).icloud")
        var stub = stat()
        if lstat(placeholder.path, &stub) == 0 { throw AttachmentError.offline }
        guard errno == ENOENT else { throw AttachmentError.posix() }
        throw AttachmentError.missing
      }
      guard before.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
            before.st_flags & UInt32(UF_HIDDEN) == 0 else { throw AttachmentError.invalid }
      guard before.st_flags & UInt32(SF_DATALESS) == 0 else { throw AttachmentError.offline }
      guard before.st_size >= 0, before.st_size <= Int64(AttachmentScope.maximumImageBytes) else { throw AttachmentError.tooLarge }
      var coordinationError: NSError?
      var outcome: Result<Data, Error> = .failure(AttachmentError.unavailable)
      let coordinator = NSFileCoordinator(filePresenter: nil)
      let deadline = DispatchTime.now() + AttachmentScope.coordinationTimeout
      let timeout = DispatchWorkItem { coordinator.cancel() }
      DispatchQueue.global(qos: .utility).asyncAfter(deadline: deadline, execute: timeout)
      defer { timeout.cancel() }
      coordinator.coordinate(readingItemAt: selected, options: [], error: &coordinationError) { coordinated in
        outcome = Result {
          guard DispatchTime.now().uptimeNanoseconds < deadline.uptimeNanoseconds,
                Data(coordinated.path.utf8) == Data(selected.path.utf8) else { throw AttachmentError.unavailable }
          let descriptor = open(selected.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
          guard descriptor >= 0 else { throw AttachmentError.posix() }
          defer { close(descriptor) }
          var opened = stat()
          guard fstat(descriptor, &opened) == 0 else { throw AttachmentError.posix() }
          guard opened.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
                WorkspaceFileScope.revision(opened) == WorkspaceFileScope.revision(before) else { throw AttachmentError.unavailable }
          guard opened.st_flags & UInt32(SF_DATALESS) == 0 else { throw AttachmentError.offline }
          var bytes = Data()
          var chunk = [UInt8](repeating: 0, count: 64 * 1024)
          let readDeadline = DispatchTime.now() + WorkspaceFileScope.readTimeout
          while true {
            guard DispatchTime.now().uptimeNanoseconds < readDeadline.uptimeNanoseconds else { throw AttachmentError.unavailable }
            let requested = min(chunk.count, AttachmentScope.maximumImageBytes - bytes.count + 1)
            let count = chunk.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress!, requested) }
            if count < 0 {
              if errno == EINTR { continue }
              throw AttachmentError.posix()
            }
            if count == 0 { break }
            guard count <= AttachmentScope.maximumImageBytes - bytes.count else { throw AttachmentError.tooLarge }
            bytes.append(contentsOf: chunk.prefix(count))
          }
          var after = stat()
          var leaf = stat()
          guard fstat(descriptor, &after) == 0, lstat(selected.path, &leaf) == 0 else { throw AttachmentError.posix() }
          guard WorkspaceFileScope.revision(after) == WorkspaceFileScope.revision(opened),
                WorkspaceFileScope.revision(leaf) == WorkspaceFileScope.revision(opened),
                leaf.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
                leaf.st_flags & UInt32(SF_DATALESS | UF_HIDDEN) == 0,
                Int64(bytes.count) == opened.st_size else { throw AttachmentError.unavailable }
          return bytes
        }
      }
      if let error = coordinationError { throw AttachmentError.classify(error) }
      return try outcome.get()
    }
  }

  private func readClipboardAttachmentImage(result: @escaping FlutterResult) {
    // This is the sole real clipboard access and only runs in the explicit
    // MethodChannel Paste handler above. No string/fileURL read or observer.
    do {
      let pasteboard = NSPasteboard.general
      let generation = pasteboard.changeCount
      let bytes = try AttachmentClipboardImage.read(types: (pasteboard.types ?? []).map(\.rawValue)) {
        pasteboard.data(forType: NSPasteboard.PasteboardType($0))
      }
      guard pasteboard.changeCount == generation else { throw AttachmentError.unavailable }
      guard let bytes else { result(nil); return }
      completeAttachmentImport(result) { try AttachmentImportImage.prepare(bytes, suggestedName: "image") }
    } catch {
      let failure = AttachmentError.classify(error)
      result(FlutterError(code: failure.code, message: failure.localizedDescription, details: nil))
    }
  }
}
#endif

/// Isolate metadata-only directory listing and active-document metadata from
/// potentially blocking content reads, without borrowing any write/transaction
/// queue. Each lane is serial: concurrent requests never materialize body reads
/// in parallel. Bounds include both the running operation and queued operations.
final class WorkspaceReadScheduler {
  enum Kind {
    case body, directory, metadata

    init?(method: String) {
      switch method {
      case "readDocument", "readDocumentBytes": self = .body
      case "listDirectory": self = .directory
      case "readDocumentSyncMetadata": self = .metadata
      default: return nil
      }
    }
  }

  private let body = BoundedWorkspaceReadQueue(label: "work.ianvs.linefold.read-body", qos: .userInitiated, capacity: 8)
  private let directory = BoundedWorkspaceReadQueue(label: "work.ianvs.linefold.read-directory", qos: .userInitiated, capacity: 2)
  private let metadata = BoundedWorkspaceReadQueue(label: "work.ianvs.linefold.sync-metadata", qos: .utility, capacity: 2)

  @discardableResult
  func execute<Value>(kind: Kind, operation: @escaping () throws -> Value,
                      completion: @escaping (Result<Value, Error>) -> Void) -> Bool {
    let queue: BoundedWorkspaceReadQueue
    switch kind {
    case .body: queue = body
    case .directory: queue = directory
    case .metadata: queue = metadata
    }
    return queue.execute(operation: operation, completion: completion)
  }
}

enum WorkspaceReadQueueError: Error, Equatable {
  case busy
}

private final class BoundedWorkspaceReadQueue {
  private let queue: DispatchQueue
  private let capacity: Int
  private let lock = NSLock()
  private var outstanding = 0

  init(label: String, qos: DispatchQoS, capacity: Int) {
    precondition(capacity > 0)
    queue = DispatchQueue(label: label, qos: qos)
    self.capacity = capacity
  }

  /// A Dart timeout/cancellation cannot interrupt arbitrary provider I/O or
  /// guarantee that NSFileCoordinator has returned. Keep that request's budget
  /// until its native operation really exits; reject excess retries immediately
  /// instead of accumulating dispatch blocks behind a stalled provider.
  @discardableResult
  func execute<Value>(operation: @escaping () throws -> Value,
                      completion: @escaping (Result<Value, Error>) -> Void) -> Bool {
    lock.lock()
    guard outstanding < capacity else {
      lock.unlock()
      DispatchQueue.main.async { completion(.failure(WorkspaceReadQueueError.busy)) }
      return false
    }
    outstanding += 1
    lock.unlock()
    queue.async {
      let outcome = self.perform(operation)
      DispatchQueue.main.async { completion(outcome) }
    }
    return true
  }

  private func perform<Value>(_ operation: () throws -> Value) -> Result<Value, Error> {
    // Release on success and throw, before delivering completion so that an
    // immediate retry from the main-thread callback can use the freed slot.
    defer {
      lock.lock()
      outstanding -= 1
      lock.unlock()
    }
    return Result(catching: operation)
  }
}

/// Optional booleans remain absent rather than becoming false. This wire-only
/// projection is separately tested with synthetic observations on native CI.
struct WorkspaceSyncObservation {
  var isUbiquitous: Bool? = nil
  var isUploaded: Bool? = nil
  var isUploading: Bool? = nil
  var isDownloading: Bool? = nil
  var downloadingStatus: URLUbiquitousItemDownloadingStatus? = nil
  var uploadError: String? = nil
  var downloadError: String? = nil
  var hasUnresolvedConflicts: Bool? = nil
  var conflictsAvailable = false
  var conflicts: [[String: Any]] = []

  func dictionary(observedAt: Date) -> [String: Any] {
    var result: [String: Any] = [
      "observedAt": observedAt.timeIntervalSince1970 * 1000,
      "conflictsAvailable": conflictsAvailable, "conflicts": conflicts,
    ]
    if let isUbiquitous { result["isUbiquitous"] = isUbiquitous }
    if let isUploaded { result["isUploaded"] = isUploaded }
    if let isUploading { result["isUploading"] = isUploading }
    if let isDownloading { result["isDownloading"] = isDownloading }
    if let hasUnresolvedConflicts { result["hasUnresolvedConflicts"] = hasUnresolvedConflicts }
    if let uploadError { result["uploadError"] = uploadError }
    if let downloadError { result["downloadError"] = downloadError }
    if downloadingStatus == .current { result["downloadingStatus"] = "current" }
    if downloadingStatus == .downloaded { result["downloadingStatus"] = "downloaded" }
    if downloadingStatus == .notDownloaded { result["downloadingStatus"] = "notDownloaded" }
    return result
  }
}
