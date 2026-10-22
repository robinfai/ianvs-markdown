import Foundation
import Darwin
import CryptoKit
#if os(iOS)
import Flutter
#else
import FlutterMacOS
#endif

/// Single-note move with a bounded, durable, app-private recovery journal.
/// Coordination is advisory. The executor must keep per-file body replacement
/// atomic, with displaced versions retained and originals synced first.
/// There is deliberately no rollback, unlink, or overwrite-recovery operation.
final class WorkspaceNoteTransaction {
  static let shared = WorkspaceNoteTransaction()
  static let methods: Set<String> = ["prepareWorkspaceNoteMove", "executeWorkspaceNoteMove",
    "listWorkspaceNoteMoves", "reconcileWorkspaceNoteMove", "recoverWorkspaceNoteMove",
    "cancelPreparedWorkspaceNoteMove"]
  static let maximumFiles = 128
  static let maximumPayloadBytes = 32 * 1024 * 1024
  static let maximumJournalBytes = 192 * 1024 * 1024
  static let maximumRecords = 32
  static let maximumArtifactReservationBytes = 192 * 1024 * 1024
  static let maximumCatalogEntries = 50_000
  // No production caller supplies fault hooks or a journal directory.
  var fault: ((String) throws -> Void)?
  var availableBytesOverride: ((String, Int32, UInt64) -> UInt64)?
  var parentDeviceOverride: ((String, Int32) -> Int32)?
  var parentAccessOverride: ((String, Bool) -> Bool)?
  var forceDependencyTimeout = false
  // Read-only synthetic-test observer. Never exposed on the Flutter channel;
  // the production singleton leaves it nil and emits no path diagnostics.
  struct CoordinationObservation {
    let expectedSource: URL
    let observedSource: URL
    let expectedDestination: URL?
    let observedDestination: URL?
    let moving: Bool
    let deadlineExpired: Bool
  }
  var coordinationObserver: ((CoordinationObservation) -> Void)?
  private let journalURL: URL
  private let journalBaseURL: URL
  private var journalIdentity: String?
  private var journalCanonicalURL: URL?
  private let maximumStoredBytes: Int
  private let maximumStoredRecords: Int
  private var sessions: [String: Session] = [:]
  // Bounded by retained journals/live grants (at most maximumRecords). Preserve
  // an observed failure in process even when every attempt to save it fails.
  private var observedConsistencyConflicts = Set<String>()
  private var unpersistedUncertainty = Set<String>()

  init(journalDirectory: URL? = nil, maximumStoredBytes: Int = WorkspaceNoteTransaction.maximumJournalBytes,
       maximumStoredRecords: Int = WorkspaceNoteTransaction.maximumRecords) {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    self.journalURL = (journalDirectory ?? support.appendingPathComponent("Linefold/NoteMoveJournal", isDirectory: true)).standardizedFileURL
    self.journalBaseURL = (journalDirectory?.deletingLastPathComponent() ?? support).standardizedFileURL
    self.maximumStoredBytes = min(maximumStoredBytes, Self.maximumJournalBytes)
    self.maximumStoredRecords = min(maximumStoredRecords, Self.maximumRecords)
  }

  private struct Failure: Error, LocalizedError {
    let code: String
    var errorDescription: String? { code }
    init(_ code: String) { self.code = code }
  }
  private struct Entry: Codable {
    let path: String
    let destinationPath: String
    let expectedRevision: String
    let expectedIdentity: String
    let parentIdentity: String
    let destinationParentIdentity: String
    let original: Data
    let replacement: Data
    let originalHash: String
    let replacementHash: String
    let permissions: UInt32
    let owner: UInt32
    let group: UInt32
    let protectionClass: Int32?
    let artifactPath: String?
    var stagedIdentity: String?
    var stagedRevision: String?
    var displacedRevision: String?
    var artifactState = "pending"
    var state = "pending"
    var intent: String?
    var writeRevision: String?
    var moveRevision: String?
    var actualPath: String?
    var actualRevision: String?
  }
  private struct Recovery: Codable {
    let sourcePath: String
    let path: String
    let parentIdentity: String
    var identity: String?
    var revision: String?
    var state = "pending"
  }
  private final class Record: Codable {
    var version = 1
    let transactionId: String
    let rootPath: String
    let rootIdentity: String
    let sourcePath: String
    let destinationPath: String
    let catalogDigest: String
    let created: Double
    var phase = "prepared"
    var code: String?
    var entries: [Entry]
    var recoveries: [Recovery] = []
    var cancelled = false
    // An observed dependency change is sticky, including after restart.
    var consistencyConflict = false
    // Written only after final dependency verification. Without a live session,
    // restart cannot infer semantic completion from a moved inode alone.
    var completionVerified = false
    init(id: String, scope: WorkspaceTextScope, rootIdentity: String, source: String,
         destination: String, digest: String, entries: [Entry]) {
      transactionId = id; rootPath = scope.rootURL.path; self.rootIdentity = rootIdentity
      sourcePath = source; destinationPath = destination; catalogDigest = digest
      self.entries = entries; created = Date().timeIntervalSince1970
    }
  }
  private struct Metadata {
    let path: String
    let revision: String
    let isDirectory: Bool
    let local: Bool
  }
  private final class Parent {
    let descriptor: Int32
    let identity: String
    init(scope: WorkspaceFileScope, components: [String]) throws {
      descriptor = try scope.parentDescriptor(components)
      var value = stat()
      guard fstat(descriptor, &value) == 0, value.st_flags & UInt32(SF_DATALESS) == 0 else {
        close(descriptor); throw Failure("parent_unavailable")
      }
      identity = WorkspaceNoteTransaction.identity(value)
    }
    deinit { close(descriptor) }
  }
  private final class Session {
    let token = UUID().uuidString
    let scope: WorkspaceTextScope
    let parents: [String: Parent]
    let assets: [Metadata]
    init(scope: WorkspaceTextScope, parents: [String: Parent], assets: [Metadata]) {
      self.scope = scope; self.parents = parents; self.assets = assets
    }
  }
  private struct Snapshot {
    let bytes: Data; let revision: String; let identity: String
    let permissions: UInt32; let owner: UInt32; let group: UInt32
    let protectionClass: Int32?
  }

  /// Call only on CloudWorkspace's serial transaction queue.
  func perform(_ method: String, arguments: [String: Any]) -> Any {
    do {
      return try WorkspaceFileScope.withoutMaterialization {
        guard let path = arguments["path"] as? String, path.hasPrefix("/"), !path.contains("\0") else {
          throw Failure("invalid_request")
        }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        if method == "listWorkspaceNoteMoves" { return try list(root: root) }
        let id = try transactionId(arguments["transactionId"])
        switch method {
        case "prepareWorkspaceNoteMove": return try prepare(root: root, id: id, arguments: arguments)
        case "cancelPreparedWorkspaceNoteMove":
          let record = try load(id)
          guard let session = sessions[id], arguments["token"] as? String == session.token,
                !hasEvidenceOfMutation(record) else { throw Failure("cannot_cancel_mutated_transaction") }
          record.cancelled = true; record.phase = "cancelled"
          try save(record); sessions.removeValue(forKey: id)
          return result(record)
        case "executeWorkspaceNoteMove":
          return try execute(root: root, id: id, token: arguments["token"] as? String)
        case "reconcileWorkspaceNoteMove":
          let record = try load(id)
          try reconcile(record, scope: try authorizedScope(root, record: record))
          return result(record)
        case "recoverWorkspaceNoteMove":
          guard let directory = arguments["relativeDirectory"] as? String else { throw Failure("invalid_request") }
          return try recover(root: root, id: id, directory: directory)
        default: throw Failure("invalid_method")
        }
      }
    } catch {
      if let id = try? transactionId(arguments["transactionId"]), let record = try? load(id) {
        markUnverifiable(record); record.code = code(error)
        return result(record)
      }
      return ["transactionId": arguments["transactionId"] as? String ?? "",
              "phase": "blocked", "code": code(error), "retryAllowed": false,
              "entries": [], "recoveryPaths": []] as [String: Any]
    }
  }

  private func transactionId(_ raw: Any?) throws -> String {
    guard let value = raw as? String, let id = UUID(uuidString: value), id.uuidString == value.uppercased() else {
      throw Failure("invalid_transaction_id")
    }
    return id.uuidString.lowercased()
  }
  private static func identity(_ value: stat) -> String { "\(value.st_dev):\(value.st_ino)" }
  private static func identity(_ revision: String) -> String {
    revision.split(separator: ":").prefix(2).joined(separator: ":")
  }
  private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
  private func code(_ error: Error) -> String {
    if let value = error as? Failure { return value.code }
    if let value = error as? AttachmentError { return value.code }
    return "native_io_failure"
  }
  private func point(_ name: String) throws { try fault?(name) }
  private func components(_ path: String) throws -> [String] {
    try WorkspaceTextScope.textComponents(path, directory: false)
  }
  private func artifactComponents(_ path: String) throws -> [String] {
    let parts = try WorkspaceFileScope.relativeComponents(path)
    guard !parts.dropLast().contains(where: { $0.hasPrefix(".") }),
          let leaf = parts.last, leaf.hasPrefix(".linefold-note-move-"), leaf.hasSuffix(".md"),
          leaf.utf8.count <= 100 else { throw Failure("invalid_artifact") }
    return parts
  }
  private func scopeIdentity(_ scope: WorkspaceFileScope) throws -> String {
    try scope.verifyRootLocation()
    let fd = try scope.directoryDescriptor([]); defer { close(fd) }
    var info = stat()
    guard fstat(fd, &info) == 0, info.st_flags & UInt32(SF_DATALESS) == 0 else { throw Failure("scope_unavailable") }
    return Self.identity(info)
  }
  private func authorizedScope(_ root: URL, record: Record) throws -> WorkspaceTextScope {
    // Never silently reopen the old path for a live token. Restart reads/recovery
    // additionally require the persisted directory identity, not just its name.
    let scope = try sessions[record.transactionId]?.scope ?? WorkspaceTextScope(root)
    let requested = try WorkspaceTextScope(root)
    guard try scopeIdentity(requested) == record.rootIdentity,
          scope.rootURL.path == record.rootPath,
          try scopeIdentity(scope) == record.rootIdentity else { throw Failure("scope_changed") }
    return scope
  }
  private func verifyParent(_ session: Session, path: String) throws -> Parent {
    guard let parent = session.parents[path] else { throw Failure("invalid_manifest") }
    try verifyParent(scope: session.scope, path: path, parent: parent)
    return parent
  }
  private func verifyParent(scope: WorkspaceFileScope, path: String, parent: Parent) throws {
    try scope.verifyRootLocation()
    let current = try scope.parentDescriptor(try components(path)); defer { close(current) }
    var a = stat(); var b = stat()
    guard fstat(current, &a) == 0, fstat(parent.descriptor, &b) == 0,
          Self.identity(a) == parent.identity, Self.identity(b) == parent.identity,
          a.st_flags & UInt32(SF_DATALESS) == 0, b.st_flags & UInt32(SF_DATALESS) == 0 else {
      throw Failure("parent_changed")
    }
  }

  /// Metadata-only complete catalog. Per-directory budgets and a whole-walk
  /// deadline are independent of the transaction byte limit. No body is fetched.
  private func catalog(_ scope: WorkspaceTextScope) throws -> [Metadata] {
    let end = DispatchTime.now().uptimeNanoseconds + 10_000_000_000
    var pending = [""]; var rows: [Metadata] = []
    while let path = pending.popLast() {
      guard DispatchTime.now().uptimeNanoseconds < end else { throw Failure("catalog_limit") }
      let listing = try scope.listDirectory(relativePath: path)
      guard listing["complete"] as? Bool == true, let entries = listing["entries"] as? [[String: Any]] else {
        throw Failure("catalog_incomplete")
      }
      for entry in entries {
        guard rows.count < Self.maximumCatalogEntries,
              let relative = entry["relativePath"] as? String,
              let revision = entry["revision"] as? String,
              let directory = entry["isDirectory"] as? Bool,
              let local = entry["local"] as? Bool, local else { throw Failure("catalog_unavailable") }
        rows.append(Metadata(path: relative, revision: revision, isDirectory: directory, local: local))
        if directory { pending.append(relative) }
      }
    }
    try scope.verifyRootLocation()
    return rows
  }
  private func metadata(_ raw: Any?, assets: Bool = false) throws -> [Metadata] {
    guard let values = raw as? [[String: Any]], values.count <= Self.maximumCatalogEntries else { throw Failure("invalid_catalog") }
    var seen = Set<String>()
    return try values.map { row in
      guard let path = row["path"] as? String, let revision = row["revision"] as? String,
            !revision.isEmpty, revision.utf8.count <= 200, seen.insert(path).inserted else { throw Failure("invalid_catalog") }
      let directory = assets ? false : row["isDirectory"] as? Bool
      let local = assets ? true : row["local"] as? Bool
      guard let isDirectory = directory, let isLocal = local, isLocal else { throw Failure("catalog_unavailable") }
      let parts = try WorkspaceFileScope.relativeComponents(path)
      guard !parts.contains(where: { $0.hasPrefix(".") }) else { throw Failure("invalid_catalog") }
      return Metadata(path: path, revision: revision, isDirectory: isDirectory, local: isLocal)
    }
  }
  /// Reconstructible metadata-only read-set fingerprint. No unrelated rows are
  /// persisted. Non-note files are included so image dependencies can also be
  /// verified after restart without retaining their paths in the journal.
  private func dependencyDigest(_ scope: WorkspaceTextScope, excluding: Set<String>) throws -> String {
    guard !forceDependencyTimeout else { throw Failure("dependency_timeout") }
    let deadline = DispatchTime.now().uptimeNanoseconds + 10_000_000_000
    var pending: [[String]] = [[]]
    var lines: [Data] = []
    var count = 0
    while let parts = pending.popLast() {
      guard DispatchTime.now().uptimeNanoseconds < deadline else { throw Failure("dependency_timeout") }
      let descriptor = try scope.directoryDescriptor(parts)
      defer { close(descriptor) }
      var before = stat()
      guard fstat(descriptor, &before) == 0, before.st_flags & UInt32(SF_DATALESS) == 0 else {
        throw Failure("dependency_unavailable")
      }
      let duplicate = openat(descriptor, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      guard duplicate >= 0, let directory = fdopendir(duplicate) else {
        if duplicate >= 0 { close(duplicate) }; throw Failure("dependency_unavailable")
      }
      defer { closedir(directory) }
      while true {
        guard DispatchTime.now().uptimeNanoseconds < deadline else { throw Failure("dependency_timeout") }
        errno = 0
        guard let item = readdir(directory) else {
          if errno != 0 { throw Failure("dependency_unavailable") }; break
        }
        let capacity = Int(item.pointee.d_namlen) + 1
        let name = withUnsafePointer(to: &item.pointee.d_name) { pointer in
          pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { String(validatingUTF8: $0) }
        }
        guard let name else { throw Failure("dependency_unavailable") }
        if name.hasPrefix(".") {
          if name.hasSuffix(".icloud") {
            let logical = String(name.dropFirst().dropLast(7))
            if !logical.isEmpty && !logical.hasPrefix(".") {
              throw Failure("catalog_unavailable")
            }
          }
          continue
        }
        count += 1
        guard count <= Self.maximumCatalogEntries else { throw Failure("dependency_limit") }
        let child = parts + [name]; let path = child.joined(separator: "/")
        _ = try WorkspaceFileScope.relativeComponents(path)
        var value = stat()
        guard fstatat(descriptor, name, &value, AT_SYMLINK_NOFOLLOW) == 0 else { throw Failure("dependency_unavailable") }
        let kind = value.st_mode & mode_t(S_IFMT)
        guard kind == mode_t(S_IFDIR) || kind == mode_t(S_IFREG) else { throw Failure("dependency_unavailable") }
        if kind == mode_t(S_IFDIR) { pending.append(child) }
        if excluding.contains(path) { continue }
        let revision = kind == mode_t(S_IFDIR) ? Self.identity(value) : WorkspaceFileScope.revision(value)
        let local = value.st_flags & UInt32(SF_DATALESS) == 0
        lines.append(Data("\(path.utf8.count):\(path)|\(kind)|\(revision)|\(local)\n".utf8))
      }
      var after = stat()
      guard fstat(descriptor, &after) == 0,
            WorkspaceFileScope.revision(before) == WorkspaceFileScope.revision(after) else {
        throw Failure("dependency_changed_during_scan")
      }
    }
    try scope.verifyRootLocation()
    lines.sort { $0.lexicographicallyPrecedes($1) }
    var hasher = SHA256()
    for line in lines { hasher.update(data: line) }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private func digest(_ rows: [Metadata], excluding: Set<String>, assets: [Metadata], scope: WorkspaceTextScope) throws -> String {
    for asset in assets {
      let parts = try WorkspaceFileScope.relativeComponents(asset.path)
      let parent = try scope.parentDescriptor(parts); defer { close(parent) }
      var value = stat()
      guard fstatat(parent, parts.last!, &value, AT_SYMLINK_NOFOLLOW) == 0,
            value.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), value.st_flags & UInt32(SF_DATALESS) == 0,
            WorkspaceFileScope.revision(value) == asset.revision else { throw Failure("asset_changed") }
    }
    return try dependencyDigest(scope, excluding: excluding)
  }

  private func matchesMetadata(_ snapshot: Snapshot?, entry: Entry) -> Bool {
    guard let snapshot else { return false }
    return snapshot.permissions == entry.permissions && snapshot.owner == entry.owner && snapshot.group == entry.group &&
      snapshot.protectionClass == entry.protectionClass
  }

  private func revokeUnpersisted(_ record: Record) {
    if sessions[record.transactionId] != nil || hasEvidenceOfMutation(record) || record.completionVerified {
      unpersistedUncertainty.insert(record.transactionId)
    }
    sessions.removeValue(forKey: record.transactionId)
    record.completionVerified = false
  }

  private func observeConsistencyConflict(_ record: Record) {
    record.consistencyConflict = true
    if sessions[record.transactionId] != nil || hasEvidenceOfMutation(record) || record.completionVerified {
      observedConsistencyConflicts.insert(record.transactionId)
    }
    // A lost conflict receipt must never leave a live token that can recreate
    // semantic completion after the offending metadata disappears.
    sessions.removeValue(forKey: record.transactionId)
  }

  private func validateReadSet(_ record: Record, session: Session) throws {
    do {
      try point("beforeSemanticScan")
      guard !record.consistencyConflict else { throw Failure("dependency_conflict") }
      let rows = try catalog(session.scope)
      let excluded = Set(record.entries.flatMap { [$0.path, $0.destinationPath] })
      guard try digest(rows, excluding: excluded, assets: session.assets, scope: session.scope) == record.catalogDigest else {
        observeConsistencyConflict(record)
        throw Failure("catalog_changed")
      }
      for entry in record.entries {
        let moved = entry.moveRevision != nil
        let path = moved ? entry.destinationPath : entry.path
        if moved && entry.path != entry.destinationPath {
          guard try pathAbsent(session.scope, path: entry.path) else { throw Failure("source_reappeared") }
        }
        _ = try verifyParent(session, path: path)
        let snapshot = try read(session.scope, path: path)
        let expected = entry.moveRevision ?? entry.writeRevision ?? entry.expectedRevision
        let bytes = entry.writeRevision != nil ? entry.replacement : entry.original
        guard snapshot.revision == expected, snapshot.identity == Self.identity(expected), snapshot.bytes == bytes,
              snapshot.permissions == entry.permissions, snapshot.owner == entry.owner, snapshot.group == entry.group,
              snapshot.protectionClass == entry.protectionClass else {
          throw Failure("file_conflict")
        }
        if let path = entry.artifactPath, let revision = entry.displacedRevision ?? entry.stagedRevision {
          let artifact = try read(session.scope, path: path, artifact: true)
          let expectedBytes = entry.displacedRevision == nil ? entry.replacement : entry.original
          guard artifact.revision == revision, artifact.identity == Self.identity(revision), artifact.bytes == expectedBytes,
                matchesMetadata(artifact, entry: entry) else {
            throw Failure("artifact_changed")
          }
        }
      }
    } catch {
      observeConsistencyConflict(record)
      throw error
    }
  }
  /// The initial executor preserves ordinary POSIX access metadata, but does
  /// not silently discard ACLs, xattrs/resource forks, compression or flags.
  /// Unknown metadata and inability to inspect it fail closed before staging.
  /// These descriptor APIs are read-only (unlike fcopyfile's destination setup).
  private func protectionClass(_ descriptor: Int32) throws -> Int32? {
    #if os(iOS)
    let value = fcntl(descriptor, F_GETPROTECTIONCLASS)
    guard value >= 0 else { throw Failure("unsupported_metadata") }
    return value
    #else
    return nil
    #endif
  }

  private func preserveMetadata(_ descriptor: Int32, entry: Entry, privateCopy: Bool = false) throws {
    try requirePlainMetadata(descriptor)
    // Change access metadata only on the new exclusive artifact or copy.
    guard fchown(descriptor, entry.owner, entry.group) == 0,
          fchmod(descriptor, privateCopy ? mode_t(0o600) : mode_t(entry.permissions)) == 0 else {
      throw Failure("metadata_preservation_failed")
    }
    #if os(iOS)
    guard let value = entry.protectionClass,
          fcntl(descriptor, F_SETPROTECTIONCLASS, value) == 0,
          try protectionClass(descriptor) == value else { throw Failure("metadata_preservation_failed") }
    #endif
  }

  private func requirePlainMetadata(_ descriptor: Int32) throws {
    var attributes = stat()
    guard fstat(descriptor, &attributes) == 0,
          attributes.st_uid == getuid(), attributes.st_flags == 0,
          attributes.st_mode & mode_t(S_ISUID | S_ISGID | S_ISVTX) == 0 else {
      throw Failure("unsupported_metadata")
    }
    let extended = flistxattr(descriptor, nil, 0, 0)
    guard extended == 0 else { throw Failure("unsupported_metadata") }
    try requireEmptyACL(descriptor)
  }

  private func requireEmptyACL(_ descriptor: Int32, failureCode: String = "unsupported_metadata") throws {
    errno = 0
    if let acl = acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) {
      defer { _ = acl_free(UnsafeMutableRawPointer(acl)) }
      guard acl_valid(acl) == 0 else { throw Failure(failureCode) }
      var entry: acl_entry_t?
      errno = 0
      guard acl_get_entry(acl, Int32(ACL_FIRST_ENTRY.rawValue), &entry) == -1, errno == EINVAL else {
        throw Failure(failureCode)
      }
    } else if errno != ENOENT { throw Failure(failureCode) }
  }

  private func read(_ scope: WorkspaceTextScope, path: String, artifact: Bool = false) throws -> Snapshot {
    let parts = try (artifact ? artifactComponents(path) : components(path))
    let parent = try scope.parentDescriptor(parts); defer { close(parent) }
    var attributes = stat()
    guard fstatat(parent, parts.last!, &attributes, AT_SYMLINK_NOFOLLOW) == 0,
          attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), attributes.st_nlink == 1,
          attributes.st_flags & UInt32(SF_DATALESS) == 0 else { throw Failure("file_unavailable") }
    let descriptor = openat(parent, parts.last!, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    guard descriptor >= 0 else { throw Failure("file_unavailable") }
    defer { close(descriptor) }
    try requirePlainMetadata(descriptor)
    let dataProtection = try protectionClass(descriptor)
    var inspected = stat()
    guard fstat(descriptor, &inspected) == 0,
          WorkspaceFileScope.revision(inspected) == WorkspaceFileScope.revision(attributes) else { throw Failure("file_conflict") }
    let data = try scope.readLocalBytes(components: parts, maximumBytes: Self.maximumPayloadBytes, verifyRevision: true)
    guard data.revision == WorkspaceFileScope.revision(attributes), String(data: data.bytes, encoding: .utf8) != nil else {
      throw Failure("file_conflict")
    }
    return Snapshot(bytes: data.bytes, revision: data.revision, identity: Self.identity(attributes),
                    permissions: UInt32(attributes.st_mode & 0o777), owner: attributes.st_uid, group: attributes.st_gid,
                    protectionClass: dataProtection)
  }
  private func destinationAbsent(_ scope: WorkspaceTextScope, path: String) throws {
    let parts = try components(path)
    let listing = try scope.listDirectory(relativePath: parts.dropLast().joined(separator: "/"))
    guard listing["complete"] as? Bool == true, let rows = listing["entries"] as? [[String: Any]] else {
      throw Failure("catalog_incomplete")
    }
    let folded = path.precomposedStringWithCanonicalMapping.lowercased()
    guard !rows.contains(where: { ($0["relativePath"] as? String)?.precomposedStringWithCanonicalMapping.lowercased() == folded }) else {
      throw Failure("destination_exists")
    }
    let parent = try scope.parentDescriptor(parts); defer { close(parent) }
    var value = stat()
    guard fstatat(parent, parts.last!, &value, AT_SYMLINK_NOFOLLOW) == -1, errno == ENOENT else {
      throw Failure("destination_exists")
    }
  }

  private func prepare(root: URL, id: String, arguments: [String: Any]) throws -> [String: Any] {
    if try exists(id) {
      let record = try load(id)
      guard arguments["sourcePath"] as? String == record.sourcePath,
            arguments["destinationPath"] as? String == record.destinationPath,
            let files = arguments["files"] as? [[String: Any]], files.count == record.entries.count,
            zip(files, record.entries).allSatisfy({ pair in
              let (file, entry) = pair
              return file["path"] as? String == entry.path && file["destinationPath"] as? String == entry.destinationPath &&
              file["expectedRevision"] as? String == entry.expectedRevision &&
              (file["expectedBytes"] as? FlutterStandardTypedData)?.data == entry.original &&
              (file["replacementBytes"] as? FlutterStandardTypedData)?.data == entry.replacement
            }) else { throw Failure("transaction_id_reused") }
      try reconcile(record, scope: try authorizedScope(root, record: record))
      return result(record)
    }
    guard let source = arguments["sourcePath"] as? String,
          let destination = arguments["destinationPath"] as? String,
          source.precomposedStringWithCanonicalMapping.lowercased() != destination.precomposedStringWithCanonicalMapping.lowercased(),
          let files = arguments["files"] as? [[String: Any]], !files.isEmpty, files.count <= Self.maximumFiles else {
      throw Failure("invalid_plan")
    }
    _ = try components(source); _ = try components(destination)
    let expectedCatalog = try metadata(arguments["catalog"])
    let assets = try metadata(arguments["assets"] ?? [[String: Any]](), assets: true)
    let scope = try WorkspaceTextScope(root)
    let journalPath = journalURL.resolvingSymlinksInPath().standardizedFileURL.path
    let rootPath = scope.rootURL.standardizedFileURL.path
    guard journalPath != rootPath, !journalPath.hasPrefix(rootPath + "/"),
          !rootPath.hasPrefix(journalPath + "/") else { throw Failure("journal_scope_overlap") }
    let identity = try scopeIdentity(scope)
    let actualCatalog = try catalog(scope)
    // Exact preview revisions at prepare, including directory revisions. Later
    // comparisons omit only the directory timestamps changed by our own work.
    let expectedRows = expectedCatalog.map { "\($0.path)|\($0.revision)|\($0.isDirectory)|\($0.local)" }.sorted()
    let actualRows = actualCatalog.map { "\($0.path)|\($0.revision)|\($0.isDirectory)|\($0.local)" }.sorted()
    guard expectedRows == actualRows else { throw Failure("catalog_changed") }
    try destinationAbsent(scope, path: destination)
    var parents: [String: Parent] = [:]; var directories: [String: Parent] = [:]
    var entries: [Entry] = []; var paths = Set<String>(); var byteCount = 0
    for file in files {
      guard let path = file["path"] as? String, let to = file["destinationPath"] as? String,
            let revision = file["expectedRevision"] as? String,
            let original = file["expectedBytes"] as? FlutterStandardTypedData, original.elementSize == 1,
            let replacement = file["replacementBytes"] as? FlutterStandardTypedData, replacement.elementSize == 1,
            paths.insert(path).inserted, to == (path == source ? destination : path),
            path == source || original.data != replacement.data,
            String(data: original.data, encoding: .utf8) != nil, String(data: replacement.data, encoding: .utf8) != nil else {
        throw Failure("invalid_plan")
      }
      byteCount += original.data.count + replacement.data.count
      guard byteCount <= Self.maximumPayloadBytes else { throw Failure("payload_limit") }
      for name in [path, to] where parents[name] == nil {
        let parts = try components(name); let directory = parts.dropLast().joined(separator: "/")
        let parent = try directories[directory] ?? Parent(scope: scope, components: parts)
        directories[directory] = parent; parents[name] = parent
      }
      let snapshot = try read(scope, path: path)
      guard snapshot.revision == revision, snapshot.bytes == original.data,
            actualCatalog.contains(where: { $0.path == path && !$0.isDirectory && $0.revision == revision }) else {
        throw Failure("file_conflict")
      }
      entries.append(Entry(path: path, destinationPath: to, expectedRevision: revision, expectedIdentity: snapshot.identity,
        parentIdentity: parents[path]!.identity, destinationParentIdentity: parents[to]!.identity,
        original: original.data, replacement: replacement.data,
        originalHash: Self.hash(original.data), replacementHash: Self.hash(replacement.data),
        permissions: snapshot.permissions, owner: snapshot.owner, group: snapshot.group,
        protectionClass: snapshot.protectionClass, artifactPath: original.data == replacement.data ? nil :
          (Array(try components(path).dropLast()) + [".linefold-note-move-\(id)-\(entries.count).md"]).joined(separator: "/"),
        actualPath: path, actualRevision: revision))
    }
    guard paths.contains(source), !paths.contains(destination) else { throw Failure("invalid_plan") }
    for entry in entries {
      if let path = entry.artifactPath, try !pathAbsent(scope, path: path, artifact: true) { throw Failure("artifact_exists") }
    }
    let excluded = Set(entries.flatMap { [$0.path, $0.destinationPath] })
    let fingerprint = try digest(actualCatalog, excluding: excluded, assets: assets, scope: scope)
    let recheckedRows = try catalog(scope).map { "\($0.path)|\($0.revision)|\($0.isDirectory)|\($0.local)" }.sorted()
    guard expectedRows == recheckedRows else { throw Failure("catalog_changed") }
    let record = Record(id: id, scope: scope, rootIdentity: identity, source: source, destination: destination,
                        digest: fingerprint, entries: entries)
    let session = Session(scope: scope, parents: parents, assets: assets)
    try validateReadSet(record, session: session)
    try checkPlanCapacity(record, scope: scope, context: "prepare")
    try point("beforePreparedJournal")
    try save(record)
    sessions[id] = session
    try point("afterPreparedJournal")
    return result(record)
  }

  private func execute(root: URL, id: String, token: String?) throws -> [String: Any] {
    let record = try load(id)
    guard !record.cancelled else { return result(record) }
    guard let session = sessions[id], token == session.token else {
      try reconcile(record, scope: try authorizedScope(root, record: record))
      record.code = "new_preview_required"; return result(record)
    }
    do {
      _ = try authorizedScope(root, record: record)
      try reconcile(record, scope: session.scope)
      if record.phase == "completed" { sessions.removeValue(forKey: id); return result(record) }
      guard record.entries.allSatisfy({ $0.state == "pending" || $0.state == "applied" }),
            record.entries.allSatisfy({ $0.intent == nil }) else { throw Failure("reconciliation_required") }
      try validateReadSet(record, session: session)
      try destinationAbsent(session.scope, path: record.destinationPath)
      try checkPlanCapacity(record, scope: session.scope, context: "execute")
      for index in record.entries.indices where record.entries[index].writeRevision == nil {
        if record.entries[index].original == record.entries[index].replacement { continue }
        try validateReadSet(record, session: session)
        try writeEntry(record, index: index, session: session)
      }
      try validateReadSet(record, session: session)
      try moveEntry(record, session: session)
      try validateReadSet(record, session: session)
      record.completionVerified = true
      record.phase = "completed"; record.code = nil
      try save(record)
      sessions.removeValue(forKey: id)
    } catch {
      revokeUnpersisted(record)
      // Retain exact in-memory evidence if a receipt flush failed; re-read the
      // last durable intent and observe disk before responding. No automatic retry.
      let failure = code(error)
      if let durable = try? load(id) {
        durable.consistencyConflict = durable.consistencyConflict || record.consistencyConflict
        do { try reconcile(durable, scope: session.scope) } catch { markUnverifiable(durable) }
        durable.code = failure
        if durable.phase != "completed" { durable.phase = hasEvidenceOfMutation(durable) ? "partial" : "blocked" }
        try? save(durable)
        if durable.phase == "completed" { sessions.removeValue(forKey: id) }
        return result(durable)
      }
      markUnverifiable(record); record.code = failure; record.phase = "uncertain"
    }
    return result(record)
  }

  /// Accept only another spelling of this exact authorized root, followed by
  /// byte-identical planned components. Never resolve the leaf or descendants.
  /// Internal for synthetic tests; no Flutter arguments can call this helper.
  func verifyCoordinatedURL(_ observed: URL, scope: WorkspaceFileScope,
                            relativePath: String, parentDescriptor: Int32) throws {
    do {
      try WorkspaceFileScope.withoutMaterialization {
        guard observed.isFileURL, observed.host == nil || observed.host == "",
              observed.user == nil, observed.password == nil, observed.port == nil,
              observed.query == nil, observed.fragment == nil, !observed.hasDirectoryPath,
              observed.path.hasPrefix("/"), observed.path.utf16.count <= 4096 else {
          throw Failure("coordinator_redirected")
        }
        guard let encodedPath = URLComponents(url: observed, resolvingAgainstBaseURL: false)?.percentEncodedPath,
              encodedPath.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({
                guard let component = String($0).removingPercentEncoding else { return false }
                return component != "." && component != ".."
              }) else { throw Failure("coordinator_redirected") }
        let planned = try WorkspaceFileScope.relativeComponents(relativePath)
        let received = observed.pathComponents
        guard received.count > planned.count,
              !received.contains("."), !received.contains(".."),
              zip(received.suffix(planned.count), planned).allSatisfy({
                $0.0.utf8.elementsEqual($0.1.utf8)
              }) else { throw Failure("coordinator_redirected") }
        var rootSpelling = observed
        for _ in planned { rootSpelling.deleteLastPathComponent() }
        // Only ancestors of the root may contain aliases, as at initial scope
        // authorization. The root itself and every descendant are no-follow.
        let candidate = try WorkspaceFileScope(rootSpelling)
        let originalRootIdentity = try scopeIdentity(scope) // Uses the pinned root descriptor.
        let candidateRootIdentity = try scopeIdentity(candidate)
        guard candidate.rootURL.path.utf8.elementsEqual(scope.rootURL.path.utf8),
              candidateRootIdentity == originalRootIdentity else {
          throw Failure("coordinator_redirected")
        }
        let candidateParent = try candidate.parentDescriptor(planned)
        defer { close(candidateParent) }
        var original = stat(); var current = stat()
        guard fstat(parentDescriptor, &original) == 0, fstat(candidateParent, &current) == 0,
              original.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              current.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              Self.identity(original) == Self.identity(current),
              original.st_flags & UInt32(SF_DATALESS) == 0,
              current.st_flags & UInt32(SF_DATALESS) == 0 else {
          throw Failure("coordinator_redirected")
        }
        // A missing leaf is valid for the exclusive move/copy destination and
        // for the old source after a move. A symlink is never a missing leaf.
        var leaf = stat()
        if fstatat(candidateParent, planned.last!, &leaf, AT_SYMLINK_NOFOLLOW) == 0 {
          guard leaf.st_mode & mode_t(S_IFMT) != mode_t(S_IFLNK),
                leaf.st_flags & UInt32(SF_DATALESS) == 0 else { throw Failure("coordinator_redirected") }
        } else if errno != ENOENT { throw Failure("coordinator_redirected") }
        try scope.verifyRootLocation(); try candidate.verifyRootLocation()
      }
    } catch { throw Failure("coordinator_redirected") }
  }

  private func coordinate(_ scope: WorkspaceFileScope, path: String, destination: String? = nil, moving: Bool = true,
                          coordinator: NSFileCoordinator = NSFileCoordinator(), body: () throws -> Void) throws {
    let url = scope.rootURL.appendingPathComponent(path)
    let sourceParent = try WorkspaceFileScope.withoutMaterialization {
      try Parent(scope: scope, components: WorkspaceFileScope.relativeComponents(path))
    }
    var coordinationError: NSError?; var outcome: Result<Void, Error> = .failure(Failure("coordination_failed"))
    let deadline = DispatchTime.now() + WorkspaceTextScope.coordinationTimeout
    let timeout = DispatchWorkItem { coordinator.cancel() }
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: deadline, execute: timeout)
    defer { timeout.cancel() }
    // All callback validation I/O shares the no-materialization policy, even
    // when Foundation dispatches the callback to another worker thread.
    if let destination {
      let target = scope.rootURL.appendingPathComponent(destination)
      let targetParent = try WorkspaceFileScope.withoutMaterialization {
        try Parent(scope: scope, components: WorkspaceFileScope.relativeComponents(destination))
      }
      coordinator.coordinate(writingItemAt: url, options: moving ? .forMoving : [],
        writingItemAt: target, options: [], error: &coordinationError) { a, b in
        outcome = Result {
          try WorkspaceFileScope.withoutMaterialization {
            coordinationObserver?(CoordinationObservation(expectedSource: url, observedSource: a,
              expectedDestination: target, observedDestination: b, moving: moving,
              deadlineExpired: DispatchTime.now().uptimeNanoseconds >= deadline.uptimeNanoseconds))
            guard DispatchTime.now().uptimeNanoseconds < deadline.uptimeNanoseconds else { throw Failure("coordinator_redirected") }
            try verifyCoordinatedURL(a, scope: scope, relativePath: path, parentDescriptor: sourceParent.descriptor)
            try verifyCoordinatedURL(b, scope: scope, relativePath: destination, parentDescriptor: targetParent.descriptor)
            guard DispatchTime.now().uptimeNanoseconds < deadline.uptimeNanoseconds else { throw Failure("coordinator_redirected") }
            try body() // The body still uses only its original pinned authority.
            try verifyCoordinatedURL(a, scope: scope, relativePath: path, parentDescriptor: sourceParent.descriptor)
            try verifyCoordinatedURL(b, scope: scope, relativePath: destination, parentDescriptor: targetParent.descriptor)
          }
        }
      }
    } else {
      coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) { current in
        outcome = Result {
          try WorkspaceFileScope.withoutMaterialization {
            coordinationObserver?(CoordinationObservation(expectedSource: url, observedSource: current,
              expectedDestination: nil, observedDestination: nil, moving: false,
              deadlineExpired: DispatchTime.now().uptimeNanoseconds >= deadline.uptimeNanoseconds))
            guard DispatchTime.now().uptimeNanoseconds < deadline.uptimeNanoseconds else { throw Failure("coordinator_redirected") }
            try verifyCoordinatedURL(current, scope: scope, relativePath: path, parentDescriptor: sourceParent.descriptor)
            guard DispatchTime.now().uptimeNanoseconds < deadline.uptimeNanoseconds else { throw Failure("coordinator_redirected") }
            try body()
            try verifyCoordinatedURL(current, scope: scope, relativePath: path, parentDescriptor: sourceParent.descriptor)
          }
        }
      }
    }
    if let coordinationError { throw coordinationError }
    try outcome.get()
  }

  // A successful fsync is the process-interruption contract here. This is not
  // F_FULLFSYNC, and is not a promise about power loss, OS crash or device caches.
  private func syncDescriptor(_ descriptor: Int32, operation: String) throws {
    try point("before\(operation)")
    guard fsync(descriptor) == 0 else { throw Failure("sync_failed") }
    try point("after\(operation)")
  }

  private func sameSnapshot(_ a: Snapshot, _ b: Snapshot) -> Bool {
    a.revision == b.revision && a.identity == b.identity && a.bytes == b.bytes &&
      a.permissions == b.permissions && a.owner == b.owner && a.group == b.group &&
      a.protectionClass == b.protectionClass
  }

  /// Called inside coordination. Flush the actual observed objects and all
  /// affected directory entries, then recheck scope, names, identity and bytes.
  /// A page-cache observation alone must never repair a missing durable receipt.
  private func syncObserved(_ scope: WorkspaceTextScope,
      files: [(path: String, snapshot: Snapshot, artifact: Bool, parent: Parent)],
      parents: [(path: String, parent: Parent)], absent: String? = nil, operation: String) throws {
    for item in parents { try verifyParent(scope: scope, path: item.path, parent: item.parent) }
    if let absent { guard try pathAbsent(scope, path: absent) else { throw Failure("sync_uncertain") } }
    for item in files {
      let parts = try (item.artifact ? artifactComponents(item.path) : components(item.path))
      guard sameSnapshot(try read(scope, path: item.path, artifact: item.artifact), item.snapshot) else { throw Failure("sync_uncertain") }
      let fd = openat(item.parent.descriptor, parts.last!, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
      guard fd >= 0 else { throw Failure("sync_uncertain") }
      defer { close(fd) }
      var info = stat()
      guard fstat(fd, &info) == 0, info.st_nlink == 1,
            WorkspaceFileScope.revision(info) == item.snapshot.revision else { throw Failure("sync_uncertain") }
      try syncDescriptor(fd, operation: operation + "FileSync")
      guard fstat(fd, &info) == 0, WorkspaceFileScope.revision(info) == item.snapshot.revision else { throw Failure("sync_uncertain") }
      try scope.verifyRootLocation()
    }
    for item in parents {
      try verifyParent(scope: scope, path: item.path, parent: item.parent)
      try syncDescriptor(item.parent.descriptor, operation: operation + "ParentSync")
      try verifyParent(scope: scope, path: item.path, parent: item.parent)
    }
    for item in files {
      guard sameSnapshot(try read(scope, path: item.path, artifact: item.artifact), item.snapshot) else { throw Failure("sync_uncertain") }
    }
    if let absent { guard try pathAbsent(scope, path: absent) else { throw Failure("sync_uncertain") } }
    for item in parents { try verifyParent(scope: scope, path: item.path, parent: item.parent) }
    try scope.verifyRootLocation()
  }

  /// Replacement bytes are fully staged and synced before RENAME_SWAP. The
  /// displaced version always survives at the exclusive artifact path, even
  /// when a non-cooperating writer wins the check-to-swap gap. Never swap back.
  private func writeEntry(_ record: Record, index: Int, session: Session) throws {
    let initial = record.entries[index]
    guard let artifact = initial.artifactPath else { return }
    let parts = try artifactComponents(artifact)
    let parent = try verifyParent(session, path: initial.path)
    if initial.stagedRevision == nil {
      try validateReadSet(record, session: session)
      try checkPlanCapacity(record, scope: session.scope, context: "stage")
      try point("beforeStageIntent")
      record.phase = "applying"; record.entries[index].intent = "stage"
      record.entries[index].artifactState = "uncertain"
      try save(record) // includes global journal + artifact reservation, before create
      try point("afterStageIntent")
      _ = try verifyParent(session, path: initial.path)
      try point("beforeStageCreate")
      _ = try verifyParent(session, path: initial.path)
      try checkPlanCapacity(record, scope: session.scope, context: "stageCreate")
      try validateReadSet(record, session: session)
      _ = try verifyParent(session, path: initial.path)
      let descriptor = openat(parent.descriptor, parts.last!, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
      guard descriptor >= 0 else { throw Failure("stage_create_failed") }
      defer { close(descriptor) }
      var created = stat()
      guard fstat(descriptor, &created) == 0, created.st_nlink == 1 else { throw Failure("stage_uncertain") }
      record.entries[index].stagedIdentity = Self.identity(created)
      try save(record)
      try point("afterStageCreate")
      _ = try verifyParent(session, path: initial.path)
      try preserveMetadata(descriptor, entry: initial)
      try writeAll(descriptor, data: initial.replacement, operation: "stage")
      try point("beforeStageSync")
      guard fsync(descriptor) == 0, fsync(parent.descriptor) == 0 else { throw Failure("stage_sync_failed") }
      try point("afterStageWrite")
      _ = try verifyParent(session, path: initial.path)
      let staged = try read(session.scope, path: artifact, artifact: true)
      guard staged.identity == Self.identity(created), staged.bytes == initial.replacement,
            staged.permissions == initial.permissions, staged.owner == initial.owner, staged.group == initial.group,
            staged.protectionClass == initial.protectionClass else { throw Failure("stage_uncertain") }
      record.entries[index].stagedRevision = staged.revision
      record.entries[index].artifactState = "staged"; record.entries[index].intent = nil
      try point("beforeStageReceipt"); try save(record); try point("afterStageReceipt")
    }
    try coordinate(session.scope, path: initial.path, destination: artifact, moving: false) {
      try validateReadSet(record, session: session)
      _ = try verifyParent(session, path: initial.path)
      let staged = try read(session.scope, path: artifact, artifact: true)
      let entry = record.entries[index]
      guard staged.identity == entry.stagedIdentity, staged.revision == entry.stagedRevision,
            staged.bytes == entry.replacement else { throw Failure("stage_changed") }
      try point("beforeWriteIntent")
      record.phase = "applying"; record.entries[index].intent = "swap"; record.entries[index].state = "uncertain"
      try save(record)
      try point("afterWriteIntent")
      try validateReadSet(record, session: session)
      try point("beforeWrite")
      try validateReadSet(record, session: session)
      _ = try verifyParent(session, path: initial.path)
      let verifiedStage = try read(session.scope, path: artifact, artifact: true)
      guard verifiedStage.identity == staged.identity, verifiedStage.revision == staged.revision,
            verifiedStage.bytes == entry.replacement else { throw Failure("stage_changed") }
      let name = try components(initial.path).last!
      try checkPlanCapacity(record, scope: session.scope, context: "swap")
      try validateReadSet(record, session: session)
      _ = try verifyParent(session, path: initial.path)
      try point("swapRace")
      // Unsupported filesystems/providers fail closed. No in-place or ordinary
      // replacement fallback. No unlink, including on a detected post-swap race.
      guard renameatx_np(parent.descriptor, parts.last!, parent.descriptor, name, UInt32(RENAME_SWAP)) == 0 else {
        throw Failure("atomic_swap_failed")
      }
      try point("beforeWriteSync")
      try point("afterWrite")
      _ = try verifyParent(session, path: initial.path)
      let observed = try read(session.scope, path: initial.path)
      let displaced = try read(session.scope, path: artifact, artifact: true)
      guard observed.identity == staged.identity, observed.bytes == entry.replacement,
            observed.permissions == entry.permissions, observed.owner == entry.owner, observed.group == entry.group,
            observed.protectionClass == entry.protectionClass,
            displaced.identity == entry.expectedIdentity, displaced.bytes == entry.original,
            matchesMetadata(displaced, entry: entry) else { throw Failure("swap_uncertain") }
      try syncObserved(session.scope,
        files: [(initial.path, observed, false, parent), (artifact, displaced, true, parent)],
        parents: [(initial.path, parent)], operation: "Write")
      try point("beforeWriteReceipt")
      record.entries[index].writeRevision = observed.revision
      record.entries[index].displacedRevision = displaced.revision
      record.entries[index].artifactState = "retained"
      record.entries[index].actualPath = initial.path; record.entries[index].actualRevision = observed.revision
      record.entries[index].intent = nil; record.entries[index].state = "applied"
      try save(record)
      try point("afterWriteReceipt")
    }
  }

  private func moveEntry(_ record: Record, session: Session) throws {
    guard let index = record.entries.firstIndex(where: { $0.path == record.sourcePath }) else { throw Failure("invalid_manifest") }
    if record.entries[index].moveRevision != nil { return }
    let coordinator = NSFileCoordinator()
    try coordinate(session.scope, path: record.sourcePath, destination: record.destinationPath, coordinator: coordinator) {
      try validateReadSet(record, session: session)
      try destinationAbsent(session.scope, path: record.destinationPath)
      let sourceParent = try verifyParent(session, path: record.sourcePath)
      let targetParent = try verifyParent(session, path: record.destinationPath)
      let source = try components(record.sourcePath).last!
      let destination = try components(record.destinationPath).last!
      try point("beforeMoveIntent")
      record.phase = "moving"; record.entries[index].intent = "move"; record.entries[index].state = "uncertain"
      try save(record)
      try point("afterMoveIntent")
      try validateReadSet(record, session: session)
      try destinationAbsent(session.scope, path: record.destinationPath)
      _ = try verifyParent(session, path: record.sourcePath); _ = try verifyParent(session, path: record.destinationPath)
      try point("beforeMove")
      try validateReadSet(record, session: session)
      _ = try verifyParent(session, path: record.sourcePath); _ = try verifyParent(session, path: record.destinationPath)
      try checkPlanCapacity(record, scope: session.scope, context: "move")
      try validateReadSet(record, session: session)
      try destinationAbsent(session.scope, path: record.destinationPath)
      _ = try verifyParent(session, path: record.sourcePath); _ = try verifyParent(session, path: record.destinationPath)
      // Advisory coordinator + last identity/byte check, NOT a kernel identity
      // CAS. A hostile writer can race this gap; postchecks report uncertainty.
      // RENAME_EXCL never overwrites an existing destination. No cleanup unlink.
      let sourceURL = session.scope.rootURL.appendingPathComponent(record.sourcePath)
      let destinationURL = session.scope.rootURL.appendingPathComponent(record.destinationPath)
      coordinator.item(at: sourceURL, willMoveTo: destinationURL)
      try point("beforeExclusiveRename")
      guard renameatx_np(sourceParent.descriptor, source, targetParent.descriptor, destination, UInt32(RENAME_EXCL)) == 0 else {
        throw Failure("exclusive_move_failed")
      }
      // The namespace has moved even if a subsequent sync/receipt fails.
      coordinator.item(at: sourceURL, didMoveTo: destinationURL)
      try point("beforeMoveSync")
      try point("afterMove")
      try verifyParent(scope: session.scope, path: record.sourcePath, parent: sourceParent)
      try verifyParent(scope: session.scope, path: record.destinationPath, parent: targetParent)
      let observed = try read(session.scope, path: record.destinationPath)
      let entry = record.entries[index]
      guard observed.identity == Self.identity(entry.writeRevision ?? entry.expectedRevision),
            observed.bytes == (entry.writeRevision == nil ? entry.original : entry.replacement),
            matchesMetadata(observed, entry: entry) else { throw Failure("move_uncertain") }
      var value = stat()
      guard fstatat(sourceParent.descriptor, source, &value, AT_SYMLINK_NOFOLLOW) == -1, errno == ENOENT else {
        throw Failure("move_uncertain")
      }
      try syncObserved(session.scope, files: [(record.destinationPath, observed, false, targetParent)],
        parents: [(record.sourcePath, sourceParent), (record.destinationPath, targetParent)],
        absent: record.sourcePath, operation: "Move")
      try point("beforeMoveReceipt")
      record.entries[index].moveRevision = observed.revision
      record.entries[index].actualPath = record.destinationPath; record.entries[index].actualRevision = observed.revision
      record.entries[index].intent = nil; record.entries[index].state = "applied"
      try save(record)
      try point("afterMoveReceipt")
    }
  }

  private func writeAll(_ descriptor: Int32, data: Data, operation: String) throws {
    try data.withUnsafeBytes { buffer in
      var offset = 0
      while offset < buffer.count {
        try point("\(operation)Chunk")
        let length = min(64 * 1024, buffer.count - offset)
        let count = pwrite(descriptor, buffer.baseAddress!.advanced(by: offset), length, off_t(offset))
        if count < 0 && errno == EINTR { continue }
        guard count > 0 else { throw Failure("write_failed") }
        offset += count
      }
    }
  }

  private func hasEvidenceOfMutation(_ record: Record) -> Bool {
    record.entries.contains { $0.intent != nil || $0.stagedIdentity != nil || $0.writeRevision != nil || $0.moveRevision != nil || $0.state == "uncertain" }
  }
  private func markUnverifiable(_ record: Record) {
    revokeUnpersisted(record)
    for index in record.entries.indices { record.entries[index].state = "uncertain"; record.entries[index].actualPath = nil; record.entries[index].actualRevision = nil; record.entries[index].artifactState = "uncertain" }
    for index in record.recoveries.indices where record.recoveries[index].state == "applied" {
      record.recoveries[index].state = "uncertain"
    }
    record.phase = "uncertain"
  }
  private func reconcile(_ record: Record, scope: WorkspaceTextScope) throws {
    guard try scopeIdentity(scope) == record.rootIdentity else { markUnverifiable(record); throw Failure("scope_changed") }
    if record.cancelled {
      record.phase = "cancelled"; reconcileRecoveries(record, scope: scope); try save(record); return
    }
    for index in record.entries.indices {
      var entry = record.entries[index]
      entry.actualPath = nil; entry.actualRevision = nil
      guard let sourceParent = try? Parent(scope: scope, components: components(entry.path)),
            let destinationParent = try? Parent(scope: scope, components: components(entry.destinationPath)) else {
        entry.state = "uncertain"; entry.artifactState = "uncertain"; record.entries[index] = entry; continue
      }
      guard sourceParent.identity == entry.parentIdentity,
            destinationParent.identity == entry.destinationParentIdentity else {
        entry.state = "uncertain"; entry.artifactState = "uncertain"; record.entries[index] = entry; continue
      }
      let source = try? read(scope, path: entry.path)
      let destination = entry.destinationPath == entry.path ? source : try? read(scope, path: entry.destinationPath)
      var artifact: Snapshot?
      var artifactMissing = false
      if let path = entry.artifactPath {
        artifact = try? read(scope, path: path, artifact: true)
        artifactMissing = (try? pathAbsent(scope, path: path, artifact: true)) == true
      }
      let originalExact = source?.identity == entry.expectedIdentity && source?.revision == entry.expectedRevision && source?.bytes == entry.original && matchesMetadata(source, entry: entry)
      let stageExact = artifact?.identity == entry.stagedIdentity && artifact?.revision == entry.stagedRevision && artifact?.bytes == entry.replacement && matchesMetadata(artifact, entry: entry)
      if entry.intent == "stage" {
        // An absent exclusive artifact plus the unchanged source proves create
        // never ran. An unreceipted existing artifact is not safe to overwrite.
        if originalExact && artifactMissing && entry.stagedIdentity == nil {
          entry.intent = nil; entry.artifactState = "pending"
        } else { entry.state = "uncertain"; entry.artifactState = "uncertain" }
      }
      if entry.intent == "swap" {
        if originalExact && stageExact {
          entry.intent = nil; entry.artifactState = "staged"
        } else if let current = source, let retained = artifact,
                  current.identity == entry.stagedIdentity, current.bytes == entry.replacement,
                  retained.identity == entry.expectedIdentity, retained.bytes == entry.original,
                  matchesMetadata(current, entry: entry), matchesMetadata(retained, entry: entry) {
          do {
            try coordinate(scope, path: entry.path, destination: entry.artifactPath!, moving: false) {
              try syncObserved(scope,
                files: [(entry.path, current, false, sourceParent), (entry.artifactPath!, retained, true, sourceParent)],
                parents: [(entry.path, sourceParent)], operation: "RepairWrite")
            }
            entry.writeRevision = current.revision; entry.displacedRevision = retained.revision
            entry.intent = nil; entry.artifactState = "retained"
          } catch { entry.state = "uncertain"; entry.artifactState = "uncertain"; record.code = code(error) }
        } else { entry.state = "uncertain"; entry.artifactState = "uncertain" }
      }
      if entry.intent == "move" {
        let expected = entry.writeRevision ?? entry.expectedRevision
        let bytes = entry.writeRevision == nil ? entry.original : entry.replacement
        if let current = source, current.identity == Self.identity(expected), current.revision == expected,
           current.bytes == bytes, (try? pathAbsent(scope, path: entry.destinationPath)) == true {
          entry.intent = nil
        } else if let moved = destination, moved.identity == Self.identity(expected), moved.bytes == bytes,
                  (try? pathAbsent(scope, path: entry.path)) == true {
          // Never replay rename. Missing sync/receipt is repaired by flushing
          // these exact objects, not by merely observing the destination.
          do {
            guard matchesMetadata(moved, entry: entry) else { throw Failure("sync_uncertain") }
            try coordinate(scope, path: entry.path, destination: entry.destinationPath, moving: false) {
              try syncObserved(scope, files: [(entry.destinationPath, moved, false, destinationParent)],
                parents: [(entry.path, sourceParent), (entry.destinationPath, destinationParent)],
                absent: entry.path, operation: "RepairMove")
            }
            entry.moveRevision = moved.revision; entry.intent = nil
          } catch { entry.state = "uncertain"; record.code = code(error) }
        } else { entry.state = "uncertain" }
      }
      let expectedPath = entry.moveRevision == nil ? entry.path : entry.destinationPath
      let current = entry.moveRevision == nil ? source : destination
      let expectedRevision = entry.moveRevision ?? entry.writeRevision ?? entry.expectedRevision
      let expectedBytes = entry.writeRevision == nil ? entry.original : entry.replacement
      if let current {
        entry.actualPath = expectedPath; entry.actualRevision = current.revision
        if entry.intent == nil, current.identity == Self.identity(expectedRevision),
           current.revision == expectedRevision, current.bytes == expectedBytes,
           current.permissions == entry.permissions, current.owner == entry.owner, current.group == entry.group,
           current.protectionClass == entry.protectionClass,
           (entry.moveRevision == nil || (try? pathAbsent(scope, path: entry.path)) == true) {
          entry.state = entry.writeRevision != nil || entry.moveRevision != nil ? "applied" : "pending"
        } else { entry.state = entry.intent == nil ? "conflict" : "uncertain" }
      } else if let moved = destination, entry.destinationPath != entry.path {
        entry.actualPath = entry.destinationPath; entry.actualRevision = moved.revision; entry.state = "uncertain"
      } else { entry.state = "uncertain" }
      if entry.artifactPath != nil {
        if entry.displacedRevision != nil {
          // Recompute because a lost receipt may just have been reconciled.
          if artifact?.identity == entry.expectedIdentity && artifact?.revision == entry.displacedRevision && artifact?.bytes == entry.original && matchesMetadata(artifact, entry: entry) {
            entry.artifactState = "retained"
          } else { entry.artifactState = "uncertain"; entry.state = "uncertain" }
        } else if entry.stagedRevision != nil {
          if stageExact { entry.artifactState = "staged" }
          else { entry.artifactState = "uncertain"; entry.state = "uncertain" }
        } else if !artifactMissing {
          entry.artifactState = "uncertain"; entry.state = "uncertain"
        }
      }
      record.entries[index] = entry
    }
    try scope.verifyRootLocation()
    reconcileRecoveries(record, scope: scope)
    // Exclude only this manifest's complete, currently identity/revision/byte-
    // verified copies. A same-prefix stranger or changed/partial copy is never
    // exempted from the read-set by filename alone.
    let ownCopies = record.recoveries.filter { $0.state == "applied" }.map(\.path)
    let excluded = Set(record.entries.flatMap { [$0.path, $0.destinationPath] } + ownCopies)
    do {
      try point("beforeSemanticScan")
      // Use the same logical-note enumeration as prepare, including hidden
      // .Name.md.icloud placeholders. A weaker visible-only digest is not proof.
      _ = try catalog(scope)
      if try dependencyDigest(scope, excluding: excluded) != record.catalogDigest { observeConsistencyConflict(record) }
    } catch { observeConsistencyConflict(record) }
    if record.consistencyConflict {
      observeConsistencyConflict(record)
      record.phase = hasEvidenceOfMutation(record) ? "partial" : "blocked"
      record.code = "dependency_conflict"
    } else if record.entries.contains(where: { $0.state == "uncertain" || $0.state == "conflict" }) {
      revokeUnpersisted(record)
      record.phase = hasEvidenceOfMutation(record) ? "partial" : "blocked"
    } else if let source = record.entries.first(where: { $0.path == record.sourcePath }), source.moveRevision != nil {
      if record.completionVerified {
        // Only execute can persist semantic completion after its final full
        // validation. Repairing bytes, identities and sync is not that proof.
        record.phase = "completed"
        if record.code == "completion_unverified" { record.code = nil }
      } else {
        record.phase = "partial"; record.code = "completion_unverified"
      }
    } else { record.phase = hasEvidenceOfMutation(record) ? "partial" : "prepared" }
    try save(record)
  }
  private func pathAbsent(_ scope: WorkspaceFileScope, path: String, artifact: Bool = false) throws -> Bool {
    let parts = try (artifact ? artifactComponents(path) : components(path)); let parent = try scope.parentDescriptor(parts); defer { close(parent) }
    var value = stat()
    if fstatat(parent, parts.last!, &value, AT_SYMLINK_NOFOLLOW) == 0 { return false }
    guard errno == ENOENT else { throw Failure("file_unavailable") }
    return true
  }

  private func reconcileRecoveries(_ record: Record, scope: WorkspaceTextScope) {
    for index in record.recoveries.indices {
      let item = record.recoveries[index]
      do {
        let parent = try Parent(scope: scope, components: components(item.path))
        guard parent.identity == item.parentIdentity,
              let entry = record.entries.first(where: { $0.path == item.sourcePath }) else { throw Failure("recovery_uncertain") }
        if item.state == "pending" {
          guard try pathAbsent(scope, path: item.path) else { throw Failure("recovery_destination_exists") }
        } else {
          let observed = try read(scope, path: item.path)
          guard item.state == "applied", observed.identity == item.identity,
                observed.revision == item.revision, observed.bytes == entry.original else { throw Failure("recovery_uncertain") }
        }
      } catch { record.recoveries[index].state = "uncertain" }
    }
  }

  private func recover(root: URL, id: String, directory: String) throws -> [String: Any] {
    let record = try load(id)
    let scope = try authorizedScope(root, record: record)
    do { try reconcile(record, scope: scope) }
    catch { markUnverifiable(record); record.code = code(error) }
    let destinationComponents = try WorkspaceTextScope.textComponents(directory, directory: true)
    sessions.removeValue(forKey: id) // Recovery never silently resumes a write grant.
    do {
      if record.recoveries.isEmpty {
        // Persist the entire bounded copy plan first. Only entries known never
        // to have started can resume on a later explicit recovery request.
        for entry in record.entries {
          let name = "Recovered-\(id.prefix(8))-\(UUID().uuidString).md"
          let path = (destinationComponents + [name]).joined(separator: "/")
          let parent = try Parent(scope: scope, components: components(path))
          try destinationAbsent(scope, path: path)
          record.recoveries.append(Recovery(sourcePath: entry.path, path: path, parentIdentity: parent.identity))
        }
        try checkPlanCapacity(record, scope: scope, context: "recovery", recovery: true)
        try save(record)
      }
      guard record.recoveries.allSatisfy({ (try? components($0.path).dropLast().joined(separator: "/")) == directory }) else {
        throw Failure("recovery_destination_locked")
      }
      reconcileRecoveries(record, scope: scope)
      // Only a new explicit recover request may retry an absent planned name.
      // O_EXCL remains mandatory, including if an earlier create outcome was lost.
      for index in record.recoveries.indices where record.recoveries[index].state == "uncertain" {
        let item = record.recoveries[index]
        if let parent = try? Parent(scope: scope, components: components(item.path)),
           parent.identity == item.parentIdentity, (try? pathAbsent(scope, path: item.path)) == true {
          record.recoveries[index].state = "pending"
          record.recoveries[index].identity = nil; record.recoveries[index].revision = nil
        }
      }
      for recoveryIndex in record.recoveries.indices where record.recoveries[recoveryIndex].state == "pending" {
        let item = record.recoveries[recoveryIndex]
        guard let entry = record.entries.first(where: { $0.path == item.sourcePath }) else { throw Failure("journal_invalid") }
        let parts = try components(item.path)
        let parent = try Parent(scope: scope, components: parts)
        guard parent.identity == item.parentIdentity else { throw Failure("parent_changed") }
        try coordinate(scope, path: item.path) {
          try verifyParent(scope: scope, path: item.path, parent: parent)
          try destinationAbsent(scope, path: item.path)
          try checkPlanCapacity(record, scope: scope, context: "recovery", recovery: true)
          try point("beforeRecoveryIntent")
          record.recoveries[recoveryIndex].state = "uncertain"
          try save(record); try point("afterRecoveryIntent")
          try verifyParent(scope: scope, path: item.path, parent: parent)
          try checkPlanCapacity(record, scope: scope, context: "recoveryCreate", recovery: true)
          try verifyParent(scope: scope, path: item.path, parent: parent)
          try destinationAbsent(scope, path: item.path)
          let fd = openat(parent.descriptor, parts.last!, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
          guard fd >= 0 else { throw Failure("recovery_create_failed") }
          defer { close(fd) }
          var created = stat()
          guard fstat(fd, &created) == 0, created.st_nlink == 1 else { throw Failure("recovery_uncertain") }
          record.recoveries[recoveryIndex].identity = Self.identity(created)
          try save(record); try point("afterRecoveryCreate")
          try verifyParent(scope: scope, path: item.path, parent: parent)
          try preserveMetadata(fd, entry: entry, privateCopy: true)
          try writeAll(fd, data: entry.original, operation: "recovery")
          guard fsync(fd) == 0, fsync(parent.descriptor) == 0 else { throw Failure("recovery_sync_failed") }
          try point("afterRecoveryWrite")
          try verifyParent(scope: scope, path: item.path, parent: parent)
          let observed = try read(scope, path: item.path)
          guard observed.identity == Self.identity(created), observed.bytes == entry.original,
                observed.permissions == 0o600, observed.protectionClass == entry.protectionClass else { throw Failure("recovery_uncertain") }
          record.recoveries[recoveryIndex].revision = observed.revision
          record.recoveries[recoveryIndex].state = "applied"
          try point("beforeRecoveryReceipt"); try save(record); try point("afterRecoveryReceipt")
        }
      }
    } catch {
      // A lost receipt must be reconciled from the durable manifest, not from
      // optimistic in-memory state that may never have reached stable storage.
      if let durable = try? load(id) {
        reconcileRecoveries(durable, scope: scope); durable.code = code(error)
        do { try reconcile(durable, scope: scope) } catch { markUnverifiable(durable) }
        try? save(durable)
        return result(durable)
      }
      record.code = code(error); markUnverifiable(record)
    }
    reconcileRecoveries(record, scope: scope)
    do { try reconcile(record, scope: scope) } catch { markUnverifiable(record); record.code = code(error) }
    return result(record)
  }

  private func retryEligible(_ record: Record) -> Bool {
    // This describes the last durable observation, not a new grant. Rendering
    // must not discover and then lose an unpersisted dependency conflict.
    !record.cancelled && !record.consistencyConflict && record.phase != "completed" &&
      sessions[record.transactionId] != nil &&
      record.entries.allSatisfy { ($0.state == "pending" || $0.state == "applied") && $0.intent == nil }
  }

  private func result(_ record: Record) -> [String: Any] {
    var value: [String: Any] = ["transactionId": record.transactionId, "phase": record.phase,
      "sourcePath": record.sourcePath, "destinationPath": record.destinationPath,
      "retryAllowed": retryEligible(record),
      "entries": record.entries.map { entry -> [String: Any] in
        var row: [String: Any] = ["path": entry.path, "destinationPath": entry.destinationPath, "state": entry.state,
          "verified": !record.cancelled && (entry.state == "pending" || entry.state == "applied") && entry.actualPath != nil && entry.actualRevision != nil]
        if let path = entry.actualPath { row["actualPath"] = path }
        if let revision = entry.actualRevision { row["revision"] = revision }
        return row
      },
      "retainedArtifacts": record.entries.compactMap { entry -> [String: Any]? in
        guard let path = entry.artifactPath, entry.artifactState != "pending" else { return nil }
        return ["path": path, "state": entry.artifactState,
                "verified": entry.artifactState == "retained" || entry.artifactState == "staged"]
      },
      "recoveryPaths": record.recoveries.filter { $0.state == "applied" }.map(\.path),
      "recoveryEntries": record.recoveries.map { item -> [String: Any] in
        var row: [String: Any] = ["sourcePath": item.sourcePath, "path": item.path, "state": item.state,
          "verified": item.state == "applied"]
        if let revision = item.revision { row["revision"] = revision }
        return row
      }]
    if let code = record.code { value["code"] = code }
    if let session = sessions[record.transactionId], value["retryAllowed"] as? Bool == true { value["token"] = session.token }
    return value
  }

  /// Conservative available-space estimates, not a reservation or quota.
  /// Aggregate by actual st_dev so journal + stage on one volume are not each
  /// allowed to spend the same free bytes. Concurrent exhaustion still fails closed.
  private struct CapacityNeed {
    let device: Int32
    let required: UInt64
    let available: UInt64
  }
  private func capacityNeed(_ fd: Int32, count: Int, context: String) throws -> CapacityNeed {
    var info = stat(); var volume = statfs()
    guard count >= 0, fstat(fd, &info) == 0, fstatfs(fd, &volume) == 0, volume.f_bsize > 0 else {
      throw Failure("capacity_unavailable")
    }
    let block = UInt64(volume.f_bsize)
    let rounded = ((UInt64(count) + block - 1) / block) * block
    let (free, overflow) = UInt64(volume.f_bavail).multipliedReportingOverflow(by: block)
    guard !overflow else { throw Failure("capacity_unavailable") }
    let effective = min(free, availableBytesOverride?(context, info.st_dev, free) ?? free)
    return CapacityNeed(device: info.st_dev, required: rounded + 16 * 1024, available: effective)
  }
  private func checkCapacityNeeds(_ needs: [CapacityNeed]) throws {
    var totals: [Int32: UInt64] = [:]; var available: [Int32: UInt64] = [:]
    for need in needs {
      totals[need.device, default: 0] += need.required
      available[need.device] = min(available[need.device] ?? need.available, need.available)
    }
    for (device, required) in totals {
      guard available[device, default: 0] >= required + 1024 * 1024 else { throw Failure("insufficient_space") }
    }
  }
  private func checkCapacity(_ reservations: [(Int32, Int)], context: String) throws {
    try checkCapacityNeeds(reservations.map { try capacityNeed($0.0, count: $0.1, context: context) })
  }
  private func parentCapacity(_ scope: WorkspaceTextScope, path: String, identity: String,
                              count: Int, context: String) throws -> CapacityNeed {
    // Extract bounded volume metadata and close this temporary descriptor now;
    // do not hold 2 * 128 extra descriptors alongside the pinned live session.
    let parent = try Parent(scope: scope, components: components(path))
    guard parent.identity == identity else { throw Failure("parent_changed") }
    try verifyParent(scope: scope, path: path, parent: parent)
    let need = try capacityNeed(parent.descriptor, count: count, context: context)
    try verifyParent(scope: scope, path: path, parent: parent)
    return need
  }

  private func checkMutationParents(_ record: Record, scope: WorkspaceTextScope) throws {
    var devices: [String: Int32] = [:]
    for entry in record.entries {
      for (path, identity) in [(entry.path, entry.parentIdentity), (entry.destinationPath, entry.destinationParentIdentity)] {
        let parent = try sessions[record.transactionId]?.parents[path] ?? Parent(scope: scope, components: components(path))
        guard parent.identity == identity else { throw Failure("parent_changed") }
        try verifyParent(scope: scope, path: path, parent: parent)
        var info = stat()
        guard fstat(parent.descriptor, &info) == 0 else { throw Failure("parent_unavailable") }
        let accessible = faccessat(parent.descriptor, ".", W_OK | X_OK, AT_EACCESS) == 0
        guard accessible && (parentAccessOverride?(path, accessible) ?? accessible) else { throw Failure("parent_not_writable") }
        devices[path] = parentDeviceOverride?(path, info.st_dev) ?? info.st_dev
        try verifyParent(scope: scope, path: path, parent: parent)
      }
    }
    // RENAME_EXCL cannot cross volumes. Refuse before rewriting any inbound
    // note, rather than discovering EXDEV after a partially applied plan.
    guard devices[record.sourcePath] == devices[record.destinationPath] else { throw Failure("cross_volume_move") }
    // faccessat is only an early rejection, not an authority/permission CAS.
  }

  private func checkPlanCapacity(_ record: Record, scope: WorkspaceTextScope, context: String,
                                 recovery: Bool = false) throws {
    if !recovery { try checkMutationParents(record, scope: scope) }
    let directory = try journalDescriptor(); defer { close(directory) }
    // JSONEncoder includes base64 expansion. Two full generations plus bounded
    // receipt/manifest headroom cover atomic .pending rewrites before any stage.
    let encoded = try JSONEncoder().encode(record).count
    var needs = [try capacityNeed(directory, count: 2 * (encoded + 512 * 1024), context: context)]
    if recovery {
      for item in record.recoveries where item.state != "applied" {
        guard let entry = record.entries.first(where: { $0.path == item.sourcePath }) else { throw Failure("journal_invalid") }
        needs.append(try parentCapacity(scope, path: item.path, identity: item.parentIdentity,
                                        count: entry.original.count, context: context))
      }
    } else {
      for entry in record.entries {
        let bytes = entry.artifactPath != nil && entry.stagedIdentity == nil ? entry.replacement.count : 0
        needs.append(try parentCapacity(scope, path: entry.path, identity: entry.parentIdentity, count: bytes, context: context))
        needs.append(try parentCapacity(scope, path: entry.destinationPath, identity: entry.destinationParentIdentity, count: 0, context: context))
      }
    }
    try checkCapacityNeeds(needs)
    try scope.verifyRootLocation()
  }

  private func verifyDirectoryLocation(_ descriptor: Int32, url: URL) throws {
    var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    var held = stat(); var named = stat()
    let pathStatus = path.withUnsafeMutableBufferPointer { fcntl(descriptor, F_GETPATH, $0.baseAddress!) }
    guard pathStatus == 0,
          URL(fileURLWithPath: String(cString: path)).standardizedFileURL == url.standardizedFileURL,
          fstat(descriptor, &held) == 0, lstat(url.path, &named) == 0,
          named.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR), Self.identity(held) == Self.identity(named) else {
      throw Failure("private_journal_unavailable")
    }
  }

  // The journal is never in the workspace or a ubiquity container. File mode
  // 0600 and directory mode 0700; bounded JSON; SHA256 per touched payload.
  // No unrelated catalog paths, graph, bodies, or attachment bytes are persisted.
  private func journalDescriptor() throws -> Int32 {
    // Resolve only the existing system/base ancestor (e.g. /var -> /private/var),
    // then pin it. App-owned suffix components never follow symlinks. Every
    // child AND its parent's directory entry are synced, including on a retry
    // that finds a directory left by an earlier failed initialization.
    var anchorURL = journalBaseURL
    var info = stat()
    while lstat(anchorURL.path, &info) != 0 {
      guard errno == ENOENT, anchorURL.path != "/" else { throw Failure("private_journal_unavailable") }
      anchorURL.deleteLastPathComponent()
    }
    guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { throw Failure("private_journal_unavailable") }
    let suffix = Array(journalURL.pathComponents.dropFirst(anchorURL.pathComponents.count))
    guard !suffix.isEmpty, !suffix.contains(".."), !suffix.contains(".") else { throw Failure("private_journal_unavailable") }
    anchorURL = anchorURL.resolvingSymlinksInPath().standardizedFileURL
    let anchor = open(anchorURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard anchor >= 0 else { throw Failure("private_journal_unavailable") }
    defer { close(anchor) }
    try verifyDirectoryLocation(anchor, url: anchorURL)
    // Also persist the anchor's own name if it was created by a prior attempt.
    let ancestor = openat(anchor, "..", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard ancestor >= 0 else { throw Failure("private_journal_unavailable") }
    defer { close(ancestor) }
    try syncDescriptor(anchor, operation: "JournalAnchorSync")
    try syncDescriptor(ancestor, operation: "JournalAncestorSync")
    try verifyDirectoryLocation(anchor, url: anchorURL)
    var current = dup(anchor)
    guard current >= 0 else { throw Failure("private_journal_unavailable") }
    var currentURL = anchorURL
    do {
      for name in suffix {
        try verifyDirectoryLocation(anchor, url: anchorURL)
        try verifyDirectoryLocation(current, url: currentURL)
        var named = stat()
        if fstatat(current, name, &named, AT_SYMLINK_NOFOLLOW) != 0 {
          guard errno == ENOENT else { throw Failure("private_journal_unavailable") }
          try checkCapacity([(current, 64 * 1024)], context: "journalDirectory")
          try point("beforeJournalDirectoryCreate")
          guard mkdirat(current, name, 0o700) == 0 else { throw Failure("private_journal_unavailable") }
          try point("afterJournalDirectoryCreate")
        }
        let child = openat(current, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard child >= 0 else { throw Failure("private_journal_unavailable") }
        do {
          var attributes = stat()
          guard fstat(child, &attributes) == 0, attributes.st_uid == getuid(),
                attributes.st_flags & UInt32(SF_DATALESS) == 0 else { throw Failure("private_journal_unavailable") }
          try requireEmptyACL(child, failureCode: "private_journal_unavailable")
          let childURL = currentURL.appendingPathComponent(name, isDirectory: true)
          try verifyDirectoryLocation(child, url: childURL)
          if name == suffix.last! {
            let excluded = try childURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
            if attributes.st_mode & 0o777 != 0o700 || !excluded {
              // Existing private journals remain readable under low free space.
              // Capacity checks apply to creation/metadata changes, not opens.
              try checkCapacity([(child, 64 * 1024)], context: "journalDirectory")
              guard fchmod(child, 0o700) == 0 else { throw Failure("private_journal_unavailable") }
              var privateURL = childURL
              var values = URLResourceValues(); values.isExcludedFromBackup = true
              try privateURL.setResourceValues(values)
            }
          }
          try syncDescriptor(child, operation: "JournalDirectoryChildSync")
          try syncDescriptor(current, operation: "JournalDirectoryParentSync")
          try verifyDirectoryLocation(current, url: currentURL)
          try verifyDirectoryLocation(child, url: childURL)
          close(current); current = child; currentURL = childURL
        } catch { close(child); throw error }
      }
      try verifyDirectoryLocation(anchor, url: anchorURL)
      var attributes = stat()
      guard fstat(current, &attributes) == 0 else { throw Failure("private_journal_unavailable") }
      let identity = Self.identity(attributes)
      guard journalIdentity == nil || journalIdentity == identity else { throw Failure("private_journal_unavailable") }
      journalIdentity = identity; journalCanonicalURL = currentURL
      return current
    } catch { close(current); throw error }
  }
  private func journalFiles(_ descriptor: Int32) throws -> [(String, Int)] {
    let duplicate = openat(descriptor, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard duplicate >= 0, let directory = fdopendir(duplicate) else { if duplicate >= 0 { close(duplicate) }; throw Failure("journal_unavailable") }
    defer { closedir(directory) }
    var result: [(String, Int)] = []
    while true {
      errno = 0
      guard let entry = readdir(directory) else { if errno != 0 { throw Failure("journal_unavailable") }; break }
      let capacity = Int(entry.pointee.d_namlen) + 1
      let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { String(validatingUTF8: $0) }
      }
      guard let name else { throw Failure("journal_unavailable") }
      if name == "." || name == ".." { continue }
      guard result.count < 256 else { throw Failure("journal_full") }
      var value = stat()
      guard fstatat(descriptor, name, &value, AT_SYMLINK_NOFOLLOW) == 0,
            value.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), value.st_size >= 0,
            value.st_size <= Self.maximumJournalBytes else { throw Failure("journal_unavailable") }
      result.append((name, Int(value.st_size)))
    }
    return result
  }
  private func exists(_ id: String) throws -> Bool {
    let fd = try journalDescriptor(); defer { close(fd) }
    var value = stat()
    if fstatat(fd, id + ".json", &value, AT_SYMLINK_NOFOLLOW) == 0 { return true }
    guard errno == ENOENT else { throw Failure("journal_unavailable") }
    return false
  }
  private func save(_ record: Record) throws {
    do {
      let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
      let data = try encoder.encode(record)
      guard data.count <= 48 * 1024 * 1024 else { throw Failure("journal_limit") }
      let directory = try journalDescriptor(); defer { close(directory) }
      let files = try journalFiles(directory)
      let name = record.transactionId + ".json"
      let retained = files.reduce(0) { $0 + $1.1 }
      let existing = files.contains { $0.0 == name }
      let largest = max(data.count, files.filter { $0.0.hasSuffix(".json") }.map { $0.1 }.max() ?? 0)
      let receiptReserve = 512 * 1024
      guard (existing || files.filter { $0.0.hasSuffix(".json") }.count < maximumStoredRecords),
            retained + data.count + (existing ? 0 : largest + receiptReserve) <= maximumStoredBytes else {
        throw Failure("journal_full")
      }
      if !existing {
        var reserved = record.entries.reduce(0) { $0 + ($1.artifactPath == nil ? 0 : $1.original.count + $1.replacement.count) }
        for (other, _) in files where other.hasSuffix(".json") {
          let previous = try load(String(other.dropLast(5)))
          reserved += previous.entries.reduce(0) { $0 + ($1.artifactPath == nil ? 0 : $1.original.count + $1.replacement.count) }
        }
        guard reserved <= Self.maximumArtifactReservationBytes else { throw Failure("artifact_storage_full") }
      }
      try checkCapacity([(directory, data.count + receiptReserve)], context: "journal")
      guard let journalCanonicalURL else { throw Failure("private_journal_unavailable") }
      try verifyDirectoryLocation(directory, url: journalCanonicalURL)
      let temporary = record.transactionId + ".\(UUID().uuidString).pending"
      let fd = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
      guard fd >= 0 else { throw Failure("journal_unavailable") }
      defer { close(fd) }
      do {
        try requirePlainMetadata(fd)
        var created = stat()
        guard fstat(fd, &created) == 0, created.st_nlink == 1,
              created.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), created.st_mode & 0o777 == 0o600 else {
          throw Failure("private_journal_unavailable")
        }
      } catch { throw Failure("private_journal_unavailable") }
      // Never prune .pending crash remnants or unfinished records to make room.
      #if os(iOS)
      // Class A (complete protection) before any original bytes enter the journal.
      guard fcntl(fd, F_SETPROTECTIONCLASS, Int32(1)) == 0,
            try protectionClass(fd) == 1 else { throw Failure("private_journal_unavailable") }
      #endif
      try writeAll(fd, data: data, operation: "journal")
      try point("beforeJournalSync")
      guard fsync(fd) == 0 else { throw Failure("journal_sync_failed") }
      try verifyDirectoryLocation(directory, url: journalCanonicalURL)
      guard renameat(directory, temporary, directory, name) == 0 else { throw Failure("journal_unavailable") }
      // This boundary is distinct from file sync: rename may already be visible
      // while its directory entry is not yet durable.
      try syncDescriptor(directory, operation: "JournalReceiptDirectorySync")
      try verifyDirectoryLocation(directory, url: journalCanonicalURL)
      try point("afterJournalSync")
    } catch {
      // Even if rename made an optimistic receipt visible in the page cache,
      // a failed journal save cannot retain authority to recreate completion.
      revokeUnpersisted(record)
      throw error
    }
  }
  private func load(_ id: String) throws -> Record {
    let directory = try journalDescriptor(); defer { close(directory) }
    let fd = openat(directory, id + ".json", O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard fd >= 0 else { throw Failure("journal_not_found") }
    defer { close(fd) }
    var info = stat()
    guard fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_nlink == 1,
          info.st_uid == getuid(), info.st_mode & 0o777 == 0o600,
          info.st_flags & UInt32(SF_DATALESS) == 0,
          info.st_size > 0, info.st_size <= 48 * 1024 * 1024 else { throw Failure("journal_invalid") }
    var data = Data(count: Int(info.st_size))
    try data.withUnsafeMutableBytes { buffer in
      var offset = 0
      while offset < buffer.count {
        let count = Darwin.read(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
        if count < 0 && errno == EINTR { continue }
        guard count > 0 else { throw Failure("journal_invalid") }; offset += count
      }
    }
    try requireEmptyACL(fd, failureCode: "private_journal_unavailable")
    let record = try JSONDecoder().decode(Record.self, from: data)
    if observedConsistencyConflicts.contains(id) { record.consistencyConflict = true }
    if unpersistedUncertainty.contains(id) { record.completionVerified = false }
    guard record.version == 1, record.transactionId == id, record.entries.count > 0,
          record.entries.count <= Self.maximumFiles, record.recoveries.count <= Self.maximumFiles,
          record.entries.reduce(0, { $0 + $1.original.count + $1.replacement.count }) <= Self.maximumPayloadBytes,
          Set(record.entries.map(\.path)).count == record.entries.count,
          record.entries.filter({ $0.path == record.sourcePath }).count == 1 else { throw Failure("journal_invalid") }
    _ = try components(record.sourcePath); _ = try components(record.destinationPath)
    for entry in record.entries {
      let parts = try components(entry.path); _ = try components(entry.destinationPath)
      if let artifact = entry.artifactPath {
        let artifactParts = try artifactComponents(artifact)
        guard artifactParts.dropLast().elementsEqual(parts.dropLast()),
              artifactParts.last == ".linefold-note-move-\(id)-\(record.entries.firstIndex(where: { $0.path == entry.path })!).md" else {
          throw Failure("journal_invalid")
        }
      }
      guard Self.hash(entry.original) == entry.originalHash, Self.hash(entry.replacement) == entry.replacementHash,
            Self.identity(entry.expectedRevision) == entry.expectedIdentity else { throw Failure("journal_invalid") }
    }
    guard Set(record.recoveries.map(\.sourcePath)).count == record.recoveries.count else { throw Failure("journal_invalid") }
    for item in record.recoveries {
      _ = try components(item.path)
      guard record.entries.contains(where: { $0.path == item.sourcePath }) else { throw Failure("journal_invalid") }
    }
    return record
  }
  private func list(root: URL) throws -> [String: Any] {
    let scope = try WorkspaceTextScope(root); let identity = try scopeIdentity(scope)
    let directory = try journalDescriptor(); defer { close(directory) }
    let files = try journalFiles(directory)
    var records: [[String: Any]] = []; var unavailable = 0
    for (name, _) in files where name.hasSuffix(".json") {
      guard let id = try? transactionId(String(name.dropLast(5))), let record = try? load(id) else { unavailable += 1; continue }
      guard record.rootIdentity == identity, record.rootPath == scope.rootURL.path else { continue }
      do { try reconcile(record, scope: try authorizedScope(root, record: record)) }
      catch { markUnverifiable(record); record.code = code(error) }
      guard records.count < Self.maximumRecords else { unavailable += 1; continue }
      records.append(result(record))
    }
    return ["transactions": records, "unavailableRecords": unavailable,
            "retainedBytes": files.reduce(0) { $0 + $1.1 },
            "storageBlocked": files.reduce(0) { $0 + $1.1 } >= maximumStoredBytes || files.count >= maximumStoredRecords]
  }
}
