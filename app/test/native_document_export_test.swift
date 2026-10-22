import AppKit
import CryptoKit
import PDFKit

@main
struct NativeDocumentExportAcceptance {
  @MainActor
  static func main() throws {
    func phase(_ name: String) {
      FileHandle.standardOutput.write(Data("PHASE: \(name)\n".utf8))
    }
    phase("destination safety and source preservation")
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("linefold-export-tests-\(UUID().uuidString)")
    try fm.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: root) }
    let source = root.appendingPathComponent("原稿.md")
    let original = Data("# 原稿\r\n\nUnchanged 😀".utf8)
    try original.write(to: source)
    let originalHash = SHA256.hash(data: original)
    func rejects(_ body: () throws -> Void) {
      do { try body(); fatalError("Expected operation to be rejected") } catch { }
    }
    let html = root.appendingPathComponent("文档.html")
    let bytes = Data("<!doctype html><p>中文</p>".utf8)
    try DocumentExportFileWriter.write(bytes, to: html, format: "html", sourcePath: source.path, expected: nil)
    rejects { try DocumentExportFileWriter.write(bytes, to: html, format: "html", sourcePath: source.path, expected: nil) }
    rejects { try DocumentExportFileWriter.validate(html, format: "html", sourcePath: source.path, protectedPaths: [html.path]) }
    let approved = try ExportDestinationVersion.read(html)
    try DocumentExportFileWriter.write(Data("replacement".utf8), to: html, format: "html", sourcePath: source.path, expected: approved)
    rejects { try DocumentExportFileWriter.write(bytes, to: html, format: "html", sourcePath: source.path, expected: approved) }
    rejects { try DocumentExportFileWriter.write(bytes, to: source, format: "html", sourcePath: source.path, expected: nil) }
    let alias = root.appendingPathComponent("alias.html")
    try fm.linkItem(at: source, to: alias)
    rejects { try DocumentExportFileWriter.validate(alias, format: "html", sourcePath: source.path) }
    let symlink = root.appendingPathComponent("link.html")
    try fm.createSymbolicLink(at: symlink, withDestinationURL: source)
    rejects { try DocumentExportFileWriter.validate(symlink, format: "html", sourcePath: source.path) }
    let sourceSymlink = root.appendingPathComponent("source-alias.md")
    try fm.createSymbolicLink(at: sourceSymlink, withDestinationURL: source)
    rejects { try DocumentExportFileWriter.validate(alias, format: "html", sourcePath: sourceSymlink.path) }
    let missing = root.appendingPathComponent("missing-parent/file.html")
    rejects { try DocumentExportFileWriter.write(bytes, to: missing, format: "html", sourcePath: source.path, expected: nil) }
    let protected = root.appendingPathComponent("protected", isDirectory: true)
    try fm.createDirectory(at: protected, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o500])
    rejects { try DocumentExportFileWriter.write(bytes, to: protected.appendingPathComponent("denied.html"), format: "html", sourcePath: source.path, expected: nil) }
    try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: protected.path)
    let cloud = root.appendingPathComponent("offline.html")
    try Data().write(to: root.appendingPathComponent(".offline.html.icloud"))
    rejects { _ = try ExportDestinationVersion.read(cloud) }
    let sourceHash = SHA256.hash(data: try Data(contentsOf: source))
    assert(sourceHash == originalHash)

    guard CommandLine.arguments.count == 3 else { fatalError("Expected generated HTML fixture and evidence folder") }
    let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
    let evidence = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    try fm.createDirectory(at: evidence, withIntermediateDirectories: true)
    let output = evidence.appendingPathComponent("pagination.pdf")
    if fm.fileExists(atPath: output.path) { try fm.removeItem(at: output) }
    phase("AppKit acceptance window startup")
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
    window.makeKeyAndOrderFront(nil)
    func spin(seconds: TimeInterval, until done: () -> Bool = { false }) {
      let deadline = Date().addingTimeInterval(seconds)
      while !done() && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.005))
      }
    }
    phase("lifecycle deadlines and once-only cleanup")
    var callbacks = 0
    var cancellations = 0
    var results = [Result<Bool, Error>]()
    let loading = DocumentExportLifecycle(loadingTimeout: 0.01, outputTimeout: 0.01,
      cancelOutput: { cancellations += 1 }) { callbacks += 1; results.append($0) }
    spin(seconds: 2, until: { !loading.isActive })
    assert(!loading.isActive && callbacks == 1 && cancellations == 0)
    assert((try? results.last!.get()) == nil)
    loading.finish(.success(true))
    assert(callbacks == 1, "Late load completion must be ignored")
    let timedOutput = DocumentExportLifecycle(loadingTimeout: 2, outputTimeout: 0.01,
      cancelOutput: { cancellations += 1 }) { callbacks += 1; results.append($0) }
    timedOutput.beginPrinting(interactive: false)
    spin(seconds: 2, until: { !timedOutput.isActive })
    assert(!timedOutput.isActive && callbacks == 2 && cancellations == 1)
    assert((try? results.last!.get()) == nil)
    timedOutput.finish(.success(true))
    assert(callbacks == 2, "Late PDF completion cannot publish or complete twice")
    let interactive = DocumentExportLifecycle(loadingTimeout: 0.01, outputTimeout: 0.01,
      cancelOutput: { cancellations += 1 }) { callbacks += 1; results.append($0) }
    interactive.beginPrinting(interactive: true)
    spin(seconds: 0.05)
    assert(interactive.isActive && callbacks == 2 && cancellations == 1,
      "A user's print-panel choice has no automatic timeout")
    interactive.finish(.success(false))
    assert(callbacks == 3 && (try? results.last!.get()) == false)

    var loadingCleanups = 0
    var loadingCallbacks = 0
    var loadingJob: OfflineDocumentPrintJob? = OfflineDocumentPrintJob(
      loadingTimeout: 0.01, compileRules: { _, _ in /* Deliberately no callback. */ })
    weak var releasedLoadingJob = loadingJob
    let loadingTemporary = root.appendingPathComponent("loading-timeout", isDirectory: true)
    try fm.createDirectory(at: loadingTemporary, withIntermediateDirectories: false)
    loadingJob!.run(html: "<p>synthetic</p>", window: window,
      pdfDestination: loadingTemporary.appendingPathComponent("unused.pdf"), terminalCleanup: {
        loadingCleanups += 1
        try? fm.removeItem(at: loadingTemporary)
      }) { result in
        assert((try? result.get()) == nil)
        loadingCallbacks += 1
        loadingJob = nil // Same ownership release as DocumentExportCoordinator.
      }
    spin(seconds: 2, until: { loadingCallbacks == 1 })
    assert(loadingCallbacks == 1 && loadingCleanups == 1 && releasedLoadingJob == nil,
      "Loading timeout must hold the job through terminal cleanup exactly once")
    assert(!fm.fileExists(atPath: loadingTemporary.path))

    phase("offline WebKit rendering and native paged PDF")
    let job = OfflineDocumentPrintJob()
    var outcome: Result<Bool, Error>?
    job.run(html: try String(contentsOf: fixture, encoding: .utf8), window: window, pdfDestination: output) { outcome = $0 }
    let deadline = Date().addingTimeInterval(90)
    while outcome == nil && Date() < deadline {
      RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    guard let outcome else { fatalError("Native PDF generation exceeded 90 seconds") }
    guard try outcome.get() else { fatalError("Native PDF generation was cancelled") }
    phase("PDF page geometry, selectable Chinese and table-cell validation")
    guard let pdf = PDFDocument(url: output), pdf.pageCount >= 3 else { fatalError("Expected real multi-page PDF") }
    let text = pdf.string ?? ""
    assert(text.contains("中文文档"), "Chinese must be selectable text, not a screenshot")
    assert(text.contains("CJK START") && text.contains("CJK END"))
    assert(text.contains("CODE_END"), "Long wrapped code must reach the end")
    var tablePages = 0
    for index in 0..<pdf.pageCount {
      guard let page = pdf.page(at: index) else { fatalError("Missing PDF page") }
      let bounds = page.bounds(for: .mediaBox)
      assert(abs(bounds.width - 595.276) < 2 && abs(bounds.height - 841.89) < 2, "PDF must use A4 pages, not one tall capture")
      let pageText = page.string ?? ""
      if pageText.contains("CELL_") {
        tablePages += 1
        assert(pageText.contains("HEADER_ONE") && pageText.contains("HEADER_FOUR"), "Every table page repeats its header")
      }
      for character in 0..<page.numberOfCharacters {
        let rectangle = page.characterBounds(at: character)
        if rectangle.isEmpty || rectangle.isNull { continue }
        assert(rectangle.minX >= -1 && rectangle.maxX <= bounds.width + 1, "Text must not clip horizontally")
      }
      if index == 0 || index == pdf.pageCount - 1 {
        let image = page.thumbnail(of: NSSize(width: 840, height: 1188), for: .mediaBox)
        if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
          try png.write(to: evidence.appendingPathComponent("page-\(index + 1).png"))
        }
      }
    }
    assert(tablePages >= 3)
    // All columns of all rows survive pagination. Normalize whitespace only,
    // because PDF extraction can introduce line breaks in narrow columns.
    let compact = text.filter { !$0.isWhitespace }
    for row in 0..<150 {
      for column in ["A", "B", "C", "D"] {
        assert(compact.contains("CELL_\(row)_\(column)"), "Missing table cell \(row) \(column)")
      }
    }
    try text.write(to: evidence.appendingPathComponent("pagination.txt"), atomically: true, encoding: .utf8)
    let finalSourceHash = SHA256.hash(data: try Data(contentsOf: source))
    assert(finalSourceHash == originalHash)
    print("PASS: source hash, explicit replacement, racing collision, hard-link/symlink, permissions, offline cloud; \(pdf.pageCount) A4 PDF pages, selectable Chinese, 600 table cells, repeated table headers and wrapped code.")
    window.orderOut(nil)
  }
}
