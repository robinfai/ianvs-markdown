# 宿主接入与生命周期

先用 [能力矩阵](API_CONTRACTS.md) 选择入口：消息/正文使用 `IanvsMarkdown`，完整阅读使用 `IanvsMarkdownView`，源码输入使用 `IanvsMarkdownEditor`，三模式编辑使用 `IanvsMarkdownLiveEditor`。View/编辑器需要有界高度，例如放入 `Scaffold.body` 或 `Expanded`；正文的滚动由宿主布局提供。

可以直接运行 [正文](../example/lib/body.dart)、[阅读](../example/lib/reading.dart)、[完整编辑](../example/lib/editor.dart) 三个入口，命令与操作步骤见 [样例说明](../example/README.md)。它们只使用公开 API；编辑样例的存储为内存演示，实际文件或数据库写入由宿主替换。

## 谁创建，谁释放

| 对象 | 宿主提供 | 组件未收到该对象时 |
| --- | --- | --- |
| `IanvsMarkdownController` | Source/Live 必须提供，宿主在组件卸载后释放 | 不自动创建 |
| `FocusNode` | 四种入口使用但不释放；正文仅在整文档选择开启时使用，View 需启用选择；替换后旧对象归宿主 | 组件创建并释放 |
| `ScrollController` | View 的参数名为 `controller`，Source/Live 为 `scrollController`；均由宿主释放 | 组件创建并释放 |
| `IanvsMarkdownHeadingFoldController` | View 可注入，由宿主释放 | View 创建并释放；Live 自己管理折叠状态 |
| 标题导航 `ValueListenable` | View 只订阅并在替换/卸载时移除监听 | 不自动向宿主创建文档身份 |

在 State 初始化或文档会话中创建这些对象；重建界面时复用，避免在每次 build 中新建 Controller。替换参数时，旧组件移除自己的监听，新参数开始生效；外部对象仍由宿主管理。先卸载或完成 widget 更新，再释放不再使用的外部对象，避免组件仍引用已释放值。

只改变 `controller.text` 是编辑当前文档，会改变 dirty、选区及历史；它不是“打开新文档”操作。推荐每个文档一个 Controller 和稳定 document ID。若必须复用 Controller，宿主需明确重置 TextEditingValue、composing、历史、保存基线、模式和外部滚动状态的顺序。

## 保存捕获的版本

内置工具栏/快捷键的流程：捕获 `controller.text` → 结束当前撤销分组 → 等待 `onSaveRequested(capturedText)` → `markSaved(savedText: capturedText)`。存储完全由宿主完成。

- 回调正常完成代表该文本已持久化；返回前不要只发出“稍后保存”的任务。
- 保存期间继续编辑时，当前文本与已保存快照不同，dirty 保持 true。
- 用户取消或宿主主动拒绝确认时抛出 `IanvsMarkdownSaveCancelledException`。普通异常保留给宿主错误处理；如宿主已经展示错误，可转成取消异常，使内置保存不清除 dirty。
- 同一文档的写入应串行，或使用存储端版本校验。组件不负责网络/文件并发顺序；只忽略旧回调而不约束真实存储写入，仍可能覆盖较新的文件。
- 文档关闭后已经开始的写入可能继续完成；其回调必须绑定原 document ID。Controller 释放后到达的保存确认会被忽略，不会触碰已释放的通知器。

[ExampleDocumentSession](../example/lib/document_session.dart) 是可编译的宿主侧示例：每个文档持有独立 Controller，串行化写入，允许某次失败后重试，并在关闭时拒绝尚未开始的排队写入。它不属于核心公共 API。组件接入方式：

```dart
IanvsMarkdownLiveEditor(
  key: ValueKey(session.id),
  controller: session.controller,
  onSaveRequested: session.persist,
)
```

宿主自行做保存按钮时，捕获 Controller/文档身份以及文本，等待实际写入后再调用 `markSaved(savedText: capturedText)`；保留上述取消和错误语义。使用组件内置保存时，回调只负责持久化，组件会完成基线确认。

## 更新、模式和异步内容

| 宿主动作 | 当前行为 | 宿主责任 |
| --- | --- | --- |
| 修改正文 `data` | 重新渲染，阅读选择失效；没有增量 AST 保证 | 合并分片、控制更新频率与总量 |
| 修改 View `data` / `syntaxPreset` | 重新解析并安排滚动到顶部 | 整文档阅读保持此默认行为；持续追加可使用下述宿主滚动样例 |
| 修改编辑 Controller 的选区 | 源码范围变化，Live 复用文档结构 | 使用 UTF-16 偏移；避免把字节数当偏移 |
| 修改编辑文本 | 刷新相关状态与当前全文结构，更新历史和 dirty | 需要精确选区时提供完整 TextEditingValue；尊重 IME composing |
| 改变 Controller.mode | Live 切换三种界面；独立 Source 控件仍显示源码 | 根据入口选择合适容器；模式切换不代表保存 |
| 替换文档 Controller | 组件撤掉旧监听，接入新文档状态 | 保存旧文档身份，管理旧对象寿命及未完成写入 |
| 异步图片/图表/嵌入返回 | builder 返回的 Widget 与状态由宿主定义 | 用 document ID、版本和资源身份防止旧结果进入新文档 |

图片、链接、Wiki 和图表的加载权限、路径解析、大小与缓存由宿主处理。默认组件不自动访问网络或本地文件。阅读态复制的 plain text 与 HTML 是不同表示：整文档 plain text 保留原始 Markdown，部分阅读选择根据语义片段重建；不要把阅读选择回调当作精确源码选区。

## 持续追加内容（R2-03）

[流式入口](../example/lib/streaming.dart) 使用 `IanvsMarkdown` 加宿主的 `SingleChildScrollView`，直接运行 `flutter run -d macos -t lib/streaming.dart`。每次把已接收片段合并成完整 `data`，保留未闭合围栏、表格和链接，直到后续片段使语法收敛。组件不负责传输、重排、重试、分片解码和总量上限；不要把 UTF-8 分片在多字节字符中间独立解码。这里没有新增核心流式 API，也不承诺增量 AST 或每 token 一帧的吞吐率。

| 状态 | 样例策略及可依赖边界 |
| --- | --- |
| 同一响应追加 | 保持 document ID / Widget Key；递增版本、替换完整源码。正文的已有阅读选择失效，需重新选择后复制；完整复制包含当前原文 |
| 跟随滚动 | 默认跟随，内容布局或异步资源高度变化后移动到末尾；向上阅读时暂停，用户显式恢复后才再次跟随 |
| 暂停跟随 | 追加不主动改变滚动偏移；内容高度缩小时仍由 Flutter 限制合法滚动范围，不承诺屏幕中同一个词始终原位 |
| 切换文档 | 替换稳定 Key、重置版本和滚动，并暂停跟随。相同文本也不代表同一文档；旧的布局回调不得滚动新文档 |
| View | 保留既有 `data` 变化后回到顶部的整文档阅读契约；不把正文样例的跟随策略暗中变为 View 默认行为 |
| Source / Live | 通过 Controller 的完整 `TextEditingValue` 指定文本、UTF-16 选区及 composing；只在原文末尾追加且不修改 preedit 时可保留有效范围。与用户编辑冲突的片段由宿主排队或合并，不能盲目覆盖 `text` |

异步资源接入见 [ExampleAsyncDiagram](../example/lib/async_diagram.dart)。它接收捕获的 `(documentId, revision, source)`，在请求身份或 loader 改变时立即清空旧结果并生成新的请求代数。结果返回时同时检查 `mounted` 和请求代数；成功与失败都遵守此检查。即使文档或源码从 A 切到 B 再切回 A，第一次 A 的结果仍然过期。普通 rebuild 不重复启动相同请求；当前错误允许重试。

```dart
IanvsMarkdown(
  key: ValueKey(documentId),
  data: completeSource,
  diagramBuilder: (_, source) => ExampleAsyncDiagram(
    request: (documentId: documentId, revision: revision, source: source),
    load: approvedHostLoader,
  ),
)
```

这里的类型来自 example，不是核心导出。样例 loader 仅延迟返回本地文本，不访问网络、文件或原生 Mermaid。真实宿主仍须授权资源、限制缓存与解码成本，并尽可能取消过期昂贵任务；忽略结果不等于取消底层任务。共享缓存也需使用完整资源身份，不能只按 Widget 的当前位置缓存。

组件内部代码块的复制反馈也按请求代数隔离：源码、复制回调变化或新复制请求都会使旧反馈失效；已经开始的复制仍作用于调用时捕获的内容，组件不会撤销已发生的系统写入。宿主自己的保存/网络写入仍须按上文的顺序与版本规则管理。

验证入口是 [组件追加回归](../test/streaming_contract_test.dart) 和 [样例回归](../example/test/streaming_example_test.dart)：正文/View 的两种预设、Live/Reading 的围栏/表格/行内及引用链接，选择失效、编辑 preedit、旧复制反馈，异步成功/失败乱序、A/B/A、重试、卸载及滚动策略。自动回归不替代 R2-01 的完整性能验收或 R3-01 的真实输入法、触摸和读屏。

## 界面文案与作用域

在要配置的组件外放置文案作用域，无需修改内部工具栏。四种入口以及独立代码块、属性卡等辅助组件使用同一配置；嵌套作用域可以为同一页面的不同文档选择不同语言。

```dart
IanvsMarkdownLocalization(
  strings: const IanvsMarkdownStrings.english(
    overrides: {
      IanvsMarkdownMessage.save: 'Save note',
      IanvsMarkdownMessage.copy: 'Copy source',
      IanvsMarkdownMessage.dragRow: 'Move row {index}',
    },
  ),
  child: IanvsMarkdownLiveEditor(
    controller: session.controller,
    onSaveRequested: session.persist,
  ),
)
```

内置 `.chinese()` / `.english()` 可显式切换；没有作用域时保留现有默认文案。只覆盖少数旧文案时使用 `.legacy(overrides: ...)`。替换 `strings` 对象会更新后代控件，map 使用 `const` 或其他不可变实例。模板参数是字面文本，值中出现的 `{...}` 不会继续展开。

文案作用域不改变 Controller、焦点对象、保存/复制回调或文档语言。文档内容、自定义 Callout 标题和宿主显式提供的属性标签不会被翻译；UI 仅翻译解析器标记为默认标签的属性。保持 `FrontMatterCard.title` 省略即可使用作用域标题，显式 `title` / `itemCountLabel` 优先。

选择菜单从所属编辑器/阅读组件捕获文案，图片弹窗保留作用域。未配置的 iOS 文本菜单仍采用 Flutter 系统原生菜单；显式配置菜单文案时使用 Flutter 自适应菜单。浏览器原生菜单和 Flutter 日期弹窗的整体本地化还应配置宿主的 locale / MaterialLocalizations。自定义 Widget builder 返回的界面由宿主自己翻译。

## 快捷键与焦点

在组件外放置 `IanvsMarkdownShortcuts`，用 `bindings` 替换指定命令的全部默认键；空列表禁用该命令的键盘入口。`hostShortcuts` 提供保留组合键的宿主回调，优先于组件命令。下例中的 `SingleActivator` / `LogicalKeyboardKey` 来自 Flutter widgets / services，`openCommandPalette` 为宿主自己的动作：

```dart
IanvsMarkdownShortcuts(
  bindings: const {
    IanvsMarkdownCommand.save: [
      SingleActivator(LogicalKeyboardKey.f5, includeRepeats: false),
    ],
    IanvsMarkdownCommand.bold: [],
  },
  hostShortcuts: {
    const SingleActivator(LogicalKeyboardKey.keyK, meta: true,
        includeRepeats: false): openCommandPalette,
  },
  child: IanvsMarkdownLiveEditor(
    controller: session.controller,
    onSaveRequested: session.persist,
  ),
)
```

未覆盖命令保留原有默认行为。替换或禁用后，旧的默认键被消费，不会意外落到内部文本框的原动作；要让它执行宿主动作，应显式放入 `hostShortcuts`。宿主回调优先，其次是显式命令绑定，最后是未改动的默认行为；两个显式命令绑定同一组合键会抛出 `ArgumentError`。最近的作用域完整替代外层配置；同一作用域内、位于 Markdown 组件之外的普通输入框不受影响。配置的 map/list 应保持不可变，更新时替换配置。

命令按焦点区域执行：表格格式化只修改当前单元格，Tab 对应单元格跳转；属性输入使用本地撤销，屏蔽文档格式化/删除行，并在保存或切换模式前提交待编辑值。阅读全选复制保留原始 Markdown；Source 的粘贴继续使用智能链接转换。`enableModeShortcuts: false` 仍会禁用重映射后的模式命令。普通文本导航、箭头、控件 Enter 和 IME 输入保持平台行为，但也可用 `hostShortcuts` 显式保留某个键。

配置中的命令或宿主组合键遇到活跃 composing 时会被消费且不执行，组合区保持不变；组合输入提交后恢复。`includeRepeats: false` 的键长按时只执行首次，重复事件仍被消费。macOS 仅在原始事件中携带修饰键的消息也走相同配置，避免原始事件和标准化事件重复执行。此处的 widget 回归不代替 [真实平台 IME 验收](PLATFORM_SUPPORT.md)。

自定义布局时，将同一宿主创建的 `FocusNode` 传给编辑器和独立工具栏：

```dart
Column(children: [
  IanvsMarkdownEditorToolbar(
    controller: session.controller,
    focusNode: editorFocus,
    onSaveRequested: session.persist,
  ),
  Expanded(child: IanvsMarkdownLiveEditor(
    controller: session.controller,
    focusNode: editorFocus,
    onSaveRequested: session.persist,
    autofocus: true,
    showToolbar: false,
  )),
])
```

`editorFocus` 在宿主 State 中创建并在卸载后释放。自定义按钮执行 Controller 动作后也可调用 `editorFocus.requestFocus()`；独立工具栏的格式化、历史和保存按钮会自动执行这一步。模式切换源于当前组件焦点时，Live 将焦点转到新模式并保留源码选区；宿主正在编辑其他输入框时，程序更新模式不会主动抢回焦点（不要同时要求新控件 `autofocus`）。`IanvsMarkdownShortcuts.labelOf(context, command)` 显示当前首个可用组合键；禁用或所有组合键均已被覆盖/保留时返回空字符串。该标签不代表命令在当前模式必然可执行。

## 剪贴板迁移（R1-04）

这是一项 **Unreleased 默认行为变化**，不是已经发布的新版本：

| 接入 | 0.3.1 / 拆分前 | 当前候选实现 |
| --- | --- | --- |
| 不提供 `clipboardWriter` | 尝试原生 Markdown + HTML，失败后纯文本回退 | Flutter 直接写入完整 Markdown 纯文本；没有原生剪贴板依赖 |
| 已有自定义 writer | 收到 `IanvsMarkdownClipboardData` | 必填字段保留；R2-05 超限时 HTML 为空，writer 应检查 `hasHtml` |
| 需要原有原生双格式输出 | 默认提供 | 显式接入 `ianvs_markdown_clipboard` 并传入 writer |

完整文档全选仍保留原文（含 YAML、换行与 Unicode），局部选择在预算内生成语义 Markdown，超限时保留完整所选纯文本。`writeIanvsMarkdownClipboard(data)` 签名保留，现在等价于 Flutter 的纯文本写入；写入失败继续向调用方报告。R2-05 增加独立 `clipboardBudget`；未生成 HTML 时 writer 应省略该格式，避免富文本粘贴目标选择一个空表示。

原生适配器当前通过源码接入，尚未发布 registry 版本。依赖声明见 [适配器说明](https://github.com/robinfai/ianvs-markdown/tree/main/packages/ianvs_markdown_clipboard)。已有富文本宿主使用：

```dart
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_markdown_clipboard/ianvs_markdown_clipboard.dart';

Future<void> writeRich(IanvsMarkdownClipboardData data) =>
    writeIanvsMarkdownRichClipboard(markdown: data.markdown, html: data.html);

IanvsMarkdownView(data: source, clipboardWriter: writeRich);
// IanvsMarkdown 和 IanvsMarkdownLiveEditor 使用相同参数。
```

有 HTML 时适配器把两种表示放入同一原生 item；HTML 为空时直接写完整纯文本且不初始化原生后端。原生后端不可用或写入失败时回退完整 Markdown，回退失败则报告错误。Source/文本框的复制属于 Flutter 原生编辑行为，不经过阅读 writer。Linefold 桌面/iOS 阅读和 Mermaid 示例已显式接入，以保留已有输出格式。

旧 macOS 宿主如果移除了最后一个 CocoaPods 插件，需要清理旧 Pods 工程引用后再做干净构建；仍使用其他插件的宿主不能一并移除它们的配置。核心示例的迁移可作参考。依赖图、成本、方案权衡与构建限制见 [决策报告](CLIPBOARD_DEPENDENCY_DECISION.md)。

## 预解析与复制预算迁移（R2-05）

旧的语法 token 限额继续生效，并新增全文和单行长度边界。需要统一策略的宿主应在 Controller 创建时就配置它，不能等 Widget 创建后再保护已经发生的预解析：

```dart
const budget = IanvsMarkdownRenderBudget(
  maxSourceCodeUnits: 1024 * 1024,
  maxLineCodeUnits: 4096,
);
final controller = IanvsMarkdownController(text: source, parseBudget: budget);
final editor = IanvsMarkdownLiveEditor(
  controller: controller,
  renderBudget: budget,
  clipboardBudget: budget,
  onRenderDecision: (decision) {
    // 帧后回调；宿主可依据 decision.budgetExceeded 显示提示。
  },
);
```

每个预算的 `null` 只关闭对应处理；信任一个文档后关闭渲染额度，不会自动允许无限 HTML 转换或 Controller 预解析。正文/View 的 `fallbackBuilder`、Controller 的 `parseDecision` 及复制 payload 的 `budgetExceeded` 可区分行长、全文长度或语法额度超限。编辑样例已显示宿主提示。

拒绝预解析时，View 不再提前抽取 YAML，而显示包括 YAML 的原始前缀；完整复制仍保留原文。自定义 writer 必须检查 `hasHtml`：超限时 `html == ''` 表示未生成 HTML，不是可以发布的空富文本格式。使用本仓库可选 writer 的宿主无需额外分支。局部选择降级为所选纯文本，语义格式不再可用，原因随 payload 交给宿主。Source 的原生文本编辑复制不经过阅读 writer。

这些额度不限制完整源码排版、保存总量、图片或自定义 builder；宿主仍负责总量、权限及持久化。详细矩阵见 [API 预算契约](API_CONTRACTS.md#预算与资源)。

## 当前差异与后续任务

| 缺口 | 归属 | 当前接入方式 |
| --- | --- | --- |
| Live / Source 尚无标准 GFM 编辑预设 | R1-02 范围决策；后续独立扩展 | 标准只读内容使用正文或 View 的 `syntaxPreset: standard`；编辑仍按 Obsidian 契约 |
| 文案、命令及焦点已有统一宿主接入 | R1-03 | 使用相应作用域配置；文档内容与资源授权仍归宿主，真实平台交互证据继续在 R3-01 收集 |
| 默认复制改为纯文本，原生富文本改为显式适配器 | R1-04 | 按上文迁移；核心没有原生剪贴板依赖，适配器仍需验证所用平台 |
| 升级后的默认历史会裁剪旧快照 | R2-02 已实现，升级时核对配置 | 阅读 [容量与迁移契约](API_CONTRACTS.md#撤销历史容量r2-02)；需要旧行为时显式设置 `historyPolicy: null` |
| 持续追加使用全文快照，View 默认重置滚动；异步资源仍由宿主负责 | R2-03 | 使用下述正文流式样例；R2-01 优化版本仍需复验，未承诺增量 AST 或实时延迟 |
| 预解析与复制已有独立预算，完整源码排版仍未完成性能验收 | R2-05 / R2-01 | 按下方配置解析、渲染、复制额度；排版耗时不能用预算检查替代 |

证据：[宿主行为回归](../test/host_contract_test.dart)、[会话示例测试](../example/test/document_session_test.dart)、[外部包接入检查](https://github.com/robinfai/ianvs-markdown/blob/main/tool/package_smoke_test.dart)。维护脚本在源码仓库提供，不属于发布包依赖；发布内容与实例接入还需执行 `make check-package`。
