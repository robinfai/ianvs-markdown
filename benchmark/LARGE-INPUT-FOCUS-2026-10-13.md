# 大文档降级与输入焦点

日期：2026-10-13。R3-02 本批处理 L07/L08，入口固定为 `example/lib/main.dart` 和
`app/lib/main.dart`。原生 IME、框架输入协议和纯文本插入分别记录，不相互代替。

## 修复和回归

- `2025e1e`：默认超预算降级新增中英文提示。Live 使用完整源码编辑；Read 说明纯文本和
  前缀截断。提示不参与选择或复制，自定义 `fallbackBuilder` 仍接管整个降级 UI。
  默认限额不变；新增三个可覆盖文案 enum 值，穷尽 switch 的宿主需按迁移指南补齐。
- `ad4f2c4`：修复从 Read 返回 Source / Live 后焦点存在、文本输入连接却未恢复的问题。
  新 surface 挂载后重新连接输入；过期模式、controller、FocusNode 的延迟回调被忽略。
  example 的 Cmd+1/2/3 和 app 原生 View 菜单均有入口级回归。
- `65f7791`：example 新增 macOS 原生菜单，将复制、粘贴、全选路由到 Flutter 当前焦点，
  模式与历史命令使用实际 controller。原生菜单通道回归覆盖 1 MiB 粘贴、Read 全文复制和
  返回 Source。实际 GUI 先发现旧菜单未可靠更新文档模型，修复后按保存字节复验通过。
- 新增 example / app 各三组默认预算测试：4,097 单元长行、4,400 个星号语法字符、
  1,049,612 UTF-16 单元文档。覆盖三模式、末尾继续编辑、example 保存回调/Reset、
  app Cmd+S 保存/关闭重开，以及 example Read 前缀之外的全文复制。
- 两项主入口输入协议回归使用 Flutter test text-input 通道，覆盖组合确认、候选取消、
  Read→Source / Read→Live 无额外点击续输及 Cmd+Z / Cmd+Shift+Z。它们不是原生 IME。
- 本地化回归覆盖英文、中文覆盖与自定义 fallback 所有权。原有预算/全量复制回归继续保留。

修复前，两入口输入协议测试均在 Read→Source 后因 `hasAnyClients == false` 失败；
修复后两项通过。L07 提示测试在旧实现中因找不到提示而失败。初次全量检查发现新测试
单行 if 和未使用 import 的静态规则问题，`847dc92` 修正；`d2788fc` 保持 fallback 在
横向宽松约束下可布局。所有失败记录保留，不算通过。

## 验证环境与自动门禁

原版 Flutter 3.44.8 / Dart 3.12.2，revision
`058e0af2c2b57e369d905a03ac9748b0ebf543c6`；macOS 27.0.1 (26A434) arm64、
Xcode 27.0 (27A266a)。app 保留 `FLUTTER_XCODE_ARCHS=arm64`、
`CARGO_PROFILE_RELEASE_STRIP=none`。SDK 工作树无改动。

完整 `make check-local build-local-release` 退出 0，对应 `d2788fc` 的库/app 实现：
核心 968、example 29、app 291（1 项历史可选语料跳过）、API 8、Python 10、预算 32 组；
Mermaid Flutter 9 / Rust 4 / 示例 3、剪贴板 6、Quick Look Rust 8 / Swift 10 和原生导入通过。
两入口 Debug / Release 共四个构建通过。随后 `65f7791` 仅改 example 菜单及测试，重新通过
example 分析、全部 30 项测试和 Debug / Release 构建；核心/app 实现未变。

公共 API 仍为 183 个导出，声明从 1,143 增至 1,146；仅新增三个降级提示 enum 值。
[契约](../doc/API_CONTRACTS.md)、[迁移](../doc/MIGRATION.md)、CHANGELOG 和两入口说明已同步。
`make check-package` 退出 0：176 个文件、675 KB，Pub-selected 快照 dry-run 零警告，
快照内示例 30 项和包外接入 6 项通过，无工作区路径泄漏。
[快照摘要](results/2026-10-13-large-input-focus/package-summary.json) 与
[逐文件哈希](results/2026-10-13-large-input-focus/package-manifest.json) 单独归档。
最终提交必须通过双 SDK Core、Core required 和 Native integrations，
回执以 [PR #21 Checks](https://github.com/robinfai/ianvs-markdown/pull/21/checks) 为准。

## 实际 UI 证据与边界

实际使用新构建的 Release bundle，进程路径及四个 App.framework 哈希存于
[validation.json](results/2026-10-13-large-input-focus/validation.json)。Debug 只验构建。
本次 GUI 使用 1,049,618 字节（1,049,612 UTF-16 单元）的合成源文，尾标记为
`L07 end 中文😀`；另外两种预算轴由入口级 widget 回归覆盖，不算三组 GUI 均已执行。

| 入口 | 实际操作与结果 |
| --- | --- |
| app | 原生打开 source-length.md，Live 显示纯文本编辑提示并可到达全文尾部；追加 `APP` 后保存。切 Read 显示前缀提示，回 Source 不点击编辑区直接追加 `SRC`，再次保存、关闭和重开。磁盘精确等于初始全文 + `APPSRC`，共 1,049,624 字节，状态 Saved |
| example | Source 粘贴同一全文 + `APPSRC`；Live 末尾追加 `EX`；Read 显示前缀提示后全选复制。将系统剪贴板粘贴到 app 新文档并保存，精确等于初始全文 + `APPSRCEX`，共 1,049,626 字节；提示文案未混入，前缀之外的尾部完整。Reset 恢复默认语料和正常编辑 |
| example 焦点 | 用短文 `L08 seed `，Read→Source 后直接输入 `SOURCE`，Read 再显示新内容；Read→Live 后直接输入 `LIVE`，Cmd+Z / Cmd+Shift+Z 分别恢复/重做。模式切换后无额外编辑区点击 |
| 原生中文 IME | 用户于 2026-10-13 人工操作并回复“已完成，两入口两模式均正常”：example/app 的 Source 与 Live 共四组，输入 `zhongwen` 确认“中文”，再输入 `quxiao` 按 Esc 取消，未反馈丢字、重复确认或不能继续输入 |

最后一项是用户人工键盘复核，不是工具观察到候选窗口。此前电脑工具尝试只输入了 ASCII，
未出现可观察的拼音候选，因此不计原生 IME 通过，也不以框架 composing 测试替代人工结果。
读屏未执行，其他 OS、输入法、触摸与最低 macOS 版本不在此次通过范围。

单次工具操作加 AX 观察的往返耗时：app 打开 956 ms、三字符输入 1,523 ms、切 Read 494 ms；
example 成功粘贴 1,145 ms、切 Read 564 ms。均含自动化等待，不能作为编辑延迟或 P95。
本轮未重跑 R2 性能基线，不声称新增性能改善。

大文档采用专用临时目录中的合成语料。原始会话仅在临时目录私有备份，仓库不包含
用户正文、访问书签或完整会话。GUI 控制工具的往返耗时含等待与 AX 读取，只用于描述
是否能继续操作；不是输入延迟、帧时长或新的性能基线。预算保护解析，不限制完整源码的
Flutter 排版、内存、文件读写或会话存储成本。

本轮不新增验收宿主、不修改 SDK、不安装到 `/Applications`、不发布包，也不追认上游
AOT 问题已解决。读屏及其他系统/输入法未实测时仍明确保留边界。

## 证据索引与复验

- [验证清单](results/2026-10-13-large-input-focus/validation.json)：提交、SDK、测试数量、
  bundle 路径/哈希、实际进程、保存结果、人工 IME 来源及边界。
- [输入清单](results/2026-10-13-large-input-focus/input-hashes.json)：三个预算轴及短输入 fixture；
  同目录 `*.md.gz` 保存合成初始输入与两份 GUI 保存结果。
- 同目录 `*.log.gz`：修复前失败、静态检查初次失败、修复后专项/全量回归与构建日志。
  截图在本次会话中观察，未另存为仓库图片；私有会话备份未归档。
- 保存结果 SHA-256：app `f0527d7e21544b5f1612c18dc00095c5da68480ba66efc4c85a4a27d87198d42`；
  example 全文复制 `f239774b84fa5ca177349b1fb2495d3d8e01d08b5add094a29dd2ecba2970161`。

复验从两个实际 main 开始，运行 `make check-local build-local-release` 与 `make check-package`。
GUI 按上表用独立临时文件操作；在新一轮修改模式/输入连接后重新执行四组人工 IME，
不能从本次人工报告推断其他 SDK、系统或后续实现已通过。
