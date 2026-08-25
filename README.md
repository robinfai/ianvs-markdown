# ianvs_markdown

从 `ianvs-acp` 抽离并继续演进的 Flutter Markdown 渲染与编辑组件。它保留了原有的阅读体验，同时去掉了对 ACP 状态、工作区文件系统和特定 Mermaid 实现的耦合。

## 能力

- GitHub Flavored Markdown、可选择文本、表格与任务列表
- 对齐 Obsidian Border 主题点阵、虚线框、亮暗语法色、可复制语言标签、四列 Tab、折行和活动行轨道的代码块
- YAML front matter 信息卡和可折叠文档大纲
- 普通链接、文件引用、Obsidian Wiki 链接、块级嵌入与层级标签的区分展示
- Obsidian `==高亮==` 与可折叠、分类型着色的 Callout 卡片
- Obsidian `%%注释%%`、块 ID、标准脚注与 `^[内联脚注]`
- Mermaid、自定义图片和额外元素 builder 注入点，以及 Obsidian 图片尺寸语法
- Markdown 语法预算和 UTF-8 有界纯文本降级
- 通过 `ThemeExtension` 支持亮色、暗色和宿主自定义主题
- 默认不读取本地文件、不发起网络请求
- 类 Obsidian 的块级实时预览、完整源码和阅读三种模式
- 源码保真的原地编辑、Markdown 快捷键和列表自动续写
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

实时预览会保留当前标题或段落的排版层级，仅在光标进入粗体、斜体、普通链接、Wiki 链接或 `==高亮==` 范围时揭示对应定界符；`[[目标|别名]]` 在非活动状态只显示别名，`![[目标#标题]]` 显示为宿主解析的透明嵌入区域，并同时保留外层嵌入竖线与内层标题级别竖线。点击嵌入正文会在内容上方恢复该块的精确源码，右上角打开按钮则只触发 `onTapLink`，`#project/flutter` 显示为层级标签胶囊。文首 YAML 在紧凑模式下显示为 Obsidian 风格的“笔记属性”：原始键名和值同排，布尔值显示勾选状态，数字与日期保留类型标识，日期使用 `YYYY / MM / DD`，别名、标签、普通列表和 Wiki 链接列表各自使用对应的行内样式，嵌套对象保留紧凑 JSON，显式空值显示“没有值”；折叠时只保留标题行，点击属性区域仍会进入完整 front matter 源码编辑。标题左侧的折叠控件按层级隐藏正文和更深级标题，遇到下一个同级或更高级标题时停止；父标题重新展开后会保留子标题原有折叠状态，Live Preview 与阅读模式共享该状态，点击大纲中的隐藏标题会先展开其祖先。`%%编辑注释%%`、行尾 `^block-id`、标准脚注引用和 `^[内联脚注]` 在实时预览中保留源码并弱化显示，标准脚注定义按首次引用顺序显示为列表；切换到阅读模式后，注释与块 ID 被移除，标准和内联脚注共用文末脚注区。围栏代码与行内代码中的同形文本始终保持字面值。`> [!note]` Callout 在非活动状态显示类型色、图标与标题，`+`/`-` 折叠标记控制初始展开状态；点击折叠箭头只改变卡片状态，点击正文才进入整块精确源码编辑。连续列表按单项进入编辑，活动项继续显示圆点或编号并隐藏源码前缀；多行引用与活动 Callout 同样保留引用竖线并隐藏每一行的 `>`。Tab/Shift+Tab 调整层级后保持原光标或选区。任务框和表格单元格直接更新其原始 Markdown 区间，因此周围空格、分隔符和表格对齐行不会被重新序列化。任务项进入编辑后仍显示可操作复选框并隐藏 `- [ ]` 标记；已完成任务的正文显示删除线，按 Enter 续写时新任务恢复为未勾选状态。表格使用 16 px 外围控件带：桌面端悬停首列或首行外侧的握柄可拖动整行或整列，拖动时显示整行/整列选区与落点线；移动端只显示当前单元格对应的两个握柄。拖拽、增行或增列后会像 Obsidian 一样重建等宽、带首尾竖线的表格源码，并让列对齐规则随列移动；每次结构操作都可独立撤销。下方增行、右侧增列控件会自动聚焦新增单元格。表格键盘流支持 Tab、Shift+Tab 和方向键跨格；Enter 或末格 Tab 新增尾行，首格 Shift+Tab 新增顶部行。围栏代码在阅读、实时预览和完整源码模式共享 Border 主题的 4 × 4 点阵底纹、1 px 虚线框、4 px 圆角、14 px 字号及亮暗语法色；阅读态复制图标仅在桌面悬停时出现、移动端常显，并用一秒绿色勾确认。实时预览的语言标签会像 Obsidian `code-block-flair` 一样持续显示并可直接复制代码，无语言时改用复制图标；块进入活动编辑后仍保留该 flair、可编辑围栏、精确源码偏移和当前视觉行轨道。长文档大纲跳转会先定位尚未构建的虚拟块，再精确滚动到目标标题。

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
