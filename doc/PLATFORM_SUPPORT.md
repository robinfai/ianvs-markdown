# 平台能力与构建证据

更新：2026-10-10。对应 R3-01 的持续盘点，任务尚未完成。范围是 Flutter Markdown 组件库；Linefold 宿主已有界面或某个平台的项目目录不等于核心库完成该平台验收。发布版本仍为 0.3.1，本轮代码在 Unreleased。

## 当前证据

| 环境 | 已验证范围 | 证据与限制 |
| --- | --- | --- |
| Ubuntu 24.04，Flutter 3.44.0 / Dart 3.12.0 | 核心分析、格式、widget 测试、发布快照及仓库外宿主测试 | [R1 最终 Core](https://github.com/robinfai/ianvs-markdown/actions/runs/37721969995)；不是 Linux 桌面二进制验收 |
| Ubuntu 24.04，Flutter 3.47.6 / Dart 3.13.5 | 同上，格式仍由 Dart 3.12 统一 | 同一 Core 矩阵；不自动扩大平台支持范围 |
| macOS CI，Flutter 3.44.8 | App/可选 Mermaid/Quick Look 回归；核心与 Mermaid 两个示例 Debug 构建 | [R1 最终 Native](https://github.com/robinfai/ianvs-markdown/actions/runs/37721970026)；runner 为 macos-15，实际运行环境以日志为准 |
| 本机 macOS 27.0.1、arm64，Flutter 3.44.8 / Dart 3.12.2 | R2 核心 842 项、示例 6 项；176 个公共符号编译、发布快照及包外宿主通过 | 基于 `e131698`；未修改日常 Flutter SDK |
| 本机 macOS 27.0.1、Xcode 27.0 (27A266a)、Rust 1.90.0 | 最小 macOS 示例 Profile / Release 候选构建 | 结果见下节；构建通过不等于完成真机交互验收 |
| 本机 macOS 27.0.1、arm64，Flutter 3.44.8 / Dart 3.12.2，2026-10-10 | 完整 `make check`、Linefold macOS Debug / iOS Simulator Debug 构建通过 | 代码对应 `603187c`；核心 842、示例 6、app 274（跳过 1 项可选语料）；Mermaid Flutter 9 / Rust 4、原生示例 3、Quick Look Rust 8 / Swift 10 和原生导入通过。宿主构建不替代平台交互验收 |

Core 的最低 SDK 与较新 SDK 组合都固定在 [CI 工作流](https://github.com/robinfai/ianvs-markdown/blob/main/.github/workflows/core.yml)，原生回归使用 [独立工作流](https://github.com/robinfai/ianvs-markdown/blob/main/.github/workflows/integrations.yml)。SDK 升级需重新验收，不能用某一次本地通过替换整个矩阵。

## macOS 候选构建

以下为基线 `e131698` 的历史候选构建，使用 [example](../example/README.md)，当时核心仍包含 `super_clipboard` 原生插件依赖。R1-04 已将它移到可选适配器，历史大小和成功结果不能替代新入口的候选构建。首次普通 Profile 构建因 `proc-macro-error` 无法加载 `proc_macro_error_attr` 失败。使用仓库已有的 macOS 27 构建环境配置重试，未修改 Flutter 或第三方包源码：

```sh
cd example
CARGO_PROFILE_RELEASE_STRIP=none FLUTTER_XCODE_ARCHS=arm64 flutter build macos --profile
CARGO_PROFILE_RELEASE_STRIP=none FLUTTER_XCODE_ARCHS=arm64 flutter build macos --release
```

| 模式 | 结果 | 产物 |
| --- | --- | --- |
| Profile | 通过，未修改 Flutter 3.44.8；上述构建环境配置 | `build/macos/Build/Products/Profile/Ianvs Markdown Playground.app`，约 40.0 MB |
| Release | 通过，同一源码与工具链 | `build/macos/Build/Products/Release/Ianvs Markdown Playground.app`，约 27.7 MB |

源码基线为 `e131698`。本次只验证构建，没有安装、发布或完成真实输入法/剪贴板/无障碍验收。SDK 在验证前后均无源码改动；这次 3.44.8 的结果不替代最低 3.44.0 的独立 Profile/Release 验收。

构建过程还提示 `irondash_engine_context` 和 `super_native_extensions` 尚未采用 macOS Swift Package Manager，使用 CocoaPods 路径。R1-04 拆分后，这一要求属于显式接入原生剪贴板适配器的宿主；这里只记录当前构建提示，不推断未来 Flutter 的截止版本。

示例声明 macOS 12 最低部署目标，并未因此证明已在 macOS 12 真机运行。R0 profile 性能基准使用的临时 windowing 补丁，仅用于受控性能归因，不能作为未修改 SDK 的候选版本验收。历史记录见 [R0 报告](https://github.com/robinfai/ianvs-markdown/blob/main/benchmark/ACCEPTANCE-2026-10-07.md)。

## 三 SDK、六入口的候选复核（2026-10-10）

在已合入的 `6b2db7f` 上，未修改 Flutter 3.44.0、3.44.8、3.47.6 各执行
纯 Flutter 对照及 Body / Reading / Editor / playground / Streaming 的 Profile、Release，
共 36 次。对照、Body 和 playground 共 18 次通过；Reading、Editor、Streaming 共 18 次
在 `_window_macos.dart / _Rect` 的 AOT 快照生成阶段失败。最低 SDK 候选已执行，
结果仍未满足完整入口支持条件。工具拒绝补丁 SDK 与重复证据标签，成功产物均检查架构。

逐入口结果、原始日志、源码/SDK 哈希、锁文件及 12 行公共 View 入口复现见
[候选构建复核](../benchmark/MACOS-CANDIDATES-2026-10-10.md)。
本次仅验证 macOS arm64 构建，没有执行候选产物的真实输入/剪贴板/无障碍验收。
R2 性能分支的后续优化仍需重验，R3-01 保持进行中。

## 核心库能力矩阵

“待验收”表示没有足够证据，并不等于已确认不支持。首先完善 macOS，再由首个实际仓库外宿主需求决定下一平台。

| 平台 | 正文/阅读 | 完整编辑与键盘 | 触摸 / IME | 富文本剪贴板 | 无障碍 |
| --- | --- | --- | --- | --- | --- |
| macOS | widget 回归、示例 Debug 构建通过；候选构建见上节 | Source / Live / Reading、保存、撤销、模式切换自动回归通过 | 真实输入法组合、候选窗、焦点切换待验收；鼠标测试不能代表触摸 | GFM/原文转换与注入 writer 回归通过；跨应用原生粘贴待验收 | 已有语义节点测试；VoiceOver 实机验收待补 |
| Linux | Linux runner 上的 widget 回归通过；桌面构建待验收 | 桌面交互待验收 | 待验收 | 原生插件构建与跨应用粘贴待验收 | 待验收 |
| Windows | 构建与运行待验收 | 待验收 | 待验收 | 待验收 | 待验收 |
| iOS | Linefold 阅读宿主已有模拟器构建/运行记录，详见下节；核心独立最小宿主待验收 | 阅读宿主未开放编辑；完整编辑待验收 | 触摸选择、软键盘与 IME 待验收 | 待验收 | VoiceOver 待验收 |
| Android | 构建与运行待验收 | 待验收 | 触摸选择、软键盘与 IME 待验收 | 待验收 | TalkBack 待验收 |
| Web | 编译、资源注入与浏览器运行待验收 | 待验收 | 浏览器 IME 与触摸待验收 | 权限、HTML/纯文本复制待验收 | 浏览器键盘与读屏待验收 |

图片、文件链接与图表的具体权限由宿主控制；注入 builder 只提供入口，不自动证明对应平台的 I/O、解码或渲染能力。R1-04 后核心默认通过 Flutter 写 Markdown 纯文本，不包含原生剪贴板插件；需要双格式输出的宿主显式选择适配器。移除依赖不能代替系统复制权限、跨应用粘贴或真实设备验收。

## R1-04 依赖拆分与新的构建边界

同一 Flutter 3.44.8、macOS 27.0.1 arm64 环境的三个临时阅读宿主 Debug 对照中，移除原生后端后不再解析/注册 `device_info_plus`、`irondash_engine_context` 和 `super_native_extensions`。默认原生、注入纯文本但保留依赖、移除后端三组均完成项目首次和重复 Debug 构建。具体数值、缓存范围及迁移见 [依赖决策](CLIPBOARD_DEPENDENCY_DECISION.md)。

实际拆分实现通过完整 `make check`：核心 902、核心示例 9、剪贴板适配器 5、app 274（可选语料跳过 1），原有 Mermaid / Quick Look / 文件导入检查通过；146 文件、约 616 KB 的 Pub 快照零警告，包外示例和新宿主依赖图均不包含原生后端。对核心 example 执行 `flutter clean` 后，`make build-examples` 的 `body.dart`、`reading.dart`、`editor.dart`、`main.dart` 四个 macOS Debug 入口全部成功，未注册 macOS 插件，产物框架仅有 App 和 FlutterMacOS。CI 已纳入这四个入口与显式使用原生剪贴板的 Mermaid 宿主；远端结果按相应 PR 的 Checks 单独确认。

最小阅读入口的 Release 构建曾在未修改 SDK 的 `_window_macos.dart / _Rect` 出现 `illegal cid, full-aot`；该入口的失败不被历史 playground Release 成功抵消。本轮没有用补丁 SDK 把它记为通过。新入口的最低 SDK、Profile/Release 候选与真实交互仍需要逐入口记录。

原生剪贴板适配器是独立源码包，当前未发布。其自动测试验证同一 item 双格式、不可用/初始化失败/写入失败时完整 Markdown 回退，以及最终写入失败的错误传播；没有触碰系统剪贴板。Linefold 与 Mermaid 宿主显式接入后仍需在候选版本执行真实跨应用粘贴，不能用这些单元回归扩大平台支持声明。

## Linefold iOS 宿主证据的范围

本次提交纳入 [iOS 阅读入口](https://github.com/robinfai/ianvs-markdown/blob/603187c46b3308719df97c0c060f72cafb330a39/app/lib/src/preview/preview_app.dart)、原生文件导入与共享 Apple 工作区。此前保留在工作区的 [2026-10-04 验证记录](https://github.com/robinfai/ianvs-markdown/blob/603187c46b3308719df97c0c060f72cafb330a39/app/RENDERING-VALIDATION.md) 包括模拟器 Debug/无签名 iPhone Release 构建、冷启动和运行中文件 URL 交付、原生 XCTest，以及模拟器中文图表检查。这些是有日期的宿主历史记录，不作为 2026-10-10 重新执行的设备验收。

2026-10-10 在未修改的 Flutter 3.44.8 / Xcode 27.0 上重新运行 Linefold macOS Debug 与 iOS Simulator Debug 构建，均通过；iOS 使用 `--simulator --debug --no-codesign`。两次构建设置 `CARGO_PROFILE_RELEASE_STRIP=none`，macOS 另外设置 `FLUTTER_XCODE_ARCHS=arm64`。iOS 原生剪贴板依赖仍通过 CocoaPods 集成，构建提示尚未采用 Swift Package Manager；这继续作为 R1-04 的依赖成本依据，不推断未来工具链的支持期限。

同日 iPhone 18 Pro / iOS 27 模拟器 XCTest 三项通过：八个中文字符生成不同且非空的轮廓、导入副本在源文件删除后保留且同名隔离、工作区远端占位文件枚举与协调读写。它验证原生逻辑和字形轮廓，不代替真机分享界面、读屏或人工视觉检查。目前 CI 的 Native integrations 仍是 macOS job，iOS 构建和 XCTest 为本机证据。

物理 iPhone 的本地存储版本曾完成签名、安装和启动；原记录明确未独立检查真机中文字形。第三方发送应用/文件提供方的完整分享流程、真机触摸与读屏仍需验收。自动跨设备 iCloud 同步还需要能够配置共享容器的开发者团队，Personal Team 本地版本不提供这项证据。

Linefold 使用仓库内核心路径依赖，因此不算 R3-02 的仓库外只读宿主。Mermaid 的字体及原生构建证据只适用于适配器，不扩大核心编辑器的平台承诺。

## 可选 Mermaid 适配器

核心库不依赖 `ianvs_mermaid`；适配器 `publish_to: none`，当前不作为核心发布包的一部分。[构建 hook](https://github.com/robinfai/ianvs-markdown/blob/main/packages/ianvs_mermaid/hook/build.dart) 的目标映射与实测状态需分开看：

| 目标 | Hook 是否接受 | 当前验证 |
| --- | --- | --- |
| macOS arm64 / x64 | 是 | macOS CI 的 Rust、Dart、图形回归及适配器示例 Debug 构建通过；未分别完成两个架构的发行验收 |
| Linux x64 / arm64 | 是 | 尚无该平台的完整原生构建和图形验收记录 |
| Windows x64 | 是 | 尚无该平台的完整原生构建和图形验收记录 |
| iOS arm64 设备、arm64 / x64 模拟器 | 是 | 已增加 hook 目标及 SDK 配置；iOS 内嵌 OFL 中文字体。2026-10-10 arm64 模拟器 Debug 构建通过，历史图形证据见上节；各架构及真机图形发行验收未全部完成 |
| 其他桌面架构、Android、Web | 无目标映射 | 不应按当前适配器可用平台接入；有实际需求后独立实现与验收 |

## 后续执行与退出标准

1. 将候选构建结论纳入版本决策。若使用其他 SDK 或主机规避失败，记录完整工具链、原始错误与未修改 SDK 的结果；不能直接把临时 SDK 补丁带入正式支持声明。
2. 为 macOS 记录真实 IME、焦点、跨应用复制、键盘选择及 VoiceOver 检查。按正文、View、Source、Live 分别执行，覆盖 standard 阅读与默认 Obsidian 编辑。
3. R1-04 完成三种最小接入样例与剪贴板依赖决策；R3-02 在仓库外只读宿主和编辑宿主中验证实际使用的平台能力。
4. 选定下一平台后增加该平台的最小构建与设备验收，不通过扩展 CI 标签来替代设备交互测试。Mermaid 单独维护证据。
5. R3-01 只有在每项拟声明支持的能力均有构建和交互证据、未覆盖项明确标注时完成。目前仍处于首批验证阶段。

## R2-03 流式入口的构建证据（2026-10-10）

在 `dba969d` 的独立工作树上，未修改 Flutter 3.44.8 / Dart 3.12.2，
`flutter build macos --debug --target lib/streaming.dart` 通过。最终样例静态分析、
完整 `make check` 和包外快照测试通过；记录及源码哈希见
[R2-03 验证摘要](../benchmark/results/2026-10-10-streaming/validation.json)。
该入口已加入 `make build-examples`；PR #10 的 Core / Native 门禁通过后已合入 `6b2db7f`。
初次 Debug 记录采集时主机锁定；本轮候选矩阵见上节。构建和自动回归不是触摸、
真实 IME、跨应用复制、读屏或性能验收。
