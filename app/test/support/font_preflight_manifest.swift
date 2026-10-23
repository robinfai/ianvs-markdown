import CryptoKit
import CoreFoundation
import Darwin
import Foundation

/// Test-only validation of prior census metadata. This helper never reads font
/// contents, constructs CTFont objects, or chooses CSS from manifest strings.
/// A digest supplied independently by the runner and an attempt-directory binding
/// detect stale/copied/accidentally changed metadata, not a same-privilege attacker.
/// File stat identities are change detectors, not content snapshots or evidence
/// of the fonts WebKit actually selected. Native PDF evidence remains necessary.
enum FontPreflightProof {
  static let systemFontsRoot = URL(fileURLWithPath: "/System/Library/Fonts", isDirectory: true)
  static let maximumFontBytes = 64 * 1024 * 1024
  static let maximumManifestBytes = 2 * 1024 * 1024
  private static let roles = ["regular", "bold"]
  private static let identityKeys: Set<String> = [
    "device", "inode", "size", "mtimeSeconds", "mtimeNanoseconds", "ctimeSeconds", "ctimeNanoseconds",
  ]

  struct Failure: LocalizedError {
    let message: String
    var errorDescription: String? { "Font preflight proof: \(message)" }
  }

  /// JSON-safe exact integers, never floating-point dates: device/size/time fields
  /// are Int64, inode is UInt64. Darwin timestamps retain nanosecond precision.
  /// Callers supply canonical paths. `root` injection is for owned test fixtures.
  static func identity(of url: URL, under root: URL = systemFontsRoot) throws -> [String: Any] {
    try requireCanonicalDirectory(root)
    guard url.isFileURL, url.path == url.standardizedFileURL.path,
          url.path == url.resolvingSymlinksInPath().standardizedFileURL.path,
          url.path.hasPrefix(root.path + "/") else {
      throw Failure(message: "file path must be canonical, non-symlink and under the system root")
    }
    let relative = String(url.path.dropFirst(root.path.count + 1))
    _ = try relativeComponents(relative)
    var current = root
    var finalInfo = stat()
    let components = relative.split(separator: "/").map(String.init)
    for (index, component) in components.enumerated() {
      current.appendPathComponent(component)
      var info = stat()
      guard lstat(current.path, &info) == 0 else { throw io("lstat file identity") }
      let expected = index == components.count - 1 ? S_IFREG : S_IFDIR
      guard (info.st_mode & S_IFMT) == expected else {
        throw Failure(message: "file identity requires a regular file and non-symlink directories")
      }
      finalInfo = info
    }
    return statIdentity(finalInfo)
  }

  /// Stat-only descriptor identity for the caller's bounded font-data reader.
  /// The caller owns and closes the descriptor; no bytes are read here.
  static func identity(ofFileDescriptor fd: Int32) throws -> [String: Any] {
    var info = stat()
    guard fstat(fd, &info) == 0 else { throw io("fstat file identity") }
    guard (info.st_mode & S_IFMT) == S_IFREG else {
      throw Failure(message: "file descriptor identity requires a regular file")
    }
    return statIdentity(info)
  }

  /// Returns whether BOTH independently checked reference roles are complete.
  /// Partial coverage is accepted only as the explicitly named partial status.
  static func validateCandidate(_ record: [String: Any], id: String, scalars: [String]) throws -> Bool {
    let expectedScalars = try scalarUniverse(scalars)
    let family: String
    switch id {
    case "songti": family = "Songti SC"
    case "pingfang": family = "PingFang SC"
    case "heiti": family = "Heiti SC"
    default: throw Failure(message: "candidate ID is not an approved fixed family")
    }
    guard record["id"] as? String == id, record["family"] as? String == family,
          record["reason"] == nil, record["error"] == nil else {
      throw Failure(message: "candidate family identity mismatch")
    }
    guard let inventory = record["inventoryFaces"] as? [[String: Any]],
          (1...64).contains(inventory.count),
          try integer(record["availableFaces"], named: "availableFaces") == Int64(inventory.count) else {
      throw Failure(message: "candidate inventory is absent or inconsistent")
    }
    var inventoriedNames = Set<String>()
    for face in inventory {
      guard let name = face["postScriptName"] as? String, !name.isEmpty,
            name.utf8.count <= 256, inventoriedNames.insert(name).inserted else {
        throw Failure(message: "duplicate or invalid inventory PostScript name")
      }
    }
    var allComplete = true
    var referenceNames = Set<String>()
    for role in roles {
      guard let face = record[role] as? [String: Any],
            face["referenceRole"] as? String == role,
            let postScript = face["postScriptName"] as? String,
            referenceNames.insert(postScript).inserted,
            let relative = face["systemRelativePath"] as? String else {
        throw Failure(message: "missing, duplicate or invalid reference role")
      }
      let components = try relativeComponents(relative)
      guard let fileName = components.last, face["systemFile"] as? String == fileName,
            let inventoried = inventory.first(where: { $0["postScriptName"] as? String == postScript }),
            inventoried["fileName"] as? String == fileName,
            isBool(inventoried["enabled"], equalTo: true),
            isBool(inventoried["downloadable"], equalTo: false),
            isBool(inventoried["italic"], equalTo: false),
            isBool(inventoried["bold"], equalTo: role == "bold"),
            isBool(face["inventoryEnabled"], equalTo: true),
            isBool(face["inventoryDownloadable"], equalTo: false),
            isBool(face["dataDescriptorRegistered"], equalTo: false),
            face["options"] as? [String] == ["preventAutoActivation", "preventAutoDownload"],
            face["reason"] == nil, face["error"] == nil else {
        throw Failure(message: "reference face does not match eligible inventory identity and state")
      }
      let recordedWeight = try finiteNumber(face["weight"], named: "reference weight")
      let inventoryWeight = try finiteNumber(inventoried["weight"], named: "inventory weight")
      let traits = try integer(face["symbolicTraits"], named: "reference symbolicTraits")
      let inventoryTraits = try integer(inventoried["symbolicTraits"], named: "inventory symbolicTraits")
      guard recordedWeight == inventoryWeight, traits == inventoryTraits,
            (0...Int64(UInt32.max)).contains(traits), traits & 1 == 0,
            (traits & 2 != 0) == (role == "bold") else {
        throw Failure(message: "reference weight or symbolic traits do not match its inventory and role")
      }
      guard let digest = face["fileSHA256"] as? String, validSHA256(digest) else {
        throw Failure(message: "reference face requires a lowercase SHA256 digest")
      }
      let bytes = try integer(face["fileBytes"], named: "fileBytes")
      guard bytes > 0, bytes <= Int64(maximumFontBytes),
            let fileIdentity = face["fileIdentity"] as? [String: Any] else {
        throw Failure(message: "reference file size or identity is invalid")
      }
      try validateIdentity(fileIdentity, expectedSize: bytes)
      let covered = try coverage(face, expected: expectedScalars)
      let complete = covered.count == expectedScalars.count
      guard isBool(face["coverageComplete"], equalTo: complete) else {
        throw Failure(message: "coverageComplete does not match the recorded glyphs")
      }
      allComplete = allComplete && complete
    }
    guard record["status"] as? String == (allComplete ? "selected" : "partial-coverage") else {
      throw Failure(message: "candidate status is inconsistent with per-role coverage")
    }
    return allComplete
  }

  static func configuration(primary: [String: Any], fallback: [String: Any], scalars: [String]) throws -> [String: Any] {
    _ = try validateCandidate(primary, id: "songti", scalars: scalars)
    guard try validateCandidate(fallback, id: "heiti", scalars: scalars) else {
      throw Failure(message: "fallback must independently cover every scalar in both roles")
    }
    let expected = try scalarUniverse(scalars)
    for role in roles {
      let primaryCovered = try coverage(primary[role] as! [String: Any], expected: expected)
      let fallbackCovered = try coverage(fallback[role] as! [String: Any], expected: expected)
      guard primaryCovered.union(fallbackCovered) == expected else {
        throw Failure(message: "same-role primary/fallback coverage union is incomplete")
      }
    }
    return ["id": "songti-heiti", "family": "Songti SC + Heiti SC", "status": "combination-only",
            "primary": primary, "fallback": fallback]
  }

  /// Reads only the runner's small JSON manifest using a single bounded fd.
  /// The returned byte count is separate from configuration and font Data input.
  static func loadConfiguration(manifest: URL, expectedSHA256: String, caseRoot: URL,
                                primary: [String: Any], scalars: [String],
                                systemRoot: URL = systemFontsRoot) throws
    -> (configuration: [String: Any], manifestInputBytes: Int) {
    guard validSHA256(expectedSHA256) else { throw Failure(message: "invalid expected manifest SHA256") }
    try requireCanonicalDirectory(caseRoot)
    let matrix = caseRoot.deletingLastPathComponent()
    try requireCanonicalDirectory(matrix)
    let expectedPath = matrix.appendingPathComponent("songti-heiti-manifest.json").path
    guard manifest.isFileURL, manifest.path == expectedPath,
          manifest.standardizedFileURL.path == expectedPath else {
      throw Failure(message: "manifest must have its fixed filename directly in the current matrix directory")
    }
    let data = try readBoundedManifest(manifest)
    let actualSHA256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    guard actualSHA256 == expectedSHA256 else { throw Failure(message: "manifest SHA256 mismatch") }
    guard let document = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          Set(document.keys) == Set(["schema", "matrixDirectory", "configuration"]),
          try integer(document["schema"], named: "manifest schema") == 1,
          document["matrixDirectory"] as? String == matrix.path,
          let stored = document["configuration"] as? [String: Any],
          Set(stored.keys) == Set(["id", "family", "status", "primary", "fallback"]),
          let storedPrimary = stored["primary"] as? [String: Any],
          let fallback = stored["fallback"] as? [String: Any] else {
      throw Failure(message: "manifest schema, matrix-directory attempt identity or fixed configuration is invalid")
    }
    // NSDictionary equality intentionally bridges JSON integer representations;
    // validate stored booleans/types too so NSNumber true/1 equivalence cannot
    // conceal a malformed copy of the otherwise fresh primary record.
    _ = try validateCandidate(storedPrimary, id: "songti", scalars: scalars)
    guard equal(storedPrimary, primary) else { throw Failure(message: "manifest primary does not equal the fresh inventory") }
    let checked = try configuration(primary: primary, fallback: fallback, scalars: scalars)
    guard equal(stored, checked) else { throw Failure(message: "manifest configuration does not equal the fixed recomputed configuration") }
    try validateFileIdentities(configuration: checked, systemRoot: systemRoot)
    return (checked, data.count)
  }

  /// Metadata-only checks before/after rendering. No font contents are read.
  static func validateFileIdentities(configuration: [String: Any], systemRoot: URL = systemFontsRoot) throws {
    guard configuration["id"] as? String == "songti-heiti",
          configuration["family"] as? String == "Songti SC + Heiti SC",
          configuration["status"] as? String == "combination-only" else {
      throw Failure(message: "file identity check requires the fixed configuration")
    }
    for candidateKey in ["primary", "fallback"] {
      guard let candidate = configuration[candidateKey] as? [String: Any] else {
        throw Failure(message: "file identity check is missing a candidate")
      }
      try validateCandidateFileIdentities(candidate, systemRoot: systemRoot)
    }
  }

  /// The solo diagnostic uses the same checks without inventing a combination.
  static func validateCandidateFileIdentities(_ candidate: [String: Any],
                                             systemRoot: URL = systemFontsRoot) throws {
    for role in roles {
      guard let face = candidate[role] as? [String: Any],
            let relative = face["systemRelativePath"] as? String,
            let recorded = face["fileIdentity"] as? [String: Any] else {
        throw Failure(message: "file identity check is missing a reference identity")
      }
      _ = try relativeComponents(relative)
      let bytes = try integer(face["fileBytes"], named: "fileBytes")
      try validateIdentity(recorded, expectedSize: bytes)
      let actual = try identity(of: systemRoot.appendingPathComponent(relative), under: systemRoot)
      guard equal(recorded, actual) else { throw Failure(message: "recorded file identity changed") }
    }
  }

  private static func scalarUniverse(_ scalars: [String]) throws -> Set<String> {
    guard !scalars.isEmpty, scalars.count <= 256, scalars == scalars.sorted(),
          Set(scalars).count == scalars.count else {
      throw Failure(message: "expected scalar universe must be unique, nonempty and sorted")
    }
    for scalar in scalars {
      guard scalar.count == 6, scalar.hasPrefix("U+"),
            let value = UInt32(scalar.dropFirst(2), radix: 16),
            value <= 0xFFFF, !(0xD800...0xDFFF).contains(value),
            scalar == String(format: "U+%04X", value) else {
        throw Failure(message: "expected scalar universe supports canonical BMP scalars only")
      }
    }
    return Set(scalars)
  }

  private static func coverage(_ face: [String: Any], expected: Set<String>) throws -> Set<String> {
    guard let table = face["coverage"] as? [[String: Any]], table.count == expected.count else {
      throw Failure(message: "coverage table has missing or extra scalars")
    }
    var seen = Set<String>(), covered = Set<String>()
    for row in table {
      guard Set(row.keys) == Set(["scalar", "glyphs"]), let scalar = row["scalar"] as? String,
            expected.contains(scalar), seen.insert(scalar).inserted,
            let glyphs = row["glyphs"] as? [Any], glyphs.count == 1 else {
        throw Failure(message: "coverage has a duplicate/unknown scalar or invalid BMP glyph count")
      }
      let glyph = try integer(glyphs[0], named: "coverage glyph")
      guard (0...65535).contains(glyph) else { throw Failure(message: "coverage glyph is outside UInt16 range") }
      if glyph != 0 { covered.insert(scalar) }
    }
    guard seen == expected else { throw Failure(message: "coverage table is missing an expected scalar") }
    return covered
  }

  private static func relativeComponents(_ path: String) throws -> [String] {
    let components = path.components(separatedBy: "/")
    guard !path.isEmpty, path.utf8.count <= 4096, !path.contains("\\"), !path.contains("\0"),
          components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
      throw Failure(message: "systemRelativePath must stay strictly under the system root")
    }
    return components
  }

  private static func requireCanonicalDirectory(_ url: URL) throws {
    guard url.isFileURL, url.path == url.standardizedFileURL.path,
          url.path == url.resolvingSymlinksInPath().standardizedFileURL.path else {
      throw Failure(message: "directory must be canonical and non-symlink")
    }
    var info = stat()
    guard lstat(url.path, &info) == 0 else { throw io("lstat directory") }
    guard (info.st_mode & S_IFMT) == S_IFDIR else { throw Failure(message: "expected an existing directory") }
  }

  private static func statIdentity(_ info: stat) -> [String: Any] {
    ["device": Int64(info.st_dev), "inode": UInt64(info.st_ino), "size": Int64(info.st_size),
     "mtimeSeconds": Int64(info.st_mtimespec.tv_sec), "mtimeNanoseconds": Int64(info.st_mtimespec.tv_nsec),
     "ctimeSeconds": Int64(info.st_ctimespec.tv_sec), "ctimeNanoseconds": Int64(info.st_ctimespec.tv_nsec)]
  }

  private static func validateIdentity(_ value: [String: Any], expectedSize: Int64) throws {
    guard Set(value.keys) == identityKeys, expectedSize > 0, expectedSize <= Int64(maximumFontBytes),
          try integer(value["device"], named: "identity device") >= 0,
          try unsignedInteger(value["inode"], named: "identity inode") > 0,
          try integer(value["size"], named: "identity size") == expectedSize else {
      throw Failure(message: "file identity fields or size are invalid")
    }
    for key in ["mtimeSeconds", "ctimeSeconds"] { _ = try integer(value[key], named: key) }
    for key in ["mtimeNanoseconds", "ctimeNanoseconds"] {
      let nanos = try integer(value[key], named: key)
      guard (0..<1_000_000_000).contains(nanos) else { throw Failure(message: "identity timestamp precision is invalid") }
    }
  }

  private static func finiteNumber(_ value: Any?, named name: String) throws -> Double {
    guard let number = value as? NSNumber, !isBoolean(number), number.doubleValue.isFinite else {
      throw Failure(message: "\(name) must be a finite number")
    }
    return number.doubleValue
  }
  private static func integer(_ value: Any?, named name: String) throws -> Int64 {
    guard let number = value as? NSNumber, !isBoolean(number),
          let integer = Int64(number.stringValue) else { throw Failure(message: "\(name) must be an exact integer") }
    return integer
  }
  private static func unsignedInteger(_ value: Any?, named name: String) throws -> UInt64 {
    guard let number = value as? NSNumber, !isBoolean(number),
          let integer = UInt64(number.stringValue) else { throw Failure(message: "\(name) must be an exact unsigned integer") }
    return integer
  }
  private static func isBoolean(_ number: NSNumber) -> Bool {
    CFGetTypeID(number) == CFBooleanGetTypeID()
  }
  private static func isBool(_ value: Any?, equalTo expected: Bool) -> Bool {
    guard let number = value as? NSNumber, isBoolean(number) else { return false }
    return number.boolValue == expected
  }
  private static func validSHA256(_ value: String) -> Bool {
    value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }
  private static func equal(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
    NSDictionary(dictionary: lhs).isEqual(NSDictionary(dictionary: rhs))
  }
  private static func io(_ action: String) -> Failure { Failure(message: "\(action) failed (errno \(errno))") }

  private static func readBoundedManifest(_ url: URL) throws -> Data {
    let fd = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
    guard fd >= 0 else { throw io("open manifest") }
    defer { Darwin.close(fd) }
    var initial = stat()
    guard fstat(fd, &initial) == 0 else { throw io("fstat manifest") }
    guard (initial.st_mode & S_IFMT) == S_IFREG,
          initial.st_size > 0, initial.st_size <= Int64(maximumManifestBytes) else {
      throw Failure(message: "manifest must be regular, nonempty and no larger than 2 MiB")
    }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
      let count = buffer.withUnsafeMutableBytes { bytes in
        Darwin.read(fd, bytes.baseAddress!, min(bytes.count, maximumManifestBytes - data.count + 1))
      }
      if count < 0, errno == EINTR { continue }
      guard count >= 0 else { throw io("read manifest") }
      if count == 0 { break }
      guard count <= maximumManifestBytes - data.count else { throw Failure(message: "manifest grew beyond 2 MiB") }
      data.append(contentsOf: buffer.prefix(count))
    }
    var final = stat(), atPath = stat()
    guard fstat(fd, &final) == 0, lstat(url.path, &atPath) == 0 else { throw io("restat manifest") }
    guard data.count == Int(initial.st_size),
          equal(statIdentity(initial), statIdentity(final)),
          (atPath.st_mode & S_IFMT) == S_IFREG,
          equal(statIdentity(final), statIdentity(atPath)) else {
      throw Failure(message: "manifest identity changed while reading")
    }
    return data
  }
}
