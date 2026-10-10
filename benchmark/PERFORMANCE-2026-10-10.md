# R2-01 性能归因与优化

状态：进行中，尚未完成性能验收。起点是 R2-05 已合入的 `dba969d`。本文件保留失败、归因、目标与后续配对证据，不以少量诊断样本替代完整基线。

## 环境与构建

Apple M4 Pro / macOS 27.0.1 arm64，Flutter 3.44.8 / Dart 3.12.2。未修改 SDK 的基准入口 Profile 构建仍在 `_window_macos.dart / _Rect` 失败，AOT snapshotter 返回 -6，未开始任何测量。之后用临时目录中的 SDK 副本，仅应用仓库已有的 windowing 补丁，10 KiB 的构建/启动检查通过。日常 SDK 未修改；这些数据是受控组件性能测量，不能关闭 R3-01 的未修改 SDK 候选构建缺口。

构建失败、受控预检查和初始归因见 [原始证据目录](results/2026-10-10-performance/)。JSON 记录准确源码、harness、runner、SDK 和补丁哈希。正式基线继续补充依赖/宿主文件哈希、逐动作 callback/等待帧耗时及生命周期状态。

## 初始归因（优化前）

独立进程 Profile 诊断，corpus v1，10 KiB / 100 KiB / 1 MiB，默认和显式关闭预算，七种操作，每项 1 次预热 / 2 个样本。42 项诊断执行完成，但样本数不足以产生正式延迟观察线。启用阶段计时并同时采 CPU，且日志存在前台激活失败；这些数据只提供热点线索，不作为正式延迟成绩。后续锁屏确认与完整基线中断见下节。

| 路径 | 实测线索 | 下一步 |
| --- | --- | --- |
| 100 KiB 输入 | Controller 和 Live 引用解析分别约 37–39 ms；块解析约 1.3 ms | 避免为收集引用而解析无关行内内容；检查能否按当前文档复用引用结果 |
| 1 MiB 无预算输入 | 两份引用解析合计约 735–754 ms，整体约 812–830 ms；Live 块约 12 ms，标题约 4.5 ms，脚注不足 1 ms | 优先处理引用热点，保持复杂定义、源码范围及预算行为；不以块缓存替代主要热点 |
| 1 MiB 无预算 Live → Source | 约 6.3–6.4 s；Source 语法跨度约 472–490 ms，背景排版约 282–318 ms；独立 CPU 样本 4,174 个，Skia spacing/cluster 处理独占约 74% | 分开验证源码样式、完整文本布局与背景几何；不得通过截断编辑源码获得收益 |
| 1 MiB 无预算 Source → Reading | 约 3.4–3.6 s；CPU 样本 2,221 个，`ListBase.contains` 独占 405 个，调用方是 MarkdownBuilder 的 `_isBlockTag`；文档标题还在进行全文 GFM 解析 | 检查重复渲染后的标签注册与查找；仅解析标题需要的行内内容，并保持原有标题语义 |
| 1 MiB 默认选区 | 一个样本约 64.7 s，另一个约 32 ms；长区间仅有 20 个 UI CPU 样本 | 保留异常，进一步区分 callback、等待帧和生命周期；当前证据不能归因于 Markdown 解析 |

静态检查当前依赖 `flutter_markdown_plus 1.0.12`，发现 `MarkdownBuilder.build` 每次把自定义块标签追加到库级 List，`_isBlockTag` 每次线性查找。重复渲染会累积重复标签；检查时的[上游源码](https://github.com/foresightmobile/flutter_markdown_plus/blob/main/lib/src/builder.dart) 同样存在该路径。该路径的跨文档语义错误已复现并修复，性能收益仍待配对测量。

## 本轮交付与未完成验收（2026-10-10）

完整基线以 `c7d8f5d` 为优化前版本开始运行。Flutter 报告 `Failed to foreground app`，电脑控制工具随后确认 Mac 已锁定。已停止本次基准所属的 Flutter 进程组；runner 记录 `complete: false`、`fullBaseline: false`，第二次基线没有开始。保留 [失败 JSON](results/2026-10-10-performance/r2-locked-before-1.json)、其引用的原始 trace、压缩日志和 [环境说明](results/2026-10-10-performance/r2-locked-before-1.environment.json)。这些样本不得用于生成观察线或声称性能改善。

等待可用 GUI 环境期间，先完成可独立验证的正确性修复：正文两种语法预设使用内部实例级块标签集合，每次构建重置，消除跨文档及重复配置切换时的标签泄漏。原实现中“行内 → 另一个文档的同名块 → 行内”测试失败；修复后两种预设各自的跨文档和 20 次重复切换测试均通过。保留 [失败日志](results/2026-10-10-performance/renderer-scope-before.log.gz)，实现来源、许可证、资源策略和升级检查见 [渲染器维护边界](../doc/RENDERER_IMPLEMENTATION.md)。公共导出和依赖版本未变。

另补 20 组语料的引用/标题等价性及跨块版本更新回归，为后续解析优化建立正确性约束；引用与标题解析优化本身尚未实施。本轮完整 `make check` 退出 0：核心 925、示例 10、Python 7、独立预算检查 32 组、app 274（1 项可选语料跳过）、Mermaid Flutter 9 / Rust 4、原生示例 3、剪贴板 6、Quick Look Rust 8 / Swift 10 和原生导入通过；包快照 dry-run 无警告、包外宿主通过。完整日志见 [renderer-check.log.gz](results/2026-10-10-performance/renderer-check.log.gz)。

此处调整了原定“基线后再修改”的顺序，只先交付已复现的正确性修复。性能验收仍须从保留的 `c7d8f5d` 源码和候选源码分别测量；若添加前台/可见性检查，必须让两边使用完全相同的 harness/runner，并显式记录源码差异。无需回退当前分支或复用失效样本。正式运行前确认机器已解锁、基准窗口可见且处于前台；确认运行期间的窗口状态有效后才接受结果。

## 交付顺序与验收范围

用户已确认解锁，基准小规模启动检查完成。新增原生窗口校验策略 `native-window-stable-v1`：启动最多等待 10 秒，之后每次动作前后记录前台、可见、隐藏、最小化、Space、窗口尺寸与变化代数。原生状态变化主动通知 Dart，即使窗口停止产帧也立即使本次运行失效；短暂离开后返回也不能恢复为有效样本。校验调用不计入动作耗时与帧区间。10 项证据校验器测试和 Dart 分析通过；[隐藏窗口实测](results/2026-10-10-performance/r2-environment-rejection.json)正确返回 `complete: false` / `fullBaseline: false`，错误包含 `visible: false`、`appHidden: true` 和代数变化，日志与 trace 同目录保留。此防护不检测其他后台负载或温度，完整运行时仍避免并行构建。

优化前源码固定在独立测量快照 `8d50d0d`（`c7d8f5d` 加相同的窗口校验与证据工具，`lib/` 未改动）；候选分支保持已完成的 renderer 修复。两次新完整基线使用 `r2-visible-before-1` / `r2-visible-before-2` 新标签串行启动，旧锁屏样本不复用。各次结果和补跑情况见下文；只有两次完整有效结果都通过逐样本校验后才生成观察线。

`r2-visible-before-1` 已完成且通过 `read_run` 逐样本校验：6 场景、42 操作、840 个正式样本，5 次预热 / 20 次测量，耗时 727.0 秒，无错误；归档后的 JSON 和 trace 再次校验通过。[第一轮原始结果](results/2026-10-10-performance/r2-visible-before-1.json)中，1 MiB 无预算输入 / Live→Source / Source→Reading 的 P95 为 836.8 / 6350.0 / 11302.8 ms。这是一轮优化前结果，尚不能生成重复基线观察线或声称优化收益。

`r2-visible-before-2` 在 1 MiB 无预算 Source→Reading 的正式样本索引 5 开始后收到 `active: false`、`generation: 2`，立即终止；其余窗口可见性标记仍正常，电脑控制随后确认桌面可访问，不能把这次中断写作锁屏。[第二轮失败记录](results/2026-10-10-performance/r2-visible-before-2.json)及 trace / 日志保留，`complete` 和 `fullBaseline` 均为 false。随后以新标签 `r2-visible-before-3` 补跑完整独立进程。该次在 1 MiB 无预算模式切换预热索引 3 又收到 `active: false` / `generation: 3` 并终止，耗时 331.1 秒；[第三次记录](results/2026-10-10-performance/r2-visible-before-3.json)同样为不完整。保留第一轮有效结果，不拼接失败轮的部分样本。再次复测前需具备约 12 分钟连续前台窗口，已向用户确认该条件；当前没有运行 GUI 基准。

用户确认可保持前台，完整回归和三套 SDK 候选构建结束后，以新标签 `r2-visible-before-4` 再次运行。该次在 1 MiB 无预算 Source→Reading 正式样本索引 13 开始后收到 `active: false` / `generation: 2`，于 634.1 秒结束；[第四次记录](results/2026-10-10-performance/r2-visible-before-4.json)仍为 `complete: false` / `fullBaseline: false`。电脑控制随后可以读取桌面应用，无法据此确定失焦来源或断言中断时曾锁屏。原始 trace 与日志已归档，校验器正确拒绝；有效完整基线仍只有第一轮。用户随后反馈可能出现系统弹窗，但未确认具体原因；不能据此归因为锁屏。第五次独立基线使用新标签补跑，结果见下。

`r2-visible-before-5` 在 100 KiB 无预算模式切换预热完成后收到 `active: false` /
`generation: 2`，运行 140.4 秒后终止；[第五次记录](results/2026-10-10-performance/r2-visible-before-5.json)
及 trace / 日志已保存，校验器拒绝不完整结果。随后桌面可访问，未确认锁屏或抢占焦点的应用。
下一次采样期间暂停其他提交、审批和桌面工具操作，以排除工具交互的干扰；固定测量输入不变。

1. 在有效 GUI 环境中用保留的优化前源码重新建立基线，固定环境和测量代码，关闭阶段计时，串行运行两个独立进程：每项 5 次预热 / 20 个样本、六个场景、七种操作。逐样本验证后生成同环境观察线，再实施后续热点优化。
2. 对引用/标题解析、持续渲染的标签状态、Source 文本与背景排版分别实施可回归的改动；每项有正确性与失效条件说明。预算语义和完整原文保持一致。
3. 补含括号长行、密集语法、跨块编辑与连续编辑验证；保留纯选区不刷新全文结构、文本变化正确刷新、IME、撤销/保存和 R2-05 超限语义。
4. 在相同测量代码下运行两个完整候选进程，显式列出库源码变化，用校验器检查环境、逐样本 trace、默认降级行为和 42 项覆盖；对超观察线项目继续诊断。
5. 完整 `make check`、发布快照、双 SDK Core / Native CI 后更新任务状态；原始证据、性能边界和剩余平台验收随提交保留。

当前已交付归因工具、诊断/失败证据、渲染器状态隔离及下述解析优化；正式重复基线和观察线现已补齐；配对收益验证和最终验收尚未完成。不能据此把 R2-01 标为完成。

## 引用与标题解析优化

第四次采样中断后，继续在候选分支实施已有归因支持的解析优化。此处再次调整
“完整基线后才实施”的工作顺序：优化前 `8d50d0d` 测量快照及其 SDK、语料、harness
保持不变，后续第二轮基线仍从该快照采集，全部有效基线必须先于候选性能测量完成。
不以正确性测试或实现改动代替配对性能成绩。

- 引用上下文使用上游 GFM BlockParser 收集定义，保留前向引用、嵌套容器、多行定义、
  大小写归一和重复定义的首次生效规则，跳过与收集定义无关的行内解析。
  `parseMarkdownLinkReferenceDefinitions` 的可见节点判定仍用完整解析。
- 大纲先做全文块解析收集前向定义，然后只解析符合层级要求的顶层标题行内内容。
  源码包含 `[^` 时保留完整上游解析，因为普通段落及被过滤的标题也会影响脚注编号。
  该保守条件可能让围栏或转义中的类似内容继续走完整解析，不改变输出语义。
- 没有添加跨调用缓存。每次文本更新重新建立局部 Document 和定义映射，预算预检查
  仍在解析前执行；源码、选择、composing、历史与保存契约保持不变。

等价性语料由 20 组扩充为 30 组，新增正文先引用、被过滤标题先引用、重复/缺失脚注、
嵌套容器、前向图片和 Setext 标题；跨版本序列覆盖脚注添加/删除，另加密集行内语法。
与完整上游 GFM 结果逐项比较。引用、标题、Controller、折叠、预算、持续追加共 164 项
定向回归已通过。实现提交 `c872097` 的完整 `make check` 退出 0：核心 961、示例 20、
Python 10、预算 32 组、app 274（1 项历史可选语料跳过）、原生及剪贴板全部通过；
包快照 159 文件、652 KB，dry-run 无警告，包内示例和仓库外接入通过，84 个实现文件
哈希与受测快照一致。证据见 [验证摘要](results/2026-10-10-performance/parse-optimization-validation.json)
及 [完整日志](results/2026-10-10-performance/parse-optimization-check.log.gz)。
最终推送头的远端门禁另行确认。该解析提交尚未改动 Source 排版；后续背景几何复用见下节。

## Source 背景几何复用与缓存

引用和围栏背景此前分别创建完整纯文本 TextPainter，重复排版，且没有复用编辑文本的
语法字体与宿主字距。新增对齐回归在旧实现中均失败：引用、代码背景的顶部与实际文字
边界相差约 2.09 px；这只是测试配置下的几何偏差，不是延迟测量。

本批移除这两份 TextPainter，通过同一 Source 字段的 RenderEditable 选择框获得当前
文字边界，再转换到背景所在 Stack 坐标。选择框已包含滚动 paint offset，不重复减去
scrollController.pixels。保留背景外扩、裁切、样式和活动代码 rail；实际布局拥有者继续
负责字体、语法样式、文字缩放、宽度、方向和滚动。没有修改字体、继承字距或完整源码。

只缓存当前源码的引用/围栏范围，每个编辑器状态至多保留一个源码版本：

- 纯选区、composing-only 和滚动复用范围，内部诊断计数器可验证不重解析。
- 文本修改、撤销、Controller 替换清空范围，包括变更后被预算拒绝而不再绘制的情况。
- 重新打开装饰或恢复到预算内时从当前文本计算；主题、缩放、方向和宽度变化使用字段
  的新布局，几何不跨帧缓存。父组件重建会重绘背景，避免漏掉宿主继承样式变化。

六项新回归覆盖换行/缩放/RTL/滚动对齐，选择与组合输入、Controller 替换、围栏闭合和
撤销、装饰开关、预算内外往返。连同流式和预算测试共 57 项通过，静态分析无问题。
实现 `760dad7` 的完整 `make check` 退出 0：核心 967、示例 20、Python 10、预算 32 组、
app 274（1 项历史可选语料跳过）、原生与剪贴板通过。包快照 160 文件、655 KB，
dry-run 无警告，84 个库与示例实现哈希匹配，包外宿主通过。
[验证摘要](results/2026-10-10-performance/source-background-validation.json)、
[完整日志](results/2026-10-10-performance/source-background-check.log.gz) 和
[旧实现的两项几何失败](results/2026-10-10-performance/source-background-before.log.gz) 已归档。
最终推送头的远端检查另行确认。正式基线和候选配对仍待完成；
Source 整段可编辑文本本身的排版仍存在，不把这次背景复用宣称为解决所有长文档延迟。

## 当前有效证据与继续条件

| 标签 | 结果 | 是否纳入重复基线 |
| --- | --- | --- |
| `r2-visible-before-1` | 完整 42/42 项、840 个正式样本，原始 trace/哈希/环境/解析次数校验通过 | 是 |
| `r2-visible-before-2` | 正式模式切换中失去前台，立即终止 | 否 |
| `r2-visible-before-3` | 模式切换预热中失去前台，立即终止 | 否 |
| `r2-visible-before-4` | 最后一组正式样本索引 13 失去前台，634.1 秒后结束 | 否 |
| `r2-visible-before-5` | 100 KiB 无预算模式切换预热后失去前台，140.4 秒后结束 | 否 |
| `r2-visible-before-6` | 完整 42/42 项、840 个正式样本，751.4 秒，逐样本与环境校验通过 | 是，第二轮完整有效基线 |

`r2-visible-before-6` 在暂停其他提交、审批及桌面操作的条件下完整完成；这不单独证明此前失焦的原因。
[第二轮有效结果](results/2026-10-10-performance/r2-visible-before-6.json) 与第一轮均通过逐样本、输入哈希、
SDK、窗口尺寸及非重叠运行校验。固定快照仍为 `8d50d0d`，阶段计时关闭，每项 5 次预热 / 20 个样本。
[42 条观察线](results/2026-10-10-performance/baseline-observation.json) 已归档，规则为两个基线 P95 的最大值
乘以 `max(1.25, 1 + 2 × 相对波动)` 再向上取整，只用于同环境退化调查。
1 MiB 无预算输入、Live→Source、Source→Reading 的第二轮 P95 为 865.9 / 6529.2 / 12025.0 ms，
对应观察线为 1083 / 8162 / 15032 ms。两轮候选复测及最终验收仍待完成，不能据此认定优化收益。
R2-01 保持进行中；优化实现 `d882078` 的双 SDK Core / Native CI 已全部通过。

性能进程结束后，对已整合 R2-03 的 `5eb6afb` 实现运行完整 `make check`，退出 0：核心 960、示例 20、Python 10、预算 32 组、app 274（1 项历史可选语料跳过）、剪贴板 6、Mermaid Flutter 9 / Rust 4、原生示例 3、Quick Look Rust 8 / Swift 10、原生导入通过。包快照 159 文件、651 KB，dry-run 无警告，包内示例和仓库外接入通过、无工作区路径泄漏；最终库及示例实现哈希与受测快照一致。证据见 [验证摘要](results/2026-10-10-performance/merged-validation.json)、[完整日志](results/2026-10-10-performance/merged-check.log.gz) 和 [包摘要](results/2026-10-10-performance/merged-package-summary.json)。同一提交的双 SDK Core / Native 远端检查均成功。该轮非 GUI 回归不能替代第二轮完整基线、候选配对或真实平台交互。
