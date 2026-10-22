import Foundation

@main
struct SyncMetadataAcceptance {
  static func main() throws {
    verifyBoundedReadScheduling()
    let now = Date(timeIntervalSince1970: 1234)
    let missing = WorkspaceSyncObservation().dictionary(observedAt: now)
    assert(missing["isUploaded"] == nil)
    assert(missing["isUploading"] == nil)
    assert(missing["isUbiquitous"] == nil)
    assert(missing["observedAt"] as? Double == 1234000)
    for status in [URLUbiquitousItemDownloadingStatus.current, .downloaded, .notDownloaded] {
      let value = WorkspaceSyncObservation(
        isUbiquitous: true, isUploaded: false, isUploading: true,
        downloadingStatus: status, uploadError: "Synthetic offline error",
        hasUnresolvedConflicts: true,
        conflictsAvailable: true,
        conflicts: [["name": "Synthetic version", "modified": 1000.0]]
      ).dictionary(observedAt: now)
      assert(value["isUploaded"] as? Bool == false)
      assert(value["isUploading"] as? Bool == true)
      assert(value["downloadingStatus"] as? String == (status == .current ? "current" : status == .downloaded ? "downloaded" : "notDownloaded"))
      assert(value["uploadError"] as? String == "Synthetic offline error")
      assert((value["conflicts"] as? [[String: Any]])?.count == 1)
    }
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("linefold-sync-metadata-\(UUID().uuidString)")
    try fm.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: root) }
    let document = root.appendingPathComponent("sample.md")
    let sibling = root.appendingPathComponent("do-not-read.md")
    let bytes = Data([0xEF, 0xBB, 0xBF] + Array("# Local fixture\r\n".utf8))
    try bytes.write(to: document)
    try Data([0xFF, 0x00]).write(to: sibling)
    let before = try fm.attributesOfItem(atPath: document.path)
    let observed = try CloudWorkspace.readSyncMetadata(document)
    assert(observed["observedAt"] is Double)
    assert(observed["isUbiquitous"] as? Bool != true)
    let documentAfter = try Data(contentsOf: document)
    let siblingAfter = try Data(contentsOf: sibling)
    assert(documentAfter == bytes)
    assert(siblingAfter == Data([0xFF, 0x00]))
    let after = try fm.attributesOfItem(atPath: document.path)
    assert(before[.modificationDate] as? Date == after[.modificationDate] as? Date)
    let names = try fm.contentsOfDirectory(atPath: root.path).sorted()
    assert(names == ["do-not-read.md", "sample.md"])
    let link = root.appendingPathComponent("link.md")
    try fm.createSymbolicLink(at: link, withDestinationURL: document)
    do { _ = try CloudWorkspace.readSyncMetadata(link); fatalError("Expected symlink rejection") } catch { }
    print("PASS: bounded isolated native reads, exactly-once main completions, throw recovery, nullable metadata, transfer flags, conflicts, download statuses, read-only active local metadata and symlink rejection")
  }
}

// Exercise the same scheduler used by the channel without a Flutter messenger,
// provider account, document materialization, user vault or real write operation.
private func verifyBoundedReadScheduling() {
  for method in ["defaultDirectory", "writeDocument", "writeDocumentGuarded", "createWorkspaceNote", "readWorkspaceTextBytes"] {
    precondition(WorkspaceReadScheduler.Kind(method: method) == nil,
                 "Writes and other existing queues must stay outside the read scheduler")
  }
  verifySlowBodyIsolation()
  for (methods, capacity) in [(["readDocument", "readDocumentBytes"], 8),
                              (["listDirectory"], 2), (["readDocumentSyncMetadata"], 2)] {
    let scheduler = WorkspaceReadScheduler()
    // Reuse each lane after both a throwing operation and a successful one.
    // Refilling the entire capacity catches leaked budgets, not just one slot.
    verifyBoundedReadBurst(scheduler, methods: methods, capacity: capacity, throwFirst: true)
    verifyBoundedReadBurst(scheduler, methods: methods, capacity: capacity, throwFirst: false)
  }
}

private func verifySlowBodyIsolation() {
  let scheduler = WorkspaceReadScheduler()
  let events = ReadQueueEvents()
  let entered = DispatchSemaphore(value: 0)
  let release = DispatchSemaphore(value: 0)
  let bodyAccepted = submitRead(scheduler, events: events, id: 0, method: "readDocumentBytes") {
    entered.signal()
    waitForSignal(release, "Blocked synthetic body was not released")
    return 0
  }
  precondition(bodyAccepted)
  waitForSignal(entered, "Body worker did not start")
  let nextBodyAccepted = submitRead(scheduler, events: events, id: 1, method: "readDocument") { 1 }
  precondition(nextBodyAccepted)
  let listAccepted = submitRead(scheduler, events: events, id: 2, method: "listDirectory") { 2 }
  let metadataAccepted = submitRead(scheduler, events: events, id: 3, method: "readDocumentSyncMetadata") { 3 }
  precondition(listAccepted && metadataAccepted)

  // The production write/transaction queue is not handed to the scheduler.
  // Model that separate existing queue without touching any document bytes.
  let existingWriteQueue = DispatchQueue(label: "linefold.test.existing-write")
  let writerFinished = DispatchSemaphore(value: 0)
  existingWriteQueue.async { writerFinished.signal() }
  waitForSignal(writerFinished, "Body reads occupied an unrelated write queue")
  runMainUntil("Independent list and metadata did not complete") {
    let completed = events.snapshot().completions
    return completed[2] == 1 && completed[3] == 1
  }
  let stalled = events.snapshot()
  precondition(stalled.executions == [0: 1, 2: 1, 3: 1],
               "Body reads must remain serial even across the two method names")
  precondition(stalled.completions[0] == nil && stalled.completions[1] == nil)
  release.signal()
  runMainUntil("Body requests did not finish after release") { events.snapshot().completions.count == 4 }
  let finished = events.snapshot()
  precondition(finished.executions == [0: 1, 1: 1, 2: 1, 3: 1])
  precondition(finished.completions == [0: 1, 1: 1, 2: 1, 3: 1])
}

private func verifyBoundedReadBurst(_ scheduler: WorkspaceReadScheduler, methods: [String],
                                    capacity: Int, throwFirst: Bool) {
  let events = ReadQueueEvents()
  let entered = DispatchSemaphore(value: 0)
  let release = DispatchSemaphore(value: 0)
  let firstAccepted = submitRead(scheduler, events: events, id: 0, method: methods[0]) {
    entered.signal()
    waitForSignal(release, "Bounded synthetic read was not released")
    if throwFirst { throw SyntheticReadError.failed }
    return 0
  }
  precondition(firstAccepted)
  waitForSignal(entered, "Bounded read worker did not start")
  for id in 1..<capacity {
    let accepted = submitRead(scheduler, events: events, id: id, method: methods[id % methods.count]) { id }
    precondition(accepted, "Lane rejected an operation below its capacity")
  }
  let burstCount = 128
  // Model retries after Dart has timed out/discarded a still-running request.
  // None may acquire another slot or enqueue its operation once the lane is full.
  for id in capacity..<(capacity + burstCount) {
    let accepted = submitRead(scheduler, events: events, id: id, method: methods[id % methods.count]) { id }
    precondition(!accepted, "Lane exceeded its running-plus-queued bound")
  }
  runMainUntil("Busy requests waited behind blocked native I/O") {
    events.snapshot().completions.count == burstCount
  }
  let stalled = events.snapshot()
  precondition(stalled.executions == [0: 1], "Rejected or serially queued work executed early")
  for id in capacity..<(capacity + burstCount) {
    precondition(stalled.completions[id] == 1)
    guard case .failure(let error)? = stalled.outcomes[id] else {
      preconditionFailure("Overflow did not complete with an error")
    }
    precondition(error as? WorkspaceReadQueueError == .busy)
  }
  release.signal()
  runMainUntil("Accepted read completions did not drain") {
    events.snapshot().completions.count == capacity + burstCount
  }
  let finished = events.snapshot()
  precondition(finished.executions.count == capacity, "Overflow requests reached the worker queue")
  for id in 0..<(capacity + burstCount) {
    precondition(finished.completions[id] == 1, "Completion was not exactly once")
    if id < capacity {
      precondition(finished.executions[id] == 1)
      if id == 0 && throwFirst {
        guard case .failure(let error)? = finished.outcomes[id] else {
          preconditionFailure("Synthetic throwing read unexpectedly succeeded")
        }
        precondition(error is SyntheticReadError)
      } else {
        guard case .success(let value)? = finished.outcomes[id] else {
          preconditionFailure("Accepted read unexpectedly failed")
        }
        precondition(value == id)
      }
    }
  }
}

private func submitRead(_ scheduler: WorkspaceReadScheduler, events: ReadQueueEvents,
                        id: Int, method: String, operation: @escaping () throws -> Int) -> Bool {
  guard let kind = WorkspaceReadScheduler.Kind(method: method) else {
    preconditionFailure("Unknown synthetic read method")
  }
  return scheduler.execute(kind: kind, operation: {
    precondition(!Thread.isMainThread, "Native I/O must run off the main thread")
    events.recordExecution(id)
    return try operation()
  }, completion: { outcome in
    precondition(Thread.isMainThread, "Success, failure and busy must complete on main")
    events.recordCompletion(id, outcome: outcome)
  })
}

private func waitForSignal(_ signal: DispatchSemaphore, _ message: String) {
  let result = signal.wait(timeout: .now() + 10)
  precondition(result == .success, message)
}

private func runMainUntil(_ message: String, condition: () -> Bool) {
  precondition(Thread.isMainThread)
  let deadline = Date().addingTimeInterval(10)
  while !condition() && Date() < deadline {
    // The standalone native executable has no Flutter event loop. Pump its
    // main run loop so production main-queue completions can be observed.
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
  }
  precondition(condition(), message)
}

private enum SyntheticReadError: Error {
  case failed
}

private final class ReadQueueEvents: @unchecked Sendable {
  struct Snapshot {
    var executions: [Int: Int] = [:]
    var completions: [Int: Int] = [:]
    var outcomes: [Int: Result<Int, Error>] = [:]
  }

  private let lock = NSLock()
  private var state = Snapshot()

  func recordExecution(_ id: Int) {
    lock.lock()
    defer { lock.unlock() }
    state.executions[id, default: 0] += 1
  }

  func recordCompletion(_ id: Int, outcome: Result<Int, Error>) {
    lock.lock()
    defer { lock.unlock() }
    state.completions[id, default: 0] += 1
    state.outcomes[id] = outcome
  }

  func snapshot() -> Snapshot {
    lock.lock()
    defer { lock.unlock() }
    return state
  }
}
