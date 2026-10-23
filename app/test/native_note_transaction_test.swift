import Foundation
import Darwin
import FlutterMacOS

// All tests exercise the production executor against synthetic, temporary local
// files. Nothing here opens a real vault, cloud-provider account, app journal or
// the clipboard. A passed Linux shell check is not native test execution.
private struct TestFailure: Error, CustomStringConvertible {
  let description: String
}

private func require(
  _ condition: @autoclosure () throws -> Bool, _ message: String,
  file: StaticString = #filePath, line: UInt = #line
) throws {
  guard try condition() else {
    throw TestFailure(description: "\(file):\(line): \(message)")
  }
}

private struct InjectedFailure: Error {
  let boundary: String
}

private func fixtureRelativePath(_ file: URL, under canonicalBase: URL) throws -> String {
  let baseComponents = canonicalBase.standardizedFileURL.pathComponents
  let components = file.standardizedFileURL.pathComponents
  try require(components.starts(with: baseComponents) && components.count > baseComponents.count,
              "Enumerated fixture file must remain under the canonical base")
  return components.dropFirst(baseComponents.count).joined(separator: "/")
}

private final class MovePresenter: NSObject, NSFilePresenter {
  private let lock = NSLock()
  private var location: URL
  let moved = DispatchSemaphore(value: 0)
  let presentedItemOperationQueue: OperationQueue = {
    let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1; return queue
  }()
  var presentedItemURL: URL? { lock.lock(); defer { lock.unlock() }; return location }
  init(url: URL) { location = url; super.init() }
  func presentedItemDidMove(to newURL: URL) {
    lock.lock(); location = newURL; lock.unlock(); moved.signal()
  }
}

private final class Fixture {
  let manager = FileManager.default
  let directory: URL
  let root: URL
  let journal: URL
  let outside: URL
  let source = "notes/Old.md"
  let destination = "archive/New.md"
  let incoming = "index.md"
  let unrelated = "unrelated.md"
  let originalSource = Data("\u{FEFF}# Café 原文 😀\r\n[image](../assets/image.png)\r\n".utf8)
  let replacementSource = Data("\u{FEFF}# Café 原文 😀\r\n[image](../assets/image.png)\r\nMoved\r\n".utf8)
  let originalIncoming = Data("# Index\r\n[Old](notes/Old.md#section \"title\")\r\n".utf8)
  let replacementIncoming = Data("# Index\r\n[Old](archive/New.md#section \"title\")\r\n".utf8)
  let originalUnrelated = Data("# Unrelated\nNo links.\n".utf8)

  init() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("linefold-note-transactions-\(UUID().uuidString)", isDirectory: true)
    root = directory.appendingPathComponent("vault", isDirectory: true)
    journal = directory.appendingPathComponent("private-journal", isDirectory: true)
    outside = directory.appendingPathComponent("outside", isDirectory: true)
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    try manager.createDirectory(at: journal, withIntermediateDirectories: true)
    try manager.createDirectory(at: outside, withIntermediateDirectories: true)
    try manager.createDirectory(at: url("archive"), withIntermediateDirectories: true)
    try write(source, originalSource)
    try write(incoming, originalIncoming)
    try write(unrelated, originalUnrelated)
    try write("assets/image.png", Data([0x89, 0x50, 0x4e, 0x47, 0, 0xff]))
  }

  deinit { try? manager.removeItem(at: directory) }

  func url(_ relative: String) -> URL { root.appendingPathComponent(relative) }

  func write(_ relative: String, _ bytes: Data, atomic: Bool = false) throws {
    let target = url(relative)
    try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try bytes.write(to: target, options: atomic ? .atomic : [])
  }

  func bytes(_ relative: String) throws -> Data { try Data(contentsOf: url(relative)) }

  func exists(_ relative: String) -> Bool {
    var value = stat()
    return lstat(url(relative).path, &value) == 0
  }

  func attributes(_ relative: String) throws -> stat {
    var value = stat()
    guard lstat(url(relative).path, &value) == 0 else {
      throw TestFailure(description: "Unable to stat synthetic file \(relative): \(errno)")
    }
    return value
  }

  func identity(_ relative: String) throws -> String {
    let value = try attributes(relative)
    return "\(value.st_dev):\(value.st_ino)"
  }

  func revision(_ relative: String) throws -> String {
    WorkspaceFileScope.revision(try attributes(relative))
  }

  func overwriteSameInode(_ relative: String, _ data: Data) throws {
    let before = try identity(relative)
    let handle = try FileHandle(forWritingTo: url(relative))
    defer { try? handle.close() }
    try handle.seek(toOffset: 0)
    try handle.write(contentsOf: data)
    try handle.truncate(atOffset: UInt64(data.count))
    try handle.synchronize()
    try require(try identity(relative) == before, "Test writer must preserve the inode")
  }

  func replaceKeepingMtime(_ relative: String, _ data: Data) throws {
    let before = try attributes(relative)
    try write(relative, data, atomic: true)
    let times = [before.st_atimespec, before.st_mtimespec]
    let result = times.withUnsafeBufferPointer {
      utimensat(AT_FDCWD, url(relative).path, $0.baseAddress!, 0)
    }
    try require(result == 0, "Test must restore the previous modification time")
    let after = try attributes(relative)
    try require(before.st_dev != after.st_dev || before.st_ino != after.st_ino,
                "Atomic fixture replacement must have a new identity")
    try require(before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec &&
                  before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
                "Replacement test must not rely on modification time changing")
  }

  func expectOriginals() throws {
    try require(try bytes(source) == originalSource, "Source changed before authorization/preflight completed")
    try require(try bytes(incoming) == originalIncoming, "Incoming-link note changed before preflight completed")
    try require(try bytes(unrelated) == originalUnrelated, "An unrelated note was modified")
    try require(!exists(destination), "An unapproved destination appeared")
  }

  func relativeFiles(under base: URL) throws -> [String] {
    // Foundation can return /private/var URLs when the supplied base used the
    // /var alias. Slice path components from the same canonical base, not raw
    // character offsets from a differently spelled URL.
    let canonicalBase = base.resolvingSymlinksInPath().standardizedFileURL
    guard let enumerator = manager.enumerator(at: canonicalBase, includingPropertiesForKeys: [.isRegularFileKey]) else {
      throw TestFailure(description: "Unable to inspect synthetic test directory")
    }
    var result: [String] = []
    for case let file as URL in enumerator {
      if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
        result.append(try fixtureRelativePath(file, under: canonicalBase))
      }
    }
    return result.sorted()
  }
}

private extension Fixture {
  func catalogRows() throws -> [[String: Any]] {
    let scope = try WorkspaceTextScope(root)
    var pending = [""]; var rows: [[String: Any]] = []
    while let directory = pending.popLast() {
      let listing = try scope.listDirectory(relativePath: directory)
      try require(listing["complete"] as? Bool == true, "Synthetic catalog must be complete")
      for row in listing["entries"] as! [[String: Any]] {
        rows.append(["path": row["relativePath"]!, "revision": row["revision"]!,
                     "isDirectory": row["isDirectory"]!, "local": row["local"]!])
        if row["isDirectory"] as? Bool == true { pending.append(row["relativePath"] as! String) }
      }
    }
    return rows
  }
  func request(id: String = UUID().uuidString) throws -> [String: Any] {
    return ["path": root.path, "transactionId": id, "sourcePath": source,
      "destinationPath": destination,
      "files": [
        ["path": source, "destinationPath": destination, "expectedRevision": try revision(source),
         "expectedBytes": FlutterStandardTypedData(bytes: originalSource),
         "replacementBytes": FlutterStandardTypedData(bytes: replacementSource)],
        ["path": incoming, "destinationPath": incoming, "expectedRevision": try revision(incoming),
         "expectedBytes": FlutterStandardTypedData(bytes: originalIncoming),
         "replacementBytes": FlutterStandardTypedData(bytes: replacementIncoming)]],
      "assets": [["path": "assets/image.png", "revision": try revision("assets/image.png")]],
      "catalog": try catalogRows()]
  }
  func invoke(_ executor: WorkspaceNoteTransaction, _ method: String,
              _ arguments: [String: Any]) throws -> [String: Any] {
    guard let result = executor.perform(method, arguments: arguments) as? [String: Any] else {
      throw TestFailure(description: "Native transaction must return a finite result dictionary")
    }
    return result
  }
  func prepare(_ executor: WorkspaceNoteTransaction, _ request: [String: Any]) throws -> [String: Any] {
    try invoke(executor, "prepareWorkspaceNoteMove", request)
  }
  func command(_ request: [String: Any], token: Any? = nil) -> [String: Any] {
    var result: [String: Any] = ["path": root.path, "transactionId": request["transactionId"]!]
    if let token { result["token"] = token }
    return result
  }
}

@main
struct NativeNoteTransactionAcceptance {
  static func main() throws {
    try run("relativePathProjection", relativePathProjection)
    try run("preflight", preflight)
    try run("journalFaultsAndBounds", journalFaultsAndBounds)
    try run("metadataProtection", metadataProtection)
    try run("successAndRestart", successAndRestart)
    try run("finalDependencyChanges", finalDependencyChanges)
    try run("lostSemanticReceipt", lostSemanticReceipt)
    try run("lostSemanticReceiptLiveToken", lostSemanticReceiptLiveToken)
    try run("executionFaults", executionFaults)
    try run("writerConflicts", writerConflicts)
    try run("scopedRaces", scopedRaces)
    try run("offlineAndSymlinks", offlineAndSymlinks)
    try run("recoveryFaults", recoveryFaults)
    try run("durableSyncRepairs", durableSyncRepairs)
    try run("semanticScanFailures", semanticScanFailures)
    try run("capacityAndParentPreflight", capacityAndParentPreflight)
    try run("maximumPlanAndLowSpaceListing", maximumPlanAndLowSpaceListing)
    try run("journalDirectoryDurabilityAndPrivacy", journalDirectoryDurabilityAndPrivacy)
    try run("inheritedRecoveryACL", inheritedRecoveryACL)
    try run("recoveryIndependentOfOldReadSet", recoveryIndependentOfOldReadSet)
    try run("coordinatorRootAliases", coordinatorRootAliases)
    try run("presenterMoveNotifications", presenterMoveNotifications)
    try run("storageInventoryReadOnly", storageInventoryReadOnly)
    try run("storageInventoryMissingAndPermissions", storageInventoryMissingAndPermissions)
    try run("storageInventoryCountsAndBounds", storageInventoryCountsAndBounds)
    try run("storageInventoryScopeAndArtifacts", storageInventoryScopeAndArtifacts)
    try run("storageInventoryRaces", storageInventoryRaces)
    try run("directorySuccessAndRestart", directorySuccessAndRestart)
    try run("directoryEmptyAndImageOnly", directoryEmptyAndImageOnly)
    try run("directoryPreflight", directoryPreflight)
    try run("directoryFaultReceipts", directoryFaultReceipts)
    try run("directoryDependencyRaces", directoryDependencyRaces)
    try run("directoryMixedJournalCapacity", directoryMixedJournalCapacity)
    try run("directoryPresenterNotifications", directoryPresenterNotifications)
    print("PASS: synthetic atomic note transactions, receipts, recovery, races, bounds and privacy")
  }
  private static func run(_ name: String, _ body: () throws -> Void) throws {
    print("RUN: \(name)"); fflush(stdout)
    try body()
    print("PASS: \(name)"); fflush(stdout)
  }
  private static func relativePathProjection() throws {
    let f = try Fixture()
    let child = f.journal.appendingPathComponent("nested/原文.md")
    try f.manager.createDirectory(at: child.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("synthetic".utf8).write(to: child)
    let alias = f.directory.appendingPathComponent("journal-alias")
    try f.manager.createSymbolicLink(at: alias, withDestinationURL: f.journal)
    try require(try f.relativeFiles(under: f.journal) == ["nested/原文.md"], "Real base must yield exact relative components")
    try require(try f.relativeFiles(under: alias) == ["nested/原文.md"], "An alias base must yield the same relative components")
    let canonicalBase = f.journal.resolvingSymlinksInPath().standardizedFileURL
    let components = canonicalBase.pathComponents
    if components.starts(with: ["/", "private", "var"]) {
      let varAlias = URL(fileURLWithPath: "/var", isDirectory: true)
        .appendingPathComponent(components.dropFirst(3).joined(separator: "/"), isDirectory: true)
      try require(try f.relativeFiles(under: canonicalBase) == ["nested/原文.md"], "The /private/var base must project exactly")
      try require(try f.relativeFiles(under: varAlias) == ["nested/原文.md"], "The /var alias must project identically")
      print("PASS: system /var and /private/var fixture aliases"); fflush(stdout)
    }
    for sibling in ["private-journal-backup/note.md", "outside/note.md"] {
      let other = canonicalBase.deletingLastPathComponent().appendingPathComponent(sibling)
      var rejected = false
      do { _ = try fixtureRelativePath(other, under: canonicalBase) }
      catch is TestFailure { rejected = true }
      try require(rejected, "Sibling paths must not be treated as children, even when names share a prefix")
    }
  }
  private static func preflight() throws {
    do {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let request = try f.request(); let prepared = try f.prepare(executor, request)
      try require(prepared["phase"] as? String == "prepared", "Prepare should produce a journal, not write notes: \(prepared)")
      try require(prepared["token"] as? String != nil, "A prepared live plan needs an opaque token")
      try f.expectOriginals()
      let cancelled = try f.invoke(executor, "cancelPreparedWorkspaceNoteMove", f.command(request, token: prepared["token"]))
      try require(cancelled["phase"] as? String == "cancelled", "Cancellation must release the prepared grant")
      let attempted = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"]))
      try require(attempted["phase"] as? String == "cancelled", "Cancelled grant cannot execute")
      try f.expectOriginals()
      let files = try f.relativeFiles(under: f.journal)
      try require(files.count == 1, "Journal persists for review without deletion")
      let journal = try String(contentsOf: f.journal.appendingPathComponent(files[0]), encoding: .utf8)
      try require(!journal.contains(f.unrelated) && !journal.contains("assets/image.png"), "Journal must not persist unrelated catalog or assets")
    }
    do {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      var request = try f.request()
      var files = request["files"] as! [[String: Any]]
      files[0]["expectedBytes"] = FlutterStandardTypedData(bytes: Data("wrong".utf8))
      request["files"] = files
      let result = try f.prepare(executor, request)
      try require(result["phase"] as? String == "blocked", "Mismatched exact bytes must fail preflight")
      try f.expectOriginals()
    }
    do {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let request = try f.request()
      try f.write("new-inbound.md", Data("[Old](notes/Old.md)".utf8))
      let result = try f.prepare(executor, request)
      try require(result["code"] as? String == "catalog_changed", "New inbound candidates invalidate the catalog")
      try f.expectOriginals()
    }
    do {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      try f.write(f.destination, Data("Destination owner".utf8))
      let result = try f.prepare(executor, f.request())
      try require(result["code"] as? String == "destination_exists", "Occupied destination cannot prepare")
      try require(try f.bytes(f.destination) == Data("Destination owner".utf8), "Occupied destination must survive")
    }
    do {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      try f.manager.linkItem(at: f.url(f.source), to: f.outside.appendingPathComponent("hardlink.md"))
      let result = try f.prepare(executor, f.request())
      try require(result["phase"] as? String == "blocked", "Hardlinks may not broaden write authority")
      try f.expectOriginals()
    }
    do {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal, maximumStoredBytes: 1)
      let result = try f.prepare(executor, f.request())
      try require(result["code"] as? String == "journal_full", "A full journal blocks before any workspace mutation")
      try f.expectOriginals()
    }
  }
  private static func journalFaultsAndBounds() throws {
    for boundary in ["beforePreparedJournal", "afterPreparedJournal", "journalChunk", "beforeJournalSync", "afterJournalSync"] {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let request = try f.request(); var hit = false
      executor.fault = { point in if point == boundary && !hit { hit = true; throw InjectedFailure(boundary: point) } }
      _ = try f.prepare(executor, request); executor.fault = nil
      try require(hit, "Journal fault hook must run: \(boundary)")
      try f.expectOriginals()
      let files = try f.relativeFiles(under: f.journal)
      try require(files.count <= 1, "A fault cannot proliferate unbounded journal files")
    }
    do {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal, maximumStoredRecords: 1)
      let first = try f.request(); _ = try f.prepare(executor, first)
      let second = try f.request(); let result = try f.prepare(executor, second)
      try require(result["code"] as? String == "journal_full", "Unfinished records cannot be silently pruned for space")
      try require(try f.relativeFiles(under: f.journal).filter { $0.hasSuffix(".json") }.count == 1, "Existing record remains retained")
      try f.expectOriginals()
    }
    do {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      var request = try f.request(); let files = request["files"] as! [[String: Any]]
      request["files"] = Array(repeating: files[0], count: 129)
      let result = try f.prepare(executor, request)
      try require(result["phase"] as? String == "blocked", "Affected-note bound is fail closed, not truncated")
      try f.expectOriginals()
    }
    do {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      var request = try f.request(); var files = request["files"] as! [[String: Any]]
      let tooLarge = FlutterStandardTypedData(bytes: Data(repeating: 65, count: 17 * 1024 * 1024))
      files[0]["expectedBytes"] = tooLarge; files[0]["replacementBytes"] = tooLarge; request["files"] = files
      let result = try f.prepare(executor, request)
      try require(result["code"] as? String == "payload_limit", "Combined before/after bytes have a strict 32 MiB bound")
      try f.expectOriginals()
    }
  }

  private static func metadataProtection() throws {
    for permissions in [mode_t(0o640), mode_t(0o644)] {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      try require(chmod(f.url(f.source).path, permissions) == 0, "Fixture mode must be set")
      try require(chmod(f.url(f.incoming).path, permissions) == 0, "Fixture inbound mode must be set")
      let before = try f.attributes(f.source)
      let request = try f.request(); let prepared = try f.prepare(executor, request)
      let result = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"]))
      try require(result["phase"] as? String == "completed", "Plain POSIX modes remain supported: \(result)")
      let after = try f.attributes(f.destination)
      try require(after.st_mode & 0o777 == permissions && after.st_uid == before.st_uid && after.st_gid == before.st_gid,
                  "Atomic replacement must preserve mode, owner and group")
      try require(try f.attributes(f.incoming).st_mode & 0o777 == permissions, "Inbound replacement mode cannot silently become 0600")
    }
    do {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let data = Data("Synthetic metadata".utf8)
      let status = data.withUnsafeBytes { setxattr(f.url(f.source).path, "work.ianvs.synthetic", $0.baseAddress, $0.count, 0, 0) }
      try require(status == 0, "Synthetic xattr must be installed")
      let result = try f.prepare(executor, f.request())
      try require(result["code"] as? String == "unsupported_metadata", "Unsupported xattrs must block instead of silently disappearing")
      try f.expectOriginals()
    }
    do {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let chmod = Process(); chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
      chmod.arguments = ["+a", "everyone allow read", f.url(f.source).path]
      try chmod.run(); chmod.waitUntilExit()
      try require(chmod.terminationStatus == 0, "Synthetic ACL must be installed")
      let result = try f.prepare(executor, f.request())
      try require(result["code"] as? String == "unsupported_metadata", "Unsupported ACL must block instead of changing shared access")
      try f.expectOriginals()
    }
  }

  private static func successAndRestart() throws {
    let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
    let request = try f.request(); let prepared = try f.prepare(executor, request)
    let completed = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"]))
    try require(completed["phase"] as? String == "completed", "Atomic transaction must finish: \(completed)")
    try require(!f.exists(f.source), "Source must be exclusively moved after reference writes")
    try require(try f.bytes(f.destination) == f.replacementSource, "Moved body must preserve exact UTF-8/BOM/CRLF")
    try require(try f.bytes(f.incoming) == f.replacementIncoming, "Incoming reference must be replaced")
    try require(try f.bytes(f.unrelated) == f.originalUnrelated, "Unrelated note must stay unchanged")
    let entries = completed["entries"] as! [[String: Any]]
    try require(entries.allSatisfy { $0["state"] as? String == "applied" && $0["verified"] as? Bool == true }, "Only verified applied receipts complete")
    let artifacts = completed["retainedArtifacts"] as! [[String: Any]]
    try require(artifacts.count == 2, "Both displaced originals must be retained")
    for (index, artifact) in artifacts.enumerated() {
      let path = artifact["path"] as! String
      try require(!path.contains("Old") && !path.contains("index"), "Artifact leaf must not reveal the original basename")
      try require(artifact["verified"] as? Bool == true, "Retained artifact must be positively verified")
      try require(try f.bytes(path) == (index == 0 ? f.originalSource : f.originalIncoming), "Displaced version must remain exact")
    }
    let restarted = WorkspaceNoteTransaction(journalDirectory: f.journal)
    let reconciled = try f.invoke(restarted, "reconcileWorkspaceNoteMove", f.command(request))
    try require(reconciled["phase"] as? String == "completed", "Restart must verify current disk receipts")
    try require(reconciled["retryAllowed"] as? Bool == false, "Restart does not recreate a live mutation grant")
    var recoveryArgs = f.command(request); recoveryArgs["relativeDirectory"] = "archive"
    let recovery = try f.invoke(restarted, "recoverWorkspaceNoteMove", recoveryArgs)
    let copies = recovery["recoveryPaths"] as! [String]
    try require(copies.count == 2, "Explicit recovery creates complete originals as new copies")
    try require(recovery["phase"] as? String == "completed", "Verified authorized recovery copies must not manufacture a dependency conflict")
    for (index, path) in copies.enumerated() {
      try require(try f.bytes(path) == (index == 0 ? f.originalSource : f.originalIncoming), "Recovery copy must equal the original")
    }
    let again = try f.invoke(restarted, "recoverWorkspaceNoteMove", recoveryArgs)
    try require(again["recoveryPaths"] as! [String] == copies, "Repeated recovery cannot duplicate or overwrite copies")
    try require(try f.bytes(f.destination) == f.replacementSource, "Recovery may not roll back the moved note")
    // Source without outgoing edits still gets an applied final-move receipt.
    let unchanged = try Fixture(); let second = WorkspaceNoteTransaction(journalDirectory: unchanged.journal)
    var unchangedRequest = try unchanged.request()
    var files = unchangedRequest["files"] as! [[String: Any]]
    files[0]["replacementBytes"] = FlutterStandardTypedData(bytes: unchanged.originalSource)
    unchangedRequest["files"] = files
    let secondPrepared = try unchanged.prepare(second, unchangedRequest)
    let secondDone = try unchanged.invoke(second, "executeWorkspaceNoteMove", unchanged.command(unchangedRequest, token: secondPrepared["token"]))
    try require(secondDone["phase"] as? String == "completed", "Unmodified source must still complete the exclusive move")
    try require((secondDone["entries"] as! [[String: Any]]).allSatisfy { $0["verified"] as? Bool == true && $0["state"] as? String == "applied" }, "Unmodified moved note must be verified applied")
  }

  private static func finalDependencyChanges() throws {
    for boundary in ["afterMove", "afterMoveReceipt"] {
      for changeAsset in [false, true] {
        let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
        let request = try f.request(); let prepared = try f.prepare(executor, request)
        var fired = false
        executor.fault = { point in
          guard point == boundary, !fired else { return }
          fired = true
          if changeAsset { try f.write("assets/image.png", Data("Competing image revision".utf8)) }
          else { try f.write("late-inbound.md", Data("[Late inbound](notes/Old.md)".utf8)) }
        }
        let result = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"]))
        try require(fired && result["phase"] as? String != "completed", "A moved note does not prove reference read-set consistency")
        try require(result["retryAllowed"] as? Bool == false, "Dependency conflict cannot permit blind replay")
        try require(try f.bytes(f.destination) == f.replacementSource, "Actual completed move must remain recoverable without reversal")
        // Restore the visible catalog after an observed new-note conflict. The
        // journal must retain that conflict, not silently manufacture success.
        if !changeAsset { try FileManager.default.removeItem(at: f.url("late-inbound.md")) }
        let restarted = WorkspaceNoteTransaction(journalDirectory: f.journal)
        let observed = try f.invoke(restarted, "reconcileWorkspaceNoteMove", f.command(request))
        try require(observed["phase"] as? String != "completed", "Restart must preserve observed dependency conflict")
        try require(observed["retryAllowed"] as? Bool == false, "Restart cannot recreate execution consent")
        let source = (observed["entries"] as? [[String: Any]])?.first { $0["path"] as? String == f.source }
        try require(source?["actualPath"] as? String == f.destination && source?["state"] as? String == "applied",
                    "Dependency conflict must not misclassify an already moved inode as pending")
      }
    }
  }

  private static func lostSemanticReceipt() throws {
    let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
    let request = try f.request(); let prepared = try f.prepare(executor, request)
    var finalMoveReceipted = false
    executor.fault = { point in
      if point == "afterMoveReceipt" {
        finalMoveReceipted = true
        try f.write("late-inbound.md", Data("[Late](notes/Old.md)".utf8))
      }
      if finalMoveReceipted && point == "beforeJournalSync" { throw InjectedFailure(boundary: point) }
    }
    let failed = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"]))
    try require(finalMoveReceipted && failed["phase"] as? String != "completed", "Lost conflict journal cannot report completion")
    try FileManager.default.removeItem(at: f.url("late-inbound.md"))
    let restarted = WorkspaceNoteTransaction(journalDirectory: f.journal)
    let observed = try f.invoke(restarted, "reconcileWorkspaceNoteMove", f.command(request))
    try require(observed["phase"] as? String == "partial" && observed["code"] as? String == "completion_unverified",
                "Restart without final semantic proof must remain partial even if conflict metadata disappeared")
    try require(try f.bytes(f.destination) == f.replacementSource, "Unverified semantic completion cannot trigger another move or rollback")
  }

  private static func lostSemanticReceiptLiveToken() throws {
    let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
    let request = try f.request(); let prepared = try f.prepare(executor, request)
    var moved = false
    executor.fault = { point in
      if point == "afterMoveReceipt" { moved = true; try f.write("late-inbound.md", Data("[Late](notes/Old.md)".utf8)) }
      if moved && point == "beforeJournalSync" { throw InjectedFailure(boundary: point) }
    }
    let failed = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"]))
    try require(moved && failed["phase"] as? String != "completed", "Unsaved observed consistency conflict blocks completion")
    try FileManager.default.removeItem(at: f.url("late-inbound.md")); executor.fault = nil
    let observed = try f.invoke(executor, "reconcileWorkspaceNoteMove", f.command(request))
    try require(observed["phase"] as? String == "partial" && observed["code"] as? String == "dependency_conflict",
                "Same-process conflict evidence must survive repeated private journal save failures")
    let attempted = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"]))
    try require(attempted["phase"] as? String != "completed" && attempted["retryAllowed"] as? Bool == false,
                "A previously issued token cannot resurrect a rejected final read-set")
  }

  private static func executionFaults() throws {
    let boundaries = ["beforeStageIntent", "afterStageIntent", "beforeStageCreate", "afterStageCreate",
      "stageChunk", "beforeStageSync", "afterStageWrite", "beforeStageReceipt", "afterStageReceipt",
      "beforeWriteIntent", "afterWriteIntent", "beforeWrite", "swapRace", "beforeWriteSync",
      "afterWrite", "beforeWriteReceipt", "afterWriteReceipt", "beforeMoveIntent", "afterMoveIntent",
      "beforeMove", "beforeMoveSync", "afterMove", "beforeMoveReceipt", "afterMoveReceipt"]
    for boundary in boundaries {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let request = try f.request(); let prepared = try f.prepare(executor, request)
      var hit = false; var repairedFiles = 0; var repairedParents = 0
      executor.fault = { point in
        if point == "afterRepairMoveFileSync" { repairedFiles += 1 }
        if point == "afterRepairMoveParentSync" { repairedParents += 1 }
        if point == boundary && !hit { hit = true; throw InjectedFailure(boundary: boundary) }
      }
      let response = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"]))
      executor.fault = nil
      try require(hit, "Fault boundary must be reached: \(boundary), \(response)")
      for (path, original, replacement) in [(f.source, f.originalSource, f.replacementSource), (f.incoming, f.originalIncoming, f.replacementIncoming)] {
        if f.exists(path) {
          let body = try f.bytes(path)
          try require(body == original || body == replacement, "Crash boundary cannot leave a truncated user note: \(boundary)")
        }
      }
      if f.exists(f.destination) { try require(try f.bytes(f.destination) == f.replacementSource, "Final destination remains whole") }
      try require(try f.bytes(f.unrelated) == f.originalUnrelated, "Fault cannot modify unrelated bytes")
      let restart = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let reconciled = try f.invoke(restart, "reconcileWorkspaceNoteMove", f.command(request))
      try require(reconciled["retryAllowed"] as? Bool == false, "Restart only recovers, never recreates authority")
      if ["afterMove", "beforeMoveReceipt", "afterMoveReceipt", "beforeMoveSync"].contains(boundary) {
        if boundary != "afterMoveReceipt" {
          try require(repairedFiles >= 1 && repairedParents >= 2, "Lost move receipt requires actual successful sync repair, never reads alone")
        }
        try require(reconciled["phase"] as? String == "partial" && reconciled["code"] as? String == "completion_unverified",
                    "Lost final proof stays partial despite synced destination identity: \(boundary), \(reconciled)")
        try require(!f.exists(f.source) && (try f.bytes(f.destination)) == f.replacementSource,
                    "Reconciliation recognizes the actual move without repeating rename")
      }
      var recovery = f.command(request); recovery["relativeDirectory"] = ""
      let result = try f.invoke(restart, "recoverWorkspaceNoteMove", recovery)
      try require((result["recoveryPaths"] as? [String])?.count == 2, "Fault still permits exclusively created original copies: \(boundary)")
    }
    // A short staging write is harmless to original note bodies and cannot be
    // overwritten on retry merely because the target original is unchanged.
    let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
    var request = try f.request(); var files = request["files"] as! [[String: Any]]
    files[0]["replacementBytes"] = FlutterStandardTypedData(bytes: Data(repeating: 65, count: 200_000))
    request["files"] = files
    let prepared = try f.prepare(executor, request); var chunks = 0
    executor.fault = { point in if point == "stageChunk" { chunks += 1; if chunks == 2 { throw InjectedFailure(boundary: point) } } }
    let result = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"]))
    executor.fault = nil
    try f.expectOriginals()
    try require(result["retryAllowed"] as? Bool == false, "Partial stage must require recovery/new decision, not overwrite")
  }

  private static func writerConflicts() throws {
    for sameInode in [true, false] {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let request = try f.request(); let prepared = try f.prepare(executor, request)
      let competing = sameInode ? Data("Same inode concurrent writer".utf8) : f.originalSource
      if sameInode { try f.overwriteSameInode(f.source, competing) }
      else { try f.replaceKeepingMtime(f.source, competing) }
      let result = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"]))
      try require(result["phase"] as? String != "completed", "Identity OR byte changes must prevent execution")
      try require(try f.bytes(f.source) == competing, "Concurrent version cannot be replaced by stale baseline")
      try require(!f.exists(f.destination), "Conflicting source must not move")
    }
    do {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let request = try f.request(); let prepared = try f.prepare(executor, request)
      let rival = Data("Concurrent version in the unavoidable check-to-swap gap".utf8)
      var hit = false
      executor.fault = { point in
        if point == "swapRace" && !hit { hit = true; try f.write(f.source, rival, atomic: true) }
      }
      let result = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"]))
      executor.fault = nil
      try require(hit && result["phase"] as? String != "completed", "Uncoordinated swap race must be reported uncertain")
      let artifacts = result["retainedArtifacts"] as! [[String: Any]]
      try require(try artifacts.contains { try f.bytes($0["path"] as! String) == rival }, "Displaced concurrent version must survive, never be silently unlinked")
      try require(!f.exists(f.destination), "A conflicted swap cannot proceed to final rename")
    }
    do {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let request = try f.request(); let prepared = try f.prepare(executor, request)
      var hit = false
      executor.fault = { point in
        if point == "beforeWriteIntent" && !hit { hit = true; throw InjectedFailure(boundary: point) }
      }
      let stopped = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"]))
      executor.fault = nil
      try require(stopped["retryAllowed"] as? Bool == false, "Even a complete untouched stage cannot retain a failed execution grant")
      let done = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"]))
      try require(done["phase"] as? String != "completed" && done["code"] as? String == "new_preview_required",
                  "An old token cannot implicitly resume execution after a fault")
      try require(try f.bytes(f.source) == f.originalSource, "Revoked execution cannot modify the original")
      try require(!f.exists(f.destination), "Revoked execution cannot rename the note")
    }
    do {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let request = try f.request(); let prepared = try f.prepare(executor, request)
      try f.write("late.md", Data("[Old](notes/Old.md)".utf8))
      let result = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"]))
      try require(["catalog_changed", "dependency_conflict"].contains(result["code"] as? String ?? ""), "Late inbound-reference candidates invalidate preview read-set")
      try f.expectOriginals()
    }
  }

  private static func scopedRaces() throws {
    for boundary in ["beforeWrite", "afterWrite"] {
    for parentRace in [true, false] {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let request = try f.request(); let prepared = try f.prepare(executor, request)
      let from = parentRace ? f.url("notes") : f.root
      let to = f.outside.appendingPathComponent("displaced", isDirectory: true)
      var hit = false
      executor.fault = { point in
        if point == boundary && !hit {
          hit = true
          try f.manager.moveItem(at: from, to: to)
          try f.manager.createDirectory(at: from, withIntermediateDirectories: true)
          if parentRace { try f.write(f.source, Data("Replacement parent owner".utf8)) }
          else { try f.write(f.source, Data("Replacement root owner".utf8)) }
        }
      }
      let result = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"]))
      executor.fault = nil
      try require(hit && result["phase"] as? String != "completed", "External directory replacement must break authority")
      try require(try f.bytes(f.source) == Data((parentRace ? "Replacement parent owner" : "Replacement root owner").utf8), "Never retarget writes into a replacement scope/parent")
      let originalURL = parentRace ? to.appendingPathComponent("Old.md") : to.appendingPathComponent(f.source)
      try require(try Data(contentsOf: originalURL) == (boundary == "beforeWrite" ? f.originalSource : f.replacementSource), "External rename may retain a whole atomic version, never a truncated note")
    }
    }
    do {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let request = try f.request(); let prepared = try f.prepare(executor, request)
      let rival = Data("Exclusive destination owner".utf8)
      var hit = false
      executor.fault = { point in if point == "beforeMove" && !hit { hit = true; try f.write(f.destination, rival) } }
      let result = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"]))
      executor.fault = nil
      try require(hit && result["phase"] as? String != "completed", "Late destination collision must block rename")
      try require(try f.bytes(f.destination) == rival, "RENAME_EXCL may not overwrite destination owner")
      try require(f.exists(f.source), "Late collision must preserve source")
    }
  }

  private static func offlineAndSymlinks() throws {
    do {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let request = try f.request()
      try f.manager.moveItem(at: f.url(f.source), to: f.outside.appendingPathComponent("original.md"))
      try f.manager.createSymbolicLink(atPath: f.url(f.source).path, withDestinationPath: f.outside.appendingPathComponent("original.md").path)
      let result = try f.prepare(executor, request)
      try require(result["phase"] as? String == "blocked", "Symlink cannot authorize a note mutation")
      try require(try Data(contentsOf: f.outside.appendingPathComponent("original.md")) == f.originalSource, "External symlink target must remain unchanged")
    }
    do {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let request = try f.request()
      try f.write("notes/.Offline.md.icloud", Data())
      let result = try f.prepare(executor, request)
      try require(result["phase"] as? String == "blocked", "Synthetic offline placeholder blocks complete native preflight")
      try f.expectOriginals()
    }
    do {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      var request = try f.request(); request["destinationPath"] = "notes/old.md"
      let result = try f.prepare(executor, request)
      try require(result["phase"] as? String == "blocked", "Case-only move has no automatic safe protocol")
      try f.expectOriginals()
    }
  }

  private static func recoveryFaults() throws {
    for boundary in ["beforeRecoveryIntent", "afterRecoveryIntent", "afterRecoveryCreate", "recoveryChunk", "afterRecoveryWrite", "beforeRecoveryReceipt", "afterRecoveryReceipt"] {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let request = try f.request(); _ = try f.prepare(executor, request)
      var hit = false
      executor.fault = { point in if point == boundary && !hit { hit = true; throw InjectedFailure(boundary: point) } }
      var arguments = f.command(request); arguments["relativeDirectory"] = "archive"
      let result = try f.invoke(executor, "recoverWorkspaceNoteMove", arguments)
      executor.fault = nil
      try require(hit, "Recovery fault boundary must be reached: \(boundary)")
      try f.expectOriginals()
      let before = try f.relativeFiles(under: f.root)
      let snapshots = try before.map { (path: $0, identity: try f.identity($0), bytes: try f.bytes($0)) }
      _ = try f.invoke(executor, "recoverWorkspaceNoteMove", arguments)
      for item in snapshots {
        try require(try f.identity(item.path) == item.identity && f.bytes(item.path) == item.bytes,
                    "Retry may resume untouched pending copies but cannot replace any existing file")
      }
      let recovered = try f.relativeFiles(under: f.root).filter { ($0 as NSString).lastPathComponent.hasPrefix("Recovered-") }
      try require(recovered.count <= 2, "Recovery retry cannot duplicate an uncertain copy")
      for path in result["recoveryPaths"] as? [String] ?? [] {
        let bytes = try f.bytes(path)
        try require(bytes == f.originalSource || bytes == f.originalIncoming, "Only complete verified recovery paths may be reported")
      }
    }
  }

  private static func durableSyncRepairs() throws {
    for operation in ["Write", "Move"] {
      for target in ["FileSync", "ParentSync"] {
        let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
        let request = try f.request(); let prepared = try f.prepare(executor, request)
        var attempts = 0
        let fail: (String) throws -> Void = { point in
          if point == "before\(operation)\(target)" || point == "beforeRepair\(operation)\(target)" {
            attempts += 1; throw InjectedFailure(boundary: point)
          }
        }
        executor.fault = fail
        let failed = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"]))
        try require(attempts >= 2, "Both initial and repair sync must actually be attempted")
        try require(failed["phase"] as? String != "completed" && failed["retryAllowed"] as? Bool == false,
                    "Persistent \(operation) \(target) failure cannot become a durable receipt or retry grant")
        let restart = WorkspaceNoteTransaction(journalDirectory: f.journal); restart.fault = fail
        let observed = try f.invoke(restart, "reconcileWorkspaceNoteMove", f.command(request))
        try require(observed["phase"] as? String != "completed", "Page-cache observations on restart are not sync evidence")
        var syncedFiles = 0; var syncedParents = 0
        executor.fault = { point in
          if point == "afterRepair\(operation)FileSync" { syncedFiles += 1 }
          if point == "afterRepair\(operation)ParentSync" { syncedParents += 1 }
        }
        let repaired = try f.invoke(executor, "reconcileWorkspaceNoteMove", f.command(request))
        try require(syncedFiles >= (operation == "Write" ? 2 : 1) && syncedParents >= (operation == "Write" ? 1 : 2),
                    "Repair needs successful file/artifact and every affected parent fsync")
        if operation == "Move" {
          try require(repaired["phase"] as? String == "partial" && repaired["code"] as? String == "completion_unverified",
                      "Sync repair recognizes the move but cannot manufacture final semantic completion")
          try require(!f.exists(f.source) && (try f.bytes(f.destination)) == f.replacementSource, "Repair must not rename again")
        }
        try require(repaired["retryAllowed"] as? Bool == false, "Successful sync repair cannot revive a failed execution grant")
      }
    }
    // A renamed private receipt is not durable until its directory sync succeeds.
    for recovery in [false, true] {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let request = try f.request(); let prepared = try f.prepare(executor, request)
      var ready = false; var failed = false
      executor.fault = { point in
        if point == (recovery ? "afterRecoveryWrite" : "afterMoveReceipt") { ready = true }
        if ready && point == "beforeJournalReceiptDirectorySync" { failed = true }
        if failed && point.hasPrefix("beforeJournal") && point.hasSuffix("Sync") {
          throw InjectedFailure(boundary: point)
        }
      }
      var args = f.command(request, token: prepared["token"]); args["relativeDirectory"] = "archive"
      let result = try f.invoke(executor, recovery ? "recoverWorkspaceNoteMove" : "executeWorkspaceNoteMove", args)
      try require(failed && result["phase"] as? String != "completed", "Persistent private directory-sync failure cannot complete")
      if recovery { try require((result["recoveryPaths"] as? [String] ?? []).isEmpty, "Lost recovery receipt must not remain optimistically verified") }
      else {
        executor.fault = nil
        let observed = try f.invoke(executor, "reconcileWorkspaceNoteMove", f.command(request))
        try require(observed["phase"] as? String != "completed" && observed["retryAllowed"] as? Bool == false,
                    "Unsaved durability uncertainty must revoke the live grant even after IO recovers")
        let oldToken = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"]))
        try require(oldToken["phase"] as? String != "completed", "Old token cannot turn an unpersisted uncertainty into success")
      }
    }
  }

  private static func semanticScanFailures() throws {
    for scenario in ["noteStub", "assetStub", "scanError", "timeout"] {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let request = try f.request(); let prepared = try f.prepare(executor, request)
      var moved = false
      executor.fault = { point in
        if point == "afterMoveReceipt" {
          moved = true
          if scenario == "noteStub" { try f.write("notes/.Late.md.icloud", Data()) }
          if scenario == "assetStub" { try f.write("assets/.Late.png.icloud", Data()) }
          if scenario == "timeout" { executor.forceDependencyTimeout = true }
        }
        if moved && scenario == "scanError" && point == "beforeSemanticScan" { throw InjectedFailure(boundary: point) }
      }
      let result = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"]))
      try require(moved && result["phase"] as? String != "completed", "Any final semantic scan failure is sticky: \(scenario)")
      if scenario == "noteStub" { try FileManager.default.removeItem(at: f.url("notes/.Late.md.icloud")) }
      if scenario == "assetStub" { try FileManager.default.removeItem(at: f.url("assets/.Late.png.icloud")) }
      let restart = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let observed = try f.invoke(restart, "reconcileWorkspaceNoteMove", f.command(request))
      try require(observed["phase"] as? String == "partial" && observed["code"] as? String == "dependency_conflict",
                  "Removing a stub/error after restart cannot erase an observed final consistency failure")
    }
  }

  private static func capacityAndParentPreflight() throws {
    for context in ["prepare", "execute", "stageCreate", "journal", "journalDirectory", "recovery", "recoveryCreate"] {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let request = try f.request()
      let initial = try f.relativeFiles(under: f.root)
      let prepareFailure = ["prepare", "journal", "journalDirectory"].contains(context)
      let prepared: [String: Any]
      if prepareFailure { prepared = [:] } else { prepared = try f.prepare(executor, request) }
      var checked = false
      executor.availableBytesOverride = { name, _, available in
        if name == context { checked = true; return 0 }; return available
      }
      let response: [String: Any]
      if prepareFailure { response = try f.prepare(executor, request) }
      else if context.hasPrefix("recovery") {
        var args = f.command(request); args["relativeDirectory"] = "archive"
        response = try f.invoke(executor, "recoverWorkspaceNoteMove", args)
      } else { response = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"])) }
      try require(checked && response["phase"] as? String != "completed", "Injected low capacity must block \(context)")
      try f.expectOriginals()
      try require(try f.relativeFiles(under: f.root) == initial, "Capacity preflight must precede any stage or copy creation: \(context)")
    }
    do {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      var request = try f.request(); var files = request["files"] as! [[String: Any]]
      files[0]["replacementBytes"] = FlutterStandardTypedData(bytes: Data(repeating: 65, count: 16 * 1024 * 1024)); request["files"] = files
      executor.availableBytesOverride = { context, _, free in context == "prepare" ? min(free, 50 * 1024 * 1024) : free }
      let result = try f.prepare(executor, request)
      try require(result["code"] as? String == "insufficient_space", "Shared volume must aggregate stage + two base64 journal generations, not check each independently")
      try f.expectOriginals()
    }
    for late in [false, true] {
      for scenario in ["device", "permissions"] {
        let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
        let request = try f.request(); let prepared: [String: Any]
        if late { prepared = try f.prepare(executor, request) } else { prepared = [:] }
        if scenario == "device" { executor.parentDeviceOverride = { path, device in path == f.destination ? device ^ 1 : device } }
        else { executor.parentAccessOverride = { path, allowed in path == f.destination ? false : allowed } }
        let result: [String: Any]
        if late { result = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"])) }
        else { result = try f.prepare(executor, request) }
        try require(result["code"] as? String == (scenario == "device" ? "cross_volume_move" : "parent_not_writable"),
                    "Known unusable move parent must block before inbound rewrites")
        try f.expectOriginals()
        try require(try f.relativeFiles(under: f.root).allSatisfy { !$0.contains(".linefold-note-move-") }, "Preflight must precede hidden stage creation")
      }
    }
    do {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let request = try f.request(); let prepared = try f.prepare(executor, request)
      executor.availableBytesOverride = { context, _, free in context == "move" ? 0 : free }
      let result = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"]))
      try require(result["phase"] as? String == "partial" && !f.exists(f.destination), "Concurrent late exhaustion preserves partial journal, not false completion")
      try require(try f.bytes(f.source) == f.replacementSource, "Late capacity failure never truncates or rolls back notes")
    }
  }

  private static func maximumPlanAndLowSpaceListing() throws {
    do {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let original = Data("# Extra note\n".utf8); let replacement = Data("# Revised extra note\n".utf8)
      for index in 0..<126 { try f.write("extra/Note\(index).md", original) }
      var request = try f.request(); var files = request["files"] as! [[String: Any]]
      for index in 0..<126 {
        let path = "extra/Note\(index).md"
        files.append(["path": path, "destinationPath": path, "expectedRevision": try f.revision(path),
                      "expectedBytes": FlutterStandardTypedData(bytes: original),
                      "replacementBytes": FlutterStandardTypedData(bytes: replacement)])
      }
      request["files"] = files
      let prepared = try f.prepare(executor, request)
      try require(prepared["phase"] as? String == "prepared" && (prepared["entries"] as? [[String: Any]])?.count == 128,
                  "Legal 128-file plan must not open another 256 budget descriptors")
      try f.expectOriginals()
    }
    do {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let request = try f.request(); _ = try f.prepare(executor, request)
      executor.availableBytesOverride = { _, _, _ in 0 }
      let listed = try f.invoke(executor, "listWorkspaceNoteMoves", ["path": f.root.path])
      try require((listed["transactions"] as? [[String: Any]])?.count == 1 && listed["unavailableRecords"] as? Int == 0,
                  "Low free space blocks rewrites, not reading an existing private recovery manifest")
      try f.expectOriginals()
    }
  }

  private static func journalDirectoryDurabilityAndPrivacy() throws {
    do {
      let f = try Fixture(); let journal = f.directory.appendingPathComponent("new-private/nested-journal")
      let executor = WorkspaceNoteTransaction(journalDirectory: journal)
      let request = try f.request(); var failed = false
      executor.fault = { point in
        if point == "beforeJournalDirectoryParentSync" { failed = true; throw InjectedFailure(boundary: point) }
      }
      let response = try f.prepare(executor, request)
      try require(failed && response["phase"] as? String == "blocked", "Unsynced new ancestor name cannot authorize payload writes")
      try f.expectOriginals()
      var parentSyncs = 0; var childSyncs = 0
      executor.fault = { point in
        if point == "afterJournalDirectoryParentSync" { parentSyncs += 1 }
        if point == "afterJournalDirectoryChildSync" { childSyncs += 1 }
        if point == "journalChunk" { try require(parentSyncs >= 1 && childSyncs >= 1, "Directory durability must precede original payload") }
      }
      let retried = try f.prepare(executor, request)
      try require(retried["phase"] as? String == "prepared" && parentSyncs >= 2 && childSyncs >= 2,
                  "Existing directories left by a failed attempt must be re-synced, not presumed durable")
    }
    do {
      let f = try Fixture(); let chmod = Process()
      chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
      chmod.arguments = ["+a", "everyone allow read,readattr,readextattr,readsecurity,file_inherit,directory_inherit", f.journal.path]
      try chmod.run(); chmod.waitUntilExit()
      try require(chmod.terminationStatus == 0, "Synthetic inheritable ACL must be installed")
      let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let result = try f.prepare(executor, f.request())
      try require(result["code"] as? String == "private_journal_unavailable", "chmod 0700 is not enough to neutralize inherited ACL disclosure")
      try require(try FileManager.default.contentsOfDirectory(atPath: f.journal.path).isEmpty, "No original bytes may be persisted under unsafe private ACL")
      try f.expectOriginals()
    }
  }

  private static func inheritedRecoveryACL() throws {
    let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
    let request = try f.request(); _ = try f.prepare(executor, request)
    let chmod = Process(); chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
    chmod.arguments = ["+a", "everyone allow read,readattr,readextattr,readsecurity,file_inherit", f.url("archive").path]
    try chmod.run(); chmod.waitUntilExit()
    try require(chmod.terminationStatus == 0, "Synthetic recovery-parent inherited ACL must be installed")
    var args = f.command(request); args["relativeDirectory"] = "archive"
    let result = try f.invoke(executor, "recoverWorkspaceNoteMove", args)
    try require((result["recoveryPaths"] as? [String] ?? []).isEmpty, "Unsafe inherited ACL cannot produce a verified original copy")
    let copies = try f.relativeFiles(under: f.root).filter { ($0 as NSString).lastPathComponent.hasPrefix("Recovered-") }
    for copy in copies { try require(try f.bytes(copy).isEmpty, "Privacy must be checked before writing any original payload") }
    try f.expectOriginals()
  }

  private static func recoveryIndependentOfOldReadSet() throws {
    for scenario in ["missingParent", "unrelatedSymlink", "absentIntent"] {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let request = try f.request(); _ = try f.prepare(executor, request)
      if scenario == "missingParent" {
        try FileManager.default.moveItem(at: f.url("notes"), to: f.outside.appendingPathComponent("saved-notes"))
      } else if scenario == "unrelatedSymlink" {
        try FileManager.default.createSymbolicLink(at: f.url("unrelated-link"), withDestinationURL: f.outside)
      } else {
        executor.fault = { point in if point == "afterRecoveryIntent" { throw InjectedFailure(boundary: point) } }
      }
      var args = f.command(request); args["relativeDirectory"] = "archive"
      let first = try f.invoke(executor, "recoverWorkspaceNoteMove", args)
      let paths = (first["recoveryEntries"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String }
      let restart = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let recovered = try f.invoke(restart, "recoverWorkspaceNoteMove", args)
      let copies = recovered["recoveryPaths"] as? [String] ?? []
      try require(copies.count == 2 && Set(copies) == Set(paths), "Explicit recovery must use the same exclusive plan despite unavailable old read-set: \(scenario)")
      for copy in copies {
        let bytes = try f.bytes(copy)
        try require(bytes == f.originalSource || bytes == f.originalIncoming, "Recovery uses only verified private original payloads")
      }
      try require(recovered["phase"] as? String != "completed", "Copy recovery cannot assert the original move completed")
    }
  }

  private static func coordinatorRootAliases() throws {
    func accepts(_ executor: WorkspaceNoteTransaction, _ observed: URL,
                 _ scope: WorkspaceFileScope, _ relative: String, _ parent: Int32) -> Bool {
      do {
        try executor.verifyCoordinatedURL(observed, scope: scope, relativePath: relative, parentDescriptor: parent)
        return true
      } catch { return false }
    }
    do {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let initial = try WorkspaceTextScope(f.root)
      let alias = f.directory.appendingPathComponent("ancestor-alias", isDirectory: true)
      try f.manager.createSymbolicLink(at: alias, withDestinationURL: f.directory)
      var spellings = [initial.rootURL, alias.appendingPathComponent("vault", isDirectory: true)]
      let canonical = initial.rootURL.pathComponents
      if canonical.starts(with: ["/", "private", "var"]) {
        spellings.append(URL(fileURLWithPath: "/var", isDirectory: true)
          .appendingPathComponent(canonical.dropFirst(3).joined(separator: "/"), isDirectory: true))
      }
      for authorized in spellings {
        let scope = try WorkspaceTextScope(authorized)
        for path in [f.source, f.destination] {
          let parent = try scope.parentDescriptor(WorkspaceFileScope.relativeComponents(path)); defer { close(parent) }
          for callbackRoot in spellings {
            try require(accepts(executor, callbackRoot.appendingPathComponent(path), scope, path, parent),
                        "Existing and missing leaves permit both directions of verified root ancestor aliases")
          }
        }
      }
      let scope = try WorkspaceTextScope(f.root)
      let parent = try scope.parentDescriptor(WorkspaceFileScope.relativeComponents(f.source)); defer { close(parent) }
      let base = f.url(f.source)
      var query = URLComponents(url: base, resolvingAgainstBaseURL: false)!; query.query = "not-authorized"
      var fragment = URLComponents(url: base, resolvingAgainstBaseURL: false)!; fragment.fragment = "not-authorized"
      let invalid = [query.url!, fragment.url!, URL(string: "https://example.invalid/notes/Old.md")!,
        URL(string: "file://localhost" + base.path)!, URL(string: "file://remote.invalid" + base.path)!,
        URL(string: "file://user:password@localhost" + base.path)!,
        URL(string: "file://localhost:99" + base.path)!,
        URL(string: f.root.absoluteString + "notes/../notes/Old.md")!,
        URL(string: f.root.absoluteString + "notes/%2e%2e/notes/Old.md")!,
        URL(string: f.root.absoluteString + "./notes/Old.md")!]
      for callback in invalid {
        try require(!accepts(executor, callback, scope, f.source, parent), "URI metadata, remote authorities and dot segments are not root aliases")
      }
      let composed = "notes/Caf\u{00e9}.md"
      let decomposed = "notes/Cafe\u{0301}.md"
      try f.write(composed, Data("synthetic".utf8))
      try require(!accepts(executor, f.url(decomposed), scope, composed, parent),
                  "Canonical Unicode equality is not byte-identical planned leaf equality")
      try require(!accepts(executor, f.url("notes/old.md"), scope, f.source, parent), "Case-only leaf redirects stay rejected")
      try f.expectOriginals()
    }
    for scenario in ["rootSymlink", "parentSymlink", "leafSymlink", "otherRoot", "siblingRoot", "artifact", "parentReplaced", "rootReplaced"] {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let scope = try WorkspaceTextScope(f.root)
      let parent = try scope.parentDescriptor(WorkspaceFileScope.relativeComponents(f.source)); defer { close(parent) }
      var observed = f.url(f.source)
      if scenario == "rootSymlink" {
        let link = f.directory.appendingPathComponent("root-link", isDirectory: true)
        try f.manager.createSymbolicLink(at: link, withDestinationURL: f.root)
        observed = link.appendingPathComponent(f.source)
      } else if scenario == "parentSymlink" || scenario == "parentReplaced" {
        let saved = f.outside.appendingPathComponent("saved-notes", isDirectory: true)
        try f.manager.moveItem(at: f.url("notes"), to: saved)
        if scenario == "parentSymlink" { try f.manager.createSymbolicLink(at: f.url("notes"), withDestinationURL: saved) }
        else { try f.write(f.source, f.originalSource) }
      } else if scenario == "rootReplaced" {
        try f.manager.moveItem(at: f.root, to: f.outside.appendingPathComponent("saved-vault", isDirectory: true))
        try f.write(f.source, f.originalSource)
      } else if scenario == "leafSymlink" {
        let saved = f.outside.appendingPathComponent("original.md")
        try f.manager.moveItem(at: f.url(f.source), to: saved)
        try f.manager.createSymbolicLink(at: f.url(f.source), withDestinationURL: saved)
      } else if scenario == "otherRoot" || scenario == "siblingRoot" {
        let root = scenario == "otherRoot" ? f.outside : f.directory.appendingPathComponent("vault-sibling", isDirectory: true)
        observed = root.appendingPathComponent(f.source)
        try f.manager.createDirectory(at: observed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try f.originalSource.write(to: observed)
      } else {
        let originalIdentity = try f.identity(f.source)
        let request = try f.request(); let prepared = try f.prepare(executor, request)
        executor.fault = { point in if point == "afterWriteReceipt" { throw InjectedFailure(boundary: point) } }
        let stopped = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"]))
        guard let artifact = (stopped["retainedArtifacts"] as? [[String: Any]])?.first(where: { $0["state"] as? String == "retained" })?["path"] as? String else {
          throw TestFailure(description: "Synthetic swap must retain the displaced original before redirect testing")
        }
        observed = f.url(artifact)
        try require(try f.identity(artifact) == originalIdentity, "Rejected artifact really is the old authorized inode")
        try require(try f.identity(f.source) != originalIdentity, "The current planned leaf is the replacement inode")
      }
      try require(!accepts(executor, observed, scope, f.source, parent), "Root identity, pinned parent and exact leaf cannot be redirected: \(scenario)")
    }
  }

  private static func inventory(_ executor: WorkspaceNoteTransaction, _ fixture: Fixture) throws -> [String: Any] {
    try fixture.invoke(executor, "inspectWorkspaceNoteMoveStorage", ["path": fixture.root.path])
  }

  private static func inventoryRows(_ value: [String: Any]) throws -> [[String: Any]] {
    guard let rows = value["records"] as? [[String: Any]] else {
      throw TestFailure(description: "Inventory must expose bounded records, including an empty array")
    }
    return rows
  }

  private static func inventorySnapshot(_ base: URL) throws -> [String: String] {
    var snapshots: [String: String] = [:]
    func walk(_ url: URL, relative: String) throws {
      var info = stat()
      try require(lstat(url.path, &info) == 0, "Fixture metadata must be readable")
      let kind = info.st_mode & mode_t(S_IFMT)
      var fingerprint = "\(WorkspaceFileScope.revision(info)):\(info.st_mode):\(info.st_nlink):\(info.st_uid):\(info.st_gid):\(info.st_flags):\(info.st_blocks)"
      if kind == mode_t(S_IFREG) && info.st_size <= 1024 * 1024 {
        fingerprint += ":" + (try Data(contentsOf: url)).base64EncodedString()
      }
      snapshots[relative] = fingerprint
      if kind == mode_t(S_IFDIR) {
        for name in try FileManager.default.contentsOfDirectory(atPath: url.path).sorted() {
          try walk(url.appendingPathComponent(name), relative: relative + "/" + name)
        }
      }
    }
    try walk(base, relative: ".")
    return snapshots
  }

  private static func storageInventoryReadOnly() throws {
    let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
    let request = try f.request(); let prepared = try f.prepare(executor, request)
    let completed = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"]))
    try require(completed["phase"] as? String == "completed", "Inventory fixture must start completed")
    // A later dependency change must not cause an inventory read to reconcile,
    // mutate the journal or relabel its saved historical completion.
    try f.write(f.unrelated, Data("External edit after completion".utf8))
    try f.write("user-recovery-copy.md", Data("Not an automatic cleanup artifact".utf8))
    let before = try inventorySnapshot(f.directory)
    let names = try f.manager.contentsOfDirectory(atPath: f.journal.path)
    let journal = f.journal.appendingPathComponent(names.first { $0.hasSuffix(".json") }!)
    let journalBytes = try Data(contentsOf: journal).count
    executor.fault = { point in
      try require(point.hasPrefix("inventory"), "Inventory invoked a mutation/reconciliation boundary: \(point)")
    }
    for _ in 0..<3 {
      let value = try inventory(executor, f)
      try require(value["observedComplete"] as? Bool == true, "A stable local inventory should be complete")
      try require(value["globalJournalCount"] as? Int == 1 && value["globalRecordSlotCount"] as? Int == 1,
                  "Valid count and occupied record slots are independently reported")
      try require(value["globalJournalBytes"] as? Int == journalBytes && value["currentRootJournalBytes"] as? Int == journalBytes,
                  "Encoded journal bytes must be exact, not the raw payload count")
      let reserved = f.originalSource.count + f.replacementSource.count + f.originalIncoming.count + f.replacementIncoming.count
      try require(value["artifactReservedBytes"] as? Int == reserved, "Reservation must match executor admission accounting")
      try require(value["currentRootArtifactBytes"] as? Int == f.originalSource.count + f.originalIncoming.count,
                  "Only retained known artifacts are included, never recovery copies or visible notes")
      let rows = try inventoryRows(value)
      try require(rows.count == 1 && rows[0]["storedPhase"] as? String == "completed", "Saved phase must not be recomputed")
      try require(rows[0]["historicalObservation"] as? Bool == true && rows[0]["cleanupSupported"] as? Bool == false,
                  "Inventory is historical observation, never cleanup approval")
      try require(rows[0]["entryCount"] as? Int == 2 && rows[0]["sourcePath"] as? String == f.source &&
                  rows[0]["destinationPath"] as? String == f.destination && (rows[0]["created"] as? Double ?? 0) > 0,
                  "Recovery UI must receive bounded original manifest metadata")
      try require(rows[0]["artifactCount"] as? Int == 2 && rows[0]["artifactUnknownCount"] as? Int == 0,
                  "Known retained artifacts should have metadata-only totals")
      try require(value["availableBudgetBytes"] as? Int == WorkspaceNoteTransaction.maximumJournalBytes - journalBytes,
                  "Budget remainder is encoded storage allowance, not free disk or move admission")
      try require(try inventorySnapshot(f.directory) == before,
                  "Repeated inventory must preserve bytes, entry sets, modes, identities, mtime and ctime (atime excluded)")
    }
  }

  private static func storageInventoryMissingAndPermissions() throws {
    do {
      let f = try Fixture()
      let absent = f.directory.appendingPathComponent("never-created/Linefold/NoteMoveJournal", isDirectory: true)
      let executor = WorkspaceNoteTransaction(journalDirectory: absent)
      let before = try inventorySnapshot(f.directory)
      let value = try inventory(executor, f)
      try require(value["observedComplete"] as? Bool == true && value["globalJournalBytes"] as? Int == 0 &&
                  value["globalRecordSlotCount"] as? Int == 0, "An absent journal is known empty without initialization")
      try require(!f.manager.fileExists(atPath: absent.path) &&
                  !f.manager.fileExists(atPath: f.directory.appendingPathComponent("never-created").path),
                  "Inspection must not create missing ancestors")
      let malformed = try f.invoke(executor, "inspectWorkspaceNoteMoveStorage", ["path": "relative", "transactionId": UUID().uuidString])
      try require(malformed["globalJournalBytes"] is NSNull, "Malformed inspection must not enter the old load error path")
      try require(try inventorySnapshot(f.directory) == before, "No-directory observation and errors are read-only")
    }
    for scenario in ["directoryMode", "directorySymlink", "journalSymlink", "offlineJournal"] {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let request = try f.request(); _ = try f.prepare(executor, request)
      let id = (request["transactionId"] as! String).lowercased()
      let file = f.journal.appendingPathComponent(id + ".json")
      var inspecting = executor
      switch scenario {
      case "directoryMode": try require(chmod(f.journal.path, 0o755) == 0, "Test mode setup")
      case "directorySymlink":
        let alias = f.directory.appendingPathComponent("journal-link", isDirectory: true)
        try f.manager.createSymbolicLink(at: alias, withDestinationURL: f.journal)
        inspecting = WorkspaceNoteTransaction(journalDirectory: alias)
      case "journalSymlink":
        try f.manager.moveItem(at: file, to: f.outside.appendingPathComponent("held.json"))
        try f.manager.createSymbolicLink(at: file, withDestinationURL: f.url(f.source))
      default: executor.inventoryDatalessOverride = { $0 == "journal:" + id + ".json" }
      }
      let before = try inventorySnapshot(f.directory)
      let value = try inventory(inspecting, f)
      try require(value["observedComplete"] as? Bool == false && value["globalJournalBytes"] is NSNull,
                  "Unavailable, redirected or offline journal storage is unknown, never known zero: \(scenario)")
      try require(try inventorySnapshot(f.directory) == before, "Inspection must not repair permissions or follow symlinks")
      try f.expectOriginals()
    }
  }

  private static func storageInventoryCountsAndBounds() throws {
    do {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let request = try f.request(); let prepared = try f.prepare(executor, request)
      _ = try f.invoke(executor, "cancelPreparedWorkspaceNoteMove", f.command(request, token: prepared["token"]))
      let id = (request["transactionId"] as! String).lowercased()
      let data = try Data(contentsOf: f.journal.appendingPathComponent(id + ".json"))
      for index in 0..<31 { try data.write(to: f.journal.appendingPathComponent("\(id).\(index).pending")) }
      let before = try inventorySnapshot(f.directory)
      let value = try inventory(executor, f)
      try require(value["globalJournalCount"] as? Int == 1 && value["globalRecordSlotCount"] as? Int == 1 &&
                  value["pendingCount"] as? Int == 31 && value["pendingBytes"] as? Int == data.count * 31,
                  "Pending remnants consume bytes, not JSON record slots")
      try require(!(value["blockers"] as? [String] ?? []).contains("journal_record_limit"),
                  "32 total directory entries must not be mistaken for 32 records")
      try require(try inventorySnapshot(f.directory) == before, "Pending remnants must never be pruned")
      let bad = f.journal.appendingPathComponent(UUID().uuidString.lowercased() + ".json")
      try Data("invalid JSON".utf8).write(to: bad); try require(chmod(bad.path, 0o600) == 0, "Test private mode setup")
      try Data("unrecognized".utf8).write(to: f.journal.appendingPathComponent("unexpected.bin"))
      let invalidBefore = try inventorySnapshot(f.directory)
      let invalid = try inventory(executor, f)
      try require(invalid["globalJournalCount"] as? Int == 1 && invalid["globalRecordSlotCount"] as? Int == 2 &&
                  invalid["invalidJournalCount"] as? Int == 1 && invalid["unknownEntryCount"] as? Int == 1,
                  "Invalid JSON occupies an actual slot without becoming a valid record")
      try require(invalid["artifactReservedBytes"] is NSNull && invalid["currentRootJournalBytes"] is NSNull,
                  "Unknown membership/reservation must not masquerade as a prefix sum")
      try require(invalid["globalJournalBytes"] as? Int == data.count * 32 + "invalid JSON".utf8.count + "unrecognized".utf8.count,
                  "Known regular-file bytes include invalid, pending and unexpected files")
      try require(try inventorySnapshot(f.directory) == invalidBefore, "Invalid and unknown data must remain untouched")
      executor.inventoryReadBudgetOverride = 0
      let limited = try inventory(executor, f)
      try require(limited["globalJournalCount"] is NSNull && limited["artifactReservedBytes"] is NSNull &&
                  (limited["blockers"] as? [String] ?? []).contains("journal_read_limit"), "Read budget exhaustion is explicit")
    }
    do {
      let f = try Fixture(); try require(chmod(f.journal.path, 0o700) == 0, "Test private directory setup")
      let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      for index in 0..<256 { try Data().write(to: f.journal.appendingPathComponent("\(index).pending")) }
      let atLimit = try inventory(executor, f)
      try require(atLimit["observedComplete"] as? Bool == true && atLimit["pendingCount"] as? Int == 256,
                  "Exactly 256 entries must be observable")
      try Data().write(to: f.journal.appendingPathComponent("overflow.pending"))
      let before = try inventorySnapshot(f.directory)
      let overflow = try inventory(executor, f)
      try require(overflow["observedComplete"] as? Bool == false && overflow["globalJournalBytes"] is NSNull &&
                  overflow["globalRecordSlotCount"] is NSNull && overflow["pendingBytes"] is NSNull,
                  "An entry-limit prefix is not a complete inventory")
      try require(try inventorySnapshot(f.directory) == before, "Bounded inspection cannot remove overflow files")
    }
    do {
      let f = try Fixture(); try require(chmod(f.journal.path, 0o700) == 0, "Test private directory setup")
      let huge = f.journal.appendingPathComponent(UUID().uuidString.lowercased() + ".json")
      try Data().write(to: huge); try require(chmod(huge.path, 0o600) == 0, "Test private file setup")
      let handle = try FileHandle(forWritingTo: huge)
      try handle.truncate(atOffset: UInt64(WorkspaceNoteTransaction.maximumJournalBytes + 1)); try handle.close()
      let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let before = try inventorySnapshot(f.directory)
      let value = try inventory(executor, f)
      try require(value["globalJournalBytes"] as? Int == WorkspaceNoteTransaction.maximumJournalBytes + 1 &&
                  value["availableBudgetBytes"] as? Int == 0 && value["artifactReservedBytes"] is NSNull,
                  "Oversized sparse metadata is counted without allocating or decoding its body")
      try require((value["blockers"] as? [String] ?? []).contains("journal_byte_limit") &&
                  (value["blockers"] as? [String] ?? []).contains("journal_read_limit"), "Byte/read limits are independent")
      try require(try inventorySnapshot(f.directory) == before, "Oversized data must remain unchanged")
    }
  }

  private static func storageInventoryScopeAndArtifacts() throws {
    do {
      let f = try Fixture(); let other = try Fixture()
      let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      for fixture in [f, other] {
        let request = try fixture.request(); let prepared = try fixture.prepare(executor, request)
        let result = try fixture.invoke(executor, "executeWorkspaceNoteMove", fixture.command(request, token: prepared["token"]))
        try require(result["phase"] as? String == "completed", "Both synthetic roots must prepare independent journals")
      }
      // Make the other recorded root unavailable. Inventory must neither reopen
      // its stored path nor inspect any artifact under that root.
      try other.manager.moveItem(at: other.root, to: other.outside.appendingPathComponent("held-vault"))
      var observedPaths: [String] = []
      executor.inventoryArtifactObserver = { observedPaths.append($0) }
      let before = try inventorySnapshot(f.directory); let otherBefore = try inventorySnapshot(other.directory)
      let value = try inventory(executor, f); let rows = try inventoryRows(value)
      try require(value["globalJournalCount"] as? Int == 2 && rows.count == 1 && observedPaths.count == 2,
                  "Global managed journals may be decoded; artifacts are inspected only in the current authorized root")
      let currentID = rows[0]["transactionId"] as! String
      try require(observedPaths.allSatisfy { $0.contains(currentID) }, "Never touch artifacts by a different record's saved root path")
      try require(value["observedComplete"] as? Bool == true, "Another root's availability is not silently probed")
      try require(try inventorySnapshot(f.directory) == before && inventorySnapshot(other.directory) == otherBefore,
                  "Neither root may be changed by observation")
    }
    for scenario in ["missing", "changed", "symlink", "offline", "parentChanged"] {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let request = try f.request(); let prepared = try f.prepare(executor, request)
      let result = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"]))
      let artifacts = result["retainedArtifacts"] as! [[String: Any]]
      let path = artifacts.first { ($0["path"] as? String)?.hasPrefix("notes/") == true }!["path"] as! String
      switch scenario {
      case "missing": try f.manager.moveItem(at: f.url(path), to: f.outside.appendingPathComponent("held-original.md"))
      case "changed": try f.overwriteSameInode(path, Data("Concurrent retained version".utf8))
      case "symlink":
        try f.manager.moveItem(at: f.url(path), to: f.outside.appendingPathComponent("held-original.md"))
        try f.manager.createSymbolicLink(at: f.url(path), withDestinationURL: f.url(f.destination))
      case "offline": executor.inventoryDatalessOverride = { $0 == "artifact:" + path }
      default:
        try f.manager.moveItem(at: f.url("notes"), to: f.outside.appendingPathComponent("held-notes"))
        try f.manager.createDirectory(at: f.url("notes"), withIntermediateDirectories: false)
      }
      let before = try inventorySnapshot(f.directory)
      let value = try inventory(executor, f); let row = try inventoryRows(value)[0]
      try require(value["observedComplete"] as? Bool == false && value["currentRootArtifactBytes"] is NSNull &&
                  row["artifactBytes"] is NSNull && row["artifactUnknownCount"] as? Int == 1,
                  "A missing/changed/offline/redirected artifact cannot become a known zero or prefix total: \(scenario)")
      if scenario == "missing" { try require(row["artifactMissingCount"] as? Int == 1, "Missing evidence is separately reported") }
      try require(row["storedPhase"] as? String == "completed", "Observation cannot rewrite historical transaction phase")
      try require(try inventorySnapshot(f.directory) == before, "Artifact inspection never edits, restores or materializes data")
    }
  }

  private static func storageInventoryRaces() throws {
    for scenario in ["root", "journal", "artifact"] {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let request = try f.request(); let prepared = try f.prepare(executor, request)
      let result = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"]))
      let artifact = (result["retainedArtifacts"] as! [[String: Any]])[0]["path"] as! String
      let journal = f.journal.appendingPathComponent((request["transactionId"] as! String).lowercased() + ".json")
      let originalJournal = try Data(contentsOf: journal)
      var hit = false
      executor.fault = { point in
        if !hit && scenario == "root" && point == "inventoryAfterRootOpen" {
          hit = true
          try f.manager.moveItem(at: f.root, to: f.outside.appendingPathComponent("held-root"))
          try f.manager.createDirectory(at: f.root, withIntermediateDirectories: false)
        } else if !hit && scenario == "journal" && point == "inventoryAfterJournalRead" {
          hit = true; try (originalJournal + Data("\n".utf8)).write(to: journal)
        } else if !hit && scenario == "artifact" && point == "inventoryAfterArtifactStat" {
          hit = true; try f.overwriteSameInode(artifact, Data("Writer version must survive".utf8))
        }
      }
      let value = try inventory(executor, f)
      try require(hit && value["observedComplete"] as? Bool == false, "Race hook must invalidate observation: \(scenario)")
      if scenario == "journal" {
        try require(value["globalJournalBytes"] is NSNull &&
                    (value["blockers"] as? [String] ?? []).contains("journal_changed_during_observation"),
                    "Journal races invalidate complete totals")
        try require(try Data(contentsOf: journal) == originalJournal + Data("\n".utf8), "Do not overwrite racing journal evidence")
      } else if scenario == "root" {
        try require(value["currentRootKnown"] as? Bool == false && value["currentRootArtifactBytes"] is NSNull,
                    "A replaced root must not preserve authority from its path spelling")
        try require(try Data(contentsOf: journal) == originalJournal, "A root race must not save a newly inferred transaction phase")
      } else {
        try require(value["currentRootArtifactBytes"] is NSNull, "Artifact race cannot publish an apparently complete sum")
        try require(try f.bytes(artifact) == Data("Writer version must survive".utf8), "Concurrent artifact bytes remain untouched")
        try require(try Data(contentsOf: journal) == originalJournal, "Artifact race must not trigger reconcile/save")
      }
    }
  }

  private static func presenterMoveNotifications() throws {
    for scenario in ["success", "renameFailure", "syncFailure"] {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let request = try f.request(); let prepared = try f.prepare(executor, request)
      func traceSourceMetadata(_ stage: String) throws {
        let attributes = try f.attributes(f.source)
        let count = listxattr(f.url(f.source).path, nil, 0, XATTR_NOFOLLOW)
        var names = [CChar](repeating: 0, count: max(0, count))
        let actual = names.withUnsafeMutableBufferPointer {
          listxattr(f.url(f.source).path, $0.baseAddress, $0.count, XATTR_NOFOLLOW)
        }
        let xattrs = actual > 0 ? String(decoding: names.prefix(actual).map { UInt8(bitPattern: $0) }, as: UTF8.self)
          .split(separator: "\u{0}").map(String.init) : []
        print("PRESENTER \(scenario) \(stage): revision=\(try f.revision(f.source)) mode=\(attributes.st_mode) flags=\(attributes.st_flags) xattrCount=\(count)/\(actual) names=\(xattrs)")
        fflush(stdout)
      }
      try traceSourceMetadata("beforeRegistration")
      let presenter = MovePresenter(url: f.url(f.source))
      NSFileCoordinator.addFilePresenter(presenter)
      defer { NSFileCoordinator.removeFilePresenter(presenter) }
      try traceSourceMetadata("afterRegistration")
      var points: [String] = []
      var coordinationSnapshots: [String] = []
      func describeURL(_ url: URL?) -> String {
        guard let url else { return "nil" }
        // Canonicalization is synthetic diagnostic evidence only, never an
        // executor acceptance check. Do not log paths outside this fixture.
        let canonical = url.resolvingSymlinksInPath().standardizedFileURL
        let canonicalRoot = f.root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let canonicalParent = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard url.isFileURL, canonicalParent.starts(with: canonicalRoot),
              let diagnosticScope = try? WorkspaceFileScope(f.root),
              let expectedParent = try? diagnosticScope.parentDescriptor(
                Array(canonicalParent.dropFirst(canonicalRoot.count)) + [url.lastPathComponent]) else {
          return "outside-synthetic-root (suppressed)"
        }
        defer { close(expectedParent) }
        let observedParent = open(url.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard observedParent >= 0 else { return "unverified-synthetic-parent (suppressed)" }
        defer { close(observedParent) }
        var expected = stat(); var actual = stat()
        guard fstat(expectedParent, &expected) == 0, fstat(observedParent, &actual) == 0,
              expected.st_dev == actual.st_dev, expected.st_ino == actual.st_ino else {
          return "different-synthetic-parent (suppressed)"
        }
        var attributes = stat()
        let metadata: String
        if lstat(url.path, &attributes) == 0 {
          guard attributes.st_mode & mode_t(S_IFMT) != mode_t(S_IFLNK) else { return "synthetic-leaf-symlink (canonical suppressed)" }
          metadata = "dev:ino=\(attributes.st_dev):\(attributes.st_ino) revision=\(WorkspaceFileScope.revision(attributes)) " +
            "mode=\(attributes.st_mode) flags=\(attributes.st_flags)"
        } else {
          metadata = errno == ENOENT ? "absent" : "lstat-error=\(errno)"
        }
        return "raw=\(url.absoluteString) standardized=\(url.standardizedFileURL.absoluteString) " +
          "canonical=\(canonical.absoluteString) lstat={\(metadata)}"
      }
      executor.coordinationObserver = { observation in
        let artifacts: String
        do {
          let paths = try f.relativeFiles(under: f.root).filter {
            $0.split(separator: "/").last?.hasPrefix(".linefold") == true
          }
          artifacts = paths.map { "\($0)={\(describeURL(f.url($0)))}" }.joined(separator: "; ")
        } catch { artifacts = "synthetic-artifact-enumeration-failed" }
        coordinationSnapshots.append("moving=\(observation.moving) expired=\(observation.deadlineExpired) " +
          "sourceOptions=\(observation.moving ? "forMoving" : "[]") destinationOptions=[] " +
          "expectedSource={\(describeURL(observation.expectedSource))} observedSource={\(describeURL(observation.observedSource))} " +
          "expectedDestination={\(describeURL(observation.expectedDestination))} observedDestination={\(describeURL(observation.observedDestination))} " +
          "artifacts=[\(artifacts)] presenter={\(describeURL(presenter.presentedItemURL))}")
      }
      executor.fault = { point in
        points.append(point)
        if scenario == "renameFailure" && point == "beforeExclusiveRename" {
          try f.write(f.destination, Data("Unrelated destination".utf8))
        } else if scenario == "syncFailure" && (point == "beforeMoveParentSync" || point == "beforeRepairMoveParentSync") {
          throw InjectedFailure(boundary: point)
        }
      }
      let result = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"]))
      for snapshot in coordinationSnapshots { print("PRESENTER \(scenario) coordination: \(snapshot)") }
      print("PRESENTER \(scenario): result=\(result) sourceExists=\(f.exists(f.source)) destinationExists=\(f.exists(f.destination)) points=\(points)"); fflush(stdout)
      let notified = presenter.moved.wait(timeout: .now() + (scenario == "renameFailure" ? 0.2 : 3)) == .success
      print("PRESENTER \(scenario): notified=\(notified) presentedURL=\(String(describing: presenter.presentedItemURL))"); fflush(stdout)
      if scenario == "renameFailure" {
        try require(!notified && presenter.presentedItemURL?.resolvingSymlinksInPath() == f.url(f.source).resolvingSymlinksInPath(), "Failed RENAME_EXCL must not send a false didMove notification")
      } else {
        try require(notified && presenter.presentedItemURL?.resolvingSymlinksInPath() == f.url(f.destination).resolvingSymlinksInPath(), "Presenter must learn actual namespace move even if subsequent durability fails")
        if scenario == "syncFailure" { try require(result["phase"] as? String != "completed", "Notification of namespace move is not a durability receipt") }
      }
    }
  }

  private static func directorySource(_ f: Fixture) -> Data {
    Data(String(decoding: f.originalSource, as: UTF8.self)
      .replacingOccurrences(of: "../assets/image.png", with: "../../assets/image.png").utf8)
  }

  private static func directoryRequest(_ f: Fixture, source: String = "notes",
                                       destination: String = "archive/Moved", empty: Bool = false) throws -> [String: Any] {
    let tree = CloudWorkspace.inspectWorkspaceDirectoryMoveTree(f.root, relativePath: source,
                                                                requestId: UUID().uuidString)
    var files: [[String: Any]] = []
    if !empty {
      files = [
        ["path": f.source, "destinationPath": destination + "/Old.md", "expectedRevision": try f.revision(f.source),
         "expectedBytes": FlutterStandardTypedData(bytes: f.originalSource),
         "replacementBytes": FlutterStandardTypedData(bytes: directorySource(f))],
        ["path": f.incoming, "destinationPath": f.incoming, "expectedRevision": try f.revision(f.incoming),
         "expectedBytes": FlutterStandardTypedData(bytes: f.originalIncoming),
         "replacementBytes": FlutterStandardTypedData(bytes: Data("# Index\r\n[Old](archive/Moved/Old.md#section \"title\")\r\n".utf8))],
      ]
    }
    return ["path": f.root.path, "transactionId": UUID().uuidString, "sourcePath": source,
            "destinationPath": destination, "files": files, "tree": tree,
            "catalog": try f.catalogRows(), "assets": [["path": "assets/image.png", "revision": try f.revision("assets/image.png")]]]
  }

  private static func directorySuccessAndRestart() throws {
    let f = try Fixture()
    try f.write("notes/nested/image.png", Data([1, 2, 3, 4]))
    let directoryIdentity = try f.identity("notes")
    let imageIdentity = try f.identity("notes/nested/image.png")
    let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
    let request = try directoryRequest(f)
    let prepared = try f.invoke(executor, "prepareWorkspaceDirectoryMove", request)
    try require(prepared["phase"] as? String == "prepared", "Directory preparation failed: \(prepared)")
    try require(prepared["version"] as? Int == 2, "Directory must have v2 journal")
    let result = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"]))
    try require(result["phase"] as? String == "completed", "Directory execution failed: \(result)")
    let namespace = result["namespace"] as! [String: Any]
    try require(namespace["moved"] as? Bool == true && namespace["synced"] as? Bool == true && namespace["verified"] as? Bool == true,
                "Completion needs a real namespace/durability receipt")
    try require(!f.exists("notes"), "Old namespace must be absent")
    try require(try f.identity("archive/Moved") == directoryIdentity, "Directory must be renamed once, not recreated")
    try require(try f.identity("archive/Moved/nested/image.png") == imageIdentity, "Images retain their inode")
    try require(try f.bytes("archive/Moved/Old.md") == directorySource(f), "Moved text must contain rewritten links")
    let artifacts = result["retainedArtifacts"] as! [[String: Any]]
    let sourceArtifact = artifacts.first { ($0["path"] as? String)?.hasPrefix("archive/Moved/") == true }!["path"] as! String
    try require(try f.bytes(sourceArtifact) == f.originalSource, "Retained original follows its parent directory")
    let restarted = WorkspaceNoteTransaction(journalDirectory: f.journal)
    let observed = try f.invoke(restarted, "reconcileWorkspaceNoteMove", f.command(request))
    try require(observed["phase"] as? String == "completed", "Restart must validate durable complete record: \(observed)")
    let beforeJournal = try Data(contentsOf: f.journal.appendingPathComponent((request["transactionId"] as! String).lowercased() + ".json"))
    let inventory = try f.invoke(restarted, "inspectWorkspaceNoteMoveStorage", ["path": f.root.path])
    try require(inventory["observedComplete"] as? Bool == true && inventory["artifactUnknownCount"] as? Int == 0,
                "v2 inventory must find relocated owned artifacts: \(inventory)")
    try require(try Data(contentsOf: f.journal.appendingPathComponent((request["transactionId"] as! String).lowercased() + ".json")) == beforeJournal,
                "Inventory must not reconcile/write v2 journals")
    var recovery = f.command(request); recovery["relativeDirectory"] = "archive"
    let recovered = try f.invoke(restarted, "recoverWorkspaceNoteMove", recovery)
    let copies = recovered["recoveryPaths"] as! [String]
    try require(copies.count == 2, "Original text recovery must work without old parent paths: \(recovered)")
    try require(try copies.map(f.bytes).contains(f.originalSource), "Original moved note must be recoverable as copy")
    try f.overwriteSameInode(sourceArtifact, Data("Concurrent artifact replacement".utf8))
    let changed = try f.invoke(WorkspaceNoteTransaction(journalDirectory: f.journal),
                              "reconcileWorkspaceNoteMove", f.command(request))
    try require(changed["phase"] as? String != "completed", "Changed artifact invalidates completion")
    let changedArtifacts = changed["retainedArtifacts"] as! [[String: Any]]
    try require(changedArtifacts.allSatisfy { $0["verified"] as? Bool == false },
                "Reconcile cannot keep stale verified artifact receipts after artifact_changed: \(changed)")
  }

  private static func directoryEmptyAndImageOnly() throws {
    for image in [false, true] {
      let f = try Fixture()
      try f.manager.createDirectory(at: f.url("empty"), withIntermediateDirectories: true)
      if image { try f.write("empty/picture.png", Data([9, 8, 7])) }
      let identity = try f.identity("empty")
      let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let request = try directoryRequest(f, source: "empty", empty: true)
      let prepared = try f.invoke(executor, "prepareWorkspaceDirectoryMove", request)
      try require(prepared["phase"] as? String == "prepared", "Zero-note preparation failed: \(prepared)")
      let result = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"]))
      try require(result["phase"] as? String == "completed", "Zero-note move failed: \(result)")
      try require((result["entries"] as? [Any])?.isEmpty == true, "No fabricated note entry")
      try require(try f.identity("archive/Moved") == identity, "Zero-note directory must actually move")
      let restarted = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let observed = try f.invoke(restarted, "reconcileWorkspaceNoteMove", f.command(request))
      try require(observed["phase"] as? String == "completed", "Zero-note receipt survives restart")
      if image { try require(try f.bytes("archive/Moved/picture.png") == Data([9, 8, 7]), "Image bytes unchanged") }
    }
  }

  private static func directoryPreflight() throws {
    for scenario in ["missingNote", "forgedTree", "unsupported", "hiddenArtifact", "symlink", "occupiedOpaque", "caseCollision", "overlap", "changedTree", "crossVolume", "capacity"] {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      if scenario == "unsupported" { try f.write("notes/file.pdf", Data([1])) }
      if scenario == "hiddenArtifact" { try f.write("notes/.linefold-note-move-old.md", Data([1])) }
      if scenario == "symlink" { try f.manager.createSymbolicLink(atPath: f.url("notes/link.png").path, withDestinationPath: f.url("assets/image.png").path) }
      if scenario == "occupiedOpaque" { try f.write("archive/Moved", Data([1])) }
      if scenario == "caseCollision" { try f.write("archive/mOvEd", Data([1])) }
      var request = try directoryRequest(f)
      if scenario == "missingNote" { request["files"] = Array((request["files"] as! [[String: Any]]).dropFirst()) }
      if scenario == "forgedTree" {
        var tree = request["tree"] as! [String: Any]
        tree["members"] = Array((tree["members"] as! [[String: Any]]).dropLast())
        request["tree"] = tree
      }
      if scenario == "overlap" { request["destinationPath"] = "notes/inside" }
      if scenario == "changedTree" { try f.write("notes/new.png", Data([2])) }
      if scenario == "crossVolume" { executor.parentDeviceOverride = { path, device in path == "archive/Moved" ? device &+ 1 : device } }
      if scenario == "capacity" { executor.availableBytesOverride = { _, _, _ in 0 } }
      let result = try f.invoke(executor, "prepareWorkspaceDirectoryMove", request)
      try require(result["phase"] as? String == "blocked", "\(scenario) must reject: \(result)")
      try require(try f.bytes(f.source) == f.originalSource && f.bytes(f.incoming) == f.originalIncoming,
                  "\(scenario) must not mutate notes")
      try require(f.exists("notes"), "\(scenario) must not move directory")
    }
  }

  private static func directoryFaultReceipts() throws {
    let points = ["beforeStageIntent", "afterStageIntent", "afterStageCreate", "beforeStageSync", "beforeStageReceipt",
                  "beforeWriteIntent", "afterWriteIntent", "beforeWrite", "afterWrite", "beforeWriteReceipt",
                  "beforeDirectoryMoveIntent", "afterDirectoryMoveIntent", "beforeDirectoryExclusiveRename",
                  "afterDirectoryRename", "beforeDirectoryMoveRootSync", "beforeDirectoryMoveSourceParentSync",
                  "beforeDirectoryMoveDestinationParentSync", "beforeDirectoryMoveReceipt", "afterDirectoryMoveReceipt",
                  "beforeDirectoryCompletion"]
    for boundary in points {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let request = try directoryRequest(f)
      let prepared = try f.invoke(executor, "prepareWorkspaceDirectoryMove", request)
      try require(prepared["phase"] as? String == "prepared", "Fault fixture prepare: \(prepared)")
      var reached = false
      executor.fault = { point in if point == boundary { reached = true; throw InjectedFailure(boundary: point) } }
      let result = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"]))
      try require(reached, "Directory fault point not exercised: \(boundary), \(result)")
      try require(result["phase"] as? String != "completed", "Fault must not claim completion: \(boundary)")
      try require(result["retryAllowed"] as? Bool == false, "Fault revokes write token: \(boundary)")
      let locations = ["notes/Old.md", "archive/Moved/Old.md"].filter(f.exists)
      try require(locations.count == 1, "Exactly one live namespace retained: \(boundary)")
      let current = try f.bytes(locations[0])
      try require(current == f.originalSource || current == directorySource(f), "No torn body: \(boundary)")
      let journal = f.journal.appendingPathComponent((request["transactionId"] as! String).lowercased() + ".json")
      let json = try JSONSerialization.jsonObject(with: Data(contentsOf: journal)) as! [String: Any]
      let originals = (json["entries"] as! [[String: Any]]).compactMap { row -> Data? in
        guard let encoded = row["original"] as? String else { return nil }; return Data(base64Encoded: encoded)
      }
      try require(originals.contains(f.originalSource) && originals.contains(f.originalIncoming), "Originals remain in durable journal")
      let restarted = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let observed = try f.invoke(restarted, "reconcileWorkspaceNoteMove", f.command(request))
      try require(observed["phase"] as? String != "completed", "Restart cannot invent completion: \(boundary)")
      let before = try f.relativeFiles(under: f.root)
      _ = try f.invoke(restarted, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"]))
      try require(try f.relativeFiles(under: f.root) == before, "Old token must not replay: \(boundary)")
    }
  }

  private static func directoryDependencyRaces() throws {
    for scenario in ["newMember", "outsideEdit", "destinationRace", "oldSourceReappears", "artifactChange"] {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let request = try directoryRequest(f)
      let prepared = try f.invoke(executor, "prepareWorkspaceDirectoryMove", request)
      var reached = false
      executor.fault = { point in
        let trigger = scenario == "oldSourceReappears" ? "afterDirectoryRename" : "beforeDirectoryMoveIntent"
        guard !reached, point == trigger else { return }; reached = true
        switch scenario {
        case "newMember": try f.write("notes/late.png", Data([8]))
        case "outsideEdit": try f.overwriteSameInode(f.unrelated, Data("Concurrent writer".utf8))
        case "destinationRace": try f.write("archive/Moved", Data("Do not overwrite".utf8))
        case "oldSourceReappears": try f.write("notes/Other.md", Data("New source namespace".utf8))
        default:
          let artifacts = try f.relativeFiles(under: f.root).filter { $0.hasPrefix("notes/.linefold-note-move-") }
          try require(artifacts.count == 1, "Fixture retained source artifact")
          try f.overwriteSameInode(artifacts[0], Data("External retained-artifact edit".utf8))
        }
      }
      let result = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"]))
      try require(reached && result["phase"] as? String != "completed", "Race must invalidate semantic completion: \(scenario), \(result)")
      if scenario == "destinationRace" { try require(try f.bytes("archive/Moved") == Data("Do not overwrite".utf8), "Occupied destination must survive") }
      if scenario == "oldSourceReappears" { try require(try f.bytes("notes/Other.md") == Data("New source namespace".utf8), "No source cleanup after race") }
    }
  }

  private static func directoryMixedJournalCapacity() throws {
    let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal, maximumStoredRecords: 1)
    let first = try f.request()
    let prepared = try f.prepare(executor, first)
    try require(prepared["phase"] as? String == "prepared", "v1 fixture")
    let second = try directoryRequest(f)
    let result = try f.invoke(executor, "prepareWorkspaceDirectoryMove", second)
    try require(result["phase"] as? String == "blocked" && result["code"] as? String == "journal_full", "v2 shares v1 global quota: \(result)")
    let listed = try f.invoke(executor, "listWorkspaceNoteMoves", ["path": f.root.path])
    try require((listed["transactions"] as? [Any])?.count == 1, "Failed v2 must not displace v1 journal")
    try f.expectOriginals()
  }

  private static func directoryPresenterNotifications() throws {
    for scenario in ["success", "renameFailure", "syncFailure"] {
      let f = try Fixture(); let executor = WorkspaceNoteTransaction(journalDirectory: f.journal)
      let request = try directoryRequest(f)
      let prepared = try f.invoke(executor, "prepareWorkspaceDirectoryMove", request)
      let directory = MovePresenter(url: f.url("notes")); let child = MovePresenter(url: f.url(f.source))
      NSFileCoordinator.addFilePresenter(directory); NSFileCoordinator.addFilePresenter(child)
      defer { NSFileCoordinator.removeFilePresenter(directory); NSFileCoordinator.removeFilePresenter(child) }
      executor.fault = { point in
        if scenario == "renameFailure" && point == "beforeDirectoryExclusiveRename" { try f.write("archive/Moved", Data([8])) }
        if scenario == "syncFailure" && point == "beforeDirectoryMoveSourceParentSync" { throw InjectedFailure(boundary: point) }
      }
      let result = try f.invoke(executor, "executeWorkspaceNoteMove", f.command(request, token: prepared["token"]))
      let directoryMoved = directory.moved.wait(timeout: .now() + (scenario == "renameFailure" ? 0.2 : 3)) == .success
      let childMoved = child.moved.wait(timeout: .now() + (scenario == "renameFailure" ? 0.2 : 3)) == .success
      if scenario == "renameFailure" { try require(!directoryMoved && !childMoved, "Rejected directory rename must not announce success") }
      else {
        try require(directoryMoved && childMoved, "Directory and child presenters must learn actual namespace move: \(scenario), \(result)")
        if scenario == "success" { try require(result["phase"] as? String == "completed", "Presenter directory success: \(result)") }
        else { try require(result["phase"] as? String != "completed", "Presenter notification is not durability") }
      }
    }
  }


}
