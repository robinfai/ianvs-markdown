import Foundation
import Darwin

enum MarkdownImportError: LocalizedError {
  case unsupported, tooLarge, invalidText, unavailable

  var errorDescription: String? {
    switch self {
    case .unsupported: return "请选择 Markdown 或纯文本文件。"
    case .tooLarge: return "文档超过 5 MB，暂时无法预览。"
    case .invalidText: return "无法读取文档，请使用 UTF-8 编码的 Markdown 文件。"
    case .unavailable: return "文件暂时不可用，请先下载文件后重试。"
    }
  }
}

/// Copy while the provider's security scope is held. Dart only receives stable
/// app-owned URLs, never an Inbox or file-provider URL with expiring access.
final class MarkdownImporter {
  static let extensions: Set<String> = ["md", "markdown", "mdown", "mkd", "txt"]
  static let maximumBytes = 5 * 1024 * 1024
  let root: URL

  init(documentsDirectory: URL) {
    root = documentsDirectory.appendingPathComponent("Imports", isDirectory: true)
  }

  func importFile(at source: URL) throws -> URL {
    guard source.isFileURL,
          Self.extensions.contains(source.pathExtension.lowercased()) else {
      throw MarkdownImportError.unsupported
    }
    let scoped = source.startAccessingSecurityScopedResource()
    defer { if scoped { source.stopAccessingSecurityScopedResource() } }
    var coordinationError: NSError?
    var outcome: Result<URL, Error> = .failure(MarkdownImportError.unavailable)
    NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { url in
      outcome = Result { try self.copyValidatedFile(at: url) }
    }
    if let coordinationError { throw coordinationError }
    return try outcome.get()
  }

  // Match the native workspace grant's F_GETPATH spelling, including system
  // /var aliases. Foundation's resolvingSymlinksInPath may preserve that alias.
  // Canonicalize only the already-open file and app-owned Imports directory;
  // never broaden Dart's lexical workspace fence or scan a source's parent.
  private func canonicalOwnedURL(for descriptor: Int32) throws -> URL? {
    let rootDescriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
    guard rootDescriptor >= 0 else {
      if errno == ENOENT { return nil } // No Imports directory before first copy.
      throw MarkdownImportError.unavailable
    }
    defer { close(rootDescriptor) }

    func path(_ descriptor: Int32) throws -> String {
      var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
      guard fcntl(descriptor, F_GETPATH, &buffer) == 0,
            let result = String(validatingUTF8: buffer) else {
        throw MarkdownImportError.unavailable
      }
      return result
    }
    let canonicalRoot = try path(rootDescriptor)
    let canonicalFile = try path(descriptor)
    guard Data(canonicalFile.utf8).starts(with: Data((canonicalRoot + "/").utf8)) else {
      return nil
    }
    var heldRoot = stat(), namedRoot = stat(), heldFile = stat(), namedFile = stat()
    guard fstat(rootDescriptor, &heldRoot) == 0, lstat(root.path, &namedRoot) == 0,
          fstat(descriptor, &heldFile) == 0, lstat(canonicalFile, &namedFile) == 0,
          heldRoot.st_dev == namedRoot.st_dev, heldRoot.st_ino == namedRoot.st_ino,
          (namedRoot.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
          heldFile.st_dev == namedFile.st_dev, heldFile.st_ino == namedFile.st_ino,
          (namedFile.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
      throw MarkdownImportError.unavailable
    }
    return URL(fileURLWithPath: canonicalFile)
  }

  private func copyValidatedFile(at source: URL) throws -> URL {
    let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    guard values.isRegularFile == true else { throw MarkdownImportError.unsupported }
    guard (values.fileSize ?? 0) <= Self.maximumBytes else { throw MarkdownImportError.tooLarge }
    let handle = try FileHandle(forReadingFrom: source)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: Self.maximumBytes + 1) ?? Data()
    guard data.count <= Self.maximumBytes else { throw MarkdownImportError.tooLarge }
    guard String(data: data, encoding: .utf8) != nil, !data.contains(0) else {
      throw MarkdownImportError.invalidText
    }
    let manager = FileManager.default
    if let owned = try canonicalOwnedURL(for: handle.fileDescriptor) {
      return owned
    }
    // A directory per import preserves names without overwriting an earlier
    // document from another app that happens to have the same filename.
    let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    let destination = directory.appendingPathComponent(source.lastPathComponent)
    do {
      var coordinationError: NSError?
      var writeError: Error?
      NSFileCoordinator().coordinate(writingItemAt: destination, options: .forReplacing, error: &coordinationError) { url in
        do { try data.write(to: url, options: .atomic) }
        catch { writeError = error }
      }
      if let coordinationError { throw coordinationError }
      if let writeError { throw writeError }
      let copied = try FileHandle(forReadingFrom: destination)
      defer { try? copied.close() }
      guard let owned = try canonicalOwnedURL(for: copied.fileDescriptor) else {
        throw MarkdownImportError.unavailable
      }
      return owned
    } catch {
      try? manager.removeItem(at: directory)
      throw error
    }
  }
}
