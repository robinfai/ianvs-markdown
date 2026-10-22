import Foundation
import Darwin

@main
struct MarkdownImportTests {
  static func main() throws {
    let manager = FileManager.default
    let temporary = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: temporary) }
    let importer = MarkdownImporter(documentsDirectory: temporary.appendingPathComponent("Documents"))
    let source = temporary.appendingPathComponent("中文 分享.MD")
    let original = Data("\u{FEFF}# Shared\r\n\r\n中文 📝 ![图](../图片/照片.png)\r\n".utf8)
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
    // Real ancestor symlinks exercise the same identity/spelling distinction as
    // Apple's /var alias, without depending on the runner's temporary URL form.
    let alias = temporary.appendingPathComponent("ancestor-alias")
    try manager.createSymbolicLink(at: alias, withDestinationURL: temporary)
    let aliasDocuments = alias.appendingPathComponent("Documents")
    let aliasImporter = MarkdownImporter(documentsDirectory: aliasDocuments)
    let canonicalRoot = try canonicalPath(importer.root)
    let ownedAlias = aliasDocuments.appendingPathComponent("Imports")
      .appendingPathComponent(first.deletingLastPathComponent().lastPathComponent)
      .appendingPathComponent(first.lastPathComponent)
    let reopenedAlias = try aliasImporter.importFile(at: ownedAlias)
    precondition(Data(reopenedAlias.path.utf8) == Data(first.path.utf8),
                 "Already-owned alias must return the same canonical file, not a duplicate")
    try assertSameIdentity(ownedAlias, reopenedAlias)
    let afterReopen = try manager.contentsOfDirectory(at: importer.root, includingPropertiesForKeys: nil)
    precondition(afterReopen.count == 2)
    let copiedFromAliasRoot = try aliasImporter.importFile(at: source)
    for url in [first, second, reopenedAlias, copiedFromAliasRoot] {
      let expected = URL(fileURLWithPath: canonicalRoot)
        .appendingPathComponent(url.deletingLastPathComponent().lastPathComponent)
        .appendingPathComponent(source.lastPathComponent)
      precondition(Data(url.path.utf8) == Data(expected.path.utf8),
                   "Every import return must share the native-selected canonical root spelling")
      let copiedBytes = try Data(contentsOf: url)
      precondition(copiedBytes == original, "Canonicalization must preserve source bytes and attachment paths")
    }
    let stillUntouched = try Data(contentsOf: source)
    precondition(stillUntouched == original)
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
    precondition(imports.count == 4, "Rejected files must not leave imported copies")
    print("Markdown import tests passed: copies, canonical ownership and alias identity, filenames, exact source bytes, size, empty files")
  }

  static func canonicalPath(_ url: URL) throws -> String {
    let descriptor = open(url.path, O_RDONLY | O_CLOEXEC)
    precondition(descriptor >= 0)
    defer { close(descriptor) }
    var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    precondition(fcntl(descriptor, F_GETPATH, &path) == 0)
    return String(cString: path)
  }

  static func assertSameIdentity(_ first: URL, _ second: URL) throws {
    let a = try FileManager.default.attributesOfItem(atPath: first.path)
    let b = try FileManager.default.attributesOfItem(atPath: second.path)
    for key in [FileAttributeKey.systemNumber, .systemFileNumber] {
      guard let left = a[key] as? NSNumber, let right = b[key] as? NSNumber else {
        preconditionFailure("Expected filesystem identity")
      }
      precondition(left == right, "Owned import must retain the original inode")
    }
  }
}
