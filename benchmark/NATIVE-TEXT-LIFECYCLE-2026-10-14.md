# R4-03：原生文本字段生命周期与小文档 Live

日期：2026-10-14。本批基于 `51ee7e875b6b9fc9c886d2376e9e3cf3715bd09a`
（PR #25 合入），继续 [上一批 R4-03](LARGE-DOCUMENT-COSTS-2026-10-14.md)。
状态：两入口各两轮正式配对及本轮人工复核已完成，保留受限 TextKit 1 兼容实现。
5 个预定优化目标全部通过；60 项中 56 项通过，4 个非目标场景超原观察线。
R4-03 继续进行中，保留 `valid=true / passed=false`，不改变原目标或历史观察线。

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

## 实验前确定的验证顺序（现已执行）

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
所有有效、无效归因轮与实验均保留；正式四轮及一次无效尝试见下方配对结果。

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
以上是行为回归结果；下方正式配对显示小文档尚未全部回到原观察线。

## TextKit 1 受控实验与实现范围

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

正式候选移除全部方法包装、原生事件跟踪及临时语料开关。下方保留决定依据无跟踪
两轮、新的 Release 编辑/保存/重开及本轮用户人工结果；归因延迟不计验收成绩。
完整本地门禁在组件修复后通过：核心 975、example 35、app 301（另 1 跳过）、API 8、
Python 27、原生与可选集成；两个 main Debug/Release 成功。发布快照 189 文件、699 KB、
零警告，快照 example 与包外 smoke 均通过。原生实验后的构建与验收另行追加。

## Release 复核与本轮人工结果

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

2026-10-14 用户在本轮候选 Release 上明确回复：“人工复核已完成，两入口的 IME、
⌘S 续输和 VoiceOver 均正常。”此前给出的复核脚本覆盖两入口 Source/Live 的拼音
确认/取消、候选期间 Undo/Read、⌘S 后续输，以及有限 VoiceOver 定位/朗读/续输。
这是用户报告的人工结果，独立于电脑工具观察；不沿用 L08/R4-01 的旧验收。
本轮有限读屏复核不代表后续 R4-07 的全部键盘与读屏任务已经完成。

## 无跟踪正式配对

候选冻结于 `373d206`，后续提交只追加文档和证据。原版 Flutter 3.44.8 / Dart 3.12.2、
macOS 27.0.1、M4 Pro、Profile、默认预算、字体、窗口、语料及动作均按 R4-02 冻结。
两个可执行文件和 App.framework 的哈希在采集时与构建冻结一致；未修改 SDK。
与 R4-02 的 12 个源码差异由配对脚本精确校验，包含上一批 app 计算优化、归因工具
及本批块身份/宿主兼容修改；正式协议、样本数和输入样式不变。

四个独立进程串行执行；采样期间不构建、不跑测试、不操作其他窗口。
以下为 UTC 时间，完整原始记录、帧号、窗口状态、语料和 receipt 均在 `runs/`。

| 运行 | PID | 开始 | 结束 | 正式 / 预热 |
| --- | ---: | --- | --- | ---: |
| example-1 | 93072 | 15:12:40.916 | 15:17:05.028 | 540 / 135 |
| example-2 | 99488 | 15:23:04.282 | 15:27:38.877 | 540 / 135 |
| app-1 | 11684 | 15:32:09.084 | 15:37:00.068 | 660 / 165 |
| app-2 | 15560 | 15:38:09.828 | 15:43:01.261 | 660 / 165 |

总计 2,400 正式样本 / 600 预热，全部运行完整、无错误，全文保真及帧归属校验通过。
另一次 app 尝试在 15:30:56.792（UTC）被窗口状态检查中止：`occlusionVisible=false`、
generation 从 0 变成 1，当时 `active=true`。保留 324 条及错误 trace 于
`invalid-runs/app-1-window-occluded/`，整轮排除；未将遮挡等同于锁屏，也没有拼接样本。

使用原 R4-02 四轮、原 R4-03 目标比较全部 60 项。机器可复算结果为
[`paired-validation.json`](results/2026-10-14-native-text-lifecycle/paired-validation.json)：
**valid=true，passed=false；5/5 目标通过，51/55 非目标通过，总计 56/60。**

| 预定目标（均为 1 MiB） | 原基线 P95，两轮 ms | 本轮 P95，两轮 ms | 原上限 ms | 结果 |
| --- | ---: | ---: | ---: | --- |
| example Read→Live | 2625.868 / 2672.944 | 1247.639 / 1352.428 | 2100.694 | 通过 |
| app Source type | 213.265 / 211.575 | 140.581 / 139.137 | 169.2600 | 通过 |
| app Source paste | 243.325 / 244.958 | 174.747 / 174.433 | 194.6600 | 通过 |
| app Live type | 212.151 / 207.253 | 140.901 / 143.493 | 165.8024 | 通过 |
| app Live paste | 245.241 / 240.276 | 176.998 / 176.689 | 192.2208 | 通过 |

example Read→Live 两轮相对较快基线改善约 48.5%–52.5%，仍需约 1.25–1.35 秒，
不能称为即时切换。app 四项目标相对较快基线改善约 26.3%–34.2%，包含上一批优化贡献，
不能全部归功于 TextKit 1。

| 未通过非目标（均为 10 KiB） | 本轮 P95，两轮 ms | 原观察线 ms | 分布及边界 |
| --- | ---: | ---: | --- |
| example Source→Read | 91.943 / 206.507 | 112.0596 | 第一轮通过；第二轮中位数 112.208，最高两次 206.507 / 226.912；帧 build P95 155.929、回调 P95 0.069 ms |
| app Live type | 40.218 / 38.424 | 39.0300 | 第二轮通过、第一轮超过；不能按均值或单轮关闭 |
| app Live paste | 40.973 / 40.889 | 40.6548 | 两轮均略超线，仍判失败，不增加容差 |
| app save | 25.799 / 31.127 | 29.9700 | 第一轮通过；第二轮最高两次 31.127 / 40.104，回调 P95 29.850，磁盘写入 P95 4.156 ms |

两项小文档 Live 比上一批 42.608/43.084 与 44.160/42.839 ms 下降，但不能用进步
替代原退出条件。归因中已有输入法激活等待，原基线未冻结输入法 ID，不能补造旧条件。
本轮另外两项新超线分别偏向 Flutter 帧构建与保存回调；仅凭分布不能判定是系统波动、
块身份修复或 TextKit 兼容引起。未删除离群点，未用更好的重测覆盖原结果，未宣称没有回退。

复算（无需 GUI，不重新采样）：

```bash
python3 - <<'PY'
import json, sys
from pathlib import Path
sys.path.insert(0, 'tool')
from compare_local_performance import compare
p = Path('benchmark/results/2026-10-14-native-text-lifecycle/paired-validation.json')
saved = json.loads(p.read_text())
result = compare([Path(x) for x in saved['baselineRuns']],
                 [Path(x) for x in saved['candidateRuns']],
                 saved['declaredSourceChanges'],
                 json.loads(Path('benchmark/R4-03-TARGETS.json').read_text())['targets'])
assert result == saved
print(result['valid'], result['passed'])  # True False；保留性能未通过结论
PY
```

## 保留决定与下一批执行顺序

**保留 Live 块身份修复，以及两个本地宿主中受限的 TextKit 1 兼容实现。**
依据是独立生命周期诊断支持的全文写入成本下降、两轮 example 目标明显改善、app 四项
大文档目标仍通过，以及当前候选的行为回归、完整文件闭环和本轮人工复核通过。
这是一项本地兼容取舍，不是 R4-03 全量性能验收通过，也不证明四个非目标超线与实现无关。
兼容逻辑仅适用于 macOS 主版本 27 的指定隐藏插件视图；当前 GUI/性能证据仅覆盖
macOS 27.0.1 + Flutter 3.44.8。升级系统/SDK 时重新验证类匹配、输入、选区和无障碍，
条件不再适用或发现行为回退时撤回两个 `makeFirstResponder` override，并重跑受影响配对。

R4-03 继续进行中，下一批按以下顺序执行，保留原目标和所有失败数据：

1. 先在 example 实际 main 复现 10 KiB Source→Read 的帧 build 长尾，在 app 实际 main
   复现 10 KiB save 的非磁盘回调等待；用相同 Dart 输入、仅切换原生 override 的对照，
   区分兼容路径与组件身份变化。诊断采样单列，不能替代正式轮。
2. 继续 app 10 KiB Live 的字段激活/输入法等待归因，保留 39.03 / 40.6548 ms 历史线。
   新的环境记录可补充当前输入法 ID，但不能回填或改变 R4-02 历史基线。
3. 若需修复，先增加能区分修复前后的行为/成本证据，再跑完整回归及两个 main 各两轮
   同配置正式配对；若涉及 composing 或原生输入，重做本轮范围的人工复核。
4. 只有全部目标及非目标通过才关闭 R4-03。若需要布局架构评估，明确保留状态，再依计划
   推进 R4-04 不涉及该布局的范围契约。当前总计仍完成 18、进行中 1、待开始 4，剩余 5。

本轮有限 VoiceOver 结果不关闭 R4-07；外部真实只读/编辑宿主仍留到最终分发阶段提醒。

## 交付与门禁

提交顺序：`6cecabe` 记录激活顺序及撤回宽度实验；`d30d62b` 保留 Live 块身份；
`373d206` 提交受控 macOS 27 TextKit 候选；`9589be8` 保存接续点；`6a1c102` 保存
四轮正式数据、一次无效尝试和本轮人工结果；随后单独提交本报告、保留决定及 roadmap。
运行输入未再改变，不为纯文档重复 GUI/全量构建。完整本地检查和默认四构建见上文及
`checks/`。`9589be8` 的双 SDK Core 与 Native 均已通过；最终文档头仍须通过
[PR #26 Checks](https://github.com/robinfai/ianvs-markdown/pull/26/checks) 后合入并同步主工作区。
