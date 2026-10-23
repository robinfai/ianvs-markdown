import AppKit
import Foundation

@main
struct NativePDFFontEvidenceTests {
  static func syntheticPDF(pages: Int = 1, stream: String = "q\nQ\n") -> Data {
    // Minimal locally generated PDF; no text/font lookup or external resource.
    var objects = ["<< /Type /Catalog /Pages 2 0 R >>", ""]
    var pageReferences = [String]()
    for _ in 0..<pages {
      let pageNumber = objects.count + 1
      let streamNumber = pageNumber + 1
      pageReferences.append("\(pageNumber) 0 R")
      objects.append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595.276 841.89] /Resources << >> /Contents \(streamNumber) 0 R >>")
      objects.append("<< /Length \(stream.utf8.count) >>\nstream\n\(stream)\nendstream")
    }
    objects[1] = "<< /Type /Pages /Count \(pages) /Kids [\(pageReferences.joined(separator: " "))] >>"
    var output = Data("%PDF-1.4\n".utf8)
    var offsets = [0]
    for (index, object) in objects.enumerated() {
      offsets.append(output.count)
      output.append(Data("\(index + 1) 0 obj\n\(object)\nendobj\n".utf8))
    }
    let start = output.count
    output.append(Data("xref\n0 \(objects.count + 1)\n0000000000 65535 f \n".utf8))
    for offset in offsets.dropFirst() {
      output.append(Data(String(format: "%010d 00000 n \n", offset).utf8))
    }
    output.append(Data("trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(start)\n%%EOF\n".utf8))
    return output
  }

  @MainActor
  static func main() throws {
    try FontPreflightManifestTests.run()
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("linefold-font-evidence-unit-\(UUID().uuidString)")
    try fm.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: root) }
    func rejects(containing expected: String, _ body: () throws -> Void) {
      do { try body(); fatalError("Expected rejection") }
      catch { assert(error.localizedDescription.contains(expected), "Unexpected rejection: \(error)") }
    }
    func file(_ name: String, _ data: Data) throws -> URL {
      let url = root.appendingPathComponent(name)
      try data.write(to: url, options: .withoutOverwriting)
      return url
    }
    print("PHASE: evidence input, stream, page and output resource boundaries")
    let input = try file("blank.pdf", syntheticPDF())
    let output = root.appendingPathComponent("new-evidence")
    let manifest = try PDFFontEvidence.inspect(input, evidenceDirectory: output)
    assert(manifest["pageCount"] as? Int == 1)
    let copiedInput = try Data(contentsOf: output.appendingPathComponent("input.pdf"))
    let originalInput = try Data(contentsOf: input)
    assert(copiedInput == originalInput)
    assert(fm.fileExists(atPath: output.appendingPathComponent("page-1.png").path))
    let before = try Data(contentsOf: output.appendingPathComponent("manifest.json"))
    rejects(containing: "create NEW evidence directory") { _ = try PDFFontEvidence.inspect(input, evidenceDirectory: output) }
    let after = try Data(contentsOf: output.appendingPathComponent("manifest.json"))
    assert(after == before)
    let link = root.appendingPathComponent("link.pdf")
    try fm.createSymbolicLink(at: link, withDestinationURL: input)
    rejects(containing: "open synthetic input") { _ = try PDFFontEvidence.inspect(link, evidenceDirectory: root.appendingPathComponent("symlink-evidence")) }
    let tooLarge = try file("large.pdf", Data(repeating: 0x20, count: 4 * 1024 * 1024 + 1))
    rejects(containing: "no larger than 4 MiB") { _ = try PDFFontEvidence.inspect(tooLarge, evidenceDirectory: root.appendingPathComponent("large-evidence")) }
    let fourPages = try file("four.pdf", syntheticPDF(pages: 4))
    rejects(containing: "PDF page count") { _ = try PDFFontEvidence.inspect(fourPages, evidenceDirectory: root.appendingPathComponent("four-evidence")) }
    let largeStream = try file("large-stream.pdf", syntheticPDF(stream: String(repeating: " ", count: 1024 * 1024 + 1)))
    rejects(containing: "Decoded stream exceeds 1 MiB") { _ = try PDFFontEvidence.inspect(largeStream, evidenceDirectory: root.appendingPathComponent("stream-evidence")) }
    let invalid = try file("invalid.pdf", Data("not a PDF".utf8))
    rejects(containing: "unencrypted CoreGraphics PDF") { _ = try PDFFontEvidence.inspect(invalid, evidenceDirectory: root.appendingPathComponent("invalid-evidence")) }
    for name in ["symlink-evidence", "large-evidence", "four-evidence", "stream-evidence", "invalid-evidence"] {
      assert(!fm.fileExists(atPath: root.appendingPathComponent(name).path))
    }

    print("PHASE: preserved print lease and exactly-once phase deadline")
    let lease = DocumentExportPrintLease()
    let owner = UUID(), other = UUID()
    assert(lease.acquire(owner))
    assert(!lease.acquire(other))
    lease.release(other)
    assert(!lease.acquire(other))
    lease.release(owner)
    assert(lease.acquire(other))
    lease.release(owner)
    assert(!lease.acquire(owner))
    lease.release(other)
    var callbacks = 0
    var cancellations = 0
    let loading = DocumentExportLifecycle(loadingTimeout: 0.01, outputTimeout: 0.01,
      cancelOutput: { cancellations += 1 }) { _ in callbacks += 1 }
    let deadline = Date().addingTimeInterval(2)
    while loading.isActive && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
    assert(callbacks == 1 && cancellations == 0 && !loading.isActive)
    loading.finish(.success(true))
    assert(callbacks == 1)
    let rendering = DocumentExportLifecycle(loadingTimeout: 1, outputTimeout: 0.01,
      cancelOutput: { cancellations += 1 }) { _ in callbacks += 1 }
    rendering.beginPrinting(interactive: false)
    let renderDeadline = Date().addingTimeInterval(2)
    while rendering.isActive && Date() < renderDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
    assert(callbacks == 2 && cancellations == 1 && !rendering.isActive)
    rendering.finish(.success(true))
    assert(callbacks == 2)
    print("PASS: bounded synthetic evidence, exclusive artifact writes, phase deadlines and stale lease isolation")
  }
}
