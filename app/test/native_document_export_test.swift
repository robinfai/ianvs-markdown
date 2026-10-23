import AppKit
import CryptoKit
import PDFKit

/// Deliberately withholds the writer handoff on its own operation queue. This
/// exercises real NSFileCoordinator waiting/cancel, not just a mocked gate.
private final class WaitingExportPresenter: NSObject, NSFilePresenter {
  let presentedItemURL: URL?
  let presentedItemOperationQueue = OperationQueue()
  let entered = DispatchSemaphore(value: 0)
  let release = DispatchSemaphore(value: 0)
  init(url: URL) { presentedItemURL = url.resolvingSymlinksInPath(); super.init() }
  func relinquishPresentedItem(toWriter writer: @escaping @Sendable ((@Sendable () -> Void)?) -> Void) {
    entered.signal()
    release.wait()
    writer(nil)
  }
}

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

    phase("Markdown copy, empty copy and source aliases")
    let copy = root.appendingPathComponent("副本.md")
    try DocumentExportFileWriter.write(original, to: copy, format: "md", sourcePath: source.path, expected: nil)
    assert((try? Data(contentsOf: copy)) == original)
    rejects { try DocumentExportFileWriter.write(original, to: source, format: "md", sourcePath: source.path, expected: try ExportDestinationVersion.read(source)) }
    rejects { try DocumentExportFileWriter.validate(copy, format: "md", sourcePath: source.path, protectedPaths: [copy.path]) }
    let markdownAlias = root.appendingPathComponent("hardlink.md")
    try fm.linkItem(at: source, to: markdownAlias)
    rejects { try DocumentExportFileWriter.validate(markdownAlias, format: "md", sourcePath: sourceSymlink.path) }
    let cancelledDestination = root.appendingPathComponent("cancelled-before-write.md")
    rejects { try DocumentExportFileWriter.write(original, to: cancelledDestination, format: "md", sourcePath: source.path, expected: nil, canCommit: { false }) }
    assert(!fm.fileExists(atPath: cancelledDestination.path))
    let blank = root.appendingPathComponent("blank.md")
    try DocumentExportFileWriter.write(Data(), to: blank, format: "md", sourcePath: source.path, expected: nil)
    assert((try? Data(contentsOf: blank))?.isEmpty == true)
    rejects { try DocumentExportFileWriter.validate(root.appendingPathComponent("not-delivered.print"), format: "print", sourcePath: source.path) }
    let oversized = Data(repeating: 65, count: 32 * 1024 * 1024 + 1)
    for format in ["html", "md"] {
      let tooLarge = root.appendingPathComponent("too-large.\(format)")
      rejects { try DocumentExportFileWriter.write(oversized, to: tooLarge, format: format, sourcePath: source.path, expected: nil) }
      assert(!fm.fileExists(atPath: tooLarge.path), "Copy output keeps the existing 32 MiB cap")
    }

    phase("coordination deadline and non-cancellable commit authorization")
    let expired = ExportCoordinationDeadline()
    assert(expired.expire() && expired.didExpire)
    assert(!expired.beginAccessor() && !expired.expire() && expired.needsCancellation)
    expired.finish()
    assert(!expired.needsCancellation && expired.didExpire)
    let writing = ExportCoordinationDeadline()
    assert(writing.beginAccessor())
    assert(!writing.expire() && !writing.didExpire && !writing.beginAccessor())
    let finished = ExportCoordinationDeadline()
    finished.finish()
    assert(!finished.expire() && !finished.beginAccessor())
    var committedResults = [Result<Bool, Error>]()
    let commitState = PendingDocumentExport(id: "commit-authorized") { committedResults.append($0) }
    commitState.awaitApproval(seconds: 5)
    assert(commitState.acceptApproval())
    commitState.beginCommit()
    assert(!commitState.cancelBeforeCommit() && committedResults.isEmpty)
    commitState.finish(.success(true))
    assert(committedResults.count == 1 && (try? committedResults[0].get()) == true)
    assert(!commitState.cancelBeforeCommit() && committedResults.count == 1)

    phase("real blocked file presenter coordination expires without a write")
    let contested = root.appendingPathComponent("contested.md")
    try original.write(to: contested)
    let contestedVersion = try ExportDestinationVersion.read(contested)
    let presenter = WaitingExportPresenter(url: contested)
    NSFileCoordinator.addFilePresenter(presenter)
    do {
      defer {
        presenter.release.signal()
        NSFileCoordinator.removeFilePresenter(presenter)
      }
      do {
        try DocumentExportFileWriter.write(Data("must not replace".utf8), to: contested,
          format: "md", sourcePath: source.path, expected: contestedVersion, coordinationTimeout: 2)
        fatalError("Blocked coordination must fail closed at its deadline")
      } catch let error as DocumentExportError {
        assert(error.message.contains("Timed out waiting for access"))
      }
      assert(presenter.entered.wait(timeout: .now()) == .success, "The actual presenter handoff must have blocked")
      assert((try? Data(contentsOf: contested)) == original)
    }
    presenter.presentedItemOperationQueue.waitUntilAllOperationsAreFinished()
    assert((try? Data(contentsOf: contested)) == original, "No late accessor may write after cancellation")

    phase("native destination cancellation, single completion and unavailable commands")
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
    var choices = 0
    var selection: ((URL?) -> Void)?
    let coordinator = DocumentExportCoordinator(window: window, pickDestination: { _, _, _, selected in
      choices += 1
      selection = selected
      return {}
    }, approveCommit: { _, approved in approved(true) })
    let arguments: [String: Any] = ["operationId": "basic", "content": "# Unsaved 中文😀\r\n", "title": "原稿.md", "sourcePath": source.path, "protectedPaths": [source.path]]
    var results = [Result<Bool, Error>]()
    coordinator.perform("markdown", arguments: arguments) { results.append($0) }
    assert(choices == 1 && results.isEmpty)
    coordinator.perform("html", arguments: arguments) { results.append($0) }
    assert(choices == 1 && results.count == 1 && (try? results[0].get()) == nil)
    selection?(nil)
    assert(results.count == 2 && (try? results[1].get()) == false)
    selection?(copy) // A late duplicate selection cannot write or complete twice.
    assert(results.count == 2 && (try? Data(contentsOf: copy)) == original)
    for unsupported in ["print", "share"] {
      coordinator.perform(unsupported, arguments: arguments) { results.append($0) }
    }
    assert(choices == 1 && results.count == 4)
    assert((try? results[2].get()) == nil && (try? results[3].get()) == nil)
    coordinator.perform("markdown", arguments: arguments) { results.append($0) }
    selection?(source)
    assert(results.count == 5 && (try? results[4].get()) == nil)
    coordinator.perform("markdown", arguments: arguments) { results.append($0) }
    let chosen = root.appendingPathComponent("chosen.md")
    selection?(chosen)
    assert(results.count == 6 && (try? results[5].get()) == true)
    assert((try? String(contentsOf: chosen, encoding: .utf8)) == arguments["content"] as? String)

    phase("scope approval, cancellation identity, timeout and late callbacks")
    var approve: ((Bool) -> Void)?
    var approvals = 0
    var dismissals = 0
    var guardedResults = [Result<Bool, Error>]()
    let guarded = DocumentExportCoordinator(window: window, approvalTimeout: 0.02,
      pickDestination: { _, _, _, selected in
        selection = selected
        return { dismissals += 1 }
      }, approveCommit: { _, reply in approvals += 1; approve = reply })
    func start(_ id: String) {
      var payload = arguments
      payload["operationId"] = id
      guarded.perform("markdown", arguments: payload) { guardedResults.append($0) }
    }
    func cancel(_ id: String, expected: Bool = true) {
      guarded.perform("cancel", arguments: ["operationId": id]) { value in assert((try? value.get()) == expected) }
    }
    let deferred = root.appendingPathComponent("deferred.md")
    start("first")
    selection?(deferred)
    selection?(copy)
    assert(approvals == 1 && !fm.fileExists(atPath: deferred.path), "Selection must not write before final approval")
    let oldApproval = approve
    cancel("first")
    assert(dismissals == 1 && guardedResults.count == 1 && (try? guardedResults[0].get()) == false)
    oldApproval?(true)
    assert(!fm.fileExists(atPath: deferred.path))
    start("second")
    cancel("first", expected: false) // A delayed cancellation must not dismiss the new panel.
    oldApproval?(true)
    assert(dismissals == 1 && guardedResults.count == 1)
    selection?(deferred)
    let outsider = Data("new destination from another writer".utf8)
    try outsider.write(to: deferred)
    approve?(true)
    assert(guardedResults.count == 2 && (try? guardedResults[1].get()) == nil)
    assert((try? Data(contentsOf: deferred)) == outsider, "Approval await must preserve expected destination version")
    let denied = root.appendingPathComponent("denied-approval.md")
    start("denied")
    selection?(denied)
    approve?(false)
    assert(guardedResults.count == 3 && (try? guardedResults[2].get()) == false)
    assert(!fm.fileExists(atPath: denied.path))
    start("timeout")
    selection?(denied)
    let lateTimeout = approve
    let deadline = Date().addingTimeInterval(2)
    while guardedResults.count < 4 && Date() < deadline {
      RunLoop.main.run(until: Date().addingTimeInterval(0.005))
    }
    assert(guardedResults.count == 4 && (try? guardedResults[3].get()) == nil)
    lateTimeout?(true)
    assert(!fm.fileExists(atPath: denied.path) && guardedResults.count == 4)
    start("after-timeout")
    selection?(denied)
    lateTimeout?(true)
    assert(guardedResults.count == 4)
    approve?(true)
    assert(guardedResults.count == 5 && (try? guardedResults[4].get()) == true)

    phase("production HTML and Markdown fixture round-trip")
    guard CommandLine.arguments.count == 4 else { fatalError("Expected generated HTML, Markdown and evidence folder") }
    let evidence = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
    try fm.createDirectory(at: evidence, withIntermediateDirectories: true)
    for (argument, format) in [(1, "html"), (2, "md")] {
      let fixture = URL(fileURLWithPath: CommandLine.arguments[argument])
      let input = try Data(contentsOf: fixture)
      let exported = evidence.appendingPathComponent("document.\(format)")
      try DocumentExportFileWriter.write(input, to: exported, format: format, sourcePath: fixture.path,
        expected: try ExportDestinationVersion.read(exported))
      let actual = try Data(contentsOf: exported)
      assert(SHA256.hash(data: actual) == SHA256.hash(data: input))
      assert((try? String(contentsOf: exported, encoding: .utf8))?.contains("CELL_149_D") == true)
    }
    phase("PDF lifecycle, lease and final-approval safety")
    try NativePDFExportSafetyTests.run(window: window)

    phase("offline production HTML through native PDF export")
    let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
    let output = evidence.appendingPathComponent("pagination.pdf")
    let productionHTML = try String(contentsOf: fixture, encoding: .utf8)
    assert(productionHTML.contains("data:image/png;base64,"), "Fixture must include the authorized synthetic attachment")
    window.makeKeyAndOrderFront(nil)
    var pdfSelections = 0
    var pdfApprovals = 0
    var outcome: Result<Bool, Error>?
    let pdfCoordinator = DocumentExportCoordinator(window: window,
      pickDestination: { _, _, format, selected in
        assert(format == "pdf")
        pdfSelections += 1
        selected(output)
        return {}
      }, approveCommit: { id, approved in
        assert(id == "production-pdf")
        pdfApprovals += 1
        approved(true)
      })
    pdfCoordinator.perform("pdf", arguments: [
      "operationId": "production-pdf", "content": productionHTML,
      "title": "pagination.md", "sourcePath": fixture.path,
      "protectedPaths": [fixture.path, CommandLine.arguments[2]],
    ]) { result in
      assert(Thread.isMainThread, "Native PDF completion must return to the main actor")
      assert(outcome == nil, "Native PDF export completes exactly once")
      outcome = result
    }
    // Keep the existing 90-second native bound inside the 120-second watchdog.
    let pdfDeadline = Date().addingTimeInterval(90)
    while outcome == nil && Date() < pdfDeadline {
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    withExtendedLifetime(pdfCoordinator) {}
    guard let outcome else { fatalError("Native PDF generation exceeded 90 seconds") }
    guard try outcome.get() else { fatalError("Native PDF generation was cancelled") }
    assert(pdfSelections == 1 && pdfApprovals == 1)
    phase("practical PDF content, page geometry, image and all-page evidence")
    try PracticalPDFEvidence.validate(output: output, evidence: evidence)

    let finalSourceHash = SHA256.hash(data: try Data(contentsOf: source))
    assert(finalSourceHash == originalHash)
    print("PASS: exact HTML/Markdown UTF-8 copies, source hash, empty Markdown, cancellation/once-only completion, unsupported Print/share, practical paged PDF evidence, explicit replacement, racing collision, hard-link/symlink, permissions and offline placeholders.")
    window.orderOut(nil)
  }
}

/// Native acceptance gates geometry, selectable CJK, actual image resources and
/// safety. The mandatory independent pypdf stage gates exact original content;
/// PDFKit extraction order and header/marker counts remain unmodified diagnostics.
/// It does not normalize Unicode or assign a fabricated fidelity percentage.
private enum PracticalPDFEvidence {
  @MainActor
  static func validate(output: URL, evidence: URL) throws {
    guard let pdf = PDFDocument(url: output) else {
      throw DocumentExportError(message: "Native PDF output is not readable")
    }
    let text = pdf.string ?? ""
    try text.write(to: evidence.appendingPathComponent("pagination.txt"), atomically: true, encoding: .utf8)
    // Bound evidence work before per-page scans/thumbnails. A failed layout
    // must not turn the production 256-page ceiling into 256 large screenshots.
    guard (3...30).contains(pdf.pageCount) else {
      let message = "Expected 3...30 finite A4 pages, got \(pdf.pageCount)"
      let report: [String: Any] = ["automatedChecksPassed": false,
        "pageCount": pdf.pageCount, "failures": [message],
        "rawText": "pagination.txt", "visualReview": "not performed; page-count limit exceeded",
        "screenshotsWritten": 0]
      try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        .write(to: evidence.appendingPathComponent("practical-pdf-report.json"))
      throw DocumentExportError(message: message)
    }
    // Layout-only whitespace removal can rejoin narrow table-cell lines. Never
    // apply NFKC, alter Chinese mappings, rewrite source, or fix extracted text.
    let compact = text.filter { !$0.isWhitespace }
    let markerPattern = try NSRegularExpression(pattern: "CELL_[0-9]+_[A-D]")
    let compactNSString = compact as NSString
    var markerCounts = [String: Int]()
    for match in markerPattern.matches(in: compact, range: NSRange(location: 0, length: compactNSString.length)) {
      markerCounts[compactNSString.substring(with: match.range), default: 0] += 1
    }
    var missing = [String]()
    var duplicates = [String: Int]()
    let expectedMarkers = Set((0..<150).flatMap { row in ["A", "B", "C", "D"].map { "CELL_\(row)_\($0)" } })
    for marker in expectedMarkers.sorted() {
      let count = markerCounts[marker, default: 0]
      if count == 0 { missing.append(marker) }
      if count > 1 { duplicates[marker] = count }
    }
    let unexpected = Set(markerCounts.keys).subtracting(expectedMarkers).sorted()
    let cjkCharacters = text.unicodeScalars.filter {
      (0x3400...0x4DBF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value)
        || (0xF900...0xFAFF).contains($0.value) || (0x20000...0x3134F).contains($0.value)
    }.count
    let codeRuns = compact.components(separatedBy: "ABCDEFGHIJKLMNOPQRSTUVWXYZ").count - 1
    var failures = [String]()
    if cjkCharacters < 300 { failures.append("PDF must retain substantial selectable Chinese text, not raster-only pages") }

    var pages = [[String: Any]]()
    var imageResources = [[String: Any]]()
    var tablePages = [Int]()
    var missingHeaderPages = [Int]()
    var totalOutOfBounds = 0
    for index in 0..<pdf.pageCount {
      guard let page = pdf.page(at: index) else {
        failures.append("Missing PDF page \(index + 1)")
        continue
      }
      let bounds = page.bounds(for: .mediaBox)
      let finitePage = [bounds.minX, bounds.minY, bounds.width, bounds.height].allSatisfy { $0.isFinite }
      let isA4 = finitePage && abs(bounds.width - 595.276) < 2 && abs(bounds.height - 841.89) < 2
      if !isA4 { failures.append("Page \(index + 1) is not finite A4") }
      let pageText = page.string ?? ""
      let pageCompact = pageText.filter { !$0.isWhitespace }
      let hasTable = pageCompact.contains("CELL_")
      let headers = ["HEADER_ONE", "HEADER_TWO", "HEADER_THREE", "HEADER_FOUR"].allSatisfy { pageCompact.contains($0) }
      if hasTable {
        tablePages.append(index + 1)
        if !headers { missingHeaderPages.append(index + 1) }
      }
      var outOfBounds = 0
      var badBounds = [[String: Any]]()
      for character in 0..<page.numberOfCharacters {
        let rectangle = page.characterBounds(at: character)
        if rectangle.isEmpty || rectangle.isNull { continue }
        let finite = [rectangle.minX, rectangle.minY, rectangle.maxX, rectangle.maxY].allSatisfy { $0.isFinite }
        let inside = finite && rectangle.minX >= bounds.minX - 2 && rectangle.maxX <= bounds.maxX + 2
          && rectangle.minY >= bounds.minY - 2 && rectangle.maxY <= bounds.maxY + 2
        if !inside {
          outOfBounds += 1
          if badBounds.count < 12 {
            badBounds.append(["character": character, "rectangle": NSStringFromRect(rectangle)])
          }
        }
      }
      totalOutOfBounds += outOfBounds
      let scanner = PDFImageResourceScanner(pageNumber: index + 1)
      if let pageRef = page.pageRef, let dictionary = pageRef.dictionary {
        scanner.scan(dictionary, depth: 0)
      }
      imageResources.append(contentsOf: scanner.images)

      // Use the established PDFKit thumbnail path on every page. The former
      // font-diagnostic drawing helper is intentionally not used here.
      let image = page.thumbnail(of: NSSize(width: 840, height: 1188), for: .mediaBox)
      let screenshot = "page-\(index + 1).png"
      if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
         let png = bitmap.representation(using: .png, properties: [:]) {
        try png.write(to: evidence.appendingPathComponent(screenshot))
      } else {
        failures.append("Could not save PDFKit thumbnail for page \(index + 1)")
      }
      pages.append([
        "page": index + 1, "mediaBox": NSStringFromRect(bounds), "finiteA4": isA4,
        "selectableCharacters": page.numberOfCharacters, "pdfkitObservedTableMarker": hasTable,
        "pdfkitObservedAllFourHeaders": headers, "offPaperCharacterCount": outOfBounds,
        "offPaperExamples": badBounds, "screenshot": screenshot,
      ])
    }
    if totalOutOfBounds != 0 { failures.append("Text character bounds must not leave the page horizontally or vertically") }
    // A generic >=64-pixel image could be a rasterized emoji. Require the exact
    // synthetic attachment dimensions; screenshots still verify its four colors.
    let recognizableImages = imageResources.filter {
      ($0["width"] as? Int ?? 0) == 192 && ($0["height"] as? Int ?? 0) == 128
    }
    if recognizableImages.isEmpty { failures.append("PDF must contain the actual 192 x 128 synthetic raster image resource, not an emoji or 1-pixel placeholder") }
    let exactChineseTitle = text.contains("中文文档")
    let exactChineseEnd = text.contains("文档结束")
    let knownLimitations = [
      "Chinese font ToUnicode mappings can vary by macOS/WebKit. Exact original Chinese phrase extraction is diagnostic, not a hard gate; substantial selectable CJK and all-page visual review remain required.",
      "PDFKit can reorder underscores and other characters during text extraction. Its observed marker/header counts do not prove content is missing: even visually present first-page headers may not match the extracted strings. Original PDFKit text is preserved; the mandatory independent pypdf stage checks all 600 cells, 35 code runs and boundaries without Unicode normalization or reordering.",
      "Viewer-dependent text extraction and reading order remain limitations. Passing an independent content checker does not fix Preview copy/search behavior, which this test has not manually verified. Repeated table headers may still appear only on the first page; inspect all-page screenshots.",
      "All PDFKit page thumbnails must be visually reviewed for readable Chinese, complete last-column content, wrapped code and the recognizable four-color attachment. Automated checks do not establish a numerical fidelity score.",
      "Print and sharing remain unsupported. The sandbox printing permission is only for the native PDF backend.",
    ]
    let pdfkitDiagnostics: [String: Any] = [
      "extractor": "PDFKit", "rawText": "pagination.txt", "contentGate": false,
      "comparisonAdjustment": "Whitespace removal only; no Unicode normalization or character reordering",
      "expectedTableCells": 600, "observedTableCellOccurrences": markerCounts.values.reduce(0, +),
      "markersNotMatchedInExtraction": missing, "duplicateMarkerMatches": duplicates,
      "unexpectedMarkerMatches": unexpected, "longCodeRuns": codeRuns,
      "cjkStartMatched": compact.contains("CJKSTART"), "cjkEndMatched": compact.contains("CJKEND"),
      "codeEndMatched": compact.contains("CODE_END"), "imageStartMatched": compact.contains("IMAGE_START"),
      "imageEndMatched": compact.contains("IMAGE_END"),
      "exactChineseTitleExtracts": exactChineseTitle, "exactChineseEndExtracts": exactChineseEnd,
      "pagesWithTableMarkerMatches": tablePages, "tablePagesWithoutAllHeaderMatches": missingHeaderPages,
    ]
    let report: [String: Any] = [
      "standard": "Practical PDF fidelity with complete content and unchanged safety gates",
      "automatedChecksPassed": failures.isEmpty, "hardGateScope": "Native geometry, selectable CJK, actual image resource and safety only",
      "independentContentCheck": "Mandatory pypdf stage runs after this native test; see practical-pdf-content-report.json",
      "visualReview": "required; not performed by this test",
      "failures": failures, "pdf": "pagination.pdf", "rawText": "pagination.txt",
      "pageCount": pdf.pageCount, "selectableCjkCharacters": cjkCharacters,
      "pdfkitObservedDiagnostics": pdfkitDiagnostics,
      "offPaperCharacterCount": totalOutOfBounds, "imageResources": imageResources,
      "syntheticImageWidth": 192, "syntheticImageHeight": 128,
      "matchingSyntheticImageResources": recognizableImages.count,
      "pages": pages, "knownLimitations": knownLimitations,
      "strictFixtureHistory": "6a571f906d40a496ccb96c940b57d41831735068",
    ]
    let json = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    try json.write(to: evidence.appendingPathComponent("practical-pdf-report.json"))
    let summary = """
    Practical native PDF acceptance
    Native geometry/selectable-CJK/image checks: \(failures.isEmpty ? "PASS" : "FAIL")
    Mandatory independent pypdf content stage still required; this native result does not certify all 600 cells.
    Pages: \(pdf.pageCount), selectable CJK characters: \(cjkCharacters), synthetic-size image resources (192 x 128): \(recognizableImages.count)
    PDFKit observed diagnostics only: cell matches \(markerCounts.values.reduce(0, +))/600; long-code matches \(codeRuns)/35
    Exact Chinese title/end extraction (diagnostic): \(exactChineseTitle)/\(exactChineseEnd)
    PDFKit table pages without all header matches (diagnostic, not proof headers are absent): \(missingHeaderPages)
    Off-paper characters: \(totalOutOfBounds)
    Visual review is still required for every page-*.png and attachment-pattern.png in the parent folder.
    No fidelity percentage has been calculated or claimed.

    \(knownLimitations.joined(separator: "\n\n"))

    Failures: \(failures.isEmpty ? "none" : failures.joined(separator: "; "))
    """
    try summary.write(to: evidence.appendingPathComponent("practical-pdf-report.txt"), atomically: true, encoding: .utf8)
    if !failures.isEmpty { throw DocumentExportError(message: failures.joined(separator: "; ")) }
    print("PASS (native stage): \(pdf.pageCount) A4 pages, selectable CJK, actual image resource and all-page evidence; mandatory independent content checks and visual review remain required.")
  }
}

/// Check actual PDF XObjects, including images nested in Form resources. Image
/// dimensions alone do not establish appearance; every rendered page is saved.
private final class PDFImageResourceScanner {
  let pageNumber: Int
  var images = [[String: Any]]()
  init(pageNumber: Int) { self.pageNumber = pageNumber }

  func scan(_ dictionary: CGPDFDictionaryRef, depth: Int) {
    guard depth < 16 else { return }
    var resources: CGPDFDictionaryRef?
    var objects: CGPDFDictionaryRef?
    guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources,
          CGPDFDictionaryGetDictionary(resources, "XObject", &objects), let objects else { return }
    let context = PDFImageResourceContext(scanner: self, depth: depth)
    CGPDFDictionaryApplyFunction(objects, { name, object, info in
      guard let info else { return }
      let context = Unmanaged<PDFImageResourceContext>.fromOpaque(info).takeUnretainedValue()
      var stream: CGPDFStreamRef?
      guard CGPDFObjectGetValue(object, .stream, &stream), let stream else { return }
      guard let dictionary = CGPDFStreamGetDictionary(stream) else { return }
      var subtype: UnsafePointer<CChar>?
      guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype else { return }
      switch String(cString: subtype) {
      case "Image":
        var width: CGPDFInteger = 0
        var height: CGPDFInteger = 0
        guard CGPDFDictionaryGetInteger(dictionary, "Width", &width),
              CGPDFDictionaryGetInteger(dictionary, "Height", &height) else { return }
        context.scanner.images.append([
          "page": context.scanner.pageNumber, "name": String(cString: name),
          "width": width, "height": height,
        ])
      case "Form":
        context.scanner.scan(dictionary, depth: context.depth + 1)
      default: break
      }
    }, Unmanaged.passUnretained(context).toOpaque())
    withExtendedLifetime(context) {}
  }
}

private final class PDFImageResourceContext {
  let scanner: PDFImageResourceScanner
  let depth: Int
  init(scanner: PDFImageResourceScanner, depth: Int) { self.scanner = scanner; self.depth = depth }
}
