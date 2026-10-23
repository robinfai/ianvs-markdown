import Foundation
import Darwin

/// Synthetic local trees only. No app journal, iCloud account, user workspace,
/// download, deletion by the inspected helper, or directory move is exercised.
@main
struct DirectoryMoveInspectionAcceptance {
  static func main() throws {
    try verifyManifestAndBlockers()
    try verifyDirectoryPackageClassification()
    try verifySourceAndRootStates()
    try verifyBudgetsAndCancellation()
    try verifyRequestAndFailureEnvelopeBounds()
    try verifyRaces()
    try verifyConcurrentCancellation()
    print("PASS: read-only all-entry directory manifests, explicit blockers, no-follow boundaries, fail-closed budgets, live cancellation and tree race detection")
  }
}

private let fm = FileManager.default

private func fixture(_ body: (URL) throws -> Void) throws {
  let root = fm.temporaryDirectory.appendingPathComponent("linefold-directory-inspection-\(UUID().uuidString)", isDirectory: true)
  try fm.createDirectory(at: root, withIntermediateDirectories: false)
  defer { try? fm.removeItem(at: root) }
  try body(root)
}

private func directory(_ root: URL, _ path: String) throws {
  try fm.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
}

private func file(_ root: URL, _ path: String, _ data: Data = Data([0xff, 0x00, 0x81])) throws {
  try data.write(to: root.appendingPathComponent(path))
}

private func inspect(_ root: URL, _ path: String = "source",
                     limits: WorkspaceDirectoryMoveInspectionLimits = WorkspaceDirectoryMoveInspectionLimits(),
                     cancellation: WorkspaceDirectoryMoveInspectionCancellation = WorkspaceDirectoryMoveInspectionCancellation(),
                     afterDirectory: ((String) throws -> Void)? = nil) -> [String: Any] {
  CloudWorkspace.inspectWorkspaceDirectoryMoveTree(
    root, relativePath: path, requestId: UUID().uuidString,
    cancellation: cancellation, limits: limits, afterDirectoryEnumerated: afterDirectory
  )
}

private func rows(_ value: [String: Any]) -> [[String: Any]] { value["members"] as! [[String: Any]] }
private func codes(_ value: [String: Any]) -> Set<String> {
  Set((value["issues"] as! [[String: String]]).map { $0["code"]! })
}
private func has(_ value: [String: Any], _ code: String, complete: Bool? = nil) {
  precondition(codes(value).contains(code), "Expected \(code), got \(value)")
  if let complete { precondition(value["complete"] as? Bool == complete) }
}
private func requireClean(_ value: [String: Any], count: Int) {
  precondition(value["sourceState"] as? String == "directory")
  precondition(value["complete"] as? Bool == true, "Incomplete: \(value)")
  precondition(codes(value).isEmpty, "Unexpected blockers: \(value)")
  precondition(rows(value).count == count)
  precondition(value["observedEntryCount"] as? Int == count)
  precondition(value["rootIdentity"] is String && value["sourceIdentity"] is String)
}

private func verifyManifestAndBlockers() throws {
  try fixture { root in
    try directory(root, "source/empty")
    try directory(root, "source/nested")
    // Deliberately invalid UTF-8/image data proves inspection does not parse or
    // load supported file bodies. There is no filename/type-content fallback.
    for name in ["a.md", "b.markdown", "c.mdown", "d.mkd", "e.txt",
                 "p.PNG", "q.jpg", "r.jpeg", "s.gif", "t.webp", "u.bmp"] {
      try file(root, "source/nested/" + name)
    }
    let before = inspect(root)
    requireClean(before, count: 14)
    let paths = rows(before).map { $0["path"] as! String }
    precondition(paths == paths.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) })
    precondition(rows(before).filter { $0["kind"] as? String == "note" }.count == 5)
    precondition(rows(before).filter { $0["kind"] as? String == "image" }.count == 6)
    precondition(rows(before).allSatisfy { $0["revision"] is String && $0["identity"] is String && $0["local"] as? Bool == true })
    requireClean(inspect(root, "source/empty"), count: 1)
    let after = inspect(root)
    precondition(NSArray(array: rows(before)).isEqual(to: rows(after)),
                 "Metadata inspection modified a fixture")
    let data = try Data(contentsOf: root.appendingPathComponent("source/nested/a.md"))
    precondition(data == Data([0xff, 0x00, 0x81]))

    try file(root, "source/guide.pdf")
    let pdf = inspect(root)
    has(pdf, "unsupportedMember", complete: true)
    precondition(pdf["sourceState"] as? String == "directory", "A PDF-containing directory is not absent")
    precondition(rows(pdf).contains { $0["path"] as? String == "source/guide.pdf" && $0["kind"] as? String == "unsupported" })
    try directory(root, "source/Bundle.app/empty")
    try directory(root, "source/.hidden")
    try file(root, "source/.hidden/secret.md")
    try file(root, "source/.DS_Store")
    try file(root, "source/hidden-flag.md")
    precondition(chflags(root.appendingPathComponent("source/hidden-flag.md").path, UInt32(UF_HIDDEN)) == 0)
    try file(root, "source/.linefold-note-move-unrecognized")
    try file(root, "source/.remote.md.icloud")
    try fm.createSymbolicLink(at: root.appendingPathComponent("source/link"), withDestinationURL: root.appendingPathComponent("source"))
    precondition(mkfifo(root.appendingPathComponent("source/pipe").path, 0o600) == 0)
    precondition(link(root.appendingPathComponent("source/nested/a.md").path,
                      root.appendingPathComponent("source/hardlink.md").path) == 0)
    try file(root, "source/bad:name.md")
    let blocked = inspect(root)
    for code in ["hiddenMember", "recoveryArtifact", "offline", "symlinkMember", "specialMember", "multiplyLinkedMember", "unsupportedPath", "packageMember"] {
      has(blocked, code, complete: true)
    }
    precondition(rows(blocked).contains { $0["path"] as? String == "source/.hidden/secret.md" })
    precondition((blocked["issues"] as! [[String: String]]).contains {
      $0["code"] == "hiddenMember" && $0["path"] == "source/hidden-flag.md"
    })
    precondition(rows(blocked).contains { $0["path"] as? String == "source/.remote.md.icloud" && $0["local"] as? Bool == false })
    precondition(!rows(blocked).contains { ($0["path"] as! String).hasPrefix("source/link/") })
    // Unknown artifacts remain where they were; inspection is never cleanup.
    precondition(fm.fileExists(atPath: root.appendingPathComponent("source/.linefold-note-move-unrecognized").path))
  }
  try fixture { root in
    try directory(root, "source")
    try file(root, "source/only.bmp")
    requireClean(inspect(root), count: 2)
  }
}

private func verifyDirectoryPackageClassification() throws {
  try fixture { root in
    // Empty synthetic packages intentionally contain no Info.plist/executable.
    // Inspection must reject their known directory type without reading bodies
    // or instantiating Bundle/resourceValues to validate an application's code.
    let names = ["Application.app", "Resources.bundle", "Library.framework", "Uppercase.APP"]
    for name in names { try directory(root, "source/" + name + "/empty") }
    let value = inspect(root)
    has(value, "packageMember", complete: true)
    let packagePaths = Set((value["issues"] as! [[String: String]]).compactMap {
      $0["code"] == "packageMember" ? $0["path"] : nil
    })
    precondition(packagePaths == Set(names.map { "source/" + $0 }),
                 "Every known package/bundle type must block, including uppercase extensions")
    for name in names {
      let path = "source/" + name
      let source = inspect(root, path)
      has(source, "packageMember", complete: true)
      precondition(source["sourceState"] as? String == "directory")
      precondition(rows(source).count == 2)
      precondition(rows(source).contains { $0["path"] as? String == path + "/empty" },
                   "Blocking a package must not silently skip its members")
    }
    // A directory-constrained dynamic type is not itself proof of a package.
    // Constraining the lookup to .package would falsely block this ordinary tree.
    try directory(root, "ordinary.linefold-unknown-directory-type/empty")
    requireClean(inspect(root, "ordinary.linefold-unknown-directory-type"), count: 2)
  }
}

private func verifySourceAndRootStates() throws {
  try fixture { root in
    let missing = inspect(root)
    has(missing, "sourceMissing", complete: false)
    precondition(missing["sourceState"] as? String == "missing")
    try file(root, "source")
    let regular = inspect(root)
    has(regular, "sourceNotDirectory", complete: false)
    precondition(regular["sourceState"] as? String == "notDirectory")
    for path in ["", "/source", "../source", "source/../other", "source//child", "source/."] {
      has(inspect(root, path), "invalidPath", complete: false)
    }
    let absentRoot = inspect(root.appendingPathComponent("no-root"))
    precondition(absentRoot["sourceState"] as? String == "unavailable")
    precondition(absentRoot["complete"] as? Bool == false)
  }
  try fixture { root in
    try directory(root, "real/source")
    try fm.createSymbolicLink(at: root.appendingPathComponent("alias"), withDestinationURL: root.appendingPathComponent("real"))
    precondition(inspect(root.appendingPathComponent("alias"))["complete"] as? Bool == false)
    has(inspect(root, "alias/source"), "invalidAncestor", complete: false)
    try fm.createSymbolicLink(at: root.appendingPathComponent("source"), withDestinationURL: root.appendingPathComponent("real/source"))
    has(inspect(root), "sourceNotDirectory", complete: false)
  }
  try fixture { root in
    try directory(root, "StoredCase")
    let alias = inspect(root, "storedcase")
    if fm.fileExists(atPath: root.appendingPathComponent("storedcase").path) {
      has(alias, "unsupportedPath", complete: false)
      precondition(alias["sourceState"] as? String == "directory")
    } else {
      has(alias, "sourceMissing", complete: false)
    }
  }
  try fixture { root in
    try file(root, ".source.icloud")
    let offline = inspect(root)
    has(offline, "offline", complete: false)
    precondition(offline["sourceState"] as? String == "unavailable", "Placeholder cannot prove a directory or absence")
  }
  try fixture { root in
    try directory(root, "source")
    precondition(chmod(root.path, 0) == 0)
    defer { _ = chmod(root.path, 0o700) }
    if geteuid() != 0 {
      let denied = inspect(root)
      has(denied, "permissionDenied", complete: false)
      precondition(denied["sourceState"] as? String == "unavailable")
    }
  }
  try fixture { root in
    try directory(root, "source")
    let restricted = root.appendingPathComponent("source").path
    precondition(chmod(restricted, 0) == 0)
    defer { _ = chmod(restricted, 0o700) }
    if geteuid() != 0 {
      has(inspect(root), "permissionDenied", complete: false)
    } else {
      print("SKIP: chmod permission-denial fixture cannot deny a root test process")
    }
  }
}

private func verifyBudgetsAndCancellation() throws {
  try fixture { root in
    try directory(root, "source/sub/empty")
    for index in 0..<6 { try file(root, "source/file\(index).md") }
    has(inspect(root, limits: WorkspaceDirectoryMoveInspectionLimits(entries: 2)), "entryLimit", complete: false)
    let limited = inspect(root, limits: WorkspaceDirectoryMoveInspectionLimits(entries: 2))
    precondition(rows(limited).count == 2 && (limited["observedEntryCount"] as? Int) == 3)
    has(inspect(root, limits: WorkspaceDirectoryMoveInspectionLimits(directories: 1)), "directoryLimit", complete: false)
    has(inspect(root, limits: WorkspaceDirectoryMoveInspectionLimits(metadataBytes: 1)), "metadataLimit", complete: false)
    has(inspect(root, cancellation: WorkspaceDirectoryMoveInspectionCancellation(deadline: .now())), "deadlineExceeded", complete: false)
    let cancelled = WorkspaceDirectoryMoveInspectionCancellation()
    cancelled.cancel()
    has(inspect(root, cancellation: cancelled), "cancelled", complete: false)
    let inFlight = WorkspaceDirectoryMoveInspectionCancellation()
    has(inspect(root, cancellation: inFlight, afterDirectory: { _ in inFlight.cancel() }), "cancelled", complete: false)
    // Production ceiling, including the source directory, is not just a test
    // injection limit. No successful prefix is returned at 257 observations.
    try directory(root, "wide")
    for index in 0..<256 { try file(root, "wide/\(index).md") }
    let wide = inspect(root, "wide")
    has(wide, "entryLimit", complete: false)
    precondition(rows(wide).count == 256 && (wide["observedEntryCount"] as? Int) == 257)
    try directory(root, "many-folders")
    for index in 0..<64 { try directory(root, "many-folders/child\(index)") }
    let folders = inspect(root, "many-folders")
    has(folders, "directoryLimit", complete: false)
    precondition(rows(folders).count == 64 && (folders["observedEntryCount"] as? Int) == 65)
  }
  let registry = WorkspaceDirectoryMoveInspectionRegistry()
  let first = UUID().uuidString
  let second = UUID().uuidString
  let one = try registry.register(first)
  let two = try registry.register(second)
  do { _ = try registry.register(UUID().uuidString); fatalError("Unbounded token admission") } catch { }
  do { _ = try registry.register(first); fatalError("Duplicate request ID admitted") } catch { }
  precondition(registry.cancel(first.lowercased()) && one.isCancelled)
  registry.finish(first, cancellation: two)
  do { _ = try registry.register(first); fatalError("Wrong token removed another request") } catch { }
  registry.finish(first, cancellation: one)
  precondition(!registry.cancel(first))
  let replacement = try registry.register(first)
  registry.finish(first, cancellation: one)
  precondition(registry.cancel(first) && replacement.isCancelled)
  registry.finish(first, cancellation: replacement)
  registry.finish(second, cancellation: two)
}

private func verifyRequestAndFailureEnvelopeBounds() throws {
  try fixture { root in
    let id = UUID().uuidString
    let huge = String(repeating: "x", count: 2 * 1024 * 1024)
    precondition(CloudWorkspace.isValidWorkspaceDirectoryMoveInspectionRequest(
      rootPath: root.path, relativePath: "source", requestId: id
    ))
    for path in [huge, "", "/source", "source/../other", "source//child"] {
      precondition(!CloudWorkspace.isValidWorkspaceDirectoryMoveInspectionRequest(
        rootPath: root.path, relativePath: path, requestId: id
      ), "Invalid paths must be rejected before queue/token admission")
    }
    precondition(!CloudWorkspace.isValidWorkspaceDirectoryMoveInspectionRequest(
      rootPath: "/" + huge, relativePath: "source", requestId: id
    ))
    precondition(!CloudWorkspace.isValidWorkspaceDirectoryMoveInspectionRequest(
      rootPath: root.path, relativePath: "source", requestId: huge
    ))
    let oversizedSource = inspect(root, huge)
    has(oversizedSource, "invalidPath", complete: false)
    precondition(oversizedSource["sourcePath"] as? String == "")
    let oversizedSourceBytes = try JSONSerialization.data(withJSONObject: oversizedSource)
    precondition(oversizedSourceBytes.count < 4096)

    // Helper callers bypass channel validation. All early-exit envelopes must
    // stay bounded, including exits occurring before request validation itself.
    let hugeRoot = URL(fileURLWithPath: "/" + huge, isDirectory: true)
    let cancelled = WorkspaceDirectoryMoveInspectionCancellation()
    cancelled.cancel()
    let tokens = [WorkspaceDirectoryMoveInspectionCancellation(), cancelled,
                  WorkspaceDirectoryMoveInspectionCancellation(deadline: .now())]
    for (token, expected) in zip(tokens, ["invalidRequest", "cancelled", "deadlineExceeded"]) {
      let value = CloudWorkspace.inspectWorkspaceDirectoryMoveTree(
        hugeRoot, relativePath: huge, requestId: huge, cancellation: token
      )
      has(value, expected, complete: false)
      precondition(value["root"] as? String == "" && value["sourcePath"] as? String == "" && value["requestId"] as? String == "")
      let encoded = try JSONSerialization.data(withJSONObject: value)
      precondition(encoded.count < 4096)
    }

    // This path is 1 KiB raw UTF-8 but over 6 KiB as JSON. Echoing it both in
    // sourcePath and the terminal issue exceeds the 8 KiB synthetic budget.
    let escaped = String(repeating: "\u{0001}", count: 1024)
    let value = inspect(root, escaped, limits: WorkspaceDirectoryMoveInspectionLimits(metadataBytes: 8000))
    has(value, "invalidPath", complete: false)
    precondition((value["issues"] as! [[String: String]]).last?["path"] == nil,
                 "Terminal diagnostic paths must be charged after JSON escaping")
    let encoded = try JSONSerialization.data(withJSONObject: value)
    precondition(encoded.count <= 8000)
  }
}

private func verifyRaces() throws {
  try fixture { root in
    try directory(root, "source/child")
    var changed = false
    let result = inspect(root, afterDirectory: { path in
      if path == "source/child" && !changed {
        changed = true
        try file(root, "source/child/new.md")
      }
    })
    has(result, "treeChanged", complete: false)
  }
  try fixture { root in
    try directory(root, "parent/source/child")
    var changed = false
    let result = inspect(root, "parent/source", afterDirectory: { _ in
      if !changed {
        changed = true
        try fm.moveItem(at: root.appendingPathComponent("parent"), to: root.appendingPathComponent("displaced"))
        try directory(root, "parent/source/child")
      }
    })
    has(result, "treeChanged", complete: false)
  }
  try fixture { outer in
    try directory(outer, "root/source")
    let root = outer.appendingPathComponent("root", isDirectory: true)
    let result = inspect(root, afterDirectory: { _ in
      try fm.moveItem(at: root, to: outer.appendingPathComponent("old-root"))
      try directory(outer, "root/source")
    })
    has(result, "treeChanged", complete: false)
  }
  try fixture { root in
    try directory(root, "source")
    try file(root, "source/note.md")
    let result = inspect(root, afterDirectory: { _ in
      // File-body metadata changes need not change the parent directory mtime.
      try Data("a longer replacement".utf8).write(to: root.appendingPathComponent("source/note.md"))
    })
    has(result, "treeChanged", complete: false)
  }
}

private func verifyConcurrentCancellation() throws {
  try fixture { root in
    try directory(root, "source")
    let registry = WorkspaceDirectoryMoveInspectionRegistry()
    let scheduler = WorkspaceReadScheduler()
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let requestId = UUID().uuidString
    let token = try registry.register(requestId)
    var completionCount = 0
    var outcome: [String: Any]?
    precondition(scheduler.execute(kind: .directory, operation: { () -> [String: Any] in
      defer { registry.finish(requestId, cancellation: token) }
      return inspect(root, cancellation: token, afterDirectory: { _ in
        entered.signal()
        precondition(release.wait(timeout: .now() + 5) == .success)
      })
    }, completion: { value in
      precondition(Thread.isMainThread)
      completionCount += 1
      outcome = try? value.get()
    }))
    precondition(entered.wait(timeout: .now() + 5) == .success)
    // This control action must complete while directory I/O is still held.
    precondition(registry.cancel(requestId) && token.isCancelled)
    release.signal()
    let end = Date().addingTimeInterval(5)
    while completionCount == 0 && Date() < end {
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    precondition(completionCount == 1)
    has(outcome!, "cancelled", complete: false)
    precondition(!registry.cancel(requestId), "Finished token leaked")
  }
}
