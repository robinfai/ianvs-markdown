import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testChineseDiagramGlyphsOnThisDevice() throws {
    let framework = try XCTUnwrap(Bundle.main.privateFrameworksURL)
      .appendingPathComponent("ianvs_svg.framework/ianvs_svg")
    let handle = try XCTUnwrap(dlopen(framework.path, RTLD_NOW))
    defer { dlclose(handle) }
    typealias Environment = @convention(c) () -> UnsafeMutablePointer<CChar>?
    typealias Preprocess = @convention(c) (UnsafePointer<UInt8>, Int, Int) -> UnsafeMutablePointer<CChar>?
    typealias Free = @convention(c) (UnsafeMutablePointer<CChar>) -> Void
    let environment = unsafeBitCast(try XCTUnwrap(dlsym(handle, "ianvs_svg_environment")), to: Environment.self)
    let preprocess = unsafeBitCast(try XCTUnwrap(dlsym(handle, "ianvs_svg_preprocess")), to: Preprocess.self)
    let release = unsafeBitCast(try XCTUnwrap(dlsym(handle, "ianvs_svg_free")), to: Free.self)
    let info = try XCTUnwrap(environment())
    defer { release(info) }
    print("Mermaid font environment: \(String(cString: info))")
    XCTAssertTrue(String(cString: info).contains("font-policy/2"))
    XCTAssertTrue(String(cString: info).contains("Noto Sans CJK SC"))
    var outlines = Set<String>()
    for character in "分享文档阅读预览" {
      let svg = Array("<svg xmlns='http://www.w3.org/2000/svg' width='60' height='60'><text font-family='sans-serif' font-size='20' x='5' y='30'>\(character)</text></svg>".utf8)
      let response = try svg.withUnsafeBufferPointer { buffer in
        try XCTUnwrap(preprocess(buffer.baseAddress!, buffer.count, 1024 * 1024))
      }
      defer { release(response) }
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(String(cString: response).utf8)) as? [String: Any])
      XCTAssertNil(json["error"], "\(json)")
      let outline = try XCTUnwrap(json["svg"] as? String)
      XCTAssertTrue(outline.contains("<path"), "Missing \(character): \(outline); fonts: \(String(cString: info))")
      outlines.insert(outline)
    }
    // LastResort previously returned identical question-mark boxes for 閱/读/预/览.
    XCTAssertEqual(outlines.count, 8, "Every label character needs its own real outline")
  }

  func testWorkspaceListsCloudStubsAndCoordinatesDocumentIO() throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: root) }
    try Data().write(to: root.appendingPathComponent(".云端.md.icloud"))
    try Data().write(to: root.appendingPathComponent(".recent.json"))
    let document = root.appendingPathComponent("sub/本地.md")
    try CloudWorkspace.write(document, contents: "# 阅读预览")
    XCTAssertEqual(try CloudWorkspace.read(document, maximumBytes: 1024), "# 阅读预览")
    let list = try CloudWorkspace.list(root, recursive: true)
    XCTAssertEqual(Set(list.compactMap { $0["name"] as? String }), ["云端.md", "本地.md"])
    XCTAssertThrowsError(try CloudWorkspace.read(document, maximumBytes: 2))
  }

  func testImportedDocumentSurvivesSourceRemovalAndDuplicateNames() throws {
    let manager = FileManager.default
    let temporary = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: temporary) }
    let importer = MarkdownImporter(documentsDirectory: temporary.appendingPathComponent("Library"))
    let source = temporary.appendingPathComponent("分享 文档.md")
    let contents = Data("# iOS 分享\n\n正文".utf8)
    try contents.write(to: source)
    let first = try importer.importFile(at: source)
    let second = try importer.importFile(at: source)
    XCTAssertNotEqual(first, second)
    XCTAssertEqual(first.lastPathComponent, source.lastPathComponent)
    try manager.removeItem(at: source)
    XCTAssertEqual(try Data(contentsOf: first), contents)
    XCTAssertEqual(try Data(contentsOf: second), contents)
    XCTAssertEqual(try importer.importFile(at: first), first)
  }

}
