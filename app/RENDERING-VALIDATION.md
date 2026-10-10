# LLM principles corpus: macOS app validation

Verified on 2026-09-26, macOS 27 / Apple Silicon. Corpus:
`/Users/robinfai/Downloads/llm-principles-series/`.

Current implementation: Mermaid and supported standalone SVGs use native usvg
preprocessing and Flutter vectors. The WebView implementation described in the
earlier entries below is historical; it has been removed. Unsupported standalone
SVGs offer an explicit action to open the file in the system's default viewer.

## Fixes

- Connected the app's Mermaid callback to the shared native renderer. A local
  WKWebView displays SVG markers and Chinese labels, including HTML labels in
  linked SVG assets. The page disables scripts, navigation, and remote resources.
- Reused the example's dylib normalization in both macOS builds. Bundled Merman
  no longer refers to an absolute path on its publisher's build machine.
- Fixed Read-mode multiline links being clipped by table rows. Live editing
  retains the span representation needed for source projection.
- Connected relative Markdown links, heading fragments, local image previews,
  and external links. Existing dirty tabs are preserved. Sandbox denial now
  explains how to grant access with File → Open Folder….
- Escaped two probability-formula pipes on line 17 of the corpus's
  `MATH-NOTES.md`, restoring its table to three columns. Updated that file's
  `MANIFEST.sha256` entry. Original files are backed up at
  `/private/tmp/linefold-series-original/`.

## Automated evidence

- Root library: **896 tests passed**, including the table-height regression and
  Live link/source-editing regressions.
- App with `LLM_SERIES_DIR`: **208 tests passed**. The acceptance suite scrolls
  all **57 Markdown documents** in both Read and Live modes, checks for render
  exceptions and table-link overflow, and verifies source remains unchanged.
- All **25 Mermaid sources** render through the bundled native engine and
  decode in the Flutter test renderer. WebView fidelity is checked separately
  in the running app because widget tests do not instantiate native WebViews.
- Example: **5 tests passed**, including native Mermaid rendering.
- Repository static analysis, formatting, and `git diff --check`: passed.
- Release build and installed app's deep code-signature verification: passed.

Reproduce the corpus checks from `app/`:

```sh
flutter test --dart-define=LLM_SERIES_DIR=/absolute/path/to/llm-principles-series
```

## Actual app checks

The installed Release app at `/Applications/Linefold.app` was relaunched and
restored its document tabs and selected corpus workspace.

- `INDEX.md`: wrapped article titles remain within their table rows.
- `MATH-NOTES.md`: three columns and a complete conditional-probability formula.
- `articles/04-attention.md`: arrows, curved connectors and Chinese text render
  in Read and Live. Clicking the Live diagram exposes its editable source.
- Its SVG and PNG links open complete images inside the app.
- The directory link opens `articles/01-request-lifecycle.md`; the installed
  Release app also displays that chapter's branching Mermaid diagram.
- A file-only permission failure was reproduced before opening the corpus
  folder. Folder access allows sibling chapters and image assets to load.

Ordinary links are editable in Live and followed in Read. Embedded image syntax
and Wiki embeds remain outside the shell's current integration; this corpus
contains no embedded Markdown images.

## Mermaid scrolling follow-up (2026-09-26)

- Reproduced in the installed app: scrolling over body text moved the document,
  while the same scroll over the Mermaid surface did nothing. The embedded
  WKWebView consumed native AppKit input before Flutter received it.
- Added a display-only macOS WebKit surface with native input hit-test
  passthrough and a transparent Flutter `AppKitView`. Rendering still uses
  WebKit with JavaScript, navigation, and remote resources disabled.
- Native AppKit regression test demonstrates ordinary WKWebView input capture
  and verifies passthrough after resize/removal. Flutter tests cover wheel and
  trackpad scrolling in both directions, enclosing editor clicks, and SVG updates.
- App suite: **95 passed**, with the optional corpus test skipped. Static
  analysis, Release build, and deep code-signature verification passed.
- In the new Release app, `01-request-lifecycle.md` scrolls up and down with the
  pointer inside the diagram in both Read and Live. Chinese labels and arrows
  remain visible, and a Live diagram click still exposes its editable source.

## Production vector pipeline follow-up (2026-09-26)

This supersedes WebKit rendering for Mermaid blocks described above. Local SVG
image previews still use WebKit because linked files include HTML labels.

- The shared package now renders real source through merman `resvg-safe`, CSS
  normalization, and an FFI usvg 0.45.1 bridge. usvg expands markers and outlines
  system font glyphs; Flutter `SvgPicture` displays the resulting vectors.
  Mermaid blocks contain no WebView and disable pan/zoom by default.
- Rendering and font discovery run on a persistent worker isolate. Requests
  are deduplicated, edits debounced, stale completions ignored, and disposal
  settles pending futures. The worker LRU is bounded by both entry count and
  byte size, with preprocessing/font identities included in cache keys.
- **3 Rust tests**, **6 shared-package tests**, **213 app tests** with the
  corpus enabled, and **5 example tests** passed. All **25 Mermaid sources**
  used the new native pipeline; all **57 Markdown documents** were scrolled
  in Read and Live using the production document widget and those actual results.
- Seven production FFI/Flutter screenshots were compared to the demo vector
  references. Five matched exactly; state differed by less than 0.001% of pixels
  and Attention by 0.2042%, within the 1% tolerance. Outputs and metrics are in
  `packages/ianvs_mermaid/build/visual-regression/`. The demo was not modified.
- Regression checks cover wheel/trackpad movement across a diagram boundary,
  Live click-to-edit, late results, errors, disposal/reopening, cache limits,
  native errors for unsupported SVG features, and caller event-loop progress.
  These checks do not claim a measured end-to-end frame-time improvement.
- Root, app, example, and shared-package static analysis passed. Rust formatting,
  Clippy with warnings denied, Dart formatting, and `git diff --check` passed.
- A clean macOS arm64 Release build includes the signed
  `ianvs_svg.framework` and the corresponding native-asset mapping. The build
  hook explicitly discovers the macOS SDK because Flutter filters `SDKROOT`
  from hook environments. Deep code-signature verification passed.
- Actual Release app: `01-request-lifecycle.md` scrolls in both directions with
  the pointer inside the Mermaid surface in Read and Live. Live clicking still
  exposes the unchanged source. `04-attention.md` displays Chinese, arrows and
  curves correctly; its separate SVG file link still opens a complete image.
- Updated and relaunched `/Applications/Linefold.app`. The installed native
  framework matches the validated build's SHA-256, passes deep signature
  verification, and loads the Attention diagram with working in-diagram scroll.

Font discovery/fallback, cache bounds, unsupported features, platform status,
and build instructions are documented in
[`packages/ianvs_mermaid/README.md`](../packages/ianvs_mermaid/README.md).
There is no automatic bitmap fallback. System fonts are discovered, not bundled.

## Complete embedded-browser removal (2026-09-26)

- Removed `webview_flutter` and all three platform/interface dependencies from
  the resolved package graph. Regenerated the macOS plugin registrant and
  CocoaPods lockfile without the WebView plugin.
- Removed `ReadOnlySvgView`, its factory/project entries, native input test and
  test script, HTML wrapper, platform-view code, and the network-client
  entitlement. The debug network-server entitlement remains for Flutter tooling.
- Standard local SVGs now use background usvg preprocessing and Flutter vectors.
  Native integration verifies Chinese glyphs and markers become visible paths.
  HTML labels, active filters and other unsupported features show a clear message
  with an explicit **Open in default app** action. This changes the previous
  in-app support for those complex SVG files; Mermaid blocks are unaffected.
- **214 app tests** (including all 57 corpus documents and 25 diagrams) and
  **7 shared-package tests** passed. SVG tests verify source updates, stale
  results, disposal, input propagation, and the external-open callback/channel.
  App/shared-package analysis, Dart formatting and `git diff --check` passed.
- Clean macOS arm64 Release build and deep code-signature verification passed.
  Inspected all **12 Mach-O binaries**: no WebView/WebKit load commands or bundled
  WebView frameworks. Signed app entitlements have no network-client capability.
- Installed and relaunched `/Applications/Linefold.app`. A standard SVG preview
  displays Chinese/Latin text, color and an arrow; an HTML-label SVG displays the
  unsupported-content message and external-open button. Temporary test tabs were
  closed and the original corpus workspace and Attention article restored.

## Separate corpus packaging observation

The original manifest lists both `preview/INDEX.html` and `preview/index.html`
with different hashes. On this case-insensitive volume they resolve to one
file, so the latter hash check fails. This pre-existing HTML-preview packaging
issue does not affect the Markdown app checks. The previews and those manifest
entries were not changed; the repaired `MATH-NOTES.md` checksum matches.

## Quick Look 系统预览（2026-09-30）

- 环境：macOS 27.0.1、Xcode 27、Apple Silicon。随 Linefold 安装数据型
  `work.ianvs.linefold.QuickLook` 扩展，支持宿主声明的 `.md` / `.markdown`。
- 原生渲染：8 个 Rust 测试和 10 项 Swift 检查通过，覆盖中文 GFM、真实
  merman SVG、箭头、错误图表、HTML/链接处理、重复标题、front matter、
  UTF-8/BOM/UTF-16、空文件、缺失文件、无效编码与有界读取。
- Finder 实测：安装后选中 `中文系统预览.markdown` 按空格，显示标题、中文、
  表格、任务列表、代码和三个中文节点的 Mermaid 流程图。箭头完整；光标位于
  图表时可滚动至文末。错误 Mermaid 保留源码，后续“文档结尾：预览完整”可见。
  本次看到的是系统 Quick Look HTML 内容，AX 标题为 `Linefold Markdown Preview`，
  不是浏览器或单独导出的 HTML 演示。
- 打包边界：Release 构建和深度签名检查通过。扩展的非系统动态依赖只有自身
  Frameworks 下的 `@rpath/libmerman_ffi.dylib`；无 Flutter 插件或构建机器绝对
  路径。沙箱开启，无网络客户端授权。安装脚本在替换旧应用前执行此检查。
- 本机临时签名沿用主应用策略。首次联调发现额外开启 Hardened Runtime 会因
  ad-hoc 签名没有 Team ID 拒绝动态库；已移除新扩展单独添加的该构建设置，
  没有增加禁用库校验的 entitlement，也没有修改系统安全设置。
- 既有回归：四个包静态分析和 Dart 格式检查通过；example 5 项、app 149 项
  （另有 1 项需外部语料而跳过）、Mermaid 7 项 Flutter 测试和 3 项 Rust 测试通过。
- `make check` **未全绿**：根包 796 项通过，`test/focus_geometry_test.dart`
  因既有跨包依赖无法加载。该测试引用 `app/lib/src/desktop_theme.dart`，而根包
  未声明应用使用的 `ianvs_design`；相关文件与 HEAD 完全一致。本次未修改这一
  无关依赖，已单独运行并通过被 `make check` 提前退出跳过的后续检查。
- 未验证：Intel 真机、macOS 12 真机、Developer ID 分发/公证，以及所有 Mermaid
  图类型与 Obsidian 专属语法的完整一致性。亮色 CSS 已实现，本次 Finder 实测
  使用系统当前的暗色外观。

复现入口：`make test-quicklook`、`make install`，以及
`bash app/tool/verify_quicklook_bundle.sh /Applications/Linefold.app`。
本机日志保存在 `app/build/quicklook-native-check.log`、`quicklook-build.log`、
`quicklook-check.log` 和 `quicklook-remaining-checks.log`（均不提交）。

2026-10-07 补充：上述根包加载问题已在组件库 R0-01 修复。真实主题布局测试
现位于 `app/test/focus_geometry_test.dart`，保留 111 项检查，并修复了宿主
填充输入框主题引起的焦点宽度偏移。后续结果以 [组件库迭代记录](../ROADMAP.md)
为准；上面的验证记录保留当时的结果。

## iOS reading preview — 2026-10-04

Validated with Flutter 3.44.8 / Dart 3.12.2 and Xcode 27.0:

- `flutter analyze` in `app/` and `packages/ianvs_mermaid/`: no issues.
- Full app suite: 160 tests passed, one optional corpus test skipped.
- `bash app/tool/test_native_markdown_import.sh`: native import checks passed.
- iOS Simulator XCTest: app-owned copies survive source removal, duplicate names
  remain separate, and reopening an imported copy does not duplicate it.
- Rust SVG bridge: three tests passed; formatting checks passed.
- iOS simulator Debug and unsigned iPhone Release builds succeeded.
- On an iPhone 18 Pro / iOS 27 simulator, system file-URL delivery opened a
  Markdown document from a terminated app and replaced it with a second
  document while the app was running. Chinese text, tables, formulas, code and
  Chinese Mermaid labels rendered successfully.
- After reinstalling the updated simulator build and relaunching, both imported
  documents remained visible in the recent library.

Local logs and screenshots are under `app/build/ios-preview*` (generated,
untracked artifacts). Physical-device signing and sharing from production
third-party apps / iCloud providers still require device acceptance. The
simulator file-URL test does not exercise a third-party share-sheet UI.

## iOS Chinese glyphs and default iCloud workspace — 2026-10-04

- A physical iPhone screenshot showed LastResort boxes for `阅读预览`. Scanning
  `/System/Library/Fonts` alone did not provide reliable Chinese coverage.
  Additional investigation with CoreText located iOS 27's `PingFangUI.ttc`, but
  its faces have no `glyf`/`CFF `/`CFF2` tables; usvg accepted the font metadata
  and silently emitted empty text. The new native glyph test reproduced that
  second failure before the final fix.
- iOS now embeds unmodified Noto Sans CJK SC Regular 2.004 under OFL 1.1, with
  its license in the package and bundled Flutter notices. LastResort and fonts
  without standard outline tables are excluded. Font-policy cache identity is
  bumped to version 2. Desktop's preferred family remains unchanged.
- Four Rust tests, seven Mermaid package tests (including seven production
  visual references), and 163 app tests pass; one optional corpus test is
  skipped. App static analysis reports no issues.
- Three iOS XCTest cases pass: each of the eight Chinese label characters
  produces a distinct nonempty outline; imported files remain owned copies;
  cloud stubs are listed and coordinated reads/writes enforce the size limit.
- The iOS 27 simulator displays both `分享文档 → Linefold → 阅读预览` and
  `繁體：閱讀預覽` correctly in the production reader. Screenshot:
  `app/build/ios-preview/mermaid-cjk-fixed.png`.
- macOS and iOS share a container identifier and default-workspace resolver.
  Tests cover choosing an external folder explicitly, returning to the default
  on file delivery/startup, unavailable iCloud, and preserving unsaved drafts.
- The iPhone local-storage Release build is signed and passes deep signature
  verification. After reconnecting the paired iPhone 17, the final repair build
  was installed and launched successfully on 2026-10-04. The on-device glyph
  appearance has not been independently inspected; the rendering acceptance
  above was performed in the simulator.
- The current Personal Team cannot provision iCloud (confirmed by Xcode's
  signing error). The standard projects retain iCloud configuration; the
  explicit local build omits that capability and labels local storage honestly.
  Actual cross-device iCloud synchronization remains unverified until an
  eligible team/container and both devices are available.

## Apple integration submission — 2026-10-10

Code baseline: `603187c` (Mermaid `fe1e559`, header `32f0e86`, Apple reader and
workspace `603187c`). The previously separate working-tree changes are now
committed together with their tests, font license, and design evidence.

Environment: unmodified Flutter 3.44.8 / Dart 3.12.2, macOS 27.0.1 arm64,
Xcode 27.0 (27A266a), Rust 1.90.0. SDK Git status was clean before and after.

- `CARGO_PROFILE_RELEASE_STRIP=none make check`: passed. Core 842, example 6,
  app 274 (one optional external-corpus test skipped), Mermaid Flutter 9 /
  Rust 4, adapter example 3, Quick Look Rust 8 / Swift 10, and native Markdown
  import checks passed. Formatting and all package analyses passed.
- Publication snapshot: 138 files, approximately 585 KB compressed, zero
  warnings; included example and external smoke host passed without resolving
  paths into this workspace. App, design screenshots and the CJK font remain
  excluded from the core publication. Final document changes are also checked
  by the PR's publication jobs.
- `CARGO_PROFILE_RELEASE_STRIP=none FLUTTER_XCODE_ARCHS=arm64 flutter build
  macos --debug` in `app/`: passed, using the default local signing configuration.
- `CARGO_PROFILE_RELEASE_STRIP=none flutter build ios --simulator --debug
  --no-codesign` in `app/`: passed.
- Xcode XCTest on iPhone 18 Pro / iOS 27 simulator: 3 passed, 0 failures.
  Tests verified eight distinct Chinese glyph outlines, imported copies after
  source removal and duplicate names, and coordinated workspace I/O/stub listing.

To repeat the simulator tests after the Flutter build, select an available
simulator ID and run from `app/`:

```sh
CARGO_PROFILE_RELEASE_STRIP=none xcodebuild \
  -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,id=<simulator-id>' \
  -derivedDataPath build/ios-xctest -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO test
```

Local logs and the XCTest result bundle are under
`build/roadmap/status-2026-10-10/` at the repository root. The iOS checks were
local; the existing Native integrations workflow covers macOS. This run did
not repeat visual QA, physical-device sharing, real iCloud cross-device sync,
or the controlled performance benchmark. The earlier limitations remain open.
