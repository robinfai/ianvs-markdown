import Foundation
import Darwin
import CryptoKit
#if os(iOS)
import Flutter
#else
import FlutterMacOS
#endif

/// Versioned note/directory/batch moves with a bounded, durable, app-private recovery journal.
/// Coordination is advisory. The executor must keep per-file body replacement
/// atomic, with displaced versions retained and originals synced first.
/// There is deliberately no rollback, unlink, or overwrite-recovery operation.
final class WorkspaceNoteTransaction {
  static let shared = WorkspaceNoteTransaction()
  static let methods: Set<String> = ["prepareWorkspaceNoteMove", "executeWorkspaceNoteMove",
    "listWorkspaceNoteMoves", "reconcileWorkspaceNoteMove", "recoverWorkspaceNoteMove",
    "cancelPreparedWorkspaceNoteMove", "inspectWorkspaceNoteMoveStorage", "prepareWorkspaceDirectoryMove", "prepareWorkspaceBatchMove"]
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
  // Synthetic inventory hooks. Production never supplies these; neither is a channel argument.
  var inventoryArtifactObserver: ((String) -> Void)?
  var inventoryDatalessOverride: ((String) -> Bool)?
  var inventoryReadBudgetOverride: Int?
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
    let provenance: Data?
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
  /// v2 separates the namespace receipt from text entries: an empty directory
  /// is a real operation, not a fabricated text file. Paths remain immutable.
  private struct TreeMember: Codable, Equatable {
    let path: String
    let kind: String
    let revision: String
    let identity: String
  }
  private struct DirectoryNamespace: Codable {
    let identity: String
    let sourceParentIdentity: String
    let destinationParentIdentity: String
    let members: [TreeMember]
    var intent = false
    var moved = false
    var synced = false
    var observedPath: String?
    var verified = false
  }
  private struct BatchNamespace: Codable {
    let sourcePath: String
    let destinationPath: String
    let kind: String
    let identity: String
    let sourceParentIdentity: String
    let destinationParentIdentity: String
    let members: [TreeMember]
    var intent = false
    var moved = false
    var synced = false
    var observedPath: String?
    var verified = false
  }
  private final class Record: Codable {
    var version = 1
    var namespace: DirectoryNamespace?
    var namespaces: [BatchNamespace]?
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
    let provenance: Data?
  }

  /// Call only on CloudWorkspace's serial transaction queue.
  func perform(_ method: String, arguments: [String: Any]) -> Any {
    // Inspection has its own error path: even a malformed request must never
    // fall through to load(), which initializes/repairs the private journal.
    if method == "inspectWorkspaceNoteMoveStorage" {
      do {
        return try WorkspaceFileScope.withoutMaterialization {
          guard let path = arguments["path"] as? String, path.hasPrefix("/"), !path.contains("\0") else {
            throw Failure("scope_unavailable")
          }
          return try inspectStorage(root: URL(fileURLWithPath: path, isDirectory: true))
        }
      } catch { return unavailableStorage(code(error)) }
    }
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
        case "prepareWorkspaceDirectoryMove": return try prepareDirectory(root: root, id: id, arguments: arguments)
        case "prepareWorkspaceBatchMove": return try prepareBatch(root: root, id: id, arguments: arguments)
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
    let current = try scope.parentDescriptor(try WorkspaceFileScope.relativeComponents(path)); defer { close(current) }
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
  private func dependencyDigest(_ scope: WorkspaceTextScope, excluding: Set<String>, directoryRecord: Record? = nil) throws -> String {
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
        let logicalPath: String
        if let record = directoryRecord, record.version == 3 {
          logicalPath = batchPath(path, record: record, inverse: true)
        } else if let record = directoryRecord, record.namespace?.moved == true {
          logicalPath = mapDirectoryPath(path, source: record.destinationPath, destination: record.sourcePath)
        } else { logicalPath = path }
        if excluding.contains(logicalPath) { continue }
        let revision = kind == mode_t(S_IFDIR) ? Self.identity(value) : WorkspaceFileScope.revision(value)
        let local = value.st_flags & UInt32(SF_DATALESS) == 0
        lines.append(Data("\(logicalPath.utf8.count):\(logicalPath)|\(kind)|\(revision)|\(local)\n".utf8))
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
      snapshot.protectionClass == entry.protectionClass && snapshot.provenance == entry.provenance
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
    if record.version == 3 { try validateBatchReadSet(record, scope: session.scope, session: session); return }
    if record.version == 2 { try validateDirectoryReadSet(record, scope: session.scope, session: session); return }
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
              snapshot.protectionClass == entry.protectionClass && snapshot.provenance == entry.provenance else {
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
  /// The bounded macOS provenance attribute is retained byte-for-byte.
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
    let currentProvenance = try readProvenance(descriptor)
    if currentProvenance != entry.provenance {
      #if os(macOS)
      guard let original = entry.provenance, !original.isEmpty, original.count <= 4096 else {
        throw Failure("metadata_preservation_failed")
      }
      let status = original.withUnsafeBytes {
        fsetxattr(descriptor, "com.apple.provenance", $0.baseAddress, $0.count, 0, 0)
      }
      guard status == 0, try readProvenance(descriptor) == original else {
        throw Failure("metadata_preservation_failed")
      }
      #else
      throw Failure("metadata_preservation_failed")
      #endif
    }
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
    _ = try readProvenance(descriptor)
    try requireEmptyACL(descriptor)
  }

  /// Preserve the one OS-generated extended attribute observed on ordinary
  /// macOS files. Unknown attributes still fail closed. Never remove provenance.
  private func readProvenance(_ descriptor: Int32) throws -> Data? {
    let count = flistxattr(descriptor, nil, 0, 0)
    guard count >= 0, count <= 256 else { throw Failure("unsupported_metadata") }
    if count == 0 { return nil }
    #if os(macOS)
    var names = [CChar](repeating: 0, count: count)
    let actual = names.withUnsafeMutableBufferPointer {
      flistxattr(descriptor, $0.baseAddress, $0.count, 0)
    }
    let expected = Array("com.apple.provenance\0".utf8)
    guard actual == count, names.map({ UInt8(bitPattern: $0) }) == expected else {
      throw Failure("unsupported_metadata")
    }
    let size = fgetxattr(descriptor, "com.apple.provenance", nil, 0, 0, 0)
    guard size > 0, size <= 4096 else { throw Failure("unsupported_metadata") }
    var data = Data(count: size)
    let read = data.withUnsafeMutableBytes {
      fgetxattr(descriptor, "com.apple.provenance", $0.baseAddress, $0.count, 0, 0)
    }
    guard read == size else { throw Failure("unsupported_metadata") }
    return data
    #else
    throw Failure("unsupported_metadata")
    #endif
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
    let sourceProvenance = try readProvenance(descriptor)
    var inspected = stat()
    guard fstat(descriptor, &inspected) == 0,
          WorkspaceFileScope.revision(inspected) == WorkspaceFileScope.revision(attributes) else { throw Failure("file_conflict") }
    let data = try scope.readLocalBytes(components: parts, maximumBytes: Self.maximumPayloadBytes, verifyRevision: true)
    guard data.revision == WorkspaceFileScope.revision(attributes), String(data: data.bytes, encoding: .utf8) != nil else {
      throw Failure("file_conflict")
    }
    return Snapshot(bytes: data.bytes, revision: data.revision, identity: Self.identity(attributes),
                    permissions: UInt32(attributes.st_mode & 0o777), owner: attributes.st_uid, group: attributes.st_gid,
                    protectionClass: dataProtection, provenance: sourceProvenance)
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
      guard record.version == 1, arguments["sourcePath"] as? String == record.sourcePath,
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
        protectionClass: snapshot.protectionClass, provenance: snapshot.provenance, artifactPath: original.data == replacement.data ? nil :
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
    if record.version == 3 { return try executeBatch(root: root, record: record, token: token) }
    if record.version == 2 { return try executeDirectory(root: root, record: record, token: token) }
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
                            relativePath: String, parentDescriptor: Int32, directory: Bool = false) throws {
    do {
      try WorkspaceFileScope.withoutMaterialization {
        guard observed.isFileURL, observed.host == nil || observed.host == "",
              observed.user == nil, observed.password == nil, observed.port == nil,
              observed.query == nil, observed.fragment == nil, directory || !observed.hasDirectoryPath,
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
          guard (directory ? leaf.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) : leaf.st_mode & mode_t(S_IFMT) != mode_t(S_IFLNK)),
                leaf.st_flags & UInt32(SF_DATALESS) == 0 else { throw Failure("coordinator_redirected") }
        } else if errno != ENOENT { throw Failure("coordinator_redirected") }
        try scope.verifyRootLocation(); try candidate.verifyRootLocation()
      }
    } catch { throw Failure("coordinator_redirected") }
  }

  private func coordinate(_ scope: WorkspaceFileScope, path: String, destination: String? = nil, moving: Bool = true,
                          coordinator: NSFileCoordinator = NSFileCoordinator(), directory: Bool = false, body: () throws -> Void) throws {
    let url = scope.rootURL.appendingPathComponent(path, isDirectory: directory)
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
      let target = scope.rootURL.appendingPathComponent(destination, isDirectory: directory)
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
            try verifyCoordinatedURL(a, scope: scope, relativePath: path, parentDescriptor: sourceParent.descriptor, directory: directory)
            try verifyCoordinatedURL(b, scope: scope, relativePath: destination, parentDescriptor: targetParent.descriptor, directory: directory)
            guard DispatchTime.now().uptimeNanoseconds < deadline.uptimeNanoseconds else { throw Failure("coordinator_redirected") }
            try body() // The body still uses only its original pinned authority.
            try verifyCoordinatedURL(a, scope: scope, relativePath: path, parentDescriptor: sourceParent.descriptor, directory: directory)
            try verifyCoordinatedURL(b, scope: scope, relativePath: destination, parentDescriptor: targetParent.descriptor, directory: directory)
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
            try verifyCoordinatedURL(current, scope: scope, relativePath: path, parentDescriptor: sourceParent.descriptor, directory: directory)
            guard DispatchTime.now().uptimeNanoseconds < deadline.uptimeNanoseconds else { throw Failure("coordinator_redirected") }
            try body()
            try verifyCoordinatedURL(current, scope: scope, relativePath: path, parentDescriptor: sourceParent.descriptor, directory: directory)
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
      a.protectionClass == b.protectionClass && a.provenance == b.provenance
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
            staged.protectionClass == initial.protectionClass, staged.provenance == initial.provenance else { throw Failure("stage_uncertain") }
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
            observed.protectionClass == entry.protectionClass, observed.provenance == entry.provenance,
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
    record.namespaces?.contains(where: { $0.intent || $0.moved }) == true || record.namespace?.intent == true || record.namespace?.moved == true || record.entries.contains { $0.intent != nil || $0.stagedIdentity != nil || $0.writeRevision != nil || $0.moveRevision != nil || $0.state == "uncertain" }
  }
  private func markUnverifiable(_ record: Record) {
    revokeUnpersisted(record)
    if record.namespace != nil { record.namespace?.verified = false; record.namespace?.observedPath = nil }
    if let roots = record.namespaces {
      for index in roots.indices { record.namespaces?[index].verified = false; record.namespaces?[index].observedPath = nil }
    }
    for index in record.entries.indices { record.entries[index].state = "uncertain"; record.entries[index].actualPath = nil; record.entries[index].actualRevision = nil; record.entries[index].artifactState = "uncertain" }
    for index in record.recoveries.indices where record.recoveries[index].state == "applied" {
      record.recoveries[index].state = "uncertain"
    }
    record.phase = "uncertain"
  }
  private func reconcile(_ record: Record, scope: WorkspaceTextScope) throws {
    if record.version == 3 { try reconcileBatch(record, scope: scope); return }
    if record.version == 2 { try reconcileDirectory(record, scope: scope); return }
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
           current.protectionClass == entry.protectionClass, current.provenance == entry.provenance,
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
  private func pathAbsent(_ scope: WorkspaceFileScope, path: String, artifact: Bool = false, directory: Bool = false) throws -> Bool {
    let parts = try (artifact ? artifactComponents(path) : (directory ? WorkspaceTextScope.textComponents(path, directory: true) : components(path))); let parent = try scope.parentDescriptor(parts); defer { close(parent) }
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
                observed.revision == item.revision, observed.bytes == entry.original,
                observed.permissions == 0o600, observed.owner == entry.owner, observed.group == entry.group,
                observed.protectionClass == entry.protectionClass,
                observed.provenance == entry.provenance else { throw Failure("recovery_uncertain") }
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
                observed.permissions == 0o600, observed.protectionClass == entry.protectionClass, observed.provenance == entry.provenance else { throw Failure("recovery_uncertain") }
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
    (record.version == 1 || (record.version == 2 && record.namespace?.intent == false && record.namespace?.moved == false) ||
      (record.version == 3 && record.namespaces?.allSatisfy({ !$0.intent && !$0.moved }) == true)) &&
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
        return ["path": artifactLocation(path, record: record), "state": entry.artifactState,
                "verified": entry.artifactState == "retained" || entry.artifactState == "staged"]
      },
      "recoveryPaths": record.recoveries.filter { $0.state == "applied" }.map(\.path),
      "recoveryEntries": record.recoveries.map { item -> [String: Any] in
        var row: [String: Any] = ["sourcePath": item.sourcePath, "path": item.path, "state": item.state,
          "verified": item.state == "applied"]
        if let revision = item.revision { row["revision"] = revision }
        return row
      }]
    value["version"] = record.version
    if let namespace = record.namespace {
      var receipt: [String: Any] = ["sourcePath": record.sourcePath, "destinationPath": record.destinationPath,
        "identity": namespace.identity, "moved": namespace.moved, "synced": namespace.synced,
        "verified": namespace.verified, "memberCount": namespace.members.count]
      if let path = namespace.observedPath { receipt["actualPath"] = path }
      value["namespace"] = receipt
    }
    if let roots = record.namespaces {
      value["namespaces"] = roots.map { root -> [String: Any] in
        var row: [String: Any] = ["sourcePath": root.sourcePath, "destinationPath": root.destinationPath,
          "kind": root.kind, "identity": root.identity, "moved": root.moved, "synced": root.synced,
          "verified": root.verified, "memberCount": root.members.count]
        if let path = root.observedPath { row["actualPath"] = path }
        return row
      }
    }
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
                              count: Int, context: String, directory: Bool = false) throws -> CapacityNeed {
    // Extract bounded volume metadata and close this temporary descriptor now;
    // do not hold 2 * 128 extra descriptors alongside the pinned live session.
    let parts = try WorkspaceTextScope.textComponents(path, directory: directory)
    let parent = try Parent(scope: scope, components: parts)
    guard parent.identity == identity else { throw Failure("parent_changed") }
    try verifyParent(scope: scope, path: path, parent: parent)
    let need = try capacityNeed(parent.descriptor, count: count, context: context)
    try verifyParent(scope: scope, path: path, parent: parent)
    return need
  }

  private func checkMutationParents(_ record: Record, scope: WorkspaceTextScope) throws {
    if record.version == 3 { try checkBatchParents(record, scope: scope); return }
    if record.version == 2 { try checkDirectoryParents(record, scope: scope); return }
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
    } else if record.version == 3 {
      guard let roots = record.namespaces else { throw Failure("journal_invalid") }
      for root in roots {
        for (path, identity) in [(root.sourcePath, root.sourceParentIdentity), (root.destinationPath, root.destinationParentIdentity)] {
          needs.append(try parentCapacity(scope, path: path, identity: identity, count: 0, context: context,
                                          directory: root.kind == "directory"))
        }
      }
      for entry in record.entries {
        let path = batchPath(entry.path, record: record)
        let parentIdentity = path == entry.path ? entry.parentIdentity : entry.destinationParentIdentity
        let bytes = entry.artifactPath != nil && entry.stagedIdentity == nil ? entry.replacement.count : 0
        needs.append(try parentCapacity(scope, path: path, identity: parentIdentity, count: bytes, context: context))
      }
    } else if record.version == 2 {
      guard let namespace = record.namespace else { throw Failure("journal_invalid") }
      for (path, identity) in [(record.sourcePath, namespace.sourceParentIdentity),
                               (record.destinationPath, namespace.destinationParentIdentity)] {
        let parent = try Parent(scope: scope, components: WorkspaceFileScope.relativeComponents(path))
        guard parent.identity == identity else { throw Failure("parent_changed") }
        needs.append(try capacityNeed(parent.descriptor, count: 0, context: context))
      }
      for entry in record.entries {
        let path = namespace.moved ? entry.destinationPath : entry.path
        let bytes = entry.artifactPath != nil && entry.stagedIdentity == nil ? entry.replacement.count : 0
        needs.append(try parentCapacity(scope, path: path, identity: entry.parentIdentity, count: bytes, context: context))
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
    let record = try decodeRecord(data, id: id)
    if observedConsistencyConflicts.contains(id) { record.consistencyConflict = true }
    if unpersistedUncertainty.contains(id) { record.completionVerified = false }
    return record
  }

  /// Pure journal decoding/validation. It does not apply live execution state,
  /// reopen paths, reconcile, save, or initialize any directory.
  private func decodeRecord(_ data: Data, id: String) throws -> Record {
    let record = try JSONDecoder().decode(Record.self, from: data)
    guard (1...3).contains(record.version), record.transactionId == id, (record.version != 1 || record.entries.count > 0),
          record.entries.count <= Self.maximumFiles, record.recoveries.count <= Self.maximumFiles,
          record.entries.reduce(0, { $0 + $1.original.count + $1.replacement.count }) <= Self.maximumPayloadBytes,
          Set(record.entries.map(\.path)).count == record.entries.count,
          (record.version != 1 || record.entries.filter({ $0.path == record.sourcePath }).count == 1) else { throw Failure("journal_invalid") }
    if record.version == 3 { try validateBatchManifest(record) }
    else if record.version == 2 { guard record.namespaces == nil else { throw Failure("journal_invalid") }; try validateDirectoryManifest(record) }
    else {
      guard record.namespace == nil, record.namespaces == nil else { throw Failure("journal_invalid") }
      _ = try components(record.sourcePath); _ = try components(record.destinationPath)
    }
    for entry in record.entries {
      if let provenance = entry.provenance {
        guard !provenance.isEmpty, provenance.count <= 4096 else { throw Failure("journal_invalid") }
      }
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
  // MARK: - v2 single-directory namespace transaction

  private func mapDirectoryPath(_ path: String, source: String, destination: String) -> String {
    if path.utf8.elementsEqual(source.utf8) { return destination }
    guard path.utf8.starts(with: (source + "/").utf8) else { return path }
    return destination + String(decoding: path.utf8.dropFirst(source.utf8.count), as: UTF8.self)
  }

  private func directoryPaths(_ source: String, _ destination: String) throws {
    for path in [source, destination] {
      let parts = try WorkspaceTextScope.textComponents(path, directory: true)
      guard !parts.isEmpty else { throw Failure("invalid_directory_plan") }
    }
    let a = source.precomposedStringWithCanonicalMapping.lowercased()
    let b = destination.precomposedStringWithCanonicalMapping.lowercased()
    guard a != b, !a.hasPrefix(b + "/"), !b.hasPrefix(a + "/") else {
      throw Failure("overlapping_directory_move")
    }
  }

  private func treeMembers(_ raw: Any?) throws -> [TreeMember] {
    guard let rows = raw as? [[String: Any]], !rows.isEmpty, rows.count <= 256,
          try JSONSerialization.data(withJSONObject: rows).count <= 1024 * 1024 else { throw Failure("invalid_tree") }
    var seen = Set<String>()
    let result = try rows.map { row -> TreeMember in
      guard let path = row["path"] as? String, let kind = row["kind"] as? String,
            ["directory", "note", "image"].contains(kind), row["local"] as? Bool == true,
            let revision = row["revision"] as? String, revision.utf8.count <= 200,
            let identity = row["identity"] as? String, !identity.isEmpty,
            identity == Self.identity(revision), seen.insert(path).inserted else { throw Failure("invalid_tree") }
      let parts = try WorkspaceFileScope.relativeComponents(path)
      guard !parts.contains(where: { $0.hasPrefix(".") }) else { throw Failure("invalid_tree") }
      return TreeMember(path: path, kind: kind, revision: revision, identity: identity)
    }
    return result.sorted { $0.path.utf8.lexicographicallyPrecedes($1.path.utf8) }
  }

  /// Reuse the complete bounded G4a scanner. The only permitted hidden members
  /// during execution are this manifest's separately byte/identity-verified
  /// stage files. A prefix or an arbitrary caller-provided allowlist is not used.
  private func inspectDirectory(_ scope: WorkspaceTextScope, source: String,
                                artifacts: [String: String] = [:]) throws -> [TreeMember] {
    let result = CloudWorkspace.inspectWorkspaceDirectoryMoveTree(scope.rootURL, relativePath: source,
      requestId: UUID().uuidString)
    guard result["complete"] as? Bool == true,
          result["rootIdentity"] as? String == (try scopeIdentity(scope)),
          let issues = result["issues"] as? [[String: String]],
          issues.allSatisfy({ issue in
            guard let path = issue["path"], artifacts[path] != nil else { return false }
            return issue["code"] == "recoveryArtifact" || issue["code"] == "hiddenMember"
          }), let rows = result["members"] as? [[String: Any]] else { throw Failure("directory_tree_unavailable") }
    let expectedArtifacts = artifacts.filter { $0.key.utf8.starts(with: (source + "/").utf8) }
    let artifactRows = rows.filter { artifacts[$0["path"] as? String ?? ""] != nil }
    guard artifactRows.count == expectedArtifacts.count,
          artifactRows.allSatisfy({ row in
            guard let path = row["path"] as? String, let revision = expectedArtifacts[path] else { return false }
            return row["revision"] as? String == revision && row["identity"] as? String == Self.identity(revision) &&
              row["kind"] as? String == "note" && row["local"] as? Bool == true
          }) else { throw Failure("artifact_changed") }
    return try treeMembers(rows.filter { artifacts[$0["path"] as? String ?? ""] == nil })
  }

  /// Inspect every directory entry, including unsupported files and provider
  /// placeholders. The filtered note catalog cannot prove destination vacancy.
  private func directoryDestinationAbsent(_ scope: WorkspaceTextScope, path: String) throws {
    let parts = try WorkspaceTextScope.textComponents(path, directory: true)
    let parent = try scope.parentDescriptor(parts); defer { close(parent) }
    var before = stat()
    guard fstat(parent, &before) == 0 else { throw Failure("destination_unavailable") }
    let fd = openat(parent, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard fd >= 0, let stream = fdopendir(fd) else {
      if fd >= 0 { close(fd) }; throw Failure("destination_unavailable")
    }
    defer { closedir(stream) }
    let folded = parts.last!.precomposedStringWithCanonicalMapping.lowercased()
    let deadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
    var count = 0
    while true {
      guard count < Self.maximumCatalogEntries, DispatchTime.now().uptimeNanoseconds < deadline else {
        throw Failure("destination_scan_limit")
      }
      errno = 0
      guard let entry = readdir(stream) else {
        if errno != 0 { throw Failure("destination_unavailable") }; break
      }
      count += 1
      let name = withUnsafePointer(to: &entry.pointee.d_name) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(validatingUTF8: $0) }
      }
      guard let name else { throw Failure("destination_unavailable") }
      let key = name.precomposedStringWithCanonicalMapping.lowercased()
      guard key != folded, key != "." + folded + ".icloud" else { throw Failure("destination_exists") }
    }
    var after = stat(); var leaf = stat()
    guard fstat(parent, &after) == 0,
          WorkspaceFileScope.revision(before) == WorkspaceFileScope.revision(after),
          fstatat(parent, parts.last!, &leaf, AT_SYMLINK_NOFOLLOW) == -1, errno == ENOENT else {
      throw Failure("destination_exists")
    }
    try scope.verifyRootLocation()
  }

  private func validateDirectoryManifest(_ record: Record) throws {
    try directoryPaths(record.sourcePath, record.destinationPath)
    guard let namespace = record.namespace, !namespace.members.isEmpty, namespace.members.count <= 256,
          namespace.members.filter({ $0.kind == "directory" }).count <= 64,
          Set(namespace.members.map(\.path)).count == namespace.members.count,
          namespace.members.first(where: { $0.path == record.sourcePath })?.identity == namespace.identity,
          namespace.members.first(where: { $0.path == record.sourcePath })?.kind == "directory",
          !namespace.synced || namespace.moved else { throw Failure("journal_invalid") }
    for member in namespace.members {
      let parts = try WorkspaceFileScope.relativeComponents(member.path)
      guard !parts.contains(where: { $0.hasPrefix(".") }),
            member.path == record.sourcePath || member.path.hasPrefix(record.sourcePath + "/"),
            ["directory", "note", "image"].contains(member.kind),
            member.identity == Self.identity(member.revision), member.revision.utf8.count <= 200 else {
        throw Failure("journal_invalid")
      }
      _ = try WorkspaceFileScope.relativeComponents(mapDirectoryPath(member.path,
        source: record.sourcePath, destination: record.destinationPath))
    }
    let notePaths = Set(namespace.members.filter { $0.kind == "note" }.map(\.path))
    let entryPaths = Set(record.entries.map(\.path))
    guard notePaths.isSubset(of: entryPaths) else { throw Failure("directory_note_missing") }
    for entry in record.entries {
      guard entry.path != record.sourcePath,
            entry.destinationPath.utf8.elementsEqual(mapDirectoryPath(entry.path, source: record.sourcePath, destination: record.destinationPath).utf8),
            !entry.path.hasPrefix(record.destinationPath + "/"), entry.path != record.destinationPath,
            entry.parentIdentity == entry.destinationParentIdentity,
            notePaths.contains(entry.path) || entry.original != entry.replacement,
            entry.moveRevision == nil else { throw Failure("journal_invalid") }
    }
  }

  private func prepareDirectory(root: URL, id: String, arguments: [String: Any]) throws -> [String: Any] {
    // Directory requests never recreate live authority from an old ID, including
    // a failed/uncertain previous prepare. A fresh preview must use a fresh ID.
    guard try !exists(id) else { throw Failure("transaction_id_reused") }
    guard let source = arguments["sourcePath"] as? String,
          let destination = arguments["destinationPath"] as? String,
          let files = arguments["files"] as? [[String: Any]], files.count <= Self.maximumFiles,
          let tree = arguments["tree"] as? [String: Any], tree["complete"] as? Bool == true,
          tree["sourcePath"] as? String == source,
          let issues = tree["issues"] as? [[String: Any]], issues.isEmpty else { throw Failure("invalid_directory_plan") }
    try directoryPaths(source, destination)
    let expectedMembers = try treeMembers(tree["members"])
    let scope = try WorkspaceTextScope(root)
    let rootIdentity = try scopeIdentity(scope)
    guard tree["rootIdentity"] as? String == rootIdentity else { throw Failure("scope_changed") }
    let journalPath = journalURL.resolvingSymlinksInPath().standardizedFileURL.path
    guard journalPath != scope.rootURL.path, !journalPath.hasPrefix(scope.rootURL.path + "/"),
          !scope.rootURL.path.hasPrefix(journalPath + "/") else { throw Failure("journal_scope_overlap") }
    let actualMembers = try inspectDirectory(scope, source: source)
    guard actualMembers.count == expectedMembers.count,
          zip(actualMembers, expectedMembers).allSatisfy({ a, b in
            a.path.utf8.elementsEqual(b.path.utf8) && a.kind == b.kind && a.revision == b.revision && a.identity == b.identity
          }),
          let sourceMember = actualMembers.first(where: { $0.path == source }),
          tree["sourceIdentity"] as? String == sourceMember.identity else { throw Failure("directory_tree_changed") }
    let expectedCatalog = try metadata(arguments["catalog"])
    let actualCatalog = try catalog(scope)
    func rows(_ values: [Metadata]) -> [String] { values.map { "\($0.path)|\($0.revision)|\($0.isDirectory)|\($0.local)" }.sorted() }
    guard rows(expectedCatalog) == rows(actualCatalog) else { throw Failure("catalog_changed") }
    let assets = try metadata(arguments["assets"] ?? [[String: Any]](), assets: true)
    try directoryDestinationAbsent(scope, path: destination)
    var parents: [String: Parent] = [:]; var directories: [String: Parent] = [:]
    func pin(_ path: String) throws -> Parent {
      if let value = parents[path] { return value }
      let parts = try WorkspaceFileScope.relativeComponents(path)
      let key = parts.dropLast().joined(separator: "/")
      let value = try directories[key] ?? Parent(scope: scope, components: parts)
      directories[key] = value; parents[path] = value; return value
    }
    let sourceParent = try pin(source); let targetParent = try pin(destination)
    var entries: [Entry] = []; var seen = Set<String>(); var byteCount = 0
    let movedNotes = Set(actualMembers.filter { $0.kind == "note" }.map(\.path))
    for file in files {
      guard let path = file["path"] as? String, let to = file["destinationPath"] as? String,
            let revision = file["expectedRevision"] as? String,
            let original = file["expectedBytes"] as? FlutterStandardTypedData, original.elementSize == 1,
            let replacement = file["replacementBytes"] as? FlutterStandardTypedData, replacement.elementSize == 1,
            seen.insert(path).inserted, path != source, path != destination,
            to.utf8.elementsEqual(mapDirectoryPath(path, source: source, destination: destination).utf8),
            movedNotes.contains(path) || original.data != replacement.data,
            String(data: original.data, encoding: .utf8) != nil, String(data: replacement.data, encoding: .utf8) != nil else {
        throw Failure("invalid_directory_plan")
      }
      _ = try components(path); _ = try components(to)
      byteCount += original.data.count + replacement.data.count
      guard byteCount <= Self.maximumPayloadBytes else { throw Failure("payload_limit") }
      let parent = try pin(path)
      // The future parent is the same pinned directory object, not a path that
      // must already exist. It is re-opened at its new address after the rename.
      parents[to] = parent
      let snapshot = try read(scope, path: path)
      guard snapshot.revision == revision, snapshot.bytes == original.data,
            actualCatalog.contains(where: { $0.path == path && !$0.isDirectory && $0.revision == revision }) else {
        throw Failure("file_conflict")
      }
      let artifact = original.data == replacement.data ? nil :
        (Array(try components(path).dropLast()) + [".linefold-note-move-\(id)-\(entries.count).md"]).joined(separator: "/")
      entries.append(Entry(path: path, destinationPath: to, expectedRevision: revision, expectedIdentity: snapshot.identity,
        parentIdentity: parent.identity, destinationParentIdentity: parent.identity,
        original: original.data, replacement: replacement.data, originalHash: Self.hash(original.data),
        replacementHash: Self.hash(replacement.data), permissions: snapshot.permissions, owner: snapshot.owner,
        group: snapshot.group, protectionClass: snapshot.protectionClass, provenance: snapshot.provenance, artifactPath: artifact,
        actualPath: path, actualRevision: revision))
    }
    guard movedNotes.isSubset(of: seen), actualMembers.filter({ $0.kind == "note" }).allSatisfy({ member in
      entries.contains { $0.path.utf8.elementsEqual(member.path.utf8) }
    }) else { throw Failure("directory_note_missing") }
    let insideArtifacts = entries.compactMap(\.artifactPath).filter { $0.hasPrefix(source + "/") }
    // The complete scanner must also fit the artifacts created by this plan.
    guard actualMembers.count + insideArtifacts.count <= 256,
          try JSONEncoder().encode(actualMembers).count + insideArtifacts.reduce(0, { $0 + 3 * $1.utf8.count + 1024 }) + 16_384 <= 1024 * 1024 else {
      throw Failure("directory_tree_budget")
    }
    for entry in entries {
      if let path = entry.artifactPath, try !pathAbsent(scope, path: path, artifact: true) { throw Failure("artifact_exists") }
    }
    let fingerprint = try digest(actualCatalog, excluding: Set(entries.map(\.path)), assets: assets, scope: scope)
    let record = Record(id: id, scope: scope, rootIdentity: rootIdentity, source: source,
                        destination: destination, digest: fingerprint, entries: entries)
    record.version = 2
    record.namespace = DirectoryNamespace(identity: sourceMember.identity, sourceParentIdentity: sourceParent.identity,
      destinationParentIdentity: targetParent.identity, members: actualMembers, observedPath: source, verified: true)
    try validateDirectoryManifest(record)
    let session = Session(scope: scope, parents: parents, assets: assets)
    try validateDirectoryReadSet(record, scope: scope, session: session)
    try checkPlanCapacity(record, scope: scope, context: "prepare")
    try point("beforePreparedJournal"); try save(record)
    sessions[id] = session
    try point("afterPreparedJournal")
    return result(record)
  }

  private func checkDirectoryParents(_ record: Record, scope: WorkspaceTextScope) throws {
    guard let namespace = record.namespace else { throw Failure("journal_invalid") }
    var devices: [Int32] = []
    var paths: [(String, String)] = [(record.sourcePath, namespace.sourceParentIdentity),
                                   (record.destinationPath, namespace.destinationParentIdentity)]
    paths += record.entries.map { (namespace.moved ? $0.destinationPath : $0.path, $0.parentIdentity) }
    for (path, identity) in paths {
      let parent = try Parent(scope: scope, components: WorkspaceFileScope.relativeComponents(path))
      guard parent.identity == identity else { throw Failure("parent_changed") }
      try verifyParent(scope: scope, path: path, parent: parent)
      var info = stat()
      guard fstat(parent.descriptor, &info) == 0 else { throw Failure("parent_unavailable") }
      let accessible = faccessat(parent.descriptor, ".", W_OK | X_OK, AT_EACCESS) == 0
      guard accessible && (parentAccessOverride?(path, accessible) ?? accessible) else { throw Failure("parent_not_writable") }
      devices.append(parentDeviceOverride?(path, info.st_dev) ?? info.st_dev)
    }
    guard Set(devices).count == 1 else { throw Failure("cross_volume_move") }
  }

  private func validateDirectoryReadSet(_ record: Record, scope: WorkspaceTextScope, session: Session? = nil) throws {
    do {
      try point("beforeSemanticScan")
      guard !record.consistencyConflict, let namespace = record.namespace,
            try scopeIdentity(scope) == record.rootIdentity else { throw Failure("dependency_conflict") }
      let activeRoot = namespace.moved ? record.destinationPath : record.sourcePath
      if namespace.moved {
        guard try pathAbsent(scope, path: record.sourcePath, directory: true) else { throw Failure("source_reappeared") }
      } else { try directoryDestinationAbsent(scope, path: record.destinationPath) }
      for (path, identity) in [(record.sourcePath, namespace.sourceParentIdentity),
                               (record.destinationPath, namespace.destinationParentIdentity)] {
        let parent = try Parent(scope: scope, components: WorkspaceFileScope.relativeComponents(path))
        guard parent.identity == identity else { throw Failure("parent_changed") }
        if let session { _ = try verifyParent(session, path: path) }
      }
      var artifactRevisions: [String: String] = [:]
      for entry in record.entries {
        let path = namespace.moved ? entry.destinationPath : entry.path
        let parent = try Parent(scope: scope, components: components(path))
        guard parent.identity == entry.parentIdentity else { throw Failure("parent_changed") }
        if let session { _ = try verifyParent(session, path: path) }
        let snapshot = try read(scope, path: path)
        let revision = entry.writeRevision ?? entry.expectedRevision
        guard snapshot.revision == revision, snapshot.identity == Self.identity(revision),
              snapshot.bytes == (entry.writeRevision == nil ? entry.original : entry.replacement),
              matchesMetadata(snapshot, entry: entry) else { throw Failure("file_conflict") }
        if let originalArtifact = entry.artifactPath {
          let path = namespace.moved ? mapDirectoryPath(originalArtifact, source: record.sourcePath,
                                                        destination: record.destinationPath) : originalArtifact
          if let expected = entry.displacedRevision ?? entry.stagedRevision {
            let artifact = try read(scope, path: path, artifact: true)
            guard artifact.revision == expected, artifact.identity == Self.identity(expected),
                  artifact.bytes == (entry.displacedRevision == nil ? entry.replacement : entry.original),
                  matchesMetadata(artifact, entry: entry) else { throw Failure("artifact_changed") }
            artifactRevisions[path] = artifact.revision
          } else {
            guard try pathAbsent(scope, path: path, artifact: true) else { throw Failure("artifact_changed") }
          }
        }
      }
      let actual = try inspectDirectory(scope, source: activeRoot, artifacts: artifactRevisions)
      guard actual.count == namespace.members.count else { throw Failure("directory_tree_changed") }
      let actualByPath = Dictionary(uniqueKeysWithValues: actual.map { ($0.path, $0) })
      for member in namespace.members {
        let path = namespace.moved ? mapDirectoryPath(member.path, source: record.sourcePath,
                                                     destination: record.destinationPath) : member.path
        guard let current = actualByPath[path], current.kind == member.kind else { throw Failure("directory_tree_changed") }
        if member.kind == "directory" {
          guard current.identity == member.identity else { throw Failure("directory_tree_changed") }
        } else {
          let entry = record.entries.first { $0.path == member.path }
          let revision = entry?.writeRevision ?? member.revision
          guard current.revision == revision, current.identity == Self.identity(revision) else { throw Failure("directory_tree_changed") }
        }
      }
      // Project paths back to the original namespace, but retain every member
      // and every outside dependency. Never exempt the whole moved subtree.
      _ = try catalog(scope)
      let copies = record.recoveries.filter { $0.state == "applied" }.map(\.path)
      guard try dependencyDigest(scope, excluding: Set(record.entries.map(\.path) + copies),
                                 directoryRecord: record) == record.catalogDigest else { throw Failure("catalog_changed") }
      if let session {
        for asset in session.assets {
          let path = namespace.moved ? mapDirectoryPath(asset.path, source: record.sourcePath,
                                                       destination: record.destinationPath) : asset.path
          let parts = try WorkspaceFileScope.relativeComponents(path)
          let parent = try scope.parentDescriptor(parts); defer { close(parent) }
          var info = stat()
          guard fstatat(parent, parts.last!, &info, AT_SYMLINK_NOFOLLOW) == 0,
                WorkspaceFileScope.revision(info) == asset.revision else { throw Failure("asset_changed") }
        }
      }
      try scope.verifyRootLocation()
    } catch { observeConsistencyConflict(record); throw error }
  }

  private func executeDirectory(root: URL, record: Record, token: String?) throws -> [String: Any] {
    guard !record.cancelled else { return result(record) }
    guard let session = sessions[record.transactionId], token == session.token else {
      try reconcileDirectory(record, scope: try authorizedScope(root, record: record))
      record.code = "new_preview_required"; return result(record)
    }
    do {
      _ = try authorizedScope(root, record: record)
      guard let namespace = record.namespace, !namespace.intent, !namespace.moved,
            record.entries.allSatisfy({ $0.intent == nil && $0.state == "pending" }) else {
        throw Failure("new_preview_required")
      }
      try validateDirectoryReadSet(record, scope: session.scope, session: session)
      try checkPlanCapacity(record, scope: session.scope, context: "execute")
      for index in record.entries.indices where record.entries[index].original != record.entries[index].replacement {
        try writeEntry(record, index: index, session: session)
      }
      try moveDirectory(record, session: session)
      try validateDirectoryReadSet(record, scope: session.scope, session: session)
      for index in record.entries.indices {
        record.entries[index].actualPath = record.entries[index].destinationPath
        record.entries[index].actualRevision = record.entries[index].writeRevision ?? record.entries[index].expectedRevision
        record.entries[index].state = "applied"
      }
      record.namespace?.verified = true; record.namespace?.observedPath = record.destinationPath
      record.completionVerified = true; record.phase = "completed"; record.code = nil
      try point("beforeDirectoryCompletion"); try save(record)
      sessions.removeValue(forKey: record.transactionId)
    } catch {
      let failure = code(error)
      revokeUnpersisted(record)
      if let durable = try? load(record.transactionId) {
        do { try reconcileDirectory(durable, scope: session.scope) } catch { markUnverifiable(durable) }
        durable.code = failure
        try? save(durable)
        return result(durable)
      }
      markUnverifiable(record); record.code = failure
    }
    return result(record)
  }

  private func moveDirectory(_ record: Record, session: Session) throws {
    let scope = session.scope
    let coordinator = NSFileCoordinator()
    try coordinate(scope, path: record.sourcePath, destination: record.destinationPath,
                   coordinator: coordinator, directory: true) {
      try validateDirectoryReadSet(record, scope: scope, session: session)
      let sourceParent = try verifyParent(session, path: record.sourcePath)
      let targetParent = try verifyParent(session, path: record.destinationPath)
      let source = try WorkspaceFileScope.relativeComponents(record.sourcePath).last!
      let destination = try WorkspaceFileScope.relativeComponents(record.destinationPath).last!
      try point("beforeDirectoryMoveIntent")
      record.phase = "moving"; record.namespace?.intent = true; record.namespace?.verified = false
      try save(record); try point("afterDirectoryMoveIntent")
      try checkPlanCapacity(record, scope: scope, context: "directoryMove")
      try validateDirectoryReadSet(record, scope: scope, session: session)
      try directoryDestinationAbsent(scope, path: record.destinationPath)
      _ = try verifyParent(session, path: record.sourcePath); _ = try verifyParent(session, path: record.destinationPath)
      let sourceURL = scope.rootURL.appendingPathComponent(record.sourcePath, isDirectory: true)
      let targetURL = scope.rootURL.appendingPathComponent(record.destinationPath, isDirectory: true)
      coordinator.item(at: sourceURL, willMoveTo: targetURL)
      try point("beforeDirectoryExclusiveRename")
      guard renameatx_np(sourceParent.descriptor, source, targetParent.descriptor, destination, UInt32(RENAME_EXCL)) == 0 else {
        throw Failure("exclusive_directory_move_failed")
      }
      coordinator.item(at: sourceURL, didMoveTo: targetURL)
      record.namespace?.moved = true
      record.namespace?.observedPath = record.destinationPath
      try point("afterDirectoryRename")
      try validateDirectoryReadSet(record, scope: scope, session: session)
      let movedFD = try scope.directoryDescriptor(WorkspaceTextScope.textComponents(record.destinationPath, directory: true))
      defer { close(movedFD) }
      try syncDescriptor(movedFD, operation: "DirectoryMoveRootSync")
      try syncDescriptor(sourceParent.descriptor, operation: "DirectoryMoveSourceParentSync")
      try syncDescriptor(targetParent.descriptor, operation: "DirectoryMoveDestinationParentSync")
      try validateDirectoryReadSet(record, scope: scope, session: session)
      record.namespace?.synced = true; record.namespace?.intent = false
      record.namespace?.verified = true
      try point("beforeDirectoryMoveReceipt"); try save(record); try point("afterDirectoryMoveReceipt")
    }
  }

  /// Observation only with respect to the workspace. Missing swap/move receipts
  /// never grant replay or synthesize fsync/completion proof. Recovery remains
  /// explicit original-text copies, not a reverse directory rename.
  private func reconcileDirectory(_ record: Record, scope: WorkspaceTextScope) throws {
    guard try scopeIdentity(scope) == record.rootIdentity else { markUnverifiable(record); throw Failure("scope_changed") }
    if record.cancelled { record.phase = "cancelled"; try save(record); return }
    guard let namespace = record.namespace else { throw Failure("journal_invalid") }
    record.namespace?.verified = false; record.namespace?.observedPath = nil
    var locations: [String] = []
    for path in [record.sourcePath, record.destinationPath] {
      if let fd = try? scope.directoryDescriptor(WorkspaceTextScope.textComponents(path, directory: true)) {
        var info = stat()
        if fstat(fd, &info) == 0, Self.identity(info) == namespace.identity { locations.append(path) }
        close(fd)
      }
    }
    if locations.count == 1 { record.namespace?.observedPath = locations[0] }
    // A rename with an unflushed receipt may be observable, but is not durable
    // completion evidence. Retain intent and require explicit recovery/new plan.
    if namespace.intent || record.entries.contains(where: { $0.intent != nil }) ||
       locations != [namespace.moved ? record.destinationPath : record.sourcePath] {
      revokeUnpersisted(record)
      for index in record.entries.indices { record.entries[index].state = "uncertain"; record.entries[index].actualPath = nil; record.entries[index].actualRevision = nil; record.entries[index].artifactState = "uncertain" }
      record.phase = hasEvidenceOfMutation(record) ? "partial" : "blocked"
      record.code = "directory_reconciliation_required"
      reconcileRecoveries(record, scope: scope); try save(record); return
    }
    do {
      reconcileRecoveries(record, scope: scope)
      try validateDirectoryReadSet(record, scope: scope)
      record.namespace?.verified = true
      for index in record.entries.indices {
        let entry = record.entries[index]
        record.entries[index].actualPath = namespace.moved ? entry.destinationPath : entry.path
        record.entries[index].actualRevision = entry.writeRevision ?? entry.expectedRevision
        record.entries[index].state = namespace.moved || entry.writeRevision != nil ? "applied" : "pending"
      }
      if namespace.moved {
        record.phase = namespace.synced && record.completionVerified ? "completed" : "partial"
        if record.phase != "completed" { record.code = "completion_unverified" }
      } else { record.phase = hasEvidenceOfMutation(record) ? "partial" : "prepared" }
    } catch {
      revokeUnpersisted(record)
      for index in record.entries.indices {
        record.entries[index].state = "uncertain"; record.entries[index].actualPath = nil
        record.entries[index].actualRevision = nil; record.entries[index].artifactState = "uncertain"
      }
      record.namespace?.verified = false
      record.phase = hasEvidenceOfMutation(record) ? "partial" : "blocked"; record.code = code(error)
    }
    try save(record)
  }

  // MARK: - v3 bounded batch, one global text plan and per-root move receipts

  /// Each path is projected once against the immutable original root list. A
  /// partial batch uses only durable/in-flight moved bits, never a chained map.
  private func batchPath(_ path: String, record: Record, inverse: Bool = false, final: Bool = false) -> String {
    for root in record.namespaces ?? [] where final || root.moved {
      let source = inverse ? root.destinationPath : root.sourcePath
      let destination = inverse ? root.sourcePath : root.destinationPath
      if path.utf8.elementsEqual(source.utf8) { return destination }
      if root.kind == "directory", path.utf8.starts(with: (source + "/").utf8) {
        return destination + String(decoding: path.utf8.dropFirst(source.utf8.count), as: UTF8.self)
      }
    }
    return path
  }

  private func artifactLocation(_ path: String, record: Record) -> String {
    if record.version == 3 { return batchPath(path, record: record) }
    return record.namespace?.moved == true ? mapDirectoryPath(path, source: record.sourcePath, destination: record.destinationPath) : path
  }

  private func validateBatchManifest(_ record: Record) throws {
    guard record.namespace == nil, let roots = record.namespaces, (2...8).contains(roots.count),
          record.sourcePath == roots[0].sourcePath, record.destinationPath == roots[0].destinationPath,
          roots.map(\.sourcePath) == roots.map(\.sourcePath).sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }),
          roots.reduce(0, { $0 + $1.members.count }) <= 256,
          roots.flatMap(\.members).filter({ $0.kind == "directory" }).count <= 64 else { throw Failure("invalid_batch_plan") }
    func folded(_ path: String) -> String { path.precomposedStringWithCanonicalMapping.lowercased() }
    let targetParents = try roots.map { try WorkspaceFileScope.relativeComponents($0.destinationPath).dropLast().joined(separator: "/") }
    guard Set(targetParents).count == 1 else { throw Failure("batch_target_mismatch") }
    var sources = Set<String>(); var targets = Set<String>(); var allMembers = Set<String>(); var notes = Set<String>()
    for root in roots {
      try directoryPaths(root.sourcePath, root.destinationPath)
      let sourceParts = try WorkspaceFileScope.relativeComponents(root.sourcePath)
      let targetParts = try WorkspaceFileScope.relativeComponents(root.destinationPath)
      guard ["note", "directory"].contains(root.kind), !sourceParts.contains(where: { $0.hasPrefix(".") }),
            !targetParts.contains(where: { $0.hasPrefix(".") }),
            sourceParts.last!.utf8.elementsEqual(targetParts.last!.utf8),
            sources.insert(folded(root.sourcePath)).inserted, targets.insert(folded(root.destinationPath)).inserted,
            !root.members.isEmpty, !root.synced || root.moved,
            let first = root.members.first(where: { $0.path.utf8.elementsEqual(root.sourcePath.utf8) }),
            first.kind == root.kind, first.identity == root.identity,
            root.kind == "directory" || root.members.count == 1 else { throw Failure("invalid_batch_plan") }
      for member in root.members {
        let parts = try WorkspaceFileScope.relativeComponents(member.path)
        guard !parts.contains(where: { $0.hasPrefix(".") }), allMembers.insert(member.path).inserted,
              member.path == root.sourcePath || (root.kind == "directory" && member.path.hasPrefix(root.sourcePath + "/")),
              ["directory", "note", "image"].contains(member.kind), member.identity == Self.identity(member.revision),
              member.revision.utf8.count <= 200 else { throw Failure("invalid_batch_plan") }
        _ = try WorkspaceFileScope.relativeComponents(batchPath(member.path, record: record, final: true))
        if member.kind == "note" { notes.insert(member.path) }
      }
    }
    for (index, root) in roots.enumerated() {
      let source = folded(root.sourcePath)
      for (otherIndex, other) in roots.enumerated() {
        let otherSource = folded(other.sourcePath); let target = folded(other.destinationPath)
        guard index == otherIndex || (!source.hasPrefix(otherSource + "/") && !otherSource.hasPrefix(source + "/")),
              target != source, !target.hasPrefix(source + "/"), !source.hasPrefix(target + "/") else {
          throw Failure("overlapping_batch_move")
        }
      }
    }
    let paths = Set(record.entries.map(\.path))
    guard notes.isSubset(of: paths), record.entries.count <= Self.maximumFiles else { throw Failure("batch_note_missing") }
    for entry in record.entries {
      let rootNote = roots.first { $0.kind == "note" && $0.sourcePath == entry.path }
      guard entry.destinationPath.utf8.elementsEqual(batchPath(entry.path, record: record, final: true).utf8),
            notes.contains(entry.path) || entry.original != entry.replacement,
            rootNote != nil || entry.parentIdentity == entry.destinationParentIdentity,
            rootNote != nil || entry.moveRevision == nil else { throw Failure("invalid_batch_plan") }
      if let rootNote {
        guard entry.expectedIdentity == rootNote.identity, entry.parentIdentity == rootNote.sourceParentIdentity,
              entry.destinationParentIdentity == rootNote.destinationParentIdentity else { throw Failure("invalid_batch_plan") }
      }
    }
    let insideArtifacts = record.entries.compactMap(\.artifactPath).filter { path in
      roots.contains { $0.kind == "directory" && path.hasPrefix($0.sourcePath + "/") }
    }
    guard allMembers.count + insideArtifacts.count <= 256,
          try JSONEncoder().encode(roots).count + insideArtifacts.reduce(0, { $0 + 3 * $1.utf8.count + 1024 }) + 16_384 <= 1024 * 1024 else {
      throw Failure("batch_tree_budget")
    }
  }

  private func prepareBatch(root: URL, id: String, arguments: [String: Any]) throws -> [String: Any] {
    guard try !exists(id) else { throw Failure("transaction_id_reused") }
    guard let rows = arguments["roots"] as? [[String: Any]], (2...8).contains(rows.count),
          let files = arguments["files"] as? [[String: Any]], files.count <= Self.maximumFiles else { throw Failure("invalid_batch_plan") }
    let scope = try WorkspaceTextScope(root); let rootIdentity = try scopeIdentity(scope)
    let journalPath = journalURL.resolvingSymlinksInPath().standardizedFileURL.path
    guard journalPath != scope.rootURL.path, !journalPath.hasPrefix(scope.rootURL.path + "/"),
          !scope.rootURL.path.hasPrefix(journalPath + "/") else { throw Failure("journal_scope_overlap") }
    var parents: [String: Parent] = [:]; var directories: [String: Parent] = [:]
    func pin(_ path: String) throws -> Parent {
      if let value = parents[path] { return value }
      let parts = try WorkspaceFileScope.relativeComponents(path); let key = parts.dropLast().joined(separator: "/")
      let value = try directories[key] ?? Parent(scope: scope, components: parts)
      directories[key] = value; parents[path] = value; return value
    }
    var roots: [BatchNamespace] = []
    for row in rows {
      guard let source = row["sourcePath"] as? String, let destination = row["destinationPath"] as? String,
            let kind = row["kind"] as? String, ["note", "directory"].contains(kind) else { throw Failure("invalid_batch_plan") }
      try directoryPaths(source, destination)
      let members: [TreeMember]
      if kind == "directory" {
        guard let tree = row["tree"] as? [String: Any], tree["complete"] as? Bool == true,
              tree["sourcePath"] as? String == source, tree["rootIdentity"] as? String == rootIdentity,
              let issues = tree["issues"] as? [[String: Any]], issues.isEmpty else { throw Failure("invalid_tree") }
        let expected = try treeMembers(tree["members"])
        members = try inspectDirectory(scope, source: source)
        guard members == expected, tree["sourceIdentity"] as? String == members.first(where: { $0.path == source })?.identity else {
          throw Failure("directory_tree_changed")
        }
      } else {
        guard row["tree"] == nil else { throw Failure("invalid_batch_plan") }
        _ = try components(source); _ = try components(destination)
        let snapshot = try read(scope, path: source)
        members = [TreeMember(path: source, kind: "note", revision: snapshot.revision, identity: snapshot.identity)]
      }
      guard let member = members.first(where: { $0.path == source }) else { throw Failure("invalid_tree") }
      try directoryDestinationAbsent(scope, path: destination)
      let sourceParent = try pin(source); let targetParent = try pin(destination)
      roots.append(BatchNamespace(sourcePath: source, destinationPath: destination, kind: kind, identity: member.identity,
        sourceParentIdentity: sourceParent.identity, destinationParentIdentity: targetParent.identity,
        members: members, observedPath: source, verified: true))
    }
    roots.sort { $0.sourcePath.utf8.lexicographicallyPrecedes($1.sourcePath.utf8) }
    let expectedCatalog = try metadata(arguments["catalog"]); let actualCatalog = try catalog(scope)
    func catalogRows(_ values: [Metadata]) -> [String] { values.map { "\($0.path)|\($0.revision)|\($0.isDirectory)|\($0.local)" }.sorted() }
    guard catalogRows(expectedCatalog) == catalogRows(actualCatalog) else { throw Failure("catalog_changed") }
    let assets = try metadata(arguments["assets"] ?? [[String: Any]](), assets: true)
    let record = Record(id: id, scope: scope, rootIdentity: rootIdentity, source: roots[0].sourcePath,
      destination: roots[0].destinationPath, digest: "", entries: [])
    record.version = 3; record.namespaces = roots
    let movedNotes = Set(roots.flatMap(\.members).filter { $0.kind == "note" }.map(\.path))
    var entries: [Entry] = []; var seen = Set<String>(); var bytes = 0
    for file in files {
      guard let path = file["path"] as? String, let to = file["destinationPath"] as? String,
            let revision = file["expectedRevision"] as? String,
            let original = file["expectedBytes"] as? FlutterStandardTypedData, original.elementSize == 1,
            let replacement = file["replacementBytes"] as? FlutterStandardTypedData, replacement.elementSize == 1,
            seen.insert(path).inserted, to.utf8.elementsEqual(batchPath(path, record: record, final: true).utf8),
            movedNotes.contains(path) || original.data != replacement.data,
            String(data: original.data, encoding: .utf8) != nil, String(data: replacement.data, encoding: .utf8) != nil else { throw Failure("invalid_batch_plan") }
      _ = try components(path); _ = try components(to)
      bytes += original.data.count + replacement.data.count
      guard bytes <= Self.maximumPayloadBytes else { throw Failure("payload_limit") }
      let parent = try pin(path)
      let noteRoot = roots.first { $0.kind == "note" && $0.sourcePath == path }
      let destinationParent: Parent
      if noteRoot != nil { destinationParent = try pin(to) }
      else { destinationParent = parent; parents[to] = parent }
      let snapshot = try read(scope, path: path)
      guard snapshot.revision == revision, snapshot.bytes == original.data,
            actualCatalog.contains(where: { $0.path == path && !$0.isDirectory && $0.revision == revision }) else { throw Failure("file_conflict") }
      let artifact = original.data == replacement.data ? nil :
        (Array(try components(path).dropLast()) + [".linefold-note-move-\(id)-\(entries.count).md"]).joined(separator: "/")
      entries.append(Entry(path: path, destinationPath: to, expectedRevision: revision, expectedIdentity: snapshot.identity,
        parentIdentity: parent.identity, destinationParentIdentity: destinationParent.identity,
        original: original.data, replacement: replacement.data, originalHash: Self.hash(original.data), replacementHash: Self.hash(replacement.data),
        permissions: snapshot.permissions, owner: snapshot.owner, group: snapshot.group, protectionClass: snapshot.protectionClass, provenance: snapshot.provenance,
        artifactPath: artifact, actualPath: path, actualRevision: revision))
    }
    // Construct the immutable digest only after the complete shared entry set is known.
    let fingerprint = try digest(actualCatalog, excluding: Set(entries.map(\.path)), assets: assets, scope: scope)
    let prepared = Record(id: id, scope: scope, rootIdentity: rootIdentity, source: roots[0].sourcePath,
      destination: roots[0].destinationPath, digest: fingerprint, entries: entries)
    prepared.version = 3; prepared.namespaces = roots
    try validateBatchManifest(prepared)
    for entry in entries {
      if let artifact = entry.artifactPath, try !pathAbsent(scope, path: artifact, artifact: true) { throw Failure("artifact_exists") }
    }
    let session = Session(scope: scope, parents: parents, assets: assets)
    try validateBatchReadSet(prepared, scope: scope, session: session)
    try checkPlanCapacity(prepared, scope: scope, context: "prepare")
    try point("beforePreparedJournal"); try save(prepared); sessions[id] = session
    try point("afterPreparedJournal")
    return result(prepared)
  }

  private func checkBatchParents(_ record: Record, scope: WorkspaceTextScope) throws {
    guard let roots = record.namespaces else { throw Failure("journal_invalid") }
    var paths: [(String, String)] = roots.flatMap { [($0.sourcePath, $0.sourceParentIdentity), ($0.destinationPath, $0.destinationParentIdentity)] }
    paths += record.entries.map { entry in
      let path = batchPath(entry.path, record: record)
      return (path, path == entry.path ? entry.parentIdentity : entry.destinationParentIdentity)
    }
    var devices = Set<Int32>()
    for (path, identity) in paths {
      let parent = try Parent(scope: scope, components: WorkspaceFileScope.relativeComponents(path))
      guard parent.identity == identity else { throw Failure("parent_changed") }
      try verifyParent(scope: scope, path: path, parent: parent)
      var info = stat(); guard fstat(parent.descriptor, &info) == 0 else { throw Failure("parent_unavailable") }
      let access = faccessat(parent.descriptor, ".", W_OK | X_OK, AT_EACCESS) == 0
      guard access && (parentAccessOverride?(path, access) ?? access) else { throw Failure("parent_not_writable") }
      devices.insert(parentDeviceOverride?(path, info.st_dev) ?? info.st_dev)
    }
    guard devices.count == 1 else { throw Failure("cross_volume_move") }
  }

  private func validateBatchReadSet(_ record: Record, scope: WorkspaceTextScope, session: Session? = nil) throws {
    do {
      try point("beforeSemanticScan")
      guard !record.consistencyConflict, let roots = record.namespaces,
            try scopeIdentity(scope) == record.rootIdentity else { throw Failure("dependency_conflict") }
      var artifactRevisions: [String: String] = [:]
      for entry in record.entries {
        let path = batchPath(entry.path, record: record)
        let parent = try Parent(scope: scope, components: components(path))
        let expectedParent = path == entry.path ? entry.parentIdentity : entry.destinationParentIdentity
        guard parent.identity == expectedParent else { throw Failure("parent_changed") }
        if let session { _ = try verifyParent(session, path: path) }
        let snapshot = try read(scope, path: path)
        let revision = entry.moveRevision ?? entry.writeRevision ?? entry.expectedRevision
        guard snapshot.revision == revision, snapshot.identity == Self.identity(revision),
              snapshot.bytes == (entry.writeRevision == nil ? entry.original : entry.replacement),
              matchesMetadata(snapshot, entry: entry) else { throw Failure("file_conflict") }
        if let originalArtifact = entry.artifactPath {
          let artifactPath = batchPath(originalArtifact, record: record)
          if let revision = entry.displacedRevision ?? entry.stagedRevision {
            let artifact = try read(scope, path: artifactPath, artifact: true)
            guard artifact.revision == revision, artifact.identity == Self.identity(revision),
                  artifact.bytes == (entry.displacedRevision == nil ? entry.replacement : entry.original),
                  matchesMetadata(artifact, entry: entry) else { throw Failure("artifact_changed") }
            artifactRevisions[artifactPath] = artifact.revision
          } else { guard try pathAbsent(scope, path: artifactPath, artifact: true) else { throw Failure("artifact_changed") } }
        }
      }
      for root in roots {
        if root.moved {
          guard try pathAbsent(scope, path: root.sourcePath, directory: root.kind == "directory") else { throw Failure("source_reappeared") }
        } else { try directoryDestinationAbsent(scope, path: root.destinationPath) }
        for (path, identity) in [(root.sourcePath, root.sourceParentIdentity), (root.destinationPath, root.destinationParentIdentity)] {
          let parent = try Parent(scope: scope, components: WorkspaceFileScope.relativeComponents(path))
          guard parent.identity == identity else { throw Failure("parent_changed") }
          if let session { _ = try verifyParent(session, path: path) }
        }
        if root.kind == "directory" {
          let actual = try inspectDirectory(scope, source: root.moved ? root.destinationPath : root.sourcePath, artifacts: artifactRevisions)
          guard actual.count == root.members.count else { throw Failure("directory_tree_changed") }
          let byPath = Dictionary(uniqueKeysWithValues: actual.map { ($0.path, $0) })
          for member in root.members {
            guard let current = byPath[batchPath(member.path, record: record)], current.kind == member.kind else { throw Failure("directory_tree_changed") }
            if member.kind == "directory" {
              guard current.identity == member.identity else { throw Failure("directory_tree_changed") }
            } else {
              let entry = record.entries.first { $0.path == member.path }
              let revision = entry?.moveRevision ?? entry?.writeRevision ?? member.revision
              guard current.revision == revision, current.identity == Self.identity(revision) else { throw Failure("directory_tree_changed") }
            }
          }
        }
      }
      _ = try catalog(scope)
      let copies = record.recoveries.filter { $0.state == "applied" }.map(\.path)
      guard try dependencyDigest(scope, excluding: Set(record.entries.map(\.path) + copies), directoryRecord: record) == record.catalogDigest else { throw Failure("catalog_changed") }
      if let session {
        for asset in session.assets {
          let path = batchPath(asset.path, record: record); let parts = try WorkspaceFileScope.relativeComponents(path)
          let parent = try scope.parentDescriptor(parts); defer { close(parent) }; var info = stat()
          guard fstatat(parent, parts.last!, &info, AT_SYMLINK_NOFOLLOW) == 0,
                WorkspaceFileScope.revision(info) == asset.revision else { throw Failure("asset_changed") }
        }
      }
      try scope.verifyRootLocation()
    } catch { observeConsistencyConflict(record); throw error }
  }

  private func executeBatch(root: URL, record: Record, token: String?) throws -> [String: Any] {
    guard !record.cancelled else { return result(record) }
    guard let session = sessions[record.transactionId], token == session.token else {
      try reconcileBatch(record, scope: try authorizedScope(root, record: record)); record.code = "new_preview_required"; return result(record)
    }
    do {
      _ = try authorizedScope(root, record: record)
      guard record.namespaces?.allSatisfy({ !$0.intent && !$0.moved }) == true,
            record.entries.allSatisfy({ $0.intent == nil && $0.state == "pending" }) else { throw Failure("new_preview_required") }
      try validateBatchReadSet(record, scope: session.scope, session: session)
      try checkPlanCapacity(record, scope: session.scope, context: "execute")
      for index in record.entries.indices where record.entries[index].original != record.entries[index].replacement {
        try writeEntry(record, index: index, session: session)
      }
      for index in (record.namespaces ?? []).indices { try moveBatchRoot(record, index: index, session: session) }
      try validateBatchReadSet(record, scope: session.scope, session: session)
      for index in record.entries.indices {
        record.entries[index].actualPath = record.entries[index].destinationPath
        record.entries[index].actualRevision = record.entries[index].moveRevision ?? record.entries[index].writeRevision ?? record.entries[index].expectedRevision
        record.entries[index].state = "applied"
      }
      record.completionVerified = true; record.phase = "completed"; record.code = nil
      try point("beforeBatchCompletion"); try save(record); sessions.removeValue(forKey: record.transactionId)
    } catch {
      let failure = code(error); revokeUnpersisted(record)
      if let durable = try? load(record.transactionId) {
        do { try reconcileBatch(durable, scope: session.scope) } catch { markUnverifiable(durable) }
        durable.code = failure; try? save(durable); return result(durable)
      }
      markUnverifiable(record); record.code = failure
    }
    return result(record)
  }

  private func moveBatchRoot(_ record: Record, index: Int, session: Session) throws {
    guard let root = record.namespaces?[index] else { throw Failure("journal_invalid") }
    let scope = session.scope; let coordinator = NSFileCoordinator()
    try coordinate(scope, path: root.sourcePath, destination: root.destinationPath,
                   coordinator: coordinator, directory: root.kind == "directory") {
      try validateBatchReadSet(record, scope: scope, session: session)
      let sourceParent = try verifyParent(session, path: root.sourcePath)
      let targetParent = try verifyParent(session, path: root.destinationPath)
      let source = try WorkspaceFileScope.relativeComponents(root.sourcePath).last!
      let destination = try WorkspaceFileScope.relativeComponents(root.destinationPath).last!
      try point("beforeBatchMoveIntent:\(index)")
      record.phase = "moving"; record.namespaces?[index].intent = true; record.namespaces?[index].verified = false
      try save(record); try point("afterBatchMoveIntent:\(index)")
      try checkPlanCapacity(record, scope: scope, context: "batchMove")
      try validateBatchReadSet(record, scope: scope, session: session)
      try directoryDestinationAbsent(scope, path: root.destinationPath)
      _ = try verifyParent(session, path: root.sourcePath); _ = try verifyParent(session, path: root.destinationPath)
      let sourceURL = scope.rootURL.appendingPathComponent(root.sourcePath, isDirectory: root.kind == "directory")
      let targetURL = scope.rootURL.appendingPathComponent(root.destinationPath, isDirectory: root.kind == "directory")
      coordinator.item(at: sourceURL, willMoveTo: targetURL)
      try point("beforeBatchExclusiveRename:\(index)")
      guard renameatx_np(sourceParent.descriptor, source, targetParent.descriptor, destination, UInt32(RENAME_EXCL)) == 0 else { throw Failure("exclusive_batch_move_failed") }
      coordinator.item(at: sourceURL, didMoveTo: targetURL)
      record.namespaces?[index].moved = true; record.namespaces?[index].observedPath = root.destinationPath
      try point("afterBatchRename:\(index)")
      if root.kind == "note" {
        guard let entryIndex = record.entries.firstIndex(where: { $0.path == root.sourcePath }) else { throw Failure("journal_invalid") }
        let entry = record.entries[entryIndex]; let observed = try read(scope, path: root.destinationPath)
        guard observed.identity == Self.identity(entry.writeRevision ?? entry.expectedRevision),
              observed.bytes == (entry.writeRevision == nil ? entry.original : entry.replacement), matchesMetadata(observed, entry: entry) else { throw Failure("move_uncertain") }
        record.entries[entryIndex].moveRevision = observed.revision
        try syncObserved(scope, files: [(root.destinationPath, observed, false, targetParent)],
          parents: [(root.sourcePath, sourceParent), (root.destinationPath, targetParent)], absent: root.sourcePath, operation: "BatchNoteMove\(index)")
      } else {
        let fd = try scope.directoryDescriptor(WorkspaceTextScope.textComponents(root.destinationPath, directory: true)); defer { close(fd) }
        try syncDescriptor(fd, operation: "BatchDirectoryMoveRootSync\(index)")
        try syncDescriptor(sourceParent.descriptor, operation: "BatchDirectoryMoveSourceParentSync\(index)")
        try syncDescriptor(targetParent.descriptor, operation: "BatchDirectoryMoveDestinationParentSync\(index)")
      }
      try validateBatchReadSet(record, scope: scope, session: session)
      record.namespaces?[index].synced = true; record.namespaces?[index].intent = false; record.namespaces?[index].verified = true
      try point("beforeBatchMoveReceipt:\(index)"); try save(record); try point("afterBatchMoveReceipt:\(index)")
    }
  }

  private func reconcileBatch(_ record: Record, scope: WorkspaceTextScope) throws {
    guard try scopeIdentity(scope) == record.rootIdentity else { markUnverifiable(record); throw Failure("scope_changed") }
    guard let roots = record.namespaces else { throw Failure("journal_invalid") }
    if record.cancelled { record.phase = "cancelled"; try save(record); return }
    var ambiguous = record.entries.contains { $0.intent != nil }
    for (index, root) in roots.enumerated() {
      record.namespaces?[index].verified = false; record.namespaces?[index].observedPath = nil
      var locations: [String] = []
      for path in [root.sourcePath, root.destinationPath] {
        if root.kind == "directory" {
          if let fd = try? scope.directoryDescriptor(WorkspaceTextScope.textComponents(path, directory: true)) {
            var info = stat(); if fstat(fd, &info) == 0, Self.identity(info) == root.identity { locations.append(path) }; close(fd)
          }
        } else if let entry = record.entries.first(where: { $0.path == root.sourcePath }),
                  let snapshot = try? read(scope, path: path),
                  snapshot.identity == Self.identity(entry.writeRevision ?? entry.expectedRevision),
                  snapshot.bytes == (entry.writeRevision == nil ? entry.original : entry.replacement), matchesMetadata(snapshot, entry: entry) {
          locations.append(path)
        }
      }
      if locations.count == 1 { record.namespaces?[index].observedPath = locations[0] }
      if root.intent || locations != [root.moved ? root.destinationPath : root.sourcePath] { ambiguous = true }
    }
    if ambiguous {
      revokeUnpersisted(record)
      for index in record.entries.indices {
        record.entries[index].state = "uncertain"; record.entries[index].actualPath = nil
        record.entries[index].actualRevision = nil; record.entries[index].artifactState = "uncertain"
      }
      record.phase = hasEvidenceOfMutation(record) ? "partial" : "blocked"; record.code = "batch_reconciliation_required"
      reconcileRecoveries(record, scope: scope); try save(record); return
    }
    do {
      reconcileRecoveries(record, scope: scope); try validateBatchReadSet(record, scope: scope)
      for index in roots.indices { record.namespaces?[index].verified = true }
      for index in record.entries.indices {
        let entry = record.entries[index]; let path = batchPath(entry.path, record: record)
        record.entries[index].actualPath = path; record.entries[index].actualRevision = entry.moveRevision ?? entry.writeRevision ?? entry.expectedRevision
        record.entries[index].state = path != entry.path || entry.writeRevision != nil ? "applied" : "pending"
      }
      if roots.allSatisfy({ $0.moved && $0.synced }), record.completionVerified { record.phase = "completed" }
      else { record.phase = hasEvidenceOfMutation(record) ? "partial" : "prepared" }
    } catch {
      revokeUnpersisted(record)
      for index in record.entries.indices {
        record.entries[index].state = "uncertain"; record.entries[index].actualPath = nil
        record.entries[index].actualRevision = nil; record.entries[index].artifactState = "uncertain"
      }
      for index in roots.indices { record.namespaces?[index].verified = false }
      record.phase = hasEvidenceOfMutation(record) ? "partial" : "blocked"; record.code = code(error)
    }
    try save(record)
  }

  // MARK: - Bounded, observation-only storage inventory

  private static var cleanupUnavailableCode: String {
    #if os(iOS)
    return "platform_recovery_surface_unverified"
    #else
    return "cleanup_not_implemented"
    #endif
  }

  private func unavailableStorage(_ reason: String) -> [String: Any] {
    var value: [String: Any] = [
      "observedComplete": false, "currentRootKnown": false,
      "records": [[String: Any]](), "cleanupSupported": false,
      "limits": ["records": maximumStoredRecords, "journalBytes": maximumStoredBytes,
                 "artifactReservedBytes": Self.maximumArtifactReservationBytes],
      "blockers": Array(Set([Self.cleanupUnavailableCode, "admission_not_evaluated", reason])).sorted()
    ]
    for key in ["globalJournalCount", "globalRecordSlotCount", "globalJournalBytes", "pendingCount",
                "pendingBytes", "invalidJournalCount", "unknownEntryCount", "unavailableCount",
                "artifactReservedBytes", "currentRootJournalBytes", "currentRootArtifactBytes",
                "currentRootArtifactAllocatedBytes", "artifactUnknownCount", "availableBudgetBytes"] {
      value[key] = NSNull()
    }
    return value
  }

  private final class StorageDirectoryPins {
    var nodes: [(descriptor: Int32, url: URL, snapshot: stat)] = []
    var missingChild: String?
    var descriptor: Int32? { missingChild == nil ? nodes.last?.descriptor : nil }
    deinit { for node in nodes { close(node.descriptor) } }
  }

  private func sameStorageMetadata(_ a: stat, _ b: stat) -> Bool {
    // Normal read atime changes are deliberately excluded. All namespace,
    // revision, ownership, permissions and allocation observations must agree.
    WorkspaceFileScope.revision(a) == WorkspaceFileScope.revision(b) &&
      a.st_mode == b.st_mode && a.st_nlink == b.st_nlink && a.st_uid == b.st_uid &&
      a.st_gid == b.st_gid && a.st_flags == b.st_flags && a.st_blocks == b.st_blocks
  }

  private func verifyStorageDirectory(_ pins: StorageDirectoryPins) throws {
    for node in pins.nodes {
      var current = stat()
      guard fstat(node.descriptor, &current) == 0, sameStorageMetadata(current, node.snapshot) else {
        throw Failure("journal_changed_during_observation")
      }
      do { try verifyDirectoryLocation(node.descriptor, url: node.url) }
      catch { throw Failure("journal_changed_during_observation") }
    }
    if let name = pins.missingChild, let parent = pins.nodes.last {
      var value = stat()
      guard fstatat(parent.descriptor, name, &value, AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT else {
        throw Failure("journal_changed_during_observation")
      }
    }
  }

  /// Does not create, chmod, fsync, mark backup exclusion or repair permissions.
  /// Only system/base ancestors may have aliases, just as in journalDescriptor;
  /// every app-owned suffix component is opened relative to a held no-follow fd.
  private func openExistingJournalDirectory() throws -> StorageDirectoryPins {
    var anchorURL = journalBaseURL
    var named = stat()
    while lstat(anchorURL.path, &named) != 0 {
      guard errno == ENOENT, anchorURL.path != "/" else { throw Failure("journal_unavailable") }
      anchorURL.deleteLastPathComponent()
    }
    guard named.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { throw Failure("journal_unavailable") }
    let suffix = Array(journalURL.pathComponents.dropFirst(anchorURL.pathComponents.count))
    guard !suffix.isEmpty, suffix.count <= WorkspaceFileScope.maximumPathDepth,
          suffix.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw Failure("journal_unavailable") }
    anchorURL = anchorURL.resolvingSymlinksInPath().standardizedFileURL
    let anchor = open(anchorURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard anchor >= 0 else { throw Failure("journal_unavailable") }
    let pins = StorageDirectoryPins()
    var info = stat()
    guard fstat(anchor, &info) == 0, info.st_flags & UInt32(SF_DATALESS) == 0 else {
      close(anchor); throw Failure("journal_unavailable")
    }
    pins.nodes.append((anchor, anchorURL, info))
    for (index, name) in suffix.enumerated() {
      try verifyStorageDirectory(pins)
      let parent = pins.nodes.last!
      if fstatat(parent.descriptor, name, &named, AT_SYMLINK_NOFOLLOW) != 0 {
        guard errno == ENOENT else { throw Failure("journal_unavailable") }
        pins.missingChild = name
        try verifyStorageDirectory(pins)
        return pins
      }
      guard named.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
            named.st_flags & UInt32(SF_DATALESS) == 0 else { throw Failure("journal_unavailable") }
      let child = openat(parent.descriptor, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      guard child >= 0 else { throw Failure("journal_unavailable") }
      guard fstat(child, &info) == 0, sameStorageMetadata(named, info) else {
        close(child); throw Failure("journal_changed_during_observation")
      }
      pins.nodes.append((child, parent.url.appendingPathComponent(name, isDirectory: true), info))
      guard info.st_uid == getuid(), index != suffix.count - 1 || info.st_mode & 0o777 == 0o700 else {
        throw Failure("journal_unavailable")
      }
      do { try requireEmptyACL(child) } catch { throw Failure("journal_unavailable") }
    }
    try verifyStorageDirectory(pins)
    return pins
  }

  private struct StorageEntry { let name: String; let metadata: stat? }

  private func storageEntries(_ pins: StorageDirectoryPins, deadline: UInt64) throws -> ([StorageEntry], Bool) {
    guard let fd = pins.descriptor else { return ([], true) }
    let duplicate = openat(fd, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard duplicate >= 0 else { throw Failure("journal_unavailable") }
    guard let stream = fdopendir(duplicate) else { close(duplicate); throw Failure("journal_unavailable") }
    defer { closedir(stream) }
    var entries: [StorageEntry] = []
    while true {
      guard DispatchTime.now().uptimeNanoseconds < deadline else { return (entries, false) }
      errno = 0
      guard let item = readdir(stream) else {
        guard errno == 0 else { throw Failure("journal_unavailable") }; break
      }
      let capacity = Int(item.pointee.d_namlen) + 1
      let name = withUnsafePointer(to: &item.pointee.d_name) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { String(validatingUTF8: $0) }
      }
      guard let name else { throw Failure("journal_unavailable") }
      if name == "." || name == ".." { continue }
      guard entries.count < 256 else { return (entries, false) }
      var info = stat()
      let metadata = fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0 ? info : nil
      entries.append(StorageEntry(name: name, metadata: metadata))
    }
    return (entries.sorted { $0.name < $1.name }, true)
  }

  private func readStorageRecord(_ item: StorageEntry, directory: Int32, id: String,
                                 remainingBytes: inout Int, deadline: UInt64) throws -> Record {
    guard let expected = item.metadata, expected.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
          expected.st_nlink == 1, expected.st_uid == getuid(), expected.st_mode & 0o777 == 0o600,
          expected.st_flags & UInt32(SF_DATALESS) == 0,
          inventoryDatalessOverride?("journal:" + item.name) != true else { throw Failure("journal_unavailable") }
    guard expected.st_size > 0, expected.st_size <= 48 * 1024 * 1024,
          expected.st_size <= remainingBytes else { throw Failure("journal_read_limit") }
    try point("inventoryBeforeJournalRead")
    let fd = openat(directory, item.name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    guard fd >= 0 else { throw Failure("journal_unavailable") }
    defer { close(fd) }
    var before = stat()
    guard fstat(fd, &before) == 0, sameStorageMetadata(before, expected) else {
      throw Failure("journal_changed_during_observation")
    }
    do { try requireEmptyACL(fd) } catch { throw Failure("journal_unavailable") }
    remainingBytes -= Int(expected.st_size)
    var data = Data(count: Int(expected.st_size))
    try data.withUnsafeMutableBytes { buffer in
      var offset = 0
      while offset < buffer.count {
        guard DispatchTime.now().uptimeNanoseconds < deadline else { throw Failure("journal_read_limit") }
        let count = Darwin.read(fd, buffer.baseAddress!.advanced(by: offset), min(64 * 1024, buffer.count - offset))
        if count < 0 && errno == EINTR { continue }
        guard count > 0 else { throw Failure("journal_changed_during_observation") }; offset += count
      }
    }
    try point("inventoryAfterJournalRead")
    var after = stat(); var named = stat()
    guard fstat(fd, &after) == 0, sameStorageMetadata(before, after),
          fstatat(directory, item.name, &named, AT_SYMLINK_NOFOLLOW) == 0,
          sameStorageMetadata(before, named) else { throw Failure("journal_changed_during_observation") }
    do {
      let record = try decodeRecord(data, id: id)
      guard record.created.isFinite, record.created >= 0, record.rootPath.hasPrefix("/"),
            record.rootPath.utf16.count <= 4096, !record.rootPath.contains("\0"),
            record.phase.utf8.count <= 128, (record.code?.utf8.count ?? 0) <= 128 else { throw Failure("journal_invalid") }
      return record
    } catch { throw Failure("journal_invalid") }
  }

  private struct ArtifactStorage {
    var bytes = 0; var allocated = 0; var count = 0; var missing = 0; var unknown = 0
    var blockers = Set<String>()
  }

  private func inspectArtifacts(_ record: Record, scope: WorkspaceTextScope, deadline: UInt64) -> ArtifactStorage {
    var result = ArtifactStorage()
    for entry in record.entries {
      guard let originalPath = entry.artifactPath else { continue }
      let path = artifactLocation(originalPath, record: record)
      result.count += 1
      do {
        guard DispatchTime.now().uptimeNanoseconds < deadline else { throw Failure("artifact_unavailable") }
        try scope.verifyRootLocation()
        let parts = try artifactComponents(path)
        let parent = try scope.parentDescriptor(parts); defer { close(parent) }
        var parentBefore = stat()
        guard fstat(parent, &parentBefore) == 0, Self.identity(parentBefore) == entry.parentIdentity,
              parentBefore.st_flags & UInt32(SF_DATALESS) == 0 else { throw Failure("artifact_unavailable") }
        inventoryArtifactObserver?(path)
        try point("inventoryBeforeArtifactStat")
        var info = stat()
        let exists = fstatat(parent, parts.last!, &info, AT_SYMLINK_NOFOLLOW) == 0
        let failure = errno
        let expectedRevision = entry.displacedRevision ?? entry.stagedRevision
        let expectedIdentity = entry.displacedRevision == nil ? entry.stagedIdentity : entry.expectedIdentity
        let expectedPresent = entry.intent != nil || entry.stagedIdentity != nil ||
          entry.writeRevision != nil || entry.moveRevision != nil || entry.artifactState != "pending"
        if !exists {
          guard failure == ENOENT else { throw Failure("artifact_unavailable") }
          if expectedPresent { throw Failure("artifact_missing") }
        } else {
          guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_nlink == 1,
                info.st_flags & UInt32(SF_DATALESS) == 0,
                inventoryDatalessOverride?("artifact:" + path) != true else { throw Failure("artifact_unavailable") }
          guard let revision = expectedRevision, let identity = expectedIdentity,
                WorkspaceFileScope.revision(info) == revision, Self.identity(info) == identity,
                UInt32(info.st_mode & 0o777) == entry.permissions, info.st_uid == entry.owner,
                info.st_gid == entry.group,
                info.st_size == (entry.displacedRevision == nil ? entry.replacement.count : entry.original.count),
                info.st_blocks >= 0, info.st_blocks <= Int64(Int.max / 512) else { throw Failure("artifact_changed") }
        }
        try point("inventoryAfterArtifactStat")
        var after = stat(); var parentAfter = stat()
        if exists {
          guard fstatat(parent, parts.last!, &after, AT_SYMLINK_NOFOLLOW) == 0,
                sameStorageMetadata(info, after) else { throw Failure("artifact_changed") }
        } else {
          guard fstatat(parent, parts.last!, &after, AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT else {
            throw Failure("artifact_changed")
          }
        }
        let currentParent = try scope.parentDescriptor(parts); defer { close(currentParent) }
        guard fstat(currentParent, &parentAfter) == 0, sameStorageMetadata(parentBefore, parentAfter) else {
          throw Failure("artifact_changed")
        }
        try scope.verifyRootLocation()
        if exists {
          let (allocated, overflow) = result.allocated.addingReportingOverflow(Int(info.st_blocks) * 512)
          guard !overflow else { throw Failure("artifact_unavailable") }
          result.bytes += Int(info.st_size); result.allocated = allocated
        }
      } catch {
        let reason = code(error)
        let stable = ["artifact_missing", "artifact_changed"].contains(reason) ? reason : "artifact_unavailable"
        result.unknown += 1
        if stable == "artifact_missing" { result.missing += 1 }
        result.blockers.insert(stable)
      }
    }
    return result
  }

  /// Observation only. No journalDescriptor/load/reconcile/save call is allowed
  /// on this path. Values describe bounded metadata observations, not content
  /// verification, a consistent filesystem snapshot or admission for a new move.
  private func inspectStorage(root: URL) throws -> [String: Any] {
    let deadline = DispatchTime.now().uptimeNanoseconds + 10_000_000_000
    var value = unavailableStorage("admission_not_evaluated")
    var blockers = Set([Self.cleanupUnavailableCode, "admission_not_evaluated"])
    let scope = try? WorkspaceTextScope(root)
    let rootIdentity = scope.flatMap { try? scopeIdentity($0) }
    var rootKnown = rootIdentity != nil
    if !rootKnown { blockers.insert("scope_unavailable") }
    try point("inventoryAfterRootOpen")
    let pins = try openExistingJournalDirectory()
    let (items, scanComplete) = try storageEntries(pins, deadline: deadline)
    try point("inventoryAfterDirectoryScan")
    var complete = scanComplete && rootKnown
    if !scanComplete { blockers.insert("journal_entry_limit") }
    var totalBytes = 0; var pendingBytes = 0; var pendingCount = 0; var slots = 0
    var valid = 0; var invalid = 0; var unknownEntries = 0; var unavailable = 0
    var reservation = 0; var rootJournalBytes = 0; var artifactBytes = 0; var artifactAllocated = 0; var artifactUnknown = 0
    var totalsKnown = scanComplete; var pendingKnown = scanComplete; var decodeComplete = scanComplete
    var membershipKnown = scanComplete; var reservationKnown = scanComplete; var allocationKnown = true
    var remainingBytes = min(Self.maximumJournalBytes, max(0, inventoryReadBudgetOverride ?? Self.maximumJournalBytes))
    var records: [[String: Any]] = []
    for item in items {
      let isJSON = item.name.hasSuffix(".json"); let isPending = item.name.hasSuffix(".pending")
      if isJSON { slots += 1 }
      if isPending { pendingCount += 1 }
      if !isJSON && !isPending { unknownEntries += 1; complete = false; blockers.insert("journal_unknown_entries") }
      guard let info = item.metadata, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
            info.st_size >= 0, info.st_size <= Int64(Int.max / 256),
            info.st_flags & UInt32(SF_DATALESS) == 0,
            inventoryDatalessOverride?("journal:" + item.name) != true else {
        totalsKnown = false; complete = false; unavailable += 1
        if isPending { pendingKnown = false }
        if isJSON { decodeComplete = false; membershipKnown = false; reservationKnown = false }
        blockers.insert("journal_unavailable"); continue
      }
      totalBytes += Int(info.st_size)
      if isPending { pendingBytes += Int(info.st_size) }
      guard isJSON else { continue }
      guard let id = try? transactionId(String(item.name.dropLast(5))), item.name == id + ".json" else {
        invalid += 1; unavailable += 1; complete = false; membershipKnown = false; reservationKnown = false
        blockers.insert("journal_invalid"); continue
      }
      guard valid < Self.maximumRecords, let directory = pins.descriptor else {
        decodeComplete = false; membershipKnown = false; reservationKnown = false; complete = false; unavailable += 1
        blockers.insert("journal_read_limit"); continue
      }
      let record: Record
      do { record = try readStorageRecord(item, directory: directory, id: id, remainingBytes: &remainingBytes, deadline: deadline) }
      catch {
        let reason = code(error)
        if reason == "journal_changed_during_observation" { throw error }
        unavailable += 1; complete = false; membershipKnown = false; reservationKnown = false
        if reason == "journal_invalid" { invalid += 1 } else { decodeComplete = false }
        blockers.insert(["journal_invalid", "journal_read_limit"].contains(reason) ? reason : "journal_unavailable")
        continue
      }
      valid += 1
      reservation += record.entries.reduce(0) { $0 + ($1.artifactPath == nil ? 0 : $1.original.count + $1.replacement.count) }
      guard let scope, let rootIdentity, record.rootPath == scope.rootURL.path,
            record.rootIdentity == rootIdentity else { continue }
      rootJournalBytes += Int(info.st_size)
      let artifacts = inspectArtifacts(record, scope: scope, deadline: deadline)
      artifactBytes += artifacts.bytes; artifactUnknown += artifacts.unknown
      let (allocated, allocationOverflow) = artifactAllocated.addingReportingOverflow(artifacts.allocated)
      if allocationOverflow { allocationKnown = false; complete = false; blockers.insert("artifact_unverified") }
      else { artifactAllocated = allocated }
      if artifacts.unknown > 0 { complete = false; blockers.insert("artifact_unverified") }
      var reasons = artifacts.blockers; reasons.insert(Self.cleanupUnavailableCode)
      if !["completed", "cancelled"].contains(record.phase) { reasons.insert("partial_unverified") }
      var row: [String: Any] = [
        "transactionId": record.transactionId, "sourcePath": record.sourcePath, "destinationPath": record.destinationPath,
        "entryCount": record.entries.count, "storedPhase": record.phase, "created": record.created,
        "journalBytes": Int(info.st_size), "historicalObservation": true, "cleanupSupported": false,
        "artifactCount": artifacts.count, "artifactMissingCount": artifacts.missing,
        "artifactUnknownCount": artifacts.unknown, "blockers": reasons.sorted()
      ]
      if record.version == 2 || record.version == 3 {
        row["version"] = record.version
        // Historical receipts only; inspection must never reconcile, save, or
        // turn these recorded flags into current namespace evidence.
        if record.version == 2 { row["namespace"] = result(record)["namespace"] }
        else { row["namespaces"] = result(record)["namespaces"] }
      }
      row["storedCode"] = record.code.map { $0 as Any } ?? NSNull()
      row["artifactBytes"] = artifacts.unknown == 0 ? artifacts.bytes as Any : NSNull()
      row["allocatedBytes"] = artifacts.unknown == 0 ? artifacts.allocated as Any : NSNull()
      records.append(row)
    }
    // Recheck every observed name and all pinned directory locations. A changed
    // private namespace invalidates the whole inventory rather than publishing a
    // prefix sum or historical bodies as a current global total.
    try point("inventoryBeforeFinalValidation")
    if let directory = pins.descriptor {
      for item in items {
        if let before = item.metadata {
          var after = stat()
          guard fstatat(directory, item.name, &after, AT_SYMLINK_NOFOLLOW) == 0,
                sameStorageMetadata(before, after) else { throw Failure("journal_changed_during_observation") }
        }
      }
    }
    try verifyStorageDirectory(pins)
    if let scope, let rootIdentity {
      if (try? scopeIdentity(scope)) != rootIdentity {
        rootKnown = false; complete = false; blockers.insert("scope_changed_during_observation")
        for index in records.indices {
          records[index]["artifactBytes"] = NSNull(); records[index]["allocatedBytes"] = NSNull()
          let count = records[index]["artifactCount"] as? Int ?? 0
          records[index]["artifactUnknownCount"] = count
          var reasons = Set(records[index]["blockers"] as? [String] ?? [])
          reasons.insert("scope_changed_during_observation"); records[index]["blockers"] = reasons.sorted()
        }
      }
    }
    if pendingCount > 0 { blockers.insert("journal_pending_remnants") }
    if slots >= maximumStoredRecords { blockers.insert("journal_record_limit") }
    if totalBytes >= maximumStoredBytes { blockers.insert("journal_byte_limit") }
    if reservationKnown && reservation >= Self.maximumArtifactReservationBytes { blockers.insert("artifact_reservation_limit") }
    value["observedComplete"] = complete; value["currentRootKnown"] = rootKnown
    value["globalJournalCount"] = decodeComplete ? valid as Any : NSNull()
    value["globalRecordSlotCount"] = scanComplete ? slots as Any : NSNull()
    value["globalJournalBytes"] = totalsKnown ? totalBytes as Any : NSNull()
    value["pendingCount"] = scanComplete ? pendingCount as Any : NSNull()
    value["pendingBytes"] = pendingKnown ? pendingBytes as Any : NSNull()
    value["invalidJournalCount"] = decodeComplete ? invalid as Any : NSNull()
    value["unknownEntryCount"] = scanComplete ? unknownEntries as Any : NSNull()
    value["unavailableCount"] = scanComplete ? unavailable as Any : NSNull()
    value["artifactReservedBytes"] = reservationKnown ? reservation as Any : NSNull()
    value["currentRootJournalBytes"] = rootKnown && membershipKnown ? rootJournalBytes as Any : NSNull()
    value["currentRootArtifactBytes"] = rootKnown && membershipKnown && artifactUnknown == 0 ? artifactBytes as Any : NSNull()
    value["currentRootArtifactAllocatedBytes"] = rootKnown && membershipKnown && artifactUnknown == 0 && allocationKnown ? artifactAllocated as Any : NSNull()
    value["artifactUnknownCount"] = rootKnown && membershipKnown ? artifactUnknown as Any : NSNull()
    value["availableBudgetBytes"] = totalsKnown ? max(0, maximumStoredBytes - totalBytes) as Any : NSNull()
    value["records"] = records; value["blockers"] = blockers.sorted()
    return value
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
