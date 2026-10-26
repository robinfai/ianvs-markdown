# Desktop app architecture

The `app` package turns `ianvs_markdown` into a file-first desktop editor. It
borrows MarkText's product shape—documents remain ordinary files, while the app
adds workspace navigation and window-level document state—but keeps the editor
engine and storage layer independent. The window shell follows macOS desktop
conventions with a user-selected black workspace sidebar.

## MarkText comparison

| MarkText concept | Ianvs desktop implementation | Design choice |
| --- | --- | --- |
| Main process and renderer shell | Flutter macOS runner + `EditorShell` | Native file access stays behind services instead of entering editor widgets. |
| Open-file tabs | `WorkspaceController` + `DocumentSession` | Every tab owns source, selection, history, mode, and scroll state. |
| Folder sidebar | `WorkspaceSidebar` + `FileBrowserController` | Virtualized visible rows consume the session-owned `WorkspaceIndex` catalog; tree preferences remain separate. No database is required. |
| Outline sidebar | `FloatingOutline` | A toggleable right-hand inspector participates in layout so it cannot cover document content. The existing class name is retained. |
| Editor modes | `IanvsMarkdownEditorMode` | Live Preview, Source, and Read all share one exact Markdown source string. |
| Window/session state | `WorkspaceSessionStore` | Open tabs, active tab, layout visibility, sidebar width, per-workspace browser preferences, favorites, and unsaved source are recovered after restart. |
| macOS file permission recovery | security-scoped bookmarks over a platform channel | User-approved file and folder access survives an app restart without disabling the sandbox. |
| Default Markdown application | `FileAssociationController` + native `MarkdownFileAssociation` | UserDefaults stores the choice separately from Launch Services; explicit changes use NSWorkspace with system consent and readback. |
| Finder document opens | native `IncomingMarkdownFiles` + `IncomingFilesService` | Queue file URLs before Flutter recovery and serialize delivery into the existing workspace, preserving unsaved tabs. |
| File watching | document subscriptions + indexed-directory subscriptions | External edits are surfaced explicitly; tree events refresh only affected directory caches. |
| Safe persistence | `writeMarkdownFileAtomic` | A same-directory temporary file is flushed and renamed over the target. |

## Dependency direction

```text
macOS runner
    ↓
EditorShell / sidebar / outline / tabs
    ↓
WorkspaceController
    ↓                         ↓
MarkdownFileService      WorkspaceSessionStore
    ↓                         ↓
ordinary .md files       recovery snapshot

IanvsMarkdownLiveEditor ← DocumentSession
```

The root package never imports `app`. This keeps `ianvs_markdown` reusable as a
widget library, and keeps `example` small enough to demonstrate package
integration without duplicating product-level file and session behavior.

The app and example share `packages/ianvs_mermaid` for native Mermaid rendering
and caching. The macOS build normalizes the bundled dylib's install names before
code signing so the app does not depend on paths from the publisher's machine.
Mermaid rendering runs in a persistent background isolate: merman's resvg-safe
SVG is normalized and passed through a bundled Rust usvg 0.45.1 FFI bridge.
usvg resolves styles, expands markers and converts system-font text to paths;
`MermaidView` displays that result with `SvgPicture` and no default pan/zoom
gesture recognizer. Source/options updates discard obsolete futures. The worker
coalesces identical requests and bounds its cache by both count and string bytes.
The cache identity includes merman/usvg versions and the system font snapshot.
`hook/build.dart` builds and bundles the usvg library as a Flutter code asset;
the existing merman dylib normalization still runs before code signing.

Local SVG image previews use `SvgDocumentView` and the shared `renderSvg` API.
usvg expands text and markers in a background isolate, then Flutter displays the
result inside the image viewer. Unsupported SVG features (including HTML labels,
filters and embedded images) produce an explicit message with an action to open
the file in its default external application. No embedded browser, native SVG
platform view, or network-client entitlement is required.
`DocumentLinkService` resolves links relative to each document and routes
Markdown through the workspace, image files to a preview, and web/HTML/PDF links
to macOS. The SVG preview's external-open action also delegates to macOS.
File reads continue to use the existing sandbox permissions.

## Quick Look 扩展

`macos/QuickLook` 是独立的 macOS 12+ 数据型预览扩展，随 Runner 放入
`Contents/PlugIns/LinefoldQuickLook.appex`。`PreviewProvider` 向系统返回
`QLPreviewReply(.html)`，文件读取与渲染在 reply 的数据创建闭包中进行。
扩展仅声明 `net.daringfireball.markdown`，沿用宿主的 `.md` / `.markdown`
类型关联，不接管所有纯文本。

```text
Finder → Quick Look → PreviewProvider
                      ↓ 有界文件读取、编码转换
                Rust pulldown-cmark
                      ↓
              HTML + merman SVG 图像 → 系统 HTML 预览
```

Mermaid 复用 Flutter 已锁定的 `merman` 原生库与 `resvg-safe` 输出模式。系统
SVG 图像支持文字和 marker，因此这里不做 Flutter 专用的 usvg 路径展开。
普通 Markdown 使用锁定版本的 `pulldown-cmark` 生成静态 HTML；不载入 Flutter
引擎、不调用宿主进程、不执行文档脚本。正文样式在 `renderer/style.css`，不
依赖用户环境中的主题文件。扩展具备独立沙箱，无网络访问授权。

`tool/build_quicklook.sh` 按 Xcode 的 ARCHS 构建 Rust 静态库，并把当前 merman
库放入扩展自身的 Frameworks；归一化 install name 后签名。扩展显式覆盖
项目层继承的 CocoaPods 链接参数，避免依赖宿主插件或发布机器上的绝对路径。
`tool/verify_quicklook_bundle.sh` 检查这一边界，安装脚本在替换旧应用前运行它。
安装完成后只注册宿主与扩展，不重设默认编辑器，不禁用其他预览提供方。

## App-shell visual contract

The shell uses one resizable black workspace sidebar (248 points by default), a minimum 52-point document
toolbar, a 32-point tab strip, and an optional 224-point outline inspector.
The sidebar's preferred width is persisted; the shell limits its displayed width
to leave space for the editor, toolbar, status bar, and visible outline.
`ianvs_design` supplies the shared compact theme, semantic surfaces, controls,
menus and dialogs. `desktop_theme.dart` bridges its tokens into the independent
Markdown theme extension. `IanvsToolbar`, themed segmented controls,
`IanvsIconButton`, `IanvsTextField` and `IanvsResizeHandle` keep product behavior
in host callbacks. The virtualized hierarchical file tree remains host-owned;
`IanvsSidebar` is a flat navigation component and would lose those contracts.
The app starts in system appearance and permits a session override. `DesktopMenuBar`
exposes the same document commands through the native macOS menu bar.
The document canvas adapts its padding to available width; word counts,
saved/edited state, encoding, and line endings live in a quiet bottom status bar.
`app_icons.dart` owns the shell's semantic icon vocabulary. The sidebar owns
workspace selection and inline file search; the toolbar owns modes/view toggles;
the tab strip owns new/close/switch. Command-1–9 follows visual tab order using
`tab_shortcuts.dart` in both the shell and native Window menu. The app disables
the library's optional mode shortcuts, including the nested Source editor, so
focused text editing does not intercept those tab bindings.

Markdown rendering remains owned by the reusable root package. The app supplies
theme overrides for neutral emphasis, code, and link colors without changing
the library's defaults. See [DESIGN.md](DESIGN.md) for the full visual contract.

## Current-document find and replace

`DocumentFindController` searches the active controller's unsaved Markdown
buffer, not the disk file or workspace. `Command-F` and Edit > Find open the
compact find/replace bar; `Command-G` / `Shift-Command-G` and Enter / Shift-Enter
in the Find field cycle through literal, non-overlapping matches. Case matching
is optional, using Unicode-aware case-insensitive matching by default. There is
no regular-expression query language, Unicode normalization, or full-text index.
Markdown syntax, YAML, hidden text and link destinations remain searchable.

Small buffers search immediately. Buffers of at least 64 Ki UTF-16 units use a
150 ms debounce and 16 Ki source windows, yielding between windows with literal
lookahead so boundary-spanning and non-overlapping matches remain exact. The
bar shows **Searching…** and disables navigation/replacement until the complete
current result is ready. Query, case, source, composition and disposal changes
invalidate earlier generations; partial or stale counts never become editable
results. Moving the source caret during a scan cancels its pending reveal.
This stage wires the desktop app only, not the example host, and makes no
device/Profile latency claim or rendered-text search claim.

While the bar is open, the app temporarily presents the same controller through
`IanvsMarkdownEditor`, with an exact current-match highlight independent of
the query field's focus. Live/Read are not rewritten into a new document mode;
closing the bar or pressing Escape returns to their original presentation.
Live resumes editing at the current source selection, revealing that block;
Read restores its previous viewport. An explicit mode change or tab change
dismisses the bar. Closing the bar retains the query for subsequent
Command-G / Shift-Command-G navigation.
Read's temporary source surface remains read-only. Only the explicit
**Edit to replace** action enters editable Source mode, which remains selected
after closing the bar. This phase does not offer in-place rendered-text search.

Each Replace or Replace All operation is one controller history group; Replace
All applies a single snapshot, even when replacement text itself contains the
query. Neither operation saves or normalizes the rest of the source. Typing or
undo refreshes counts without moving the caret; the user navigates again before
replacing an individual match whose prior highlight became stale. Replace All
continues to act on the displayed query's full current set. Active editor,
query, or replacement composition blocks search navigation and replacement.
Find is not opened over an active editor composition or a modal dialog. Query
and replacement text are transient window state and are not recovery content.

## Source-of-truth rules

Recovery snapshots include the source selection's UTF-16 base/extent, affinity,
and direction. Missing or invalid selection metadata retains the legacy default;
IME composing ranges are never recovered. Reloading identical disk text retains
the selection. Changed disk text maps positions in the unchanged prefix/suffix
and falls back to the replacement start for positions inside the changed span,
without splitting a surrogate pair at that boundary. Snapshots also include the
viewport's source offset and vertical position, bound to the snapshot's text.
Viewport-only changes schedule the existing debounced recovery writer; they do
not mark the document dirty or write the original Markdown file. The desktop
editor opts into `preserveViewport` for tab, mode and restart restoration. Text
changes rebase anchors through unchanged spans or a unique following excerpt;
ambiguous changes fall back to the changed span. User scrolling cancels delayed
restoration. Read also retains its paragraph through image and typography size
changes. These tests do not substitute for physical IME or performance checks.

1. `DocumentSession.controller.text` is the current source shown by the editor.
2. `persistedText` is the last version successfully saved to the document path.
3. A dirty recovered document wins over the disk copy, but a changed disk copy
   raises an explicit conflict banner.
4. A clean recovered document is refreshed from disk during launch.
5. Workspace metadata is recovery state, never a replacement for Markdown
   files.
6. The default-application preference is intent, not proof of the system default.
   Both acceptance and refusal survive restart. Loading preferences never changes
   the system association. Settings refreshes the actual default when reopened
   and when the app becomes active; failed changes remain visible and retryable.

The native bridge declares `net.daringfireball.markdown` as an imported document
type and an alternate editor. It does not claim the general plain-text type.
The existing app sandbox remains enabled. Explicit association changes use
[NSWorkspace.setDefaultApplication](https://developer.apple.com/documentation/appkit/nsworkspace/setdefaultapplication(at:toopen:completion:)),
which lets macOS request consent when required. The saved previous application
is restored only while Linefold remains the current default; an external choice
is preserved. If no previous application remains available, an application
picker allows the user to choose a replacement.

## Sidebar state and file mutations

`WorkspaceController` owns `FileBrowserController` for the lifetime of the session,
including when the sidebar is hidden. Browser preferences are keyed by workspace
root. The browser flattens visible rows for `ListView.builder`, separates focus
and selection from the active document, and never enumerates external parents.
Search walks the directory cache with a cancellation generation; subsequent
queries reuse it. Filesystem events debounce a local cache refresh. Root epochs
and reveal generations reject stale reads across workspace switches and rapid
navigation. Symlink directories are not followed.

File create, move, duplicate, Trash, save and open are serialized by the workspace
controller. `MarkdownFileService` delegates mutations to native
`WorkspaceFileOperations`: exclusive creation, no-replace FileManager move/copy,
and recoverable macOS Trash. A successful move remaps open sessions, watchers,
expanded paths, selection, favorites and bookmarks before persisting recovery.
Failures before disk success leave session identity unchanged. Batch operations
preflight collisions and report partial filesystem failures explicitly.

Additional containing-folder grants and external-file favorite bookmarks are
persisted separately. New changes typed during an asynchronous Trash operation
remain in an untitled session, while queued saves of removed sessions are ignored.
This preserves the file-first model without a second content database.

## iOS reading preview

The iOS product lives in `lib/src/preview/` and shares the Markdown renderer and
native Mermaid pipeline with the desktop editor. `main.dart` chooses it on iOS;
desktop workspace recovery, file-association prompts and editor chrome remain
in the macOS shell.

`MarkdownImporter.swift` coordinates a provider read under security-scoped
access, validates the extension/UTF-8/5 MiB limit, and atomically stores an
app-owned copy. `PreviewIntegration` imports off the main thread and queues
paths/errors until Dart drains them. `SceneDelegate` forwards both cold and
running-app file URLs; Flutter deep-link routing is disabled for these URLs.

`apple/CloudWorkspace.swift` is compiled into both native apps. It resolves the
entitled ubiquity container off the main thread, coordinates file reads/writes,
exposes remote document stubs, and forwards iCloud metadata updates. Both apps
select this container on startup; security scopes for other workspaces are only
acquired by manual selection. Native iOS folder scopes last for the session.

`PreviewLibrary` discovers workspace documents and records recent history in
local Application Support. It bounds reads and refuses paths or symlinks outside
the selected workspace. Old local imports migrate once by stable import ID;
their backups remain local and never resurrect a subsequently deleted cloud file.
The explicit Personal Team build omits iCloud signing/Info.plist capabilities
and exposes local storage honestly; regular builds retain the shared container.
`PreviewController` protects the reader from stale asynchronous opens and
continues through individual batch failures. `PreviewPlatform` serializes
native queue drains. Tests cover real file copies, queue ordering, recovery,
same-named documents, bad input, and narrow/large-text reading layouts.

## Workspace source search (P1c)

`WorkspaceController` owns one `WorkspaceIndex`. The file tree/path-name search
and `WorkspaceSearchController` share its root-relative metadata snapshots and
per-directory singleflight requests. The browser owns view preferences and
watcher hints, not another filesystem database. Simultaneous refreshes coalesce
and a refresh arriving during enumeration is replayed; incomplete/error listings
are never evidence that an old subtree was deleted. Each catalog revision carries
its affected directory paths; the tree applies only changed snapshots, rather
than rebuilding unrelated visible entries for every scanned sibling.

Search has a separate sidebar action and Command-Shift-F / Control-Shift-F. It
matches literal Markdown source (including front matter, code and destinations),
not rendered text or regex. In-document Find and workspace search share
`LiteralSourceMatcher`: Unicode simple case folding, no normalization, UTF-16
ranges, non-overlapping matches and scalar-safe chunk boundaries.

Every open session supplies an overlay, even a clean-but-conflicted buffer.
Listeners compare text rather than the dirty flag, so successive dirty edits,
undo, reload and save races remain current without cursor-triggered indexing.
An old save baseline never replaces newer input. Root epochs, query generations,
metadata revisions and native disk stamps discard obsolete work. Result clicks
recheck their revision, then use the existing `openPath`/session and compare the
opened text exactly before temporarily showing the existing Source Find surface.
Search never saves, reloads, or replaces source. A standalone-file grant searches
only open buffers and never enumerates a parent folder.

`AppleWorkspaceIndexSource` uses new native scoped metadata/local-text channels.
`WorkspaceFileScope` shares pinned-root/no-follow descriptor safety with image
attachments while `WorkspaceTextScope` has a separate Markdown allow-list and
never downloads or coordinates cloud documents. It turns materialization off
for the worker thread, rejects dataless files, bounds byte reads and checks the
file descriptor and rooted path identity before/after reading. There is no Dart
absolute-path `File` read fallback. Image policy/cache is unchanged and separate.

Bounds: 5 MiB per disk source; 32 MiB UTF-16 body LRU (not an RSS claim); at most
two Dart body reads and one native search queue; 50,000 total catalog entries;
64 directory levels; native enumeration caps of 50,000 returned/100,000 visited
entries and a one-second progress deadline; 64 Ki UTF-16 literal query budget.
A syscall already in progress is not claimed to be forcibly cancellable. Source
matching yields between 16 Ki windows and directory traversal periodically
yields. The first 500 snippets are displayed, but scanning/counting continues;
there is no cumulative body-byte limit silently hiding later documents. Snippets
are bounded separately and do not retain full document bodies.

Offline, denied, oversized, changed, invalid, missing and incomplete sources are
visible separately from result display limits. Cancellation is visibly incomplete.
Search/refresh reconciles metadata (two-second reuse window for overlapping
consumers); loaded tree watchers and iCloud notifications are only hints. Manual
iOS providers are not claimed to have real-time or complete watchers. The shared
source implementation is included in the iOS host, but P1c exposes its search UI only in
the desktop editor; the iOS reading library is not yet a full-workspace search UI.

Synthetic Dart tests cover 1k/10k flat catalogs and sibling directories, exact IO
and consumer snapshot-application counts, partial deep trees, bounded cache and
concurrency, live buffer/save conflicts, stale epochs/revisions, partial coverage,
Unicode windows, and navigation. They are not measured end-user latency, memory
or Apple provider performance. Native synthetic filesystem tests, macOS build,
and unsigned iOS build are CI gates. Real sandbox/iCloud/Files behavior and
profile performance still need Apple-device acceptance.

## Wiki note links (P1d)

The reusable renderer reports `IanvsMarkdownLinkTarget` with an explicit
`markdown`, `wiki` or `tag` kind. Hosts may opt in without removing the legacy
`onTapLink`; only one callback is invoked. The app routes Wiki targets to
`WikiNoteResolver`, not through URI decoding or extension guesses in the existing
Markdown link service. Raw Wiki `%` characters remain filename characters.
Ordinary Markdown links and anchors keep their original behavior.

The resolver uses the session's `WorkspaceIndex.catalog()` and metadata-only
`catalogSnapshot`, sharing directory cache, single-flight reads, reconciliation,
partial status and lifecycle invalidation with the tree and source search. It
never creates a second filesystem catalog or reads bodies to find names.
Only `.md` notes inside the current selected workspace are candidates. Existing
sessions, including dirty or externally conflicted buffers, win over disk.
Case/NFC path aliases are coalesced only after scoped native file-descriptor
identity and actual stored-path verification; two real case-sensitive files are
never merged merely because their comparison keys match. Each new linked tab
retains the minimum per-file bookmark, so selecting another workspace does not
drop its authorized access at the next sandboxed launch.
Root-relative full paths (`folder/Note` or `/folder/Note`), explicit relative paths
(`./Note`, `../Note`) and unique bare basenames accept an optional `.md` suffix.
No path-suffix fallback is used for a missing explicit full path. NFC/case
comparison keys never replace actual filesystem identity; collisions require
choosing a full path, even if one candidate matches the exact spelling. An
incomplete catalog cannot prove uniqueness or absence.

The **Insert note link** action (Command/Control-Shift-K) filters the shared local
catalog and inserts an explicit vault-root path. At an unfinished `[[target`, it
completes that target without consuming following prose. Existing `#fragment`,
`|display alias`, delimiters, all unrelated UTF-16 source units and line endings
are preserved. The edit is one undo unit and is rejected after source, selection,
mode, composition, tab or workspace changes. This is an explicit picker, not an
automatically opening suggestion menu on every `[[` keystroke.
The compact action shares the existing document-context row; it does not consume
an extra toolbar row. Its tooltip, semantic label and keyboard shortcut remain
available at larger text scales. Empty outline guidance and the picker body can
scroll rather than clipping when vertical space is limited. In Live mode, a
focused local table/property editor is not assumed to map to the source caret:
use the document body or Source mode instead. That local target remains remembered
across toolbar focus changes and invalidates an already pending insertion.

Clicking a missing note offers **Create note**, with the exact root-relative
filename. Cancel writes nothing. Confirmation is followed by fresh catalog
reconciliation; a changed target requires another click. Creation is an empty
`.md` file through a separate root-relative native capability. Creation cooperates
with `NSFileCoordinator` on a dedicated write queue, with a five-second cancellation
deadline so a stalled presenter does not block catalog reads. The selected root
and existing parent descriptors use no-follow traversal; the final open uses
`O_CREAT | O_EXCL | O_NOFOLLOW`. It never creates parents, borrows favorites or
operation-folder grants, downloads provider files, truncates or replaces a file.
Root, parent and target identities are checked before/after creation. Observed
changes fail without navigation, retry or deletion. This is not a cross-directory
atomic transaction against non-cooperating external renames: an originally
authorized parent can be moved outside the vault in the final syscall window,
leaving an empty file in that moved directory even though verification reports
failure. Flush failure can also leave an empty file. These outcomes are disclosed
and never retrospectively deleted, because another writer may now own the path.
Editing/saving the resulting session uses the existing P0 guarded save path. Opening existing targets uses `index.read()` directly,
without an ordinary file-read fallback that could download or follow a symlink.

P1f adds bounded YAML aliases to bare-name resolution through the shared
source-preserving reference index. The insertion picker remains filename-based;
the truncated property-card UI model is never used as an alias database.
Wiki heading/block navigation, non-`.md` note
matching, cross-vault navigation, link-aware rename transactions and graphs are
not implemented in this phase. Display aliases (`[[Note|label]]`) still render
and route normally. These conservative duplicate-name rules are not a claim to
reproduce undocumented Obsidian priority rules. Reference behavior was checked
against the official [Internal links](https://help.obsidian.md/links) and
[Settings](https://help.obsidian.md/settings) documentation.

Synthetic Dart/widget tests cover source fidelity, UTF-16, IME, dirty sessions,
case/NFC ambiguity, raw Wiki paths, partial catalogs, creation cancellation,
collisions, failure and stale tab/scope results. Native acceptance scenarios live
in `native_attachment_test.swift`; Linux source-contract tests do not establish
Swift compilation, real sandbox/iCloud behavior or Apple UI/device acceptance.


## Source references, backlinks and tags (P1f)

`WorkspaceController.references` owns a read-only semantic projection of
`WorkspaceIndex` effective snapshots. Dirty/clean open buffers win over disk,
every text revision invalidates the note projection, and scope/catalog epochs
gate publication and navigation. No separate filesystem scan or implicit cloud
download is allowed. Markdown and Wiki source spans, shared reference-definition
identity, body/YAML tags and complete bounded aliases come from the storage-free
core parser, not rendered UI models.

Backlinks use the existing compact document actions row; rendered tag clicks
in Read mode open postings from the same index. Live Preview keeps its existing
tag-click caret/source-editing behavior. Results distinguish unknown coverage from absence,
retain exact revision-bound source ranges, and reuse dirty tabs and source-find
navigation. UI display limits do not truncate the index. `previewImpact` exposes
confirmed/possible rename-affected references only; it does not perform writes.
Cross-file rename requires a later journal/CAS implementation and source-mapped
per-cell table parsing. Table bodies currently contribute explicit unknown
coverage, never guessed references or tags. A forced metadata refresh queued
during a scan must rerun before publishing to any joined caller.

See [reference-index contract](../doc/WORKSPACE_REFERENCE_INDEX.md) and
[parser semantic boundaries](../doc/NOTE_SEMANTICS.md) for budgets, supported
syntax, URI decoding, collision rules, incomplete coverage and test evidence.

正文查找的大文档索引由 `BodySearchWorker` 执行：每个查找会话延迟启动一个 isolate，
在后台缓存当前原文的语义索引。最多一个请求运行、一个最新请求等待；被替代的等待请求返回空取消结果，
不与“零命中”混淆。关闭查找终止 isolate。主控制器在接收结果时重新校验查询代次、原文和组合输入，
预算拒绝或后台失败均显示正文搜索不可用并保留显式源码入口。小文档继续使用防抖后的本地缓存索引。

桌面 Read/Live 文内查找默认保持正文组件挂载并使用正文索引；显式切换到 Source 时，
源码选区定位必须延迟到该帧旧 Live 编辑监听器卸载后，防止 YAML 等隐藏元数据命中被重定向。
关闭正文查找保留既有编辑选区，直接恢复原编辑焦点；只有临时 Source 查找需要重新激活 Live 表面。

### Native PDF table pagination (2026-10-26)

The macOS host declares `com.apple.security.network.client` in all four signing
configurations because sandboxed WKWebView needs it to launch even when loading
only an in-memory HTML string. A same-binary sandboxed probe on macOS 27.0.1
terminated without this entitlement and loaded with it. This is an app-wide
outgoing-network capability, not a domain-specific permission. PDF export still
uses a nonpersistent data store, disabled document JavaScript, content blocking
rules and a navigation allowlist; the entitlement does not authorize remote
document resources. The signing checker verifies this and the print entitlement,
including a selected built mode via `--built-apps --build-mode Profile`.

`OfflineDocumentPrintJob` keeps document JavaScript disabled. Before starting the
print factory, it runs a fixed application-owned layout function in WebKit's
isolated default client world. After fonts and images settle, it measures rows
at the A4 printable width, splits long tables into page-sized blocks with cloned
headers and fixed column widths, and keeps short tables together. No Markdown or
persisted file is changed. The existing output deadline covers preparation.
The job holds its owner-token print lease during preparation; terminal failure
or cancellation releases it, and late layout callbacks cannot start printing.
A single row taller than the page fails explicitly; tables are bounded to 5,000
rows and 256 generated blocks. These are rejection limits, never truncation.
Native acceptance checks repeated headers, nonblank pages, unchanged original
content, oversized-row cleanup, and a successful subsequent graphics export.

### Transaction provenance preservation

Native note transactions accept the macOS-generated `com.apple.provenance`
extended attribute only, bounded to 4 KiB. Its actual bytes are captured in the
source snapshot and private journal, compared during conflict/recovery checks,
and retained on replacement and recovery files. Existing journals without the
optional field represent an absent attribute. Other extended attributes, ACLs,
unsupported flags and ownership still fail closed.

The executor never removes provenance. If a newly created artifact differs from
the original, it attempts an exact copy and reads it back before writing document
bytes. A successful `fsetxattr` return alone is insufficient: on the tested macOS
version an attempted different value can be ignored. Failure to preserve the
value (including absence) aborts that artifact operation. Recovery receipts also
verify provenance, mode, owner, group and data protection before treating a copy
as complete. This does not provide general extended-attribute migration support.
