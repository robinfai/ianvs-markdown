import Foundation

@main
enum QuickLookTests {
  static func main() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("linefold-quicklook-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    var checks = 0

    func check(_ condition: @autoclosure () -> Bool, _ message: String) {
      precondition(condition(), message)
      checks += 1
    }

    func preview(_ name: String, _ data: Data) throws -> String {
      let url = directory.appendingPathComponent(name)
      try data.write(to: url)
      return try MarkdownPreview.source(for: url)
    }

    let source = "# 系统预览\n\n| 项目 | 状态 |\n| --- | --- |\n| Markdown | 正常 |\n\n```mermaid\nflowchart LR\n A[读取文件] --> B[显示预览]\n```\n"
    let html = try preview("中文 空格.md", Data(source.utf8))
    check(html.contains("# 系统预览"), "UTF-8 heading")
    check(html.contains("| Markdown | 正常 |"), "GFM table")
    check(html.contains("```mermaid"), "Real merman SVG")
    let bom = try preview("bom.markdown", Data([0xef, 0xbb, 0xbf]) + Data("# BOM".utf8))
    check(bom == "# BOM", "UTF-8 BOM")
    let utf16 = try preview("utf16.md", "# UTF-16 中文".data(using: .utf16)!)
    check(utf16 == "# UTF-16 中文", "UTF-16 BOM")
    let crlf = try preview("crlf.md", Data("# CRLF\r\n\r\n正文\r\n".utf8))
    check(crlf.contains("# CRLF\r\n"), "CRLF")
    let empty = try preview("empty.md", Data())
    check(empty.isEmpty, "Empty file notice")
    do {
      _ = try preview("large.md", Data(repeating: 65, count: MarkdownPreview.maximumBytes + 1))
      preconditionFailure("Oversized files must fail")
    } catch { checks += 1 }
    do {
      _ = try preview("invalid.md", Data([0xff, 0x00, 0xff]))
      preconditionFailure("Invalid UTF-8 must report an error")
    } catch { checks += 1 }
    do {
      _ = try MarkdownPreview.source(for: directory.appendingPathComponent("missing.md"))
      preconditionFailure("Missing file must report an error")
    } catch { checks += 1 }
    let document = directory.appendingPathComponent("document.md")
    let image = directory.appendingPathComponent("image.png")
    try Data([1, 2, 3]).write(to: image)
    check(MarkdownPreview.imageData("image.png", documentURL: document) == Data([1, 2, 3]), "Relative image")
    check(MarkdownPreview.imageData("https://example.com/image.png", documentURL: document) == nil, "No remote image")
    check(MarkdownPreview.imageData(image.absoluteString, documentURL: document) == nil, "No absolute file URL")
    check(MarkdownPreview.imageData("../image.png", documentURL: document) == nil, "No parent traversal")
    let link = directory.appendingPathComponent("escape.png")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
    check(MarkdownPreview.imageData("escape.png", documentURL: document) == nil, "No symlink escape")
    if CommandLine.arguments.count == 3 {
      let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
      let output = URL(fileURLWithPath: CommandLine.arguments[2])
      try MarkdownPreview.source(for: fixture).write(to: output, atomically: true, encoding: .utf8)
    }
    print("Passed \(checks) native Quick Look checks")
  }
}
