# 公共 API 与行为契约

适用范围：2026-10-22 的仓库版本（`0.3.1` + `Unreleased`）。本文件对应 R1-01 / R1-02 / R2-02、R1-03 文案/命令/焦点、R1-04 剪贴板默认行为迁移及 R2-05 预解析/复制预算、L07/L08 降级提示和输入连接。后续修改预设、预算或默认行为时必须同步更新。平台范围见 [构建与交互证据](PLATFORM_SUPPORT.md)，不能从 Dart 类型可用推断平台支持。

## API 漂移校验

仓库的 `make check-api`（同时包含在 `make check-core` 和双 SDK Core CI 中）解析公共入口，
比较 182 个项目导出、11 个第三方重导出，以及它们声明的公开成员、类型、默认值和常量。
新增、删除和修改都要求审查；检查不会自动重写基线。修改 API 时先更新本契约、迁移说明和
行为测试，再显式生成并审查基线差异。工具不比较继承成员的实现或任意行为，不能证明
语义版本兼容，也不表示 1.0 API 已冻结。维护工具与基线不进入发布包，操作说明见
[源码仓库中的 API 校验说明](https://github.com/robinfai/ianvs-markdown/blob/main/tool/api_check/README.md)。

## 链接交互类型

`IanvsMarkdown`、`IanvsMarkdownView`、`IanvsMarkdownLiveEditor`、front matter 卡片和
内置 link/embed/footnote builder 提供可选 `onTapLinkTarget`。
`IanvsMarkdownLinkTarget` 是不可变值，包含 `text`、可空 `href`、`title`（默认空串）和
`kind`（`IanvsMarkdownLinkKind.markdown` / `wiki` / `tag`）。`kind` 来自解析结构，
不根据扩展名或同文档中其他链接的 href/显示文本猜测。Wiki 的 `href` 保留原解析目标，
包括 `#Heading` / `#^block`，不追加 `.md`、做 URL 编码或文件路径解析；`text` 是实际显示
的 alias 或格式化标签。普通 Markdown href 保持已有空目标/链接解析规则。

同时传两个回调时只调用 `onTapLinkTarget`；未传它时仍调用原 `onTapLink(text, href, title)`。
嵌套 callout/HTML、Reading View、front matter Wiki 属性及 Wiki embed 打开按钮沿用同一契约。
普通 Markdown、HTML 和脚注链接为 `markdown`；Wiki 属性和 embed 为 `wiki`。
Live 仅 Wiki 导航直接交给宿主；普通链接仍保留原有渲染控制/编辑行为，tag 点击仍进入编辑。
Reading 的 inline tag 回调带 `tag`。任何点击都不会改写 Markdown 原文。

## 源码保真笔记语义（P1f）

`parseIanvsMarkdownNoteSemantics(source)` 返回不可变的 references/tags/aliases/issues。
它是纯核心解析，不读取工作区或解析文件身份。所有范围是原文 UTF-16 半开范围，保留
BOM/CRLF/emoji；reference use 的目标范围指向 first-definition-wins 的有效 definition，
不是 label。Markdown `target` 先分离 query/fragment 再 percent 解码一次；Wiki 不解码，
宿主不得重复解码。`destinationRange` 只覆盖路径，`rawDestination` 保留完整原始目标。
`complete` 必须与结果一起检查；超预算、未知语法和不能安全映射的路径不能解释成空引用。
`aliasesComplete` 与正文覆盖独立；YAML 元数据按 64 KiB/每类合计 1,024 项解析，不复用
properties UI 的 40/16 展示截断。完整字段、支持范围与未知边界见
[笔记语义契约](NOTE_SEMANTICS.md)。这是加法 API，不改变已有渲染或点击回调。

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
| 焦点对象 | 整文档选择可注入 `focusNode` / `autofocus`；块级选择不使用它们 | 可注入 `focusNode` / `autofocus`，需启用 `selectable` | 可注入 `focusNode`，另有 `autofocus` | 可注入 `focusNode`，另有 `autofocus` |
| 解析/渲染预算 | 整个正文的 `renderBudget` 与 `fallbackBuilder` | 原文预解析和显示预算；`fallbackBuilder` | Controller 的 `parseBudget` 保护引用和高亮；完整原文排版 | 全文结构使用 `renderBudget`；超限 Live 使用完整源码编辑；`onRenderDecision` 可观察；Reading 传给 View |
| 主题 | `theme` / ThemeExtension；`styleSheet` 与 `styleSheetTheme` | `theme` / ThemeExtension；`styleSheet` | `theme` / ThemeExtension 与组件源码样式 | `theme` / ThemeExtension；`styleSheet` 用于渲染面 |
| 界面文案 | 外层 `IanvsMarkdownLocalization`，中/英文与逐条覆盖 | 同正文，含大纲及折叠 | 同正文，含工具栏与文本选择菜单 | 同正文，含导航、表格与各模式 |
| Front matter / 大纲 | 没有完整文档容器 | `showFrontMatter: false`、`showOutline: true`、`enableHeadingFolding: false` | 原样编辑 YAML；无阅读大纲 | `showFrontMatter: false`、`showOutlineInPreview: true`、`showNavigationPane: false`、`enableHeadingFolding: false` |
| 模式切换 | 无 | 无 | 控件始终是源码编辑器；工具栏可以改变 Controller.mode，宿主负责切换显示 | 监听 Controller.mode 并切换实际界面 |
| 文本变化通知 | 宿主更新 `data` | 宿主更新 `data` | `onChanged` 只报告文本变化 | `onChanged` 报告文本变化，`onModeChanged` 报告模式变化 |
| 保存 | 宿主负责 | 宿主负责 | `onSaveRequested`，支持异步完成与取消 | `onSaveRequested`，支持异步完成与取消 |
| 工具栏/快捷键 | `IanvsMarkdownShortcuts` 配置选择/复制；无编辑工具栏 | 同正文 | 作用域配置命令；`showToolbar`；`enableModeShortcuts` 仍控制重映射后的模式键 | 同 Source；表格与属性保留局部命令语义，导航显示当前组合键 |
| 阅读复制 | writer 接收原始 Markdown / 安全 HTML 双表示；默认写 Markdown 纯文本，可选适配器写双格式 | 同正文 | 使用文本编辑面复制；无 `clipboardWriter` 参数 | `clipboardWriter` 用于阅读/渲染面，不替换 Source 的文本编辑复制 |

源码依据：[正文与 View](../lib/src/ianvs_markdown.dart)、[Source](../lib/src/editor/source_editor.dart)、[Live](../lib/src/editor/live_editor.dart)。
行为证据：[标准 View](../test/standard_view_test.dart)、[标题范围](../test/heading_folding_test.dart)、[标准语法](../test/standard_syntax_test.dart)、[正文/View](../test/ianvs_markdown_test.dart)、[Live](../test/live_editor_test.dart)、[宿主契约](../test/host_contract_test.dart)。矩阵描述支持范围，不能把同名参数视为相同的处理路径。

## 同文档阅读刷新（P1h）

`IanvsMarkdownView.preserveScrollOnUpdate` 默认为 `false`，保留已有的 `data`、
语法预设、front matter 或渲染预算变化后回到文首的行为。宿主仅在更新同一文档时
显式设为 `true`：保留当前 `ScrollPosition` 的像素位置，内容变短时由滚动布局裁剪到
合法范围，不恢复请求发起时的旧 offset，因此异步刷新期间用户后续滚动不会被抢回。
这不是语义锚点重定位，前方内容增删仍可能改变该位置对应的段落。

不同文档或同一路径的不同 workspace/session 必须更换 widget key；该参数本身不会判断
文档身份。既有折叠控制器继续按 heading identity 保留仍存在的折叠项，消失的 identity
会被移除；没有新建或全量清空折叠状态的副作用。仅 View 新增此参数，其他入口无需迁移。
iOS preview 使用已成功打开的 scope generation、root 与 path 作为阅读器身份。

## 宿主 Paste 拦截（P1 图片附件）

`IanvsMarkdownEditor`、`IanvsMarkdownLiveEditor` 与辅助 `IanvsMarkdownEditorShortcuts`
新增可空 `Future<bool> Function()? onPaste`。省略时不改变既有粘贴或原生菜单行为，无需迁移。
回调只由用户发起的 Paste 命令触发，包括 Ctrl/Cmd+V、
`IanvsMarkdownShortcuts.invoke(IanvsMarkdownCommand.paste)` 及组件文本菜单中的 Paste；
普通输入、构建、切换标签和剪贴板状态查询不会调用它，也不自动读取图片。

- `true` 表示宿主已经处理或主动消费请求，不执行核心文本粘贴；异常同样消费，避免宿主
  已导入/插入但报错后再次粘贴。需要错误提示时由宿主负责。
- `false` 表示没有处理，继续已有的纯文本/选中文本 URL 链接语义。安装回调后，核心只读取
  一次纯文本，通过原输入面的格式器/源码映射写入，不重复获取可能已变化的剪贴板。
- 空选区也调用回调。Reading、只读 Source、活跃 IME composing 不调用回调。
  Live 主体、Source 及渲染预算超限后的完整源码降级均支持；Live 表格单元格和 front matter
  属性仍使用原有局部文本粘贴，不调用宿主钩子。上述区域的附件粘贴需切到 Source。
- 安装回调时，组件使用自适应文本菜单，并在没有文本的剪贴板上仍提供 Paste；没有回调
  时保留既有原生菜单选择。平台直接提交的编辑更新不经过此钩子。
- 核心只保证自己的异步文本回退：等待期间 controller、输入面、焦点、原文、选区、
  composing、模式、只读状态变化或移除回调，就丢弃迟到回退，不粘贴到新文档或新选区。
  宿主回调自己的副作用不由核心取消；宿主必须在异步工作前捕获文档/controller/源码选区，
  写文件与插入前重新校验其身份、可写状态和焦点，并处理已写附件但未插入的结果。

自动证据：[Paste 拦截回归](../test/paste_interception_test.dart)。此 API 不包含附件存储、
授权、路径选择、Obsidian 附件配置解析或解码策略；这些属于宿主责任。

## 界面文案（R1-03 首批交付）

`IanvsMarkdownLocalization` 是可嵌套的文案作用域，四种入口及独立辅助 Widget 从最近的作用域读取 `IanvsMarkdownStrings`。不提供作用域时使用 `.legacy()`，保留现有中英文混合标签；`.chinese()` / `.english()` 显式选择完整的内置界面文案。`overrides` 按 `IanvsMarkdownMessage` 覆盖单条消息，未覆盖项回退到所选语言；更新时替换配置对象，传入的 map 应保持不可变。

模板只替换一次 `{label}` / `{index}` / `{count}` 等命名参数，参数中的花括号不继续求值。文档正文、原始 YAML 键值、代码语言名称、显式 Callout 标题和宿主传入的标签保持原样。解析器生成的元数据标签带 `useDefaultLabel: true`；宿主直接构造 `MarkdownMetadataEntry` 默认不翻译其 `label`。`FrontMatterCard.title` 仍返回旧默认字符串，但省略构造参数时界面可使用作用域文案；显式传入同名字符串也会保留。

文案覆盖包括工具栏、导航/折叠、表格控件、属性、任务语义标签、代码复制/降级、图片查看器、默认 Callout 标题和文本选择菜单。选择菜单在 Overlay 中从所属组件读取配置；图片弹窗捕获主题作用域。回调、源码、选区/历史与复制数据不因改文案而改变。默认文本菜单保留 Flutter 的系统原生路径；显式自定义菜单文案时使用 Flutter 自适应菜单。浏览器原生菜单及 Flutter 自有日期弹窗的整体 locale 仍由宿主的浏览器/MaterialLocalizations 配置负责。

快捷键策略由独立的 `IanvsMarkdownShortcuts` 配置，不受文案语言影响。接入见 [指南](INTEGRATION_GUIDE.md#界面文案与作用域)，回归见 [localization_test.dart](../test/localization_test.dart)。

## 命令配置与焦点（R1-03）

公共配置是 `IanvsMarkdownShortcuts` 和 `IanvsMarkdownCommand`。`bindings` 为命令到 `List<SingleActivator>` 的覆盖；空列表禁用，未提供的命令保留默认行为。`hostShortcuts` 绑定明确的宿主回调，优先于组件命令；显式命令优先于未修改的默认键。替换/禁用命令后，其旧默认键被消费，不能依赖祖先 Shortcuts 自动接管；改用宿主回调。显式命令间、宿主条目间存在重叠时抛出 `ArgumentError`，宿主与命令重叠则按宿主优先处理。最近作用域完整替代外层配置，更新需替换不可变 map/list。

命令集合：撤销、重做、粗体、斜体、插入链接、删除行、保存、切换阅读、Live/Source/Reading、缩进/反缩进、全选、复制、剪切和粘贴。内部命令边界按当前焦点分发：阅读使用整文档语义（块级选择使用相应文本块），Source 使用源码，Live 活动块保持源码映射，表格格式化与 Tab 使用单元格语义，属性使用本地撤销并阻止正文格式化/删行。属性保存/模式命令先提交局部输入再交给外层。文本箭头、普通输入、控件 Enter 属于平台/控件行为；宿主仍可显式保留这些键。

作用域只处理 Markdown 区域内的焦点。默认编辑命令、配置命令与宿主保留键在活跃组合输入期间不执行，不清除 composing；默认 Tab/Shift+Tab 仍由局部控件处理，保留日期分段导航。非重复绑定消费长按重复消息但不重复调用。原始 macOS 消息与标准化键盘路径共用配置并去重；阅读的 HardwareKeyboard 监听也遵守它，防止宿主复制键同时触发正文复制。`enableModeShortcuts: false` 不因重映射而被绕过。标签 API `labelOf` 返回首个可用组合键；命令被禁用或所有组合键均已被覆盖/保留时返回空字符串。

`IanvsMarkdownShortcuts.invoke(command, controller: optionalController)` 用于菜单/工具栏的显式操作，
不需要额外配置 Widget，也不受键位禁用/重映射或 `enableModeShortcuts` 影响。可选 controller
只用于焦点所属校验；返回 true 表示命令已处理（包括 composing 时抑制），false 表示当前
焦点没有匹配的 Markdown 目标或未处理。false 后宿主可调用当前普通控件的 Actions，不能
无条件撤销上一次正文选区。卸载、替换 controller 与脱离渲染树的旧焦点不会收到命令。
同步返回值只表示分发，不能当成异步保存/剪贴板完成回执；真实完成仍由原有宿主回调负责。

| 当前区域 | 显式命令边界 |
| --- | --- |
| Source / Live 正文 | 使用文档历史与源码映射，格式与文本操作沿用现有 Actions |
| 表格 | 格式化留在单元格，Undo/Redo 使用文档历史；默认 Tab 保持单元格导航 |
| 属性 | Undo/Redo 使用局部历史；保存/模式先提交草稿；正文格式与删行被抑制 |
| Read | 文档历史与修改命令不改源文；选择/复制保留完整文档语义 |
| 活跃 composing | 菜单/工具栏/默认编辑快捷键都不确认、不丢弃候选；调用被消费 |
| 普通宿主控件 | invoke 返回 false，由宿主 Actions 决定；不操作旧正文选区 |

工具栏 Read 下撤销/重做禁用；属性历史按钮观察局部栈，未提交属性可保存；没有局部语义
的结构格式按钮在属性/表格中禁用。按钮激活时再次校验 composing，避免可用状态更新间隙。
两个 macOS main 的原生 Edit/View 及 app Save 不注册编辑 accelerator；快捷键只经 Flutter
焦点路由，菜单仍可点击执行禁用键位的命令。原生编辑菜单不显示快捷键、保持可点击，
无可执行操作时由目标消费；宿主 File/Window 的其他快捷键不变。这是明确的宿主策略，
不是核心自动修改系统菜单。app Save As 在 composing 期间也暂停；Window 的 Cmd+数字
继续由宿主切文档，`enableModeShortcuts:false` 只禁用组件的模式键。

正文和 View 新增可选、宿主持有的 `focusNode` / `autofocus`（默认 false）；正文仅在整文档选择开启时使用。替换或卸载不释放宿主焦点对象。内置工具栏属于文本输入 TapRegion；格式/历史/保存动作保留当前局部编辑焦点，未找到本 controller 的焦点目标时使用显式传入的编辑焦点；独立工具栏可传同一 `focusNode`，未传时保持原有行为。Live 在当前组件内触发模式变化后恢复新模式焦点和源码选区；外部输入正持有焦点时，程序更新模式不主动抢焦点，宿主显式 autofocus 另行生效。

Live 初次挂载的 `autofocus:true` 尊重 Controller 现有源码光标或选区，而非固定激活首块；
远处的虚拟块先定位再连接输入。隐藏 YAML 内的选区回到首个可见正文块；只有隐藏 YAML
时不创建不可见的编辑焦点。异步定位期间外部输入接管焦点后，不再抢回输入。

接入与兼容说明见 [快捷键与焦点](INTEGRATION_GUIDE.md#快捷键与焦点)。自动证据见 [命令配置回归](../test/keyboard_configuration_test.dart) 与 [包外 smoke host](../tool/package_smoke_test.dart)。真实输入和系统剪贴板按当前 [双入口执行清单](R3_ACCEPTANCE.md) 在 example/app 中验收；已记录的本机结果不扩大其他平台或输入法范围。原生 IME 的用户人工确认与自动输入协议分开记载，读屏未执行。

## 原文、选择与更新

- 原始 Markdown 是唯一文档模型。编辑 Controller 和块范围使用 Dart 字符串的 UTF-16 偏移；语法预算降级的大小使用 UTF-8 字节，两者不能混用。
- 阅读态 `onSelectionChanged` 提供选择内容及阅读态范围，不保证是原始 Markdown 的精确偏移；需要编辑或源码导航时使用编辑 Controller / 源码范围接口。
- 正文 `data` 变化重新构建解析；阅读选择会随源码变化失效，不承诺增量 AST。View 的 `data`、`syntaxPreset`、`showFrontMatter` 或预算变化会重新解析并安排滚动回到顶部。
- Live 在纯选区/composing 变化时复用文档结构，文本变化、撤销/重做与替换 Controller 时重新更新结构。Controller 自身还维护引用上下文。解析次数减少不代表所有布局成本已经消除。
- 模式切换使用同一 Controller 的原文、dirty 和历史。Live 与 Reading 的选区是不同交互面，不保证恢复阅读态的拖选区域或所有模式的滚动像素位置。
- 持续追加和异步资源遵守 [R2-03 宿主接入](INTEGRATION_GUIDE.md#持续追加内容r2-03)：正文可由宿主跟随/暂停滚动，View 默认更新回到顶部；旧阅读选择不跨源码版本保留。资源结果按文档、版本和资源身份隔离，资源缓存仍由宿主管理。
- 没有独立的 document ID API。推荐每个文档持有一个 Controller，宿主保存文档身份并用稳定 Key 区分文档。直接替换 `controller.text` 不会自动重置历史或保存基线。

## Source 范围导航与只读展示（R4-05 P1a）

`IanvsMarkdownEditor` 新增可选的 `highlightedRange`（默认 null）与 `readOnly`（默认 false）。
默认编辑行为和 Controller API 不变；查找查询、结果集与替换仍由宿主管理。

- `IanvsMarkdownSourceHighlight(source: snapshot, range: TextRange(...))` 是不可变请求。
  `source` 必须等于当前 Controller 原文；`range` 使用 UTF-16 偏移且必须非空、正向、有效并在文本内。
  快照不一致、越界、负值、反向或空范围会被忽略，不夹紧到另一个可能错误的位置。
- 每个新的请求实例在布局后把准确源码范围滚入 Source 视口，不修改 Controller 的文本、
  选区、composing、dirty 或历史，也不主动请求焦点。覆盖多行且高于视口的匹配定位到起点。
  再次定位同一范围也要创建新实例；复用同一实例的普通 rebuild 不抢回用户滚动位置。
- 高亮独立于输入框焦点与源码语法高亮；查询框可以持续持有焦点。高亮跟随实际源码排版、
  换行和滚动，设为 null 立即清除而不恢复旧滚动位置。它不是阅读投影范围或第二份选区。
- 原文编辑、撤销/重做造成的文字变化及 Controller 替换使已接受的请求失效；撤回到旧文字也不会
  复活旧请求。宿主须基于最新原文计算并发送新实例。延迟导航会检查实例、原文、Controller、
  滚动对象与挂载状态。替换 ScrollController 保留 Flutter 自身的位置迁移行为，不承诺回顶。
- `readOnly: true` 与 Controller.mode 独立，包括 Controller 仍为 Reading 时直接展示 Source。
  完整原文可以选择和复制；输入、剪切、粘贴、删除、格式化和用户 Undo/Redo 不修改原文。
  编辑工具栏不显示，修改命令在 Source 边界被消费；selectAll/copy、保存和模式命令保留。
  保存沿用 `onSaveRequested`；`enableModeShortcuts: false` 仍抑制模式按键，但不抑制
  `IanvsMarkdownShortcuts.invoke` 的显式模式操作。不要把只读当成 Controller 的权限或不可变性。
- 宿主仍持有唯一 Controller，并可程序更新文字和历史。只读只限制本 Source 的用户编辑路径；
  明确配置的宿主回调或其他编辑面仍由宿主管理。正在等待剪贴板的源码智能链接粘贴会在原输入面
  被替换、卸载或改为只读后取消，不能把迟到结果写入当前只读面。

自动证据见 [Source 查找面回归](../test/source_search_surface_test.dart)，包含焦点保留、
重复/清除/失效、对象替换、只读命令与迟到粘贴。macOS/Linux 的 widget 平台变体不等于
原生菜单、系统输入法或真实剪贴板的物理验收。

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

默认降级 UI 显式提示纯文本和截断状态；提示不参与文档选择或复制，完整原文仍由 controller / data 保留。自定义 `fallbackBuilder` 接管整个降级显示，不额外插入默认提示。Live 的源码回退在编辑区上方提示；Reading 提示是否只展示前缀。

默认 `IanvsMarkdownRenderBudget` 同时限制全文 1,048,576 个 UTF-16 单元、每行 4,096 个 UTF-16 单元、4,096 个语法 token，以及最多 64 KiB UTF-8 的显示降级前缀。长度与 token 在昂贵解析前检查，限额本身允许通过，超过才降级。按 LF 分行，CRLF 中的 CR 不计入行长；单独的 CR 计入行长，以覆盖仍按 LF 分行的解析器。全文长度优先报告，之后按扫描时首次超限报告行长或 token；`budgetExceeded` 不代表其他限额都未超出。

| 入口 | 预算与可观察结果 | 超限行为 |
| --- | --- | --- |
| 正文 | `renderBudget`；`fallbackBuilder(context, decision)` | 不调用 Markdown/宿主 builder，展示有界纯文本 |
| View / Document | `renderBudget` / `IanvsMarkdownDocument.parse(budget: ...)`；`fallbackBuilder` / `parseDecision` | 在 YAML、标题、大纲与折叠解析前检查完整原文；保留原始 `body`，元数据与标题为空，显示包括 YAML 的原文前缀 |
| Controller / Source | 构造时固定 `parseBudget`；`parseDecision` 在文本改变时更新；原有 Controller 监听可观察 | 跳过引用和语法高亮；Source 背景也跳过结构解析，仍完整编辑/保存原文。选择和 composing 变化复用决定，撤销/重做重新判断实际文本 |
| Live | `renderBudget` 在引用、跨段高亮、脚注、块与标题之前检查全文；`onRenderDecision` 在帧后报告最新决定 | Live 保留 Controller.mode 并改用完整源码编辑；不创建部分块映射。缩短后恢复 Live，组合输入期间延后恢复；保留焦点、输入连接及选择。Reading 由 View 降级 |
| 标题/折叠解析辅助函数 | `parseMarkdownHeadings`、`HeadingFoldModel.parse/fromBlocks` 的 `budget`；折叠模型的 `budgetExceeded` | 标题列表为空；折叠模型保留原文且没有块和标题。直接调用 `parseMarkdownHeadings` 时可先用公开扫描函数获取原因 |
| 阅读复制 / 独立转换 | 三种渲染入口的 `clipboardBudget`、转换函数的 `budget`；payload 的 `budgetExceeded`、`hasHtml`，或 HTML 函数的 `onBudgetExceeded` | 检查原文、额外 HTML 来源及所选文本；超限跳过 Markdown 和 DOM 转换。整篇保留精确原文，局部保留完整可见所选纯文本，`html` 为空 |
| Markdown 输入格式器 | `IanvsMarkdownEditingFormatter(budget: ...)`；Source / Live 的输入格式器使用 Controller 的预算 | 旧值或新值超限时不改写输入，IME composing 总是原样通过 |

Controller 创建早于 Widget，因此 `parseBudget` 与 `renderBudget` 独立；需要相同策略时由宿主传入同一对象。`clipboardBudget` 独立于显示额度，小显示前缀不要求小复制额度。每个参数都可用 `null` 显式关闭该操作的保护，不会隐式关闭其他预算。独立转换函数同样默认有预算；`ianvsMarkdownDocumentClipboardData` 是保留完整原文及降级原因的整篇复制入口。HTML 转换继续按 GFM 语义处理，不复刻自定义 Widget。

UTF-8 显示前缀不切开有效 Unicode 码点；无效代理单元在显示中使用替换字符，原始文档和复制字符串不改写。`maxFallbackBytes` 只作用于显示，不能用它截断存储、保存或复制。

输入限额不是进程内存或硬性执行时间限制；它限制送入内置昂贵解析器的输入，不保护任意宿主 builder、自定义语法、图片解码，也不限制完整源码的 Flutter 排版或操作系统复制负载。直接调用低层源码投影/扫描工具的宿主仍需先预算输入；不能把所有公共辅助函数视为一个受控 AST 服务。Source 和 Live 降级后的完整文本排版仍需 R2-01 归因验收；历史使用独立的 R2-02 策略。

图片默认显示占位，不自动读取文件或网络；图片、Wiki 嵌入、链接导航和图表后端的权限、解码、缓存及过期结果由宿主负责。R1-04 将 `super_clipboard` 移到可选适配器；核心默认 writer 通过 Flutter 只写完整 Markdown，预算允许时提供 HTML；`hasHtml == false` 的 writer 必须省略 HTML 格式，可选适配器已处理该路径。现有必填参数保留，默认输出格式有显式变更，见 [迁移说明](INTEGRATION_GUIDE.md#剪贴板迁移r1-04)。参考 [剪贴板](../lib/src/rich_clipboard.dart)、[预算](../lib/src/render_budget.dart)。

## 撤销历史容量（R2-02）

`IanvsMarkdownController.historyPolicy` 默认是 `IanvsMarkdownHistoryPolicy(maxEntries: 200, maxTextBytes: 32 * 1024 * 1024)`。这是一项 **Unreleased 行为变更**：此前无限保留，升级后旧快照会被裁剪。依赖完整历史的宿主可以显式传入 `historyPolicy: null` 保持旧行为，也可以创建 Controller 时提供不同限额；运行中不支持替换策略。

```dart
final bounded = IanvsMarkdownController(
  text: initialMarkdown,
  historyPolicy: const IanvsMarkdownHistoryPolicy(
    maxEntries: 100,
    maxTextBytes: 16 * 1024 * 1024,
  ),
);
final legacy = IanvsMarkdownController(text: initialMarkdown, historyPolicy: null);
```

- 条目包含撤销、当前和重做快照；200 条最多产生 199 步撤销，连续输入合并后算一个快照。`maxEntries: 1` 仅保留当前状态。
- 文本容量按每个快照的 `text.length * 2` 求和，即 UTF-16 计费字节。`中` 为 2，`😀` 为 4；与降级文本的 UTF-8 限额不同。不去重共享字符串，不包含对象开销、解析缓存及单独保留的保存基线，因此不是 Dart 堆或进程 RSS 的硬上限。
- 每次文字改变后，先释放被新编辑替代的 redo 分支，再更新输入分组，最后裁掉最旧的连续前缀，直到同时满足两个限额。撤销/重做本身不改变保留集合。
- 当前快照始终完整保留。如果当前文本本身超过字节限额，保留它作为唯一状态，不能撤销；缩小文本后也不会重新获得已裁剪的超大快照。`maxTextBytes: 0` 同样只保留当前状态，不截断用户原文。
- `retainedHistoryEntries` / `retainedHistoryTextBytes` 提供当前计数。选择/composing-only 更新不增加计费量；文字变化沿用既有输入分组，历史恢复会清除 composing。该策略不重新定义“一次 IME 会话等于一次撤销”。
- 保存基线独立于历史。保存点被裁剪不表示文件已保存，dirty 仍用当前原文与最近确认的 `savedText` 比较；异步保存契约不变。`clearHistory()` 只保留当前状态并重置计数，不改变 dirty 或保存基线。

默认值是可配置的容量起点，优先限制长期编辑持有的完整快照；不是最佳性能承诺。约 1 MiB ASCII 文档每个快照计费约 2 MiB，默认字节限额通常会先于 200 条上限生效。回归覆盖 [历史策略](../test/history_policy_test.dart)、[编辑 Controller](../test/editor_controller_test.dart) 和 [异步宿主保存](../test/host_contract_test.dart)。

## 对象与保存

生命周期、异步保存及文档切换的可运行示例见 [接入指南](INTEGRATION_GUIDE.md)。关键契约如下：

- 宿主传入的文档 Controller、FocusNode、ScrollController 不由组件释放；组件仅释放自己创建的焦点、滚动和内部对象。
- 保存回调收到触发时捕获的原文。正常完成后，内置工具栏/快捷键调用 `markSaved(savedText: capturedText)`；保存期间的后续编辑仍为 dirty。回调不得再次无条件 `markSaved()` 覆盖这个基线。
- `IanvsMarkdownSaveCancelledException` 表示未确认保存，内置保存保持 dirty；其他异常不被吞掉。宿主负责报告错误、串行化写入和处理文档身份。
- 文档已释放后到达的 `markSaved` 确认被忽略；这不取消已经开始的存储操作，也不允许继续使用其他已释放接口。该修复属于当前 `Unreleased`。

## 公共导出承诺与分层

入口是 `package:ianvs_markdown/ianvs_markdown.dart`。R1-01 用 Dart AST 审查直接导出及 show/hide 规则，并用 Flutter 编译探针核对符号；后续新增的文案及键盘五种类型由公共入口 widget 回归验证。清单现在包括 172 个项目符号和 11 个第三方重导出；不包含实例成员清单。

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

`IanvsMarkdownController`、`IanvsMarkdownEditingFormatter`、`IanvsMarkdownHistoryPolicy`、`IanvsMarkdownHistoryValue`、`IanvsMarkdownInlineMathSource`、`IanvsMarkdownSyntaxTheme`、`buildMarkdownSourceTextSpan`、`ianvsMarkdownInlineLinkSources`、`ianvsMarkdownInlineMathSources`

### [lib/src/editor/editor_models.dart](../lib/src/editor/editor_models.dart)

`IanvsMarkdownBlock`、`IanvsMarkdownBlockType`、`IanvsMarkdownEditorMode`、`IanvsMarkdownHeadingNavigation`、`ianvsMarkdownTableBodyContinues`、`markdownBlockAtOffset`、`markdownGapLineCount`、`parseMarkdownBlocks`

### [lib/src/editor/editor_shortcuts.dart](../lib/src/editor/editor_shortcuts.dart)

`IanvsMarkdownEditorShortcuts`

### [lib/src/editor/editor_toolbar.dart](../lib/src/editor/editor_toolbar.dart)

`IanvsMarkdownEditorToolbar`、`IanvsMarkdownSaveCallback`、`IanvsMarkdownSaveCancelledException`

### [lib/src/editor/live_editor.dart](../lib/src/editor/live_editor.dart)

`IanvsMarkdownLiveEditor`

### [lib/src/editor/source_editor.dart](../lib/src/editor/source_editor.dart)

`IanvsMarkdownEditor`、`IanvsMarkdownSourceHighlight`、`ianvsMarkdownSyntaxTheme`

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

### [lib/src/link_target.dart](../lib/src/link_target.dart)

`IanvsMarkdownLinkKind`、`IanvsMarkdownLinkTarget`、`IanvsMarkdownTapLinkTargetCallback`

### [lib/src/markdown_document.dart](../lib/src/markdown_document.dart)

`IanvsMarkdownDocument`、`IanvsMarkdownHeading`、`parseMarkdownHeadings`

### [lib/src/keyboard.dart](../lib/src/keyboard.dart)

`IanvsMarkdownCommand`、`IanvsMarkdownShortcuts`

### [lib/src/localization.dart](../lib/src/localization.dart)

`IanvsMarkdownLocalization`、`IanvsMarkdownStrings`、`IanvsMarkdownMessage`

### [lib/src/math.dart](../lib/src/math.dart)

`IanvsMarkdownDisplayMathSyntax`、`IanvsMarkdownInlineDisplayMathSyntax`、`IanvsMarkdownInlineMathSyntax`、`IanvsMarkdownMath`、`IanvsMarkdownMathBuilder`、`IanvsMarkdownMathElementBuilder`

### [lib/src/obsidian_image.dart](../lib/src/obsidian_image.dart)

`IanvsMarkdownImageDimensions`、`IanvsMarkdownImageEditHandler`、`IanvsMarkdownImageResizeHandler`、`IanvsMarkdownImageResizeRequest`、`IanvsMarkdownImageSourceSyntax`、`IanvsMarkdownInteractiveImage`、`IanvsMarkdownSizedImage`、`IanvsMarkdownStandardImageSource`、`IanvsMarkdownStandardImageSourceSyntax`、`findIanvsMarkdownStandardImageSource`、`parseIanvsMarkdownImageDimensions`、`rewriteIanvsMarkdownImageWidth`、`rewriteIanvsMarkdownWikiImageWidth`

### [lib/src/note_semantics.dart](../lib/src/note_semantics.dart)

`IanvsMarkdownNoteSemantics`、`IanvsMarkdownSourceReference`、`IanvsMarkdownSourceReferenceKind`、`IanvsMarkdownSourceTag`、`IanvsMarkdownSemanticIssue`、`parseIanvsMarkdownNoteSemantics`

### [lib/src/obsidian_inline.dart](../lib/src/obsidian_inline.dart)

`IanvsMarkdownCodeSpanPresentation`、`IanvsMarkdownCodeSpanSyntax`、`IanvsMarkdownEntityPresentation`、`IanvsMarkdownEntitySyntax`、`IanvsMarkdownRenderedWhitespaceSyntax`、`IanvsMarkdownTagSyntax`、`IanvsMarkdownWikiLinkPresentation`、`IanvsMarkdownWikiLinkSyntax`、`ianvsMarkdownTagRanges`

### [lib/src/obsidian_metadata.dart](../lib/src/obsidian_metadata.dart)

`IanvsMarkdownEditingCommentBlockSyntax`、`IanvsMarkdownEditingFootnoteDefinitionSyntax`、`IanvsMarkdownEditingMetadataBuilder`、`IanvsMarkdownEditingMetadataInlineSyntax`、`IanvsMarkdownFootnoteSuperscriptBuilder`、`IanvsMarkdownLivePreviewFootnoteReference`、`IanvsMarkdownObsidianMetadataMode`、`collectObsidianStandardFootnoteOrdinals`、`ianvsMarkdownBlockIdRanges`、`ianvsMarkdownCommentRanges`、`ianvsMarkdownLivePreviewFootnoteReferences`、`prepareObsidianFootnoteDefinitionForEditing`、`prepareObsidianMarkdownForRendering`、`projectObsidianInlineLinkDestinationBackslashesForRendering`、`projectObsidianReferenceImagesForLivePreview`

### [lib/src/render_budget.dart](../lib/src/render_budget.dart)

`IanvsMarkdownRenderBudget`、`IanvsMarkdownRenderDecision`、`IanvsMarkdownBudgetExceeded`、`scanMarkdownForRendering`

### [lib/src/rich_clipboard.dart](../lib/src/rich_clipboard.dart)

`IanvsMarkdownClipboardData`、`IanvsMarkdownClipboardWriter`、`ianvsMarkdownDocumentClipboardData`、`ianvsMarkdownClipboardHtml`、`ianvsMarkdownSelectionClipboardData`、`ianvsPlainTextClipboardHtml`、`writeIanvsMarkdownClipboard`

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


### 模式切换后的输入连接

当焦点原本在 LiveEditor 内时，模式切换保留选择并在新编辑 surface 挂载后重新连接文本输入。
Read 本身不持有可编辑输入连接。使用 mode 快捷键或原生菜单返回 Source / Live 后无需额外点击
即可继续输入；异步回调检查模式代次、controller 和 FocusNode 身份。两个主应用的输入协议回归
覆盖组合确认、候选取消、Read 往返和撤销/重做；真实 macOS 候选窗口需另外留证。
