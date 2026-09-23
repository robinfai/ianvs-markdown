# 验证记录

日期：2026-09-22。所有命令在当前工作树运行，包含任务开始前已有的修改；测试总数不是本轮新增数量。

| 检查 | 执行位置 / 命令 | 最终结果 | 日志 |
| --- | --- | --- | --- |
| Markdown 全套 | 仓库根目录：flutter test --reporter compact | 876 passed | [library-tests-complete.log](library-tests-complete.log) |
| 桌面全套 | app：flutter test --reporter compact | 56 passed | [app-tests-complete.log](app-tests-complete.log) |
| 示例集成 | example：flutter test --reporter compact | 5 passed | [example-tests-final.log](example-tests-final.log) |
| 静态分析 | 仓库根目录：flutter analyze | No issues found | [analyze-final.log](analyze-final.log) |
| macOS 构建 | app：flutter build macos --debug | 成功生成 Linefold.app | [macos-build-final.log](macos-build-final.log) |

总计 937 个测试通过。构建提示现有 irondash_engine_context 和 super_native_extensions 尚未支持 Swift Package Manager；当前构建成功，本轮没有更换依赖或构建系统。

## 本轮新增的回归检查

- app/test/editor_affordances_test.dart：模式名称、button/selected/tap 语义和最低高度；空文档提示不进入内容与保存；中英文文件名及窗口收窄时当前标签可见。
- test/theme_rebuild_test.dart：连续切换主题保留普通/重复标题和自定义任务状态；图片源索引在主题变化后仍对应原图片。
- 主题问题的两项测试在修复前均失败，修复后通过。见 [修复前](theme-regression-before.log) 与 [修复后](theme-regression-after.log)。
- 既有 app/test/widget_test.dart 的 tooltip 查找更新为新的解释文案。

主题测试的两个多余 import 在完整套件运行后移除，随后静态分析重新通过；不涉及行为变更。

## 真实设备验证

实际使用电脑工具控制 macOS Linefold，经过原生目录/保存对话框、工作区树、搜索、模式按钮、菜单、编辑区、任务、表格和大纲。主要证据及步骤见 [体验报告](audit.md) 和 [功能矩阵](feature-matrix.md)。

CRLF 检查还读取了 UI 保存后的磁盘字节：[结果](crlf-validation.txt)。实际保存内容包含中文和 emoji，3 处 CRLF 保留，孤立 LF 为 0。

界面调整完成后通过 Flutter 热重载运行复验，并完成最终 macOS debug 构建。最终应用保持打开，显示本轮体验样本。

## 本轮修改边界

产品修改集中于：

- app/lib/src/widgets/title_tabs_bar.dart
- app/lib/src/widgets/editor_shell.dart
- lib/src/editor/source_editor.dart
- lib/src/editor/live_editor.dart 的 placeholder 参数及空内容呈现
- lib/src/ianvs_markdown.dart 的重复解析索引
- README.md、app/README.md 的当前产品描述

上面某些文件在任务开始前已有其他改动。本轮没有回退这些改动，也没有将工作区完整 diff 全部归为本轮成果。

## 尚未验证的范围

- 没有把 937 个自动测试描述为 937 次人工操作。
- 未进行真实中文输入法候选/组合过程、完整 VoiceOver、跨平台、真实 Finder 拖放、所有表格拖拽落点以及跨第三方富文本应用的剪贴板往返。
- 未进行极大文档性能基准、断电/文件系统故障实验、远端图片加载或真实 Mermaid 集成。后三类中的图片和 Mermaid 当前桌面宿主还未接入。
- 没有做完整浏览器 HTML 兼容、全 Markdown 方言兼容或无障碍合规认证。
- 01 / 02 截图因初始锁屏阶段画面陈旧，不用于运行结论。AI 生成设计图不属于功能验收证据。

中间测试日志保留用于定位过程；上表指向最终通过的日志。
