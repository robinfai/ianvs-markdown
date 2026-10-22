# P0 save and recovery safety

This phase hardens explicit Markdown saves and workspace recovery. It does not
add autosave of original Markdown files, version history, automatic merge, or
sync-completion guarantees.

## Save contract

A save captures the editor text at request time. The target must still contain
its last saved baseline; a new/Save As destination must not already exist.
Filesystem watcher delivery is not the authority for this check.

If the target changed or was deleted, the host offers:

- **Cancel:** leave the disk, document identity, and saved baseline unchanged.
- **Keep Both:** keep the external file untouched and save the captured local
  version as a uniquely named `local copy` sibling. The tab follows the copy;
  edits made after the save request remain dirty. When only the original file
  has been granted sandbox access, a save panel requests permission for the copy
  instead of assuming permission to create siblings. Cancelling leaves the draft
  untouched; an occupied selected destination is checked again for conflicts.
- **Overwrite:** replace only the exact external version observed by the
  conflict. A further external change requires another decision. For a deleted
  target this explicitly recreates the original path.

Apple source reads, guarded write payloads, and conflict versions use UTF-8
byte buffers across the method channel. This prevents its String decoder from
dropping leading BOMs and keeps the saved baseline byte-exact.

The Apple host validates and atomically replaces inside the same
`NSFileCoordinator` writing claim. This serializes participating coordinated
writers, not arbitrary applications that ignore file coordination. The portable
Dart host stages/flushed bytes and validates immediately before atomic rename;
portable Dart does not provide an OS-level atomic compare-and-replace, so an
uncoordinated writer can still race that last comparison. Neither host falls
back to truncating the original when atomic replacement fails. Read/access or
invalid-text errors fail closed, rather than being treated as deletion.

## Recovery contract

The application still persists recovery snapshots separately from Markdown
files. `workspace.json.bak` retains a validated complete snapshot before the
primary file is atomically replaced. A first save creates a valid backup too.
The primary and backup are validated before use or rotation. A malformed record
cannot silently become an empty draft or disappear from the restored list.

Loading is read-only. A valid backup can recover a missing/damaged primary,
with a visible notice. Before a later repair replaces corrupt readable bytes,
they are copied byte-for-byte to a unique `workspace.json.corrupt-*/original`
(or backup equivalent) directory. Unreadable originals are never overwritten.
If neither recovery copy can be used, startup shows a retry screen rather than
creating and persisting Welcome. Background recovery failures show a persistent
retry banner; normal exit still waits for recovery storage and cancels on error.

The guarantee is flushed snapshot files, atomic rename, and retention of a valid
backup. This is not a directory-fsync/power-loss guarantee, multi-process session
locking, or a historical-version archive. Corruption archives are preserved for
manual inspection, not silently deleted.

## Verification

Focused automated scenarios are in:

- `app/test/save_conflict_test.dart`
- `app/test/guarded_markdown_file_service_test.dart`
- `app/test/recovery_failure_test.dart`
- `app/test/workspace_session_store_safety_test.dart`
- `app/test/file_watcher_save_test.dart`, existing save-race and exit tests
- `app/test/native_guarded_save_test.swift` on macOS

Tests use in-memory files or isolated temporary directories, never user notes.
Linux Dart/widget tests do not certify Apple sandbox access, real iCloud sync,
or macOS UI behavior. Native integration CI and real-device acceptance remain
separate evidence.
