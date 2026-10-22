import Foundation
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
      guard ["defaultDirectory", "listDirectory", "readDocument", "readDocumentBytes", "writeDocument", "writeDocumentGuarded"].contains(method) else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.queue.async {
        do {
          let value: Any
          if method == "defaultDirectory" {
            value = try self.defaultDirectory().path
          } else {
            guard let path = arguments["path"] as? String, path.hasPrefix("/") else {
              throw WorkspaceError.invalidPath
            }
            let url = URL(fileURLWithPath: path)
            switch method {
            case "listDirectory":
              value = try Self.list(url, recursive: arguments["recursive"] as? Bool ?? false)
            case "readDocument":
              value = try Self.read(url, maximumBytes: arguments["maximumBytes"] as? Int)
            case "readDocumentBytes":
              let contents = try Self.read(url, maximumBytes: arguments["maximumBytes"] as? Int)
              value = FlutterStandardTypedData(bytes: Data(contents.utf8))
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
    if (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true {
      try FileManager.default.startDownloadingUbiquitousItem(at: url)
    }
    // A modification claim needs the old bytes, unlike a replacement-only
    // claim, so iCloud can materialize the existing document for validation.
    try coordinatedWrite(url, contents: contents, options: []) { coordinated in
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
    var writeError: Error?
    NSFileCoordinator().coordinate(writingItemAt: url, options: options, error: &coordinationError) { coordinated in
      do {
        try validate?(coordinated)
        try Data(contents.utf8).write(to: coordinated, options: .atomic)
      }
      catch { writeError = error }
    }
    if let coordinationError { throw coordinationError }
    if let writeError { throw writeError }
  }

  private static func currentContents(_ url: URL) throws -> String? {
    do {
      let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
      guard values.isRegularFile == true, values.isSymbolicLink != true else { throw WorkspaceError.invalidPath }
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
