# 公共 API 与行为契约

适用范围：2026-10-08 的仓库版本（`0.3.1` + `Unreleased`）。本文件对应 R1-01 / R1-02，说明已有行为与接入边界；后续修改预设、预算或默认行为时必须同步更新。平台构建能力另行验收，不能从 Dart 类型可用推断平台支持。

## 四种入口

| 能力 | `IanvsMarkdown` | `IanvsMarkdownView` | `IanvsMarkdownEditor` | `IanvsMarkdownLiveEditor` |
| --- | --- | --- | --- | --- |
| 用途 | 内容大小的正文/消息 | 有界高度的完整文档阅读 | 完整源码编辑 | Live / Source / Reading 三模式容器 |
| 文档输入 | `data: String` | `data: String` | 宿主的 `IanvsMarkdownController` | 宿主的 `IanvsMarkdownController` |
| 修改原文 | 无编辑 Controller | 无编辑 Controller；局部 HTML 控件状态不等于文档编辑 | 编辑 Controller 原文 | 编辑 Controller 原文 |
| 语法预设 | `syntaxPreset`，默认 `obsidian`，可选 `standard` | `syntaxPreset`，默认 `obsidian`，可选 `standard` | Obsidian 风格源码高亮与输入行为 | 当前仅 Obsidian 文档语义 |
| 自定义语法 | `blockSyntaxes` / `inlineSyntaxes` / `extensionSet` | 不公开上述参数 | 不公开 | 不公开 |
| 自定义元素 | `builders`、`paddingBuilders`、图片/图表/公式/Wiki builder | `builders`、图片/图表/公式/Wiki builder | 无渲染 builder | `builders`、图片/图表/公式/Wiki builder；应用于可渲染模式 |
| 选择 | 默认单文档跨块选择；可用 `documentSelection: false` 退回块级选择；`selectable: false` 关闭 | 默认跨块选择；可用 `selectable: false` 关闭 | Controller 的原文选区 | Live/Source 使用源码选区；Reading 使用阅读态选择 |
| 滚动对象 | 由外层宿主提供滚动布局 | 参数 `controller` 的类型是 **`ScrollController`** | 参数 `scrollController` | 参数 `scrollController`，随模式使用 |
| 焦点对象 | 阅读选择内部管理 | 阅读选择内部管理 | 可注入 `focusNode`，另有 `autofocus` | 可注入 `focusNode`，另有 `autofocus` |
| 渲染预算 | 整个正文的 `renderBudget` 与 `fallbackBuilder` | 正文预算与 `fallbackBuilder`；预解析范围另见下文 | 无 `renderBudget` | 渲染块使用 `renderBudget`，Reading 传给 View；无公开 `fallbackBuilder`，Source 不受该预算约束 |
| 主题 | `theme` / ThemeExtension；`styleSheet` 与 `styleSheetTheme` | `theme` / ThemeExtension；`styleSheet` | `theme` / ThemeExtension 与组件源码样式 | `theme` / ThemeExtension；`styleSheet` 用于渲染面 |
| Front matter / 大纲 | 没有完整文档容器 | `showFrontMatter: false`、`showOutline: true`、`enableHeadingFolding: false` | 原样编辑 YAML；无阅读大纲 | `showFrontMatter: false`、`showOutlineInPreview: true`、`showNavigationPane: false`、`enableHeadingFolding: false` |
| 模式切换 | 无 | 无 | 控件始终是源码编辑器；工具栏可以改变 Controller.mode，宿主负责切换显示 | 监听 Controller.mode 并切换实际界面 |
| 文本变化通知 | 宿主更新 `data` | 宿主更新 `data` | `onChanged` 只报告文本变化 | `onChanged` 报告文本变化，`onModeChanged` 报告模式变化 |
| 保存 | 宿主负责 | 宿主负责 | `onSaveRequested`，支持异步完成与取消 | `onSaveRequested`，支持异步完成与取消 |
| 工具栏/快捷键 | 无编辑工具栏 | 无编辑工具栏 | `showToolbar`；`enableModeShortcuts` 只控制模式键 | 同 Source；导航栏可替代工具栏中的模式切换器 |
| 阅读复制 | 原始 Markdown / 安全 HTML 双表示，可注入 `clipboardWriter` | 同正文 | 使用文本编辑面复制；无 `clipboardWriter` 参数 | `clipboardWriter` 用于阅读/渲染面，不替换 Source 的文本编辑复制 |

源码依据：[正文与 View](../lib/src/ianvs_markdown.dart)、[Source](../lib/src/editor/source_editor.dart)、[Live](../lib/src/editor/live_editor.dart)。
行为证据：[标准 View](../test/standard_view_test.dart)、[标题范围](../test/heading_folding_test.dart)、[标准语法](../test/standard_syntax_test.dart)、[正文/View](../test/ianvs_markdown_test.dart)、[Live](../test/live_editor_test.dart)、[宿主契约](../test/host_contract_test.dart)。矩阵描述支持范围，不能把同名参数视为相同的处理路径。

## 原文、选择与更新

- 原始 Markdown 是唯一文档模型。编辑 Controller 和块范围使用 Dart 字符串的 UTF-16 偏移；语法预算降级的大小使用 UTF-8 字节，两者不能混用。
- 阅读态 `onSelectionChanged` 提供选择内容及阅读态范围，不保证是原始 Markdown 的精确偏移；需要编辑或源码导航时使用编辑 Controller / 源码范围接口。
- 正文 `data` 变化重新构建解析；阅读选择会随源码变化失效，不承诺增量 AST。View 的 `data`、`syntaxPreset`、`showFrontMatter` 或预算变化会重新解析并安排滚动回到顶部。
- Live 在纯选区/composing 变化时复用文档结构，文本变化、撤销/重做与替换 Controller 时重新更新结构。Controller 自身还维护引用上下文。解析次数减少不代表所有布局成本已经消除。
- 模式切换使用同一 Controller 的原文、dirty 和历史。Live 与 Reading 的选区是不同交互面，不保证恢复阅读态的拖选区域或所有模式的滚动像素位置。
- 没有独立的 document ID API。推荐每个文档持有一个 Controller，宿主保存文档身份并用稳定 Key 区分文档。直接替换 `controller.text` 不会自动重置历史或保存基线。

## 语法预设的范围（R1-02）

正文和 View 均支持 `syntaxPreset: IanvsMarkdownSyntaxPreset.standard`，默认继续为 `obsidian`。两种入口使用同一份 [v2 标准语法样例](../test/fixtures/standard_syntax_contract.json)，覆盖字面 Obsidian 标记、HTML、YAML、任务、强调、表格、嵌套列表、链接和脚注。

| 行为 | `obsidian` | `standard` |
| --- | --- | --- |
| View front matter | 从正文移除；`showFrontMatter` 控制属性卡 | 完整原文进入 GFM，YAML 形状的内容可能成为 Setext 标题；不生成属性卡，`showFrontMatter` / `showDocumentTitle` 不生效 |
| Wiki、注释、数学等扩展 | 保留既有投影和 builder | 标记保持 GFM 原始语义，不启用 Obsidian 投影、数学或 HTML 交互控件 |
| View 大纲/折叠/导航 | 既有文档块模型 | 按 GFM 顶层标题建立范围，保留原始 UTF-16 偏移；代码围栏、HTML、引用和列表中的标题不进入文档大纲 |
| 预算 token | 美元符号计入数学语法 | 字面美元符号不计入数学语法；View 的标题判断与正文使用相同预设 |
| 全选复制 | plain text 保留完整原文；View 的富文本从去除 front matter 后的正文生成 | plain text 保留完整原文；富文本从完整 GFM 原文生成 |

复制的 HTML 经过安全过滤，不承诺自定义 Widget、Obsidian 扩展或原生图表的视觉复刻；部分选择按已有 GFM DOM 映射，无法匹配时降为所选纯文本。预算截断的是显示前缀，全选复制不截断原文。预设切换会使阅读选择失效，View 重新解析并回到顶部；旧折叠状态仅保留新标题模型中仍存在的身份。

Live 与 Source 在本轮继续使用 Obsidian 编辑语义。**暂不向 Live 暴露 standard 参数**：它同时影响源码高亮、块分割、投影后的选区/输入映射、嵌套编辑和三模式切换，仅传递给 Reading 会产生模式间语义差异。需要标准 GFM 阅读时使用正文或 View；完整标准编辑作为独立扩展，先具备上述编辑契约和回归，再决定实现，不阻塞本轮只读接入。

## 预算与资源

默认 `IanvsMarkdownRenderBudget` 为 4096 个语法 token、64 KiB UTF-8 降级文本。`renderBudget: null` 显式关闭相应渲染预算。它不是整个文档大小、内存、布局时间、资源解码或全部预解析的总量上限。

| 入口 | 计量与降级范围 |
| --- | --- |
| 正文 | 使用所选预设扫描传入 `data`，超限后调用 `fallbackBuilder`，不调用渲染资源 builder |
| View | 使用所选预设扫描正文以决定大纲可用性；显示正文（开启折叠时为折叠投影）由内部正文组件再扫描和降级。Obsidian 元数据卡不计入正文预算，standard 的 YAML 计入原文 |
| Live | 渲染块分别使用预算，Reading 传给 View；不能把每块额度解释为全文件总额 |
| Source | 无渲染预算参数，排版完整可编辑原文 |

UTF-8 降级边界不切开有效 Unicode 码点；小于下一个码点所需字节时停止。宿主设置 `renderBudget: null` 意味着承担该渲染路径的完整负载，不能据此宣称其他路径有独立保护。

View 在正文渲染预算判断前解析文档，Live 在各块渲染前维护全文结构；Source 排版完整源码。富文本复制还会转换 Markdown/HTML。历史容量、预解析和复制预算分别由 R2-02 / R2-05 跟进，不能把当前预算描述成这些路径的完整保护。

图片默认显示占位，不自动读取文件或网络；图片、Wiki 嵌入、链接导航和图表后端的权限、解码、缓存及过期结果由宿主负责。`super_clipboard` 是包级依赖，注入 writer 只改变调用行为，不能消除原生构建依赖。参考 [剪贴板](../lib/src/rich_clipboard.dart)、[预算](../lib/src/render_budget.dart)。

## 对象与保存

生命周期、异步保存及文档切换的可运行示例见 [接入指南](INTEGRATION_GUIDE.md)。关键契约如下：

- 宿主传入的文档 Controller、FocusNode、ScrollController 不由组件释放；组件仅释放自己创建的焦点、滚动和内部对象。
- 保存回调收到触发时捕获的原文。正常完成后，内置工具栏/快捷键调用 `markSaved(savedText: capturedText)`；保存期间的后续编辑仍为 dirty。回调不得再次无条件 `markSaved()` 覆盖这个基线。
- `IanvsMarkdownSaveCancelledException` 表示未确认保存，内置保存保持 dirty；其他异常不被吞掉。宿主负责报告错误、串行化写入和处理文档身份。
- 文档已释放后到达的 `markSaved` 确认被忽略；这不取消已经开始的存储操作，也不允许继续使用其他已释放接口。该修复属于当前 `Unreleased`。

## 公共导出承诺与分层

入口是 `package:ianvs_markdown/ianvs_markdown.dart`。本次用 Dart AST 审查其直接导出及 show/hide 规则，并用 Flutter 编译探针核对全部符号。清单包括 164 个项目符号和 11 个第三方重导出；不包含实例成员清单。

| 使用面 | 范围 | 兼容约束 |
| --- | --- | --- |
| 稳定接入面 | 四种 Widget、Controller 与 EditorMode、主题、预算、保存/资源回调、阅读剪贴板、工具栏及标题导航控制器 | 本文件和接入样例优先覆盖；改变签名、默认行为或存储语义时提供迁移说明 |
| 兼容保留的扩展面 | 下表中的语法类、builder、投影、解析、源码操作和独立 UI 辅助类型 | 都是当前可用的公共导出；本轮不删改。其组合不构成通用或增量 AST 承诺，1.0 前逐项决定长期定位；收敛也需兼容/弃用路径 |
| 第三方重导出 | 下表显式列出的 flutter_markdown_plus 类型 | 来源受已验证依赖组合约束；依赖升级要验证签名与行为，不能独立承诺上游实现 |
| 实验/内部 | 未从入口导出的诊断接口，以及宿主直接导入 `src/` 获得的实现细节 | 不属于稳定公共入口；例如隐藏的 `ianvsMarkdownInlineSourceRangeAt` 和未导出的性能计数工具 |

已弃用的 `markdownFrontMatterLineLimit` 仍兼容导出；front matter 实际按 `markdownFrontMatterByteLimit` 限制，新增接入应使用字节限制。

以下是本次核对的完整顶层导出清单，按源码分组。类型的公开成员详见其 Dart 声明；第三方签名中用到的 `markdown` 语法类型仍需宿主显式导入该包。

### [lib/src/blocked_image.dart](../lib/src/blocked_image.dart)

`IanvsMarkdownBlockedImage`

### [lib/src/callout.dart](../lib/src/callout.dart)

`IanvsMarkdownCallout`、`IanvsMarkdownCalloutBodyBuilder`、`IanvsMarkdownCalloutBuilder`、`IanvsMarkdownCalloutHeader`、`IanvsMarkdownCalloutSyntax`、`IanvsMarkdownCalloutTitleBuilder`、`parseIanvsMarkdownCalloutHeader`

### [lib/src/code_block.dart](../lib/src/code_block.dart)

`IanvsMarkdownCodeBlock`、`IanvsMarkdownCodeBlockBuilder`、`IanvsMarkdownCodeBlockPresentation`、`IanvsMarkdownCodeCopyHandler`、`IanvsMarkdownCodeFlair`、`IanvsMarkdownDiagramBuilder`、`IanvsMarkdownIndentedCodeBlock`、`IanvsMarkdownIndentedCodeBlockSyntax`、`markdownCodeCanHighlight`、`markdownCodeExpandTabs`、`markdownCodeHighlightCharacterLimit`、`markdownCodeHighlightLineLimit`、`markdownCodeLanguage`、`markdownCodeLanguageLabel`、`markdownCodeLineCount`、`markdownCodeTabSize`、`markdownHighlightedCodeSpan`、`normalizeMarkdownCodeLanguage`

### [lib/src/editor/editor_controller.dart](../lib/src/editor/editor_controller.dart)

`IanvsMarkdownController`、`IanvsMarkdownEditingFormatter`、`IanvsMarkdownHistoryValue`、`IanvsMarkdownInlineMathSource`、`IanvsMarkdownSyntaxTheme`、`buildMarkdownSourceTextSpan`、`ianvsMarkdownInlineLinkSources`、`ianvsMarkdownInlineMathSources`

### [lib/src/editor/editor_models.dart](../lib/src/editor/editor_models.dart)

`IanvsMarkdownBlock`、`IanvsMarkdownBlockType`、`IanvsMarkdownEditorMode`、`IanvsMarkdownHeadingNavigation`、`ianvsMarkdownTableBodyContinues`、`markdownBlockAtOffset`、`markdownGapLineCount`、`parseMarkdownBlocks`

### [lib/src/editor/editor_shortcuts.dart](../lib/src/editor/editor_shortcuts.dart)

`IanvsMarkdownEditorShortcuts`

### [lib/src/editor/editor_toolbar.dart](../lib/src/editor/editor_toolbar.dart)

`IanvsMarkdownEditorToolbar`、`IanvsMarkdownSaveCallback`、`IanvsMarkdownSaveCancelledException`

### [lib/src/editor/live_editor.dart](../lib/src/editor/live_editor.dart)

`IanvsMarkdownLiveEditor`

### [lib/src/editor/source_editor.dart](../lib/src/editor/source_editor.dart)

`IanvsMarkdownEditor`、`ianvsMarkdownSyntaxTheme`

### [lib/src/emphasis.dart](../lib/src/emphasis.dart)

`IanvsMarkdownEmphasisKind`、`IanvsMarkdownEmphasisMatch`、`IanvsMarkdownEmphasisPresentation`、`IanvsMarkdownEmphasisScan`、`IanvsMarkdownEmphasisSyntax`、`ianvsMarkdownEmphasisScan`

### [lib/src/front_matter.dart](../lib/src/front_matter.dart)

`MarkdownFrontMatterDocument`、`MarkdownMetadataEntry`、`MarkdownMetadataValueType`、`markdownFrontMatterByteLimit`、`markdownFrontMatterEntryLimit`、`markdownFrontMatterLineLimit`、`parseMarkdownFrontMatter`、`replaceMarkdownFrontMatterBooleanValue`、`replaceMarkdownFrontMatterDateValue`、`replaceMarkdownFrontMatterKey`、`replaceMarkdownFrontMatterListValue`、`replaceMarkdownFrontMatterNumberValue`、`replaceMarkdownFrontMatterTextValue`

### [lib/src/front_matter_card.dart](../lib/src/front_matter_card.dart)

`IanvsMarkdownFrontMatterCard`、`IanvsMarkdownMetadataBooleanChanged`、`IanvsMarkdownMetadataDateChanged`、`IanvsMarkdownMetadataKeyChanged`、`IanvsMarkdownMetadataListChanged`、`IanvsMarkdownMetadataNumberChanged`、`IanvsMarkdownMetadataTextChanged`

### [lib/src/heading_folding.dart](../lib/src/heading_folding.dart)

`IanvsMarkdownHeadingFoldController`、`IanvsMarkdownHeadingFoldModel`、`IanvsMarkdownHeadingFoldProjection`、`IanvsMarkdownHeadingSection`

### [lib/src/highlight.dart](../lib/src/highlight.dart)

`IanvsMarkdownHighlightBuilder`、`IanvsMarkdownHighlightMatch`、`IanvsMarkdownHighlightPresentation`、`IanvsMarkdownHighlightSyntax`、`ianvsMarkdownCrossParagraphHighlightLiteralRuns`、`ianvsMarkdownHighlightMatches`、`projectObsidianCrossParagraphHighlightsForRendering`

### [lib/src/ianvs_markdown.dart](../lib/src/ianvs_markdown.dart)

`IanvsMarkdown`、`IanvsMarkdownFallbackBuilder`、`IanvsMarkdownView`、`ianvsMarkdownStyleSheet`

### [lib/src/inline_link.dart](../lib/src/inline_link.dart)

`IanvsMarkdownAutolinkScope`、`IanvsMarkdownInlineLinkBuilder`、`IanvsMarkdownWikiLinkExists`、`looksLikeMarkdownFileReference`

### [lib/src/markdown_document.dart](../lib/src/markdown_document.dart)

`IanvsMarkdownDocument`、`IanvsMarkdownHeading`、`parseMarkdownHeadings`

### [lib/src/math.dart](../lib/src/math.dart)

`IanvsMarkdownDisplayMathSyntax`、`IanvsMarkdownInlineDisplayMathSyntax`、`IanvsMarkdownInlineMathSyntax`、`IanvsMarkdownMath`、`IanvsMarkdownMathBuilder`、`IanvsMarkdownMathElementBuilder`

### [lib/src/obsidian_image.dart](../lib/src/obsidian_image.dart)

`IanvsMarkdownImageDimensions`、`IanvsMarkdownImageEditHandler`、`IanvsMarkdownImageResizeHandler`、`IanvsMarkdownImageResizeRequest`、`IanvsMarkdownImageSourceSyntax`、`IanvsMarkdownInteractiveImage`、`IanvsMarkdownSizedImage`、`IanvsMarkdownStandardImageSource`、`IanvsMarkdownStandardImageSourceSyntax`、`findIanvsMarkdownStandardImageSource`、`parseIanvsMarkdownImageDimensions`、`rewriteIanvsMarkdownImageWidth`、`rewriteIanvsMarkdownWikiImageWidth`

### [lib/src/obsidian_inline.dart](../lib/src/obsidian_inline.dart)

`IanvsMarkdownCodeSpanPresentation`、`IanvsMarkdownCodeSpanSyntax`、`IanvsMarkdownEntityPresentation`、`IanvsMarkdownEntitySyntax`、`IanvsMarkdownRenderedWhitespaceSyntax`、`IanvsMarkdownTagSyntax`、`IanvsMarkdownWikiLinkPresentation`、`IanvsMarkdownWikiLinkSyntax`、`ianvsMarkdownTagRanges`

### [lib/src/obsidian_metadata.dart](../lib/src/obsidian_metadata.dart)

`IanvsMarkdownEditingCommentBlockSyntax`、`IanvsMarkdownEditingFootnoteDefinitionSyntax`、`IanvsMarkdownEditingMetadataBuilder`、`IanvsMarkdownEditingMetadataInlineSyntax`、`IanvsMarkdownFootnoteSuperscriptBuilder`、`IanvsMarkdownLivePreviewFootnoteReference`、`IanvsMarkdownObsidianMetadataMode`、`collectObsidianStandardFootnoteOrdinals`、`ianvsMarkdownBlockIdRanges`、`ianvsMarkdownCommentRanges`、`ianvsMarkdownLivePreviewFootnoteReferences`、`prepareObsidianFootnoteDefinitionForEditing`、`prepareObsidianMarkdownForRendering`、`projectObsidianInlineLinkDestinationBackslashesForRendering`、`projectObsidianReferenceImagesForLivePreview`

### [lib/src/render_budget.dart](../lib/src/render_budget.dart)

`IanvsMarkdownRenderBudget`、`IanvsMarkdownRenderDecision`、`scanMarkdownForRendering`

### [lib/src/rich_clipboard.dart](../lib/src/rich_clipboard.dart)

`IanvsMarkdownClipboardData`、`IanvsMarkdownClipboardWriter`、`ianvsMarkdownClipboardHtml`、`ianvsMarkdownSelectionClipboardData`、`ianvsPlainTextClipboardHtml`、`writeIanvsMarkdownClipboard`

### [lib/src/strikethrough.dart](../lib/src/strikethrough.dart)

`IanvsMarkdownStrikethroughMatch`、`IanvsMarkdownStrikethroughPresentation`、`IanvsMarkdownStrikethroughScan`、`IanvsMarkdownStrikethroughSyntax`、`ianvsMarkdownStrikethroughScan`

### [lib/src/syntax_preset.dart](../lib/src/syntax_preset.dart)

`IanvsMarkdownSyntaxPreset`

### [lib/src/task_checkbox.dart](../lib/src/task_checkbox.dart)

`IanvsMarkdownTaskCheckbox`、`ianvsMarkdownTaskMarkerIsChecked`、`ianvsMarkdownTaskMarkerUsesDoneText`

### [lib/src/theme.dart](../lib/src/theme.dart)

`IanvsMarkdownThemeData`

### [lib/src/wiki_embed.dart](../lib/src/wiki_embed.dart)

`IanvsMarkdownWikiEmbed`、`IanvsMarkdownWikiEmbedContentBuilder`、`IanvsMarkdownWikiEmbedElementBuilder`、`IanvsMarkdownWikiEmbedReference`、`IanvsMarkdownWikiEmbedSyntax`

### `package:flutter_markdown_plus/flutter_markdown_plus.dart`

`MarkdownBulletBuilder`、`MarkdownBulletParameters`、`MarkdownCheckboxBuilder`、`MarkdownElementBuilder`、`MarkdownImageBuilder`、`MarkdownListItemCrossAxisAlignment`、`MarkdownOnSelectionChangedCallback`、`MarkdownPaddingBuilder`、`MarkdownStyleSheet`、`MarkdownStyleSheetBaseTheme`、`MarkdownTapLinkCallback`

