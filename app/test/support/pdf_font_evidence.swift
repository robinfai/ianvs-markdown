import AppKit
import CoreGraphics
import Darwin
import Foundation
import PDFKit

/// Test-only evidence, not a PDF repairer or a general-purpose hostile-PDF reader.
/// Call from the diagnostic's separately supervised process, with its own synthetic
/// fixture and a NEW directory below a test-owned parent. No URLs in the PDF are
/// opened, no fonts are installed, and no source or existing output is overwritten.
///
/// CoreGraphics/PDFKit allocate while parsing, extracting and rendering. In
/// particular CGPDFStreamCopyData has no bounded-decode API: decoded-size checks
/// happen AFTER that framework allocation. The limits below bound accepted input,
/// traversal and persisted evidence, not framework peak memory or execution time.
/// Keep the caller's process watchdog/resource limits; never use external PDFs.
///
/// Public API references (native compilation/visual verification still required):
/// https://developer.apple.com/documentation/pdfkit/pdfpage
/// https://developer.apple.com/documentation/coregraphics/cgpdfdictionary
/// https://developer.apple.com/documentation/coregraphics/cgpdfstreamcopydata(_:_:)
/// https://developer.apple.com/documentation/coregraphics/cgpdfpage
/// https://developer.apple.com/documentation/appkit/nsbitmapimagerep
public enum PDFFontEvidence {
  public static func inspect(_ url: URL, evidenceDirectory: URL) throws -> [String: Any] {
    guard url.isFileURL, evidenceDirectory.isFileURL else {
      throw EvidenceError.invalid("Only local, test-owned file URLs are supported")
    }
    let input = try readBoundedInput(url)
    guard let provider = CGDataProvider(data: input as CFData),
          let document = CGPDFDocument(provider), !document.isEncrypted else {
      throw EvidenceError.invalid("Input is not an unencrypted CoreGraphics PDF")
    }
    guard (1...Limits.pages).contains(document.numberOfPages) else {
      throw EvidenceError.limit("PDF page count must be between 1 and \(Limits.pages)")
    }

    let collector = Collector()
    try collector.add(input, named: "input.pdf")
    // Inspect streams/resources before asking PDFKit to extract or render text.
    var pageEvidence = [[String: Any]]()
    for index in 1...document.numberOfPages {
      guard let page = document.page(at: index), let dictionary = page.dictionary else {
        throw EvidenceError.invalid("Missing CoreGraphics page \(index)")
      }
      let pageCollector = PageCollector(artifacts: collector)
      let contents = try pageCollector.contents(dictionary)
      let inherited = try inheritedResources(dictionary)
      let resources: Any
      if let dictionary = inherited.dictionary {
        resources = try pageCollector.resources(dictionary, depth: 0, ancestors: [])
      } else {
        resources = NSNull()
      }
      pageEvidence.append([
        "pageNumber": index,
        "coreGraphicsRotationDegrees": Int(page.rotationAngle),
        "coreGraphicsBoxes": try boxes(page),
        "pageContentStreamsInOrder": contents,
        "decodedPageAndFormContentBytes": pageCollector.contentBytes,
        "resourceInheritanceParentSteps": inherited.parentSteps,
        "resources": resources,
      ])
    }

    guard let pdfKit = PDFDocument(data: input), !pdfKit.isLocked,
          pdfKit.pageCount == document.numberOfPages else {
      throw EvidenceError.invalid("PDFKit could not open the same unencrypted page set")
    }
    for index in 0..<pdfKit.pageCount {
      guard let page = pdfKit.page(at: index), let cgPage = document.page(at: index + 1) else {
        throw EvidenceError.invalid("Missing page during PDFKit extraction")
      }
      pageEvidence[index]["pdfKit"] = try pdfKitEvidence(page)
      pageEvidence[index]["rendering"] = try render(cgPage, number: index + 1, artifacts: collector)
    }

    var manifest: [String: Any] = [
      "schemaVersion": 1,
      "status": "evidence_collected_not_glyph_mapping_verified",
      "input": ["file": "input.pdf", "byteCount": input.count, "unchangedCopy": true],
      "pageCount": document.numberOfPages,
      "pages": pageEvidence,
      "budgets": [
        "maximumInputBytes": Limits.inputBytes,
        "maximumPages": Limits.pages,
        "maximumDecodedCMapBytesEach": Limits.streamBytes,
        "maximumDecodedPageAndFormContentBytesPerPage": Limits.streamBytes,
        "maximumPersistedEvidenceBytesIncludingManifest": Limits.evidenceBytes,
        "maximumDictionaryEntries": Limits.dictionaryEntries,
        "maximumResourceDepth": Limits.resourceDepth,
        "maximumResourceScopesPerPage": Limits.resourceScopes,
        "maximumFontsPerPageIncludingDescendants": Limits.fonts,
        "maximumDecodedStreamsPerPage": Limits.streams,
        "maximumTextUTF16UnitsPerPage": Limits.textUnits,
        "maximumAttributedFontRunsPerPage": Limits.fontRuns,
        "maximumImageEdgePixels": Limits.imageEdge,
        "maximumImagePixels": Limits.imagePixels,
      ],
      "interpretation": [
        "Raw PDFKit text is unchanged; scalar strings describe that returned text, not a corrected extraction.",
        "PDFKit attributed fonts are PDFKit inference, not proof of a PDF resource or font used for a specific glyph.",
        "BaseFont/Subtype are actual resource dictionary values. Listing a font does not prove that it was used.",
        "Coverage is page/inherited Font resources, DescendantFonts and nested Form XObject resources. It is not a complete PDF interpreter.",
        "Patterns, Type3 CharProcs/resources, ExtGState Font entries and annotation appearance resources are not inventoried. The unchanged PDF is retained for independent review.",
        "Decoded bytes are preserved without CMap rewriting, Unicode normalization or speculative Tf/Tj/TJ association.",
        "Named CMaps and usecmap semantics are not resolved. A decoded CMap is evidence, not proof of correct mapping.",
        "PNGs use CoreGraphics media-box rendering, not an independent renderer or a printer, and omit annotation appearances.",
        "Framework peak allocations/time are not bounded by these acceptance limits; only supervised synthetic fixtures are supported.",
      ],
      "artifactsExcludingManifest": collector.inventory,
      "artifactBytesExcludingManifest": collector.byteCount,
    ]
    guard JSONSerialization.isValidJSONObject(manifest) else {
      throw EvidenceError.invalid("Evidence contains a non-JSON value")
    }
    // No mutable 'total' field whose own encoded length could change the budget.
    manifest["manifestFile"] = "manifest.json"
    let json = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    try collector.add(json, named: "manifest.json")
    try collector.writeNewDirectory(evidenceDirectory)
    return manifest
  }

  private enum Limits {
    static let inputBytes = 4 * 1024 * 1024
    static let pages = 3
    static let streamBytes = 1024 * 1024
    static let evidenceBytes = 16 * 1024 * 1024
    static let dictionaryEntries = 256
    static let resourceDepth = 8
    static let resourceScopes = 64
    static let fonts = 128
    static let streams = 256
    static let parentDepth = 16
    static let nameBytes = 1024
    static let textUnits = 65_536
    static let fontRuns = 4096
    static let imageEdge = 2048
    static let imagePixels = 4 * 1024 * 1024
  }

  private enum EvidenceError: Error, LocalizedError {
    case invalid(String)
    case limit(String)
    case io(String, Int32)
    var errorDescription: String? {
      switch self {
      case .invalid(let message): return "PDF evidence unsupported: \(message)"
      case .limit(let message): return "PDF evidence budget exceeded: \(message)"
      case .io(let operation, let code): return "PDF evidence I/O failed: \(operation) (errno \(code))"
      }
    }
  }

  private final class Collector {
    private var files = [(name: String, data: Data)]()
    private(set) var byteCount = 0
    var inventory: [[String: Any]] { files.map { ["file": $0.name, "byteCount": $0.data.count] } }
    func add(_ data: Data, named name: String) throws {
      guard !name.isEmpty, !name.contains("/"), name != ".", name != "..",
            !files.contains(where: { $0.name == name }) else {
        throw EvidenceError.invalid("Duplicate or unsafe generated artifact name")
      }
      guard data.count <= Limits.evidenceBytes - byteCount else {
        throw EvidenceError.limit("Total evidence exceeds 16 MiB")
      }
      files.append((name, data))
      byteCount += data.count
    }
    func writeNewDirectory(_ url: URL) throws {
      let leaf = url.lastPathComponent
      guard !leaf.isEmpty, leaf != ".", leaf != "..", !leaf.contains("/") else {
        throw EvidenceError.invalid("Evidence directory must have a new leaf name")
      }
      let parent = url.deletingLastPathComponent().resolvingSymlinksInPath()
      let parentFD = Darwin.open(parent.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
      guard parentFD >= 0 else { throw EvidenceError.io("open test-owned parent", errno) }
      defer { Darwin.close(parentFD) }
      // mkdirat is exclusive even when an existing destination is an empty directory
      // or dangling symlink. No existing destination is removed or replaced.
      guard mkdirat(parentFD, leaf, 0o700) == 0 else {
        throw EvidenceError.io("create NEW evidence directory", errno)
      }
      let directoryFD = openat(parentFD, leaf, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
      guard directoryFD >= 0 else { throw EvidenceError.io("open new evidence directory", errno) }
      defer { Darwin.close(directoryFD) }
      for file in files {
        let fd = openat(directoryFD, file.name, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw EvidenceError.io("exclusively create \(file.name)", errno) }
        do {
          try file.data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
              let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
              if count < 0, errno == EINTR { continue }
              guard count > 0 else { throw EvidenceError.io("write \(file.name)", errno) }
              offset += count
            }
          }
        } catch {
          Darwin.close(fd)
          // Leave only this new directory for caller-owned cleanup. Never recursively
          // delete a path that might have been changed by another actor.
          throw error
        }
        // close() is attempted exactly once, even if it reports an error: retrying
        // may close a reused descriptor on platforms where the first close took effect.
        guard Darwin.close(fd) == 0 else { throw EvidenceError.io("close \(file.name)", errno) }
      }
    }
  }

  private static func readBoundedInput(_ url: URL) throws -> Data {
    let fd = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
    guard fd >= 0 else { throw EvidenceError.io("open synthetic input", errno) }
    defer { Darwin.close(fd) }
    var info = stat()
    guard fstat(fd, &info) == 0 else { throw EvidenceError.io("stat synthetic input", errno) }
    guard (info.st_mode & S_IFMT) == S_IFREG, info.st_size > 0,
          info.st_size <= Int64(Limits.inputBytes) else {
      throw EvidenceError.limit("Input must be a regular nonempty file no larger than 4 MiB")
    }
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
      let count = buffer.withUnsafeMutableBytes { bytes in
        Darwin.read(fd, bytes.baseAddress!, min(bytes.count, Limits.inputBytes - result.count + 1))
      }
      if count < 0, errno == EINTR { continue }
      guard count >= 0 else { throw EvidenceError.io("read synthetic input", errno) }
      if count == 0 { break }
      guard count <= Limits.inputBytes - result.count else {
        throw EvidenceError.limit("Input grew beyond 4 MiB while reading")
      }
      result.append(contentsOf: buffer.prefix(count))
    }
    guard result.count == Int(info.st_size) else {
      throw EvidenceError.invalid("Synthetic input changed size during inspection")
    }
    return result
  }

  private struct Name {
    let bytes: Data
    var text: String? { String(data: bytes, encoding: .utf8) }
    var json: [String: Any] { ["utf8": optional(text), "bytesBase64": bytes.base64EncodedString()] }
    init(_ pointer: UnsafePointer<CChar>) throws {
      let count = strnlen(pointer, Limits.nameBytes + 1)
      guard count <= Limits.nameBytes else { throw EvidenceError.limit("PDF name exceeds 1024 bytes") }
      bytes = Data(bytes: pointer, count: count)
    }
  }

  private static func optional<T>(_ value: T?) -> Any {
    if let value = value { return value }
    return NSNull()
  }
  private static func object(_ dictionary: CGPDFDictionaryRef, _ key: String) -> CGPDFObjectRef? {
    var value: CGPDFObjectRef?
    return CGPDFDictionaryGetObject(dictionary, key, &value) ? value : nil
  }
  private static func child(_ dictionary: CGPDFDictionaryRef, _ key: String) throws -> CGPDFDictionaryRef? {
    guard let item = object(dictionary, key), CGPDFObjectGetType(item) != .null else { return nil }
    return try asDictionary(item)
  }
  private static func asDictionary(_ item: CGPDFObjectRef) throws -> CGPDFDictionaryRef {
    var value: CGPDFDictionaryRef?
    guard CGPDFObjectGetValue(item, .dictionary, &value), let value = value else {
      throw EvidenceError.invalid("Expected a resource dictionary")
    }
    guard CGPDFDictionaryGetCount(value) <= Limits.dictionaryEntries else {
      throw EvidenceError.limit("Dictionary has more than 256 entries")
    }
    return value
  }
  private static func asStream(_ item: CGPDFObjectRef) throws -> CGPDFStreamRef {
    var value: CGPDFStreamRef?
    guard CGPDFObjectGetValue(item, .stream, &value), let value = value else {
      throw EvidenceError.invalid("Expected a PDF stream")
    }
    return value
  }
  private static func asArray(_ item: CGPDFObjectRef) throws -> CGPDFArrayRef {
    var value: CGPDFArrayRef?
    guard CGPDFObjectGetValue(item, .array, &value), let value = value,
          CGPDFArrayGetCount(value) <= Limits.dictionaryEntries else {
      throw EvidenceError.invalid("Expected an array with at most 256 entries")
    }
    return value
  }
  private static func arrayObject(_ array: CGPDFArrayRef, _ index: Int) throws -> CGPDFObjectRef {
    var value: CGPDFObjectRef?
    guard CGPDFArrayGetObject(array, index, &value), let value = value else {
      throw EvidenceError.invalid("Unreadable array element")
    }
    return value
  }
  private static func name(_ dictionary: CGPDFDictionaryRef, _ key: String) throws -> Name? {
    guard let item = object(dictionary, key), CGPDFObjectGetType(item) != .null else { return nil }
    return try asName(item)
  }
  private static func asName(_ item: CGPDFObjectRef) throws -> Name {
    var pointer: UnsafePointer<CChar>?
    guard CGPDFObjectGetValue(item, .name, &pointer), let pointer = pointer else {
      throw EvidenceError.invalid("Expected a PDF name")
    }
    return try Name(pointer)
  }
  private static func entries(_ dictionary: CGPDFDictionaryRef) throws -> [(Name, CGPDFObjectRef)] {
    guard CGPDFDictionaryGetCount(dictionary) <= Limits.dictionaryEntries else {
      throw EvidenceError.limit("Dictionary has more than 256 entries")
    }
    var result = [(Name, CGPDFObjectRef)]()
    var failure: Error?
    CGPDFDictionaryApplyBlock(dictionary, { pointer, value, _ in
      do { result.append((try Name(pointer), value)); return true }
      catch { failure = error; return false }
    }, nil)
    if let failure = failure { throw failure }
    return result.sorted { $0.0.bytes.lexicographicallyPrecedes($1.0.bytes) }
  }
  private static func inheritedResources(_ page: CGPDFDictionaryRef) throws -> (dictionary: CGPDFDictionaryRef?, parentSteps: Int) {
    var current = page
    var ancestors = [CGPDFDictionaryRef]()
    for step in 0...Limits.parentDepth {
      guard !ancestors.contains(current) else { throw EvidenceError.invalid("Page tree cycle") }
      ancestors.append(current)
      if let resources = try child(current, "Resources") { return (resources, step) }
      guard let parent = try child(current, "Parent") else { return (nil, step) }
      current = parent
    }
    throw EvidenceError.limit("Page resource inheritance exceeds 16 parent steps")
  }

  private final class PageCollector {
    let artifacts: Collector
    var contentBytes = 0
    private var streamCount = 0
    private var scopeCount = 0
    private var fontCount = 0
    init(artifacts: Collector) { self.artifacts = artifacts }

    func contents(_ page: CGPDFDictionaryRef) throws -> [[String: Any]] {
      guard let item = object(page, "Contents"), CGPDFObjectGetType(item) != .null else { return [] }
      if CGPDFObjectGetType(item) == .stream { return [try stream(asStream(item), kind: "content")] }
      let array = try asArray(item)
      return try (0..<CGPDFArrayGetCount(array)).map {
        try stream(asStream(arrayObject(array, $0)), kind: "content")
      }
    }

    func resources(_ dictionary: CGPDFDictionaryRef, depth: Int, ancestors: [CGPDFDictionaryRef]) throws -> [String: Any] {
      guard depth <= Limits.resourceDepth, scopeCount < Limits.resourceScopes else {
        throw EvidenceError.limit("Resource nesting or scope count exceeded")
      }
      guard !ancestors.contains(dictionary) else { throw EvidenceError.invalid("Resource dictionary cycle") }
      scopeCount += 1
      let path = ancestors + [dictionary]
      var fonts = [[String: Any]]()
      if let fontDictionary = try child(dictionary, "Font") {
        for (resourceName, item) in try entries(fontDictionary) {
          fonts.append(["resourceName": resourceName.json, "font": try font(asDictionary(item), depth: 0)])
        }
      }
      var xObjects = [[String: Any]]()
      if let xObjectDictionary = try child(dictionary, "XObject") {
        for (resourceName, item) in try entries(xObjectDictionary) {
          let value = try asStream(item)
          guard let details = CGPDFStreamGetDictionary(value) else {
            throw EvidenceError.invalid("XObject has no stream dictionary")
          }
          try rejectExternalStream(details)
          let subtype = try name(details, "Subtype")
          var row: [String: Any] = ["resourceName": resourceName.json, "subtype": optional(subtype?.json)]
          if subtype?.text == "Form" {
            guard object(details, "Ref") == nil else { throw EvidenceError.invalid("Reference XObjects are unsupported") }
            row["content"] = try stream(value, kind: "form-content")
            if let ownResources = try child(details, "Resources") {
              row["resources"] = try resources(ownResources, depth: depth + 1, ancestors: path)
              row["resourceScope"] = "form_own_resources"
            } else {
              row["resources"] = NSNull()
              row["resourceScope"] = "no_own_resources_parent_scope_not_duplicated"
            }
          } else {
            row["contentInspected"] = false
            row["reason"] = "Non-Form XObject, not a decoded text-content stream"
          }
          xObjects.append(row)
        }
      }
      return ["fonts": fonts, "xObjects": xObjects]
    }

    private func font(_ dictionary: CGPDFDictionaryRef, depth: Int) throws -> [String: Any] {
      guard depth <= Limits.resourceDepth, fontCount < Limits.fonts else {
        throw EvidenceError.limit("Font depth or count exceeded")
      }
      fontCount += 1
      let baseFont = try name(dictionary, "BaseFont")
      let subtype = try name(dictionary, "Subtype")
      var result: [String: Any] = [
        "baseFont": optional(baseFont?.text), "baseFontName": optional(baseFont?.json),
        "subtype": optional(subtype?.text), "subtypeName": optional(subtype?.json),
        "evidenceKind": "actual_pdf_resource_dictionary_not_glyph_usage_proof",
      ]
      if let toUnicode = object(dictionary, "ToUnicode"), CGPDFObjectGetType(toUnicode) != .null {
        result["toUnicode"] = try cmap(toUnicode, depth: 0)
      } else {
        result["toUnicode"] = ["kind": "absent"]
      }
      if let encoding = object(dictionary, "Encoding"), CGPDFObjectGetType(encoding) != .null {
        switch CGPDFObjectGetType(encoding) {
        case .name, .stream: result["encoding"] = try cmap(encoding, depth: 0)
        case .dictionary:
          let encodingDictionary = try asDictionary(encoding)
          result["encoding"] = ["kind": "dictionary", "baseEncoding": optional(try name(encodingDictionary, "BaseEncoding")?.json), "differencesPresent": object(encodingDictionary, "Differences") != nil]
        default: throw EvidenceError.invalid("Unsupported font Encoding value")
        }
      } else { result["encoding"] = ["kind": "absent"] }
      if let descriptor = try child(dictionary, "FontDescriptor") {
        result["fontDescriptor"] = [
          "fontName": optional(try name(descriptor, "FontName")?.json),
          "fontFileEntryPresent": object(descriptor, "FontFile") != nil,
          "fontFile2EntryPresent": object(descriptor, "FontFile2") != nil,
          "fontFile3EntryPresent": object(descriptor, "FontFile3") != nil,
          "note": "Presence only; embedded font program and glyph selection are not validated",
        ]
        for key in ["FontFile", "FontFile2", "FontFile3"] {
          if let item = object(descriptor, key), CGPDFObjectGetType(item) != .null {
            guard let details = CGPDFStreamGetDictionary(try asStream(item)) else {
              throw EvidenceError.invalid("Font program has no stream dictionary")
            }
            try rejectExternalStream(details)
          }
        }
      }
      if let descendants = object(dictionary, "DescendantFonts") {
        let array = try asArray(descendants)
        result["descendantFonts"] = try (0..<CGPDFArrayGetCount(array)).map {
          try font(asDictionary(arrayObject(array, $0)), depth: depth + 1)
        }
      }
      if subtype?.text == "Type3" {
        result["coverageWarning"] = "Type3 CharProcs/resources are not inventoried; inspect unchanged input.pdf independently"
      }
      return result
    }

    private func cmap(_ item: CGPDFObjectRef, depth: Int) throws -> [String: Any] {
      guard depth <= Limits.resourceDepth else { throw EvidenceError.limit("UseCMap nesting exceeded") }
      if CGPDFObjectGetType(item) == .name {
        return ["kind": "name", "name": try asName(item).json, "resolved": false]
      }
      let value = try asStream(item)
      var result = try stream(value, kind: "cmap")
      result["kind"] = "decoded_stream"
      result["interpreted"] = false
      if let dictionary = CGPDFStreamGetDictionary(value), let base = object(dictionary, "UseCMap") {
        result["useCMap"] = try cmap(base, depth: depth + 1)
      }
      return result
    }

    private func stream(_ value: CGPDFStreamRef, kind: String) throws -> [String: Any] {
      guard streamCount < Limits.streams else { throw EvidenceError.limit("Decoded stream count exceeded") }
      streamCount += 1
      guard let dictionary = CGPDFStreamGetDictionary(value) else {
        throw EvidenceError.invalid("Missing stream dictionary")
      }
      try rejectExternalStream(dictionary)
      var format = CGPDFDataFormat.raw
      guard let decoded = CGPDFStreamCopyData(value, &format), format == .raw else {
        throw EvidenceError.invalid("Text/CMap stream did not decode to raw bytes")
      }
      let count = CFDataGetLength(decoded)
      guard count <= Limits.streamBytes else { throw EvidenceError.limit("Decoded stream exceeds 1 MiB") }
      if kind != "cmap" {
        guard count <= Limits.streamBytes - contentBytes else {
          throw EvidenceError.limit("Combined page/Form content exceeds 1 MiB")
        }
        contentBytes += count
      }
      // Copy no textual reinterpretation into the canonical stream artifact.
      let bytes = decoded as Data
      let filename = "stream-\(artifacts.inventory.count)-\(kind).bin"
      try artifacts.add(bytes, named: filename)
      var result: [String: Any] = ["file": filename, "byteCount": count, "format": "decoded_raw_bytes", "streamRole": kind]
      if let length = object(dictionary, "Length") {
        var encodedLength: CGPDFInteger = 0
        if CGPDFObjectGetValue(length, .integer, &encodedLength) { result["declaredEncodedLength"] = encodedLength }
      }
      if let filter = object(dictionary, "Filter"), CGPDFObjectGetType(filter) != .null {
        if CGPDFObjectGetType(filter) == .name { result["filters"] = [try asName(filter).json] }
        else {
          let array = try asArray(filter)
          result["filters"] = try (0..<CGPDFArrayGetCount(array)).map { try asName(arrayObject(array, $0)).json }
        }
      } else { result["filters"] = [[String: Any]]() }
      return result
    }

    private func rejectExternalStream(_ dictionary: CGPDFDictionaryRef) throws {
      guard CGPDFDictionaryGetCount(dictionary) <= Limits.dictionaryEntries else {
        throw EvidenceError.limit("Stream dictionary has more than 256 entries")
      }
      for key in ["F", "FFilter", "FDecodeParms"] where object(dictionary, key) != nil {
        throw EvidenceError.invalid("External-file stream key /\(key) is unsupported")
      }
    }
  }

  private static func rect(_ value: CGRect) throws -> [String: Double] {
    let values = [Double(value.origin.x), Double(value.origin.y), Double(value.width), Double(value.height)]
    guard values.allSatisfy({ $0.isFinite && abs($0) <= 14_400 }) else {
      throw EvidenceError.limit("Page bounds must be finite and within 14,400 PDF units")
    }
    return ["x": values[0], "y": values[1], "width": values[2], "height": values[3]]
  }
  private static func boxes(_ page: CGPDFPage) throws -> [String: Any] {
    return [
      "mediaBox": try rect(page.getBoxRect(.mediaBox)),
      "cropBox": try rect(page.getBoxRect(.cropBox)),
      "bleedBox": try rect(page.getBoxRect(.bleedBox)),
      "trimBox": try rect(page.getBoxRect(.trimBox)),
      "artBox": try rect(page.getBoxRect(.artBox)),
    ]
  }
  private static func checkedText(_ value: String) throws -> String {
    guard value.utf16.count <= Limits.textUnits else { throw EvidenceError.limit("PDFKit text exceeds 65,536 UTF-16 units") }
    return value
  }
  private static func pdfKitEvidence(_ page: PDFPage) throws -> [String: Any] {
    let text = try page.string.map(checkedText)
    var result: [String: Any] = [
      "rawText": optional(text),
      "unicodeScalars": optional(text.map { $0.unicodeScalars.map { String(format: "U+%04X", $0.value) } }),
      "unicodeNormalizationApplied": false,
      "rotationDegrees": page.rotation,
      "mediaBox": try rect(page.bounds(for: .mediaBox)),
      "cropBox": try rect(page.bounds(for: .cropBox)),
      "attributedFontEvidenceKind": "PDFKit_inference_not_verified_pdf_font_glyph_association",
    ]
    guard let attributed = page.attributedString else {
      result["attributedText"] = NSNull()
      result["attributedFontRuns"] = NSNull()
      return result
    }
    let attributedText = try checkedText(attributed.string)
    result["attributedText"] = attributedText
    result["attributedTextEqualsRawText"] = text.map { Array($0.utf16) == Array(attributedText.utf16) } ?? false
    var runs = [[String: Any]]()
    var failure: Error?
    attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length), options: []) { value, range, stop in
      guard runs.count < Limits.fontRuns else {
        failure = EvidenceError.limit("PDFKit attributed font runs exceed 4096")
        stop.pointee = true
        return
      }
      var run: [String: Any] = ["rangeInAttributedTextUTF16": ["location": range.location, "length": range.length]]
      if let font = value as? NSFont, font.pointSize.isFinite {
        run["font"] = ["postScriptName": font.fontName, "familyName": optional(font.familyName), "pointSize": Double(font.pointSize)]
      } else {
        run["font"] = NSNull()
        run["fontAttributePresentButUnsupported"] = value != nil
      }
      runs.append(run)
    }
    if let failure = failure { throw failure }
    result["attributedFontRuns"] = runs
    return result
  }
  private static func render(_ page: CGPDFPage, number: Int, artifacts: Collector) throws -> [String: Any] {
    let media = page.getBoxRect(.mediaBox)
    _ = try rect(media)
    guard media.width > 0, media.height > 0, page.rotationAngle % 90 == 0 else {
      throw EvidenceError.invalid("Cannot render empty bounds or a non-quarter-turn page rotation")
    }
    let quarterTurn = abs(Int(page.rotationAngle) % 180) == 90
    let displayWidth = quarterTurn ? media.height : media.width
    let displayHeight = quarterTurn ? media.width : media.height
    let scale = min(CGFloat(2), CGFloat(Limits.imageEdge) / max(displayWidth, displayHeight))
    let width = max(1, Int(ceil(displayWidth * scale)))
    let height = max(1, Int(ceil(displayHeight * scale)))
    guard width <= Limits.imageEdge, height <= Limits.imageEdge, width * height <= Limits.imagePixels else {
      throw EvidenceError.limit("Page bitmap pixel budget exceeded")
    }
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
      throw EvidenceError.invalid("Could not allocate bounded page bitmap")
    }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
    let transform = page.getDrawingTransform(.mediaBox,
      rect: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)), rotate: 0, preserveAspectRatio: true)
    context.concatenate(transform)
    context.clip(to: media)
    context.drawPDFPage(page)
    guard let image = context.makeImage(),
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
      throw EvidenceError.invalid("Could not encode PNG page evidence")
    }
    let filename = "page-\(number).png"
    try artifacts.add(png, named: filename)
    return ["file": filename, "renderer": "CoreGraphics", "box": "mediaBox", "widthPixels": width,
            "heightPixels": height, "requestedPixelsPerPDFUnit": Double(scale),
            "annotationsIncluded": false, "byteCount": png.count]
  }
}
