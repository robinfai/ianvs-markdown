# R2-05 预解析与复制预算验证

本任务限制送入昂贵解析器的输入，并保留完整源码。它不是 R2-01 的文本排版或交互延迟验收。实现提交 `ee69d50`，基于 `main` 的 `659df15`（与 PR #7 的 `5d63927` 源码树相同），使用未修改的 Flutter 3.44.8 / Dart 3.12.2、macOS 27.0.1 arm64。版本仍是 `0.3.1` + `Unreleased`，没有发布。

## 问题与证据

旧扫描器只限制语法 token。1 MiB ASCII 单行只含一个 `[` 时仍获准解析，但 Controller 引用、文档标题、整篇 HTML 和局部复制均在进入操作后的 5 秒期限内未返回。父进程终止各自的子进程组，不让同步 Dart 解析阻塞整个验证进程。没有 `[` 的单行虽能跳过引用解析，HTML 路径同样超时。

证据保存在 [原组件结果](results/2026-10-10-processing-budget/before-component.json)、[原解析诊断](results/2026-10-10-processing-budget/before-parser.json) 和 [原脚本/日志压缩包](results/2026-10-10-processing-budget/before-logs-and-probes.json.gz)。后者是 gzip JSON，键为原脚本或日志文件名；可用 Python `gzip.open(..., 'rt')` 与 `json.load` 读取。测量基线为 `5d63927`，工具与输入生成方式一起保留。复现时可在 `5d63927` 的隔离检出中解析依赖，将压缩包内脚本恢复到 `build/roadmap/r2-05/`，调整 SDK 路径后运行 `run_component_probe.py`。原组件测试的 `html` 名称曾使用子串筛选，但该第一项已超时并结束该进程，未混入其他测量；新工具采用锚定的精确名称。

第一版候选选择 8,192 单元行长，通过 19/20 项；未闭合链接在该精确边界的 Controller 创建/编辑/撤销/重做组合仍超过 5 秒，其他解析组合约 1.46–3.01 秒。不能仅因 1 MiB 已被拒绝就宣告边界可用。因此收紧到 4,096 单元，再加入行长加一、独立 CR、含括号分行的对照。保留 [8,192 候选结果](results/2026-10-10-processing-budget/candidate-8192.json) 与 [日志](results/2026-10-10-processing-budget/candidate-8192-logs.json.gz)，没有抹除失败。

## 实现与边界

默认输入额度：全文 1,048,576 个 UTF-16 单元、LF 分隔的每行 4,096 个 UTF-16 单元、4,096 个语法 token。CRLF 的 CR 不计入行长，独立 CR 计入行长，以免绕过仍按 LF 分行的引用解析。恰好等于上限允许通过；超出才降级。显示前缀仍最多 64 KiB UTF-8，不切开有效 Unicode 码点。

| 路径 | 检查位置与结果 |
| --- | --- |
| Controller | 构造及文本改变时，用 `parseBudget` 先扫描；拒绝则不做引用解析和语法高亮。`parseDecision` 可查询并随原有通知观察；选择/composing 不重新扫描 |
| Document / View | 先检查完整原文，再解析 YAML、标题和折叠。拒绝时原文/body 不变，元数据/标题为空，显示包括 YAML 的原始前缀 |
| Live | 用 `renderBudget` 在引用、跨段高亮、脚注、块和标题前检查全文。拒绝则保留完整源码编辑，不创建部分块映射；帧后 `onRenderDecision` 可观察 |
| Source | Controller 拒绝后不做语法高亮和背景结构解析；完整文本继续交给 Flutter 编辑/排版。输入格式器分别检查新旧值，拒绝时不改写输入 |
| 复制 | `clipboardBudget` 独立于显示额度；整篇保留精确原文，局部超限保留全部可见所选纯文本。跳过 Markdown/DOM 转换，返回空 HTML 与 `budgetExceeded` |
| 可选原生 writer | 无 HTML 时直接写完整纯文本，不访问原生 writer 工厂；有 HTML 时保留既有双表示及失败回退 |

各参数的 `null` 只关闭对应操作的保护。宿主希望策略一致时，需要给 Controller、Widget 和复制明确传同一预算；Widget 无法追溯保护 Controller 已发生的构造过程。Public `Document`、标题及折叠模型也提供独立预算。低层源码操作工具不是统一受限 AST 服务，调用者仍负责其输入预扫描。

Live 在超限和恢复之间保留 Controller、模式、文本、选择、保存与历史。恢复到 Live 时若仍有 IME composing，会等提交后再切换。专项回归发现共享 FocusNode 不足以让新文本框获得输入连接，因此切换后对新 EditableText 明确请求键盘连接，使用真实测试输入通道验证能继续输入。旧文档或预算已过期的帧后结果不会重新激活错误的编辑面。

## 独立进程检查

入口：[Python 超时控制器](../tool/check_processing_budget.py)、[Flutter 用例](processing_budget_probe_test.dart)。每个用例拥有独立进程组，启动期限 60 秒；收到 `PROBE_READY` 后的操作期限 5 秒。失败仍写日志和 JSON；未进入操作的构建失败不能当成解析超时。超时由父进程终止整个所属进程组，包含 `flutter_tester`。普通 Dart 测试的超时不能中断一个不让出执行权的同步解析器。

```sh
make deps-core
make check-processing-budget
# 等价，可指定输出目录和已安装 SDK：
python3 tool/check_processing_budget.py \
  --flutter /path/to/flutter/bin/flutter \
  --output build/processing-budget
```

八种语料，各自覆盖 Controller、Document/两种折叠预设、整篇 HTML、局部复制，共 32 项：

| 语料 | 默认行为 |
| --- | --- |
| 1 MiB 单行纯文本 | 拒绝 Markdown 处理，保留完整文本 |
| 1 MiB 单行未闭合 `[` | 同上 |
| 约 1 MiB 密集 `[x](y)` | 语法预算拒绝 |
| 1 MiB，每行 127 个 `a` + LF | 正常解析 |
| 约 1 MiB 分行文本，开头额外 `[` | 保持完整解析 |
| 4,096 单元未闭合 `[` | 边界允许，完整结果与源码保留 |
| 4,097 单元未闭合 `[` | 行长拒绝 |
| 1 MiB 交替 `a` / 独立 CR | 行长拒绝，不能伪装为短行 |

4,096 候选 **32/32 通过**，见 [结果](results/2026-10-10-processing-budget/candidate-4096.json) 与 [日志](results/2026-10-10-processing-budget/candidate-4096-logs.json.gz)。JSON 中的 `log` 对应压缩包内的键；`revision` 是当时基线，`trackedDiffSha256` 标识运行开始时的工作区改动。输入生成和测量范围在用例中明确。

这些是 Flutter test/JIT 的单次诊断，不是 profile 基准或 CI 延迟承诺。当前 Controller 用例含创建、写入、撤销/重做；文档用例含两种折叠模型；HTML 用例含整篇 payload 与独立 HTML 两次调用。旧基线只测单次操作，不能从这些数值计算配对提速百分比。4,096 边界的 Controller 组合仍约 1.36 秒，说明允许通过不等于满足交互延迟目标；该热点继续交给 R2-01。

## 回归与剩余范围

普通回归覆盖 UTF-16/UTF-8、CRLF、精确上限/加一、YAML 解析顺序、完整源码与局部文本复制、独立关闭、撤销/保存、选择复用、预算/对象替换、焦点及 IME。正文、View、Live Reading 三个入口都验证显示截断不会截断整篇复制。编辑样例显示宿主降级提示，包外 smoke host 直接使用公共预算与复制 API。核心 CI 的两种 SDK 都执行独立进程检查并上传结果。

完整 `CARGO_PROFILE_RELEASE_STRIP=none make check` 已通过：核心 **918**、示例 **10**、适配器 **6**、app **274**（可选外部语料跳过 1）、Mermaid Flutter **9** / Rust **4**、原生示例 **3**、Quick Look Rust **8** / Swift **10** 及原生导入。最终 [32 项结果](results/2026-10-10-processing-budget/acceptance.json) 与 [日志](results/2026-10-10-processing-budget/acceptance-logs.json.gz) 归档；Pub 快照 **147 文件、625 KB**，dry-run 零警告，示例与独立宿主通过，无工作区路径泄漏。

额外核对了 `maxFallbackBytes: 0` 时仍能显式全选复制完整原文；Live 的输入格式器也接收宿主 Controller 的预算，并通过跨上限/恢复时的真实测试输入通道保留 composing。性能 harness 同时设置 `parseBudget` / `renderBudget` / `clipboardBudget`，并标记新的预算语义；最后的接线经格式及分析通过，未运行新的 profile 全量采样。远端 Core/Native 以承载本批实现的 PR 最终 Checks 为准，通过准确提交的所有检查后才合入。

Source/Live 纯源码面仍排版完整文本，系统剪贴板仍需传输完整字符串；这些路径的耗时与内存未被输入预算限制。自定义语法、资源 builder 和插件实现也不受该计数器的运行时间约束。真实 IME、跨应用粘贴、触摸与读屏继续归 R3-01。本任务没有重跑 R0 的完整 profile 前后配对，也没有完成 R2-01。
