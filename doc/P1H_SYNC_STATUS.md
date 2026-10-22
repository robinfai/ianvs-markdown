# P1h: truthful document status and active iOS refresh

## Contract

Local saving, recovery storage, and cloud observations are independent:

- `Saved locally` means the captured source snapshot completed the existing
  guarded local-write path. It does **not** mean uploaded or received elsewhere.
- `Edited`/`Draft` can show recovery pending/saved/failed. A recovery copy is
  current only when both text and saved baseline match the successfully written
  session snapshot. Saving A while typing B leaves B edited.
- `Saving locally`, local-save failure, and disk conflicts retain the existing
  cancellation/conflict flow. There is no new autosave, overwrite, conflict
  resolution, or deletion policy.
- The cloud label is an optional, separate observation for the active document.
  Unsupported providers, absent keys, failures to obtain metadata, observations
  over 30 seconds old, and future-dated samples are unknown. Missing metadata
  never proves offline, local-only, or uploaded.
- Explicit upload/download errors, in-progress flags, pending states and conflict
  flags come from Apple resource values. `iCloud reports uploaded` deliberately
  does not certify a particular local revision or another device's receipt.
- A metadata request times out after five seconds. Expiry changes the label to
  unknown without polling. Change notifications coalesce over 500 ms. Target
  generations invalidate old completions, including A → B → A. Cancel/dispose
  releases the Dart wait; it does not claim to cancel native work.

## Native boundary and permissions

`readDocumentSyncMetadata(path)` reads URL resource values for only that already
selected file. It does not read file contents, enumerate directories, invoke the
full-text index, start downloads, establish a container/security scope, alter
sharing or resolve/delete versions. A dedicated utility queue prevents status
reads from waiting behind a document materialization. Resource cache values are
cleared before sampling. Non-ubiquitous items stay unknown because they may be
managed by an unsupported third-party provider.

Native body, directory-list and metadata reads use independent serial bounded
lanes, capped at 8, 2 and 2 outstanding operations respectively (running plus
queued). Saturation returns a retryable `workspace_busy` result rather than adding
unlimited work after cancelled/timed-out Dart callers; a blocked body does not
occupy list, metadata or existing write/transaction queues. Accepted operations
still may wait on the operating system's provider coordination. The bounds do not
claim to terminate in-flight `NSFileCoordinator` or arbitrary provider I/O.
Incoming path strings/options are immutable snapshots and completions return on
main. File URLs are constructed only inside admitted workers: the default URL
initializer can query the filesystem to infer directory-ness, so main-thread
admission performs no such conversion. Workers do not acquire scope or read/write
monitor/root configuration. Each body operation creates its own file coordinator
and uses it on one thread. Guarded
write coordination and its original transaction queue are unchanged.

When Apple reports unresolved conflicts, the bridge lists up to 50 existing
`NSFileVersion` records (display name and optional modification date only). It
never fetches nonlocal versions or reads their bodies. Missing version details
are explicitly unavailable, not an empty guarantee of no conflicts.

The existing authorized workspace metadata observer batches notifications; the
new code only refreshes the selected document's status. The full-text index
keeps its existing local-only/materialization policy.

## iOS preview refresh

Manual refresh, resume and coalesced workspace notifications reread the active
body, not just the library list. Refresh reads do not rewrite recent history.
Body and list are independently bounded concurrent operations. Their outcomes
commit separately: a successful body remains visible if listing fails, while a
failed or invalid body leaves the displayed text unchanged and does not suppress
a successful list refresh. Retry and cancel-wait controls are available. Each body/list operation
has a 15-second wait limit. New navigation, library dismissal, workspace changes
(including A → B → A), cancellation and disposal reject old results. Cancelling
a folder picker preserves the current displayed document. Same-document refresh
opts into preserving the current scroll position, including user scrolling while
the read was pending; shorter content clamps normally. Different document/scope
keys reset the reader. Existing heading-identity fold retention remains intact.

Native reads and picker side effects cannot actually be cancelled. Request
invalidation prevents their late results from replacing the current Dart state.
This is not a claim of cross-device convergence or real-device acceptance.

## Apple API evidence

Official documentation checked for this implementation:

- [File URL initializers may inspect the filesystem](https://developer.apple.com/documentation/foundation/nsurl/init(fileurlwithpath:))
- [Explicit directory hints avoid that filesystem probe](https://developer.apple.com/documentation/foundation/url/init(fileurlwithpath:isdirectory:))
- [File-coordinator lifecycle and threading](https://developer.apple.com/documentation/foundation/nsfilecoordinator)
- [File manager thread safety](https://developer.apple.com/documentation/foundation/filemanager)
- [Avoiding blocked file-provider work on UI threads](https://developer.apple.com/documentation/foundation/improving-performance-and-stability-when-accessing-the-file-system)
- [URLResourceValues.isUbiquitousItem](https://developer.apple.com/documentation/foundation/urlresourcevalues/isubiquitousitem)
- [URLResourceValues.ubiquitousItemIsUploaded](https://developer.apple.com/documentation/foundation/urlresourcevalues/ubiquitousitemisuploaded)
- [Upload-status key and change notification guidance](https://developer.apple.com/documentation/foundation/urlresourcekey/ubiquitousitemisuploadedkey)
- [Download states](https://developer.apple.com/documentation/foundation/urlubiquitousitemdownloadingstatus)
- [Upload errors](https://developer.apple.com/documentation/foundation/urlresourcevalues/ubiquitousitemuploadingerror)
- [Download request](https://developer.apple.com/documentation/foundation/filemanager/startdownloadingubiquitousitem(at:))
- [Unresolved version records](https://developer.apple.com/documentation/foundation/nsfileversion/unresolvedconflictversionsofitem(at:))
- [Version resolution is a separate mutation](https://developer.apple.com/documentation/foundation/nsfileversion/isresolved)

The download-start API initiates download; it is not upload completion. The
`current` download value is the newest version known **to the device**, not proof
that every device has the same revision. The existing native coordinated-write
completion confirms the local write only. No local completion callback is
converted into cloud-upload success.

## Verification

Synthetic Dart tests cover local/recovery states, save A/input B, failures/retry,
missing metadata, explicit offline error, stale and future observations, conflict
listing, request timeout, scope ABA, active-path-only requests, source contracts
that prohibit download/write calls, and 320px/3× status details. Preview tests
exercise manual/cloud/resume body changes, invalid input, list/read failures,
retry/cancel, picker cancellation, scope races and recent-history preservation.

`make test-native-sync-metadata` compiles the actual shared Apple bridge against
the real FlutterMacOS framework, tests nullable synthetic observations and reads
only temporary local fixtures. Synthetic blocked-body tests prove list/metadata
progress independently, write/default/create routing stays excluded, saturation
rejects 128 retries per lane, callbacks occur exactly once on main, and budgets
are reusable after successful or throwing operations. These are fixtures, not
real-provider or native-cancellation acceptance. The test is included in
`check-integrations`. Both the
macOS native workflow and unsigned iOS simulator build must pass for the reviewed
commit. Linux tests cannot certify Apple compilation or actual iCloud behavior.

Unsupported metadata providers retain a visible unknown label with disabled
reads and retry; they do not allocate deadline, refresh, or expiry timers. Compact
labels use at most two visual lines, while full semantics and the details dialog
retain the complete status. The desktop footer stays a single horizontally
scrollable line, with persistence/cloud state before statistics, so a short 3×
window retains usable document height without clipping away status details.
