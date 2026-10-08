# 平台能力与构建证据

更新：2026-10-08。对应 R3-01 的首批盘点，任务尚未完成。范围是 Flutter Markdown 组件库；Linefold 宿主已有界面或某个平台的项目目录不等于核心库完成该平台验收。发布版本仍为 0.3.1，本轮代码在 Unreleased。

## 当前证据

| 环境 | 已验证范围 | 证据与限制 |
| --- | --- | --- |
| Ubuntu 24.04，Flutter 3.44.0 / Dart 3.12.0 | 核心分析、格式、widget 测试、发布快照及仓库外宿主测试 | [R1 最终 Core](https://github.com/robinfai/ianvs-markdown/actions/runs/37721969995)；不是 Linux 桌面二进制验收 |
| Ubuntu 24.04，Flutter 3.47.6 / Dart 3.13.5 | 同上，格式仍由 Dart 3.12 统一 | 同一 Core 矩阵；不自动扩大平台支持范围 |
| macOS CI，Flutter 3.44.8 | App/可选 Mermaid/Quick Look 回归；核心与 Mermaid 两个示例 Debug 构建 | [R1 最终 Native](https://github.com/robinfai/ianvs-markdown/actions/runs/37721970026)；runner 为 macos-15，实际运行环境以日志为准 |
| 本机 macOS 27.0.1、arm64，Flutter 3.44.8 / Dart 3.12.2 | R2 核心 842 项、示例 6 项；176 个公共符号编译、发布快照及包外宿主通过 | 基于 `e131698`；未修改日常 Flutter SDK |
| 本机 macOS 27.0.1、Xcode 27.0 (27A266a)、Rust 1.90.0 | 最小 macOS 示例 Profile / Release 候选构建 | 结果见下节；构建通过不等于完成真机交互验收 |

Core 的最低 SDK 与较新 SDK 组合都固定在 [CI 工作流](https://github.com/robinfai/ianvs-markdown/blob/main/.github/workflows/core.yml)，原生回归使用 [独立工作流](https://github.com/robinfai/ianvs-markdown/blob/main/.github/workflows/integrations.yml)。SDK 升级需重新验收，不能用某一次本地通过替换整个矩阵。

## macOS 候选构建

最小宿主使用 [example](../example/README.md)，核心仍包含 `super_clipboard` 原生插件依赖。首次普通 Profile 构建因 `proc-macro-error` 无法加载 `proc_macro_error_attr` 失败。使用仓库已有的 macOS 27 构建环境配置重试，未修改 Flutter 或第三方包源码：

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

构建过程还提示 `irondash_engine_context` 和 `super_native_extensions` 尚未采用 macOS Swift Package Manager，当前使用 CocoaPods 路径。R1-04 评估剪贴板适配层时需要一起核对；这里只记录当前构建提示，不推断未来 Flutter 的截止版本。

示例声明 macOS 12 最低部署目标，并未因此证明已在 macOS 12 真机运行。R0 profile 性能基准使用的临时 windowing 补丁，仅用于受控性能归因，不能作为未修改 SDK 的候选版本验收。历史记录见 [R0 报告](https://github.com/robinfai/ianvs-markdown/blob/main/benchmark/ACCEPTANCE-2026-10-07.md)。

## 核心库能力矩阵

“待验收”表示没有足够证据，并不等于已确认不支持。首先完善 macOS，再由首个实际仓库外宿主需求决定下一平台。

| 平台 | 正文/阅读 | 完整编辑与键盘 | 触摸 / IME | 富文本剪贴板 | 无障碍 |
| --- | --- | --- | --- | --- | --- |
| macOS | widget 回归、示例 Debug 构建通过；候选构建见上节 | Source / Live / Reading、保存、撤销、模式切换自动回归通过 | 真实输入法组合、候选窗、焦点切换待验收；鼠标测试不能代表触摸 | GFM/原文转换与注入 writer 回归通过；跨应用原生粘贴待验收 | 已有语义节点测试；VoiceOver 实机验收待补 |
| Linux | Linux runner 上的 widget 回归通过；桌面构建待验收 | 桌面交互待验收 | 待验收 | 原生插件构建与跨应用粘贴待验收 | 待验收 |
| Windows | 构建与运行待验收 | 待验收 | 待验收 | 待验收 | 待验收 |
| iOS | 核心最小宿主构建与运行待验收 | 待验收 | 触摸选择、软键盘与 IME 待验收 | 待验收 | VoiceOver 待验收 |
| Android | 构建与运行待验收 | 待验收 | 触摸选择、软键盘与 IME 待验收 | 待验收 | TalkBack 待验收 |
| Web | 编译、资源注入与浏览器运行待验收 | 待验收 | 浏览器 IME 与触摸待验收 | 权限、HTML/纯文本复制待验收 | 浏览器键盘与读屏待验收 |

图片、文件链接与图表的具体权限由宿主控制；注入 builder 只提供入口，不自动证明对应平台的 I/O、解码或渲染能力。传入 `clipboardWriter` 可替换复制行为，但不能删除包级原生构建依赖。

## 可选 Mermaid 适配器

核心库不依赖 `ianvs_mermaid`；适配器 `publish_to: none`，当前不作为核心发布包的一部分。[构建 hook](https://github.com/robinfai/ianvs-markdown/blob/main/packages/ianvs_mermaid/hook/build.dart) 的目标映射与实测状态需分开看：

| 目标 | Hook 是否接受 | 当前验证 |
| --- | --- | --- |
| macOS arm64 / x64 | 是 | macOS CI 的 Rust、Dart、图形回归及适配器示例 Debug 构建通过；未分别完成两个架构的发行验收 |
| Linux x64 / arm64 | 是 | 尚无该平台的完整原生构建和图形验收记录 |
| Windows x64 | 是 | 尚无该平台的完整原生构建和图形验收记录 |
| 其他桌面架构、iOS、Android、Web | 无目标映射 | 不应按当前适配器可用平台接入；有实际需求后独立实现与验收 |

## 后续执行与退出标准

1. 将候选构建结论纳入版本决策。若使用其他 SDK 或主机规避失败，记录完整工具链、原始错误与未修改 SDK 的结果；不能直接把临时 SDK 补丁带入正式支持声明。
2. 为 macOS 记录真实 IME、焦点、跨应用复制、键盘选择及 VoiceOver 检查。按正文、View、Source、Live 分别执行，覆盖 standard 阅读与默认 Obsidian 编辑。
3. R1-04 完成三种最小接入样例与剪贴板依赖决策；R3-02 在仓库外只读宿主和编辑宿主中验证实际使用的平台能力。
4. 选定下一平台后增加该平台的最小构建与设备验收，不通过扩展 CI 标签来替代设备交互测试。Mermaid 单独维护证据。
5. R3-01 只有在每项拟声明支持的能力均有构建和交互证据、未覆盖项明确标注时完成。目前仍处于首批验证阶段。
