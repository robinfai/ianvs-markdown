# ianvs_markdown

从 `ianvs-acp` 抽离并继续演进的 Flutter Markdown 渲染与编辑组件。它保留了原有的阅读体验，同时去掉了对 ACP 状态、工作区文件系统和特定 Mermaid 实现的耦合。

## 能力

- GitHub Flavored Markdown、可选择文本、表格与任务列表
- 对齐 Obsidian Border 主题点阵、虚线框、亮暗语法色、可复制语言标签、四列 Tab、折行和活动行轨道的代码块
- 阅读、实时预览与源码模式共享 Border 点阵、3 px 内缩强调轨和 4 px 圆角的引用块，以及 2 px 水平分隔线
- 阅读渲染与实时预览使用 Border 的 16 px 任务框、6 px 圆角、亮暗八色、悬停/焦点环、粗勾形和完整自定义任务状态
- 阅读渲染与实时预览共享 Border 的 1 px 嵌套列表引导线和 28 px 层级步进，活动列表项也保持结构缩进
- YAML front matter 信息卡和可折叠文档大纲
- 普通链接、文件引用、Obsidian Wiki 链接、块级嵌入与层级标签的区分展示
- Obsidian `==高亮==` 与可折叠、分类型着色的 Callout 卡片
- Obsidian `%%注释%%`、块 ID、标准脚注与 `^[内联脚注]`
- Mermaid、自定义图片和额外元素 builder 注入点，以及 Obsidian 图片尺寸语法
- Markdown 语法预算和 UTF-8 有界纯文本降级
- 通过 `ThemeExtension` 支持亮色、暗色和宿主自定义主题
- 默认不读取本地文件、不发起网络请求
- 类 Obsidian 的块级实时预览、完整源码和阅读三种模式
- 源码保真的原地编辑、Markdown 快捷键，以及按 Obsidian 层级退出、引用续行和 marker 后 Tab 边界工作的列表自动续写
- 光标邻近语法标记显隐、跨行 inline code 的双态空白语义、单列表项编辑和任务框原地切换
- 不暴露管道源码的 GFM 表格单元格编辑
- 文档级 dirty 状态、撤销/重做和显式保存回调

## 使用

在应用的 `pubspec.yaml` 中添加路径依赖：

```yaml
dependencies:
  ianvs_markdown: ^0.1.0
```

聊天消息或卡片内使用非滚动组件：

```dart
IanvsMarkdown(
  data: message,
  onTapLink: (text, href, title) {
    // 由宿主决定如何打开链接。
  },
)
```

完整文档使用带滚动、大纲和 front matter 的组件。父级需要提供有限高度：

```dart
Expanded(
  child: IanvsMarkdownView(
    data: document,
    imageBuilder: (uri, title, alt) {
      return MyApprovedImage(uri: uri);
    },
    diagramBuilder: (context, source) {
      return MyMermaidView(source: source);
    },
  ),
)
```

默认图片 builder 只显示安全占位，不会自动访问网络或文件系统。宿主注入 `imageBuilder` 后，应自行完成路径授权、大小限制、解码预算和远端加载确认。标准图片支持 Obsidian 的 `![替代文本|250](image.png)`、`![替代文本|100x145](image.png)` 和外部图片简写 `![250](https://example.com/image.png)`；有效尺寸会从传给宿主的 `alt` 中移除，并以逻辑像素约束宿主返回的图片组件。无效尺寸保持为普通替代文本。

无显式别名的 Wiki 锚点在 Live Preview 中保留 `[[Note#Heading]]` 的 `Note#Heading` 标签，阅读态显示为 `Note > Heading`；本地 `[[#Heading]]` 在两种模式下都只显示 `Heading`。宿主可同步提供 `wikiLinkExists`，让缺失目标使用 Obsidian 风格的紫色无下划线样式：

```dart
IanvsMarkdown(
  data: document,
  wikiLinkExists: (target) => repository.wikiTargetExists(target),
)
```

回调收到不含方括号、但保留路径、标题或块后缀的完整目标。未注入回调时，链接保持默认已解析外观，组件不会自行查询文件系统。

Obsidian 风格的行内 `$…$`、同行 `$$…$$` 与独占行的块级 `$$` 公式默认由纯 Flutter TeX 渲染器处理，不访问网络或文件系统。转义美元符、货币文本和代码范围保持字面值；无效 TeX 使用可见错误回退。宿主也可以替换公式渲染：

```dart
IanvsMarkdown(
  data: document,
  mathBuilder: (context, expression, {required displayMode}) {
    return MyMathView(expression, displayMode: displayMode);
  },
)
```

Live Preview 中行内公式仅在光标进入范围时揭示定界符；块级公式进入编辑后保留上方精确源码和下方预览。

独占一行的 `![[Note]]`、`![[Note#Heading]]` 和 `![[Note#^block]]` 会渲染为带强调竖线与打开按钮的 Obsidian 风格嵌入。组件负责解析引用和外观，实际内容仍由宿主解析：

```dart
IanvsMarkdown(
  data: document,
  onTapLink: openLink,
  wikiEmbedBuilder: (context, reference) {
    final embeddedMarkdown = repository.resolveWikiEmbed(reference);
    return IanvsMarkdown(
      data: embeddedMarkdown,
      onTapLink: openLink,
      fitContent: true,
    );
  },
)
```

`IanvsMarkdownWikiEmbedReference` 会分别提供完整 `target`、笔记路径 `note`、标题或块目标 `subpath` 以及可选 `alias`。图片嵌入还支持 `![[image.png|250]]` 和 `![[image.png|替代文本|100x145]]`，回调可通过 `isImageEmbed`、`width` 与 `height` 读取解析结果；宿主返回的图片组件会受到对应尺寸约束。普通笔记的数字别名不会被当作图片尺寸。未注入 `wikiEmbedBuilder` 时显示安全的引用占位，不会读取文件或访问网络。

在桌面端 Live Preview 中，宿主成功解析的标准图片和 Wiki 图片会在悬停时显示右下角缩放柄。拖拽保持当前宽高比，宽度限制在 `20` 到编辑区可用宽度之间；松开后只把整数宽度写回 `|宽度`，双击缩放柄则移除有效尺寸。拖拽和重置各自形成独立撤销项。阅读模式、源码模式和移动端不显示该控件，安全占位也不会因此触发任何图片 I/O。

## 编辑与实时预览

`IanvsMarkdownController` 是编辑状态的唯一数据源，管理文本、选区、模式、dirty 状态和撤销历史。`IanvsMarkdownLiveEditor` 会把当前块显示为原始 Markdown，其余块继续使用渲染组件：

行内源码边界遵循 Obsidian Live Preview：光标到达起始定界符前即揭示完整范围，越过闭合定界符后立即重新隐藏；双击格式化内容会连同定界符选中完整源码。普通 Markdown 链接支持空目标、`<…>` 目标、平衡或转义括号、双引号/单引号/括号 title，以及 title 前的 soft break；destination 中奇数反斜线 run 的最后一条继续转义括号，前面的每一对会在链接目标中保留为 `%5C`，Live Preview 激活后仍恢复精确源码。角括号内的 `http`、`https`、email、`mailto`、`ftp` 与 `obsidian` scheme 会先于安全 raw-HTML fallback 解析，并在 Live Preview 激活后恢复完整角括号源码。`<www.example.com>` 采用 Obsidian 的非标准回退：前导 `<` 保持字面值，`www.example.com>` 成为 bare-link label，尾随 `>` 在回调目标中编码为 `%3E`；普通 `www` 链接不变。只有 Reading parser 确认识别的完整语法才会在非活动状态隐藏，未闭合 title 与多余尾随字符保持源码并允许合法 shortcut reference 回退。full、collapsed 和 shortcut reference 共享文档定义映射，label 大小写不敏感；实测 `[Whitespace   Ref][  Ref   A  ]` 这类同时含周围空白与内部连续空白的 secondary label 会保持字面值。首个重复定义优先级和 block-local definition 注入保持一致。普通 Markdown 链接单击进入源码编辑而不导航，Wiki 链接单击交给宿主的 `onTapLink` 打开目标。

注释只配对未被奇数反斜线转义的 `%%`；未闭合 delimiter 保持字面源码，`%%%%` 为空注释，连续 `%` 的余留字符保持可见。独立注释可跨空行作为一个 Live Preview 编辑块，行内代码和围栏代码始终优先于注释解析。

标签词法与 Obsidian 对齐：标签通常从文首或空白后开始，也接受实测的全角冒号起始边界，并允许 `#one#two` 这样的相邻标签；内容支持 Unicode、emoji 和 `/` 路径，但不能只有 ASCII 数字。ASCII 标点及 Obsidian 排除的两个 Unicode 标点区会结束标签，全角标点等范围外字符仍可成为标签的一部分；奇数个反斜线转义 `#`，偶数个则恢复解析。阅读态和非活动 Live Preview 显示标签胶囊，活动块恢复精确 Markdown 源码，点击标签仍通过 `onTapLink` 交给宿主。

`==高亮==` 同样使用 Obsidian 1.13.7 的边界：inner 首尾为空格或 Tab、空内容和纯空白内容都保持字面值；合法闭合高亮可以跨一个 soft break，但不能跨空行，未闭合 opening 只着色到当前物理行末。Reading 每侧只隐藏成对的两个 `=` 并保留 surplus，非活动 Live Preview 会隐藏参与语法的完整等号 run，活动块恢复精确源码；`==one====two==` 仍是两个相邻高亮。奇偶反斜线、行内/围栏代码和注释优先级在渲染与源码着色中一致，普通链接和 Wiki alias 内也能叠加高亮，双击正文会选中完整 delimiter 范围。

粗体与斜体使用 Obsidian 1.13.7 的 delimiter-run、左右 flanking 和 rule-of-three 语义：星号允许 `foo*bar*baz` 这样的 intraword emphasis，单/双下划线在 `foo_bar_baz`、`foo__bar__baz` 中均保持字面值；inner 首尾空格或 Tab、奇偶反斜线、soft break 与空段落边界也按实测解析。长 run 在 Reading 与非活动 Live Preview 有意采用不同投影：对称 4/5/6/7 星号在 Reading 分别显示 `**strong**`、`*em*`、`**strong-em**`、`***plain***` 的可见 surplus，而 Live Preview 分别保留 1/2/3/0 枚 marker，并使用 em/strong/两者/plain 样式；2/4、4/2、3/4、4/3、3/2、2/3、4/1、1/4 与 6/9 非对称 run 也保留各自实测 surplus。strong/em 可与 highlight、strikethrough、普通链接、Wiki alias 和标签叠加，代码与 `%%注释%%` 优先；源码 token 与 delimiter stack 共用扫描结果，双击三星号正文会选择完整 `***source***`。

删除线按 Obsidian 的双波浪号规则解析：`~single~` 始终是字面值，inner 首尾空格或 Tab 会使闭合 pair 失效；奇数 run 在 Reading 保留一枚 surplus，偶数 pair 可继续消费，4/2 与 2/4 的多余 pair 显示在删除线正文之后，`~~one~~~~two~~` 则形成两个相邻删除线。非活动 Live Preview 会隐藏参与语法的完整连续 run，包括 Reading 可见的 surplus；闭合 pair 可跨 soft break，未闭合 opening 只作用到当前物理行末，空行终止范围。奇偶反斜线、strong/emphasis/highlight、普通链接、Wiki alias、标签以及行内/围栏代码和注释的优先级均与实测一致，双击删除线正文会选中完整 `~~source~~` 范围。

块 ID 支持字母、数字、连字符和下划线，可位于块末或独占一行；独占标记会与最近的前一个段落、标题、列表、引用、Callout、表格、分隔线或公式块保持同一编辑块，即使两者之间保留空行。有效标记必须由空白分隔，marker 后允许保留 ASCII 空格；点号、冒号、中文、空 `^` 和行末标点仍保持字面值，同一行存在多个候选时只隐藏最后一个。奇数反斜线转义 `^`，偶数反斜线保留斜线并继续识别块 ID，行内代码、围栏代码、URL 和 Wiki 块引用始终优先。

实时预览会保留当前标题或段落的排版层级，仅在光标进入粗体、斜体、普通链接、Wiki 链接或 `==高亮==` 范围时揭示对应定界符；`[[目标|别名]]` 在非活动状态只显示别名，`![[目标#标题]]` 显示为宿主解析的透明嵌入区域，并同时保留外层嵌入竖线与内层标题级别竖线。点击嵌入正文会在内容上方恢复该块的精确源码，右上角打开按钮则只触发 `onTapLink`，`#project/flutter` 显示为层级标签胶囊。只有文档字节 0 的 `---` mapping 与 closing `---` 会在紧凑模式下形成 Obsidian 风格的“笔记属性”；closing `...`、空 mapping、未闭合、top-level list 和正文内分隔线都不显示面板，其中合法空 mapping 在 Reading 与 Live Preview 中也不会把定界符显示成横线。属性默认展开并严格保留源码 key 顺序，`title` 仍是普通属性行而不会自动提升成正文标题；布尔值显示勾选状态，数字与日期保留类型标识，日期使用 `YYYY / MM / DD`，aliases、tags、`cssclasses` 和普通列表使用各自的行内样式，单值 Wiki/URL 显示为链接，嵌套对象保留紧凑 JSON，显式空值显示“没有值”。`IanvsMarkdownLiveEditor` 的普通文本属性可以原地输入：Enter 或失焦以单次可撤销编辑提交，Escape 取消尚未提交的文字；布尔属性点击后立即写回 `true`/`false`；数字属性使用有限数值输入，Tab 或失焦提交，非法或非有限值会恢复原值并保持 YAML number 类型。完整字符串属性名也可原地重命名：Tab、Enter 或失焦提交，Escape 取消，空、重复、截断或非字符串 key 不会写回，YAML 易歧义名称会自动加引号。文本、数字与属性名提交会像实测 Obsidian Properties 一样把 top-level inline scalar list 规范化为 block list，同时保持 key 顺序和未编辑 scalar 源码；点击类型图标或非交互空白仍可进入完整 front matter 源码编辑。标题左侧的折叠控件按层级隐藏正文和更深级标题，遇到下一个同级或更高级标题时停止；父标题重新展开后会保留子标题原有折叠状态，Live Preview 与阅读模式共享该状态，点击大纲中的隐藏标题会先展开其祖先。`%%编辑注释%%`、行尾 `^block-id`、标准脚注引用和 `^[内联脚注]` 在实时预览中保留源码并弱化显示，标准脚注定义按首次引用顺序显示为列表；标准 label 大小写不敏感，重复定义以后出现者为准，首个引用显示 `[N]`、后续显示 `[N-k]`，并为每次引用保留独立 backlink。切换到阅读模式后，注释与块 ID 被移除，标准和内联脚注共用文末脚注区。围栏代码与行内代码中的同形文本始终保持字面值。Callout type 对大小写不敏感，并接受 `]` 前的任意非空内容，因此 `.`、`/`、Unicode 与未知类型仍会形成 fallback 卡片；`>` 后只允许无空格或一个普通空格，Tab 与两个以上空格保持普通引用字面值。紧邻 `]` 的 `+`/`-` 控制初始展开状态，只有真实的无引用空行才结束当前 Callout；点击折叠箭头只改变卡片状态，点击正文才进入整块精确源码编辑。连续列表按单项进入编辑，活动项继续显示圆点或编号并隐藏源码前缀；活动普通引用保留竖线、只显示当前物理行的精确 `>` marker，活动 Callout 则显示整块每一行的 `>` 与完整 header 源码。`Cmd+A` 会一次选中整篇 Markdown；桌面鼠标可从任意文本块正向或反向拖过其他 block，建立保持原始 Markdown 偏移的连续选区，普通点击会收起该选区。Tab/Shift+Tab 调整层级后保持原光标或选区。任务框和表格单元格直接更新其原始 Markdown 区间，因此周围空格、分隔符和表格对齐行不会被重新序列化。任务项进入编辑后仍显示可操作复选框并隐藏 `- [ ]` 标记；复选框使用 16 px 可见尺寸、6 px 圆角、1 px 边框和 24 px 外环区，桌面悬停或键盘聚焦显示两像素外环，空格或回车可切换状态；已完成任务使用 Border 亮暗绿色粗勾，正文转为弱化色并显示删除线，按 Enter 续写时新任务恢复为未勾选状态。表格使用 16 px 外围控件带：桌面端悬停首列或首行外侧的握柄可拖动整行或整列，拖动时显示整行/整列选区与落点线；移动端只显示当前单元格对应的两个握柄。拖拽、增行或增列后会像 Obsidian 一样重建等宽、带首尾竖线的表格源码，并让列对齐规则随列移动；每次结构操作都可独立撤销。下方增行、右侧增列控件会自动聚焦新增单元格。表格键盘流支持 Tab、Shift+Tab 和方向键跨格；Enter 或末格 Tab 新增尾行，首格 Shift+Tab 新增顶部行。围栏代码在阅读、实时预览和完整源码模式共享 Border 主题的 4 × 4 点阵底纹、1 px 虚线框、4 px 圆角、14 px 字号及亮暗语法色；阅读态复制图标仅在桌面悬停时出现、移动端常显，并用一秒绿色勾确认。实时预览的语言标签会像 Obsidian `code-block-flair` 一样持续显示并可直接复制代码，无语言时改用复制图标；块进入活动编辑后仍保留该 flair、可编辑围栏、精确源码偏移和当前视觉行轨道。长文档大纲跳转会先定位尚未构建的虚拟块，再精确滚动到目标标题。

日期属性提供年、月、日分段输入和日历选择入口。与实测 Obsidian 一致，完整有效日期按 Return 才会以一次可撤销编辑写回并规范化 top-level inline scalar list；Tab 只移动焦点、保留界面暂态，不修改 Markdown。

属性名冲突按 Obsidian 的大小写不敏感规则处理：已有 `title` 时不能改成 `TITLE`，`count` 也不能只改成 `Count`；失败提交会恢复原属性名且不改变 YAML。

紧凑属性面板会对完整、纯文本且不超过 16 项的 `tags` 开放 chip 增删：删除立即写回，最后一项删除后保留精确空属性 `tags:`，从空属性输入后按 Tab 或 Enter 会重新生成 block list。含数字/布尔等 typed item、嵌套值、空字符串、超长或被展示上限截断的列表保持只读，仍可点击属性名进入完整 YAML，避免结构化 UI 覆盖未显示的源数据。

完整纯文本 `aliases` 列表使用不带标签底色的可编辑 chip：删除立即写回，删除最后一项后保留精确空属性 `aliases:`；从空值或已有列表输入后按 Tab、Return、Escape 或失焦会按原顺序生成 block list，并同步规范化其他安全的 top-level inline scalar list。首尾 ASCII 空格会被裁掉，纯空白或精确重复值不会写入；typed、嵌套、截断或超限 aliases 仍保持只读。

Obsidian 的任务状态不限于 `[ ]` 和 `[x]`。组件会原样保留任意单字符状态，未知字符使用普通绿色勾作为安全回退；Border 已定义的 `[/]`、`[-]`、`[>]`、`[<]`、`[?]`、`[!]`、`[*]`、`[i]`、`[I]`、`[l]`、`[b]`、`[n]`、`[p]`、`[c]`、`["]`、`[“]`、`[S]`、`[u]` 和 `[d]` 分别显示进度、取消、转发、日程、疑问、重要、星标、信息、想法、位置、书签、笔记、正负反馈、引用、储蓄及趋势图形。点击空状态写入 `x`，点击任意非空状态写回空格；有序任务续写时也会递增编号并创建 `[ ]`，不会重排或替换其他原始状态字符。

```dart
final controller = IanvsMarkdownController(
  text: source,
  mode: IanvsMarkdownEditorMode.livePreview,
);

Expanded(
  child: IanvsMarkdownLiveEditor(
    controller: controller,
    onChanged: (markdown) {
      // 更新宿主状态，但组件不会自行写文件。
    },
    onSaveRequested: (markdown) async {
      await repository.save(markdown);
    },
    imageBuilder: approvedImageBuilder,
    diagramBuilder: (context, source) => MyMermaidView(source: source),
    wikiEmbedBuilder: resolveWikiEmbed,
    wikiLinkExists: repository.wikiTargetExists,
  ),
)
```

也可以单独使用完整源码编辑器：

```dart
IanvsMarkdownEditor(controller: controller)
```

工具栏支持实时预览、源码和阅读模式切换，以及粗体、斜体、行内代码、链接、标题、列表、任务和代码块。编辑区支持 `Cmd/Ctrl+B`、`Cmd/Ctrl+I`、`Cmd/Ctrl+K`、`Cmd/Ctrl+S`、`Cmd/Ctrl+E`、撤销/重做和 Tab 缩进。

## macOS 示例应用

[example](example/) 是完整的 macOS Playground，覆盖实时编辑、三种模式、保存状态、主题、表格、代码块、基于 `merman` 的真实 Mermaid 注入和图片安全占位：

```sh
cd example
flutter pub get --offline
flutter run -d macos
```

示例应用不会落盘；“保存”按钮用于展示宿主应用如何接管持久化。

## 主题

可以为单个组件传入 `theme`，也可以注册到应用主题：

```dart
ThemeData(
  extensions: const <ThemeExtension<dynamic>>[
    IanvsMarkdownThemeData.light,
  ],
)
```

暗色界面可使用 `IanvsMarkdownThemeData.dark`；未注册扩展时组件会根据 `ThemeData.brightness` 自动选择默认值。

## 渲染预算

组件默认最多解析 4096 个 Markdown 语法 token。超限后会展示最多 64 KiB 的纯文本前缀，避免病理输入阻塞 UI。可信文档可以关闭预算：

```dart
IanvsMarkdown(data: trustedSource, renderBudget: null)
```

## 来源边界

首版基于 `ianvs-acp` 的 Markdown 代码块、链接、front matter 和文件预览实现整理。ACP 专属输入预算、图片解码账本、工作区路径校验和文件预览导航没有进入本包；对应能力改为通用预算或宿主注入点。

运行验证：

```sh
flutter test
flutter analyze
```
