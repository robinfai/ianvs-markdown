import Foundation
import Darwin
import FlutterMacOS

@main struct MobileManagementTests {
  static func main() throws {
    let manager = FileManager.default
    let sandbox = manager.temporaryDirectory.appendingPathComponent("linefold-mobile-\(UUID().uuidString)")
    try manager.createDirectory(at: sandbox, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: sandbox) }
    let authority = WorkspaceWriteAuthority()
    let selection = try authority.activate(sandbox)
    let root = URL(fileURLWithPath: selection["path"]!)
    func operation(_ kind: String, _ path: String, _ destination: String? = nil) throws {
      FileHandle.standardError.write(Data("operation \(kind) \(path)\n".utf8))
      let lease = try authority.admit(path: root.path, token: selection["workspaceToken"]!)
      defer { lease.finish() }
      var args: [String: Any] = ["operation": kind, "relativePath": path]
      if let destination { args["destination"] = destination }
      try CloudWorkspace.manageWorkspaceEntry(root, arguments: args, validateAuthority: lease.validate)
    }
    func check(_ value: Bool) { precondition(value) }
    func rejects(_ body: () throws -> Void) {
      do { try body(); preconditionFailure("Expected rejection") } catch {}
    }
    try operation("createDirectory", "Notes")
    try operation("createDirectory", "Notes/Nested")
    try Data("# exact\r\n".utf8).write(to: root.appendingPathComponent("Notes/Nested/a.md"))
    try Data([1, 2, 3]).write(to: root.appendingPathComponent("Notes/Nested/asset.png"))
    try operation("copy", "Notes", "Copy")
    check(try Data(contentsOf: root.appendingPathComponent("Copy/Nested/asset.png")) == Data([1, 2, 3]))
    try operation("move", "Copy", "Renamed")
    precondition(!manager.fileExists(atPath: root.appendingPathComponent("Copy").path))
    rejects { try operation("move", "Renamed", "Notes") }
    rejects { try operation("copy", "Notes", "Notes/Child") }
    rejects { try operation("createDirectory", "../escape") }
    rejects { try operation("trash", "") }
    try manager.createSymbolicLink(atPath: root.appendingPathComponent("link").path, withDestinationPath: root.appendingPathComponent("Notes").path)
    rejects { try operation("createDirectory", "link/escape") }
    try manager.createSymbolicLink(atPath: root.appendingPathComponent("Notes/link").path, withDestinationPath: root.appendingPathComponent("Renamed").path)
    rejects { try operation("copy", "Notes", "UnsafeCopy") }
    precondition(!manager.fileExists(atPath: root.appendingPathComponent("UnsafeCopy").path))

    let other = root.appendingPathComponent("Other")
    try manager.createDirectory(at: other, withIntermediateDirectories: false)
    let grants = WorkspaceOperationGrants()
    let selectedOther = try grants.activate(other)
    let destinationLease = try grants.admit(path: selectedOther["path"]!, token: selectedOther["workspaceToken"]!)
    try CloudWorkspace.manageWorkspaceEntry(root, arguments: ["operation": "move", "relativePath": "Renamed", "destinationRoot": selectedOther["path"]!, "destination": "Moved"], validateAuthority: destinationLease.validate)
    destinationLease.finish()
    precondition(manager.fileExists(atPath: other.appendingPathComponent("Moved/Nested/a.md").path))
    rejects { _ = try grants.admit(path: root.path, token: selectedOther["workspaceToken"]!) }
    let recovery = root.appendingPathComponent("SyntheticTrash")
    try manager.createDirectory(at: recovery, withIntermediateDirectories: false)
    try CloudWorkspace.manageWorkspaceEntry(root, arguments: ["operation": "trash", "relativePath": "Other/Moved"], trash: { source in
      try manager.moveItem(at: source, to: recovery.appendingPathComponent(source.lastPathComponent))
    })
    precondition(!manager.fileExists(atPath: other.appendingPathComponent("Moved").path))
    precondition(manager.fileExists(atPath: recovery.appendingPathComponent("Moved/Nested/a.md").path))

    let target = root.appendingPathComponent("conflict.md")
    try Data("disk\r\n".utf8).write(to: target)
    var resolved = Set<AnyHashable>()
    var delayConfirmation = false
    var remote = "remote\r\n"
    var includeNewVersion = false
    let conflicts = CloudConflictSessions(versions: { _ in
      var records = [CloudConflictVersionRecord(id: "cloud-a", name: "Other device", modified: nil, read: { Data(remote.utf8) }, resolve: { resolved.insert("cloud-a") })]
      if includeNewVersion { records.append(CloudConflictVersionRecord(id: "cloud-b", name: "New device", modified: nil, read: { Data("new".utf8) }, resolve: { resolved.insert("cloud-b") })) }
      return records.filter { delayConfirmation || !resolved.contains($0.id) }
    })
    let args: [String: Any] = ["relativePath": "conflict.md", "workspaceToken": "capability"]
    func review() throws -> [String: Any] { try conflicts.inspect(root, arguments: args) }
    func resolve(_ review: [String: Any], choice: String = "0") throws -> [String: Any] {
      var request = args
      request["session"] = review["session"]
      request["choice"] = choice
      request["localContents"] = FlutterStandardTypedData(bytes: Data("unsaved draft".utf8))
      return try conflicts.resolve(root, arguments: request)
    }
    FileHandle.standardError.write(Data("conflict review\n".utf8))
    let first = try review()
    try Data("new disk".utf8).write(to: target)
    rejects { _ = try resolve(first) }
    precondition(resolved.isEmpty)
    let second = try review()
    includeNewVersion = true
    rejects { _ = try resolve(second) }
    includeNewVersion = false
    let third = try review()
    remote = "changed remote"
    rejects { _ = try resolve(third) }
    precondition(resolved.isEmpty)
    FileHandle.standardError.write(Data("conflict commit\n".utf8))
    let fourth = try review()
    let result = try resolve(fourth)
    check(try Data(contentsOf: target) == Data(remote.utf8))
    precondition(resolved == ["cloud-a"])
    let copies = result["copies"] as! [String]
    let contents = try copies.map { try Data(contentsOf: root.appendingPathComponent($0)) }
    precondition(Set(contents) == Set([Data("new disk".utf8), Data("unsaved draft".utf8)]))
    rejects { _ = try resolve(fourth) }
    resolved.removeAll()
    let all = try resolve(review(), choice: "keepAll")
    check(try Data(contentsOf: target) == Data("unsaved draft".utf8))
    precondition(!(all["copies"] as! [String]).isEmpty)
    resolved.removeAll()
    delayConfirmation = true
    let pending = try resolve(review(), choice: "0")
    precondition(pending["resolutionPending"] as? Bool == true)
    precondition(resolved == ["cloud-a"])
    check(try Data(contentsOf: target) == Data(remote.utf8))
    precondition(!(pending["copies"] as! [String]).isEmpty)
    print("PASS: delayed iCloud confirmation preserves content without reporting a failed resolution")
    print("PASS: mobile directory create/copy/move, collision and scope checks; cloud version selection, changed-review rejection and preserved disk/draft copies")
  }
}
