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
