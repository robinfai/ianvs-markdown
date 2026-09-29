import AppKit

@main
struct WorkspaceFileAcceptance {
  static func main() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("linefold-file-tests-\(UUID().uuidString)")
    try fm.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: root) }
    func run(_ method: String, _ path: String, _ destination: String? = nil, folder: Bool = false) throws -> String? {
      var args: [String: Any] = ["path": path, "directory": folder, "contents": "# Original"]
      if let destination { args["destination"] = destination }
      return try WorkspaceFileOperations.perform(method, arguments: args)
    }
    func rejects(_ body: () throws -> String?) {
      do { _ = try body(); fatalError("Expected operation to fail") } catch { }
    }
    let folder = root.appendingPathComponent("notes").path
    _ = try run("createEntry", folder, folder: true)
    rejects { try run("createEntry", folder, folder: true) }
    let original = folder + "/设计.md"
    _ = try run("createEntry", original)
    rejects { try run("createEntry", original) }
    let copy = folder + "/copy.md"
    _ = try run("copyEntry", original, copy)
    rejects { try run("moveEntry", original, copy) }
    let contents = try String(contentsOfFile: original, encoding: .utf8)
    assert(contents == "# Original")
    let moved = root.appendingPathComponent("moved").path
    rejects { try run("moveEntry", folder, folder + "/nested") }
    _ = try run("moveEntry", folder, moved)
    assert(!fm.fileExists(atPath: folder))
    assert(fm.fileExists(atPath: moved + "/设计.md"))
    let trashed = try run("trashEntry", moved)
    assert(!fm.fileExists(atPath: moved))
    guard let trashed else { fatalError("Trash location missing") }
    assert(fm.fileExists(atPath: trashed + "/copy.md"))
    // Restore only the test fixture, proving Trash is recoverable; defer removes it.
    try fm.moveItem(atPath: trashed, toPath: folder)
    assert(fm.fileExists(atPath: original))
    print("PASS: exclusive create, Unicode, copy, collision, descendant move, directory move, Trash and restore")
  }
}
