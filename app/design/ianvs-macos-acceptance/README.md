# Ianvs Design / macOS 验收记录

日期：2026-09-29。结论：**本次约定的集成、布局及交互检查通过**。

## 实现范围

- 应用依赖已发布的 `ianvs_design: ^0.4.0`，锁定解析版本为 0.4.0；无本机 path override。
- `IanvsTheme.build` 提供深浅色、compact 密度、系统字体及 Material 控件主题；`IanvsTokens` 同步映射到 Markdown 主题，保留独立的文档语义样式。
- 接入 `IanvsToolbar`、`IanvsIconButton`、`IanvsTextField` 和 `IanvsResizeHandle`；模式切换使用 Ianvs 主题下的标准 `SegmentedButton`。
- 保留黑色侧栏、懒加载层级树、搜索索引、收藏、多选和已有文件事务；通用平面 `IanvsSidebar` 没有替代这些业务结构。
- 默认跟随系统外观；View → Toggle Appearance 可暂时覆盖，Use System Appearance 恢复跟随。
- Control-click 打开上下文菜单，Command-click 多选；危险操作分组置底。
- 分栏支持方向键、Home/End、Enter 与双击复位；宽度继续进入会话恢复。
- 文件行、搜索框、工具栏、标签和状态栏适应放大文字。拖动浮标改为鼠标锚点，根目录落点使用轻色背景、边框和明确目的地文字。

## 规范依据与产品选择

参考 Apple 的 [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)、[Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)、[Focus and selection](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection/) 与 [Context menus](https://developer.apple.com/design/human-interface-guidelines/context-menus)。Control-click 的语义及危险操作置底直接采用后者的约定。

52 pt 工具栏、28 pt 文件行、32 pt 通用控件等是应用/Ianvs 的密度选择，不是 Apple 强制尺寸。黑色侧栏是既有产品偏好。应用使用 Flutter 控件与图标；未宣称实现 AppKit 控件、SF Symbols 或 Liquid Glass。系统自定义强调色、窗口失活配色与完整实机 VoiceOver 验证不在本次验收结论内。

## 自动化验收

执行 `bash app/tool/verify_sidebar.sh`（仓库根目录），进程退出码为 0。完整日志：[verification.log](verification.log)。

| 检查 | 结果 |
| --- | --- |
| Dart 格式检查 | 通过 |
| `flutter analyze` | No issues found |
| Flutter 应用测试 | **147 通过，1 跳过，0 失败** |
| 原生文件操作 | 独占创建、Unicode、复制、重名冲突、后代移动拒绝、目录移动、Trash 与恢复通过 |
| `flutter build macos --debug` | 通过，产物位于 `app/build/macos/Build/Products/Debug/Linefold.app` |

跳过项是依赖可选本地 LLM 语料的既有测试。构建日志保留了既有插件的 Swift Package Manager 提醒和 SDK 搜索路径警告；本次构建成功。

交互回归覆盖：子目录文件垂直拖到根标题、拖到根空白区域、拖到根文件行、目录携带未保存后代回到根目录、同目录无操作、失败不破坏文件、搜索与展开状态、多选、Control-click、菜单关闭、模式按钮语义、分栏拖动/键盘/双击、会话宽度恢复及系统外观切换。

## 原始界面证据

这些 PNG 来自实际 Flutter widget 渲染，载入 macOS 系统字体及应用图标字体；采用确定性内存文件夹，未修改用户文档。它们不是原生窗口截屏，不包含 AppKit 交通灯或系统菜单栏。完整桌面捕获保留 Overlay，可见真实菜单及拖动浮标。

| 场景 | 原始截图 |
| --- | --- |
| 接入前浅色基线 | [before-light.png](before-light.png) |
| 最终浅色，1200 × 780 | [desktop-light.png](desktop-light.png) |
| 最终深色，1200 × 780 | [desktop-dark.png](desktop-dark.png) |
| 最小窗口，840 × 560 | [desktop-narrow.png](desktop-narrow.png) |
| 200% 文字，1200 × 780 | [desktop-large-text.png](desktop-large-text.png) |
| 200% 文字，840 × 560 | [desktop-narrow-large-text.png](desktop-narrow-large-text.png) |
| Control-click 菜单 | [desktop-context-menu.png](desktop-context-menu.png) |
| 根目录拖动悬停 | [desktop-root-drop.png](desktop-root-drop.png) |
| 248 pt / 180 pt 侧栏 | [普通](sidebar-normal.png) / [窄侧栏](sidebar-narrow.png) |
| 文件搜索 | [sidebar-search.png](sidebar-search.png) |

逐图检查结果：控件层级与文字对比清晰，活动文件、多选和焦点可区分，深浅色共享语义；最小窗口和 200% 文字没有布局溢出，长文件名保留省略与路径提示，状态栏可增高换行。根目录目标名和拖动文件名同时可读，浮标未从窗口左缘裁切。

## ImageGen 辅助视觉验收

按用户要求，在代码及全量验收完成后使用**内置 ImageGen**，以上述真实截图生成 [视觉验收汇总图](imagegen-review.png)。完整请求见 [imagegen-prompt.md](imagegen-prompt.md)。原始生成文件保留在工具默认生成目录，项目中保存了一份副本。

已对生成图与原图进行对照：总体结构、黑色侧栏、深浅色与根目录目的地得以表达。生成图存在小字、控件细节和比例的重绘差异，只用于展示验收要点；逐像素界面与交互结论以原始 PNG 和测试日志为准。图上的通过结论来自已完成的检查，并非由图像生成工具执行测试得出。
