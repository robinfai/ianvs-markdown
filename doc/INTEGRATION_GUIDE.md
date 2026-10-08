# 宿主接入与生命周期

先用 [能力矩阵](API_CONTRACTS.md) 选择入口：消息/正文使用 `IanvsMarkdown`，完整阅读使用 `IanvsMarkdownView`，源码输入使用 `IanvsMarkdownEditor`，三模式编辑使用 `IanvsMarkdownLiveEditor`。View/编辑器需要有界高度，例如放入 `Scaffold.body` 或 `Expanded`；正文的滚动由宿主布局提供。

## 谁创建，谁释放

| 对象 | 宿主提供 | 组件未收到该对象时 |
| --- | --- | --- |
| `IanvsMarkdownController` | Source/Live 必须提供，宿主在组件卸载后释放 | 不自动创建 |
| `FocusNode` | Source/Live 使用但不释放；替换后旧对象归宿主 | 组件创建并释放 |
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
| 修改 View `data` / `syntaxPreset` | 重新解析并安排滚动到顶部 | 需要持续追加/跟随滚动时先定义策略；该扩展记录在 R2-03 |
| 修改编辑 Controller 的选区 | 源码范围变化，Live 复用文档结构 | 使用 UTF-16 偏移；避免把字节数当偏移 |
| 修改编辑文本 | 刷新相关状态与当前全文结构，更新历史和 dirty | 需要精确选区时提供完整 TextEditingValue；尊重 IME composing |
| 改变 Controller.mode | Live 切换三种界面；独立 Source 控件仍显示源码 | 根据入口选择合适容器；模式切换不代表保存 |
| 替换文档 Controller | 组件撤掉旧监听，接入新文档状态 | 保存旧文档身份，管理旧对象寿命及未完成写入 |
| 异步图片/图表/嵌入返回 | builder 返回的 Widget 与状态由宿主定义 | 用 document ID、版本和资源身份防止旧结果进入新文档 |

图片、链接、Wiki 和图表的加载权限、路径解析、大小与缓存由宿主处理。默认组件不自动访问网络或本地文件。阅读态复制的 plain text 与 HTML 是不同表示：整文档 plain text 保留原始 Markdown，部分阅读选择根据语义片段重建；不要把阅读选择回调当作精确源码选区。

## 当前差异与后续任务

| 缺口 | 归属 | 当前接入方式 |
| --- | --- | --- |
| Live / Source 尚无标准 GFM 编辑预设 | R1-02 范围决策；后续独立扩展 | 标准只读内容使用正文或 View 的 `syntaxPreset: standard`；编辑仍按 Obsidian 契约 |
| 文案与部分内部按键映射不能统一覆盖 | R1-03 | 可隐藏工具栏；`enableModeShortcuts` 仅关闭模式键，不代表禁用全部命令 |
| 注入 clipboard writer 仍保留原生依赖 | R1-04 | 把它当作行为注入；按实际平台构建验证，拆包另行决策 |
| 升级后的默认历史会裁剪旧快照 | R2-02 已实现，升级时核对配置 | 阅读 [容量与迁移契约](API_CONTRACTS.md#撤销历史容量r2-02)；需要旧行为时显式设置 `historyPolicy: null` |
| View 追加数据重置滚动，异步结果没有组件级文档身份 | R2-03 | 宿主管理文档/版本与加载状态，当前不承诺完整流式接入能力 |
| 渲染预算未覆盖全部预解析/复制/排版 | R2-01、R2-05 | 按已测负载使用；区分默认降级和无预算完整渲染 |

证据：[宿主行为回归](../test/host_contract_test.dart)、[会话示例测试](../example/test/document_session_test.dart)、[外部包接入检查](https://github.com/robinfai/ianvs-markdown/blob/main/tool/package_smoke_test.dart)。维护脚本在源码仓库提供，不属于发布包依赖；发布内容与实例接入还需执行 `make check-package`。
