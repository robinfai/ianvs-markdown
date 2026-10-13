# 两个实际主入口的交互性能基线（R4-02）

入口为 `example/lib/main.dart` 和 `app/lib/main.dart`，沿用各自页面树、菜单、编辑器和
app 的文件工作流。默认关闭的诊断面板负责加载固定合成语料与串行采样，不增加独立 main。
两个入口各两轮完整有效测量及归档副本校验均已通过。R4-02 完成；本项建立基线，不宣称性能改善。

## 冻结协议与边界

[协议](LOCAL-PERFORMANCE-PROTOCOL.md)在有效测量前冻结，使用原版 Flutter 3.44.8 /
Dart 3.12.2、默认预算、Profile。精确 10 KiB、100 KiB、1 MiB 的语料包含中文、emoji、
标题、段落、列表、代码与表格；没有网络资源、长单行或原生图表，不能推广为所有文档表现。
每动作固定 5 次预热、20 次正式样本；example 27 组，app 33 组。两个入口各两次新进程，
串行完成，共 2,400 个正式样本和 600 个预热样本。窗口、源码、SDK、二进制和语料哈希均校验。

框架合成输入不代表物理键盘/IME 延迟；粘贴从剪贴板读取后的插入路径开始，排除系统剪贴板。
`callbackMs` 是动作调用到返回，`nextFrameMs` 是同一起点到回调后下一帧结束，不是显示器呈现时间。
尾部动作包含懒布局逐帧更新范围的收敛时间，最多 100 帧、连续两帧稳定，记录 `tailPasses`。
帧按共享引擎 frameNumber 归属，保留 build/raster/totalSpan 及原始时钟；RSS 是完整进程驻留量。
app 打开/保存包含正常文件服务与文档通知，磁盘子区间另记；恢复快照在编辑采样前后排空。
临时文件为暖缓存本地文件，不代表 iCloud、冷盘、文件面板或启动耗时。

两轮 P95 的较大值记为 H，观察线固定为 `max(H × 1.20, H + 2 ms)`。
使用 nearest-rank 统计，不删慢样本；观察线用于同配置后续配对，不是跨机器 SLA 或显著性检验。

## 四轮有效结果与环境

最终受测提交 `3956a01320945de4916c6480118cc63b1d961f5c`，两个 Profile 二进制来自
同一 [冻结清单](results/2026-10-13-main-entry-performance/build-profile-4/freeze.json)。
SDK revision `058e0af2c2b57e369d905a03ac9748b0ebf543c6`，工作树干净；Apple M4 Pro /
48 GiB、macOS 27.0.1 (26A434) arm64、Xcode 27.0 (27A266a)。保留仓库已有
`FLUTTER_XCODE_ARCHS=arm64`、`CARGO_PROFILE_RELEASE_STRIP=none`。

| 轮次 | PID | UTC 起止 | 正式 / 预热 | 结果 |
| --- | --- | --- | --- | --- |
| example-1 | 62508 | 05:38:56–05:44:34 | 540 / 135 | 完整有效 |
| example-2 | 67939 | 05:45:40–05:51:22 | 540 / 135 | 完整有效 |
| app-1 | 82529 | 05:58:14–06:03:28 | 660 / 165 | 完整有效 |
| app-2 | 89821 | 06:04:04–06:09:13 | 660 / 165 | 完整有效 |

四轮都在 2026-10-13 串行运行，最终校验 `valid=true`。example 为 1180×780 逻辑像素，
app 为 1200×780，scale 2、浅色、文字缩放 1；同入口两轮窗口尺寸/位置、输入字体逐样本相同。
Source 使用 SF Mono 13.5 / height 1.62；example 字距 0.5，app 字距 0。正常 Live 输入
使用系统字体 14.5 / height 1.58，example 字距 0.25，app 字距 0 且保留应用字体回退。
完整字体、窗口、屏幕及逐样本记录均在原始结果中，两个入口不做同布局横向排名。

| 语料 | UTF-8 字节 | UTF-16 单元 | 默认分支 | Reading 字节 |
| --- | --- | --- | --- | --- |
| 10 KiB | 10,240 | 10,004 | 完整 Markdown | 10,240 |
| 100 KiB | 102,400 | 100,094 | syntaxTokens 降级 | 65,536 |
| 1 MiB | 1,048,576 | 1,025,282 | syntaxTokens 降级 | 65,536 |

四轮语料 SHA-256 一致；降级只限制处理/Reading，完整源码及保存校验均通过。
所有尾部动作在 2–3 次布局检查内收敛，没有改预算、裁剪编辑原文或缩减固定样本。

## 主要延迟与可复验观察线

下表单位 ms，数值为第 1 / 第 2 轮；`到下一帧` 从动作起点计时。完整 60 个场景的
P50/P95/max、callback/frameWait、build/raster/totalSpan、RSS 和磁盘子区间见
[summary.csv](results/2026-10-13-main-entry-performance/summary.csv)；
[summary.json](results/2026-10-13-main-entry-performance/summary.json) 另含原始分布、帧数和排序。

| 入口 / 尺寸 / 动作 | 到下一帧 P50 | 到下一帧 P95 | 回调 P95 | 观察线 |
| --- | --- | --- | --- | --- |
| example / 1 MiB / readToLive | 2528.404 / 2615.949 | 2625.868 / 2672.944 | 0.040 / 0.052 | 3207.533 |
| example / 1 MiB / sourceType | 75.940 / 75.391 | 83.173 / 83.212 | 7.036 / 6.943 | 99.854 |
| example / 1 MiB / liveType | 75.625 / 75.436 | 76.772 / 77.463 | 7.339 / 8.770 | 92.956 |
| example / 1 MiB / sourcePaste | 112.979 / 112.863 | 114.319 / 113.758 | 20.217 / 20.720 | 137.183 |
| example / 1 MiB / livePaste | 111.855 / 115.828 | 113.648 / 121.980 | 19.680 / 19.018 | 146.376 |
| app / 1 MiB / sourceType | 211.691 / 206.904 | 213.265 / 211.575 | 8.940 / 8.105 | 255.918 |
| app / 1 MiB / liveType | 205.587 / 204.361 | 212.151 / 207.253 | 8.167 / 8.017 | 254.581 |
| app / 1 MiB / sourcePaste | 240.011 / 239.171 | 243.325 / 244.958 | 21.490 / 19.941 | 293.950 |
| app / 1 MiB / livePaste | 240.387 / 237.535 | 245.241 / 240.276 | 20.621 / 20.642 | 294.289 |
| app / 1 MiB / readToLive | 96.273 / 96.398 | 104.001 / 105.220 | 0.103 / 0.090 | 126.264 |
| app / 1 MiB / open | 211.261 / 210.764 | 218.193 / 217.770 | 19.906 / 19.202 | 261.832 |
| app / 1 MiB / save | 183.427 / 180.256 | 192.834 / 194.303 | 181.903 / 183.644 | 233.164 |
| example / 10 KiB / liveTail | 302.485 / 301.393 | 329.421 / 332.074 | 322.070 / 324.224 | 398.489 |
| app / 10 KiB / liveTail | 331.087 / 300.141 | 348.315 / 314.732 | 340.582 / 306.988 | 417.978 |

关键分布解释：

- example 1 MiB Read→Live 的回调 P95 只有 0.040/0.052 ms，归属帧 build P95 为
  65.359/66.260 ms、raster 0.560/0.536 ms、totalSpan 66.093/66.949 ms，但总等待
  2.626/2.673 秒。帧时长没有覆盖大部分等待，不能仅凭这份数据归因到解析或栅格化；
  下一批应补命令之后的调度、布局及帧前后时间线/CPU 样本。
- app 1 MiB 输入 build P95 约 189–194 ms，raster 约 2.5–2.8 ms；批量插入 build
  约 181–192 ms。这指向 UI 线程/布局路径的调查优先级，仍需 CPU 归因确认。
- app 1 MiB 打开：磁盘读取 P95 15.541/15.571 ms，整个回调 19.906/19.202 ms，
  到下一帧 218.193/217.770 ms。保存：写入 10.711/10.797 ms，回调 181.903/183.644 ms，
  到下一帧 192.834/194.303 ms。子区间与回调嵌套，不相加，不将全部保存时间称作磁盘延迟。
- 10 KiB Live 尾部到达，两入口 P95 约 315–348 ms，主要帧 build P95 约 195–224 ms；
  动作包含 2–3 帧收敛，不能与单次 jumpTo 或键盘 End 延迟直接比较。
- 四轮全流程 RSS 峰值分别为 example 1401.8/1398.8 MiB、app 1641.0/1620.2 MiB。
  这是宿主/引擎/缓存的进程值，既不是组件堆用量，也不证明泄漏；R4-06 再做持续会话和释放配对。

## R4-03 的执行起点

1. 首先复现并归因 **example 默认预算 1 MiB Read→Live**：区分命令通知、焦点/选区、
   Source/Live 布局、调度与真正完成帧，不用旧独立入口代替。首个候选目标为两轮 P95
   均不高于 `2625.868 × 0.8 = 2100.694 ms`，即至少比本基线较快一轮改善 20%。
2. 同时用 app 1 MiB Source/Live 输入及批量插入检查共享路径；确认热点后再冻结对应改善
   目标。先做最小改动，不能预设需要全量虚拟化，也不能靠关闭选择、字距/字体、IME 或预算换成绩。
3. 10 KiB Live 尾部和 app 大文档打开/保存作为后续调查及回归观察项；R4-03 候选必须重跑
   两入口各两轮，所有非目标动作不超过本次固定观察线。大文档优化之外的契约交给 R4-04。

R4-03 仍为待开始。本轮只交付可重复基线和立项依据；如果后续归因证明目标不可用，先记录
证据并调整方案，不能将本轮基线登记为优化成果。R4 还剩 R4-03 至 R4-07 共 5 项。

## 采样器校准与无效轮次

这些轮次保留原始结果和错误，均不计入基线：

- `build-profile-1`：example 构建通过，app 因重复 Swift `deinit` 失败；合并诊断观察者与
  原有文件授权清理后，两个原版 SDK Profile main 均构建成功。这不是上游 AOT 失败。
- `example-invalid-startup-1/2`：电脑工具后台启动/点击，原生 `active=false`，均为零样本。
  后续通过 Finder 正常打开应用确认前台，没有放宽窗口有效性策略。
- `example-invalid-frames-1`：25 次输入记录后帧证据匹配失败。改用引擎 frameNumber，
  避免 begin-frame 与 vsync 的微秒差；准备帧和动作完成后的帧仍拒绝归属。
- `example-invalid-tail-1`：200 次动作完成后，首次 Live 尾部检查失败。一次 jumpTo 的
  估算范围不能保证到达懒布局末尾，改为上述有上限的收敛动作，并重新冻结协议和二进制。
- `app-invalid-startup-1`：原生前台/可见性检查失败，零样本；初始化完成后经 Finder 再次激活。
- `app-invalid-focus-1`：637 次动作后失去前台，generation 增至 1；保留部分 trace 并从头重跑。

以上共六次无效运行，未拼接、未用于分布或观察线。归档中的 `build-profile-2/3` 是诊断修正前
构建；只有 `build-profile-4` 的四轮正式结果进入汇总。

## 本地门禁

`7592ab5` 的完整 `make check-local build-local-release` 退出 0：核心 972、example 35、
app 297（另有 1 项历史可选语料跳过）、API 8、Python 20、预算 32 组；Mermaid Flutter 9 /
Rust 4 / 示例 3、剪贴板 6、Quick Look Rust 8 / Swift 10、原生导入均通过；两个 main
默认 Debug/Release 共四次构建通过。公共 API 仍为 183 个导出、1,147 个声明。
帧归属与尾部诊断修正后另行分析并运行 Python 22 项；正式采样不并行执行这些检查。

初始 Pub-selected 快照 185 文件 / 694 KB、零警告，示例及自动包外 smoke 测试通过，
没有工作区路径泄漏。最终文档快照再次通过：185 文件 / 695 KB，
零警告，快照示例与自动包外 smoke 均通过；[清单](results/2026-10-13-main-entry-performance/package-manifest.json)
与 [摘要](results/2026-10-13-main-entry-performance/package-summary.json) 已归档。

版本仍为 0.3.1 + Unreleased；未修改 SDK、发布包或安装到 `/Applications`。
本轮没有重新执行物理 IME 或 VoiceOver；R4-01 的人工结果保持原记录。

受测代码 `3956a01` 的双 SDK Core、Core required 和 Native 已全绿：
[Core](https://github.com/robinfai/ianvs-markdown/actions/runs/38352361201)、
[Native](https://github.com/robinfai/ianvs-markdown/actions/runs/38352361211)。
最终文档头以 [PR #24 Checks](https://github.com/robinfai/ianvs-markdown/pull/24/checks) 为交付门禁。

## 证据索引

[validation.json](results/2026-10-13-main-entry-performance/validation.json) 记录代码、环境、
配置一致性、本地门禁、运行时 CI 和限制；同目录 `runs/` 保存四轮 result、trace、三份原始语料
和逐文件 SHA-256 receipt，`invalid/` 保存六次失败，`build-profile-*` 保存冻结清单与构建日志。
`*.log.gz` 保留本地完整检查、针对性分析与校准失败；解压只为阅读日志，不需要转换运行数据。

## 复验命令

```sh
make build-local-performance FLUTTER=/path/to/flutter/bin/flutter MODE=profile LABEL=baseline
# 按 freeze.json 中的 bundle 路径从 Finder 打开两个 Profile .app，依次 Run R4-02；每轮新进程。
# 运行期间保持窗口前台、尺寸和位置不变，不执行构建/测试。
python3 tool/local_performance.py collect \
  --freeze build/local-performance/build-baseline/freeze.json \
  --source /actual/output/directory --label example-1
# 同样收集 example-2、app-1、app-2，失败轮次也使用单独标签收集。
python3 tool/analyze_local_performance.py \
  build/local-performance/runs/example-1 build/local-performance/runs/example-2 \
  build/local-performance/runs/app-1 build/local-performance/runs/app-2 \
  --output build/local-performance/summary.json
```

采集前保持冻结输入和两个二进制不变；收集器会拒绝源码/SDK/构建漂移。
分析器检查全部 3,000 个动作及 trace、语料、帧归属、窗口事件、PID 和串行时间区间。
外部真实产品验收继续留到最终分发阶段再提醒，不作为本阶段前置条件。

归档复验无需重新构建或打开 GUI：

```sh
python3 tool/analyze_local_performance.py \
  benchmark/results/2026-10-13-main-entry-performance/runs/example-1 \
  benchmark/results/2026-10-13-main-entry-performance/runs/example-2 \
  benchmark/results/2026-10-13-main-entry-performance/runs/app-1 \
  benchmark/results/2026-10-13-main-entry-performance/runs/app-2 \
  --output /tmp/r402-summary.json
```
