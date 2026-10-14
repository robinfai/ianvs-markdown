# R4-03：双入口大文档成本

状态：**进行中，未通过全部性能退出条件**；日期 2026-10-14。起点为 PR #24 合入 `e12b701`。
本批保留 app 大纲/统计优化，四项 1 MiB 输入的两轮 P95 均改善至少 20%；
example Read→Live 仍约 2.66 秒。另有两项 10 KiB Live 场景超出历史观察线，
同环境旧实现控制轮也复现。配对结果为 `valid=true, passed=false`，不关闭 R4-03。
交付通过 [PR #25](https://github.com/robinfai/ianvs-markdown/pull/25) 分步提交。

## 实现前的目标和归因方案

沿用 [R4-02 协议](LOCAL-PERFORMANCE-PROTOCOL.md) 与两轮冻结证据。example 1 MiB
Read→Live 两轮 P95 必须均 ≤ 2100.694 ms。先解释约 2.6 秒总等待与约 66 ms
归属帧的差值；不能直接归因于解析。app 1 MiB 四项输入的目标在 CPU 归因后、
优化实现前冻结。保留完整文本、字体、预算、语料、窗口和动作。

CPU 诊断仅在两个原 main 内开启 `IANVS_PERF_ATTRIBUTION=true`，过滤到 1 MiB
输入和 Read→Live；写入 VM 时间区间与本机 VM service 地址。其协议标识为
`r4-attribution-only-v1`，正式校验器必须拒绝。诊断 CPU 采样有额外开销，不能
并入正式候选成绩。默认构建及正式性能构建不开启该标志。

本批按归因/目标、最小实现与回归、两入口各两轮完整配对、默认构建和 Release
实际使用分步交付。外部产品接入仍留到最终分发阶段。

## 优化前归因与追加目标

受测代码 `1ee8342`，原版 SDK 与 R4-02 一致；两个 main 内的诊断运行各 125
动作，原始结果/CPU 样本见 [归因目录](results/2026-10-14-large-document-costs/attribution/)。
example 第一次 profiler 初始关闭，随后手动开启并保留原生 sample；第二次和 app
在动作前显式启用 CPU profiler。CPU 数据不是正式延迟成绩，不保留 VM service 地址。

- example 第二次 Read→Live 的完整动作 2562.318 ms，2011 CPU 样本中 1941
  落在 `flushSemantics`，1936 落在原生语义更新。原生 sample 指向
  `FlutterTextField.startEditing → updateString → NSTextField.setStringValue →
  NSTextView._scrollRangeToVisible → NSTextLayoutManager`。Flutter FrameTiming
  的构建区间不覆盖这段同步原生语义工作，约 2.5 秒差额不来自 Markdown 解析。
- app sourceType 197.079 ms / 151 CPU 样本，其中大纲 `_headings` 69（块解析
  46、逐标题 Markdown 解析 23），状态栏 builder 25；输入回调与预算扫描仅少量。
  app Read→Live 87.962 ms / 68 样本，语义刷新仅 5。两入口差异还需进一步隔离。

在任何优化实现前冻结 app 1 MiB Source/Live 输入及粘贴各改善至少 20%，
按两轮较快基线计算。机器可读阈值见 [R4-03-TARGETS.json](R4-03-TARGETS.json)。
候选方向：保留当前大纲块识别与完整标题，复用未变化标题的解析结果；状态栏用
一次 UTF-16 遍历保持当前空白分词和 Unicode scalar 计数语义。选区/composing
变化复用同一文本结果。所有结果必须在同一帧正确显示，不靠延迟侧栏工作换成绩。

## 候选设计与排除记录

进一步的原生对照记录了两个 main 最终相同的选区 2、完整 1 MiB 文本、TextKit 2
和输入插件状态，差异发生在语义刷新期间，而非最终文本长度。app 原有 route 内
`Semantics(container: true, explicitChildNodes: true)`；组件本身此前借用了宿主 route
节点。新增语义范围回归在原实现失败（scopesRoute=true），独立组件范围后通过，
并检查 Source→Read→Live 的语义节点稳定与完整正文值仍然存在。

候选一在 LiveEditor 外层建立自己的语义范围；没有移除或截断编辑字段的语义值，
没有更改焦点/composing 时序。它是否能减少 macOS 桥接耗时仍需真实 Profile 验证。
核心 Live 编辑器与范围回归 390 项通过。

候选二将 app 大纲解析结果和状态栏统计保留在 DocumentSession 内，文本不变时
复用，文本变化仍同步更新。大纲继续采用原组件块识别，只缓存当前标题来源的
inline 解析；过期标题不会累积成历史缓存。统计一次扫描保持原 `\S+` 分词及
`String.runes.length` 口径，包括 CRLF、组合字符、emoji 和孤立 surrogate。
4 项派生数据回归及大纲/大文档/输入主入口共 14 项通过。

### 已否决：组件内显式子节点边界

`a521710` 的组件边界候选没有改善 example：诊断 Read→Live 2627.521 ms，
2071 样本中 2004 仍在 flushSemantics；app 更从约 88 ms 回退到约 2.65 秒。
app 实验末尾窗口失焦后恢复（generation 2），124/125 条记录，整轮标无效；
已有 CPU 区间仅用于否决该方案，不可计入正式延迟配对。全部证据保留。

因此撤回组件包装及其新语义边界断言，不把“测试通过”当成性能完成。随后对照
只在 example 的 home 采用 app 原有的宿主级语义边界；app 保留计算优化。
边界所在层级影响原生桥接，仍需实际 main 结果，不能从语义树结构推断改善。
app 已取得的输入诊断为约 140 ms、粘贴约 176–181 ms，尚非正式两轮结果。

### 已否决：example 宿主级边界

`5f7da67` 的 home 边界对照完成 125/125 动作。Read→Live CPU 区间为
2495.821 ms / 1965 样本，整组仍约 2.5–2.7 秒，未达到冻结目标。因此同样
撤回，example 与核心编辑器恢复原有语义结构。原始运行和 CPU 证据保留在
`r403-host-boundary-example` 与 `cpu-example-host-candidate`。

最终仅保留 app 派生数据计算优化。完整回归及正式两轮配对覆盖两个 main，
example 未达标继续保留为 R4-03 未完成项。已定位的原生文本字段激活/
布局热点需要独立的生命周期设计；尚不能解释两入口所有触发差异，不能关闭
可访问性、截断全文或用额外焦点变更规避成本。

## 最终保留的实现与两轮正式配对

受测运行源码为 `6a57e55`；在后续对照结束后逐文件恢复，全部运行输入 SHA-256 与
[冻结记录](results/2026-10-14-large-document-costs/build-profile/freeze.json) 完全一致。
只保留 app 的 `DocumentAnalysis`：未变化标题复用 inline 解析，当前块边界仍完整扫描；
统计保持原空白分词和 Unicode scalar 计数。缓存限于每个当前文档，未引入 debounce、
异步 UI 更新或历史文本缓存。核心编辑器与 example main 恢复原语义结构，公共 API 不变。

原版 Flutter 3.44.8 / Dart 3.12.2、M4 Pro / macOS 27.0.1、Profile；语料、预算、
字体、窗口和 5 次预热 / 20 次正式动作均沿用 R4-02。四个新进程串行完成，
**2,400 正式 / 600 预热**全部有效。本批正式候选无失焦重跑或删样本；额外的 CPU
实验及旧实现控制轮单列，不并入候选。原始 JSON、trace、语料、产物与源码哈希见
[证据目录](results/2026-10-14-large-document-costs/)。

下表为动作到下一帧完成的 P95，单位 ms。目标按优化前较快基线再改善 20% 冻结，未修改。
改善范围使用“较快旧基线 → 较慢候选”的保守比较；不是跨设备 SLA，也不是物理输入到屏幕像素。

| 1 MiB 场景 | R4-02 两轮 | 候选两轮 | 原目标上限 | 结果 |
| --- | --- | --- | --- | --- |
| example Read→Live | 2625.868 / 2672.944 | 2655.539 / 2657.556 | 2100.694 | 未达标 |
| app Source 输入 | 213.265 / 211.575 | 145.035 / 144.013 | 169.260 | 通过，改善 31.5% |
| app Live 输入 | 212.151 / 207.253 | 142.961 / 143.922 | 165.8024 | 通过，改善 30.6% |
| app Source 粘贴 | 243.325 / 244.958 | 177.424 / 176.816 | 194.660 | 通过，改善 27.1% |
| app Live 粘贴 | 245.241 / 240.276 | 177.031 / 180.266 | 192.2208 | 通过，改善 25.0% |

55 个非目标场景中 53 个在原观察线内；以下两项仍超线，不因补充对照而修改结论：

| app 10 KiB 场景 | R4-02 两轮 P95 | 候选两轮 P95 | 原观察线 | 旧实现完整控制轮 P95 |
| --- | --- | --- | --- | --- |
| Live 输入 | 31.335 / 32.525 | 42.608 / 43.084 | 39.030 | 45.182 |
| Live 粘贴 | 33.879 / 32.398 | 44.160 / 42.839 | 40.6548 | 44.068 |

小文档 Live 的 Flutter build P95 从约 15–18 ms 降到约 14–15 ms，增加的等待不在
构建区间内。追加同 main 的 10 KiB 新旧 CPU 对照，各 125 动作：两者均出现约
9–11 个原生语义更新 CPU 样本（1 ms 周期）。随后关闭 profiler 的旧实现完整控制轮
完成 825 动作、源码/窗口/文件校验通过，仍复现上述超线；其 1 MiB 四项输入为
206.816 / 207.374 / 241.343 / 238.802 ms（Source 输入 / Live 输入 / Source 粘贴 /
Live 粘贴），支持本批 app 大文档计算收益。

这些对照支持“小文档等待并非本轮计算优化新增”的判断，但没有解释 R4-02 到当前
原生等待为何变化，不能据此宣称历史观察线已通过。控制轮不是新基线，也不与候选拼接。
恢复旧路径仅涉及 DocumentSession、EditorShell、FloatingOutline 三个文件；其来源
为 `e12b701`。临时诊断语料选择补丁保留在
[small-attribution.patch](results/2026-10-14-large-document-costs/attribution/small-attribution.patch)，
完成后已撤回；正式协议和最终运行代码未因该对照改变。

每轮完整分布（P50/P95/max、callback、build、raster、RSS）见
[JSON](results/2026-10-14-large-document-costs/r403-summary.json) 和
[CSV](results/2026-10-14-large-document-costs/r403-summary.csv)。候选全过程 RSS 峰值
example 为 1381.05 / 1426.50 MiB，app 为 1585.36 / 1603.06 MiB；这不是堆上限或无泄漏证明。
[配对 JSON](results/2026-10-14-large-document-costs/r403-paired.json) 保留 60 项结果及三个未通过项。

## 回归、实际入口与复现

`make check-local build-local-release` 退出 0：核心 972、example 35、app 301
（另 1 项既有可选语料跳过）、API 8、Python 27、32 组独立进程预算检查，以及
剪贴板、Mermaid、Quick Look、原生导入通过。两 main 默认 Debug / Release 四个构建通过。
包快照检查通过，185 文件、零警告，示例和自动包集成 smoke 通过，无工作区路径泄漏。
这不是延期的真实外部产品接入验收。日志与摘要见
[验证证据](results/2026-10-14-large-document-costs/validation/validation.json)。

默认 Release 实测：example 替换含中文、emoji、组合字符的完整 Source，撤销/重做，
触发宿主保存回调并切换 Read/Live；app 修改标题/正文后大纲与统计同步更新，撤销恢复
10 words / 57 characters 和 Saved 状态。撤销后保存恢复原始 **81 字节 CRLF**；
重做后保存与所粘贴 **79 字节 LF**逐字节一致，关闭重开后保持 11 words / 55 characters、
正确标题和 Saved 状态。两种行尾按给定源码保留，没有把 LF 替换误称为 CRLF 保存。

CUA 的移动选区/逐键操作不能替代人工键盘验收：本次模式返回后的工具选区动作未折叠
Flutter 中的全选，随后组合输入替换了该选区；取消与撤销可恢复保存快照。本批未新增
物理键盘 IME 或 VoiceOver 验收，不扩大 R4-01 人工结果的覆盖范围。最终实现没有改变
输入路由、composing 或语义包装。

可从仓库根目录重放已归档的校验命令：

```sh
python3 -c 'import json, subprocess; c=json.load(open("benchmark/results/2026-10-14-large-document-costs/commands.json")); subprocess.run(c["analyze"], check=True)'
python3 -c 'import json, subprocess; c=json.load(open("benchmark/results/2026-10-14-large-document-costs/commands.json")); raise SystemExit(subprocess.run(c["pair"]).returncode)'
```

第一条应成功；第二条应退出 **1** 并重写 `valid=true, passed=false` 的配对结果。
十个经审阅的源码差异路径列于命令和结果中：四个 app 运行文件，以及默认关闭的归因
设施、只读原生快照和构建工具。它们不改变正式动作、字号、预算或采样边界。
SDK、语料、窗口、输入字体与未声明源码差异均由校验器拒绝。
最终交付仍以 PR #25 最新头的 Core / Native 门禁为准，不用历史成功替代。

## 剩余边界与下一批实施顺序

example 的目标及两项小文档原观察线不会因 app 改善而取消。后续仍在两个实际 main 内做受控对照：

1. 记录 Read→Live 期间原生语义节点创建、无障碍焦点、文本字段激活和全文赋值的
   顺序，而不只采集动作前后快照。区分键盘焦点与无障碍焦点；当前 CPU 栈只能
   确认同步文本布局热点，尚未证明两入口触发差异的完整因果链。
2. 逐一隔离宿主属性区/侧栏、route 与编辑字段生命周期，保留同一全文、输入
   样式和预算。每次只改变一个因素，记录原生编辑客户端是否被重新安装或
   激活；不要再把 Semantics 包装层级变化本身当成修复。
3. 若能在组件内部复用正确的编辑/语义生命周期，先补模式切换、完整语义值、
   选区、composing、焦点及卸载回归，再走同协议两轮完整验证。涉及原生输入
   或读屏行为时，需要新的实际 IME/VoiceOver 复核，不能沿用历史人工结论。
4. 若兼容方案需要重做全文输入布局，另写范围/映射/历史/IME 成本设计后再实施；
   R4-03 保持进行中。R4-04 可先做不改变当前布局的源码范围契约，不能把它
   当作本项性能验收。外部产品接入仍留到最终分发时提醒用户。
