# example / app 本地主入口首轮验证

日期：2026-10-12。按用户最新方向，当前围绕 `example/lib/main.dart` 和
`app/lib/main.dart` 迭代。R3-01 的本地构建/启动基线完成，R3-02 应用链路继续推进，
R3-03 持续维护本地门禁与文档。调整后的 16 项中完成 14 项、进行中 2 项、剩余 2 项。
旧的独立 AOT、外部产品和分发验收移出本轮范围，没有被补记通过。

## 受测输入与环境

- 运行库、测试和依赖基线：`1f814eb39347716511170d47c32ed74a3d7eb413`，本批未改运行代码。
- `ce9f525`：双主入口命令、Native CI 和路线文档。构建及核心/原生检查发生在该提交前的
  同一组工作区变更上，包快照检查发生在该提交上；441 个实际输入哈希记录在证据清单。
- 原版 Flutter 3.44.8 / Dart 3.12.2，SDK revision `058e0af2c2`，Git 工作区干净。
  macOS 27.0.1 (26A434)、arm64、Xcode 27.0 (27A266a)、Rust 1.90.0。
- app 沿用 `FLUTTER_XCODE_ARCHS=arm64`、`CARGO_PROFILE_RELEASE_STRIP=none`。
  没有修改 SDK、升级依赖、安装到 `/Applications` 或发布版本。
- SDK 信息由已有 `flutter.version.json`、Git HEAD/status 和预算检查中的版本记录互证。
  独立版本查询因尝试写缓存被自动审批拒绝，未再次执行该命令。

## 四次构建与自动回归

以下命令退出码均为 0；使用 `FLUTTER=/Users/robinfai/development/flutter/bin/flutter`
及对应 `DART`，完整命令见 JSON。本轮分别执行这些组成检查，没有将其记为一次原样运行的
`make check-local`。

```sh
make build-local build-local-release
make check-core check-integrations
make check-package
```

| 入口 | Debug | Release | 真实 GUI |
| --- | --- | --- | --- |
| example/lib/main.dart | 通过 | 通过 | 本次 Release bundle 启动，三模式、编辑、保存反馈与 Reset |
| app/lib/main.dart | 通过 | 通过 | 本次 Release Linefold 启动，本地文件、Source/Live 编辑、原生 Mermaid |

Debug 仅构建，未另外启动 GUI。Release 的实际进程路径均为本工作树 `build/macos/Build/Products/Release/`
下的 bundle，已核对 PID 24889 / 35885；四个产物均保存 executable 与 App.framework 哈希。
构建日志中的 SPM/CocoaPods 迁移和 Xcode Metal 路径警告未导致失败。

| 自动检查 | 结果 |
| --- | --- |
| Core / example | 967 / 20 项通过，格式和分析通过 |
| API 门禁 | 8 项通过；183 exports / 1143 declarations 匹配 |
| Python / 输入预算 | 10 项 / 32 组通过；预算诊断不是 GUI 性能基线 |
| app | 274 项通过，1 项历史可选外部语料跳过 |
| Mermaid | Flutter 9 / Rust 4 / 示例 3 项通过 |
| Clipboard | 6 项通过 |
| Quick Look / 原生导入 | Rust 8 / Swift 10 项和原生导入检查通过 |
| Pub 快照自动质量检查 | 166 文件、665 KB、零警告，示例及包外自动 smoke 通过，无工作区路径泄漏 |

Native CI 现在构建两个 main 的 Debug 和 Release，补上此前只构建独立样例、未构建实际 app
bundle 的缺口。Core 双 SDK 与包快照自动检查继续保留；它们不要求用户提供独立验收项目。

## 真实应用操作与磁盘结果

本轮通过 Computer Use 操作实际应用。只在新建的 `ianvs-local-entries-20261012-7kfjedn5`
测试目录内写入两个文件；没有编辑或关闭用户原有标签。截图保留在任务过程，仓库归档文字步骤、
输入/保存文件、构建与回归日志和哈希，不宣称另有截图文件。

1. example 默认完整 playground 启动。Source 输入 ASCII 标记后，Live/Reading 可见相同标记；
   Save 显示 `Host save callback invoked`，Reset 恢复默认语料。这是内存回调，不是磁盘保存。
2. app 打开 `workflow.md`，显示 UTF-8/CRLF、中文/emoji、表格，以及“打开 → 保存”的原生
   Mermaid 图。通过模式菜单键盘切换到 Source。
3. Source 首次前缀输入后执行 ⌘Z，文档回到 Saved；再用 ⌘↓ 到文末，输入 `LOCALCHECK`，
   状态为 Edited。⌘S 后为 Saved，磁盘字节严格等于原文件加该 ASCII 标记。
4. 15 处 CRLF 全部保留，无裸 LF；YAML、中文、emoji、表格和 Mermaid 源码字节未变。
   ⌘W 关闭测试标签后从侧栏重开，显示同一标记、Saved、UTF-8、CRLF。
5. 打开 `second.md`，在 Live 段落末追加 `SECOND`。⌘W 显示未保存关闭提示，Cancel 保留
   Edited；切回 `workflow.md` 仍为 Saved/CRLF，内容未串。再切回第二个文档并保存，
   磁盘严格等于预期，保持 LF。

Computer Use 的坐标点击间歇返回 `noWindowsAvailable`，AX 有时滞后于画面；改用索引、
键盘焦点和实际磁盘验证。未确认生效的 paste/setValue 尝试不计通过；ASCII 自动输入不等于
中文 IME 组合输入验收。本轮没有据此认定编辑器存在丢字缺陷。

## 剩余的应用内工作

对应 [R3 执行清单](../doc/R3_ACCEPTANCE.md)，以下是本次证据范围，并非全部完成：

| 用例 | 本次状态 | 下一步 |
| --- | --- | --- |
| L01 三模式保真 | 部分完成 | example 默认语料加标记跨模式可见；补自定义完整源码比较、选区及撤销/重做 |
| L02 示例保存 | 通过本次路径 | 保存回调反馈和 Reset 已验证；未来改动继续回归 |
| L03 本地文件闭环 | 通过本次路径 | Source 编辑、磁盘字节、CRLF、关闭重开已验证 |
| L04 多文档与恢复 | 部分完成 | 文档隔离、取消关闭已验证；补未命名文档和重启恢复 |
| L05 保存期间编辑 | 自动回归通过 | 补真实 UI 保存后的连续输入；异步竞态以可控测试为准 |
| L06 复制与资源 | 部分完成 | app Live 原生 Mermaid 已显示；补 Read、本地链接/图片及系统剪贴板格式 |
| L07 大文档降级 | 自动回归通过 | 补两个主入口实际大文档编辑、保存/复制；不套用 Debug 耗时 |
| L08 输入与无障碍 | 未完成 | 补真实中文 IME、候选取消、键盘选择/焦点；读屏按需求逐项留证 |

优先补 L01/L04 的源码与恢复，再处理 L05/L06、L07、L08。所有操作继续从两个 main 进入。
R3-03 在上述迭代中维护检查和记录；本报告没有宣告完整 R3、其他平台或 1.0 发布完成。
本轮没有运行新的性能基线，性能边界沿用已记录的 R2 配对结果。

## 证据

完整索引：[validation.json](results/2026-10-12-local-entries/validation.json)。目录内保留
三个压缩原始命令日志、SDK/预算/包清单、四份前后测试文件、四个产物及 441 个输入哈希。
最终 PR 必须在其最新提交通过 Core required 和 Native integrations 后合入；远端结果以该 PR
Checks 为准，不能从本机通过推断 CI 已完成。
