import Foundation
import FlutterMacOS

@main
struct GuardedSaveTests {
  static func main() throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("linefold-guarded-save-\(UUID().uuidString)")
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: root) }
    let target = root.appendingPathComponent("设计.md")

    func write(_ text: String) throws { try Data(text.utf8).write(to: target) }
    func expectContents(_ text: String) throws {
      let bytes = try Data(contentsOf: target)
      precondition(bytes == Data(text.utf8), "Destination bytes changed unexpectedly")
    }
    func expectConflict(expected: String?, current: String?) throws {
      do {
        try CloudWorkspace.writeGuarded(target, contents: "mine", expectedContents: expected)
        preconditionFailure("Expected a save conflict")
      } catch let conflict as WorkspaceSaveConflict {
        precondition(conflict.path == target.path)
        precondition(conflict.expectedContents.map { Data($0.utf8) } == expected.map { Data($0.utf8) })
        precondition(conflict.currentContents.map { Data($0.utf8) } == current.map { Data($0.utf8) })
      }
      if let current { try expectContents(current) }
      else { precondition(!manager.fileExists(atPath: target.path)) }
    }
    func expectReadFailure(expected: String?) {
      do {
        try CloudWorkspace.writeGuarded(target, contents: "mine", expectedContents: expected)
        preconditionFailure("Expected an unreadable destination to fail closed")
      } catch is WorkspaceSaveConflict {
        preconditionFailure("An unreadable destination must not become a save conflict")
      } catch {}
    }

    try CloudWorkspace.writeGuarded(target, contents: "# First\r\n中文 😀", expectedContents: nil)
    try expectContents("# First\r\n中文 😀")
    try CloudWorkspace.writeGuarded(target, contents: "# Next", expectedContents: "# First\r\n中文 😀")
    try expectContents("# Next")
    try CloudWorkspace.write(target, contents: "legacy")
    try expectContents("legacy")

    try write("external 1")
    try expectConflict(expected: "baseline", current: "external 1")
    try expectConflict(expected: nil, current: "external 1")
    // Overwrite approval grants only the exact observed version. Another edit
    // before the retry must prompt another conflict, not a blanket overwrite.
    try write("external 2")
    try expectConflict(expected: "external 1", current: "external 2")
    try CloudWorkspace.writeGuarded(target, contents: "mine", expectedContents: "external 2")
    try expectContents("mine")

    try manager.removeItem(at: target)
    try expectConflict(expected: "mine", current: nil)
    try expectConflict(expected: "", current: nil)
    try CloudWorkspace.writeGuarded(target, contents: "", expectedContents: nil)
    try expectConflict(expected: nil, current: "")
    try CloudWorkspace.writeGuarded(target, contents: "empty baseline matched", expectedContents: "")

    let exact = "\u{FEFF}# Café\r\n中文 😀"
    try write(exact)
    let readBack = try CloudWorkspace.read(target)
    precondition(Data(readBack.utf8) == Data(exact.utf8), "BOM must survive native reads")
    try expectConflict(expected: String(exact.dropFirst()), current: exact)
    try expectConflict(expected: exact.replacingOccurrences(of: "é", with: "e\u{0301}"), current: exact)
    try expectConflict(expected: exact.replacingOccurrences(of: "\r\n", with: "\n"), current: exact)
    try CloudWorkspace.writeGuarded(target, contents: exact + "\r\nAdded", expectedContents: exact)
    try expectContents(exact + "\r\nAdded")

    // The channel uses typed bytes rather than Strings so Dart does not drop a
    // BOM. Exercise the same argument validation used by the native handler.
    try CloudWorkspace.writeGuarded(target, arguments: [
      "contentsBytes": FlutterStandardTypedData(bytes: Data(exact.utf8)),
      "expectedContentsBytes": FlutterStandardTypedData(bytes: Data((exact + "\r\nAdded").utf8)),
    ])
    try expectContents(exact)
    let validBytes = FlutterStandardTypedData(bytes: Data(exact.utf8))
    let invalidArguments: [[String: Any]] = [
      ["contentsBytes": validBytes],
      ["contentsBytes": validBytes, "expectedContentsBytes": exact],
      ["contentsBytes": exact, "expectedContentsBytes": validBytes],
      ["contentsBytes": FlutterStandardTypedData(bytes: Data([0xff])), "expectedContentsBytes": validBytes],
      ["contentsBytes": validBytes, "expectedContentsBytes": FlutterStandardTypedData(int32: Data([0, 0, 0, 0]))],
    ]
    for arguments in invalidArguments {
      do {
        try CloudWorkspace.writeGuarded(target, arguments: arguments)
        preconditionFailure("Malformed channel arguments must not authorize a save")
      } catch is WorkspaceSaveConflict {
        preconditionFailure("Malformed channel arguments must not become a conflict")
      } catch {}
      try expectContents(exact)
    }

    for bytes in [Data([0xff, 0xfe]), Data([0x23, 0, 0x41])] {
      try bytes.write(to: target)
      expectReadFailure(expected: nil)
      let after = try Data(contentsOf: target)
      precondition(after == bytes)
    }
    try manager.removeItem(at: target)
    try manager.createDirectory(at: target, withIntermediateDirectories: false)
    expectReadFailure(expected: nil)
    var isDirectory: ObjCBool = false
    precondition(manager.fileExists(atPath: target.path, isDirectory: &isDirectory) && isDirectory.boolValue)
    try manager.removeItem(at: target)
    try manager.createSymbolicLink(at: target, withDestinationURL: root.appendingPathComponent("missing.md"))
    expectReadFailure(expected: nil)
    _ = try manager.destinationOfSymbolicLink(atPath: target.path)
    try manager.removeItem(at: target)

    let linked = root.appendingPathComponent("linked.md")
    try Data("linked baseline".utf8).write(to: linked)
    try manager.createSymbolicLink(at: target, withDestinationURL: linked)
    expectReadFailure(expected: "linked baseline")
    _ = try manager.destinationOfSymbolicLink(atPath: target.path)
    let linkedBytes = try Data(contentsOf: linked)
    precondition(linkedBytes == Data("linked baseline".utf8))
    try manager.removeItem(at: target)
    try manager.removeItem(at: linked)

    let placeholder = root.appendingPathComponent(".\(target.lastPathComponent).icloud")
    try Data("evicted placeholder".utf8).write(to: placeholder)
    expectReadFailure(expected: nil)
    precondition(!manager.fileExists(atPath: target.path))
    precondition(manager.fileExists(atPath: placeholder.path))
    try manager.removeItem(at: placeholder)

    try write("read-protected")
    // macOS CI runs unprivileged. Root can bypass mode bits, so that environment
    // still exercises unreadable destinations above but cannot prove this case.
    if getuid() != 0 {
      try manager.setAttributes([.posixPermissions: 0], ofItemAtPath: target.path)
      expectReadFailure(expected: "read-protected")
      try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
      try expectContents("read-protected")
    }

    try verifyCoordinatedConflict(at: target)
    print("PASS: guarded native saves, exact source, deletion, creation, overwrite revalidation, UTF-8, read failures and file coordination")
  }

  /// The save must compare only after a preceding coordinated writer releases
  /// its claim, and the writer's newer version must survive the conflict.
  static func verifyCoordinatedConflict(at target: URL) throws {
    try Data("baseline".utf8).write(to: target)
    let writerEntered = DispatchSemaphore(value: 0)
    let releaseWriter = DispatchSemaphore(value: 0)
    let writerFinished = DispatchSemaphore(value: 0)
    let saveStarted = DispatchSemaphore(value: 0)
    let saveFinished = DispatchSemaphore(value: 0)
    let writerOutcome = LockedOutcome()
    let saveOutcome = LockedOutcome()
    DispatchQueue.global().async {
      var coordinationError: NSError?
      var writeError: Error?
      NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordinationError) { coordinated in
        do { try Data("coordinated external edit".utf8).write(to: coordinated, options: .atomic) }
        catch { writeError = error }
        writerEntered.signal()
        precondition(releaseWriter.wait(timeout: .now() + 10) == .success, "Save test failed to release coordinated writer")
      }
      if let coordinationError { writerOutcome.store(coordinationError) }
      else { writerOutcome.store(writeError) }
      writerFinished.signal()
    }
    precondition(writerEntered.wait(timeout: .now() + 10) == .success, "Writer did not acquire file coordination")
    DispatchQueue.global().async {
      saveStarted.signal()
      do {
        try CloudWorkspace.writeGuarded(target, contents: "mine", expectedContents: "baseline")
        saveOutcome.store(nil)
      } catch { saveOutcome.store(error) }
      saveFinished.signal()
    }
    precondition(saveStarted.wait(timeout: .now() + 10) == .success)
    let earlySave = saveFinished.wait(timeout: .now() + 0.2)
    releaseWriter.signal()
    precondition(writerFinished.wait(timeout: .now() + 10) == .success)
    precondition(earlySave == .timedOut, "Guarded save escaped another writer's coordination claim")
    precondition(saveFinished.wait(timeout: .now() + 10) == .success)
    if let error = writerOutcome.load() { throw error }
    guard let conflict = saveOutcome.load() as? WorkspaceSaveConflict else {
      preconditionFailure("Expected conflict after coordinated writer finished")
    }
    precondition(conflict.currentContents == "coordinated external edit")
    let bytes = try Data(contentsOf: target)
    precondition(bytes == Data("coordinated external edit".utf8))
  }
}

private final class LockedOutcome: @unchecked Sendable {
  private let lock = NSLock()
  private var error: Error?

  func store(_ value: Error?) {
    lock.lock()
    defer { lock.unlock() }
    error = value
  }

  func load() -> Error? {
    lock.lock()
    defer { lock.unlock() }
    return error
  }
}
