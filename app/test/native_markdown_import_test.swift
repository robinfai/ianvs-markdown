import Foundation

@main
struct MarkdownImportTests {
  static func main() throws {
    let manager = FileManager.default
    let temporary = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: temporary) }
    let importer = MarkdownImporter(documentsDirectory: temporary.appendingPathComponent("Documents"))
    let source = temporary.appendingPathComponent("中文 分享.MD")
    let original = Data("\u{FEFF}# Shared\n\n中文内容".utf8)
    try original.write(to: source)
    let first = try importer.importFile(at: source)
    let second = try importer.importFile(at: source)
    precondition(first != second, "Same-named imports must not overwrite")
    precondition(first.lastPathComponent == source.lastPathComponent)
    let saved = try Data(contentsOf: first)
    let untouched = try Data(contentsOf: source)
    precondition(saved == original && untouched == original)
    let reopened = try importer.importFile(at: first)
    precondition(reopened == first, "Opening an app-owned copy must not import it twice")
    try manager.removeItem(at: source)
    precondition(manager.fileExists(atPath: first.path), "Imported copy must outlive its source")

    for (name, bytes) in [
      ("wrong.pdf", Data("# Nope".utf8)),
      ("invalid.md", Data([0xff, 0xfe])),
      ("binary.md", Data([0, 1, 2])),
      ("oversize.md", Data(repeating: 65, count: MarkdownImporter.maximumBytes + 1)),
    ] {
      let url = temporary.appendingPathComponent(name)
      try bytes.write(to: url)
      do {
        _ = try importer.importFile(at: url)
        preconditionFailure("Unexpectedly imported \(name)")
      } catch is MarkdownImportError {}
    }
    let empty = temporary.appendingPathComponent("empty.markdown")
    try Data().write(to: empty)
    let emptyCopy = try importer.importFile(at: empty)
    let emptyBytes = try Data(contentsOf: emptyCopy)
    precondition(emptyBytes.isEmpty)
    let imports = try manager.contentsOfDirectory(at: importer.root, includingPropertiesForKeys: nil)
    precondition(imports.count == 3, "Rejected files must not leave imported copies")
    print("Markdown import tests passed: copies, ownership, filenames, encoding, size, empty files")
  }
}
