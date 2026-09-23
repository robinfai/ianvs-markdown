# Linefold：第一轮设计评审

状态：第一轮生成与设计评审完成；第二轮已完成定向纠偏，最终实施约束见 `design-review-round-2.md`。

执行：subagent，内置 `image_gen`，`ui-mockup`；没有使用 CLI/API fallback。

参考：`01-live-baseline.png`、`02-paragraph-focused.png`。两张均已通过 `view_image` 检查。遵循 `app/DESIGN.md` 的现有桌面界面约束。

已知事实：主代理实测普通段落和标题进入焦点后块高度减少 6 px、基线上移 3 px；引用编辑字号变大；代码块两态不一致。生成图仅用于审查目标体验，不作为这些问题已解决的证据。

## 完整生成提示词

```text
Use case: ui-mockup
Asset type: internal UI design review board for the existing Linefold Markdown desktop app, round 1. This is a design proposal, not a screenshot or runtime verification.
Input images: Image 1 is the actual unfocused app reference; Image 2 is the actual focused-paragraph app reference and demonstrates a layout-jump defect. Both are reference images, not permission to redesign the product.
Primary request: generate a high fidelity side-by-side comparison of the intended stable reading and text-editing focus states. Keep the existing interface and document from Image 1. On the right show the same paragraph focused, with a text insertion caret and at most the existing subtle blue focus rail. Crucially both states have exactly identical text baselines, line heights, word wrapping, paragraph heights, top/bottom padding and positions of all following content.
Style/medium: precise desktop UI mockup, restrained macOS-like visual language, faithful to the supplied screenshot.
Composition/framing: a wide review board with two equal-sized app windows aligned to the same top edge, captions OUTSIDE each window: "READING" and "FOCUSED". A very small outside-window footer says "Design target · runtime verification required". Do not add measurement or commentary UI inside the app.
Content: retain the black single Workspace sidebar, inline Search Files, fixtures file tree, compact tab strip, light toolbar with Live / Source / Read, white reading surface, right Outline inspector, and bottom status bar. Keep Chinese/English document text and mixed Markdown examples from the reference: front matter currently appearing as title/tags, heading, ordinary paragraph, bold, italic, strikethrough, highlight, inline code, link, lists, task boxes and quote. The unintended raw title/tags display remains for diagnosis; do not normalize it into decorative document metadata.
Constraints: sidebar 248 points, toolbar 44 points, tab strip 32 points, inspector 224 points, status 25 points at original logical scale. No new navigation, no new branding, no promotional ornaments, no AI entry points. Keep the original document typography and glyph shapes. Preserve the existing heading hierarchy, list indent, quote text size and geometry, neutral inline-code styling. Focus changes only caret and lightweight existing emphasis. No content shifting, larger focused text, changing line height, added focus padding, thick outline, shadows, cards, new controls, or different document content between states.
Review purpose: express the invariant for all Markdown blocks, including headings, list items, quote and fenced code. Do not imply that a generated image establishes pixel-correct implementation.
```

## 第一轮评审

生成图：`design-round-1.png`。已人工查看内置工具返回的完整图像。

### 可以保留

- 黑色单侧边栏、白色文档、紧凑标签、居中模式切换、右侧大纲、底部状态栏延续现有界面；没有新增导航或 AI 入口。
- 两态使用相同文档和同一可视范围；普通段落、列表、引用在视觉上保持近似对齐。聚焦只用细蓝色边线与插入光标表达，这是应落实的交互方向。
- 文档的语义样式保留：标题仍是标题，引用仍是引用，代码仍使用等宽字形，任务仍有复选框。
- 原截图里被错误当作正文渲染的 title/tags 仍保留在审查图中，避免把功能缺陷美化为新设计。

### 不接受或不能据此验收

- 生成图存在重新栅格化和缩放，中文、小图标、个别间距与原始截图不是像素级复制；不能据此认定 +0/-0 px。
- 生成图仅展示普通段落获得焦点，没有实际覆盖标题、列表、引用和围栏代码进入编辑态。尤其代码块在这个视口中未出现。
- 图中的近似对齐不证明原组件的 baseline、height、padding 或 caret 几何已统一；需要实现后实测。
- 不应把生成图带来的窗口外背景、外部投影、额外留白或微小字体差异复制进产品。
- 行内语法若在编辑时显示标记，字符数增加可能引发重新折行；这不能被掩盖为“已稳定”。普通文本聚焦必须零变化；有标记文本的显示/编辑模型必须在实现与测试里明确处理。

### 第二轮定向纠偏

将审查焦点从整窗近似对齐收敛到不同 Markdown 区块的相同排版约束。保留现有界面作为参照，补充标题、列表、引用、围栏代码的两态细节。所有审查注释放在应用窗口外，不能成为新产品功能。第二轮不另起设计方向。

### 先行实现原则（第二轮完成前不调整生产 UI）

1. 编辑与展示共享每类区块的字体族、字号、字重、字距、行高和文本缩放策略。
2. 区块外部间距与内部 padding 是几何的一部分；焦点边线用不影响布局的覆盖层或预留固定槽位。
3. 编辑器默认 decoration、contentPadding、minLines、strut/baseline 差异必须检查，禁止依靠负 margin 抵消某个截图。
4. 点击 focus 后不改文档、dirty state、Undo 历史；光标要落到点击附近，不应把整段全选。
5. 验收以运行中基线、块尺寸、下一区块 y 坐标及截图为证据，不能以 mock 代替。
