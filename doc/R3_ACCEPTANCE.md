# R3 双入口本地执行清单

更新：2026-10-12。用户已将当前目标改为围绕仓库内 example / app 推进，不等待上游修复，
不走独立验收宿主。本文替代 [原 R3 执行规程](https://github.com/robinfai/ianvs-markdown/blob/1f814eb39347716511170d47c32ed74a3d7eb413/doc/R3_ACCEPTANCE.md)；历史 AOT、实验和平台记录保留，未验证能力不补记通过。
任务状态以 [ROADMAP](../ROADMAP.md) 为准；以下是操作规程，实际结果单独留证。

## 1. 固定两个应用入口

| 入口 | 作用 | 操作范围 |
| --- | --- | --- |
| `example/lib/main.dart` | 无原生后端依赖的组件 playground | 默认完整语料，Live / Source / Reading、选择、撤销、保存回调、主题及安全资源回退 |
| `app/lib/main.dart` | Linefold 实际应用 | macOS 本地文件、工作区、多标签、保存/恢复、Mermaid 与剪贴板；iOS 分支按实际需求处理阅读 |

不另外创建临时 Flutter host；不将 `body.dart` / `reading.dart` / `editor.dart` /
`streaming.dart` 或 FFI fixture 作为当前任务的应用入口。它们仍可用于单项诊断和契约测试。
自动 Pub 快照 smoke 作为包内容质量检查保留，真实外部宿主验收已移出本轮计划。
当前首先验证本机 macOS；不据此扩大其他 OS、CPU、最低 macOS 或 SDK 的支持声明。

## 2. R3-01：构建与启动

从仓库根目录使用原版 Flutter 3.44.8（或实际明确选择并记录的工具链）：

```sh
make build-local          # 两个 main 的 Debug
make build-local-release  # 同两个 main 的 Release
make run-example          # 默认 example main
make run-app              # 默认 app main
```

可以用 `FLUTTER=/path/to/flutter/bin/flutter` 指定 SDK。app 的构建目标保留现有
`FLUTTER_XCODE_ARCHS=$(uname -m)` 和 `CARGO_PROFILE_RELEASE_STRIP=none` 配置。
不修改 SDK、不执行安装或覆盖 `/Applications`。Debug 与 Release 各自记录；构建通过
后直接打开该构建的 bundle，记录实际进程路径和产物哈希，不能误用旧安装包。

| 检查 | example | app |
| --- | --- | --- |
| Debug / Release 构建 | 使用 `lib/main.dart`，保留日志与退出码 | 同左，包含实际原生插件和 Quick Look 构建 |
| 冷启动 | 显示默认 Markdown 和三模式工具栏，无启动异常 | 显示工作区/文件 UI，无启动异常；iCloud 不可用时本地文件路径仍可用 |
| 基本操作 | 在 Source/Live/Reading 切换，能返回原文 | 新建或打开测试文档，切换模式，返回可编辑状态 |
| 证据边界 | 主入口通过不代表独立最小入口 AOT 修复 | 构建和启动不等于真机 IME、分享或无障碍已验收 |

若两个真实入口之一失败，优先修复该入口的可复现问题；不先展开独立矩阵或等待上游。

## 3. R3-02：应用内使用链路

在专用本地测试目录保存语料，保留用户原有文件与未保存文档。使用同一提交的两个主入口，
记录模式、步骤、预期/实际文本；真实 UI 与自动 widget 测试分开标记。

| 用例 | 入口与步骤 | 验收条件 |
| --- | --- | --- |
| L01 三模式保真 | example 输入含 YAML、中文、emoji、链接、表格的 Markdown，Source→Live→Reading→Source | 完整源码不变；改动可撤销/重做，选择与焦点能继续操作 |
| L02 示例保存 | example 编辑后触发保存，再 Reset example | 保存反馈符合回调语义；Reset 恢复默认语料和历史基线。示例不宣称磁盘持久化 |
| L03 本地文件闭环 | app 打开临时目录中的 Markdown，编辑、保存、关闭文档并重开 | 磁盘内容与捕获原文一致；标题、dirty、编码/换行信息正确 |
| L04 多文档与恢复 | app 在两个文件/未命名文档间切换，测试未保存关闭提示；重启恢复 | 文本、dirty 和文档归属不串；取消关闭保留内容；恢复路径按现有契约工作 |
| L05 保存期间编辑 | app 通过已有保存竞态/文件监视回归复验；真实 UI 用本地文件检查保存后新输入 | 旧确认不清除较新编辑，文件监视不误判自己的写入，错误和取消保留 dirty |
| L06 复制与资源 | 两个应用分别全选复制；app Read 检查本地链接、图像和 Mermaid | example 原文纯文本与 app 选择的双格式符合契约；只访问测试目录中的资源，失败有回退 |
| L07 大文档降级 | 在两个主入口输入超预算但可管理的测试文本，编辑、保存或复制 | 完整原文保留，观察预算结果和实际延迟；不以 debug 耗时作为性能基准 |
| L08 输入与无障碍 | 两个主入口实际中文组合输入、候选取消、焦点/快捷键；读屏有需求时逐项记录 | 无丢字/重复确认/焦点陷阱；未执行部分保留待办，不用程序输入冒充真实 IME |

没有实际 UI/存储证据时只填写自动测试通过，不能写成真实场景通过。发现缺陷后按当前
入口复现、修复、添加有区分力的回归，再复测同一路径。

## 4. R3-03：每批本地交付

```sh
make check-local    # 核心、example/app/适配器回归，以及两个 main 的 Debug 构建
make build-local-release
# 改动影响发布内容或公共接入时额外运行；CI 继续保留此自动检查。
make check-package
```

`check-core` 仍包含 API 基线、格式、分析与输入预算回归；`check-integrations` 包含 app、
原生剪贴板、Mermaid、Quick Look 等实际依赖的回归。独立示例测试属于契约辅助证据。
Native CI 默认构建 example/app 的 main（Debug / Release），不再将五个独立示例的构建
作为本地交付主线。版本、SDK 和原生依赖不随入口调整自动升级。

公共 API/默认行为有变化时同时更新 [API 契约](API_CONTRACTS.md)、[迁移指南](MIGRATION.md)、
CHANGELOG 和对应入口说明；修改基线需显式审查。本地交付不包含 1.0 API 冻结或包发布。

每次记录：

```text
日期 / 组件提交 / 工作区改动或输入哈希：
入口：example/lib/main.dart 或 app/lib/main.dart
SDK revision / OS / CPU / Xcode / 原生构建配置：
模式 / bundle 路径 / App.framework 哈希 / 实际进程路径：
用例编号 / 自动或真实 UI / 输入 / 实际步骤和结果：
状态：通过 / 失败 / 未执行 / 不适用（说明原因）
日志、截图、测试文件与保存结果：
已修复问题、保留限制和下一项：
```

本轮不再请求用户提供外部项目；以后若重新开展跨平台独立分发，再单独确定外部产品、
SDK 矩阵与发行要求。上游报告和实验补丁作为历史证据保留，不在当前工作中继续等待或催办。
