import Foundation

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
    let sourcePath = source.resolvingSymlinksInPath().path
    let rootPath = root.resolvingSymlinksInPath().path + "/"
    if sourcePath.hasPrefix(rootPath) {
      return source
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
      return destination
    } catch {
      try? manager.removeItem(at: directory)
      throw error
    }
  }
}
