import CryptoKit
import Darwin
import Foundation

/// Synthetic metadata/files only: never opens a system font or invokes CoreText.
/// Called by the existing evidence test executable; deliberately has no @main.
enum FontPreflightManifestTests {
  private struct Failure: LocalizedError {
    let message: String
    var errorDescription: String? { "Manifest test failed: \(message)" }
  }

  static func run() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("linefold-font-manifest-unit-\(UUID().uuidString)")
      .resolvingSymlinksInPath().standardizedFileURL
    try fm.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: root) }
    let system = root.appendingPathComponent("synthetic-system", isDirectory: true)
    try fm.createDirectory(at: system, withIntermediateDirectories: false)
    let scalars = Set("文⽂长⻓中文文档代码ABCDEFGHIJKLMNOPQRSTUVWXYZ_0123456789 ".unicodeScalars
      .map { String(format: "U+%04X", $0.value) }).sorted()
    try require(scalars.count == 46, "the fixed diagnostic scalar universe changed")

    func write(_ name: String, _ data: Data, in directory: URL? = nil) throws -> URL {
      let url = (directory ?? root).appendingPathComponent(name)
      try data.write(to: url, options: .withoutOverwriting)
      return url
    }
    func candidate(_ id: String, missingRegular: Set<String> = [], missingBold: Set<String> = []) throws -> [String: Any] {
      let family = ["songti": "Songti SC", "heiti": "Heiti SC", "pingfang": "PingFang SC"][id]!
      let bytes = Data("owned synthetic metadata fixture \(id)".utf8)
      let url = try write("\(id).ttc", bytes, in: system)
      let fileIdentity = try FontPreflightProof.identity(of: url, under: system)
      var faces = [String: Any](), inventory = [[String: Any]]()
      for role in ["regular", "bold"] {
        let postScript = "Synthetic-\(id)-\(role)"
        let missing = role == "regular" ? missingRegular : missingBold
        faces[role] = [
          "postScriptName": postScript, "systemFile": url.lastPathComponent,
          "systemRelativePath": url.lastPathComponent, "fileIdentity": fileIdentity,
          "fileSHA256": digest(bytes), "fileBytes": bytes.count,
          "inventoryEnabled": true, "inventoryDownloadable": false, "dataDescriptorRegistered": false,
          "referenceRole": role, "coverageComplete": missing.isEmpty,
          "options": ["preventAutoActivation", "preventAutoDownload"],
          "weight": role == "bold" ? 0.4 : 0.0, "symbolicTraits": role == "bold" ? 2 : 0,
          "coverage": scalars.map { ["scalar": $0, "glyphs": [missing.contains($0) ? 0 : 1]] as [String: Any] },
        ] as [String: Any]
        inventory.append(["postScriptName": postScript, "fileName": url.lastPathComponent,
                          "enabled": true, "downloadable": false, "italic": false, "bold": role == "bold",
                          "weight": role == "bold" ? 0.4 : 0.0, "symbolicTraits": role == "bold" ? 2 : 0])
      }
      faces["id"] = id
      faces["family"] = family
      faces["availableFaces"] = inventory.count
      faces["inventoryFaces"] = inventory
      faces["status"] = missingRegular.isEmpty && missingBold.isEmpty ? "selected" : "partial-coverage"
      return faces
    }
    let primary = try candidate("songti", missingRegular: ["U+2F42"], missingBold: ["U+2ED3"])
    let fallback = try candidate("heiti")
    let configuration = try FontPreflightProof.configuration(primary: primary, fallback: fallback, scalars: scalars)
    let primaryComplete = try FontPreflightProof.validateCandidate(primary, id: "songti", scalars: scalars)
    let fallbackComplete = try FontPreflightProof.validateCandidate(fallback, id: "heiti", scalars: scalars)
    try require(!primaryComplete && fallbackComplete, "partial primary and independently full fallback")
    let pingfang = try candidate("pingfang")
    let pingfangComplete = try FontPreflightProof.validateCandidate(pingfang, id: "pingfang", scalars: scalars)
    try require(pingfangComplete, "the unchanged PingFang solo control remains eligible")
    try rejects("PingFang is not an approved combination primary") {
      _ = try FontPreflightProof.configuration(primary: pingfang, fallback: fallback, scalars: scalars)
    }
    var fullPrimary = primary
    for role in ["regular", "bold"] {
      fullPrimary = alter(fullPrimary, role: role) {
        $0["coverageComplete"] = true
        $0["coverage"] = scalars.map { ["scalar": $0, "glyphs": [1]] as [String: Any] }
      }
    }
    fullPrimary["status"] = "selected"
    _ = try FontPreflightProof.configuration(primary: fullPrimary, fallback: fallback, scalars: scalars)
    try require(configuration.count == 5 && configuration["status"] as? String == "combination-only", "fixed configuration shape")
    try FontPreflightProof.validateFileIdentities(configuration: configuration, systemRoot: system)
    try FontPreflightProof.validateCandidateFileIdentities(primary, systemRoot: system)
    let roundTrip = try JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: configuration)) as! [String: Any]
    try require(NSDictionary(dictionary: roundTrip).isEqual(NSDictionary(dictionary: configuration)), "exact JSON integer/stat round trip")

    print("PHASE: font metadata fixed identity, independent roles and complete scalar coverage")
    func rejectsCandidate(_ label: String, _ record: [String: Any], id: String = "songti") throws {
      try rejects(label) { _ = try FontPreflightProof.validateCandidate(record, id: id, scalars: scalars) }
    }
    var changed = primary
    changed["family"] = "Heiti SC"
    try rejectsCandidate("wrong fixed family", changed)
    changed = primary; changed["id"] = "heiti"
    try rejectsCandidate("wrong fixed ID", changed)
    for status in ["selected", "unavailable", "identity-invalid", "combination-only"] {
      changed = primary; changed["status"] = status
      try rejectsCandidate("partial coverage cannot claim \(status)", changed)
    }
    changed = fallback; changed["status"] = "partial-coverage"
    try rejectsCandidate("complete faces cannot claim partial coverage", changed, id: "heiti")
    changed = primary; changed.removeValue(forKey: "bold")
    try rejectsCandidate("missing bold role", changed)
    try rejectsCandidate("duplicated role name", alter(primary, role: "bold") { $0["referenceRole"] = "regular" })
    try rejectsCandidate("unbound PostScript name", alter(primary) { $0["postScriptName"] = "Uninventoried" })
    let regularPS = (primary["regular"] as! [String: Any])["postScriptName"]!
    try rejectsCandidate("one PostScript face cannot satisfy two roles", alter(primary, role: "bold") { $0["postScriptName"] = regularPS })
    for (key, value) in [("enabled", false), ("downloadable", true), ("italic", true), ("bold", true)] {
      changed = primary
      var inventory = changed["inventoryFaces"] as! [[String: Any]]
      inventory[0][key] = value
      changed["inventoryFaces"] = inventory
      try rejectsCandidate("invalid inventoried \(key)", changed)
    }
    changed = primary
    var inventory = changed["inventoryFaces"] as! [[String: Any]]
    inventory[1] = inventory[0]
    changed["inventoryFaces"] = inventory
    try rejectsCandidate("duplicate inventoried PostScript name", changed)
    changed = primary; changed["availableFaces"] = true
    try rejectsCandidate("Boolean is not an inventory count", changed)
    for key in ["inventoryEnabled", "inventoryDownloadable", "dataDescriptorRegistered"] {
      try rejectsCandidate("invalid face state \(key)", alter(primary) { $0[key] = key != "inventoryEnabled" })
    }
    try rejectsCandidate("numeric value is not a Boolean", alter(primary) { $0["inventoryEnabled"] = 1 })
    for key in ["reason", "error"] {
      changed = primary; changed[key] = "noncoverage failure"
      try rejectsCandidate("partial coverage cannot conceal a noncoverage failure", changed)
    }
    try rejectsCandidate("wrong CT options", alter(primary) { $0["options"] = ["preventAutoActivation"] })
    try rejectsCandidate("changed reference weight", alter(primary) { $0["weight"] = 0.7 })
    try rejectsCandidate("nonfinite reference weight", alter(primary) { $0["weight"] = Double.nan })
    try rejectsCandidate("changed reference traits", alter(primary) { $0["symbolicTraits"] = 2 })
    changed = primary
    var wrongTraitsInventory = changed["inventoryFaces"] as! [[String: Any]]
    wrongTraitsInventory[0]["symbolicTraits"] = 1
    changed["inventoryFaces"] = wrongTraitsInventory
    changed = alter(changed) { $0["symbolicTraits"] = 1 }
    try rejectsCandidate("matching but italic reference traits", changed)
    try rejectsCandidate("wrong inventoried file", alter(primary) { $0["systemFile"] = "other.ttc" })
    for path in ["/outside.ttc", "../outside.ttc", "nested/../songti.ttc", "nested//songti.ttc", "./songti.ttc", "nested\\songti.ttc"] {
      try rejectsCandidate("unsafe relative path", alter(primary) { $0["systemRelativePath"] = path })
    }
    for hash in ["", String(repeating: "a", count: 63), String(repeating: "A", count: 64), String(repeating: "g", count: 64)] {
      try rejectsCandidate("malformed file digest", alter(primary) { $0["fileSHA256"] = hash })
    }
    for size in [0, -1, FontPreflightProof.maximumFontBytes + 1] {
      try rejectsCandidate("out of range file size", alter(primary) { $0["fileBytes"] = size })
    }
    try rejectsCandidate("missing file identity", alter(primary) { $0.removeValue(forKey: "fileIdentity") })
    try rejectsCandidate("missing identity precision", alter(primary) {
      var identity = $0["fileIdentity"] as! [String: Any]; identity.removeValue(forKey: "ctimeNanoseconds"); $0["fileIdentity"] = identity
    })
    try rejectsCandidate("changed identity size", alter(primary) {
      var identity = $0["fileIdentity"] as! [String: Any]; identity["size"] = 1; $0["fileIdentity"] = identity
    })
    try rejectsCandidate("out of range nanoseconds", alter(primary) {
      var identity = $0["fileIdentity"] as! [String: Any]; identity["mtimeNanoseconds"] = 1_000_000_000; $0["fileIdentity"] = identity
    })
    try rejectsCandidate("Boolean identity inode", alter(primary) {
      var identity = $0["fileIdentity"] as! [String: Any]; identity["inode"] = true; $0["fileIdentity"] = identity
    })
    try rejectsCandidate("missing scalar", alter(primary) { var c = $0["coverage"] as! [[String: Any]]; c.removeLast(); $0["coverage"] = c })
    try rejectsCandidate("duplicate scalar", alter(primary) { var c = $0["coverage"] as! [[String: Any]]; c[1] = c[0]; $0["coverage"] = c })
    try rejectsCandidate("unknown scalar", alter(primary) { var c = $0["coverage"] as! [[String: Any]]; c[0]["scalar"] = "U+2603"; $0["coverage"] = c })
    let invalidGlyphSets: [[Any]] = [[], [0, 1], [-1], [65536], [true], [1.5], ["1"]]
    for invalidGlyphs in invalidGlyphSets {
      try rejectsCandidate("invalid BMP glyph value", alter(primary) { var c = $0["coverage"] as! [[String: Any]]; c[0]["glyphs"] = invalidGlyphs; $0["coverage"] = c })
    }
    try rejectsCandidate("incorrect coverageComplete", alter(primary) { $0["coverageComplete"] = true })
    // Complete union across two roles is not sufficient: each role must stand on
    // its own. Marking only bold complete must not rescue a missing regular GID.
    var mixedFallback = alter(fallback) {
      var c = $0["coverage"] as! [[String: Any]]; c[0]["glyphs"] = [0]; $0["coverage"] = c; $0["coverageComplete"] = false
    }
    mixedFallback["status"] = "partial-coverage"
    try rejects("regular/bold cross-role coverage mixing") {
      _ = try FontPreflightProof.configuration(primary: primary, fallback: mixedFallback, scalars: scalars)
    }
    try rejects("duplicate expected scalar universe") {
      _ = try FontPreflightProof.validateCandidate(primary, id: "songti", scalars: scalars + [scalars.last!])
    }
    try rejects("non-BMP scalar universe") {
      _ = try FontPreflightProof.validateCandidate(primary, id: "songti", scalars: ["U+1F600"])
    }

    print("PHASE: bounded manifest fd, attempt provenance and fresh primary equality")
    func attempt(_ name: String) throws -> (matrix: URL, caseRoot: URL, manifest: URL) {
      let matrix = root.appendingPathComponent(name, isDirectory: true)
      let caseRoot = matrix.appendingPathComponent("songti-heiti-forward", isDirectory: true)
      try fm.createDirectory(at: caseRoot, withIntermediateDirectories: true)
      return (matrix, caseRoot, matrix.appendingPathComponent("songti-heiti-manifest.json"))
    }
    func manifestBytes(_ matrix: URL, mutate: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
      var document: [String: Any] = ["schema": 1, "matrixDirectory": matrix.path, "configuration": configuration]
      mutate(&document)
      return try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
    }
    func load(_ fixture: (matrix: URL, caseRoot: URL, manifest: URL), hash: String,
              freshPrimary: [String: Any]? = nil) throws -> (configuration: [String: Any], manifestInputBytes: Int) {
      try FontPreflightProof.loadConfiguration(manifest: fixture.manifest, expectedSHA256: hash,
        caseRoot: fixture.caseRoot, primary: freshPrimary ?? primary, scalars: scalars, systemRoot: system)
    }
    let valid = try attempt("valid")
    let validBytes = try manifestBytes(valid.matrix)
    try validBytes.write(to: valid.manifest, options: .withoutOverwriting)
    let loaded = try load(valid, hash: digest(validBytes))
    try require(loaded.manifestInputBytes == validBytes.count, "manifest byte accounting must be independent")
    try require(NSDictionary(dictionary: loaded.configuration).isEqual(NSDictionary(dictionary: configuration)), "loaded fixed configuration")
    try rejects("wrong independent hash") { _ = try load(valid, hash: String(repeating: "0", count: 64)) }
    try rejects("malformed independent hash") { _ = try load(valid, hash: "not-a-hash") }
    let differentPrimary = alter(primary) { $0["fileSHA256"] = String(repeating: "f", count: 64) }
    try rejects("fresh primary mismatch") { _ = try load(valid, hash: digest(validBytes), freshPrimary: differentPrimary) }
    let wrongName = try write("wrong-name.json", validBytes, in: valid.matrix)
    try rejects("wrong fixed manifest filename") {
      _ = try FontPreflightProof.loadConfiguration(manifest: wrongName, expectedSHA256: digest(validBytes),
        caseRoot: valid.caseRoot, primary: primary, scalars: scalars, systemRoot: system)
    }
    let old = try attempt("copied-old-attempt")
    try validBytes.write(to: old.manifest, options: .withoutOverwriting)
    try rejects("manifest copied from another matrix attempt") { _ = try load(old, hash: digest(validBytes)) }
    for mutation in ["schema", "extra-top", "extra-config", "css-family", "configuration-id", "configuration-status", "primary-bool-as-number"] {
      let fixture = try attempt(mutation)
      let bytes = try manifestBytes(fixture.matrix) { document in
        if mutation == "schema" { document["schema"] = true }
        else if mutation == "extra-top" { document["extra"] = "not allowed" }
        else {
          var c = document["configuration"] as! [String: Any]
          if mutation == "extra-config" { c["css"] = "unexpected" }
          if mutation == "css-family" { c["family"] = "Arial';src:url(https://invalid.example)" }
          if mutation == "configuration-id" { c["id"] = "heiti-songti" }
          if mutation == "configuration-status" { c["status"] = "selected" }
          if mutation == "primary-bool-as-number" {
            c["primary"] = alter(primary) { $0["inventoryEnabled"] = 1 }
          }
          document["configuration"] = c
        }
      }
      try bytes.write(to: fixture.manifest, options: .withoutOverwriting)
      try rejects("invalid manifest \(mutation)") { _ = try load(fixture, hash: digest(bytes)) }
    }
    let symlink = try attempt("symlink")
    try fm.createSymbolicLink(at: symlink.manifest, withDestinationURL: valid.manifest)
    try rejects("symlink manifest") { _ = try load(symlink, hash: digest(validBytes)) }
    let directory = try attempt("directory")
    try fm.createDirectory(at: directory.manifest, withIntermediateDirectories: false)
    try rejects("directory manifest") { _ = try load(directory, hash: digest(validBytes)) }
    let fifo = try attempt("fifo")
    guard mkfifo(fifo.manifest.path, mode_t(0o600)) == 0 else { throw Failure(message: "cannot create owned FIFO") }
    try rejects("FIFO manifest must reject without blocking") { _ = try load(fifo, hash: digest(validBytes)) }
    let oversized = try attempt("oversized")
    let oversizedFD = Darwin.open(oversized.manifest.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, mode_t(0o600))
    guard oversizedFD >= 0 else { throw Failure(message: "cannot create owned sparse manifest") }
    let truncateResult = ftruncate(oversizedFD, off_t(FontPreflightProof.maximumManifestBytes + 1))
    Darwin.close(oversizedFD)
    try require(truncateResult == 0, "cannot size owned sparse manifest")
    try rejects("oversized manifest") { _ = try load(oversized, hash: digest(validBytes)) }
    let empty = try attempt("empty")
    try Data().write(to: empty.manifest, options: .withoutOverwriting)
    try rejects("empty manifest") { _ = try load(empty, hash: digest(Data())) }
    let malformed = try attempt("invalid-json")
    let malformedBytes = Data("not json".utf8)
    try malformedBytes.write(to: malformed.manifest, options: .withoutOverwriting)
    try rejects("malformed manifest JSON") { _ = try load(malformed, hash: digest(malformedBytes)) }

    print("PHASE: synthetic stat identity, descriptor binding and change detection")
    let font = system.appendingPathComponent("songti.ttc")
    let before = try FontPreflightProof.identity(of: font, under: system)
    let fd = Darwin.open(font.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard fd >= 0 else { throw Failure(message: "cannot open owned synthetic file") }
    defer { Darwin.close(fd) }
    let fdIdentity = try FontPreflightProof.identity(ofFileDescriptor: fd)
    try require(NSDictionary(dictionary: before).isEqual(NSDictionary(dictionary: fdIdentity)), "path and opened-fd identity must match")
    try rejects("invalid descriptor") { _ = try FontPreflightProof.identity(ofFileDescriptor: -1) }
    let dirFD = Darwin.open(system.path, O_RDONLY | O_CLOEXEC)
    guard dirFD >= 0 else { throw Failure(message: "cannot open owned synthetic directory") }
    defer { Darwin.close(dirFD) }
    try rejects("nonregular descriptor") { _ = try FontPreflightProof.identity(ofFileDescriptor: dirFD) }
    let linkedFont = system.appendingPathComponent("linked.ttc")
    try fm.createSymbolicLink(at: linkedFont, withDestinationURL: font)
    try rejects("font symlink") { _ = try FontPreflightProof.identity(of: linkedFont, under: system) }
    let linkedDirectory = system.appendingPathComponent("linked-directory")
    try fm.createSymbolicLink(at: linkedDirectory, withDestinationURL: system)
    try rejects("symlink directory component") {
      _ = try FontPreflightProof.identity(of: linkedDirectory.appendingPathComponent("songti.ttc"), under: system)
    }
    try rejects("outside-root file") { _ = try FontPreflightProof.identity(of: valid.manifest, under: system) }
    try rejects("missing file") { _ = try FontPreflightProof.identity(of: system.appendingPathComponent("missing.ttc"), under: system) }
    try rejects("directory instead of font") { _ = try FontPreflightProof.identity(of: system, under: root) }
    // Change one nanosecond deterministically without sleeps or reading contents.
    let seconds = (before["mtimeSeconds"] as! NSNumber).int64Value
    let nanos = (before["mtimeNanoseconds"] as! NSNumber).int64Value
    let changedNanos = nanos == 999_999_999 ? nanos - 1 : nanos + 1
    let times = [timespec(tv_sec: 0, tv_nsec: Int(UTIME_OMIT)), timespec(tv_sec: Int(seconds), tv_nsec: Int(changedNanos))]
    let timeResult = times.withUnsafeBufferPointer { futimens(fd, $0.baseAddress!) }
    try require(timeResult == 0, "cannot change owned file timestamp")
    try rejects("nanosecond file-identity change") {
      try FontPreflightProof.validateFileIdentities(configuration: configuration, systemRoot: system)
    }
    try rejects("manifest with changed primary file identity") { _ = try load(valid, hash: digest(validBytes)) }
    // A separate fallback edit proves checks do not stop at primary or one role.
    let fallbackOnly = fallback
    let fallbackURL = system.appendingPathComponent("heiti.ttc")
    let handle = try FileHandle(forWritingTo: fallbackURL)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data([0]))
    try handle.close()
    try rejects("fallback file growth") { try FontPreflightProof.validateCandidateFileIdentities(fallbackOnly, systemRoot: system) }
    print("PASS: bounded manifest provenance, fixed roles/coverage and metadata-only file identities")
  }

  private static func alter(_ record: [String: Any], role: String = "regular", _ body: (inout [String: Any]) -> Void) -> [String: Any] {
    var changed = record, face = record[role] as! [String: Any]
    body(&face)
    changed[role] = face
    return changed
  }
  private static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
  private static func require(_ condition: Bool, _ message: String) throws {
    guard condition else { throw Failure(message: message) }
  }
  private static func rejects(_ label: String, _ body: () throws -> Void) throws {
    do { try body() } catch { return }
    throw Failure(message: "expected rejection: \(label)")
  }
}
