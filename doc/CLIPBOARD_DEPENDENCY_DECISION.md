# 剪贴板依赖成本与适配决策

日期：2026-10-10。R1-04，基线 `2a65a2c`。这是当前候选实现的决策，尚未发布新版本；不把包拆分当作无感知升级。

## 决策

将原生双格式写入移到可选包 `ianvs_markdown_clipboard`，核心移除 `super_clipboard` 依赖。理由是只读/纯文本宿主也为当前默认后端承担整个原生依赖链，注入 writer 不能消除该成本。测量证明真正移除依赖可以消除三个 macOS 插件和 16 个解析依赖；行为注入没有这个效果。

核心继续生成 `IanvsMarkdownClipboardData` 的 Markdown 和 HTML，保留现有类型、writer 参数及 `writeIanvsMarkdownClipboard` 签名。默认 writer 改为 Flutter 纯文本剪贴板，完整文档复制保留原始 Markdown。需要 HTML 的宿主显式选择原生适配器，仍在同一个剪贴板 item 写入 Markdown/HTML，原生后端不可用时回退完整 Markdown；纯文本写入也失败时向调用方报告错误。

Linefold 与原生 Mermaid 示例显式接入适配器以维持已有复制行为。核心的正文、阅读和编辑样例使用默认纯文本复制。适配器以 Markdown/HTML 两个字符串为边界，只依赖 Flutter 与 `super_clipboard`，避免绑定核心的候选版本和工作区路径；宿主在 writer 回调中传入这两个字段。

评估过的其他方案：

| 方案 | 收益 | 没有解决的问题 / 成本 |
| --- | --- | --- |
| 保留依赖，允许注入 writer | 默认富文本行为完全兼容 | 纯文本宿主仍解析、编译和打包原生插件；本次实测没有移除成本 |
| 同包提供纯文本入口文件 | Dart 调用代码可分开 | Flutter 按 pubspec 的插件依赖集成，不能通过 import 路径移除原生构建依赖 |
| 新建纯核心包，旧包作为兼容门面 | 旧 import 默认行为可维持 | 旧 `ianvs_markdown` 仍带原生依赖；需要迁移整套核心类型、包名及发布流程，超出仅隔离 writer 所需的边界 |
| **可选原生 writer（采用）** | 核心宿主不承担原生后端；现有 payload 与注入契约可复用 | 默认 HTML 写入改为显式接入，需要迁移说明、宿主更新和单独维护适配器平台证据 |

## 可复现测量

在同一未修改的 Flutter 3.44.8 / Dart 3.12.2、macOS 27.0.1 arm64、Xcode 27.0、Rust 1.90.0 上，从固定提交复制三个隔离宿主。三个宿主都使用相同最小 `IanvsMarkdownView`，内容、原生工程与构建模式一致：

```sh
python3 tool/measure_clipboard_cost.py \
  --revision 2a65a2c --mode debug \
  --flutter /path/to/flutter/bin/flutter \
  --output build/roadmap/r1-04/clipboard-cost
```

工具仅修改临时副本，第三组在副本里移除依赖和原生 writer。每组先解析依赖、显式执行 `pod install`，再运行一次项目首次构建和一次无源码变化的重复构建。保留 SDK/Pub/Cargo 下载与工具链缓存；这里的“首次”不是空白机器冷构建。设置 `CARGO_PROFILE_RELEASE_STRIP=none`、`FLUTTER_XCODE_ARCHS=arm64`，没有修改 SDK 或第三方缓存源码。

| 组别 | Pub 解析 | Pods 准备 | 首次 Debug 构建 | 重复 Debug 构建 | App 文件逻辑字节 | macOS 插件 |
| --- | --- | --- | --- | --- | --- | --- |
| 默认原生 writer | 0.881 s | 0.673 s | 29.258 s | 9.334 s | 148,108,048 | 3 |
| 注入纯文本 writer，保留原生依赖 | 0.950 s | 0.523 s | 28.774 s | 9.516 s | 148,112,568 | 3 |
| 临时移除原生后端 | 0.877 s | 0.621 s | 16.468 s | 8.220 s | 117,803,778 | 0 |

App 大小按普通文件逻辑字节累计、不重复计入符号链接；不是安装占用、压缩下载大小或 Release 大小。第三组相对第一组减少 30,304,270 字节（约 30.3 MB / 28.9 MiB，20.5%）。默认组中 `super_native_extensions.framework` 为 16,019,441 字节；其余差额也包含 Dart 依赖编译内容，不能全部归因于单个 framework。每组只有一对样本，顺序固定，共享缓存与系统负载存在影响；这些是本机观察值，不是性能阈值或其他平台的收益承诺。

原始日志、解析图及逐组 JSON 保存在 `build/roadmap/r1-04/clipboard-cost-v2/`（忽略目录）。本文保留结论和复现方法，后续工具/依赖升级应重测。

## 依赖与迁移边界

基线依赖主链：

```text
ianvs_markdown
└─ super_clipboard 0.9.1
   └─ super_native_extensions 0.9.1
      ├─ irondash_engine_context 0.5.5
      ├─ irondash_message_channel 0.7.0
      └─ device_info_plus 11.5.0
```

macOS 注册的三个插件为 `device_info_plus`、`irondash_engine_context`、`super_native_extensions`。后者的 CocoaPods 构建脚本调用 Cargokit/Rust；现有 Apple 工程还需要 Xcode 和 CocoaPods。插件声明支持的平台不等于本项目完成对应平台验收，仍以 [平台矩阵](PLATFORM_SUPPORT.md) 为准。

本次对照少解析的 16 项是 `super_clipboard`、`super_native_extensions`、`irondash_engine_context`、`irondash_message_channel`、`device_info_plus`、`device_info_plus_platform_interface`、`ffi`、`file`、`fixnum`、`flutter_web_plugins`、`pixel_snap`、`plugin_platform_interface`、`crypto`、`uuid`、`win32`、`win32_registry`。这只适用于该最小宿主；Linefold 的其他插件可能继续引入其中部分依赖。

迁移要求：

1. 需要原有双格式复制的宿主，在正文、View 和 Live Editor 的 `clipboardWriter` 显式调用适配器；仅需要完整 Markdown 的宿主可保留默认值。Source 的平台文本编辑复制语义不变。
2. 已集成 CocoaPods 的旧 macOS 工程移除最后一个插件后，Flutter 可能不再自动执行 `pod install`，旧工程仍引用 Pods 文件列表。本次首次无原生实验因此失败；统一显式准备 Pods 后通过。核心示例应清理旧 Pods 集成，再验证全新工程输出。不要删除宿主仍在使用的其他插件配置。
3. 适配器仍是原生插件，需单独跑构建、回退与真实跨应用复制验收；它不扩大核心平台声明。候选源码接入与最终发布版本配对在 R3-03 核对，不能提前声称已经发布。

## 尚未证明的范围

最小阅读入口的首次 Release 构建在 `_window_macos.dart / _Rect` 处出现 `illegal cid, full-aot`，未生成可比较产物；日志为 `build/roadmap/r1-04/clipboard-cost/default/first.log`。这与已有 [AOT 限制记录](https://github.com/robinfai/ianvs-markdown/blob/main/benchmark/README.md#macos-aot-prerequisite) 属于同一错误形态，本次没有用补丁 SDK 绕过，也没有证明由剪贴板导致。

因此本表只证明 Debug 依赖/产物差异。新入口的 Release/Profile、最低 SDK 候选构建及真实输入/跨应用粘贴继续归 R3-01；现有完整示例某次 Release 通过不能推定任意入口都通过。依赖拆分也不解决渲染前解析或 HTML 转换预算，后者仍由 R2-05 验收。
