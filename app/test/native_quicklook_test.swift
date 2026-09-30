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
      return String(decoding: try MarkdownPreview.html(for: url), as: UTF8.self)
    }

    let source = "# 系统预览\n\n| 项目 | 状态 |\n| --- | --- |\n| Markdown | 正常 |\n\n```mermaid\nflowchart LR\n A[读取文件] --> B[显示预览]\n```\n"
    let html = try preview("中文 空格.md", Data(source.utf8))
    check(html.contains(">系统预览</h1>"), "UTF-8 heading")
    check(html.contains("<table>"), "GFM table")
    check(html.contains("data:image/svg+xml;base64,"), "Real merman SVG")
    let bom = try preview("bom.markdown", Data([0xef, 0xbb, 0xbf]) + Data("# BOM".utf8))
    check(bom.contains(">BOM</h1>"), "UTF-8 BOM")
    let utf16 = try preview("utf16.md", "# UTF-16 中文".data(using: .utf16)!)
    check(utf16.contains(">UTF-16 中文</h1>"), "UTF-16 BOM")
    let crlf = try preview("crlf.md", Data("# CRLF\r\n\r\n正文\r\n".utf8))
    check(crlf.contains(">CRLF</h1>"), "CRLF")
    let empty = try preview("empty.md", Data())
    check(empty.contains("document is empty"), "Empty file notice")
    let large = try preview("large.md", Data(repeating: 65, count: MarkdownPreview.maximumBytes + 1))
    check(large.contains("2 MiB"), "Bounded file read")
    do {
      _ = try preview("invalid.md", Data([0xff, 0x00, 0xff]))
      preconditionFailure("Invalid UTF-8 must report an error")
    } catch { checks += 1 }
    do {
      _ = try MarkdownPreview.html(for: directory.appendingPathComponent("missing.md"))
      preconditionFailure("Missing file must report an error")
    } catch { checks += 1 }
    if CommandLine.arguments.count == 3 {
      let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
      let output = URL(fileURLWithPath: CommandLine.arguments[2])
      try MarkdownPreview.html(for: fixture).write(to: output)
    }
    print("Passed \(checks) native Quick Look checks")
  }
}
