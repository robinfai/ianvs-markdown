# Linefold

`app/` includes the macOS editor and an iOS reader with explicit Source quick editing. The normal
`lib/main.dart` entry point selects the iOS reader on iPhone/iPad and keeps the
existing desktop shell on macOS.

## Local iteration

The repository now uses two default entries: this application's `lib/main.dart`
and `example/lib/main.dart`. On macOS, start them with `make run-app` and
`make run-example` from the repository root. Use `make check-local` for core,
example/app and native regressions plus both Debug builds; use
`make build-local-release` for both Release builds. These targets do not install
over `/Applications` or require an independent acceptance host.

Current work follows the local file workflow in this app and the three-mode
component playground in example. Upstream AOT diagnostics and broader release
support remain recorded separately; they do not block this local iteration.
See [the execution checklist](../doc/R3_ACCEPTANCE.md) for save/reopen, recovery,
multiple-document, resource and input checks. Build success alone does not
claim those interactions passed.

## Document and workspace search

On Mac, **Command-F** searches the rendered body in Read and Live without
switching the editor surface. Use the **Body / Source** selector for literal
Markdown source search; replacement requires source editing. Next/previous
matches keep the query focused, and closing body search preserves the editing
selection and current viewport. Body indexing for documents of at least 64 Ki
UTF-16 code units runs in a background isolate. Documents rejected by the render
budget offer source search explicitly. External embeds and diagram source are
not part of body search.

On Mac, choose **Search source** in the sidebar or press **Command-Shift-F**
(**Control-Shift-F** also works). This is separate from filename search and searches
literal Markdown source, including code and front matter. Open unsaved buffers
always take precedence. Clicking a result opens its existing session and locates
it in the temporary Source Find view, without changing the document's mode or
saving it.

Only locally available documents inside the selected workspace and open buffers
are searched. Selecting one file does not grant a scan of its parent folder.
Search never downloads the entire iCloud library. Cloud-only, inaccessible,
changed, invalid UTF-8 or files over 5 MiB are reported as incomplete coverage.
Results show up to 500 snippets while counting continues. Use **Refresh metadata**
after provider changes; providers are not guaranteed to update live. Very large
or slow directory listings can also be incomplete and are explicitly labelled.

The iOS reader shares the safe native source contract but does not yet expose the
workspace search interface.

## Mermaid in offline export

HTML and PDF preparation now request diagrams from the same native Mermaid
renderer used by the editor. Successful SVG output is embedded as an image data
URI, with a collapsible copy of its source. Rendering errors, unsupported external
resources and image-budget limits retain readable source and add a notice.
No diagram resources are downloaded. Math export still uses readable source;
real native HTML/PDF diagram fidelity and printing remain to be verified.

## Compare desktop save conflicts

A desktop save conflict offers **Compare Changes** before Cancel, Overwrite or
Keep Both. The read-only comparison shows disk removals and captured local
additions, both line numbers, and LF/CRLF/CR or missing final-newline markers.
The local side is the exact snapshot the pending save would write. Large changed
regions show complete removal/addition groups instead of an expensive fine diff;
no content is truncated. Returning to Overwrite still rechecks the disk and asks
again if it changed while the comparison was open.

## Paste spreadsheet tables

Paste a rectangular tab-separated range with at least two rows and two columns
into ordinary prose in Source or Live to create a Markdown table. The first row
becomes the header. Empty cells, quoted spreadsheet fields, embedded line breaks
and literal Markdown punctuation are preserved; cell line breaks use `<br>`.
One undo removes the complete insertion. Edit → Paste as Plain Text
(Command/Ctrl+Shift+V) retains the clipboard text instead of converting TSV or
wrapping a selected label in a link, and skips the host image-import hook. Code, existing tables, properties and
other structured block contexts keep their native paste behavior. Single-row,
ragged or malformed ranges stay plain text. Clipboard text above 1 MiB is not
converted automatically. Normal Paste also reads native HTML when available and converts headings,
paragraphs, emphasis, links, lists, code and rectangular tables to Markdown in
ordinary Source/Live prose. Unsupported HTML or code editing contexts use the
same clipboard item's plain text. Without HTML, the existing image/text paste
pipeline remains available. Paste as Plain Text skips native rich reading.
Real browser-to-app clipboard acceptance remains pending.

## Import images and paste screenshots

On Mac, choose **File → Import Image…** or **Import image** above the editor.
Normal Paste (including Command-V/Control-V) imports an actual clipboard image;
text and URL Paste continue to work. Save the note inside the opened workspace
first. The app copies images to the vault's configured Obsidian attachment
location, inserts an encoded relative Markdown link, and never changes the
settings or the source image. With no setting, new images go to the vault root.

Undo removes only the link. If the note, selection, tab or workspace changes
while the image is being written, the file is kept and **Show link** provides
its path for recovery. In Live table cells/properties, switch to Source to paste
images. Dragging Markdown files still opens them. This is a desktop editing
feature; iOS quick editing does not collect photos or clipboard images. See [the complete boundaries and test gates](../doc/P1E_ATTACHMENT_IMPORT.md).

## iOS reading and quick notes

The iOS version supports iPhone and iPad on iOS 15 or later. In another app,
share a **file attachment** and choose **Linefold** (sometimes under **More** or
**Open in**). Alternatively, use **打开文件** in Linefold to select one or more
documents from Files/iCloud Drive. Imported copies remain available under
**最近文档**, including after a restart. Editing an imported copy never changes the original file in the sending app.

With iCloud signing enabled and the container available, both apps default to the **iCloud · Linefold**
workspace on every launch. They use the same `iCloud.work.ianvs.linefold`
container and its `Documents` directory.
On iPhone, **切换文件夹 → 选择其他文件夹…** opens a manually selected folder for
this session. On Mac, use the sidebar folder button; its workspace menu returns
to iCloud. When that automatic iCloud workspace is available, external workspaces
are not automatically reopened at startup.
Unsaved desktop edits from an external workspace are recovered as untitled-path
drafts, so selecting a new default never discards the text.

On Mac without automatic iCloud access, Linefold restores the last selected local
workspace, saved tabs and unsaved drafts using their stored file access bookmarks.
Clean tabs refresh from disk; dirty tabs retain their recovered text and flag any
conflict. Unnamed drafts remain unnamed and require Save As. Recovery never writes
the draft over the Markdown file without a save request.

iCloud container signing requires an Apple Developer team that supports iCloud;
free Personal Teams cannot provision this capability. Both app targets must be
signed by the same eligible team with this container registered. See
[Apple's shared-container configuration](https://help.apple.com/xcode/mac/current/en.lproj/devcae40ccb9.html).
An unavailable container is reported visibly. The iPhone retains incoming files
locally until iCloud becomes available; existing imports migrate without deleting
their local backups, overwriting cloud edits, or resurrecting deleted imports.
Documents are read/written using file coordination, and evicted iCloud documents
are listed before download and downloaded when opened. Recent history stays local.

For a Personal Team, an explicit **local-storage** build remains available:

```sh
bash app/tool/build_ios_local.sh <development-team-id>
```

This produces `app/build/ios-device-install/Build/Products/Release-iphoneos/Runner.app`.
It disables automatic iCloud container access and says so in the library; manual
selection of an iCloud Drive folder still works. The cloud-enabled project files
are preserved. Automatic cross-device sync cannot be validated with a Personal Team.

- `.md`, `.markdown`, `.mdown`, `.mkd`, and `.txt`, including uppercase extensions
- UTF-8 (with or without BOM), up to 5 MiB per document; empty files are supported
- Markdown reading, selectable text, tables, code, formulas, native Mermaid
  diagrams, a heading directory, in-document anchors, and web/email links
- system light/dark appearance, portrait/landscape, and accessible text sizing
- separate copies for same-named imports; corrupt/unsupported imports report an
  error while other files in the batch continue opening

The integration uses Apple's document **Open in** mechanism, not a text/URL
Share Extension. The sending app must offer a file attachment. Remote images,
adjacent image files, Wiki embeds, and links to other local files are not
automatically imported; the existing renderer displays image/embed placeholders.
Source editing saves the imported copy only; writing back to the sending app is not exposed.

Choose **编辑源码** to enter the lightweight Source editor. **保存** explicitly
writes the selected note; **取消编辑** confirms before discarding dirty text.
Task checkboxes can be edited as `[ ]` / `[x]` source. New notes use the **+**
button in the library, a safe basename and exclusive creation in the current
folder. No parent directories or existing notes are overwritten by New.

Original-file saves compare exact observed source bytes inside native file
coordination. A conflict offers **取消保存**, **保留两份**, or **覆盖此版本**.
Overwrite approval covers only the displayed observed version; another external
change prompts again. Pending native writes cannot be cancelled by changing
folders or dismissing a Dart timeout. Permission/offline errors retain the draft.

Mobile recovery uses its own local primary/backup store, not desktop sessions.
Edits are debounced and flushed on lifecycle inactivity, but are not saved to
Markdown until Save. On relaunch, **恢复草稿** requires an explicit action in the
same selected workspace; external folders must be manually selected again.
Recovery never restores file grants or silently overwrites an externally edited
note. Failed persistence is reported, and recovery files are not discarded.

If the original folder cannot be reauthorized (including an old app container
path), **恢复为新笔记** explicitly copies recovered source into a fresh exclusive
file in the current granted root. It does not copy attachments or change the old
file. The new Source still requires Save. Lifecycle events before recovery load
finishes cannot clear an unseen draft.

Library search filters filenames and relative paths only, not note bodies.
Ordinary relative Markdown links and Wiki note names navigate within the already
selected folder. Duplicate Wiki names require a choice; missing notes are not
created by following a link. Wiki YAML aliases and block references are not yet
supported in this lightweight reader. A single imported file never grants access
to its old parent or adjacent attachments.

See [mobile quick-note boundaries and verification](../doc/P2C_IOS_QUICK_NOTES.md).

The native importer coordinates access to file-provider URLs, reads while their
security scope is active, then writes into the default workspace's
`Imports/<UUID>/<filename>`. Copies are visible in Files under Linefold. Cold-launch URLs are received in
`SceneDelegate.willConnectTo`; running-app deliveries use `openURLContexts`.
The native queue is drained after the Flutter library is initialized, and a
library scan recovers copies even if a launch was interrupted. Recent history
uses relative paths so iOS container changes do not invalidate it.
This follows [Apple's document-sharing integration](https://developer.apple.com/documentation/uikit/enabling-document-sharing)
and [Flutter's UIScene lifecycle](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate).

From the repository root:

```sh
make test-ios-preview
make build-ios-preview
make run-ios DEVICE=<simulator-or-device-id>
```

The Mermaid SVG preprocessing library also builds for iOS through the shared
native-asset hook. iOS bundles the unmodified OFL-licensed Noto Sans CJK SC Regular
font for offline Chinese outlines (about 16 MB). LastResort placeholder glyphs
and fonts without standard outline tables are excluded. Install the Rust targets for the devices you build:
`rustup target add aarch64-apple-ios aarch64-apple-ios-sim` (and
`x86_64-apple-ios` for an Intel simulator). Xcode and CocoaPods are required.
For a physical iPhone, open `ios/Runner.xcworkspace`, select a development team
for Runner, and build/run on the device. No signing identity is committed.
The simulator build is at `build/ios/iphonesimulator/Runner.app`.

Use `test/fixtures/ios-preview.md` for a device smoke test: open it while
Linefold is terminated, send another file while Linefold is running, return to
recent documents, relaunch, and check the Chinese Mermaid labels and anchors.
Repeat from Files/iCloud Drive and the third-party sender used in production.
Generate the iOS icon catalog from the shared artwork with
`swift app/tool/generate_ios_app_icons.swift` from the repository root.

## macOS editor

`app/` is the file-first desktop editor built on top of the reusable
`ianvs_markdown` package. Its file-first product structure keeps the useful
parts of MarkText, with app chrome adapted to macOS toolbar, source-list,
inspector, menu, typography, and selection conventions.

Implemented application-shell capabilities:

- document toolbar with editing modes and a compact, reorderable tab strip
- Command-1–9 switches the first nine tabs in their current order, not editor modes
- shared monochrome icons and one primary window location per action
- black workspace sidebar, neutral light/dark chrome, and blue action accents
- native File, Edit, View, and Window menus and an all-open-documents menu
- new/open/save/save-as and Finder file drop
- virtualized Markdown file tree with cancellable filename/path search, ranked
  highlights, result counts, natural/modified sorting and directory-local refresh
- reveal active file, optional follow mode, keyboard navigation and per-workspace
  expansion, scroll, sort and favorites recovery
- inline new Markdown/folder and rename, duplicate saved copy, move picker,
  multi-selection, folder drop targets and native Trash with unsaved-edit protection
- External Files tree for individually opened files outside the workspace,
  with shared directory paths merged into expanded branches and synced with
  open tabs; paths stay on one line with middle ellipsis and full-path tooltips
- collapsible left sidebar with a draggable right edge and remembered width,
  plus a docked document outline inspector
- per-document mode, cursor, scroll, dirty state, encoding and line-ending UI
- atomic UTF-8 writes and external file-change notifications
- debounced crash recovery for open files and unsaved drafts
- macOS security-scoped bookmarks for restoring user-approved files and folders
- a one-time choice of Linefold as the default Markdown application, with a
  persistent preference in Linefold → Settings… (Command-,)
- Finder open requests, including files received before workspace recovery finishes
- native Mermaid diagrams in Live/Read, including SVG arrowheads and Chinese labels
- Finder Quick Look previews for `.md` and `.markdown`, including native Mermaid diagrams
- Read-mode links to local Markdown and headings, local image previews, and
  external web, HTML, and PDF links

Saving captures the source at the time of the request. Continuing to type or copy
while a write is pending uses the current draft; a completed older write does not
clear newer edits. Both the editor shortcut and native File menu show save errors
without acknowledging the failed snapshot, and allow another save to retry.

Integration boundaries in the current desktop shell:

- Embedded local/remote images and Wiki embeds still need host resolution:
  images show a blocked placeholder and Wiki embeds show a reference. Ordinary
  image links open a preview. Missing/oversized files and malformed SVG text
  show a closable error without changing the document. Open the document's containing folder as a workspace
  to grant sandbox access to sibling documents and assets. In Live mode, ordinary
  links retain their source-editing behavior; use Read mode to follow them.
- YAML is editable in Source and hidden in Live/Read. The package's optional
  Properties editor and heading-fold controls are not enabled in this app.
- Search matches names and relative paths in the workspace, and full paths for
  external files. It returns the best 200 matches with the total count; it is not
  a document-content search. Rename and move do not rewrite Markdown links.
  Document find/replace and export are available; an encoding or line-ending
  selector is not exposed.
- Open-document text, modes, and workspace visibility are recovered.
  Source selections and source-anchored reading positions are recovered separately;
  undo history is not restored across app launches.
  Snapshot writes are serialized, including mode-only changes. Normal cancellable
  Quit requests wait for the latest recovery snapshot, including edits made while
  storage is busy. If recovery storage fails, Quit is cancelled with an error so
  the user can retry or save files. Forced termination/power loss can still lose
  changes since the last completed snapshot; the 350 ms debounce is not a durable
  per-keystroke write guarantee.

The desktop shell integrates the published `ianvs_design: ^0.4.1` package.
Shared themes and controls use compact density and macOS system fonts.
Appearance follows the system by default; View → Use System Appearance restores
following after a manual override. Sidebar resize supports arrow keys, Home/End,
and double-click or Enter to reset. Its single divider sits at the sidebar's
right edge while retaining an 8-point drag target inside the sidebar.
Control-click opens the file context menu;
Command-click remains additive selection.

Specialized outline/tab typography is defined in `lib/src/desktop_typography.dart`.
It maps Apple's macOS text styles to system-font controls: 13/16 pt for primary
interface text, 12/15 pt for tabs, and 11/14 pt for secondary information. Use
these shared styles for app chrome so font family, leading, and tracking remain
consistent. The Markdown canvas keeps its own reading and monospace styles.

The app icon uses the folded-paper L mark. Its master artwork and generation
prompt are in [design/linefold-icon-v1.md](design/linefold-icon-v1.md). Regenerate
all macOS icon sizes from the repository root with
`bash app/tool/generate_app_icons.sh`.

Settings also provides reading text size (12–28 pt), line spacing (1.2–2.2),
and narrow/standard/wide document columns (560/720/960 logical pixels, constrained
by the window). Text size scales body text and headings in Read/Live; the column
width remains shared across modes. Preferences survive restart independently of
Markdown contents and undo history. Reset reading settings restores 14.5 pt,
1.58 spacing and the standard column. View → Larger/Smaller Reading Text and
Actual Reading Text Size share the reading preferences: Command/Ctrl + plus or
minus changes size by 0.5 pt, and Command/Ctrl + 0 restores 14.5 pt without
resetting width or spacing. Command/Ctrl + equals also enlarges text. These
commands defer during active editor composition. “Wrap code lines” defaults to
on; turning it off lets fenced and indented Markdown code scroll horizontally in
Read and Live, including the active code editor. The preference survives restart
and never inserts or removes source line breaks. Source mode and custom diagram
renderers retain their own layout.

The first-launch association prompt remembers both acceptance and refusal.
Settings shows the saved preference alongside the actual macOS default. Changing
the preference off restores the previous application when available, or asks for
a replacement. Linefold respects later changes made in Finder and does not
reapply its preference on launch. If macOS cancels or rejects a change, the choice
is still remembered and Settings offers a retry and Finder instructions.

Native association tests use an isolated preference domain and a simulated
workspace; run `bash app/tool/test_native_file_association.sh` from the repository
root. They do not change the machine's default applications. Run the Flutter
controller, settings, and Finder-delivery tests with `cd app && flutter test`.

The host typography and focus geometry suite lives in
[`test/focus_geometry_test.dart`](test/focus_geometry_test.dart). From `app/`,
run `flutter test test/focus_geometry_test.dart`. On macOS, add
`--dart-define=LINEFOLD_SYSTEM_FONTS=true` to also check the system Latin/CJK fonts.
The root package's tests use its own dependencies and do not import the app theme.

Mermaid blocks use the shared [native vector pipeline](../packages/ianvs_mermaid/README.md):
merman renders in a background isolate, usvg expands markers and outlines system
font glyphs, and Flutter displays the result. Document diagrams have no embedded
WebView or pan/zoom gesture handler. Run `flutter test test/document_diagram_test.dart`
from `app/` for wheel, trackpad, Live editing, and async lifecycle regressions.

Local SVG previews use the same native text/marker expansion and Flutter vectors.
Run `flutter test test/svg_document_scroll_test.dart` from `app/` for input,
source-update, stale-result, error and disposal regressions. SVGs with unsupported
features such as HTML labels, filters or embedded images offer **Open in default
app**. The app has no embedded browser dependency or native SVG platform view.

To validate a local copy of the LLM principles corpus in both Live and Read modes,
run `flutter test test/llm_series_render_test.dart
--dart-define=LLM_SERIES_DIR=/absolute/path/to/llm-principles-series` from `app/`.
This optional test scrolls every Markdown document, checks table-link bounds,
and renders every Mermaid source through the bundled native vector pipeline.
Native library loading and external link navigation also require a macOS app
smoke test.

The desktop app requires macOS 12 or later. From the repository root, run
`make run` (or `make run-app`), or use Flutter directly:

```sh
cd app
flutter pub get
flutter run -d macos
```

macOS builds use local ad-hoc signing by default, so `make run`, `make install`,
and `flutter build macos` do not require an Apple Developer certificate. The app
reports that automatic iCloud sync is disabled; you can still open local files
or manually select an iCloud Drive folder. Sandbox, user-selected file access,
and the Debug/Profile permissions needed by Flutter remain enabled.

To enable automatic iCloud sync with an eligible Apple Developer team, copy
`macos/Runner/Configs/Signing.local.xcconfig.example` to
`macos/Runner/Configs/Signing.local.xcconfig`, then replace `YOUR_TEAM_ID` with
your team ID. This ignored file enables iCloud and development signing for both
Runner and its Quick Look extension, while preserving the extension's own
sandbox-only entitlements. Open `macos/Runner.xcworkspace` in Xcode and build
Runner once to provision signing. The team must have the
`iCloud.work.ianvs.linefold` container configured for the app, as described in
[Apple's container configuration guide](https://help.apple.com/xcode/mac/current/en.lproj/devcae40ccb9.html).
Remove the local signing file to return to local builds. iOS signing is configured
separately.

To build a Release version for your Mac's architecture and install it into
`/Applications/Linefold.app`, run `make install` from the repository root.
Run it again to update the installed app,
then launch Linefold from Finder's Applications folder. To choose another
destination, use `make install INSTALL_DIR="$HOME/Applications"`. Installation
replaces the app bundle after verifying the new copy and preserves user data.

`example/` remains the small package-integration example. Product features
belong here instead of in the example application.

## macOS 系统快速预览

`make install` 会同时安装并注册 `Linefold Markdown Preview` 扩展。在 Finder
选中 `.md` 或 `.markdown` 文件并按空格，即可预览磁盘上已保存的内容；无需启动
Linefold，也不改变默认编辑器。若系统没有自动启用，可在“系统设置 → 通用 →
登录项与扩展 → 快速查看”中启用它。不同 macOS 版本的设置位置可能略有区别。
已有其他 Markdown 预览扩展时，最终使用哪个扩展由系统和用户的扩展选择决定。

支持标题、强调、列表、任务、引用、表格、围栏代码、删除线、脚注、标题锚点和
Mermaid；闭合的 YAML front matter 不显示。正文随系统切换亮暗配色，图表使用
白底以保持原生引擎的文字和连线对比度。读取支持 UTF-8、UTF-8 BOM 和带 BOM 的
UTF-16。图表失败时显示原因和原始源码，其余正文继续显示。

Quick Look 的正文使用 CommonMark/GFM HTML 输出，与应用里的 Flutter 排版是
两个展示后端；公式、Wiki 嵌入及其他 Obsidian 专属语法不承诺与应用一致。
原始 HTML 显示为文本；本地和远程图片显示带说明的占位符，扩展不读取相邻文件
或请求网络。网页、邮件与标题锚点保留链接，本地相对链接只保留文字。
预览限制为 2 MiB 文本、32 张图，每图 128 KiB 源码，生成内容最多
16 MiB；超限会显示提示，文档不会被修改。

在仓库根目录运行：

```sh
make test-quicklook
make install
bash app/tool/verify_quicklook_bundle.sh /Applications/Linefold.app
```

原生测试覆盖实际 merman FFI、Markdown 结构、编码、错误恢复和输入限制；打包
检查覆盖扩展声明、宿主版本一致性、独立动态库路径与签名。交互样例为
`app/test/fixtures/quicklook.md`。Finder 按空格的实测用于确认系统选中了扩展；
`qlmanage -p` 的成功不能替代这一步。

See [DESIGN.md](DESIGN.md) for the macOS visual contract and verification notes,
and [ARCHITECTURE.md](ARCHITECTURE.md) for dependency and recovery rules.

## Sidebar file management

Use the workspace **…** menu for new files/folders, reveal/follow, collapse,
refresh and sorting. Right-click a row for file operations, favorites and path
copying. A new item uses the selected folder (or selected file's parent); names
are edited inline. Return commits and Escape cancels. New Markdown names receive
`.md` when no extension is supplied. External-folder creation uses a dialog
because the external tree contains only open files, never a directory listing.

Arrow keys navigate the tree independently of the active document. Return opens;
Escape clears search and restores the previous tree position. Command-click
(or Control-click) toggles selection; Shift-click extends a range. Use **Move
selected** / **Trash selected**, or right-click for batch actions. Drop onto a
folder to move into it. To move back to the workspace root, drop onto its title,
a root-level file row, or the empty space below the tree. File-row and empty-space
targets show the destination folder while hovering. Touch/trackpad scrolling
continues to scroll the list. Favorites appear only after the first item is added.

Moves and copies refuse collisions. Trash uses the macOS Trash and checks all
open descendants for unsaved changes. Copies use saved bytes. Editing during a
pending Trash operation preserves the new text as a recoverable untitled draft.
Operations outside the workspace request a containing-folder grant; they do not
silently enumerate an individually opened file's parent. External directory rows
are synthetic groups: bulk commands affect only their opened files, and whole-folder
rename/move/Trash requires opening that folder as a workspace. Partial batch failures
report the number completed and identify each failed item.

Run all sidebar acceptance gates with `bash app/tool/verify_sidebar.sh` from the
repository root. Logs and rendered normal/narrow/search screenshots are written
to `app/build/sidebar-acceptance/`. See
[the acceptance matrix](design/sidebar-enhancement-acceptance.md) for coverage.


The Ianvs/macOS design integration and visual acceptance artifacts are documented
in [the acceptance record](design/ianvs-macos-acceptance/README.md). Run
`bash tool/verify_sidebar.sh` from `app/` for static analysis, all app tests,
native file-operation checks, and a macOS debug build. The visual fixture also
covers system-style light/dark surfaces, 840 × 560, 200% text, context menus,
and root-directory drop feedback.

## Large documents and input focus

The main entry uses the default Markdown processing limits. When a document is
large or complex, Live falls back to editing its full plain source. Read shows a
bounded plain-text prefix and an explicit notice when truncated; whole-document
copy still preserves the full Markdown. The notice is not part of the document.
These parsing limits do not bound Flutter's full-source text layout or memory.

Returning from Read to a focused Source/Live surface reconnects keyboard input.
`test/large_document_main_test.dart` covers all three default budget axes;
`test/input_focus_main_test.dart` covers composition commit/cancel, mode switching
and undo/redo through this main application. These are framework protocol tests,
not native IME evidence. Actual local results are recorded in the repository's
R3 acceptance reports.

## Native editing commands (R4-01)

The macOS main entry routes explicit editing menus through
`IanvsMarkdownShortcuts.invoke`. Edit/View menus (and app Save) do not register
native editing accelerators; Flutter owns configurable shortcuts. Native menu
items remain clickable and may safely do nothing in Read or during composition.
Disabled/remapped keys do not disable an explicit menu action. In example,
property undo stays local and toolbar Save commits its draft; in app, Search Files
keeps its own text history and the editor continues to hide front matter.
See [the command contract](../doc/API_CONTRACTS.md#命令配置与焦点r1-03) and
[the validation record](../benchmark/COMMAND-ROUTING-2026-10-13.md).

### 跳转返回入口（2026-10-26 增量）

桌面正文上下文栏提供返回按钮，无历史时禁用，状态随活动标签切换。
View 菜单和窗口快捷键继续支持同一命令。iOS 阅读底栏新增「返回」，目录、标题链接和
脚注跳转共用组件的文档内返回历史；正文刷新后按源码变化调整保存位置。
当前 iOS 返回历史仅存在于阅读组件生命周期内，切到快速编辑、重新打开文档或重启后
不承诺保留；跨文档历史和持久化位置仍待补齐。本批通过 widget 布局与实际滚动断言，
尚未执行真机输入/手势及 VoiceOver 验收。

### iOS 正文查找（2026-10-26 增量）

阅读底栏的「查找」打开正文搜索，提供命中数、前后匹配和关闭入口，保持原阅读组件与
正文高亮。链接地址等隐藏源码不纳入正文搜索；不提供替换。关闭保留当前命中位置，
不会产生跳转返回历史或修改文档。复用搜索控制器的防抖、后台大文档索引、预算提示和
过期结果保护；输入法组合输入期间禁用跳转/关闭。查找期间暂时收起阅读底栏，
避免小屏、大字号和软键盘同时出现时溢出。320px/3倍字号/键盘及长文实际滚动已有
widget 回归；真实 iOS 键盘、VoiceOver、性能和跨重启阅读位置仍待验收。

### iOS 阅读位置持久化（2026-10-26 后续增量）

存储目录初始化或读取失败后，后续加载/保存会重试。未成功读取已有位置前不会覆盖磁盘快照；
关闭时的最终保存仍会合并旧位置与本次阅读进度，存储失败不修改 Markdown 文件。

移动阅读器现在按工作区路径与文档路径保存正文锚点，重新挂载或重新打开同一文档时恢复；
应用重建后从独立的 `LinefoldMobileReading` 主备快照读取。保存包含原文快照，以便磁盘内容
改变后保守重定位；不修改 Markdown，不保存文件授权。滚动写入合并 400ms，生命周期暂停
和退出组件时请求 flush；最多保留 24 项、合计 8 Mi UTF-16 源码单位，超限淘汰旧项。
本项替代上文“重新打开或重启不保留阅读位置”的历史限制；返回栈仍不跨重启保存。
已验证实际磁盘写入/重新加载与新应用控制器恢复，真机强制退出时机及 iCloud 路径变化
仍需平台验收。位置存储失败不阻止阅读，服务保留错误状态并允许后续写入重试。

### iOS 阅读到快速编辑的位置连续性

从当前阅读文档进入「编辑源码」时，将光标定位到阅读锚点对应的源码位置；
异步打开后核对路径与工作区，避免对另一文档应用旧位置。取消编辑恢复原阅读视口，
保存后按新正文重定位原阅读段落。新增 iOS widget 测试检查光标屏幕坐标、取消恢复，
以及前文插入并保存后的段落可见性；真实软键盘/IME 与强退仍需设备验收。

### 桌面跨文档返回（增量）

Markdown 和 Wiki 链接打开其他文档后，返回按钮/菜单会在处理后续文内跳转后回到来源标签，
保留来源未保存内容并恢复离开时的选区及阅读锚点。普通标签切换不入栈；关闭文档即移除
相关历史，返回不自动重开文件。跨文档历史仅在当前工作区控制器生命周期保留，最多64项，
保存的源码快照合计不超过8 Mi UTF-16单位。iOS 跨文档返回仍待接入。

### iOS 阅读返回的会话保留（2026-10-26）

本地 Markdown/Wiki 链接可逐级返回来源阅读位置。到达目标后的文内跳转优先返回，
回到来源后可继续返回它之前的段落；读取失败保留重试入口，不修改 Markdown。
阅读会话按工作区代次与路径隔离，最多缓存 24 篇、8 Mi UTF-16 当前原文单位，
活动文档单独超限时保留活动会话。淘汰后不再保留该文档的文内跳转历史。
跳转历史仅限当前进程，重启恢复使用独立的阅读位置快照。
当前自动测试覆盖实际视口恢复与缓存释放，尚未替代 iOS 真机和长会话性能验收。

### 公式导出（2026-10-26）

HTML/PDF 导出流程将可渲染公式生成为内嵌 2x PNG，与编辑器使用同一数学库。
公式不依赖外部脚本或字体；行内图片 alt 保留原式，块级公式另附折叠源码。
公式超过 8,192 字符、1,024×512 逻辑像素，或超过全局图像预算时保留源码并说明原因。
公式图片不能作为 PDF 中可搜索的公式文字；原生 PDF 文字质量、分页与导出产物验收仍在进行。

### PDF 中文复制与搜索验证（2026-10-26）

导出优先使用系统 Arial Unicode MS，避免当前 Apple PDF 路径把部分汉字映射成康熙部首。
同时避免 WebKit 合成粗体造成重复文本，以轻描边保留标题和强调的视觉区分。
macOS 27.0.1 的原生验收已验证原标题、结尾、表格中文和长代码的精确码点与次数，
并通过 PDFKit 原文搜索。没有改写原始提取文字或进行 Unicode 归一化。
这不代表所有系统字体、字符或第三方阅读器已覆盖；跨页表头及原生公式/图表产物验收仍在进行。

### 原生图形导出回归（2026-10-26）

`make test-document-export-fixture test-native-document-export` 现同时验证真实数学渲染器、
原生 Mermaid 与 WebKit PDF 输出；夹具检查两张公式的图像尺寸和 Mermaid 节点的实际像素，
并保留独立 PDF、截图与 JSON 报告于 `build/export-qa/native/`。
当前代表性公式和流程图已通过原生输出与 Poppler 页面检查，复杂图形和跨平台覆盖仍需扩展。

### PDF 跨页表头（2026-10-26）

原生导出按实际行高为长表格分页，并在续页复制表头；短表格保持整块。
150 行、四列的验收语料已通过全部单元格、重复表头、中文搜索和无空白页检查。
单行内容超过一页时会明确拒绝导出，不截断文字；请缩短该单行后重试。
混合行高、多表格以及其他系统版本仍需扩展验收。

### Markdown with attachments ZIP

On macOS, **File → Export Markdown + Attachments…** exports the command-time
buffer, including unsaved changes, into `document.md`, `assets/`, and
`manifest.json`. Referenced local attachments retain their original bytes; references
in the exported copy are rewritten to portable relative paths. Repeated attachments
are copied once, and generated asset names avoid same-name collisions.

The bundle reader supports local regular files, including images, PDF, SVG,
archives and files without extensions. Linked Markdown notes are listed but not
recursively copied. Hidden files and symbolic links are blocked; remote resources
and cloud-only files are not downloaded. Missing or blocked resources remain unchanged in Markdown and are
reported before the Save dialog, with the full list inside the manifest.
You can cancel or export the available resources. The original document is
never saved or rewritten by this operation. Bundle output is bounded to 32 MiB
and 256 unique attachments, and uses the same native atomic destination and
source-file protection as other exports.
