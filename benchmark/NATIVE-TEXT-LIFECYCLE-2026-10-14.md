# R4-03：原生文本字段生命周期与小文档 Live

日期：2026-10-14。本批基于 `51ee7e875b6b9fc9c886d2376e9e3cf3715bd09a`
（PR #25 合入），继续 [上一批 R4-03](LARGE-DOCUMENT-COSTS-2026-10-14.md)。
状态：进行中，尚未完成新的正式配对，不改变原目标或历史观察线。

## 固定边界

只使用 example/app 的实际 main、原版 Flutter 3.44.8 / Dart 3.12.2。
保持 [R4-02 协议](LOCAL-PERFORMANCE-PROTOCOL.md) 与 [R4-03 目标](R4-03-TARGETS.json)。
不修改 SDK、不关闭语义或 IME、不截断编辑全文、不将工作延迟至计时结束后。
外部真实宿主仍在分发阶段最后提醒，不作为本批前置。

原生跟踪通过独立诊断补丁包装 `FlutterTextField.startEditing`、
`setStringValue:`、`FlutterTextInputPlugin.setEditingState:`；原实现仍调用一次，
记录对象身份、长度、选区、容器尺寸与相对时间，不记录文本。
仅归因流程调用 `beginInputTrace` 才安装观察，正式构建必须移除补丁。
读取原生字符串与桥接也有显著成本，不能用这些延迟作为验收成绩。
CPU/native sample 也只用于归因。VM service 地址不归档。

## 已确认的 Read→Live 差异

两个 1 MiB 原生对照均完整完成 125 次：

| 入口 | Read→Live 的原生顺序 | 诊断中位数（非验收） |
| --- | --- | ---: |
| example | 空 FlutterTextField 先 `startEditing`；进入编辑后写入全文；然后恢复选区，最后接收 TextInput 状态 | 2587.573 ms |
| app | 该操作只观察到 `setEditingState`；未调用原生字段 `startEditing` / `setStringValue` | 91.563 ms |

example 第一条 Read→Live：约 73.4 ms 进入 `startEditing`，字段长度 0、无当前编辑器；
87.1 ms 开始写入 1,025,282 个 UTF-16 单元，2223.3 ms 返回，原生选区暂为全文；
2237.4 ms 恢复为 `{2, 0}`。此时视图宽度 0、排版容器宽度 0，TextKit 2。
app 第一条则在约 105.6–111.3 ms 接收完整文本及 `{2, 0}` 的输入状态。

这证明此前相同的最终 snapshot 掩盖了不同的中间激活顺序。
SDK 本地源码中，`AccessibilityBridgeMac::VALUE_CHANGED` 可调用 `startEditing`；
后者先 `selectText:` 再写入语义文本。节点从非文本角色变成文本角色时，
`FlutterPlatformNodeDelegateMac::NodeDataChanged` 会重建原生字段。
但不能仅凭这些事实断言所有差异都由某一 Flutter Widget 层级造成。

## 已撤回：修改隐藏排版容器宽度

在宿主 `makeFirstResponder` 中保留隐藏视图宽度 0，令其排版容器宽度跟随窗口。
该实验未改变源文/语义/选择，但 1 MiB Source paste 诊断中位数从 200.003 ms
上升至 1672.791 ms，单次 `setStringValue` 约 1.5 秒。确认回退后主动停止。

保留 result 的 50 条检查点和 trace 的 59 条完整事件，标记无效部分轮，
不拼接、不计入验收；实验源码补丁与构建冻结一并归档。此实现已撤回。
因此不能将“非零宽度”当作已证实的解法。

## 待验证顺序

1. 完成 app 10 KiB 原生调用与语义变化归因，继续使用 39.03 ms（Live type）、
   40.6548 ms（Live paste）历史观察线。
2. 原生候选必须在完整输入、选区与激活顺序下减少真实工作；不能仅用新语义节点
   把等待挪到第一次编辑或无障碍聚焦。
3. 移除观察补丁，执行全量本地门禁，再跑两入口各两轮完整配对；任一目标或非目标
   未通过则继续保留 R4-03 进行中。
4. 修改原生输入路径后，在 Release 重做编辑/保存/重开及新的人工 IME/VoiceOver 复核。

TextKit 1 兼容路径已获用户明确授权进行受控实验：此前自动审批认为它与只读诊断
保留 TextKit 2 的约束冲突，未执行被拒命令；用户授权后才应用。Apple 说明访问 NSLayoutManager API
会使 NSTextView 进入 TextKit 1 兼容模式；这是一次有行为风险的引擎选择，不是只读观察。
参考 [Apple TextKit](https://developer.apple.com/documentation/appkit/textkit) 与
[WWDC22 兼容模式说明](https://developer.apple.com/videos/play/wwdc2022/10090/)。

证据目录：[2026-10-14-native-text-lifecycle](results/2026-10-14-native-text-lifecycle/)。
所有有效、无效归因轮与实验均保留；正式两轮结果将在完成后追加。

## 小文档的新增证据与组件修复

app 10 KiB 完整原生归因轮 125 条已保留。第一条正式阶段 Live type 中，字段
进入 `startEditing` 时长度 0、尚无 currentEditor，但输入插件已持有 48 字符。
约 24.2 ms 进入、37.2 ms 才开始写入 49 字符；写入自身约 0.67 ms。
原生 sample 在 `selectText:` 内观察到 `NSTextInputContext.activate →
MyActivateTSMDocument → IMKInputSessionActivate → invocationAwaitXPCReply`，
当时线程输入法为 `com.apple.inputmethod.SCIM`。这解释了本轮等待所处路径，
但旧 R4-02 没有冻结输入法 ID，不能追认其输入法、改变历史线或宣称已解释全部历史漂移。

独立的组件回归证明：修改前部标题会重建未改变的后续 Markdown 元素和语义节点。
原因是块键和 Column 键使用绝对源码偏移，偏移变化被误当成新的 Widget 身份。
修复通过未改变的前后连续块复用键，并向 Sliver 提供新的索引映射；源码位置作为
内部区域元数据单独更新。修改区原有位置只有在身份未被移动时才可复用；文档
Controller 替换会清空身份映射。此策略不承诺任意重排/多处修改的全量 diff。

先前失败的元素身份回归现在通过，并覆盖语义 ID、重复段落的插入/删除/撤销、
Controller 替换隔离。核心 975 项通过；两个实际 main 的输入/撤销/dirty 与语义
身份回归通过，app 另外 120 项焦点、标题和目录布局检查通过。
以上只是行为结果，小文档是否回到原观察线仍须正式测量。

## TextKit 1 受控实验（尚待正式配对和人工复核）

用户明确允许“受控实验，验证后再决定保留”。两个实际 main 的 1 MiB 归因各完整
125 条。example Read→Live 中位数 1283.526 ms，最大 1297.484 ms；此前 TextKit 2
为 2587.573 / 2644.772 ms。原生全选写入从约 2.14 秒降至约 1.14 秒，最终仍为
1,025,282 UTF-16 单元、选区 `{2, 0}`、零宽隐藏视图；snapshot 确认 TextKit 2 已关闭。
app 1 MiB 中位数 sourceType 165.950、sourcePaste 265.529、liveType 170.128、
livePaste 266.537、Read→Live 89.383 ms，和原引擎诊断接近。跟踪有桥接成本，均非验收成绩。

随后将条件收窄至 macOS 主版本 27、精确 `FlutterTextInputPlugin` 类、本窗口、视图宽 0、
没有 marked text 且仍为 TextKit 2。仅访问公开兼容 API，不更换字段、不截断字符串、不屏蔽
语义事件；`super.makeFirstResponder` 仍调用一次。其他 macOS 版本与普通 NSTextView 不变。
这是两个宿主的本地兼容措施，不进入 Flutter Markdown 的公共 API，也不承诺其他 SDK。

收窄后 app 10 KiB 归因 125 条完整：Live type 中位数 35.644 / 最大 41.210 ms，
Live paste 36.233 / 41.680 ms；仍有输入法激活成本，不能称为全面解决历史漂移。
此前仅组件身份修复的 TextKit 2 对照中位数分别为 35.573 / 37.507 ms。
一轮因启动时失去前台而 0 样本失效，单独归档，不拼接。

正式候选移除全部方法包装、原生事件跟踪及临时语料开关。是否保留原生兼容路径，要依据
无跟踪两轮结果、新的 Release 编辑/保存/重开及人工 IME/VoiceOver 结果；本节不提前验收。
完整本地门禁在组件修复后通过：核心 975、example 35、app 301（另 1 跳过）、API 8、
Python 27、原生与可选集成；两个 main Debug/Release 成功。发布快照 189 文件、699 KB、
零警告，快照 example 与包外 smoke 均通过。原生实验后的构建与验收另行追加。

## Release 复核与当前接续点

受控候选提交 `373d206`，已移除诊断补丁；两个 main 的普通 Debug/Release 与
正式 Profile 构建成功。对照期间只重建 app Release，随后恢复候选；Profile 两个
可执行文件及 App.framework 的 SHA-256 均仍与冻结一致。

电脑工具复核：example Source 的中文/emoji/CRLF、保存回调、输入与撤销正常；Live
段落输入后撤销恢复原文。app 使用本轮临时 `native-input.md`，Live 插入 x 后保存的
磁盘字节精确等于原文加该字符，11 个 CRLF 保留；菜单 File→Save 后直接输入 q，
仍在同一段落末尾，撤销回到 Saved；重开后正文和表格正确。

同时发现工具路径的限制：CUA `super+s` 后出现全文选区，下一次输入会覆盖该选区；
已撤销未保存的替换。以相同 Dart 代码、仅移除 app 原生兼容 override 的 TextKit 2
Release 控制，也复现同样全选。因此不能认定由 TextKit 1 引入，也不能据此声称物理
键盘正常。CUA paste 自身也可能保留选区；工具的 End 没有折叠，Right 后续输有效。
这些观察独立记在 `gui/automated-release.json`，不隐去，不计作物理键盘验收。

已准备并保留两个候选 Release 窗口，向用户请求本轮两入口 Source/Live 的物理拼音
确认/取消、候选期间 Undo/Read、⌘S 后直接续输，以及有限 VoiceOver 定位/朗读/续输。
**目前尚未收到这轮人工结果。原生候选未作保留决定，PR #26 保持草稿，未合入主线。**

接续顺序：

1. 记录本轮人工结果；若出现候选回退，保留证据并撤回原生 override，不能沿用旧 IME 验收。
2. 人工操作结束后关闭两个 Release，使用冻结于 `builds/r403-native-candidate/freeze.json`
   的两个无跟踪 Profile main。串行跑 example-1、example-2、app-1、app-2 四个新进程。
   采样期间不构建、不运行测试、不打开其他窗口；失焦轮整轮保留并重测。
3. 按原协议收集 2,400 正式 / 600 预热，以原 R4-02 四轮和原 R4-03 目标比较全部 60 项。
   不把本报告中的归因轮充当正式两轮，不改变 39.03 / 40.6548 ms 小文档观察线。
4. 完整记录结论与是否保留兼容措施；只在验收满足时关闭 R4-03。最终提交头的 Core / Native
   CI 通过后再合入，随后同步主工作区。外部真实宿主留到最终分发阶段提醒。

提交顺序：`6cecabe` 记录激活顺序及撤回宽度实验；`d30d62b` 保留 Live 块身份；
`373d206` 提交受控的 macOS 27 TextKit 候选与诊断。当前候选的双 SDK Core CI 已通过，
Native CI 仍在运行；文档提交的最终门禁以 [PR #26 Checks](https://github.com/robinfai/ianvs-markdown/pull/26/checks)
为准。正式性能配对尚未开始，R4-03 状态不变。
