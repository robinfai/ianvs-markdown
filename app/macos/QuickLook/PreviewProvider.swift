import Foundation
import QuickLookUI
import UniformTypeIdentifiers

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
  func providePreview(
    for request: QLFilePreviewRequest,
    completionHandler handler: @escaping (QLPreviewReply?, Error?) -> Void
  ) {
    let url = request.fileURL
    let reply = QLPreviewReply(
      dataOfContentType: .html,
      contentSize: CGSize(width: 820, height: 900)
    ) { reply in
      reply.stringEncoding = .utf8
      return try MarkdownPreview.html(for: url)
    }
    handler(reply, nil)
  }
}

// Kept independent of QLFilePreviewRequest so native tests exercise the same
// bounded read, encoding conversion and FFI path used by Finder.
enum MarkdownPreview {
  static let maximumBytes = 2 * 1024 * 1024

  static func html(for url: URL) throws -> Data {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let values = try url.resourceValues(forKeys: [.isRegularFileKey])
    guard values.isRegularFile == true else {
      throw CocoaError(.fileReadUnsupportedScheme)
    }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let bytes = try handle.read(upToCount: maximumBytes + 1) ?? Data()
    if bytes.count > maximumBytes {
      return render(Data(), declaredLength: maximumBytes + 1)
    }
    let text: String?
    if bytes.starts(with: [0xff, 0xfe]) || bytes.starts(with: [0xfe, 0xff]) {
      text = String(data: bytes, encoding: .utf16)
    } else {
      let source = bytes.starts(with: [0xef, 0xbb, 0xbf]) ? bytes.dropFirst(3) : bytes[...]
      text = String(data: source, encoding: .utf8)
    }
    guard let text else { throw CocoaError(.fileReadInapplicableStringEncoding) }
    return render(Data(text.utf8))
  }

  private static func render(_ source: Data, declaredLength: Int? = nil) -> Data {
    source.withUnsafeBytes { bytes in
      let result = linefold_preview_render(
        bytes.bindMemory(to: UInt8.self).baseAddress,
        declaredLength ?? source.count)
      defer { linefold_preview_free(result) }
      return Data(bytes: result.data, count: result.len)
    }
  }
}
