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
      guard ["defaultDirectory", "listDirectory", "readDocument", "writeDocument"].contains(method) else {
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
            default:
              guard let contents = arguments["contents"] as? String else { throw WorkspaceError.invalidPath }
              try Self.write(url, contents: contents)
              value = true
            }
          }
          DispatchQueue.main.async { result(value) }
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
        guard let text = String(data: data, encoding: .utf8), !data.contains(0) else { throw WorkspaceError.invalidText }
        return text
      }
    }
    if let coordinationError { throw coordinationError }
    return try outcome.get()
  }

  static func write(_ url: URL, contents: String) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var coordinationError: NSError?
    var writeError: Error?
    NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinated in
      do { try Data(contents.utf8).write(to: coordinated, options: .atomic) }
      catch { writeError = error }
    }
    if let coordinationError { throw coordinationError }
    if let writeError { throw writeError }
  }
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
