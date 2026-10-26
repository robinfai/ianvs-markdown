# Markdown 增强交付验收 — 2026-10-26

## 结论与停止条件

按用户调整后的范围完成本轮交付：功能增强、源码保真、保存与恢复安全，以及无已知严重功能回退。性能观察线用于调查，不要求消除全部历史性能债务。保留原始失败报告，不调整阈值。物理 IME、VoiceOver、iOS 界面和长会话未验证项明确保留，不将其写成通过。本轮未提交、推送或发布。

本记录替代 ROADMAP 历史过程记录中“必须全部手工/性能验收通过才交付”的要求；历史记录仍用于追溯。

## 已交付与实测

- 统一阅读/源码锚点，模式、标签页、重启后的阅读位置恢复，目录和跨文档跳转返回；真实界面验证位置与原文不变。
- Read/Live 正文查找及定位；字号、行距、正文宽度、代码换行偏好保存和重启恢复。设置立即显示，系统文件关联查询异步刷新。
- 离线数学与 Mermaid 导出，中文 PDF 搜索/复制与分页；Markdown 与附件 ZIP 导出，解压搬移后附件仍可显示。PDF 渲染所需 macOS entitlement 已修复，离线导航/资源限制保留。
- HTML 富文本及 TSV 表格粘贴、单步撤销和纯文本路径。
- 冲突差异、覆盖前精确版本复核、保留两份；真实界面验证对话框期间磁盘再次变化时阻止旧版本覆盖。
- iOS 查找、阅读恢复和返回实现；已完成构建及原生测试，GUI 边界见下。

## 验证证据

此前完整集成检查包含核心 1298 项、example 34 项、应用 1136 项通过及 1 项跳过，另含导出、原生桥接、API/预算/包检查。完整过程日志为 `/tmp/ianvs-integration-final-pass.log`。这些结果对应此前集成阶段，不冒称最终一次全量重跑。

最终受影响检查：导航/锚点/返回历史 40 项全部通过（`/tmp/ianvs-final-reverted-navigation-tests.log`）；两个恢复后的 renderer 文件 SHA-256 与 recovery-timing 冻结输入完全一致。此前保存保护、计时、关联设置与偏好定向检查 33 项通过（`/tmp/ianvs-final-focused-20261026.log`）；恢复计时包装器及写入计时测试 4 项通过且静态分析通过。诊断计时默认关闭，不改变生产保存语义。

iOS 原生测试 3 项通过，记录 `/tmp/ianvs-ios-enhancement-20261026-tests.log`；不等同 iOS 界面验收。

## 性能结果与已知边界

增强前基线为 `1e0b62d4d89b7d511cefa77cf26fbe65dc64a75c`，app/example 各两轮完整有效，共 2400 条正式样本、600 条预热。与 guarded-timing 增强候选对比，原观察线 56/60 项通过：1 MiB Source→Read 约从 18–20 ms 增至 27 ms；另有两项单轮尾部输入超线。保存三个文档大小均在增强前相对观察线内。历史 Oct13/14 基线的保存超线仍保留，但安全快照写入成本在本批增强前已经存在。

可选换行扫描优化只将一次 Source→Read P95 降至 25.669 ms，同时该轮 Read→Live 出现 1308.279 ms 异常；因收益有限且因果未确定，已撤回该可选优化，不将该轮作为最终实现的通过证据，不再追加轮次。原始报告完整保留。

基线证据已从临时工作区按文件 SHA-256 验证复制到 `build/local-performance/pre-enhancement-1e0b62d-evidence/`。其中 `pre-enhancement-vs-guarded-timing-20261026.json` 为完整对比，`pre-enhancement-four-runs-20261026.json` 为四轮汇总。报告中原绝对路径为采样出处；复制未改写原始数据。增强候选和撤回候选证据仍在本仓库 `build/local-performance/` 对应目录。

## 未验证与可选后续

- 物理中文 IME 组合输入；自动输入/粘贴不能替代。
- 实际 VoiceOver 朗读；语义树和原生 AX 已检查，但不能替代读屏。设置弹窗在 CUA AX 中的可见性不稳定。
- iOS GUI 查找关闭、恢复和返回；当前环境未完成模拟器界面验证。
- 连续长会话资源行为；重启后源码选择焦点高亮、物理横向滚轮未独立确认。组件测试与键盘横向移动已有证据。

可选后续为上述平台/辅助功能实机检查，以及单独调查大文档模式切换成本。自动原文件保存/版本归档、渲染器重写、像素级一致性及 iOS 附件导入分享不在本批范围。

## 收尾与复现

上述可用临时测试日志已另存至 `build/local-performance/final-acceptance-20261026/`。临时基线工作区归档被应用拒绝（当前主工作区不能移除），因此保留原目录；证据已独立复制校验，不依赖删除操作。

普通 macOS Profile 构建须沿用仓库 `tool/local_performance.py` 的环境：`CARGO_PROFILE_RELEASE_STRIP=none FLUTTER_XCODE_ARCHS=arm64`。直接缺省构建出现 Rust 过程宏依赖 E0463，清缓存后仍然复现；失败日志保留，不能据此归因于产品源码回退。

最终普通 Profile 构建成功（未启用 IANVS_LOCAL_PERFORMANCE），日志 `build/local-performance/final-acceptance-20261026/ianvs-final-normal-profile-supported-env.log`。通过 computer use 启动后，AX 与截图确认恢复原测试工作区、image-reflow.md 的 Read 界面和图片/中文正文，底栏 Saved locally，且无 Run R4-02 诊断面板。
