// Run with app/tool/test_native_file_association.sh. Every workspace operation
// is faked; these tests never change the user's real default applications.
import Cocoa

private final class FakeApplicationWorkspace: MarkdownApplicationWorkspace {
  static let linefold = URL(fileURLWithPath: "/linefold-tests/Linefold.app")
  static let editor = URL(fileURLWithPath: "/linefold-tests/Other Editor.app")
  static let replacement = URL(fileURLWithPath: "/linefold-tests/Replacement.app")
  var current: URL? = editor
  var available: Set<URL> = [editor, replacement, linefold]
  var changes: [URL] = []
  var rejectChange = false
  var applyChange = true
  var holdChange = false
  var heldCompletion: (() -> Void)?
  var selectedApplication: URL? = replacement
  var chooserCount = 0

  func defaultApplication() -> URL? { current }
  func applicationExists(_ application: URL) -> Bool { available.contains(application) }
  func chooseApplication(completion: @escaping (URL?) -> Void) {
    chooserCount += 1
    completion(selectedApplication)
  }
  func setDefaultApplication(_ application: URL, completion: @escaping (Error?) -> Void) {
    changes.append(application)
    let finish = {
      if self.rejectChange {
        completion(NSError(domain: "test", code: -54))
      } else {
        if self.applyChange { self.current = application }
        completion(nil)
      }
    }
    if holdChange { heldCompletion = finish } else { finish() }
  }
}

private struct TestFailure: Error, CustomStringConvertible {
  let description: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
  if !condition() { throw TestFailure(description: message) }
}

@main
private struct NativeFileAssociationTests {
  static func main() throws {
    try scenario("decline persists without changing the system") { defaults, workspace, association in
      try expect(association.state()["preferLinefold"] == nil, "Fresh installation must be undecided")
      association.setPreference(false) { error in precondition(error == nil) }
      let reloaded = MarkdownFileAssociation(defaults: defaults, workspace: workspace, applicationURL: FakeApplicationWorkspace.linefold)
      try expect(reloaded.state()["preferLinefold"] as? Bool == false, "Decline must survive controller recreation")
      try expect(workspace.changes.isEmpty, "Decline must preserve the current default")
    }
    try scenario("enable then disable restores the prior application") { defaults, workspace, association in
      association.setPreference(true) { error in precondition(error == nil) }
      try expect(association.state()["isDefault"] as? Bool == true, "Linefold should become default")
      let reloaded = MarkdownFileAssociation(defaults: defaults, workspace: workspace, applicationURL: FakeApplicationWorkspace.linefold)
      reloaded.setPreference(false) { error in precondition(error == nil) }
      try expect(workspace.current == FakeApplicationWorkspace.editor, "Original editor must be restored after restart")
      try expect(workspace.chooserCount == 0, "An available original editor needs no chooser")
    }
    try scenario("a denied change remembers intent and reports the actual association") { defaults, workspace, association in
      workspace.rejectChange = true
      var failure: Error?
      association.setPreference(true) { failure = $0 }
      try expect(failure != nil, "OS denial must be reported")
      try expect(association.state()["preferLinefold"] as? Bool == true, "Accepted intent must be saved even after denial")
      try expect(association.state()["isDefault"] as? Bool == false, "A denial must not report success")
      let reloaded = MarkdownFileAssociation(defaults: defaults, workspace: workspace, applicationURL: FakeApplicationWorkspace.linefold)
      _ = reloaded.state()
      try expect(workspace.changes.count == 1, "Reading persisted preferences must not retry")
    }
    try scenario("disabling respects a newer external default") { _, workspace, association in
      association.setPreference(true) { error in precondition(error == nil) }
      workspace.current = FakeApplicationWorkspace.replacement
      association.setPreference(false) { error in precondition(error == nil) }
      try expect(workspace.current == FakeApplicationWorkspace.replacement, "An external choice must win")
      try expect(workspace.changes.count == 1, "Disabling must not replace another current default")
    }
    try scenario("a missing original application opens a replacement chooser") { _, workspace, association in
      association.setPreference(true) { error in precondition(error == nil) }
      workspace.available.remove(FakeApplicationWorkspace.editor)
      association.setPreference(false) { error in precondition(error == nil) }
      try expect(workspace.chooserCount == 1, "Removed original editor requires another selection")
      try expect(workspace.current == FakeApplicationWorkspace.replacement, "Chosen editor should become default")
    }
    try scenario("canceling the replacement chooser preserves actual state") { _, workspace, association in
      workspace.current = FakeApplicationWorkspace.linefold
      workspace.selectedApplication = nil
      var failure: Error?
      association.setPreference(false) { failure = $0 }
      try expect(failure != nil, "Cancellation must be explained")
      try expect(association.state()["preferLinefold"] as? Bool == false, "Refusal must still be remembered")
      try expect(association.state()["isDefault"] as? Bool == true, "Cancelled removal must not pretend the default changed")
      try expect(workspace.changes.isEmpty, "A cancelled chooser must not change the association")
    }
    try scenario("a successful API reply is checked against the system") { _, workspace, association in
      workspace.applyChange = false
      var failure: Error?
      association.setPreference(true) { failure = $0 }
      try expect(failure != nil, "A no-op system reply must not report a changed default")
      try expect(association.state()["isDefault"] as? Bool == false, "System readback must remain authoritative")
    }
    try scenario("overlapping changes cannot overwrite an in-flight choice") { _, workspace, association in
      workspace.holdChange = true
      association.setPreference(true) { error in precondition(error == nil) }
      var failure: Error?
      association.setPreference(false) { failure = $0 }
      try expect(failure != nil, "A concurrent change must be rejected")
      try expect(association.state()["preferLinefold"] as? Bool == true, "An in-flight preference must stay intact")
      workspace.heldCompletion?()
      try expect(workspace.changes.count == 1, "Only one OS request is allowed")
    }
    let incoming = IncomingMarkdownFiles()
    incoming.receive([
      URL(fileURLWithPath: "/notes/First.MD"),
      URL(fileURLWithPath: "/notes/not-an-image.png"),
      URL(string: "https://example.com/readme.md")!,
    ])
    try expect(incoming.takePendingFiles() == ["/notes/First.MD"], "Cold-start queue must accept Markdown file URLs only")
    try expect(incoming.takePendingFiles().isEmpty, "A startup request must be drained once")
    var notifications = 0
    incoming.onFilesAvailable = { notifications += 1 }
    incoming.receive([URL(fileURLWithPath: "/notes/Second.md")])
    try expect(notifications == 1, "Live Finder opens must notify Flutter")
    try expect(incoming.takePendingFiles() == ["/notes/Second.md"], "Live requests must remain queued until Flutter is ready")
    print("PASS: queued and live Finder requests")
    print("9 native file-association scenarios passed.")
  }

  private static func scenario(
    _ name: String,
    _ body: (UserDefaults, FakeApplicationWorkspace, MarkdownFileAssociation) throws -> Void
  ) throws {
    let suite = "work.ianvs.linefold.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let workspace = FakeApplicationWorkspace()
    let association = MarkdownFileAssociation(defaults: defaults, workspace: workspace, applicationURL: FakeApplicationWorkspace.linefold)
    try body(defaults, workspace, association)
    print("PASS: \(name)")
  }
}
