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
