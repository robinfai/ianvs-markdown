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
| Folder sidebar | `WorkspaceSidebar` + `FileBrowserController` | Virtualized visible rows; lazily cached directories form the incremental search index. No database is required. |
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

## Source-of-truth rules

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
