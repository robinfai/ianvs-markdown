# Linefold 用户体验与 Markdown 功能走查

日期：2026-09-22。对象：当前 macOS 桌面应用及其 Markdown 组件。使用电脑工具实际操作构建出的 Linefold；全部写入和冲突实验使用本目录 `fixtures` 内的样例，没有修改用户原有文档。

## 结论与证据口径

本轮覆盖桌面功能 22 类、Markdown 能力 19 类，修复 9 类问题，已重建并复测实际应用。真实操作、回归测试和源码检查分别记录；“有解析器/有组件测试”不等于桌面功能可用。中文测试使用粘贴，不能据此宣称系统中文输入法组合输入已通过。桌面自动化中偶有点击或画面更新延迟，原生辅助动作、窗口恢复或缩放后才反映实际状态；没有把这类工具现象直接归类为产品冻结。

用户指出的 focus 行高变化已在真实应用复现：普通段落点入后后续内容上移约 6 px，引用点入后字体变大、块高度增加。还发现 YAML 在 Live 意外显示、大纲跳转离开当前模式、新保存文件不出现在目录树、Reload 清除草稿的撤销机会，以及重复内联 HTML 产生红色错误块。保存中的并发输入问题由失败回归确认。

UI 改动之前，subagent 使用内置 ImageGen 完成两轮设计评审。实施约束是保留当前应用外壳、共享编辑与展示排版度量、焦点不增加块尺寸、源码仍可编辑。生成图是设计意图，运行截图及布局断言才是验收证据。

- [第一轮设计评审与完整提示词](/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/audit-2026-09-22/design-review-round-1.md)
- [第二轮设计评审与完整提示词](/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/audit-2026-09-22/design-review-round-2.md)
- [源码及既有测试的逐项清单](/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/audit-2026-09-22/feature-inventory.md)

## 本轮修复记录

| 问题 | 用户影响与复现证据 | 修复内容 | 验证状态 |
| --- | --- | --- | --- |
| focus 改变排版 | 普通段落、标题、列表、引用、代码的字体继承、padding、strut 不一致；点击即带动后文跳动 | 共享有效样式与文本度量；固定 marker 槽位；保留源文和编辑能力 | 107 项几何/边界测试与真实字体复跑通过；新构建中段落、引用、围栏及缩进代码实测位置稳定 |
| Live 意外显示 YAML | `showFrontMatter:false` 下仍把 title/tags 等渲染为正文，Read 正常 | 合法文档头在 Live/Read 隐藏，Source 保留 | 回归通过；新构建确认 Live 隐藏、Source 完整，字数和 Saved 状态未变 |
| 大纲跳转不准确且切模式 | Read 点击远端 Setext 标题会切 Live 并跳到顶部 | 按原始源码位置定位实际块、Source caret 或 Read anchor，保留当前模式 | 6 项新回归通过；新构建 Read/Source 的 Setext、Live 的代码标题实际定位通过 |
| 保存状态与落盘内容不一致 | 保存 A 时继续输入 B，异步结束会误将 B 标成 Saved | 每次保存固定快照；同文档保存串行；dirty 基线对应实际落盘文字 | 9 项新回归通过 |
| Reload 无法撤销 | 外部写盘后点 Reload 丢弃本地草稿，Undo 无效 | Reload 作为单个可撤销编辑，磁盘版本仍为已保存基线 | 2 项新回归通过；实际 Reload→⌘Z 恢复完整中文草稿且为 Edited，Redo 回磁盘版本为 Saved |
| 新保存文件不出现在树中 | File workflow.md 已 Saved，左侧只有原有两份文件；搜索却能找到它 | 保存后刷新工作区目录和搜索，保留展开、滚动与查询状态 | 4 项新回归通过；实际新建并保存 Final verification.md 后立即出现在树中 |
| 重复内联 HTML 红屏 | 一段内两个 `<kbd>` 出现 Duplicate keys | 将每个元素的诊断 key 限定在独立子树，保持样式及点击行为 | 13 项新回归与 13 项既有回归通过；原样例在新构建中显示 Command + B、上下标，不再出现红色错误块 |
| Read 仍可能被快捷键修改 | 完整应用 widget 测试中，9 种键盘动作及 2 种原生菜单回调会修改旧选区；本机 OS 按键走查未独立复现 | 修改动作按当前模式保护，保留选择、复制、保存及 Live/Source 编辑 | 15 项新回归通过，既有保存与应用交互 13 项通过 |
| 保存后的外部变更漏报/误报 | 可控 watcher 回归确认：保存后 0 ms 的不同内容被忽略，600 ms 后的相同内容又误报；保存期间外写也可能被吞 | 去掉时间盲窗；保存队列完成后比对磁盘与 persistedText，过期异步读取重新检查，关闭文档后不再通知 | 9 项新回归通过；连同保存、Reload、工作区共 24 项通过 |

### 修复前的真实截图

普通段落进入编辑态后，下面区块发生位移；引用进入编辑态后字形和行距变化。对比为同一份隔离样例，未修改内容。

![修复前：段落未聚焦](/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/audit-2026-09-22/01-live-baseline.png)

![修复前：段落聚焦](/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/audit-2026-09-22/02-paragraph-focused.png)

![修复前：引用聚焦后字号与块高度变化](/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/audit-2026-09-22/07-quote-focused.png)

![修复前：同段重复 kbd 导致错误块](/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/audit-2026-09-22/18-html-and-headings.png)

## 桌面功能实际覆盖

“实测”指本轮电脑操作；“测试”指自动化回归；“源码”指实现检查；未操作的分支明确保留，不能理解为全部场景均已通过。

| ID | 功能 | 本轮结果与边界 |
| --- | --- | --- |
| A01 | 启动、Welcome | 实测启动与恢复；能恢复上次工作区、标签和正文。首次安装空状态主要由既有测试覆盖。 |
| A02 | 新建 | 实测菜单及 ⌘N，新文档可输入、显示 Edited，撤销回空白恢复 Saved。空白未落盘文件显示 Saved 的措辞值得后续统一。 |
| A03 | 打开文件 | 实测原生对话框打开中文名、空格名和多份样例；Finder 拖入未实测。 |
| A04 | 打开文件夹 | 实测切到隔离工作区、树打开文件；新保存文件刷新缺陷本轮修复。外部新增/改名目录仍没有工作区目录 watcher。 |
| A05 | 搜索文件 | 实测文件名搜索能找到新保存文件；这是文件名搜索，非正文全文搜索。搜索刷新和状态保留有回归。 |
| A06 | 查找与替换 | 桌面未提供文内 Find/Replace，不能用侧栏 Search Files 代替。 |
| A07 | 保存 | 实测原生保存、中文内容、标签改名、Saved 状态；磁盘内容核对。并发输入、连续保存、失败重试、取消由新回归覆盖。 |
| A08 | 另存为 | 实测生成 Saved copy.md，旧文件仍在，新文件包含草稿；另存期间后续保存的路径时序有新回归。 |
| A09 | 关闭标签 | 实测未保存关闭出现三选项，Cancel 保留草稿；新建空白页关闭、跨标签切换可用。其他关闭分支有既有测试，非全部原生分支实测。 |
| A10 | 外部变更 | 实测修改样例磁盘后 banner 出现，本地草稿仍保留；Keep/Reload 无合并能力。Reload 恢复机会本轮修复。 |
| A11 | 会话恢复 | 实测安全退出再启动恢复未保存的表格改动和 Source 模式。正文恢复与视图状态分开：光标、滚动、外观未完整持久化。 |
| A12 | 标签与全部文档 | 实测多文档及全部文档菜单切换；拖动重排及 ⌘1–9 的顺序由 app 既有测试覆盖。超长中文标题及大量标签未穷举。 |
| A13 | Live / Source / Read | 实测切换与源文核对；任务修改、表格编辑均可在 Source 看到对应文字。Read 修改快捷键问题由应用级测试确认并修复，选择复制仍可用。 |
| A14 | 大纲 | 实测复现 Setext 远端跳转缺陷；修复覆盖三模式、同名标题、隐藏 YAML 和大代码块。 |
| A15 | 侧栏与大纲显隐 | 实测左右侧栏隐藏、恢复后正文布局正常；固定宽度，没有拖拽调整入口。最小窗口有 app 测试。 |
| A16 | 亮暗外观 | 实测暗色，文本、代码、表格、HTML 样例可读。外观当前不跨启动保留。 |
| A17 | 剪贴板与撤销 | 实测粘贴、全选、Undo；代码复制到新文档逐字核对。跨块拖选、所有富文本来源、系统 Edit 菜单分支未逐项穷举。 |
| A18 | 格式快捷键 | 组件有粗斜体/链接/缩进等回归；真实桌面 Source 的 ⌘B 本轮未看到修改，不能宣称桌面所有格式键可用。产品也缺少格式入口的说明。 |
| A19 | 状态栏 | 实测字数/字符数、Saved/Edited、UTF-8/LF 随内容变化；words 按空白分词，不是中文语义字数。 |
| A20 | 编码与行尾 | 源码支持严格 UTF-8 读写并显示行尾；没有编码或行尾转换 UI。本轮没有 GBK/BOM/混合行尾的原生打开验收。 |
| A21 | 链接与资源 | 已实测展示及部分点击，详见 Markdown 表中的 M06–M09；宿主回调缺失必须列为功能边界。 |
| A22 | 可访问性 | 使用辅助功能树完成大量操作；不能等同 VoiceOver 验收。完整键盘路径、焦点可见性、标签 selected 语义和紧凑点击目标需后续专项。 |

## Markdown 细节实际覆盖

| ID | 能力 | 本轮结果与边界 |
| --- | --- | --- |
| M01 | 段落、软换行、中英混排、Emoji | 实测显示、粘贴、焦点变化；布局回归增加不同宽度与文本缩放。未进行真实中文 IME 候选组合输入验收。 |
| M02 | H1–H6、Setext、分隔线 | 实测各级显示和大纲；焦点几何纳入回归。产品默认不开启标题折叠按钮，组件折叠能力单列测试。 |
| M03 | 粗体、斜体、删除线、高亮、行内代码 | 实测样例呈现；保留原源码标记揭示规则。点击、选择及编辑边界由现有组件测试与新增焦点回归共同验证。 |
| M04 | 普通、有序、嵌套列表 | 实测不同层级呈现；Enter、Tab、退格、重排数字有组件回归。编辑 marker 与正文的宽度、行高纳入本轮修复。 |
| M05 | 任务列表 | 实测点击后只有目标 `[ ]` 变 `[x]`，Source 核对并 Undo 回基线；聚焦不能改任务状态。任意状态字符由组件测试覆盖。 |
| M06 | 普通、相对、锚点、引用链接 | 实测普通链接展示，Read 的外链点击无有效宿主动作。桌面未传 onTapLink；不能把蓝色文本算作导航已实现。 |
| M07 | Wiki、tag | 实测展示；桌面未接目标解析与导航回调，无法保证笔记/块/标签跳转。 |
| M08 | 图片与尺寸 | 实测本地图片文件存在仍显示 Image blocked；宿主未传 imageBuilder，因此真实图片加载及拖动缩放不可验收。 |
| M09 | 嵌入、Mermaid | 实测 Mermaid 代码回退；Wiki embed 为占位。diagramBuilder/wikiEmbedBuilder 未接入桌面。 |
| M10 | 围栏与缩进代码 | 实测高亮、未知语言按字面显示、复制中文/Emoji/换行。焦点前后字体、代码面板和围栏槽位在本轮调整；caret/选择/IME 用组件回归验证。 |
| M11 | GFM 表格 | 实测单元格 12→18、Tab 移动和 Source 对照；自动规范化会改整表源格式。增删/拖行列及全部键盘边界主要由现有组件测试覆盖。 |
| M12 | 引用与 Callout | 实测引用、嵌套引用、普通/未知 Callout；引用聚焦排版差异本轮修复。Callout 所有折叠与编辑组合未穷举。 |
| M13 | 数学 | 实测行内和块公式，以及无效 TeX 的可见回退。公式进入源码编辑会揭示语法，这和普通文本仅获得 focus 的排版稳定性分开记录。 |
| M14 | 注释、块 ID、脚注 | 实测 Live 弱化 metadata，Read 隐藏注释/块 ID；重复引用、行内脚注和末尾列表可见。脚注真实导航受宿主 onTapLink 接入限制。 |
| M15 | YAML | 实测 Source 原文与 Read 隐藏；Live 错误渲染本轮修复。未闭合 YAML 不能误吞，完整源文保留由回归约束。 |
| M16 | HTML 子集 | 实测 input/checkbox/progress、sup/sub/kbd、details、center。重复内联 HTML 错误本轮修复。details/summary/closing 必须独占行；同一行写法不属于当前支持语法。表单控件状态仅在 view 内，不等于修改 Markdown。 |
| M17 | 选择、复制、粘贴 | 实测 Source 全选、代码复制、表格粘贴；跨块拖选、反向拖选和网页富文本粘贴仍以组件测试为主。 |
| M18 | Undo/Redo、输入组合 | 实测任务、普通粘贴和恢复流程；保存快照与 Reload 新增回归。真实系统 IME 尚未验收。 |
| M19 | 大文档、异常语法 | 实测未闭合 inline/code、无效公式、未知语言的回退；1000 行代码前后大纲定位有回归。大文件持续输入、深层嵌套和资源占用没有性能基准结论。 |

### 其他真实操作证据

![未保存关闭时的三选项](/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/audit-2026-09-22/16-close-unsaved-dialog.png)

![支持语法的 details 展开、center、代码和列表](/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/audit-2026-09-22/20-supported-html.png)

![从代码块复制后粘到新文档，中文、Emoji 和换行完整](/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/audit-2026-09-22/21-code-copy.png)

## 后续优先项

1. 接通桌面链接、相对笔记、Wiki 与脚注导航；统一不可操作资源的说明。图片、嵌入与 Mermaid 应按明确产品范围逐项接入。
2. 增加文内查找/替换和易发现的格式操作；核实桌面原生快捷键路由。
3. 完善工作区外部新增/改名刷新、编码错误反馈、视图状态恢复。
4. 单独执行真实中文 IME、VoiceOver、Finder 拖入、全键盘路径和大文件性能验收。

## 最终构建与复测

| 检查 | 结果 |
| --- | --- |
| 组件全套测试 | 874 / 874 通过 |
| 桌面应用全套测试 | 53 / 53 通过 |
| 示例应用全套测试 | 5 / 5 通过 |
| macOS 真实 SF / SF Mono / CJK 字体复跑 | 107 / 107 通过；这是组件几何测试的额外配置复跑，不与上面的数量混算 |
| 根目录、app、example 静态分析 | 全部无问题 |
| Dart 格式检查 | 118 个文件，0 个待格式化 |
| git diff --check | 通过 |
| macOS debug 构建 | 成功，已启动新构建完成上述真实复测 |

构建仍提示两个既有原生依赖尚未采用 Swift Package Manager；本轮构建成功，没有修改依赖管理方式。

[焦点测试的根因、精确断言和覆盖范围](/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/audit-2026-09-22/focus-geometry-verification.md) · [检查结果摘录](/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/audit-2026-09-22/validation.txt)

普通正文仅获得焦点时，行高、基线、块高与后文位置稳定。主动进入标记、链接 URL 或公式的源码编辑时，保留完整语法展开；其额外文字仍可能换行。这一边界不应被误读为任意源码修改都保持块高不变。

### 新构建的真实截图

以下截图直接来自运行中的 Linefold，没有用 ImageGen 替代运行证据。段落前后两张、代码前后两张分别使用同一窗口尺寸。

![修复后：普通段落未聚焦](/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/audit-2026-09-22/22-fixed-idle.png)

![修复后：段落聚焦，后续内容位置不变](/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/audit-2026-09-22/23-fixed-paragraph-focus.png)

![修复后：引用维持原字号与行距](/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/audit-2026-09-22/24-fixed-quote-focus.png)

![修复后：代码未聚焦](/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/audit-2026-09-22/28-fixed-code-idle.png)

![修复后：围栏可编辑但代码和表格位置稳定](/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/audit-2026-09-22/29-fixed-code-focus.png)

![修复后：Read 保持模式并找到 Setext 标题](/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/audit-2026-09-22/25-fixed-read-outline.png)

![修复后：重复 HTML 元素正常呈现](/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/audit-2026-09-22/31-fixed-inline-html.png)

![修复后：新保存文件立即出现在树中](/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/audit-2026-09-22/32-fixed-save-tree.png)

![修复后：Reload 后一次撤销恢复本地草稿](/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/audit-2026-09-22/33-fixed-reload-undo.png)
