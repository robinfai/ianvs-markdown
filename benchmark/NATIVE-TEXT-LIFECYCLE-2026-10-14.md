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

候选 TextKit 1 兼容路径目前尚未应用：自动审批认为它与此前诊断保留 TextKit 2
的约束冲突，已提交具体实验方案等待用户授权。Apple 说明访问 NSLayoutManager API
会使 NSTextView 进入 TextKit 1 兼容模式；这是一次有行为风险的引擎选择，不是只读观察。
参考 [Apple TextKit](https://developer.apple.com/documentation/appkit/textkit) 与
[WWDC22 兼容模式说明](https://developer.apple.com/videos/play/wwdc2022/10090/)。

证据目录：[2026-10-14-native-text-lifecycle](results/2026-10-14-native-text-lifecycle/)。
所有有效、无效归因轮与实验均保留；正式两轮结果将在完成后追加。
