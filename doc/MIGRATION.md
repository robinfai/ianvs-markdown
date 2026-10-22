# 从 0.3.1 升级到当前 Unreleased

更新：2026-10-22。面向已使用 0.3.1 的宿主，整理当前仓库候选的行为变化与接入步骤。
仓库版本仍是 `0.3.1`，这些变更尚未发布到 pub.dev；不能仅通过更新版本约束获得它们。
接入验证应锁定候选提交或该提交的 Pub-selected 包快照，并记录文件哈希。
本指南不表示 1.0 API 已冻结。2026-10-12 起当前迭代改以 example/app 两个 main 为入口，
按 [本地执行清单](R3_ACCEPTANCE.md) 推进；跨平台独立分发与外部产品验收不作为本地前置。

## 1. 先确认受影响的默认行为

| 项目 | 0.3.1 行为 | 当前 Unreleased | 宿主需要做什么 |
| --- | --- | --- | --- |
| 默认阅读复制 | 尝试原生 Markdown + HTML，失败后纯文本回退 | Flutter 写完整 Markdown 纯文本；核心移除原生剪贴板依赖 | 需要双格式的宿主显式接入可选适配器；自定义 writer 检查 `hasHtml` |
| 昂贵解析与复制 | 已有显示语法预算，但不是所有预解析和 HTML 复制入口都有相同保护 | Controller、文档预解析、Live 结构和复制先检查输入；新增全文与单行额度 | 明确 `parseBudget`、`renderBudget`、`clipboardBudget`，观察各自的降级原因 |
| 撤销历史 | 无容量上限 | 默认最多 200 个快照、32 MiB 计账文本，含当前状态 | 需要不同容量时配置策略；确需旧行为时显式 `historyPolicy: null` |
| standard GFM | 正文已支持 opt-in standard | View 也支持 standard；默认仍为 Obsidian | 按阅读用途选择，不向 Live/Source 传入不存在的 standard 编辑参数 |
| 文案、快捷键与焦点 | 原有标签和命令 | 增加局部配置作用域与可注入焦点 | 需要时 opt in，校验自己的快捷键保留、焦点和对象释放 |
| Source 范围定位/只读 | 无独立请求 | 新增可选 `highlightedRange` 与 `readOnly`；原默认不变 | 查找使用原文快照和 UTF-16 范围，Reading 临时源码面显式传 `readOnly: true` |
| Live 初次 autofocus | 固定激活首块 | 按 Controller 当前源码选区激活并定位；晚到外部焦点取消异步恢复 | 若确需从文首开始，先显式设置源码光标为 0；隐藏 YAML 选区转到可见正文 |
| 异步保存 | 已支持捕获文本确认 | 契约保持；补充文档关闭后迟到确认的保护和接入样例 | 检查存储回调真正等待写入，绑定文档身份；不能把新编辑错误标为已保存 |

内部 renderer 状态隔离、Source 几何复用和 Live 私有模块拆分不要求改用新的公共入口。
不要引用 `lib/src/` 的内部实现；完整参数与语义见 [API 契约](API_CONTRACTS.md)。

### 可选笔记语义接入（P1f）

新增 `parseIanvsMarkdownNoteSemantics(source)`，已有宿主无需迁移。需要建立引用索引时，
保存原文修订并消费 source ranges，不从渲染文本反推路径。先检查 `complete`/`issues`，
不要将未知覆盖视为没有引用；aliases 可单独依赖 `aliasesComplete`。Markdown `target`
已 percent 解码一次，宿主不得再做一次 URI 解码；Wiki 保留字面 percent 拼写。
reference use 与有效 definition 共用目标范围，重命名计划必须去重并另行获得写入授权。
完整限制和元数据 bounds 见 [笔记语义契约](NOTE_SEMANTICS.md)。

### 可选同文档阅读刷新（P1h）

`IanvsMarkdownView(preserveScrollOnUpdate: true, ...)` 可让同文档外部数据更新保留
当前阅读像素位置。省略时保持原来的更新后回到文首，无需迁移；其他组件没有新增此参数。
内容变短会裁剪到合法滚动范围，等待更新期间的用户滚动不会被旧请求位置覆盖。
它不做语义锚点恢复。换文档或 workspace/session 时务必换 key；现有按 heading identity
保留折叠状态的合同不变。详见 [同文档阅读刷新](API_CONTRACTS.md#同文档阅读刷新p1h)。

## 2. 复制：明确选择纯文本或原生双格式

不传 `clipboardWriter` 的正文/View 及 Live 阅读面会使用核心纯文本 writer。
完整文档复制保留原始 YAML、Markdown 标记、换行和 Unicode；这不是渲染后的纯文本导出。
Source 和文本框的复制仍走 Flutter 编辑行为，不经过阅读 writer。

现有 `IanvsMarkdownClipboardData(markdown: ..., html: ...)` 构造和 writer 注入继续可用。
预算超限时 `markdown` 仍完整，`html` 为空，`hasHtml == false`；自定义原生 writer 必须省略
HTML 格式，避免接收端选择空表示。`maxFallbackBytes` 不限制要复制的原文长度。
核心 writer 示例：

```dart
final data = ianvsMarkdownDocumentClipboardData(source);
await writeIanvsMarkdownClipboard(data); // 写入 data.markdown，包含完整原文
```

需要原有 Markdown + HTML 输出时，按 [剪贴板接入](INTEGRATION_GUIDE.md#剪贴板迁移r1-04)
显式添加 `ianvs_markdown_clipboard` 并注入其 writer。适配器当前为 `publish_to: none`
的源码包，没有可承诺的 registry 版本；候选提交、核心和适配器来源需一起固定。
适配器的原生平台验收独立于核心纯文本测试，不能因核心移除插件就删除宿主其他插件的配置。

## 3. 预算：三个操作分别配置，降级不丢原文

默认输入额度为 1,048,576 个 UTF-16 单元、每行 4,096 个 UTF-16 单元、4,096 个语法 token；
默认显示降级前缀最多 64 KiB UTF-8。等于额度时允许，超过才降级；不要混淆 UTF-16 长度和
UTF-8 显示字节。检查完整原文后，Reading 可以显示包括未解析 YAML 的原文前缀，Live 可以
退到完整源码编辑。Controller 的原文、选区、保存和整篇复制不被显示前缀截断。

需要一致策略时由宿主把同一对象传给各入口：

```dart
const budget = IanvsMarkdownRenderBudget();
final controller = IanvsMarkdownController(
  text: source,
  parseBudget: budget,
);
final editor = IanvsMarkdownLiveEditor(
  controller: controller,
  renderBudget: budget,
  clipboardBudget: budget,
);
```

Controller 在 Widget 前创建，`parseBudget` 不从 Widget 自动继承。
`parseBudget: null` 只关闭该 Controller 的保护，不会关闭渲染或复制的保护；其他预算参数
同理。Controller 的预算在构造时确定；需要切换策略时按文档会话管理 Controller 替换。
独立文档解析、HTML 转换和折叠辅助函数也要核对自己的 `budget` 参数。

默认超预算显示新增中英文状态提示；截断仅影响 Read 显示，不影响编辑、保存或全文复制。自定义 `fallbackBuilder` 继续拥有全部降级 UI。新增 `IanvsMarkdownMessage.documentPlainEditing`、`documentPlainReading`、`documentPreviewTruncated` 可通过现有文案作用域覆盖；对该 enum 做穷尽 switch 的宿主需补齐三项。预算数值未变。

宿主通过 `controller.parseDecision`、Live 的 `onRenderDecision`、渲染 `fallbackBuilder`
和复制数据的 `budgetExceeded` / `hasHtml` 观察结果。预算不限制完整源码的 Flutter 排版、
宿主 builder、图片解码、进程内存或耗时；关闭预算应根据实际文档负载评估，不能推断大文档
输入已实时化。范围和已有性能边界见 [预算契约](API_CONTRACTS.md#预算与资源)。

## 4. 历史：选择容量，不把撤销栈当持久化

默认策略会裁剪旧快照；200 指保留状态总数，包含当前状态，不是保证 200 次可撤销操作。
32 MiB 按每份字符串 `length * 2` 计账，不是 Dart 堆内存上限。当前状态超过额度时仍完整
保留，但可能只剩当前状态可用；保存基线独立于历史裁剪。

```dart
final bounded = IanvsMarkdownController(
  text: source,
  historyPolicy: const IanvsMarkdownHistoryPolicy(
    maxEntries: 100,
    maxTextBytes: 16 * 1024 * 1024,
  ),
);
final legacy = IanvsMarkdownController(text: source, historyPolicy: null);
```

`null` 恢复无界历史，长时间编辑可能持续累积快照。两种方式都保留完整当前文本。
使用 `retainedHistoryEntries` / `retainedHistoryTextBytes` 检查宿主负载，测试裁剪后的撤销、
重做与 dirty；不要依赖历史栈在关闭重开后恢复内容。详见 [历史契约](API_CONTRACTS.md#撤销历史容量r2-02)。

## 5. 保存、文档切换和异步资源

使用内置工具栏/快捷键时，`onSaveRequested(capturedText)` 应返回真实写入的 Future。
组件等它成功后用捕获的文本确认保存；期间的新编辑仍为 dirty。回调不需要再次调用
`markSaved()`，也不能只排队后台写入就提前返回成功。

自行实现保存按钮时，捕获文档 ID、Controller 和文本，写入该文档后调用
`controller.markSaved(savedText: capturedText)`。同一文档写入应串行或由存储端校验版本。
取消保存使用 `IanvsMarkdownSaveCancelledException`；普通错误交给宿主错误处理，失败和
取消都不能清除 dirty。已关闭文档的写入绑定原文档，不能改写当前打开的另一篇文档。

一次打开对应独立 Controller 和稳定文档 ID；只赋值 `controller.text` 是编辑当前文档，
不是完整的文档切换。宿主创建的 Controller、FocusNode 和 ScrollController 由宿主释放，
先完成组件替换或卸载。异步图片/图表结果需同时检查文档、版本和资源身份。
可运行的串行保存与切换示例见 [接入指南](INTEGRATION_GUIDE.md#保存捕获的版本) 和
[编辑样例](../example/lib/editor.dart)；示例使用内存存储，持久化由实际宿主实现。

## 6. 预设、配置与 SDK 范围

- `IanvsMarkdownView(syntaxPreset: IanvsMarkdownSyntaxPreset.standard, ...)`
  现在可用于标准 GFM 阅读；正文的 standard 已在 0.3.1 提供。Live/Source 仍使用 Obsidian
  编辑语义，不能把 View 的能力推断为 standard 三模式编辑。
- `IanvsMarkdownLocalization` 不设置时保留旧标签；`.chinese()` / `.english()` 与覆盖表
  按最近作用域生效，文档文本不被翻译。
- `IanvsMarkdownShortcuts` 可以重映射或禁用命令；需要宿主接管时显式配置 `hostShortcuts`，
  不依赖禁用命令自动冒泡。组合输入期间的行为仍须在目标平台实测。
- 当前声明 Flutter `>=3.44.0` / Dart `^3.12.0`。Core CI 的 3.44.0 与 3.47.6 证明对应的
  分析、widget 测试和包快照检查；它们不等于全部平台的 AOT 或真实交互通过。
  macOS Reading/Editor/Streaming AOT 仍有上游限制，见 [平台矩阵](PLATFORM_SUPPORT.md)。
- 核心、剪贴板适配器和 Mermaid 的分发/版本分别管理；本轮没有发布新版本，也没有扩大
  平台承诺。最终分发范围与版本决策另行安排，不是当前双入口本地迭代的退出条件。

### R4-01 原生菜单与输入边界

新增静态 `IanvsMarkdownShortcuts.invoke`，已有构造参数和 enum 不变。原生菜单/自定义工具栏
应通过当前焦点分发，传入 controller 可拒绝其他文档；只有返回 false 时才委派普通控件
Actions。不要在返回 true 后再次调用 controller，composing 抑制也返回 true。
保存异步完成仍使用 `onSaveRequested`，不能把分发返回值当成已写盘。

默认编辑命令现在和重映射命令一样保护组合输入；调用方应先让输入法确认/取消再重试。
`bindings: {command: []}` 只禁用按键，菜单点击仍可执行；`enableModeShortcuts:false` 也只
针对按键。宿主需删除冲突的原生编辑 accelerator，或自行完整同步当前焦点配置；两个
主入口采用前者，菜单不显示快捷键，键盘仍按组件配置执行。

内置工具栏的属性撤销/保存保留局部焦点，Read 历史按钮禁用；属性/表格上没有局部定义
的结构格式按钮禁用。独立工具栏没有对应焦点时仍使用传入 controller 与 focusNode。
默认日期字段 Tab 保持分段导航。升级后应分别验菜单、按键、工具栏与原生 IME；
框架 composing 回归不能替代目标系统/输入法的人工验收。

### R4-05 P1a Source 查找面

既有 `IanvsMarkdownEditor` 调用无需修改。需要当前匹配定位的宿主使用唯一文档 Controller，
直接传精确的源码快照和 UTF-16 范围，不用复制 Controller 或设置其选区来模拟高亮：

```dart
IanvsMarkdownEditor(
  controller: controller,
  readOnly: controller.mode == IanvsMarkdownEditorMode.preview,
  highlightedRange: IanvsMarkdownSourceHighlight(
    source: searchedSource,
    range: TextRange(start: matchStart, end: matchEnd),
  ),
);
```

新建请求对象表示一次导航；仅普通 rebuild 时应复用请求，下一处/上一处即使落回同一范围
也要创建新实例。null 清除高亮。文本变化或 Controller 替换后旧请求失效，需要重新搜索；
无效范围或不匹配的快照被忽略。导航不改变焦点、文本、选择或历史，查询框可继续输入。

`readOnly: true` 保留选择、复制、保存与模式切换，隐藏编辑工具栏并消费修改命令。
保存沿用 `onSaveRequested`；`enableModeShortcuts: false` 只抑制模式按键，不影响显式
`IanvsMarkdownShortcuts.invoke` 模式操作。显式宿主回调和程序 Controller 写入不在这个
只读边界内。Controller.mode 本身不能代替该参数。只读切换还会取消已经发起、
但尚未完成的智能 URL 粘贴。详见 [范围与失效契约](API_CONTRACTS.md#source-范围导航与只读展示r4-05-p1a)。

## 7. 按顺序验证升级

1. 固定候选提交/快照，记录原版本、目标平台、SDK 与可选适配器来源；对照上表选择策略。
2. 更新宿主依赖和配置，分析并编译。核对源码保真、预算降级、复制格式、历史裁剪、异步
   保存失败/取消/重试、文档切换与过期资源，不从编译成功推断行为兼容。
3. 在组件源码仓库运行 `make check-core` 和 `make check-package`。前者含 API 基线门禁；
   后者只复制 Pub 实际选中的文件，在全新包外宿主执行迁移 smoke，不解析回工作目录。
4. 当前在 example/app 的 main 中验证三模式和实际文件工作流，app 记录保存/关闭重开。
   自动 smoke 使用模拟剪贴板与内存 Future，不能替代真实 UI、系统复制或 IME；独立
   产品接入与发行支持留待后续分发工作另行安排，不要求本轮提供外部项目。

维护工具和 smoke 源码只在
[源码仓库](https://github.com/robinfai/ianvs-markdown/blob/main/tool/package_smoke_test.dart)
提供，不进入核心包依赖。API 基线检测新增、删除和声明变化，不能证明行为兼容；后续每次
改动仍需同步本指南、[API 契约](API_CONTRACTS.md) 和 [CHANGELOG](../CHANGELOG.md)。

## Typed 链接回调（P1d）

旧 `onTapLink` 可原样保留。需要区分 Wiki、普通 Markdown 和 tag 的宿主可以改用
`onTapLinkTarget: (target) { ... }`，按 `target.kind` 分发。不要根据 `.md` 扩展名、
标签或同段其他 Wiki 链接猜来源。`target.href` 可空；Wiki 目标保留 fragment，路径解析、
当前笔记内定位和打开/创建策略由宿主负责。两个回调同时设置时 typed 优先且仅调用一次。

Wiki embed、front matter Wiki 属性和嵌套渲染面也保留来源；Live 的普通 Markdown/tag
编辑交互不变，Reading 则交付完整 typed 导航事件。该接口为可选新增，无需迁移已有回调。
