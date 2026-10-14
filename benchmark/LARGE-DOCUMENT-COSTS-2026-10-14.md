# R4-03：双入口大文档成本

状态：进行中；日期 2026-10-14。起点为 PR #24 合入 `e12b701`。

## 实现前的目标和归因方案

沿用 [R4-02 协议](LOCAL-PERFORMANCE-PROTOCOL.md) 与两轮冻结证据。example 1 MiB
Read→Live 两轮 P95 必须均 ≤ 2100.694 ms。先解释约 2.6 秒总等待与约 66 ms
归属帧的差值；不能直接归因于解析。app 1 MiB 四项输入的目标在 CPU 归因后、
优化实现前冻结。保留完整文本、字体、预算、语料、窗口和动作。

CPU 诊断仅在两个原 main 内开启 `IANVS_PERF_ATTRIBUTION=true`，过滤到 1 MiB
输入和 Read→Live；写入 VM 时间区间与本机 VM service 地址。其协议标识为
`r4-attribution-only-v1`，正式校验器必须拒绝。诊断 CPU 采样有额外开销，不能
并入正式候选成绩。默认构建及正式性能构建不开启该标志。

后续按归因/目标 → 最小实现与回归 → 两入口各两轮完整配对 → 默认构建、Release
实际使用与文档证据分步提交。外部产品接入仍留到最终分发阶段。

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

## 第一组候选（待主入口性能验证）

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
