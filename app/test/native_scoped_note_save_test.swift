import Foundation
import Darwin
import FlutterMacOS

@main
struct ScopedNoteSaveTests {
  static func main() throws {
    let manager = FileManager.default
    let sandbox = manager.temporaryDirectory.appendingPathComponent("linefold-scoped-save-\(UUID().uuidString)")
    let root = sandbox.appendingPathComponent("notes")
    let outside = sandbox.appendingPathComponent("outside")
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    try manager.createDirectory(at: outside, withIntermediateDirectories: false)
    defer { try? manager.removeItem(at: sandbox) }
    let target = root.appendingPathComponent("设计.md")
    // The channel contract exposes the descriptor-derived native root. System
    // volume aliases need not equal Foundation's symlink-normalized URL spelling.
    let selection = try WorkspaceWriteAuthority().activate(root)
    let selectedTarget = URL(fileURLWithPath: selection["path"]!).appendingPathComponent("设计.md").path
    func bytes(_ url: URL) throws -> Data { try Data(contentsOf: url) }
    func check(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
      precondition(value, file: file, line: line)
    }
    func save(_ text: String, _ expected: String?) throws {
      try CloudWorkspace.writeWorkspaceNoteGuarded(root, relativePath: "设计.md", contents: text, expectedContents: expected)
    }
    func rejects(_ operation: () throws -> Void) {
      do { try operation(); preconditionFailure("Expected a fail-closed error") } catch {}
    }
    func conflict(expected: String?, current: String?) throws {
      do {
        try save("my draft", expected)
        preconditionFailure("Expected scoped save conflict")
      } catch let failure as WorkspaceSaveConflict {
        let foundationTarget = root.resolvingSymlinksInPath().appendingPathComponent("设计.md").path
        let observedBytesMatch = failure.currentContents.map { Data($0.utf8) } == current.map { Data($0.utf8) }
        var paths = [root.path, root.resolvingSymlinksInPath().path, selection["path"]!,
                     target.path, foundationTarget, selectedTarget, failure.path]
        paths += paths.compactMap { path -> String? in
          if path.hasPrefix("/private/var/") { return String(path.dropFirst("/private".count)) }
          if path.hasPrefix("/var/") { return "/private" + path }
          return nil
        }
        var evidence = "Synthetic conflict paths: origin=\(target.path), actual=\(failure.path), foundation=\(foundationTarget), nativeSelected=\(selectedTarget), observedBytesMatch=\(observedBytesMatch)\n"
        for path in Set(paths).sorted() {
          do {
            let attributes = try manager.attributesOfItem(atPath: path)
            evidence += "path=\(path) device=\(String(describing: attributes[.systemNumber])) inode=\(String(describing: attributes[.systemFileNumber])) type=\(String(describing: attributes[.type])) size=\(String(describing: attributes[.size]))\n"
          } catch {
            evidence += "path=\(path) metadataError=\(error)\n"
          }
        }
        // stderr is flushed before a trapping assertion; stdout may be buffered.
        FileHandle.standardError.write(Data(evidence.utf8))
        precondition(observedBytesMatch)
        precondition(Data(failure.path.utf8) == Data(selectedTarget.utf8),
                     "Conflict path must exactly match the native-selected target")
        if let current {
          let originalAttributes = try manager.attributesOfItem(atPath: target.path)
          let returnedAttributes = try manager.attributesOfItem(atPath: failure.path)
          for key in [FileAttributeKey.systemNumber, .systemFileNumber] {
            guard let original = originalAttributes[key] as? NSNumber,
                  let returned = returnedAttributes[key] as? NSNumber else {
              preconditionFailure("Expected filesystem identity for the synthetic conflict target")
            }
            precondition(original == returned, "Conflict must identify the original target inode")
          }
          check(try bytes(target) == Data(current.utf8))
          check(try bytes(URL(fileURLWithPath: failure.path)) == Data(current.utf8))
        } else {
          precondition(!manager.fileExists(atPath: target.path))
          precondition(!manager.fileExists(atPath: failure.path))
        }
      }
    }

    let original = "\u{FEFF}# Café\r\n中文 😀"
    try save(original, nil)
    check(try bytes(target) == Data(original.utf8))
    try conflict(expected: String(original.dropFirst()), current: original)
    try conflict(expected: original.replacingOccurrences(of: "é", with: "e\u{0301}"), current: original)
    try save(original + "\r\nEdited", original)
    check(try bytes(target) == Data((original + "\r\nEdited").utf8))
    try conflict(expected: nil, current: original + "\r\nEdited")
    try manager.removeItem(at: target)
    try conflict(expected: original, current: nil)
    try save("restored after explicit approval", nil)
    check(try bytes(target) == Data("restored after explicit approval".utf8))

    let valid = FlutterStandardTypedData(bytes: Data("valid".utf8))
    let invalidArguments: [[String: Any]] = [
      ["contentsBytes": valid],
      ["contentsBytes": "not bytes", "expectedContentsBytes": NSNull()],
      ["contentsBytes": valid, "expectedContentsBytes": "not bytes"],
      ["contentsBytes": FlutterStandardTypedData(bytes: Data([0xff])), "expectedContentsBytes": valid],
      ["contentsBytes": FlutterStandardTypedData(bytes: Data([0])), "expectedContentsBytes": valid],
      ["contentsBytes": FlutterStandardTypedData(bytes: Data(repeating: 65, count: 5 * 1024 * 1024 + 1)), "expectedContentsBytes": valid],
    ]
    for arguments in invalidArguments {
      rejects { try CloudWorkspace.writeWorkspaceNoteGuarded(root, relativePath: "设计.md", arguments: arguments) }
    }
    check(try bytes(target) == Data("restored after explicit approval".utf8))
    for relative in ["../escape.md", "/absolute.md", "nested/../escape.md", ".hidden.md", "not-markdown.png"] {
      rejects { try CloudWorkspace.writeWorkspaceNoteGuarded(root, relativePath: relative, contents: "draft", expectedContents: nil) }
    }
    rejects { try CloudWorkspace.writeWorkspaceNoteGuarded(root, relativePath: "missing/parent.md", contents: "draft", expectedContents: nil) }
    precondition(!manager.fileExists(atPath: root.appendingPathComponent("missing").path), "Scoped saves must not mkdir")

    try manager.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: outside)
    rejects { try CloudWorkspace.writeWorkspaceNoteGuarded(root, relativePath: "escape/note.md", contents: "draft", expectedContents: nil) }
    check(try manager.contentsOfDirectory(atPath: outside.path).isEmpty)
    try manager.removeItem(at: target)
    try manager.createSymbolicLink(at: target, withDestinationURL: outside.appendingPathComponent("missing.md"))
    rejects { try save("draft", nil) }
    _ = try manager.destinationOfSymbolicLink(atPath: target.path)
    try manager.removeItem(at: target)
    let placeholder = root.appendingPathComponent(".设计.md.icloud")
    try Data("stub".utf8).write(to: placeholder)
    rejects { try save("draft", nil) }
    precondition(!manager.fileExists(atPath: target.path))
    try manager.removeItem(at: placeholder)
    try Data([0xff]).write(to: target)
    rejects { try save("draft", nil) }
    check(try bytes(target) == Data([0xff]))
    try Data(repeating: 65, count: 5 * 1024 * 1024 + 1).write(to: target)
    rejects { try save("draft", nil) }

    // Deterministic uncoordinated writes between initial compare and commit.
    try Data("baseline".utf8).write(to: target)
    do {
      try CloudWorkspace.writeWorkspaceNoteGuarded(root, relativePath: "设计.md", contents: "my draft", expectedContents: "baseline", beforeCommit: {
        try Data("new external version".utf8).write(to: target, options: .atomic)
      })
      preconditionFailure("An intervening edit must conflict")
    } catch let failure as WorkspaceSaveConflict {
      precondition(failure.currentContents == "new external version")
    }
    check(try bytes(target) == Data("new external version".utf8))
    check(try !manager.contentsOfDirectory(atPath: root.path).contains(where: { $0.hasPrefix(".linefold-save-") }))
    try manager.removeItem(at: target)
    do {
      try CloudWorkspace.writeWorkspaceNoteGuarded(root, relativePath: "设计.md", contents: "my draft", expectedContents: nil, beforeCommit: {
        try Data("occupied".utf8).write(to: target)
      })
      preconditionFailure("An intervening creation must conflict")
    } catch let failure as WorkspaceSaveConflict { precondition(failure.currentContents == "occupied") }
    check(try bytes(target) == Data("occupied".utf8))

    // Missing-file recreation follows the same full-name collision policy as
    // explicit create, including aliases and provider stubs on sensitive disks.
    for (existing, desired) in [("Alias.md", "alias.md"), ("Café.md", "Cafe\u{0301}.md"), (".Stub.md.icloud", "stub.md")] {
      let alias = root.appendingPathComponent(existing)
      try Data("existing alias".utf8).write(to: alias)
      rejects { try CloudWorkspace.writeWorkspaceNoteGuarded(root, relativePath: desired, contents: "draft", expectedContents: nil) }
      check(try bytes(alias) == Data("existing alias".utf8))
      try manager.removeItem(at: alias)
    }
    let aliasLink = root.appendingPathComponent("AliasLink.md")
    try manager.createSymbolicLink(at: aliasLink, withDestinationURL: outside.appendingPathComponent("absent.md"))
    rejects { try CloudWorkspace.writeWorkspaceNoteGuarded(root, relativePath: "aliaslink.md", contents: "draft", expectedContents: nil) }
    _ = try manager.destinationOfSymbolicLink(atPath: aliasLink.path)
    rejects { try CloudWorkspace.createWorkspaceNote(root, relativePath: "aliaslink.md") }
    do {
      try WorkspaceTextScope(root).createNote(relativePath: "aliaslink.md")
      preconditionFailure("New must reject normalized symlink aliases")
    } catch AttachmentError.collision {}
    // The wrapper must refuse safely, but coordination can reject a symlink
    // before the scope runs. Assert the scan's exact error on the scope itself
    // to exercise it even on a default case-insensitive CI volume.
    check(try manager.destinationOfSymbolicLink(atPath: aliasLink.path) == outside.appendingPathComponent("absent.md").path)
    precondition(!manager.fileExists(atPath: outside.appendingPathComponent("absent.md").path))
    try manager.removeItem(at: aliasLink)
    for (existing, desired) in [("Alias.md", "alias.md"), ("Café.md", "Cafe\u{0301}.md"), (".Stub.md.icloud", "stub.md")] {
      let alias = root.appendingPathComponent(existing)
      try Data("existing alias".utf8).write(to: alias)
      do {
        try CloudWorkspace.createWorkspaceNote(root, relativePath: desired)
        preconditionFailure("New must use the full normalized name scan")
      } catch let failure as AttachmentError {
        precondition(failure == (existing.hasPrefix(".") ? .offline : .collision))
      }
      check(try bytes(alias) == Data("existing alias".utf8))
      try manager.removeItem(at: alias)
    }

    // Staging is authority only while its pathname still refers to our exact
    // descriptor and revision. Never replace a baseline with substituted bytes.
    func stageURL() throws -> URL {
      let names = try manager.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".linefold-save-") }
      precondition(names.count == 1)
      return root.appendingPathComponent(names[0])
    }
    try Data("baseline".utf8).write(to: target)
    var substituted: URL?
    rejects {
      try CloudWorkspace.writeWorkspaceNoteGuarded(root, relativePath: "设计.md", contents: "my draft", expectedContents: "baseline", beforeCommit: {
        let stage = try stageURL()
        try Data("attacker".utf8).write(to: stage, options: .atomic)
        substituted = stage
      })
    }
    check(try bytes(target) == Data("baseline".utf8))
    check(try bytes(substituted!) == Data("attacker".utf8))
    try manager.removeItem(at: substituted!) // Test cleanup, never production cleanup of another inode.
    rejects {
      try CloudWorkspace.writeWorkspaceNoteGuarded(root, relativePath: "设计.md", contents: "my draft", expectedContents: "baseline", beforeCommit: {
        try Data("attacker".utf8).write(to: stageURL())
      })
    }
    check(try bytes(target) == Data("baseline".utf8))
    check(try !manager.contentsOfDirectory(atPath: root.path).contains(where: { $0.hasPrefix(".linefold-save-") }))

    // A same-length change after commit must not be reported as a successful
    // save of the captured draft, even when the target inode is unchanged.
    rejects {
      try CloudWorkspace.writeWorkspaceNoteGuarded(root, relativePath: "设计.md", contents: "my draft", expectedContents: "baseline", afterCommit: {
        try Data("external".utf8).write(to: target)
      })
    }
    check(try bytes(target) == Data("external".utf8))
    try manager.removeItem(at: target)
    rejects {
      try CloudWorkspace.writeWorkspaceNoteGuarded(root, relativePath: "设计.md", contents: "my draft", expectedContents: nil, afterCommit: {
        try Data("external".utf8).write(to: target)
      })
    }
    check(try bytes(target) == Data("external".utf8))

    try verifyCoordinatorAliases(sandbox: sandbox)
    try verifyCoordinatedConflict(root: root, target: target)

    let directory = root.appendingPathComponent("folder")
    let moved = outside.appendingPathComponent("moved")
    try manager.createDirectory(at: directory, withIntermediateDirectories: false)
    try Data("baseline".utf8).write(to: directory.appendingPathComponent("note.md"))
    rejects {
      try CloudWorkspace.writeWorkspaceNoteGuarded(root, relativePath: "folder/note.md", contents: "my draft", expectedContents: "baseline", beforeCommit: {
        try manager.moveItem(at: directory, to: moved)
        try manager.createDirectory(at: directory, withIntermediateDirectories: false)
        try Data("replacement".utf8).write(to: directory.appendingPathComponent("note.md"))
      })
    }
    check(try bytes(moved.appendingPathComponent("note.md")) == Data("baseline".utf8))
    check(try bytes(directory.appendingPathComponent("note.md")) == Data("replacement".utf8))

    // Native grants are session-only epochs, not path equality. A -> B -> A
    // invalidates the original token; a pending write prevents any root switch.
    let authority = WorkspaceWriteAuthority()
    let a = try authority.activate(root)
    let lease = try authority.admit(path: a["path"]!, token: a["workspaceToken"]!)
    try lease.validate()
    do { _ = try authority.activate(outside); preconditionFailure("Pending writes must retain their root") }
    catch WorkspaceWriteAuthorityError.busy {}
    lease.finish()
    lease.finish() // Idempotent completion and deinit must not underflow.
    do {
      let failed = try authority.admit(path: a["path"]!, token: a["workspaceToken"]!)
      defer { failed.finish() }
      try CloudWorkspace.writeWorkspaceNoteGuarded(root, relativePath: "../escape.md", contents: "draft", expectedContents: nil,
                                                  validateAuthority: { try failed.validate() })
      preconditionFailure("Invalid scoped request must fail")
    } catch {}
    _ = try authority.activate(outside)
    let a2 = try authority.activate(root)
    rejects { _ = try authority.admit(path: a["path"]!, token: a["workspaceToken"]!) }
    rejects { _ = try authority.admit(path: outside.path, token: a2["workspaceToken"]!) }
    let fresh = try authority.admit(path: a2["path"]!, token: a2["workspaceToken"]!)
    let renamed = sandbox.appendingPathComponent("renamed-notes")
    try manager.moveItem(at: root, to: renamed)
    try manager.createDirectory(at: root, withIntermediateDirectories: false)
    rejects { try fresh.validate() }
    fresh.finish()
    print("PASS: scoped note saves, raw UTF-8, conflicts, exclusive absence, root/parent/symlink fences, bounds, file coordination and native epoch leases")
  }

  static func verifyCoordinatorAliases(sandbox: URL) throws {
    let manager = FileManager.default
    let root = sandbox.appendingPathComponent("callback-vault")
    let folder = root.appendingPathComponent("folder")
    let target = folder.appendingPathComponent("note.md")
    try manager.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("unchanged".utf8).write(to: target)
    let scope = try WorkspaceNoteWriteScope(root)
    let parent = try scope.parentDescriptor(["folder", "note.md"])
    defer { close(parent) }
    func reject(_ url: URL, _ relative: String = "folder/note.md") {
      do {
        try scope.verifyCoordinatedURL(url, relativePath: relative, parentDescriptor: parent)
        preconditionFailure("Coordinator redirect must not authorize another spelling/target: \(url)")
      } catch {}
    }
    let ancestor = sandbox.appendingPathComponent("callback-ancestor")
    try manager.createSymbolicLink(at: ancestor, withDestinationURL: sandbox)
    let aliasedRoot = ancestor.appendingPathComponent("callback-vault")
    for spelling in [root, scope.rootURL, aliasedRoot] {
      for relative in ["folder/note.md", "folder/missing.md"] {
        try scope.verifyCoordinatedURL(spelling.appendingPathComponent(relative),
                                        relativePath: relative, parentDescriptor: parent)
      }
    }
    // Same inode is insufficient: planned components must remain byte exact.
    let alternate = folder.appendingPathComponent("alternate.md")
    try manager.linkItem(at: target, to: alternate)
    reject(alternate)
    reject(folder.appendingPathComponent("NOTE.md"))
    reject(folder.appendingPathComponent("Cafe\u{0301}.md"), "folder/Café.md")
    let rootLink = sandbox.appendingPathComponent("callback-root-link")
    try manager.createSymbolicLink(at: rootLink, withDestinationURL: root)
    reject(rootLink.appendingPathComponent("folder/note.md"))
    let inner = root.appendingPathComponent("folder-link")
    try manager.createSymbolicLink(at: inner, withDestinationURL: folder)
    reject(inner.appendingPathComponent("note.md"), "folder-link/note.md")
    let leaf = folder.appendingPathComponent("leaf.md")
    try manager.createSymbolicLink(at: leaf, withDestinationURL: target)
    reject(leaf, "folder/leaf.md")
    let directoryLeaf = folder.appendingPathComponent("directory.md")
    try manager.createDirectory(at: directoryLeaf, withIntermediateDirectories: false)
    reject(directoryLeaf, "folder/directory.md")
    var extra = URLComponents(url: target, resolvingAgainstBaseURL: false)!
    extra.query = "redirect=1"; reject(extra.url!)
    extra.query = nil; extra.fragment = "redirect"; reject(extra.url!)
    extra.fragment = nil; extra.host = "localhost"; reject(extra.url!)
    reject(URL(string: root.absoluteString + "/folder/%2e%2e/folder/note.md")!)
    let foreign = sandbox.appendingPathComponent("callback-foreign/folder/note.md")
    try manager.createDirectory(at: foreign.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("unchanged".utf8).write(to: foreign)
    reject(foreign)
    // A replaced parent or root cannot inherit a pre-coordination descriptor.
    try manager.moveItem(at: folder, to: sandbox.appendingPathComponent("callback-old-parent"))
    try manager.createDirectory(at: folder, withIntermediateDirectories: false)
    try Data("unchanged".utf8).write(to: target)
    reject(target)
    do {
      try scope.writeNote(relativePath: "folder/note.md", contents: "must not write", expectedContents: "unchanged",
                          coordinatedParent: parent)
      preconditionFailure("A callback-to-commit parent replacement must not rebind the pinned write")
    } catch {}
    let unchangedOld = try Data(contentsOf: sandbox.appendingPathComponent("callback-old-parent/note.md"))
    let unchangedNew = try Data(contentsOf: target)
    precondition(unchangedOld == Data("unchanged".utf8) && unchangedNew == unchangedOld)
    try manager.moveItem(at: root, to: sandbox.appendingPathComponent("callback-old-root"))
    try manager.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("unchanged".utf8).write(to: target)
    reject(target)
    let bytes = try Data(contentsOf: target)
    precondition(bytes == Data("unchanged".utf8))

    // Deterministically replace the parent after callback validation but before
    // writeNote starts. Identical bytes must not make the new directory inherit
    // the earlier coordination claim or pinned parent authority.
    let movedAfterValidation = sandbox.appendingPathComponent("callback-after-validation")
    var validations = 0
    do {
      try CloudWorkspace.writeWorkspaceNoteGuarded(root, relativePath: "folder/note.md",
        contents: "must not write", expectedContents: "unchanged", validateAuthority: {
          validations += 1
          if validations == 2 {
            try manager.moveItem(at: folder, to: movedAfterValidation)
            try manager.createDirectory(at: folder, withIntermediateDirectories: false)
            try Data("unchanged".utf8).write(to: target)
          }
        })
      preconditionFailure("The callback-to-write window must not rebind parent identity")
    } catch {}
    precondition(validations >= 3, "The fixture must reach writeNote after callback validation")
    let oldBytes = try Data(contentsOf: movedAfterValidation.appendingPathComponent("note.md"))
    let newBytes = try Data(contentsOf: target)
    precondition(oldBytes == Data("unchanged".utf8) && newBytes == oldBytes)
  }

  static func verifyCoordinatedConflict(root: URL, target: URL) throws {
    try Data("baseline".utf8).write(to: target)
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let writerFinished = DispatchSemaphore(value: 0)
    let saverStarted = DispatchSemaphore(value: 0)
    let saverFinished = DispatchSemaphore(value: 0)
    let writer = ScopedSaveOutcome()
    let saver = ScopedSaveOutcome()
    DispatchQueue.global().async {
      var coordinationError: NSError?
      var writeError: Error?
      NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordinationError) { coordinated in
        do { try Data("coordinated external edit".utf8).write(to: coordinated, options: .atomic) }
        catch { writeError = error }
        entered.signal()
        precondition(release.wait(timeout: .now() + 10) == .success)
      }
      if let coordinationError { writer.store(coordinationError) }
      else { writer.store(writeError) }
      writerFinished.signal()
    }
    precondition(entered.wait(timeout: .now() + 10) == .success)
    DispatchQueue.global().async {
      saverStarted.signal()
      do {
        try CloudWorkspace.writeWorkspaceNoteGuarded(root, relativePath: "设计.md", contents: "my draft", expectedContents: "baseline")
        saver.store(nil)
      } catch { saver.store(error) }
      saverFinished.signal()
    }
    precondition(saverStarted.wait(timeout: .now() + 10) == .success)
    let early = saverFinished.wait(timeout: .now() + 0.2)
    release.signal()
    precondition(writerFinished.wait(timeout: .now() + 10) == .success)
    precondition(early == .timedOut, "Scoped save escaped another writer's coordination claim")
    precondition(saverFinished.wait(timeout: .now() + 10) == .success)
    if let error = writer.load() { throw error }
    guard let conflict = saver.load() as? WorkspaceSaveConflict else {
      let observed = saver.load()
      FileHandle.standardError.write(Data("Concurrent save actual outcome=\(String(reflecting: observed))\n".utf8))
      let selection = try WorkspaceWriteAuthority().activate(root)
      let expected = URL(fileURLWithPath: selection["path"]!).appendingPathComponent("设计.md")
      var evidence = "Concurrent save outcome=\(String(reflecting: observed)), original=\(target.path), nativeSelected=\(expected.path)\n"
      var probeError: NSError?
      let probe = NSFileCoordinator()
      let cancelProbe = DispatchWorkItem { probe.cancel() }
      DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: cancelProbe)
      defer { cancelProbe.cancel() }
      probe.coordinate(writingItemAt: expected, options: [], error: &probeError) { coordinated in
        evidence += "Subsequent coordination probe requested=\(expected.path), returned=\(coordinated.path)\n"
        for url in [target, expected, coordinated] {
          do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let data = try Data(contentsOf: url)
            evidence += "path=\(url.path) device=\(String(describing: attributes[.systemNumber])) inode=\(String(describing: attributes[.systemFileNumber])) bytes=\(data.base64EncodedString())\n"
          } catch { evidence += "path=\(url.path) error=\(error)\n" }
        }
      }
      evidence += "Subsequent coordination probe error=\(String(reflecting: probeError))\n"
      FileHandle.standardError.write(Data(evidence.utf8))
      preconditionFailure("Expected coordinated conflict")
    }
    precondition(conflict.currentContents == "coordinated external edit")
    let selection = try WorkspaceWriteAuthority().activate(root)
    let selectedTarget = URL(fileURLWithPath: selection["path"]!).appendingPathComponent("设计.md")
    precondition(conflict.path.utf8.elementsEqual(selectedTarget.path.utf8))
    let returned = try Data(contentsOf: URL(fileURLWithPath: conflict.path))
    precondition(returned == Data("coordinated external edit".utf8))
    let bytes = try Data(contentsOf: target)
    precondition(bytes == Data("coordinated external edit".utf8))
  }
}

private final class ScopedSaveOutcome: @unchecked Sendable {
  private let lock = NSLock()
  private var error: Error?
  func store(_ value: Error?) { lock.lock(); defer { lock.unlock() }; error = value }
  func load() -> Error? { lock.lock(); defer { lock.unlock() }; return error }
}
