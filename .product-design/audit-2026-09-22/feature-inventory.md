# Linefold 功能覆盖清单（代码与现有测试审查）

日期：2026-09-22。范围：`app/lib`、README、`lib/src`、`app/test`、组件测试。

**证据边界：下方两张功能矩阵保留修复前的基线代码检查；“已接入”表示代码路径存在，“测试覆盖”表示当时已有测试定义。候选问题章节附有后续修复与回归记录。最新真实走查、最终测试结果和剩余边界见 [完整体验报告](/Users/robinfai/flutter_projects/ianvs-markdown/.product-design/audit-2026-09-22/audit.md)。** 未接入的组件能力列作产品边界，不自动扩大成本轮新增功能。

## 桌面功能矩阵

| ID | 用户目标 / 入口 | 当前代码状态 | 实际走查重点 |
|---|---|---|---|
| A01 | 启动 / Welcome | 首次生成 Welcome.md；恢复上次 workspace 后才展示编辑器 | 首次与恢复路径、加载时反馈；Welcome 显示 Saved 但尚未有磁盘路径 |
| A02 | 新建 / 标签栏 +、File、⌘N / Ctrl+N | 新建空白 Untitled-N.md 并激活；最后一页关闭后自动补空白页 | 标题、焦点、直接输入、关闭最后页是否符合预期 |
| A03 | 打开文件 / File Open、⌘O、拖入编辑区 | 多选；`.md/.markdown/.mdown/.mkd/.txt`；重复路径激活已有页 | 多文件顺序、重复打开、中文/空格路径；其他类型拖入会被静默忽略 |
| A04 | 打开文件夹 / 侧栏图标、File、⌘⇧O | 一个工作区；懒加载目录；文件夹优先排序；隐藏点开头的目录 | 子目录展开、深层文件、空目录、权限失败；目录新增后的刷新 |
| A05 | 搜索文件 / Search Files | 180 ms 防抖；递归文件名子串搜索；不区分大小写；最多 200 条 | 是文件名搜索，非正文全文搜索；清空/无结果/重复文件名/快速连续输入 |
| A06 | 文内查找 / ⌘F、替换 | 未找到 Find / Replace UI 或快捷键接入 | 记录当前能力边界，不将“文件名搜索”误报为全文搜索 |
| A07 | 保存 / File Save、⌘S / Ctrl+S | 新文件用原生保存对话框；UTF-8；临时文件后 rename；取消不关页 | 保存中继续输入、取消、权限错误、同名覆盖、Saved/Edited 是否准确 |
| A08 | 另存为 / File Save As、⌘⇧S | 选择新路径；更新当前标签名称与 watcher | 旧文件保留；取消无修改；另存为已经在另一个标签打开的路径 |
| A09 | 关闭文件 / 标签 ×、File、⌘W | dirty 时 Save / Don’t Save / Cancel；Save 取消保留标签 | 三个分支；磁盘写入失败是否向用户报告；键盘和按钮行为一致 |
| A10 | 外部变更 / 顶部 Banner | 目录 watcher 精确匹配路径；提供 Keep My Changes / Reload | 本地 dirty 时 Reload 是否丢修改；删除/重命名；保存后紧接外部写入 |
| A11 | 恢复 / 重启应用 | 350 ms 防抖快照；保存全文和 persistedText；恢复 clean 时读磁盘，dirty 冲突保留草稿 | 未保存草稿、原文件丢失、变更冲突；刚输入后立即退出；光标/滚动/外观 |
| A12 | 标签 / 单击、拖动、全部文档菜单、⌘1–9 | 可重排；数字快捷键跟随可见顺序；长列表自动将选中标签滚入视口 | 多页切换保留内容/模式/选区；拖动后快捷键；长中文文件名；dirty 点与关闭钮 |
| A13 | 三种模式 / 顶部 Live、Source、Read；View | 每文档独立模式；数字快捷键用于标签；组件 ⌘E 也被一并关闭 | 跨模式文本不变；Read 是否真正不可编辑；焦点回到文本；切换时滚动稳定 |
| A14 | 大纲 / 右上角图标、右侧标题列表 | ATX / Setext 标题解析；选中项按 controller 光标位置计算 | 点击会强制切 Live；滚动按字符占比估算，含大量代码/长行的文档跳转需实测 |
| A15 | 侧栏、大纲显隐 / 工具栏、View | 保存到 workspace 快照；侧栏还绑定 ⌘Ctrl+S / Ctrl+B | 最小窗口下正文宽度、键盘焦点；左右 pane 固定宽度，无拖拽调整入口 |
| A16 | 外观 / View Toggle Appearance | 亮 / 暗切换；当前 `_dark` 仅驻留组件内 | 重启后回亮色；窗口背景、选择、焦点、表格和代码等的暗色对比度 |
| A17 | 编辑 / Edit 菜单、剪切复制粘贴全选撤销 | 菜单转发 Actions；undo 根据焦点位于 editor 与否路由 | 搜索输入框里的 Undo 不应撤销正文；Read 菜单动作、跨块选择与富文本剪贴板 |
| A18 | 格式 / ⌘B、⌘I、⌘K、⌘D、Tab | 组件格式快捷键已接入；产品隐藏组件格式工具栏，Edit 菜单没有格式命令 | 新用户发现性；选区/词内切换；⌘D 删除物理行；Mac Ctrl+B/F 等原生命令冲突 |
| A19 | 状态栏 / 底部 | whitespace 分词、Unicode rune 字符数、Saved/Edited、UTF-8、LF/CRLF | 中文字数解释；空白和 Markdown 标记是否计入；保存期间状态是否失真 |
| A20 | 文件编码 / 打开与保存 | 严格 UTF-8，非 UTF-8 打开抛错；行尾仅展示并按文本保存 | BOM、CRLF、混合换行、GBK 错误可读性；无编码/行尾转换 UI |
| A21 | 标签/双链/链接/图片 | package 有解析与呈现，桌面未传宿主回调 | 见 M06–M09；避免将组件测试当成产品功能通过 |
| A22 | 可访问性 / 键盘与 VoiceOver | 目录项有 button、expanded/selected 语义；模式按钮有 selected；图标有 tooltip | 键盘完整遍历、焦点可见；当前标签/大纲缺少明确 selected 语义；26–28 px 点击目标 |

## Markdown 细节矩阵

| ID | 内容或交互 | 已接入 / 边界 | 建议实际验证 |
|---|---|---|---|
| M01 | 段落、软换行、空行、中文/Emoji | Live 块级源码与非活动渲染；默认保留软换行；活动空格精确保留 | **点入/点出后行高、相邻块 y 坐标、baseline 不跳；** 长行自动换行；中文输入法连续输入及候选确认 |
| M02 | H1–H6、Setext、分隔线 | 保留标题层级；按源码编辑；标题折叠是组件可选项，但产品默认关闭 | 各标题焦点前后字体/行高；ATX 前缀显隐、空标题、Setext 两行；分隔线点中再 Undo |
| M03 | 粗体、斜体、删除线、代码、高亮 | 隐藏/揭示 delimiters；精确源码映射；双击选择规则已有大量测试 | 字符级点击、双击、三击；emoji 邻接、跨软换行、多重嵌套；标记显隐不能挤动非活动行 |
| M04 | 有序/无序/嵌套/松散列表 | 单列表项编辑；28 px 层级步进；Enter 续写/空项退出；Tab 缩进，数字重排 | 点击每层焦点前后高度；续写、退格合并、Shift+Tab；列表中 quote/code 与空行 |
| M05 | 任务列表 | 任意单字符状态可见；已勾选/自定义状态；checkbox 原位改源；键盘 Space/Return | 点击复选框不丢 caret；仅目标项变化；撤销；新项变 `[ ]`；Read 中是否意外可更改 |
| M06 | 普通 URL / Markdown 链接 / 引用链接 | 解析 full/collapsed/shortcut、title、转义与括号；`onTapLink` 产品未接 | Live 普通链接点入源码属设计行为；Read 外链、相对 `.md`、`#Heading` 的打开行为须实测 |
| M07 | Wiki links、层级 tag | 解析别名、标题/块链接、Unicode tag；缺失目标解析回调也未接 | `[[Note]]`、`[[#Heading]]`、`#project/flutter` 点按可能无动作，默认外观不能证明目标存在 |
| M08 | 图片及尺寸 | 组件支持 Markdown / Wiki 尺寸与拖拽调整；产品 imageBuilder 未接 | 当前默认 `Image blocked · local/host`；本地/远程图片不加载；无真实图片便无缩放操作 |
| M09 | 笔记/标题/块嵌入、Mermaid | 未注入 wikiEmbedBuilder / diagramBuilder | 嵌入安全占位；Mermaid 显示代码回退，非图；应明确作为产品边界 |
| M10 | fenced / indented code | 代码语法色、点阵框、语言/复制、四列 Tab、长行折行、活动行轨道 | focus 前后行高；首末 fence；多行选区；Tab/退格；复制精确内容；未知语言与空代码块 |
| M11 | GFM 表格 | 单元格直接编辑；默认整表 normalize；Tab/Shift+Tab/方向键；增行增列与拖动 | 单击 caret 位置；末格 Tab/Enter；行列拖动不丢内容和 align；source→Live roundtrip；横向空间和中文 |
| M12 | 引用与 Callout | 引用轨道；Callout 类型、+/− 折叠；只箭头切折叠 | 进入编辑时 quote marker 与卡片尺寸变化；折叠后只变化内容；嵌套、未知类型、空正文 |
| M13 | 数学 | Flutter TeX 默认可用；inline/display；invalid TeX 可见回退 | 行内公式与文字 baseline；焦点揭示源码；块公式编辑后双区高度；无效表达式 |
| M14 | 注释、块 ID、脚注 | Live 保留弱化 metadata；Read 注释/ID 隐藏、脚注编号与末尾区 | 不污染代码；重复引用和 backlink；产品 `onTapLink` 未接时脚注导航要核实 |
| M15 | YAML front matter | parse 但 Live/Read 默认隐藏；产品显式 `showFrontMatter:false` | Source 可见且可编辑；切模式不丢 YAML；不要把组件完整属性卡的可编辑能力说成桌面已提供 |
| M16 | HTML 子集 | `<details>`、表单控件、列表/表格/引用等由安全本地 widgets 呈现 | `<details>` 展开；checkbox/input/select 的状态是 view-local，不代表源码/磁盘被更新；重建后恢复行为 |
| M17 | 跨块选择、复制粘贴 | Cmd+A 整文；原始 Markdown + 过滤 HTML；鼠标跨块；选中文字贴 URL 转链接 | 正反向 drag、滚动跨块、读取态 copy、粘回 Source；代码/表格/HTML 混合选择 |
| M18 | 撤销/重做与输入组合 | document history、coalescing；表格/任务/结构操作独立历史项 | 连续输入、切 tab、切模式再 Undo；IME composition 不重复提交；Reload 清历史风险单列 |
| M19 | 大文档 / 异常 Markdown | render budget 与有界纯文本回退；Live 虚拟化 | 大段 text、深层嵌套、超长行不冻结；回退可读；UI 应报告边界而不假装内容齐全 |

## 高价值问题候选（均为代码证据，尚非 UI 复现）

### C01 — 保存期间输入可能被错误标成 Saved（优先）

**后续状态：已用失败回归确认并修复（2026-09-22）。** 本项以下文字保留初次审查证据；现实现对每次保存固定文本快照，以实际落盘内容作为 dirty / 恢复基线，并串行执行同一文档的保存与另存。快捷键和组件工具栏均使用快照标记保存，不清除保存期间新输入的 dirty 状态。Undo 到实际保存快照时恢复 clean。

- 新增 `app/test/save_race_test.dart`：修复前 9 例中的 5 例失败，修复后 9 例全通过；覆盖连续保存、另存后的普通保存、失败重试、取消、选择保留、恢复快照、Undo/Redo，以及快捷键/工具栏入口。
- 验证：完整 app 测试 17 例、原有 controller 测试 98 例、既有 Command+S 交互测试 3 例通过；6 个修改文件静态分析无问题。

- `app/lib/src/controllers/workspace_controller.dart:205` 在 await 写盘前取 `controller.text`，写盘后调用 `document.markSaved()`；`app/lib/src/models/document_session.dart:70` 又以最新 `controller.text` 作为 persistedText。
- `lib/src/editor/editor_shortcuts.dart:191` 在异步保存回调完成后也再次 `controller.markSaved()`。
- 如果保存期间文字 A→B，磁盘写的是 A，完成时却可能把 B 标成已保存；之后关标签或恢复会将 B 视作 clean。风险比单纯状态提示错误高。
- 最小验证：带延迟的测试 file service 启动 save(A)，完成前输入 B，完成后应 dirty=true、persistedText=A。产品走查可使用较慢存储，但不应把难以复现当成不存在。

### C02 — Reload 无保护地丢弃本地改动及 Undo（优先）

**后续状态：主代理已在真实应用复现并修复。** Reload 保留为单个历史操作；`app/test/reload_recovery_test.dart` 两例先失败后通过，新构建实际 Reload→Undo 恢复完整草稿且为 Edited，Redo 回到磁盘文本且为 Saved。以下保留初次检查证据。

- Banner 在 `app/lib/src/widgets/editor_shell.dart:312` 直接调用 reload；controller `reloadFromDisk` 没查 dirty；`DocumentSession.replaceFromDisk` 会 `clearHistory()`。
- 最小走查：隔离样例先本地输入未保存内容，再外部改盘，点 Reload，尝试 Undo。预期应有明确放弃确认，或保留可恢复的本地版本。
- 同时核验 Keep My Changes 只是关 banner，下一次 Save 覆盖磁盘，没有合并能力；这属于当前能力边界。

### C03 — Read 模式可能仍响应修改快捷键（优先）

**后续状态：已在完整 `LinefoldApp` 配置的 widget 回归中确认并修复（2026-09-22），不能等同于真实 macOS 键盘走查复现。** 主代理真实应用键盘走查未复现同一行为；以下失败证据来自 macOS 平台变体的 app widget 事件路由，保留证据层级差异。

- 实际渲染 Live、聚焦文本框并保留有效选区，再点 Read 和另一阅读段落。修复前 Cmd+B/I/K/D、Tab/Shift+Tab、URL 粘贴、Undo/Redo 共 9 个回归改动旧 Live 选区；Cmd+X 没有改文。原生 Undo/Redo 菜单实际回调另 2 个回归也失败。
- 最小修复为 `editor_shortcuts.dart` 执行动作时检查当前 mode；格式/删除/缩进/智能粘贴/历史操作在 Read 不修改源文，Tab/Shift+Tab 使用焦点导航，词级选择委托阅读选择动作。异步 clipboard 返回时也重新检查 mode。`desktop_menu_bar.dart` 的原生 Undo/Redo 同样保护阅读正文；搜索框自己的原生 Undo 路由保留。
- 独立 `app/test/read_mode_shortcuts_test.dart` 15 例通过：上述保护、Read 全选复制与鼠标跨块复制、回到 Live/Source 的格式及 Undo。既有保存快照与 app widget 相关测试 13 例通过；没有运行 root 完整测试。
- 复制边界：全文 Cmd+A/C 保留原 Markdown；当前含中间代码块的鼠标跨块选区能复制可用纯文本，未把本例当作保留富文本格式的证据。

- `lib/src/editor/live_editor.dart:3418` 的快捷键层包围全部模式；`editor_shortcuts.dart` 的 Bold/Italic/Link/DeleteLine/Indent action 无 mode guard。
- 最小走查：Live 留有效光标/选区→切 Read→点阅读正文→⌘B / ⌘D→切 Source 比较字节和 dirty。读模式选区可能没有同步到 controller，若动作生效还可能修改旧位置。
- 非所有阅读交互都应禁止：选择、复制、链接与折叠仍是合理阅读功能。

### C04 — 当前文件夹中新保存的文件可能不显示

**后续状态：主代理真实应用已复现，保存后的自动刷新已修复（2026-09-22）。** 保存/另存成功后以工作区目录版本通知侧栏重读目录和当前文件名查询，刷新期间保留原目录子树；切入搜索后目录展开与滚动状态也继续保留。

- 新增 `app/test/workspace_tree_refresh_test.dart`：先复现已保存的 `File workflow.md` 不出现，再修复；4 例覆盖新文件、已展开目录内另存、当前搜索同步以及树滚动位置，全部通过。原有工作区/侧栏/保存相关 17 例通过，针对改动的静态检查无问题。
- 本次范围是本应用成功保存触发的刷新；未扩展成递归外部目录 watcher，Finder 的外部新增/重命名自动刷新仍未建立。

- `app/lib/src/widgets/workspace_sidebar.dart:344` 将目录列表保存在 `late final Future`，没有目录 watcher、手动刷新或 save 后 invalidation。
- 最小走查：打开文件夹→新建→存入该文件夹→观察树；也在 Finder 新增/重命名一份样例。搜索每次新请求会再读目录，所以树和搜索可能互相矛盾。

### C05 — 大纲跳转估算位置且强制离开 Read / Source

**后续状态：已由主代理真实应用复现，并在两轮 ImageGen 设计评审完成后修复（2026-09-22）。** 保留以下初次审查证据。现通过原始 Markdown offset 请求导航：Live 定位实际虚拟块并对可见块范围二分校准，Source 使用实际 caret 几何，Read 复用标题 anchor；三种模式均保持不变，必要时展开折叠祖先。隐藏 YAML 和同名标题不会改变目标身份，重复点击当前选中标题仍可重新导航。

- 新增 `app/test/outline_navigation_test.dart`：5 个原始回归先全部失败、修复后全部通过；增加含 1000 行代码块的定位边界后 6 例全通过。
- 6 例覆盖 Live/Source/Read 的远端 Setext、重复标题、front matter 原始偏移、重复点击、Live/Read 两层折叠祖先、文本与 dirty/undo 不变。原有组件大纲与折叠的 3 个回归通过，6 个修改文件分析无问题。

- `app/lib/src/widgets/floating_outline.dart:111` 设 Live 模式与 controller selection，再按字符偏移比例乘最大滚动距离。
- 最小走查：一篇前段包含极长代码行或很多短表格行的样例；在 Read 点击中后段标题，观察是否真的进入目标及是否保持模式。
- 组件内部有针对虚拟块的精确导航实现与测试，但桌面大纲没有复用它。

### C06 — 部分明显可点内容没有产品动作

- `app/lib/src/widgets/editor_shell.dart:172` 只传 editor 保存回调，未传 link/image/wiki/diagram host callbacks。
- 最小走查：Read 点击一个 HTTPS 链接、相对笔记、Wiki、tag、脚注；图片观察明确占位。分别记录“编辑行为”“无动作”“未提供”，不要只凭蓝色/下划线认定可用。

### C07 — 恢复不包含全部视图状态

- `app/lib/src/models/document_session.dart:58` 快照无 selection/scroll；`app/lib/src/app.dart:25` 外观默认 false 不持久化；仅正文、路径、mode 等被保存。
- 最小走查：长文滚到底部留 caret，切暗色，等待 >350 ms 后安全重启；比较光标、滚动、外观。文档内容恢复与视图状态恢复分开判定。

### C08 — 保存外部变更通知的 600 ms 盲窗

**后续状态：已用可控 file service/watcher 与假时钟确认并修复（2026-09-22）。** 保存结束后不推进时钟立即外写不同内容，原实现 `hasExternalChanges` 仍为 false；保存期间外写和保存后删除也漏报。相反，晚于 600 ms 的自身事件即使磁盘仍等于落盘快照也会误报。以下保留初次审查证据。

- 修复移除基于时间的路径屏蔽。事件处理等待该文档保存队列结算后，读取磁盘并与 `persistedText` 比较；不与正在编辑的文字比较。删除/不可读继续使用已有外部变更提示，保存失败不吞事件。
- 异步读取被更新的保存/Reload 快照取代时重读；已关闭或换路径的文档不接收旧读取结果。未新增 UI，也未扩展为目录/文件移动监视重构。
- `app/test/file_watcher_save_test.dart` 9 例覆盖即时外写、自身延迟事件与未保存输入、保存期间外写、删除、Save As 新旧路径、失败、排队保存、过期读取、关闭生命周期；原保存快照/Reload/工作区测试一起共 24 例通过。2 个修改文件分析无问题。
- 证据范围为控制器与受控文件事件；macOS 原生事件合并、原子重命名的完整投递行为仍不能仅由这些测试证明。

- controller `saveDocument` 在 finally 后 600 ms 才移除 `_savingPaths`，watcher 在集合期间忽略整个路径，而非仅忽略内容相同的自写入事件。
- 最小验证：保存完成后 600 ms 内外部写入不同内容，用户应仍得到冲突提示。文件 watcher 的事件合并和原子替换也需要实际 macOS 验证。

### C09 — 同段重复内联 HTML 触发红屏（真实应用复现，已修复）

- 主代理在 `fixtures/More-markdown.md` 的 `<kbd>Command</kbd> + <kbd>B</kbd>` 实际观察到红屏，截图 `18-html-and-headings.png`；该项来自 UI 证据，而非最初的代码候选。
- `obsidian_html.dart` 和 `inline_code.dart` 将同类内联控件的静态诊断 key 放在 `Wrap` 的直接子控件上；同段重复时违反兄弟 key 唯一性。失败回归确认 kbd、sup、sub、strong、em、s、small、q、abbr、mark、span、code 共 12 类受影响。
- 最小修复以无 key 的非布局根节点隔离每次出现的诊断 key，保留现有控件 key、手势、样式与布局。`test/repeated_inline_html_test.dart` 使用同类型、同文本重复元素，在 Live、Read、Source 三种模式及两处点击验证显示、内容和 dirty/undo；12 类与 underline 对照共 13 例通过。
- 既有 HTML 点击/阅读回归 13 例通过，修改文件静态检查无问题。真实应用复测由主代理负责；此处不把组件回归表述为 UI 复测。

## 推荐主代理走查顺序

1. 使用一份隔离审查样例，包含中文/Emoji、所有标题、普通段落、软换行、粗斜体、普通与任务列表、quote/Callout、代码、表格、公式、链接/图片、脚注和 YAML。先存盘保留基线。
2. **优先固定视口拍 before/after**：逐一点击普通多行段落、列表、标题、代码、表格，再点击另一块；记录相邻行和下一块的位置；内容没改时不应仅因 focus 改变普通行高。
3. 在 Live 输入与删改，覆盖中文 IME、Enter/Backspace、Tab/Shift+Tab，随后 Source 对照原始 Markdown，Undo 回基线。
4. 单独复现 C03：Read 的修改快捷键；只在隔离样例验证，避免改变用户文档。
5. 文件流程：新建→取消保存→保存→改动→另存→三个关闭选项；标签拖动及 ⌘1–9。
6. 文件夹流程：展开/搜索/清空/深层打开；保存新文件到当前目录观察刷新（C04）。
7. 阅读流程：跨块选择复制、链接/图片/嵌入/脚注真实表现、代码复制、表格与 HTML 本地状态。
8. 大纲与视图：Read/Source 跳中远端标题、两个 pane 隐显、最小窗口、暗色、仅键盘遍历。
9. 在隔离文件核验外部修改：clean/dirty 两种状态的提示、Keep / Reload；C02 先备份样例；不把缺失合并能力扩张成本轮大型新特性。
10. 最后安全重启验证恢复；记录关闭前的内容与视图状态，分开判定 C07。

## 现有测试覆盖与缺口

- `app/test/workspace_controller_test.dart`：打开/保存/重排/会话，clean 文件恢复读盘，dirty 恢复冲突，丢失文件的未保存草稿保留。
- `app/test/widget_test.dart`：⌘数字标签及拖动后顺序、最小窗口菜单/关闭保存、聚合 shell、树直接显示。
- `test/live_editor_test.dart` / `editor_controller_test.dart` / `ianvs_markdown_test.dart`：大量语法边界、源码 offsets、selection、键盘、code/table/task/HTML/metadata/clipboard 用例；只能证明组件的对应配置路径。
- 候选缺口：保存期间内容变化，Read 修改快捷键，本地 dirty 的 Reload，已展开树刷新，app 大纲远距离跳转，真实磁盘 watcher 时序、原生 Finder drop/对话框、中文输入法、系统可访问性及全应用重启。应优先针对实际改动添加必要回归，避免重复语法层测试。
