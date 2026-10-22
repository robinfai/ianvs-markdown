# 源码保真笔记语义（P1f）

`parseIanvsMarkdownNoteSemantics(String source)` 是核心包的纯同步解析入口，不读取
文件、不解析工作区路径、不建立全局图、不执行重命名、不改写原文。结果可用于应用层
按文件身份和内容修订维护引用索引。所有样例和回归使用合成内容，不访问个人笔记。

## 结果与范围

`IanvsMarkdownNoteSemantics` 的 `references`、`tags`、`aliases`、`issues` 均不可变。
`complete` 等价于 `issues.isEmpty`；存在 issue 时，结果是已确认的局部信息，不得解释为
“没有引用”或把遗漏目标判成不存在。`aliasesComplete` 单独描述 YAML alias 覆盖；
正文超预算、HTML 或其他不支持的语法，不会抹掉已完整解析的 aliases。

`IanvsMarkdownSourceReference` 提供：

- `range`：整个语法出现的原始范围，包含标记、标签、fragment、title。
- `destinationRange`：仅路径的原始拼写，排除括号、angle wrapper、query、fragment、
  Wiki alias 和 title。空路径的范围可折叠。它不是显示标签的范围。
- `rawDestination`：完整原始目标，保留转义和 percent 编码、query、fragment，不含
  wrapper、title 和 Wiki alias。
- `target`：Markdown 先按渲染器处理标点转义/HTML entities，再在 percent 解码之前
  分离 query/fragment，最后只解码一次；宿主不得再次解码。Wiki 路径不做 percent 解码，
  `?` 在 Wiki 中是普通路径字符。
- `fragment`、`query`、`alias`、`title`：可空。`query` 仅用于 Markdown；`alias` 用于
  Wiki，普通链接的显示标签仍由原文 `range` 保存。title 遵循 Markdown 渲染器属性语义。
- `kind`：`markdownLink`、`markdownImage`、`markdownReferenceLink`、
  `markdownReferenceImage`、`markdownDefinition`、`wikiLink`、`wikiEmbed`。
- `definitionIdentity`：有效 definition 的规范化 label 加 `@start:end`，宿主还应绑定
  文档身份与原文修订。`definitionRange` 指向同一个有效 definition。

所有范围均是未修改原文的 UTF-16 半开范围；BOM、CRLF、emoji 的偏移不做归一化。
reference use 的 `destinationRange` 指向有效 definition 的目标，不伪造 label 可重写范围。
每个 Markdown destination 必须通过原生 destination 或独立 inline grammar 核验；
无法证明 raw source 与 renderer target 对应时返回 `destinationSpan`，不暴露猜测范围。
多处 uses 可以共享一个 definition 目标范围。重复 definition 遵循 first-definition-wins，
只输出生效的 definition；被遮蔽的 definition 不伪装成可导航引用。

例如 `[x](A%3F%23%2520.md?mode=1#Heading)` 的 `target` 是 `A?#%20.md`，
路径源码范围只覆盖 `A%3F%23%2520.md`。`[[A%20B#Heading|Label]]` 的 `target`
仍是 `A%20B`。fragment 的 `#` 即使来自 `\#` 或 `&#35;`，路径范围也在完整转义/entity
之前结束，不留下半个转义字符。

## 支持与语法来源

- Markdown inline links/images、full/collapsed/shortcut references、角括号目标、
  平衡/转义括号、可选/多行 title、空目标、heading/block fragment。
- Wiki links/embeds、普通 alias、路径/heading/block fragment；`[[|Alias]]` 的前导 pipe
  属于路径。embed 沿用独立 embed 规则：`![[|Alias]]` 是文字，`![[Note|]]` 指向 Note。
- `package:markdown` 的 BlockParser/LinkSyntax 决定有效 definition、label case folding、
  reference precedence 和 nested Markdown link 识别；不使用正则搜括号作为链接解析器。
- 编辑器原有的源码映射投影处理 list/blockquote 容器、fenced/indented code；既有
  Obsidian code-span、comment、math、tag 和 Wiki body grammar 决定对应语义。
- code、配对 comments 和 front matter 内的链接/inline tags 不计入正文。comments 的
  移除保留原始偏移；若 comment 打断 destination，使其不再具有连续原始路径范围，
  返回 `nonContiguousDestination`，不提供可能破坏 comment 的替换范围。
- 普通链接标签内的 tags 遵循渲染器 inline grammar；destination/title 中的 `#` 不会被
  误认成 tag。image description 最终展平成 alt 文本，其中嵌套链接/tags 不作为引用返回；
  作为链接内容的 image 仍同时保留外层链接与 image 目标。

`IanvsMarkdownSourceTag` 的 `name` 无开头 `#`；`range` 覆盖完整原始 inline tag 或
YAML scalar（包括引号）。若正文 tag 被 comment 打断，range 包含该 comment，name
则是阅读语义；不要把 tag range 当成已授权的重写操作。

原生 Markdown grammar 的边界也须保留：前导 NBSP 是路径字符，不是可丢弃的空白；
bare destination 中的 tab 目前也是路径字符，而不是 title 分隔。definition 的非配对
右括号由当前原生 parser 接受时，路径 span 必须包含它，不能提前截断。
路径中的前导 U+FEFF（原字符或 `%EF%BB%BF`）在一次 URI 解码时保留，不能误当
传输 BOM 丢弃并指向另一个文件；Wiki 仍沿用既有 body grammar。

## 独立 YAML 元数据解析

仅解析文首 `---` 包围的 YAML mapping，兼容 BOM/CRLF。64 KiB 上限按 YAML 内容的
UTF-8 字节计，与 properties UI 的 40 条展示/16 个 list 项截断无关。所有顶层键都会检查，
所以 aliases 在第 41 个键之后或超过 16 个 alias 时不会静默丢失。

支持大小写精确的 `alias`/`aliases` 和 `tag`/`tags`，值为一个非空字符串或字符串列表。
每个字符串最多 1,024 个 UTF-16 单元，不支持多行。`alias` 与 `aliases` 合计最多
1,024 项，`tag` 与 `tags` 也合计最多 1,024 项。值按原顺序保留，不转成展示字符串，
不把数字、布尔、mapping、nested list 等强制字符串化。无值的空列表是完整空集合。

YAML tag 可带可不带开头 `#`，但必须完整符合已有 inline tag grammar：允许 nested/
Unicode/emoji，拒绝只有数字、只有 `#`、含空格或不支持标点的名字。空值、类型、计数、
长度或 tag grammar 不支持时产生 issue；alias 问题同时令 `aliasesComplete = false`。
YAML anchors/alias references/merge 目前显式不支持，避免把 anchor 定义的 span 误报为
`*alias` 使用位置。显式 YAML tag（例如 `!!str &a`）也不能绕过 anchor 检测；
list 元素 span 必须落在当前属性 value 内。带引号的普通 `"&name"` 字符串不是 anchor，照常解析。

## 显式不完整边界

- 正文使用默认 `IanvsMarkdownRenderBudget`：1 Mi UTF-16 原文、4 Ki 单行、4,096 syntax
  tokens。超限返回 `bodyBudget`，不把截断文本当完整文档。
- references、tags 与 issues 合计最多分配 4,096 条常规记录；超限即停止正文解析，
  另附一条 `occurrenceBudget` 终止标记，包括不计入 renderer syntax tokens 的 tag-heavy
  或 automatic-URL-heavy 输入。
- source-mapped container 嵌套最多 64 层；超限或无法建立语义时返回 `parserLimit`。
- tables 暂不索引任何正文 references/tags，并返回 `tableContext`。真实 renderer 按 cell
  分割并解转义 pipe；在逐 cell 精确源码投影完成前，不跨 cell 猜测链接或扫描未渲染额外列。
  YAML aliases 的独立完整性不受影响。逐 cell 源码映射与相应回归仍是未完成项，
  是后续安全 rename 支持表格的前置条件；P1f 不声称正文语法全覆盖。
- HTML blocks/inline HTML、automatic URL/email links、footnote definition bodies、
  Wiki alias 内的嵌套链接/tags 目前各自返回 issue。不猜测宿主扩展或将其默认为空。
- 无效 URI 编码、无法安全映射的 definition/destination/query/fragment 也返回 issue。
- 未定义的 reference label 和普通不成形 Markdown 本来就是 literal，不凭外观制造引用。

宿主需要同时处理“已解析引用”与“覆盖未知”。这些 DTO 为后续安全重命名预留来源信息，
不授权或实现跨文件写入。工作区身份、dirty overlay、文件 fingerprint、目标解析和失效
策略由 app/宿主负责，不能放进该核心 API。

回归：[note_semantics_test.dart](../test/note_semantics_test.dart)。
