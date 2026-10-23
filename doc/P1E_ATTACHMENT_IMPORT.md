# P1e: explicit desktop image import, Paste and single-image drop

## User workflow

In the macOS editor, choose **File → Import Image…** or **Import image** above the
document. Select one local PNG, JPEG, GIF, WebP, BMP or TIFF image. The app copies
it, never moves or rewrites the source. TIFF screenshots are converted to PNG.
For screenshots, use the editor's normal **Paste**, Command-V or Control-V.
An image-only clipboard also has a Paste item in the source/live context menu.
No image clipboard read occurs on startup, focus change or a timer.

Drop one local PNG/JPEG/GIF/WebP/BMP/TIFF file onto the document to copy it to the
same configured attachment directory and insert a link at the **current caret**
(not the pointer's drop coordinates). The note must be in Live or Source mode
with a main-body edit target. TIFF is normalized to PNG, as with File Import.
Multiple images and mixed image/other-file drops are rejected as a whole; nothing
is imported or opened. Unsupported image formats are rejected. Markdown-only or
directory drops keep the existing open workflow. These decisions use the filename
only for routing; actual image bytes are validated before any destination write.

A drag must supply a temporary security-scoped file bookmark from the native
`desktop_drop` event. Its resolved path must exactly match the dropped path and
it must not be stale. The capability is held only for the bounded source read,
then released; it is not saved or widened to a directory. File promises and
other sources without a bookmark must use **Import Image** instead. There is no
path-only fallback. This first iteration intentionally imports only one image
per drop and does not collect image data from remote URLs or HTML drag content.

The note must already be saved inside the currently opened workspace. An unnamed
draft, individually opened note or note outside the workspace must first be saved
inside/opened with a workspace folder. The file picker does not grant access to
the source's parent, and opening one Markdown file does not authorize writes in
its parent. The app does not request an additional directory automatically.

The current vault's `.obsidian/app.json` is read immediately before import using
a dedicated, revision-checked local-only read. It never requests a settings
download or waits for file coordination. Only `attachmentFolderPath` is interpreted. The adapter maps:

| Stored field | New destination |
| --- | --- |
| Missing, empty string, `/` | Vault root |
| `assets/images` | That fixed path under the vault |
| `./` | Current note's folder |
| `./attachments` | That subfolder of the current note's folder |

A confirmed missing settings file also defaults to the vault root.
Null/non-string folder fields and unpaired UTF-16 surrogates are malformed. Malformed, inaccessible, nonlocal or
symlinked settings fail closed instead of silently choosing a different directory.
Hidden/escaping destination components are rejected, while the specific local
`.obsidian/app.json` configuration path is intentionally readable even when hidden. Missing destination folders are created only during this
explicit import. Existing images are not moved and Obsidian settings are never
written. These raw mappings are fixture-backed compatibility policy; they are
not a claim that a current Obsidian application has been exercised side by side.

## Source and failure contract

- Newly created files use generated, safe, unique `image-…` names and an extension
  detected from actual bytes. Collisions retry with a different name, at most
  eight times. The writer never overwrites an existing exact basename.
- The default inserted text is ordinary relative Markdown: `![](./image.png)` or
  `![](../assets/image.png)`. Every filename component is URL-encoded, including
  Unicode, literal `%`, spaces, brackets and parentheses. This default is fixed;
  the phase does not infer or rewrite a vault's preferred Wiki syntax.
- Source outside the selection is preserved. One Undo removes the inserted link,
  not the image file. Redo restores the link without writing another file.
- Validation, picker cancellation or write failure never inserts text. A failed
  post-create verification may retain a partial/completed file and reports its
  path; no rollback deletes a concurrent writer's data.
- Text, caret, composition, editor mode, active tab and workspace changes cancel
  stale insertion. Moving editor focus also cancels clipboard insertion. Once a
  write has succeeded, a stale result leaves the attachment intact and provides
  a persistent **Show link** notice with its path and original note. Dismissing
  that notice does not delete the attachment. Switching away and back does not
  revalidate the old operation. Recovery notices are session UI, not a durable
  import journal across app restart.
- Plain-text and smart URL Paste retain their previous behavior. Live table cells
  and properties retain their own local text Paste; switch to Source mode to
  paste an image there. File/toolbar import also requires a main-body/Source
  target, not a local table/property field whose caret may not map to source. No
  image is inserted into a table/property-local caret. Markdown-only drops
  retain the existing open-file workflow.

## Security and resource boundary

All destination IO is native, root-relative and no-follow. It uses file
coordination, descriptor-pinned directories, exclusive creation, and pre/post
identity checks. A raced `mkdir` is an error, not an adopted directory. Known
case/NFC aliases and logical cloud placeholders are rejected. Supported images
must pass real-format metadata validation and the same actual Flutter codec,
working-memory and pixel-admission policy used by existing previews before
writing. The import bridge has no remote download, file-URL clipboard or Dart
`File` fallback. See [native gates and limits](../app/test/NATIVE_ATTACHMENT_IMPORT.md).

This reduces accidental cross-scope IO, but is not absolute atomicity against an
uncoordinated process moving a pinned directory during a write. An observed
replacement fails and leaves uncertain data intact, possibly in a renamed parent.
`NSPasteboard.data(forType:)` has no bounded-read API: encoded-size validation
happens immediately after the selected representation is delivered. TIFF decode
is separately capped before allocating pixels.

## Verification

Synthetic fixtures only; no user vault or real clipboard contents are used.

- `cd app && flutter test --no-pub test/attachment_import_test.dart test/attachment_import_widgets_test.dart`
- Existing attachment resolver/repository/widget suites recheck byte/pixel and
  source-preserving preview behavior after import.
- `flutter test --no-pub test/paste_interception_test.dart` checks the opt-in core
  hook and ordinary text/URL fallback, context menus and stale input guards.
- `make test-native-attachments` runs read and import Swift fixture suites on
  macOS. `make build-ios-preview` compiles the shared native code for iOS.
- Required final gates are the actual candidate's Core, native macOS builds/tests
  and iOS compile CI. Linux cannot substitute for those Apple gates.

Still requiring device acceptance: native picker cancellation and file-only
security scope, screenshot interoperability with other apps, signed sandbox,
real iCloud/offline providers, sandboxed Finder drop/bookmark interoperability,
macOS/iOS deployment behavior. iOS already has a quick-note editor; this phase adds desktop-only image drop,
not iOS image import or image clipboard UI.
