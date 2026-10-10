# R2-04 Live Editor 模块拆分验收

基线 `6c0e769`，实现提交 `875590a`（表格）、`1c02afd`（导航）、`f33ea43`（源码投影），受测整合提交 `0735d58`。公共 Widget、其他库源码及渲染算法保持不变；不是性能优化交付。职责和数据流见 [内部架构](../doc/LIVE_EDITOR_ARCHITECTURE.md)。

## 实现与正确性

- 同一 Dart library 中新增 table、navigation、source_projection 三个私有 part；导航和命中映射通过私有 State extension 组织。所有迁移正文逐字核验，主文件保留的逻辑不变，仅新增 part 指令及调整末尾空行。
- State 继续拥有监听、激活表面、焦点/IME、历史、输入和文档写回；投影只生成展示和源码偏移，不序列化回文档。私有 extension 仍读取 State，不声明已消除耦合。
- 未修改 Flutter 3.44.8 / Dart 3.12.2 的完整 `make check` 通过：核心 967、示例 20、Python 10、预算 32 组、app 274（1 项历史可选语料跳过），原生、剪贴板和包外回归全部通过。
- Pub 快照 164 文件、658 KB、零警告。三个 part 均进入快照，87 个 Dart 文件和 1 份 renderer 许可证的哈希与受测库/示例一致。未发布新版本。
- 受测 `0735d58` 的 [双 SDK Core](https://github.com/robinfai/ianvs-markdown/actions/runs/38039899211) 和 [Native](https://github.com/robinfai/ianvs-markdown/actions/runs/38039899212) 通过。文档收尾后的最终合入仍遵守 PR #13 最新头的门禁。

对应证据：[表格](results/2026-10-10-live-modules/table-validation.json)、[导航](results/2026-10-10-live-modules/navigation-validation.json)、[投影](results/2026-10-10-live-modules/projection-validation.json)、[完整检查与包快照](results/2026-10-10-live-modules/full-validation.json)。

## 完整性能复验

复用 R2-01 的 `r2-candidate-1` / `r2-candidate-3` 为前置结果：其库实现与重构前一致。固定同一临时 windowing SDK、harness、依赖、语料、1180 × 780 窗口、5 次预热及每项 20 个正式样本；每轮六组场景、42 项操作、840 正式样本。临时 SDK 不用于平台支持声明。

| 轮次 | 用时 | 结果 |
| --- | --- | --- |
| r204-modules-1 | 427.9 秒 | 完整有效；两项 P95 超出预先固定的观察线 |
| r204-modules-2 | 331.4 秒 | 17:14:18 左右失去 active 状态，仍可见；原因未知，整轮排除，校验器拒绝 |
| r204-modules-3 | 401.0 秒 | 完整有效；42 项均未超出观察线 |

两轮有效结果的输入、窗口、原始 trace、源码变更清单和确定性解析门槛全部通过。只允许主文件和三个新 part 变化。**配对结果仍保留 2 条超线记录**，没有删除第一轮、移动观察线或拼接失焦轮次。

### 两项波动的调查

单位为 ms；以下均为 1 MiB 场景。观察线是同环境调查触发线，不是平台无关的 CI SLA。

| 操作 | 重构前两轮 P95 | 第一轮 / 第三轮 P95 | 观察线 | 定向旧版 / 新版 P95 |
| --- | --- | --- | --- | --- |
| 默认预算 Reading→Live | 82.414 / 82.263 | 113.880 / 81.092 | 104 | 79.433 / 85.092 |
| 无预算滚动 | 85.468 / 83.180 | 114.222 / 85.710 | 107 | 83.581 / 85.342 |

首轮对应 build 帧 P95 分别为 104.421 / 105.465 ms，第三轮为 72.678 / 82.302 ms；raster 帧没有同等幅度增加。因此超线发生于构建帧耗时，但没有证据将原因归为某个后台应用、温度或系统弹窗。

随后以重构前 `6c0e769` 和受测 `0735d58` 各做两项独立定向运行，全部保留 5 次预热、20 正式样本，并核对每个窗口事件、原始指标、SDK/宿主和源码差异。两项均未复现超线。定向运行标记 `fullBaseline: false`，不能冒充额外完整轮次。

验收判断：结合原声明等价性、完整回归、完整第三轮及旧/新定向对照，未发现可重复的明显代码性能回退；接受本次职责拆分。第一轮波动的系统层原因仍未知，证据和观察线持续保留，后续同条件出现重复超线时重新调查。本判断不等于所有有效样本均达线，也不声明性能改善。

无预算 Live→Source 仍约 6.18–6.29 秒；默认输入 P95 为 368.5–453.8 ms。原有性能边界继续有效。

[全部配对数据](results/2026-10-10-live-modules/paired-comparison.json)、[波动与定向校验](results/2026-10-10-live-modules/performance-validation.json)、[证据哈希索引](results/2026-10-10-live-modules/SHA256.json)。

## 平台与后续

最终模块输入在未修改 Flutter 3.47.7 的四次定向构建中，对照 Profile/Release 通过，Reading 两种模式仍为 AOT 失败，见 [平台复核](MACOS-CANDIDATES-2026-10-10.md#r2-04-模块拆分后的-reading-复核)。R3-01 继续处理 SDK/平台与真实交互；R3-02 的两个真实外部宿主按用户要求留到最后提醒其操作；R3-03 的最终 API/发布候选验收依赖前两项，不提前宣告 1.0 或发布。
