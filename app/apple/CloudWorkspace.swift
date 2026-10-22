import Foundation
import Darwin
import CoreFoundation
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
      guard ["defaultDirectory", "listDirectory", "readDocument", "readDocumentBytes", "writeDocument", "writeDocumentGuarded",
             "listAttachments", "readAttachmentBytes", "normalizeAttachmentPaths"].contains(method) else {
        result(FlutterMethodNotImplemented)
        return
      }
      let workQueue = method == "listAttachments" || method == "readAttachmentBytes" ? self.attachmentQueue : self.queue
      workQueue.async {
        do {
          let value: Any
          if method == "normalizeAttachmentPaths" {
            value = try Self.normalizeAttachmentPaths(arguments["values"])
          } else if method == "defaultDirectory" {
            value = try self.defaultDirectory().path
          } else {
            guard let path = arguments["path"] as? String, path.hasPrefix("/") else {
              if method == "listAttachments" || method == "readAttachmentBytes" {
                throw AttachmentError.invalid
              }
              throw WorkspaceError.invalidPath
            }
            if (method == "listAttachments" || method == "readAttachmentBytes") && path.contains("\0") {
              throw AttachmentError.invalid
            }
            let url = URL(fileURLWithPath: path)
            switch method {
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

// Attachment IO deliberately does not reuse the text reader. A vault root is
// the authority, not a concatenated absolute image URL; every component below
// that root is opened relative to a pinned directory descriptor without links.
extension CloudWorkspace {
  static func normalizeAttachmentPaths(_ value: Any?) throws -> [String] {
    guard let paths = value as? [String], paths.count <= 32,
          paths.allSatisfy({ $0.utf16.count <= 4096 }) else { throw AttachmentError.invalid }
    return paths.map { $0.precomposedStringWithCanonicalMapping.lowercased() }
  }

  static func listAttachments(_ root: URL) throws -> [[String: Any]] {
    do { return try AttachmentScope.withoutMaterialization { try AttachmentScope(root).list() } }
    catch { throw AttachmentError.classify(error) }
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
  case missing, offline, denied, invalid, tooLarge, indexLimit, unavailable

  var code: String {
    switch self {
    case .missing: return "attachment_missing"
    case .offline: return "attachment_offline"
    case .denied: return "attachment_denied"
    case .invalid: return "attachment_invalid"
    case .tooLarge: return "attachment_too_large"
    case .indexLimit: return "attachment_index_limit"
    case .unavailable: return "attachment_unavailable"
    }
  }

  var errorDescription: String? {
    switch self {
    case .missing: return "The attachment is missing."
    case .offline: return "The attachment is not available locally. Download it in iCloud Drive and retry."
    case .denied: return "Permission to read the attachment was denied."
    case .invalid: return "The attachment path or file type is not allowed."
    case .tooLarge: return "The attachment exceeds the permitted size."
    case .indexLimit: return "The vault exceeds attachment indexing limits. No partial index was returned."
    case .unavailable: return "The attachment could not be read. Please retry."
    }
  }

  static func posix(_ code: Int32 = errno) -> AttachmentError {
    switch code {
    case ENOENT: return .missing
    case EACCES, EPERM: return .denied
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

/// Internal to the native bridge, also exercised by the synthetic macOS tests.
final class AttachmentScope {
  static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp"]
  static let maximumImageBytes = 32 * 1024 * 1024
  static let maximumSettingsBytes = 64 * 1024
  static let maximumEntries = 10_000
  static let maximumVisitedEntries = 50_000
  static let maximumDepth = 64
  static let coordinationTimeout: TimeInterval = 5

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
  private let rootDescriptor: Int32
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

  static func components(_ path: String) throws -> [String] {
    guard !path.isEmpty, path.utf16.count <= 4096, !path.hasPrefix("/"),
          !path.contains("\\"), !path.unicodeScalars.contains(where: { $0.value < 32 }), !path.contains(":") else {
      throw AttachmentError.invalid
    }
    let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard components.count <= maximumDepth + 1,
          components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
      throw AttachmentError.invalid
    }
    if path == ".obsidian/app.json" { return components }
    guard !components.contains(where: { $0.hasPrefix(".") }),
          imageExtensions.contains((path as NSString).pathExtension.lowercased()) else {
      throw AttachmentError.invalid
    }
    return components
  }

  private func parentDescriptor(_ components: [String]) throws -> Int32 {
    var current = dup(rootDescriptor)
    guard current >= 0 else { throw AttachmentError.posix() }
    for name in components.dropLast() {
      let next = openat(current, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      let failure = errno
      close(current)
      guard next >= 0 else { throw AttachmentError.posix(failure) }
      current = next
    }
    return current
  }

  private func verifyRootLocation() throws {
    let descriptor = open(rootURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else { throw AttachmentError.posix() }
    defer { close(descriptor) }
    var current = stat()
    guard fstat(descriptor, &current) == 0 else { throw AttachmentError.posix() }
    guard current.st_dev == identity.st_dev, current.st_ino == identity.st_ino else {
      throw AttachmentError.invalid
    }
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
        if name.unicodeScalars.contains(where: { $0.value < 32 }) ||
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
          revision: "\(attributes.st_dev):\(attributes.st_ino):\(attributes.st_size):" +
            "\(attributes.st_mtimespec.tv_sec):\(attributes.st_mtimespec.tv_nsec):" +
            "\(attributes.st_ctimespec.tv_sec):\(attributes.st_ctimespec.tv_nsec)",
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

  private func isPlaceholder(_ components: [String]) throws -> Bool {
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
    guard attributes.st_size <= Int64(limit) else { throw AttachmentError.tooLarge }
    let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(Self.coordinationTimeout * 1_000_000_000)
    var bytes = Data()
    var chunk = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
      guard DispatchTime.now().uptimeNanoseconds < deadline else { throw AttachmentError.unavailable }
      let requested = min(chunk.count, limit - bytes.count + 1)
      let count = chunk.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress!, requested) }
      if count < 0 {
        if errno == EINTR { continue }
        throw AttachmentError.posix()
      }
      if count == 0 { return bytes }
      guard bytes.count + count <= limit else { throw AttachmentError.tooLarge }
      bytes.append(contentsOf: chunk.prefix(count))
    }
  }
}
