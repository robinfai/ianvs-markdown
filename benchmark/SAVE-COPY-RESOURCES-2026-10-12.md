# 保存后继续编辑、复制与本地资源

日期：2026-10-12。R3-02 本批处理 L05/L06，使用 `example/lib/main.dart` 和
`app/lib/main.dart` 两个正式入口。roadmap 仍为 14 项完成、2 项进行中；L07/L08 留待后续。

## 修复与自动回归

- `4f5aba9`：修复 app 保存失败处理。编辑器快捷键原先会把保存错误作为未处理的异步异常抛出；
  原生 File 菜单的 `Future<bool>.catchError` 回调则因返回类型不符再次失败。现在宿主显示错误，
  编辑器不确认失败快照，用户可继续编辑并重试。保存成功只确认请求时的原文，后续输入继续为 dirty。
- `8f159c9`：把本地 SVG 的 UTF-8 解码移入异步读取，使损坏文本与缺失/超限文件走同一可关闭
  错误界面。此前解码发生在 widget build，非法字节会导致界面异常。
- 新增 9 项正式应用 widget 测试：app 的快捷键/原生菜单 × 保存成功/失败 4 项，缺失图片/
  非法 SVG 2 项，example Source/Live/Read 整篇纯文本复制 3 项。输入覆盖 CRLF、中文、emoji、
  尾随空格和无末尾换行；同时检查最新草稿、旧保存快照和文件监视状态。
- 最终门禁前补齐新测试的条件分支格式与资源错误文本断言。核心公共 API、运行库和依赖未变，
  无新增迁移要求；宿主行为写入 [app 说明](../app/README.md)。

同一组 app 回归在基线 `1b1443e` 的两个运行文件上得到 3 通过 / 3 失败，失败分别是两种保存
入口的错误处理和非法 UTF-8 SVG。修复后保存/竞态/监视专项 22 项、资源 2 项及 example 3 项
通过。初次组合检查因 example 测试的单行 if lint 中断，未当作通过；最终组合检查结果见下表。

## 自动门禁与构建

| 检查 | 结果 |
| --- | --- |
| 核心 / example | 967 / 25 项通过，格式、分析通过 |
| API / Python / 处理预算 | 8 / 10 / 32 组通过；183 exports、1143 declarations 不变 |
| app | 287 项通过，历史可选外部语料跳过 1 项 |
| Mermaid / Clipboard | Flutter 9、Rust 4、适配器示例 3 / 剪贴板 6 项通过 |
| Quick Look / 导入 | Rust 8、Swift 10 及原生 Markdown 导入通过 |
| 两个 main 构建 | example/app Debug 和 Release，共 4 次通过 |
| 包快照 | 168 文件 / 668 KB，零警告，示例与自动包外 smoke 通过，无工作区路径泄漏 |

第二次组合检查的 Core/API/example/Python/预算全部通过；app 的缺失文件断言误用了父异常类名，
改为匹配 `Cannot open file` 后，最终 `make check-integrations build-local build-local-release`
退出 0。最终 PR 头仍须双 SDK Core required 与 Native integrations 通过。

SDK 为原版 Flutter 3.44.8 / Dart 3.12.2，revision
`058e0af2c2b57e369d905a03ac9748b0ebf543c6`；macOS 27.0.1 arm64、Xcode 27.0、Rust 1.90.0。
app 使用 `FLUTTER_XCODE_ARCHS=arm64`、`CARGO_PROFILE_RELEASE_STRIP=none`。
证据记录输入哈希及四个构建产物；Debug 只构建，真实 GUI 使用新构建的 Release bundle。

## 两个 Release 主入口的实际操作

1. app 打开专用测试目录中的 `save.md`：90 字节，3 处 CRLF，无末尾换行。Source 末尾输入
   `SAVED` 并保存，磁盘精确为原文加标记（95 字节）。继续输入 `LATER`，界面 Edited，
   恢复存储正文是新内容、persistedText 是旧快照，磁盘仍为 95 字节。再次保存后精确为
   100 字节，关闭标签再从文件树重开，内容和 Saved/CRLF 均正确，没有自身写入冲突提示。
2. example 使用默认完整语料，在 Source 全选后通过原生 Edit → Copy，粘贴到 app 新建的
   Source 文档，保存为 `example-copy.md`。4,478 字节与 Dart 直接求值的 `exampleMarkdown`
   常量完全一致。GUI 自定义 CRLF 粘贴曾只改变 AX 而未进入模型，未算通过；自定义全文及
   三模式复制由新增 widget 回归覆盖。快捷键与焦点细节仍随 L08 验证。
3. app Read 打开 `resources.md`：带 `%20` 路径及 `#target` 的链接打开 `chapter one.md`，
   保留 Read 模式并显示 Target；普通 SVG 链接预览蓝色矩形与白色圆形。损坏 SVG 显示
   `FormatException: Invalid UTF-8 byte (at offset 0)`；缺失 PNG 显示可读的文件错误；
   两个错误均可关闭并继续使用文档。嵌入图片仍显示 `Image blocked · local`。
4. 同一 app Read 文档的 Mermaid 实际渲染中文节点“保存 → 继续输入”。单独的非法图表
   显示解析错误并保留原始图表源码，文档保持 Saved。
5. app Read 正文全选/复制一次，先粘贴到 TextEdit 的空白富文本文档，再粘贴到 app 的新
   Source 文档，期间没有重新复制。RTF 显示标题、粗体、斜体、中文/emoji 与代码文本；
   保存的 Markdown 为 273 字节，与原 `resources.md` 完全一致。TextEdit 只是系统剪贴板
   接收端，没有增加 Flutter 验收入口。相对链接保留蓝色下划线样式，但 RTF 中没有有效
   HYPERLINK 字段；不将其记为跨应用相对路径可点击，原路径仍完整保存在 Markdown 中。
6. 原有 9 个文档的正文和 persistedText 核对未变。原始会话、书签与用户文本不进入仓库；
   只归档本轮语料、保存结果、压缩日志、产物和输入哈希以及过滤后的布尔核验结果。

实际运行 PID 首次记录为 example 75195 / app 76300，均来自本次 Release bundle。截图可在
任务操作过程查看，仓库未归档截图文件。CRLF 及长原文用 gzip 保存以避免证据换行被转换。

## 边界与后续

保存期间挂起写入、取消、错误重试与监视竞态由可控文件服务的自动回归覆盖；实际 GUI 记录
只支持其明确执行的文件操作，不能把瞬时磁盘写入称为真实并发或故障注入。默认图片嵌入仍为
占位符，不自动读取本地或远程图片；app Read 的普通图片链接由用户打开预览。剪贴板的
双格式由同一次复制分别送入富文本和纯文本接收端核验，接收端格式选择不等同于所有应用兼容。

本轮没有新增入口、修改 SDK、安装到 `/Applications`、发布包或宣称上游 AOT 问题解决。
接下来推进 L07 两个主入口的大文档降级，以及 L08 真实中文 IME、候选取消、选区/撤销/焦点；
自动输入中文字符串不作为 IME 验收。外部宿主不作为当前前置条件，重新开展分发时再单独安排。

证据索引：[validation.json](results/2026-10-12-save-copy-resources/validation.json)。
