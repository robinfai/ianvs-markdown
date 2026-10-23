import AppKit
import CoreText
import CryptoKit
import PDFKit

/// Synthetic, test-only diagnostic. Does not open user notes or a SavePanel.
@main
struct NativePDFFontDiagnostic {
  struct Failure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
  }
  struct Candidate {
    let id: String
    let family: String
    let regularName: String
    let boldName: String
    let regular: CTFont
    let bold: CTFont
    let evidence: [String: Any]
  }
  struct Probe {
    let id: String
    let text: String
    let element: String
    let allowLayoutLineBreaks: Bool
    var start: String { "BEGIN_\(id)_" }
    var end: String { "_END_\(id)" }
    var full: String { start + text + end }
  }

  static let families = [
    ("pingfang", "PingFang SC"),
    ("heiti", "Heiti SC"),
    ("songti", "Songti SC"),
  ]
  static let coverage = "文⽂长⻓中文文档代码ABCDEFGHIJKLMNOPQRSTUVWXYZ_0123456789 "

  static func phase(_ value: String) {
    FileHandle.standardOutput.write(Data("PHASE: \(value)\n".utf8))
  }
  static func writeJSON(_ value: Any, to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    guard data.count <= 2 * 1024 * 1024 else { throw Failure(message: "JSON evidence budget exceeded") }
    try data.write(to: url, options: .withoutOverwriting)
  }
  static func attribute(_ descriptor: CTFontDescriptor, _ name: CFString) -> Any? {
    CTFontDescriptorCopyAttribute(descriptor, name)
  }
  static func name(_ descriptor: CTFontDescriptor, _ key: CFString) -> String? {
    attribute(descriptor, key) as? String
  }
  static func flag(_ descriptor: CTFontDescriptor, _ key: CFString) -> Bool? {
    (attribute(descriptor, key) as? NSNumber)?.boolValue
  }
  static func weight(_ descriptor: CTFontDescriptor) -> Double? {
    let traits = attribute(descriptor, kCTFontTraitsAttribute) as? [String: Any]
    return (traits?[kCTFontWeightTrait as String] as? NSNumber)?.doubleValue
  }
  static func symbolicTraits(_ descriptor: CTFontDescriptor) -> UInt32? {
    let traits = attribute(descriptor, kCTFontTraitsAttribute) as? [String: Any]
    return (traits?[kCTFontSymbolicTrait as String] as? NSNumber)?.uint32Value
  }
  static func isItalic(_ descriptor: CTFontDescriptor) -> Bool? {
    guard let value = symbolicTraits(descriptor) else { return nil }
    return value & CTFontSymbolicTraits.traitItalic.rawValue != 0
  }
  static func isBold(_ descriptor: CTFontDescriptor) -> Bool? {
    guard let value = symbolicTraits(descriptor) else { return nil }
    return value & CTFontSymbolicTraits.traitBold.rawValue != 0
  }
  static func scalarStrings(_ value: String) -> [String] {
    value.unicodeScalars.map { String(format: "U+%04X", $0.value) }
  }
  static func glyphs(_ font: CTFont, _ value: String) -> [CGGlyph] {
    let units = Array(value.utf16)
    var result = [CGGlyph](repeating: 0, count: units.count)
    units.withUnsafeBufferPointer { input in
      result.withUnsafeMutableBufferPointer { output in
        _ = CTFontGetGlyphsForCharacters(font, input.baseAddress!, output.baseAddress!, units.count)
      }
    }
    return result
  }

  /// macOS 13 is a diagnostic prerequisite, not a changed app deployment target.
  /// The options affect these CT calls only, never WK's own fallback service.
  @available(macOS 13.0, *)
  static func inventory() throws -> ([Candidate], [String: Any]) {
    phase("enumerate existing system fonts without name probing")
    guard let names = CTFontManagerCopyAvailablePostScriptNames() as? [String],
          let urls = CTFontManagerCopyAvailableFontURLs() as? [URL] else {
      throw Failure(message: "Available-font census returned an unexpected bridge type")
    }
    let availableNames = Set(names)
    let availableURLs = Set(urls.filter {
      $0.isFileURL && $0.standardizedFileURL.path.hasPrefix("/System/Library/Fonts/")
    }.map { $0.resolvingSymlinksInPath().standardizedFileURL })
    let options = [kCTFontCollectionDisallowAutoActivationOption: true] as CFDictionary
    let collection = CTFontCollectionCreateFromAvailableFonts(options)
    guard let rawDescriptors = CTFontCollectionCreateMatchingFontDescriptors(collection),
          let descriptors = rawDescriptors as? [CTFontDescriptor] else {
      throw Failure(message: "Available-font descriptor census is absent or has an unexpected type")
    }
    var records = [[String: Any]]()
    var selected = [Candidate]()
    var cachedData = [URL: Data]()
    var readBytes = 0
    let fm = FileManager.default

    func makeFont(_ descriptor: CTFontDescriptor) throws -> (CTFont, [String: Any]) {
      guard let ps = name(descriptor, kCTFontNameAttribute), availableNames.contains(ps),
            let url = attribute(descriptor, kCTFontURLAttribute) as? URL else {
        throw Failure(message: "Available font has no stable local identity")
      }
      guard url.isFileURL, url.standardizedFileURL.path.hasPrefix("/System/Library/Fonts/") else {
        throw Failure(message: "Candidate is not a local system-font path")
      }
      let local = url.resolvingSymlinksInPath().standardizedFileURL
      guard local.isFileURL, local.path.hasPrefix("/System/Library/Fonts/"),
            availableURLs.contains(local), fm.fileExists(atPath: local.path),
            flag(descriptor, kCTFontEnabledAttribute) == true,
            flag(descriptor, kCTFontDownloadableAttribute) == false else {
        throw Failure(message: "Font availability is unknown, disabled, downloadable, or not a system file")
      }
      let data: Data
      if let cached = cachedData[local] {
        data = cached
      } else {
        let values = try local.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize,
              size > 0, size <= 64 * 1024 * 1024, readBytes + size <= 128 * 1024 * 1024 else {
          throw Failure(message: "Local font file exceeds diagnostic input budget")
        }
        data = try Data(contentsOf: local)
        guard data.count == size else { throw Failure(message: "System font changed while reading") }
        readBytes += data.count
        cachedData[local] = data
      }
      // Data-backed descriptors are not registered. Preserve the exact face of a
      // TTC/OTC; never reconstruct a descriptor from a guessed family name.
      guard let fromData = CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor] else {
        throw Failure(message: "System font data has no readable descriptor array")
      }
      guard let exact = fromData.first(where: { name($0, kCTFontNameAttribute) == ps }) else {
        throw Failure(message: "Font collection does not contain the inventoried face")
      }
      let font = CTFontCreateWithFontDescriptorAndOptions(exact, 14, nil,
        [.preventAutoActivation, .preventAutoDownload])
      guard CTFontCopyPostScriptName(font) as String == ps,
            CTFontCopyFamilyName(font) as String == name(descriptor, kCTFontFamilyNameAttribute),
            let expectedTraits = symbolicTraits(descriptor),
            CTFontGetSymbolicTraits(font).rawValue == expectedTraits else {
        throw Failure(message: "CoreText substituted a different face or symbolic traits")
      }
      let createdTraits = CTFontCopyTraits(font) as NSDictionary
      guard let createdWeight = createdTraits[kCTFontWeightTrait] as? NSNumber,
            let expectedWeight = weight(descriptor),
            abs(createdWeight.doubleValue - expectedWeight) < 0.001 else {
        throw Failure(message: "CoreText reference-face weight changed")
      }
      if let variations = attribute(descriptor, kCTFontVariationAttribute) as? NSDictionary, variations.count > 0 {
        throw Failure(message: "Variable-font coordinate instances are outside this minimal diagnostic")
      }
      let mapping = glyphs(font, coverage)
      guard !mapping.contains(0) else { throw Failure(message: "Face lacks required diagnostic glyphs") }
      return (font, [
        "postScriptName": ps,
        "systemFile": local.lastPathComponent,
        "fileSHA256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
        "fileBytes": data.count,
        "inventoryEnabled": true,
        "inventoryDownloadable": false,
        "inventoryDownloaded": flag(descriptor, kCTFontDownloadedAttribute) as Any? ?? NSNull(),
        "dataDescriptorRegistered": false,
        "options": ["preventAutoActivation", "preventAutoDownload"],
        "radicalScalars": scalarStrings("文⽂长⻓"),
        "radicalGIDs": glyphs(font, "文⽂长⻓").map(Int.init),
        "weight": weight(descriptor) as Any? ?? NSNull(),
        "symbolicTraits": symbolicTraits(descriptor) as Any? ?? NSNull(),
        "role": "Inventoried preflight reference face, not a prediction of WK CSS face selection",
        "mappingScope": "Basic CT mapping only; not shaping, fallback, or WK font proof",
      ])
    }

    for (id, family) in families {
      let matching = descriptors.filter {
        guard name($0, kCTFontFamilyNameAttribute) == family,
              let url = attribute($0, kCTFontURLAttribute) as? URL else { return false }
        return url.isFileURL && url.standardizedFileURL.path.hasPrefix("/System/Library/Fonts/")
      }
      var record: [String: Any] = ["id": id, "family": family, "availableFaces": matching.count]
      do {
        guard matching.count <= 64 else { throw Failure(message: "Unexpected family inventory size") }
        record["inventoryFaces"] = matching.map { descriptor -> [String: Any] in
          ["postScriptName": name(descriptor, kCTFontNameAttribute) as Any? ?? NSNull(),
           "enabled": flag(descriptor, kCTFontEnabledAttribute) as Any? ?? NSNull(),
           "downloadable": flag(descriptor, kCTFontDownloadableAttribute) as Any? ?? NSNull(),
           "weight": weight(descriptor) as Any? ?? NSNull(),
           "italic": isItalic(descriptor) as Any? ?? NSNull(), "bold": isBold(descriptor) as Any? ?? NSNull(),
           "fileName": (attribute(descriptor, kCTFontURLAttribute) as? URL)?.lastPathComponent as Any? ?? NSNull()]
        }.sorted { ($0["postScriptName"] as? String ?? "") < ($1["postScriptName"] as? String ?? "") }

        let eligible = matching.filter {
          flag($0, kCTFontEnabledAttribute) == true &&
          flag($0, kCTFontDownloadableAttribute) == false && weight($0) != nil && isItalic($0) == false && isBold($0) != nil
        }
        guard let regular = eligible.filter({ isBold($0) == false })
          .sorted(by: {
            let left = abs(weight($0)!), right = abs(weight($1)!)
            return left == right ? (name($0, kCTFontNameAttribute) ?? "") < (name($1, kCTFontNameAttribute) ?? "") : left < right
          }).first,
          let bold = eligible.filter({ isBold($0) == true })
          .sorted(by: {
            let left = abs(weight($0)! - 0.4), right = abs(weight($1)! - 0.4)
            return left == right ? (name($0, kCTFontNameAttribute) ?? "") < (name($1, kCTFontNameAttribute) ?? "") : left < right
          }).first else {
          throw Failure(message: "No known local non-bold/bold reference pair; no activation attempted")
        }
        let (regularFont, regularEvidence) = try makeFont(regular)
        let (boldFont, boldEvidence) = try makeFont(bold)
        let regularName = CTFontCopyPostScriptName(regularFont) as String
        let boldName = CTFontCopyPostScriptName(boldFont) as String
        record["status"] = "selected"
        record["regular"] = regularEvidence
        record["bold"] = boldEvidence
        selected.append(Candidate(id: id, family: family, regularName: regularName,
          boldName: boldName, regular: regularFont, bold: boldFont, evidence: record))
      } catch {
        record["status"] = "unavailable"
        record["reason"] = error.localizedDescription
      }
      records.append(record)
    }
    return (selected, [
      "schema": 1,
      "os": ProcessInfo.processInfo.operatingSystemVersionString,
      "minimumDiagnosticOS": "macOS 13 (preventAutoDownload availability)",
      "candidates": records,
      "selectedCount": selected.count,
      "maxFamilies": 3,
      "maxPreflightFaces": 6,
      "fontBytesRead": readBytes,
      "wkBoundary": "Own CT options do not govern WK lookup or system fallback. No download, registration, activation, or security-setting API is requested by this fixture.",
    ])
  }

  static func probes(order: String) throws -> [Probe] {
    let text: String
    switch order {
    case "forward": text = "文⽂长⻓"
    case "reverse": text = "⽂文⻓长"
    case "mixed": text = "文文⽂⽂长长⻓⻓"
    default: throw Failure(message: "Unknown synthetic corpus order")
    }
    return [
      Probe(id: "BODY", text: text, element: "p", allowLayoutLineBreaks: false),
      Probe(id: "TITLE", text: "中文文档" + text, element: "h2", allowLayoutLineBreaks: false),
      Probe(id: "CODE", text: text, element: "pre", allowLayoutLineBreaks: false),
      Probe(id: "TABLE", text: text, element: "table", allowLayoutLineBreaks: false),
      Probe(id: "LONGCODE", text: String(repeating: "长代码 ABCDEFGHIJKLMNOPQRSTUVWXYZ ", count: 35),
        element: "pre", allowLayoutLineBreaks: true),
    ]
  }
  static func escaped(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&#39;")
  }
  static func html(family: String, probes: [Probe]) -> String {
    // family is selected from the fixed, inventoried allowlist. No generic or
    // absent fallback names, external font URL, font-face, or document script.
    let body = probes.map { probe in
      let value = escaped(probe.full)
      if probe.element == "table" { return "<table><tbody><tr><td>\(value)</td></tr></tbody></table>" }
      return "<\(probe.element)>\(value)</\(probe.element)>"
    }.joined(separator: "\n")
    return """
    <!doctype html><html lang="und"><head><meta charset="utf-8">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; font-src 'none'; img-src 'none'; connect-src 'none'; base-uri 'none'; form-action 'none'">
    <style>@page{size:A4;margin:18mm}*{box-sizing:border-box}body{margin:0;color:#111;background:#fff;font-family:'\(escaped(family))';font-size:14px;font-weight:400;line-height:1.4}h2{font-family:inherit;font-size:18px;font-weight:700}pre{font-family:inherit;font-size:13px;font-weight:400;white-space:pre-wrap;overflow-wrap:anywhere;word-break:break-all}table{width:100%;table-layout:fixed;border-collapse:collapse}td{border:1px solid #777;padding:4px;font-family:inherit;font-size:14px}</style></head><body>\(body)</body></html>
    """
  }

  @MainActor
  @available(macOS 13.0, *)
  static func runCase(id: String, order: String, root: URL) throws -> Bool {
    let (available, census) = try inventory()
    try writeJSON(census, to: root.appendingPathComponent("inventory.json"))
    guard let candidate = available.first(where: { $0.id == id }) else {
      throw Failure(message: "Requested candidate is not an audited available system family")
    }
    let probes = try probes(order: order)
    let source = html(family: candidate.family, probes: probes)
    let data = Data(source.utf8)
    try data.write(to: root.appendingPathComponent("input.html"), options: .withoutOverwriting)
    phase("load and print \(id) / \(order)")
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 900),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.makeKeyAndOrderFront(nil)
    defer { window.orderOut(nil) }
    let output = root.appendingPathComponent("output.pdf")
    var outcome: Result<Bool, Error>?
    let job = OfflineDocumentPrintJob(loadingTimeout: 20, outputTimeout: 60)
    job.run(html: source, window: window, pdfDestination: output) { outcome = $0 }
    let deadline = Date().addingTimeInterval(85)
    while outcome == nil && Date() < deadline {
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    guard let outcome, try outcome.get() else { throw Failure(message: "Native PDF did not finish successfully") }
    phase("inspect actual PDF and compare original Unicode")
    let observed = try PDFFontEvidence.inspect(output,
      evidenceDirectory: root.appendingPathComponent("pdf-evidence", isDirectory: true))
    guard let pdf = PDFDocument(url: output), pdf.pageCount == 1 else {
      throw Failure(message: "Tiny corpus must produce exactly one real page")
    }
    let text = pdf.string ?? ""
    try Data(text.utf8).write(to: root.appendingPathComponent("pdfkit.txt"), options: .withoutOverwriting)
    var comparisons = [[String: Any]]()
    var allMatch = true
    var previousMarkerEnd = text.startIndex
    for probe in probes {
      let starts = text.components(separatedBy: probe.start)
      let ends = text.components(separatedBy: probe.end)
      var record: [String: Any] = [
        "id": probe.id, "expected": probe.text,
        "expectedScalars": scalarStrings(probe.text),
        "allowOnlyExtractionLineBreaks": probe.allowLayoutLineBreaks,
      ]
      if starts.count == 2, ends.count == 2,
         let start = text.range(of: probe.start),
         let end = text.range(of: probe.end, range: start.upperBound..<text.endIndex),
         start.lowerBound >= previousMarkerEnd {
        previousMarkerEnd = end.upperBound
        let raw = String(text[start.upperBound..<end.lowerBound])
        // The original source LONGCODE line has no LF/CR and preserves every space: only renderer-added line breaks may
        // be ignored for that explicitly identified probe. Never normalize Unicode.
        let actual = probe.allowLayoutLineBreaks
          ? raw.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "") : raw
        let matches = actual.unicodeScalars.elementsEqual(probe.text.unicodeScalars)
        record["rawExtracted"] = raw
        record["actualScalars"] = scalarStrings(actual)
        record["matches"] = matches
        allMatch = allMatch && matches
      } else {
        record["matches"] = false
        record["reason"] = "Missing, duplicated or reordered marker"
        allMatch = false
      }
      comparisons.append(record)
    }
    let page = pdf.page(at: 0)!
    let bounds = page.bounds(for: .mediaBox)
    var geometryOK = abs(bounds.width - 595.276) < 2 && abs(bounds.height - 841.89) < 2
    for index in 0..<page.numberOfCharacters {
      let box = page.characterBounds(at: index)
      if box.isEmpty || box.isNull { continue }
      if !box.minX.isFinite || !box.minY.isFinite || !box.maxX.isFinite || !box.maxY.isFinite ||
        box.minX < -1 || box.minY < -1 || box.maxX > bounds.width + 1 || box.maxY > bounds.height + 1 {
        geometryOK = false
      }
    }
    let result: [String: Any] = [
      "schema": 1, "id": id, "order": order, "font": candidate.evidence,
      "inputSHA256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
      "comparisons": comparisons, "geometryOK": geometryOK,
      "strictUnicodePassed": allMatch, "passed": allMatch && geometryOK,
      "pdfEvidence": observed,
      "visualReview": "pending; a machine text pass is not visual acceptance",
      "independentExtractor": "pending; PDFKit is not an independent cross-check",
      "scope": "Synthetic font diagnostic only; original multi-page header and full PDF/Print gates remain unresolved",
    ]
    try writeJSON(result, to: root.appendingPathComponent("result.json"))
    phase(allMatch && geometryOK ? "diagnostic text/geometry passed; visual review pending" : "FAIL: strict Unicode or geometry mismatch")
    return allMatch && geometryOK
  }

  @MainActor
  static func main() {
    do {
      guard #available(macOS 13.0, *) else {
        throw Failure(message: "Diagnostic requires macOS 13 preventAutoDownload; app support is unchanged")
      }
      let args = CommandLine.arguments
      guard args.count == 3 || args.count == 5 else { throw Failure(message: "Expected --inventory ROOT or --case ID ORDER ROOT") }
      let root = URL(fileURLWithPath: args.last!, isDirectory: true)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
      if args.count == 3, args[1] == "--inventory" {
        let (selected, census) = try inventory()
        try writeJSON(census, to: root.appendingPathComponent("inventory.json"))
        guard !selected.isEmpty else { throw Failure(message: "No eligible local system font pair; no rendering attempted") }
      } else if args.count == 5, args[1] == "--case" {
        guard try runCase(id: args[2], order: args[3], root: root) else { exit(1) }
      } else {
        throw Failure(message: "Unknown diagnostic mode")
      }
    } catch {
      FileHandle.standardError.write(Data("FAIL: \(error.localizedDescription)\n".utf8))
      exit(2)
    }
  }
}
