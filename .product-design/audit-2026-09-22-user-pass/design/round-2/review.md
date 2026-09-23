# 第二轮设计评审 — 收敛结论

本轮完成在产品 UI 修改之前。仅生成设计产物、审查第一轮建议和相关源码；未编辑产品代码、未操作电脑 UI、未运行 VoiceOver。生成图是方案说明，不能证明交互或辅助功能已实现。

## 结论

**通过三个最小改动：模式控件语义与说明、标签真实字宽测量、Source 空文档轻量提示。** 保持现有布局、颜色和图标体系。Live/Read 空白态本轮不直接批准实现，须先完成当前运行态体验；具体条件见下表。

| 第一轮提案 | 第二轮决定 | 依据与边界 |
| --- | --- | --- |
| Live / Source / Read 明确按钮语义、解释性 tooltip、28 点最低命中高度 | **通过** | 主流程本轮 AX 核验读出文字及无 label 按钮；源码仅有 selected，tooltip 为短名称，11 点文字加上下各 4 点 padding，没有 28 点约束。保留三个可见短标签，不扩大 44 点工具栏。 |
| 用 TextPainter 计算中英文标签宽度 | **通过** | `_tabWidth` 使用 `runes.length * 7 + 42`，没有考虑字体、CJK、emoji 与文本缩放。修正测量算法有明确代码依据，但不把旧截图的省略认定为当前运行缺陷。保留 92–220 点范围及已存在的完整路径 tooltip。 |
| Source 空文档加入轻量 placeholder | **通过** | 新鲜 `04-empty-source.png` 确实没有写作提示；`source_editor.dart` 的 TextField decoration 没有 hint。只在内容为空时出现，不写入 controller，不改变保存内容。 |
| Live 空文档加入提示 | **条件通过，尚不进入实施范围** | parser 对空串返回一个零长度 paragraph；非活动空块渲染为 SizedBox.shrink，外层保留至少 24 点可点击区域；活动块 TextField 也没有 hint。源码说明了可能的改善位置，但本轮没有新鲜 Live 空白态截图与点击/输入证据。若主流程复核需要补充，必须同时处理活动/非活动状态，且只针对整份文档严格为空，不针对文中的每个空段。 |
| Read 空文档加入提示 | **暂缓** | Read 使用 IanvsMarkdownView，模式定义明确为只读。先体验是否造成理解问题；即便补充，只能是 `Empty document` 类只读说明，不能出现写作提示、光标或新增编辑入口。 |

## 证据与图片

- 规范：`app/DESIGN.md`，其中 44 点 toolbar、32 点 tab、224 点 inspector、28 点 action target 都是本产品约定，不宣称来自 Apple 强制要求。
- 代码：`app/lib/src/widgets/title_tabs_bar.dart`、`lib/src/editor/source_editor.dart`、`lib/src/editor/live_editor.dart`、`lib/src/editor/editor_models.dart`。
- 主参考：`../../screenshots/04-empty-source.png`，已用 view_image 查看。
- 辅助参考：`../round-1/mockup.png`，已用 view_image 查看。它是方案图，不能当成真实运行截图。
- 第一轮 `01-initial.png` 未用于本轮生成或尺寸判断。
- 收敛稿：[`mockup.png`](mockup.png)。
- 完整提示词：[`prompt.md`](prompt.md)。
- 使用内置 `image_gen`，没有使用 CLI fallback。原图保留在：
  `/Users/robinfai/.codex/generated_images/01a0c7c1-0f5a-7513-ad1c-f7df5e359cc0/exec-a93f4d48-7776-43d2-83ca-c3110a7f55d8.png`。
- 已复制到本工作区 `design/round-2/mockup.png`。

## 可直接实施的最小代码建议

### 1. 模式控件：只修语义、解释和最低高度

位置：`title_tabs_bar.dart` 的 `_EditorModePicker`，原约 307–373 行。

1. 保持可见文字 `Live`、`Source`、`Read`。tooltip/辅助功能名称可分别为：
   - `Live Preview — edit with inline formatting`
   - `Source — edit Markdown source`
   - `Read — preview without editing`
2. 每段提供一个明确的语义节点：`button: true`、`selected: selected == mode`、完整 `label` 和 `onTap`。保留现有 InkWell 点击与键盘激活。
3. 若采用父 Semantics + ExcludeSemantics 的方式，父节点必须恢复 `onTap`，避免只剩标签却无法辅助技术激活。排除子 Text/InkWell/Tooltip 的重复语义，避免完整名称与短文字重复播报；tooltip 可以使用 `excludeFromSemantics: true`。
4. 在现有段内加入 `BoxConstraints(minHeight: 28)`，保留水平 10 点 padding、字号、选中背景和 4 点圆角。目标大小与 glyph 大小分开，不放大其他已是 28 点的图标按钮。
5. 外层 2 点 padding 后总高约 32 点，仍在 44 点工具栏内。已有焦点样式不作无证据的重绘。

### 2. 标签：测量与选中滚入视口共用宽度

位置：`title_tabs_bar.dart` 的 `_tabWidth`、`_revealSelection`、`_DocumentTab.build`，原约 132、161、233 行。

1. 用 TextPainter 测量真实渲染的文件名。TextStyle 应与 Text 一致：解析 DefaultTextStyle 后合并 12 点、w400；传入同一 Directionality、MediaQuery.textScalerOf(context) 和 locale，单行 layout。
2. 将测得宽度向上取整，再加原有约 42 点 chrome 预算，并继续 clamp 到 92–220。42 点覆盖左右 12 点 padding、28 点关闭目标及现有少量余量；不要依据生成图的视觉宽度硬编码某个文件名。
3. 宽度函数或本次 build 的宽度列表必须同时供标签构建与 `_revealSelection` 使用。若重排、重命名、字体或文本缩放变化，重新测量并在布局后重新 reveal，避免显示宽度和滚动偏移不同步。
4. 保留现有完整路径 tooltip、ellipsis、重排、水平滚动、关闭和 dirty 语义。可将 dirty 圆点放入固定 28 点尾部槽位，使 hover/选中切换时文本可用宽度稳定；这是同一布局问题的附带收敛，不需要新视觉元素。
5. 不提高全部标签的固定最小宽度，不修改最大宽度，不新增蓝色选中线。

### 3. Source：使用现有 TextField 的 hint

位置：`source_editor.dart` 的 TextField/InputDecoration，原约 438–466 行。

1. 优先使用 `InputDecoration.hintText: 'Start writing Markdown…'`，样式使用已有 source 字体及 theme 的 secondary/tertiary neutral 色；避免额外覆盖层、额外可点击区域或把提示写进 controller。
2. 保留现有 contentPadding 和正文首行原点，hint 与真实输入的基线/字体一致；不要照抄生成图里偏大的非等宽字体和较大的留白。必要时只调整 hint 自身的单行呈现。
3. TextField 应自行随内容隐藏/显示 hint。判定严格为空字符串；用户输入空格、换行或 IME 正在组合的内容都不应被当成“没有输入”。
4. 保留右侧已有 `No Headings / Add headings to navigate your document.`，不额外新增说明卡片或新建/打开按钮。

## 生成图验收

**采纳：** 保持黑侧栏、三模式、标签页、固定右大纲和简洁空白编辑区；Source tooltip 解释明确；文件名示例使用完整中英文名称；提示是轻量的一行。

**不采纳生成偏差：**

- 图中字号、栏宽和空白边距只是示意；实际采用 DESIGN.md 和既有布局常量，不能从图量尺寸。
- Source hint 在生成图中为较大非等宽字体；实施必须与当前 Source 文本样式相符。
- 图中出现灰色竖线模拟光标，不作为新增组件。真实 caret 仍由现有 TextField 控制。
- 注释栏缺少请求的总标题，并保留蓝色编号；这些仅为评审板说明，不属于产品 UI。
- 图中 tooltip 正常浮现只是示例状态，不常驻显示；截屏无法证明其 keyboard/AX 行为。

## 实施后的必要验收

这些验证针对行为风险，不要求镜像实现的测试。

- 模式：辅助功能树中出现三个可命名、可激活、有 selected 状态的按钮；一次播报即可区分三模式；鼠标和既有键盘/菜单切换仍同步。实际量控件满足 28 点最低高度。
- 标签：中英文、emoji、长名和放大文字时仍遵守最大宽度；前九标签快捷键、重排后的 reveal、关闭和 dirty 状态正常；完整路径 tooltip 仍在。
- Source：新建空文档提示可见；首次输入消失、删除回空再现；点击提示位置可输入；切换模式/保存/撤销后文档内容及 dirty 状态正确；提示不被保存或算入字数。若 hint 影响 selection 或 IME，应先修复再交付。
- 保持现有最小窗口 840 × 560、浅深外观和右栏可见时无溢出；不根据生成图认定通过。
- Live/Read 若后续获准补充提示，另验空文档点击、模式切回、输入/删除、只读限制；不修改 Markdown 内容与 parser。

第二轮评审结束。主流程可以在上述边界内开始三项 UI 调整；Live/Read 空白态仍须按条件取证后决定。

## 补充核验：Live 空文档条件已满足

补充时间：同一轮体验过程，主流程已开始此前通过的三项 UI 调整；本补充只读核验 Live，未修改产品代码、未重新生成方案图。

主流程提供新的运行截图 [`13-empty-live.jpg`](../../screenshots/13-empty-live.jpg)，本评审已用 view_image 查看：Live 模式选中，活动标签是 `Untitled-12.md`，状态栏为 `0 words / 0 characters`，中央编辑区完全空白，右侧仍有既存的 `No Headings` 说明。主流程同时报告本次 AX 只有 `Edit Markdown block` 按钮，没有写作提示；该 AX 事实来自主流程实际操作，不是由截图推测。

**Live 原“先取得当前运行态空白证据”的条件现已满足，批准补充与 Source 同一文案的轻量提示。** 这只将既有条件结论转为可实施；Read 仍暂缓，不能使用写作提示。生成图仍是 Source 的设计示意，不能当作已经生成或已经验收 Live 的证明。

### 共享参数建议

主流程刚添加、尚未发布的 `sourcePlaceholder` 可收敛为 `IanvsMarkdownLiveEditor.placeholder`，与 `IanvsMarkdownEditor.placeholder` 命名一致。类型保留 `String?`、默认 `null`，宿主 app 传入 `Start writing Markdown…`；注释明确它只在整份文档为空且处于 Source/Live 两个编辑模式时显示。这样保留库使用者的默认外观，也避免新增两个内容相同但以后易失配的参数。Source 分支继续向内层 editor 传递；Read 分支完全不消费该值。

### Live 最小实施位置

1. **未激活的空文档**：`_buildRenderedBlock` 中当前 `if (block.source.trim().isEmpty)` 返回 `SizedBox.shrink()`。保留这个分支对普通空白块的既有行为，只在 `widget.controller.text.isEmpty` 且 placeholder 非空时换为提示 Text。用本模式已有段落字体及 secondary/tertiary neutral 色，保留外层原有 `MouseRegion`、`Semantics`、`GestureDetector`、24 点最小高度和 10/3 点 padding。不要新增浮层、按钮或新的激活逻辑。
2. **已激活的空文档**：`_buildActiveBlock` 的现有 TextField/InputDecoration 加入 `hintText: widget.controller.text.isEmpty ? widget.placeholder : null`，hintStyle 从其 `activeTextStyle` 派生，只改颜色。这样点击后提示仍在相同首行位置，真正输入才消失。
3. **空白判定必须看整份文档**，不能只用 `block.source.trim().isEmpty` 或 `_blockController.text.isEmpty`。后两者会把有内容文档里的普通空段/空 gap 行也提示为“开始写作”。用户已输入的空格、换行和组合输入均应保留其真实状态。
4. **不需要改 `_buildActiveGapLine` 或 parser**：现有文档同步在整份内容删除为空后会将尾部 gap 归回零长度 paragraph（`keepsTransientTrailingGap` 要求编辑末尾严格大于块末尾，空文档时不成立）。若运行复核出现异常，应先定位该状态，不通过全局给 gap 加提示掩盖。
5. 不把提示加入 controller、块源码、字数统计、undo 历史或保存内容。避免让非活动提示成为可复制的正文；全选/复制空文档必须仍得到空内容。

### Live 完成条件

新建后未聚焦即可看见提示；点击提示进入原编辑入口，首行位置不跳动；输入首字符隐藏，删除回空再现；Live/Source 来回切换保持文案与实际空状态一致；退出到 Read 不出现写作提示；空格和换行不误触发；空文档保存、复制和撤销均不包含提示。现有右大纲空白说明保持原样。

