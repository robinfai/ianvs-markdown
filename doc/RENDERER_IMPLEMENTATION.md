# 内部 Markdown 渲染器维护边界

核心继续使用 `flutter_markdown_plus` 的公共样式、builder、回调和语法类型，公共导出未替换。正文的两种预设改用内部 `ScopedMarkdownBody`，它继承上游 `MarkdownBody`，保留原有布局接口和资源注入方式。

## 引入原因与范围

`flutter_markdown_plus 1.0.12` 的 `MarkdownBuilder.build` 将每次构建的自定义块标签追加到库级 List；访问节点时使用线性查找。重复渲染会增加查找成本，更会把一个文档的块声明带到另一个文档。回归复现：先渲染行内 token，再在另一文档把同名 token 声明为块，最后重新渲染原行内文档，其几何位置会错误换行。

修复在 [scoped_builder.dart](../lib/src/renderer/scoped_builder.dart) 中将注册集合限定为每个 builder 实例，并在每次 `build` 时重置为内置标签和当前配置。集合不随历史文档数量增长，同名标签可以在不同 renderer 中分别是行内或块。没有修改 Pub 缓存，也没有给核心引入 Git 或工作区路径依赖。

由于上游构建状态和标签注册不可通过公共接口替换，内部保留一份有限的派生实现：

| 文件 | 来源与有意差异 |
| --- | --- |
| `scoped_builder.dart` | 上游 `lib/src/builder.dart`；类型改名，块标签改为每次构建独立的 Set。核心要求提供图片回调，因此移除不可达的默认文件/网络加载分支；URI 分段和回调参数保持原语义 |
| `scoped_body.dart` | 上游 `lib/src/widget.dart` 的 State 桥接；继续使用公共 `MarkdownBody` 构造和布局；调用内部 builder，增加默认关闭的解析/Widget 构建阶段计时 |
| `fallback_style_io.dart` / `fallback_style_web.dart` | 上游同名平台辅助文件中的样式回退部分；保持原有 native 平台和 Web user-agent 判定及 text scaler |

来源版本为 `1.0.12`，原 `builder.dart` SHA-256 为 `f1e276216dcc9715b80bc10a4dbcf16d2520e90dae4db477c8f1b7722b2be64d`。保留原版权和 [BSD 许可证](../lib/src/renderer/LICENSE.flutter_markdown_plus)，包根许可证也包含此声明。其余上游资源、样式表和公共类型不复制；依赖仍参与正常的版本锁定和包外验证。

## 状态、更新与验证

块标签集合只属于一次构建，没有全局缓存。State 仍按上游规则在依赖变化、数据或样式变化时重建；核心为每次配置生成相应样式和 builder。链接 recognizer 在重新解析和销毁时释放，回调继续读取当前 widget。图片继续由宿主回调或核心占位处理，不自动读取资源。

升级 `flutter_markdown_plus` 时须对照这几份源文件，检查新增的构建字段、节点类型、布局和 recognizer 行为。如果上游提供实例隔离的实现与可用替换接口，优先移除派生代码。不能只更新依赖版本而忽略内部副本。

验收包含跨 renderer 的块/行内隔离、同一 renderer 的配置切换、重复创建/销毁、GFM/Obsidian 全套布局与交互回归、资源回调、完整包快照和实际 Profile 配对。修复确定性状态泄漏不代表性能目标已验收；GUI 基线受锁屏影响的记录不得用作通过依据。
