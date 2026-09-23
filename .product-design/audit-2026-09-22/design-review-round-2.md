# Linefold：第二轮设计评审

状态：第二轮生成与设计评审完成。两轮设计流程已完成，可以依据下方约束开始生产 UI 调整。

执行：subagent，内置 `image_gen`，`ui-mockup`；没有使用 CLI/API fallback。第一轮评审完成后才发起本轮。

输入图：`design-round-1.png`（上轮方案）、`01-live-baseline.png`（真实外壳基准）、`03-read-mode.png`（真实语义样式/代码/正确隐藏 front matter）、`07-quote-focused.png`（真实引用聚焦缺陷）。均已通过 `view_image` 查看。另检查 `05-outline-navigation.png`、`04-read-extensions.png` 以确认相关功能边界。

## 本轮纠偏

第一轮未直接覆盖标题、列表、引用和围栏代码的编辑态。本轮保留同一外壳，使用分开的局部示意逐一审查，避免把多个光标错画为同一运行状态。第 07 张真实截图还显示：引用聚焦后源语法 `>` 被插入正文文本流，进一步改变文字起点；因此不仅要统一字号，还需处理语法标记占位。

主代理新增证据：`showFrontMatter: false` 的 Live 仍显示 YAML，而 Read 正确隐藏；Read 大纲点击 Setext 会切回 Live 且错误到顶部。因此准许将 YAML 在 Live 隐藏且不占空间，保留 Source 原文；大纲沿用现有视觉，仅修正定位与模式保持。外链/Wiki 回调、图片与 Mermaid 宿主渲染能力另列功能范围，不以设计图臆造。

## 完整生成提示词

```text
Use case: ui-mockup
Asset type: second and final internal design-review board for the existing Linefold desktop Markdown editor.
Input images: Image 1 (first generated board) is the prior proposal to correct. Image 2 (actual baseline) is the authoritative visual shell reference. Image 3 (actual Read mode) is a reference for semantic Markdown typography and visible fenced code, and correctly shows hidden front matter. Image 4 (actual focused quote) is a defect reference only: it wrongly enlarges quoted text and exposes a greater-than marker in the text flow.
Primary request: targeted revision of round 1: make focus-state review cover paragraph, heading, list, quote and fenced code. This is a design target illustration, never runtime evidence.
Composition: one small contextual full app window across the top, faithfully retaining the actual black single Workspace sidebar, light toolbar, compact tab strip, white document and right Outline. Use Live mode selected. Its document starts with the real Linefold Markdown heading as in Image 3 because valid front matter is intended to be hidden in Live and Read. Below the app context, an external comparison board with two equal columns labelled "LIVE · IDLE" and "LIVE · FOCUSED", and five clearly separate rows labelled "Paragraph", "Heading", "List", "Quote", "Code". Each row consists of matching white document detail crops, not new cards or panels inside the product. Each focused crop is an INDEPENDENT focus example; never show several carets in the same actual app window.
Exact content in both columns:
Paragraph: "普通段落：点击前后，文字基线、行高不变。"
Heading: "列表与引用"
List: a normal bullet followed by "普通列表第一项"; next line an indented bullet followed by "嵌套子项".
Quote: "引用第一行，点击后保持字体和行距一致。" on line one; "引用第二行，后面的区块不应跳动。" on line two.
Code, monospace: "final greeting = 'Hello, 折行';" then "print(greeting);"
Style: use the existing semantic text styles from the actual app; the focused crop must retain the idle crop's exact font family, size, weight, letter spacing, line height, wrapping, indentation, padding, background and block dimensions. Preserve the quote's original blue rail and subtle background in both crops. Code is the same monospace size and same background in both crops, with the same syntax highlighting if present. Heading remains heading-sized; nested list keeps its gutter and indent. Focus changes only a thin insertion caret and optional subtle existing blue focus rail. The quote source marker ">" must NOT appear inside the text flow; do not reveal source syntax that changes the paragraph width or causes wrapping. Keep all text origins and the next-block marker aligned across each pair.
Outside-window annotations only: a very small footer "Design target · verify in running app". A separate short review note at the bottom: "Front matter: hidden in Live / Read; preserved in Source. Outline: keep current mode and scroll to heading."
Constraints: do not introduce a new design direction. No new navigation, additional inspector, extra branding, AI action, decoration, large focus outline, extra focus padding, shadows or focus color wash. Preserve the app's current black sidebar and restrained macOS desktop shell. Do not treat exposed YAML as decorative metadata. Do not invent image, Mermaid or Wiki functionality. Do not put the comparison board or review labels inside the app window. This board expresses implementation invariants, not measured pixels.
```

## 第二轮评审与实施验收

生成图：`design-round-2.png`。已人工查看内置工具返回的完整图像。

### 评审结论

采纳行为方向和现有界面约束，不能把生成图作为像素尺寸规范。第二轮补齐五类内容的独立焦点示意，引用未再向正文插入 `>`，代码保持等宽排版，焦点没有以更大字号表达。上下文保留黑色单侧边栏、紧凑标签、模式控件和大纲；没有引入新产品入口。合法 YAML 不再占用正文顶部，这是已证实缺陷的修复目标。

生成图仍有局限：部分光标旁字符被重绘后出现额外空隙；引用蓝线比真实截图略粗；上下文的文本内容被简化；裁切示意经过缩放，无法证明每个基线、padding、行高和尺寸数值相同。实施时拒绝复制这些偏差、窗口外投影、外部审查标签以及示意图中任何装饰。保留 `app/DESIGN.md` 尺寸和现有主题值。没有第三个设计方向，也不需要生成图作为运行修复的证明。

### 可实施约束

| 对象 | 实施要求 |
| --- | --- |
| 普通段落 | 展示与编辑必须共享有效 TextStyle、文本缩放、strut/baseline、line-height、wrapping width、内外 padding；聚焦只出现 caret/既有轻量焦点标识。 |
| 标题 | H1–H6 与 Setext 各自维持原字号、字重和上下留白；进入编辑不能回退成普通正文大小，标题装饰不能改变文本起点。 |
| 列表/任务 | marker gutter、缩进、checkbox 和正文起点保持。聚焦不切换任务状态；点击 checkbox 才是修改动作。嵌套层级不随焦点改变。 |
| 引用 | 共享原引用字号、行距、边线槽位、背景和内边距。编辑器不可恢复默认大号正文；`>` 语法不能临时挤入 payload 宽度。多行与嵌套引用分别验证。 |
| 代码 | 围栏代码/缩进代码共享等宽字体与度量、背景和 padding；围栏/语言标识采用固定空间或 Source 编辑，焦点本身不得增加空行、围栏行或语言栏高度。长行的折行或水平滚动策略在两态一致。 |
| 焦点修饰 | 采用 overlay 或预留的固定槽位，不能增加 Border/Container 尺寸、改变 padding，也不能把字符挤开。 |
| 原文标记 | 若 Live 进入编辑会显露源语法，需要确保语法占位不改变可用正文宽度或行数；不能只修行高然后接受重新折行。具体实现可以共享文本布局/固定 gutter/语义编辑到源文映射，但必须以运行结果验收。Source 持续保留完整 Markdown。 |
| Front matter | 已识别的合法文档头在 Live 与 Read 的 `showFrontMatter: false` 下完全隐藏、零占位；Source 原文和保存内容逐字保留。未闭合或正文中的 `---` 不能被吞掉。 |
| 大纲 | 点击任何 ATX/Setext 标题保持当前 Live/Source/Read 模式，实际目标进入可视区、选中状态对应目标；不只设置高亮，不错误回顶部。Source 的位置换算必须考虑 front matter 的原始行数。 |
| 应用外壳 | 不改导航结构、控件尺寸、侧栏颜色、标签密度、大纲宽度或状态栏。沿用原图与 DESIGN.md；所有图中审查注释都不属于产品 UI。 |

### 运行验收标准

1. 对实际测试文档逐块测量 idle/focused：首行 baseline、每行 baseline、块 height、文本 origin、内外 padding、下一可见区块 y；逻辑尺寸必须相同。自动化布局断言只允许浮点舍入误差，不可用 ±6 px 或 ±8 px 掩盖当前缺陷。截图判断时区分亚像素抗锯齿与真实布局位移。
2. 至少覆盖：单行/自动换行普通段落、中英混排、行内粗斜体/删除线/高亮/代码/链接，H1/H2/Setext，普通/有序/嵌套/任务列表，两行引用、围栏/缩进代码及长代码行。仅测试纯英文短句不足以排除换行风险。
3. 保持原有文档宽度与较窄窗口各执行一次；字体缩放若被宿主支持，至少验证默认与另一档。点击处于视口内的区块，焦点不得主动改变整篇 scroll offset，后续内容不能跳动。
4. 只点击 focus、切换焦点、失焦，不修改源字符串、不增加 Undo entry、不触发 dirty，不改变任务状态。输入、撤销、保存重新打开另验源语法完整，不能通过丢失 Markdown 标记换取视觉稳定。
5. Front matter 验证 Live/Read 都以第一个真实正文块开头；切 Source 后原 YAML 包含分隔线仍完整；保存后无丢失。
6. 分别在 Live、Source、Read 点击大纲远端 Setext 标题；当前模式不变，目标实际进入视口，必要时以原始 offset/行号或稳定 heading id 校验，而不是标题文本猜测。包含同名标题与 front matter 的文档也不得选错目标。
7. 实施后由主代理在真实应用重新截图对比，再报告通过/未通过。两张 imagegen 输出从未、也不能证明实现已通过。

### 本轮范围边界

Read 外链/Wiki 回调以及图片、Mermaid 的宿主渲染属于功能能力审查，未经实现和实际运行不宣称可用。本轮只确定与既有体验一致的行为，不添加新 UI 入口或生成不存在的渲染效果。

## 交付记录

- 第一轮：`design-round-1.png`、`design-review-round-1.md`。
- 第二轮：`design-round-2.png`、本文件。
- 完整最终提示词分别保存在两轮评审文件；两轮均调用内置 `image_gen`，没有 CLI fallback。
- 本 subagent 仅写入审查文档和图片，没有修改生产代码。
