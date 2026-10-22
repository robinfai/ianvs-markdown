# Explicit attachment import native gate

Run `make test-native-attachments` on macOS with Flutter and Xcode installed.
The existing `check-integrations` CI job runs both native attachment suites
against the actual FlutterMacOS module. The existing unsigned
`build-ios-preview` simulator CI job compiles the shared Apple writer while the
AppKit picker/clipboard implementation is excluded with `#if os(macOS)`.
These are build and fixture-test gates, not a publication step.

`native_attachment_import_test.swift` uses temporary directories and synthetic
PNG/TIFF data and clipboard-provider closures. It does not invoke the open panel
or read/write the machine's real clipboard.

Covered policy:

- Inspect actual image type and dimensions through ImageIO before any pixel
  decode or destination mutation; maximum 32 MiB encoded, 32 Mi pixels per frame,
  and 256 frames. Imports preserve supported PNG/JPEG/GIF/WebP/BMP bytes. TIFF
  screenshots with at most 8 Mi pixels, 16,384 pixels per side and known 1–8-bit
  channels convert frame 0 to PNG using a capped
  output consumer. Wider TIFF channels and unsupported formats fail closed.
- Prefer an advertised PNG to TIFF. Only supported image UTI bytes are requested.
  File URLs, remote URLs and ordinary text are never read by this bridge. An
  advertised but unsupported/failed image is an error, not a text fallback.
- The picker grants only the selected file. Its read does not require opening
  or listing the parent directory, preserves the source, refuses symlink/non-file
  leaves and provider stubs, bounds reads, and verifies identity/revision after
  reading while the selected security scope is held.
- Import settings use a dedicated `readAttachmentImportSettings({path})` method:
  only `.obsidian/app.json`, at most 64 KiB, pinned descriptor-relative no-follow
  reads with root/file revision checks. It never coordinates or requests a
  provider download; preview image/config reading behavior is unchanged. Fixture
  coverage includes local/missing/stub/symlink/pipe/permission/size cases and a
  held coordinator claim to verify the import reader does not wait on it. Only
  explicitly confirmed parent/config absence returns `attachment_missing`;
  a missing vault or disappearance/replacement after observing config is a
  failure, never permission to default the destination to the vault root.
  The dedicated parent preflight rejects `SF_DATALESS` and the parent marker
  `..obsidian.icloud`. `UF_HIDDEN` is deliberately permitted on the selected
  root and the exact `.obsidian/app.json` directory/leaf, not arbitrary paths.
  Dataless directory-state coverage injects synthetic stat metadata into the
  same policy helper; it does not simulate a real iCloud provider.
- The writer rejects hidden/traversal/symlink/offline/read-only destinations;
  missing visible directories are created only during the explicit import.
  Descriptor-relative `openat` uses exclusive creation and no-follow semantics.
  Known case/NFC names and iCloud placeholders are checked before creation.
  A concurrently won mkdir fails closed instead of adopting the directory.
- Existing names are never overwritten. Observed root, parent and file
  replacement fails closed. Deterministic race hooks are test-only and cannot be
  called through the platform channel.
- Once exclusive file creation succeeds, subsequent failure returns
  `details: {relativePath: ..., fileMayRemain: true}`. Partial files, completed
  files, concurrently replaced files and directories are never deleted as
  rollback. The editor must not insert markup on failure.

Limitations requiring macOS UI/device acceptance:

- NSOpenPanel cancellation, file-only sandbox scope and source permissions.
- Explicit Paste with screenshots from other applications, including delayed
  pasteboard providers. AppKit has no size-limited `data(forType:)` API, so the
  32 MiB input cap is checked immediately after the selected representation is
  delivered; TIFF decoding and PNG output are bounded separately.
- iCloud dataless/offline providers, ACLs, read-only mounted volumes and actual
  signed app entitlements. Synthetic placeholder and mode-bit cases do not
  substitute for provider/device behavior.
- File coordination and repeated identity checks detect observed interference,
  not absolute race immunity against uncoordinated third-party writers. A pinned
  parent renamed outside the vault can retain an uncertain created file. A
  differently cased concurrent name can race a preflight check on a case-sensitive
  filesystem. Neither permits overwrite of an existing exact basename.

On Linux, shell syntax and diff checks can run; neither Swift/AppKit fixture
execution nor Apple platform compilation should be reported as passing without
Xcode/macOS evidence.
