# 原生菜单与命令路由（R4-01）

入口固定为 `example/lib/main.dart` 与 `app/lib/main.dart`。基线 bd77b32，
原版 Flutter 3.44.8 / Dart 3.12.2。当前阶段：实现、本地全量门禁、两个 Release 命令实操及本轮人工 IME 已通过。

## 修复前复现

实际应用 Widget 挂载后，通过 `SystemChannels.menu` 的 `Menu.setMenus` 取得 ID，
发送 `Menu.selectedCallback`；并非直接调用待测 controller。合成 composing 不等同原生 IME。

| 场景 | 预期 | 基线实测 |
| --- | --- | --- |
| example 属性 author 局部输入后 Undo | 键盘和菜单均撤销属性草稿，正文不变 | Cmd+Z 成功；菜单 Undo 保留 Changed again，失败 |
| example Source composing 中菜单 Read | 保留 Source、选区与 composing | 切到 Read，失败 |
| example 将 Undo 改为 F3 | 原生菜单不注册冲突的默认 accelerator | 仍注册 Cmd+Z，失败 |
| app Source composing 中菜单 Undo | 输入值、选区与 composing 不变 | ni 被撤销、composing 清空，失败 |
| app Source composing 中菜单 Read | 保持 Source | 切到 Read，失败 |

example 三项、app 两项回归均在行为断言处失败。
[example 原始日志](results/2026-10-13-command-routing/example-before.log.gz)、
[app 原始日志](results/2026-10-13-command-routing/app-before.log.gz)。

## 路由策略与后续验证

- 菜单显式操作不受键位禁用/重映射影响；编辑命令 accelerator 由 Flutter 焦点路由拥有，
  原生 Edit/View 菜单不再重复注册。宿主 File/Window 命令仍由宿主决定。
- 按当前焦点由属性/表格/正文向外委派；属性撤销只改局部草稿，保存/切模式先提交草稿。
- composing 期间抑制编辑命令，不隐式确认或丢弃；键盘、菜单、工具栏均需覆盖。
- Read 的历史/修改命令不改正文；非编辑控件使用自身 Actions，不操作旧正文选区。
- 修复后补齐菜单/快捷键/工具栏、禁用/重映射、Read、表格、非编辑焦点与卸载隔离回归，
  执行全量门禁、两个实际 Release 菜单操作，重新人工确认中文 IME。

## 实现与专项结果

新增一个公开静态 `IanvsMarkdownShortcuts.invoke(command, controller: ...)`，复用现有局部
命令链；没有增加命令 enum。controller 只校验归属，返回 true 包含 composing 抑制，不能
理解成异步保存完成。两个 main 的 Edit/View 及 app Save 去掉重复 accelerator；其他宿主
菜单键保留，普通控件回退到自身 Actions。工具栏使用文本 TapRegion，属性草稿支持局部
撤销与保存，Read 历史按钮禁用，未定义局部语义的结构格式按钮不操作属性/表格。
app 窗口模式选择器在 composing 时不弹出；Save As 同样检查当前单元格的局部 composing。

专项：核心命令配置/调用 45、example main 5、app main 5 全部通过；Live/流式相关 426 项
已通过。主入口覆盖 Source、Live、属性、表格、Read、重映射/禁用、非编辑 Search Files、
保存/另存为与窗口模式选择器；组件测试另验 controller 替换、卸载和非 Markdown 焦点。
保存结果、选区/composing 与源文分别断言，不只检查 UI 标签。

首次全量发现默认 Tab 接管改变日期分段输入，以及新工具栏读取已脱离树的旧焦点；保留
默认 Tab 的控件处理并拒绝已脱离渲染树的焦点。随后发现监听表格局部 controller 会在
表格重建时触发工具栏重建，改为仅监听属性局部输入；表格使用已有文档通知和调用时校验。
这些中间失败不计为通过。表格/正文现有历史分组规则未改，本项不承诺整段输入法候选
只有一个撤销步骤；覆盖的是命令触发期间不会确认、撤销或丢弃正在组合的输入。

公共基线仍为 183 个导出，声明 1,146 → 1,147，仅 `invoke` 一项；契约、接入指南、迁移、
CHANGELOG 和两个入口说明已同步。完整验证与人工 IME 记录见下文。

全量 app 回归还捕获 `enableModeShortcuts:false` 下 Cmd+数字被默认路由消费的问题；
`cef6719` 让未重映射的模式键继续交给宿主，显式重映射的禁用语义不变。核心键位 43 和
app 文档切换/命令 9 项复验通过。静态门禁中的宿主 callback / 多行条件规则已修正，
失败轮次日志保留；最终通过以完整成功轮次为准。

## 完整验证与环境

最终运行时代码 `2320bdd`，原版 Flutter 3.44.8 / Dart 3.12.2，SDK revision
`058e0af2c2b57e369d905a03ac9748b0ebf543c6`、SDK 工作树干净；macOS 27.0.1 (26A434)
arm64、Xcode 27.0 (27A266a)。app 保留 `FLUTTER_XCODE_ARCHS=arm64` 与
`CARGO_PROFILE_RELEASE_STRIP=none`。四个构建都指向既有 `lib/main.dart`。

`make check-local build-local-release` 完整成功，退出 0：核心 970、example 35、app 296
（另有 1 项历史可选语料跳过）、API 8、Python 10、预算 32 组；Mermaid Flutter 9 / Rust 4 /
示例 3、剪贴板 6、Quick Look Rust 8 / Swift 10、原生导入通过；两入口 Debug/Release
共四次构建成功。没有放宽预算，也没有新增性能成绩。

`make check-package` 退出 0：180 文件 / 688 KB，Pub-selected 快照 dry-run 零警告；
快照示例 35 项和包外接入 6 项通过，无工作区路径泄漏。库仍是 0.3.1 + Unreleased，
没有 SDK 补丁、升级、包发布或 `/Applications` 安装。

运行时代码头 `2320bdd` 的双 SDK Core、Core required 与 Native 全绿：
[Core](https://github.com/robinfai/ianvs-markdown/actions/runs/38341467973)、
[Native](https://github.com/robinfai/ianvs-markdown/actions/runs/38341467976)。证据/roadmap
文档随后独立提交；最终交付仍需检查该最终头，回执以 [PR #23 Checks](https://github.com/robinfai/ianvs-markdown/pull/23/checks) 为准。

## 新 Release 的实际操作

已退出旧进程后从工作树 Release 路径启动。实际 PID 为 example 31212、app 33546；
进程命令路径和新 App.framework 哈希相符，四个构建哈希见验证清单。

| 入口 | 操作与观察 |
| --- | --- |
| example 属性 | author 从 Ianvs 输入为 R4 Author；原生 Edit→Undo 恢复 Ianvs；Cmd+Shift+Z 恢复 R4 Author；工具栏 Undo 恢复 Ianvs，焦点仍在属性框 |
| example Source | Cmd+2 切 Source，全选粘贴短文 R4 IME seed，文本输入连接正常；用于本轮人工输入 |
| app Live 历史 | 在 main 中新建合成文档，输入 R4 IME seed（12 字符）；原生 Undo 清空，Cmd+Shift+Z 恢复 12 字符 |
| app Read 与续输 | 原生 View→Read 后再点 Undo，文本和字符数不变；View→Source 后不点击编辑区直接输入 SOURCE，得到 19 字符 |
| app 保存 | Cmd+S 正常打开系统保存面板，在临时目录保存 r4-commands.md，UI 为 Saved；磁盘精确等于 `R4 IME seed SOURCE `（尾空格保留），19 字节 |
| 本轮原生 IME | 用户在两个 Release 的 Source/Live 四组中，输入 zhongwen 确认“中文”、quxiao 按 Esc 取消，候选未确认时试 Edit→Undo、View→Read 并续输；回复“**四组均正常，候选期间命令未打断输入**” |

IME 结论来自本轮用户人工键盘报告；电脑工具没有观察到候选窗口，框架 composing 测试和
CUA 文本注入均不替代原生 IME。未执行 VoiceOver、其他 OS/输入法或性能基线。

GUI 最初尝试通过 CUA 的系统 Open 面板打开另一份合成 input.md，但 Open 保持禁用，
这次尝试没有完成；随后取消并用主应用 New document → 原生 Save 完成上述流程。
不将这次尝试记为打开/关闭重开成功，也不凭自动化现象断言其产品原因。R3 既有文件闭环
证据保持原记录，本批 R4 菜单与保存协议回归另有两入口自动覆盖。

实际测试只用合成文本；原会话已在临时目录私有备份，未归档用户正文、书签或会话。
系统菜单仍显示可点击的 Edit 项，Read/无历史/composing 时由路由消费；没有“禁用菜单
等于命令不可达”的假设。原生编辑菜单不显示快捷键是本批明确的兼容策略。

## 证据与复验

- [validation.json](results/2026-10-13-command-routing/validation.json)：运行时代码、SDK、
  测试数量、四个 bundle 路径/哈希、实际 PID、保存字节、用户 IME 原话及限制。
- [package-summary.json](results/2026-10-13-command-routing/package-summary.json) /
  [package-manifest.json](results/2026-10-13-command-routing/package-manifest.json)：实际发布快照及逐文件哈希。
- 同目录 `*-before.log.gz`、`*-failure.log.gz` 保留失败；`*-target.log.gz`、
  `mode-key-*.log.gz`、`check-local.log.gz`、`package.log.gz` 保留专项与最终通过。
- `app-gui-saved.md.gz` 保存本轮已核验的 19 字节合成结果；SHA-256
  `086fbb031c2f6b7a44b5aebc5534000879554cace76974b6005db50472cf32c0`。
  GUI 截图已在会话中观察，未另存仓库。

复验先运行两个 main 的 `command_routing_main_test.dart` 和核心 `command_invocation_test.dart` /
`keyboard_configuration_test.dart`，再执行 `make check-local build-local-release` 与
`make check-package`。实际菜单与原生 IME 按上表重新执行；后续改动不能沿用本轮人工确认。
R4-01 的命令边界已交付；下一项 R4-02 冻结两入口测量方案，外部产品验收继续留在最终分发阶段。
