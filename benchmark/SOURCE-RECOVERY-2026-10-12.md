# 两个主入口的源码保真与文档恢复

日期：2026-10-12。R3-02 本批优先完成 L01/L04 的自动回归与实际恢复链路，R3-03 同步维护
证据和交付门禁。共 16 个 roadmap 任务仍为 14 完成、2 进行中；本报告没有宣告整个 R3 完成。

## 改动及适用范围

- `d842df4`：直接使用 `ExampleApp` 和 `LinefoldApp` 的源码保真回归，沿两个 main 的实际
  模式、工具栏和文件控制器操作。新增 example 2 项、app 1 项；没有新建独立验收入口。
- `b4aa079`：修复 app 恢复路径，新增 6 项会话回归，补充模式切换断言和 app 恢复说明。
  发布核心运行库、依赖和公共 API 均未变化。
- iCloud 自动目录不可用时，恢复上次本地工作区、权限书签、文件标签和脏内容。此前只要
  配置了默认目录回调就跳过本地恢复；现在以实际 iCloud 解析结果决定。iCloud 可用时原有
  云端默认策略仍保留，已有云端隔离回归通过。
- 单独切换模式也触发恢复存储；所有快照串行写入，避免异步写入共用临时文件或旧结果覆盖
  新草稿。空闲时直接开始写入，保持既有浏览器状态回归所依赖的调度行为。
- 正常可取消退出等待 `flushSession()`；等待期间继续输入会补写最新快照。存储失败时
  取消退出并显示错误，之后可以再次退出重试。退出刷新只写恢复会话，不代替用户保存 Markdown。

恢复仍不包含光标、滚动位置、撤销历史或外观偏好。强制终止/断电可能丢失最后 350 ms 自动
存储窗口内的输入。本次没有模拟实际磁盘故障或强退，失败/重试由可控存储与真实应用退出
回调的 widget 回归覆盖；不据此声明所有系统退出路径都能阻止终止。

## 自动回归和构建

本机原版 Flutter 3.44.8 / Dart 3.12.2，SDK `058e0af2c2b57e369d905a03ac9748b0ebf543c6`，
SDK Git 工作区干净；macOS 27.0.1 arm64、Xcode 27.0、Rust 1.90.0。
app 沿用 `FLUTTER_XCODE_ARCHS=arm64`、`CARGO_PROFILE_RELEASE_STRIP=none`。
未改 SDK、升级依赖、安装到 `/Applications` 或发布包。

| 检查 | 结果 |
| --- | --- |
| 核心 / example | 967 / 22 项通过；格式、分析通过 |
| API / Python / 输入预算 | 8 / 10 / 32 组通过；183 exports、1143 declarations 不变 |
| app | 281 项通过，1 项历史可选外部语料跳过 |
| Mermaid / Clipboard | Flutter 9、Rust 4、示例 3 / 剪贴板 6 项通过 |
| Quick Look / 原生导入 | Rust 8、Swift 10 及导入检查通过 |
| 两个 main 构建 | example/app 的 Debug 和 Release，共 4 次通过 |
| 包快照 | 167 文件，示例与包外自动 smoke、零警告和路径泄漏检查通过；精确大小/哈希见证据 |

新增源码回归检查 YAML、中文/emoji、转义表格管道符、链接、尾随空格、tab、代码块、无末尾
换行及 LF/CRLF。断言完整源码相等，选择替换可撤销/重做；example 保存回调/Reset 和 app
磁盘抽象层保存/关闭重开分别验证，避免将渲染文本相同误当成源码一致。

执行过程保留失败证据：旧实现上 5 项新恢复回归失败；修复后专项 23 项通过，随后加上退出
等待期间新输入测试。首个 `make check-local build-local-release` 在 app 分析的未使用 import
处退出 2，此前 Core/example/API/预算均已通过。为模式增加实际断言后分析通过；最初的串行
队列引入了 11 项侧栏调度回归，改为空闲直接保存后，最终 app 281 项全部通过。
最终 `make check-integrations build-local build-local-release` 退出 0，覆盖格式、分析、
完整 app/适配器和全部四次构建。`make check-package` 退出 0。没有把首次中断命令写成通过；
完整组合门禁由最终 PR 的双 SDK Core 和 Native 检查再次执行。

## 原生 Release 主入口验证

运行产物来自同一工作树的本次构建。首次核对 example PID 14321 / app PID 22438，路径均在
`build/macos/Build/Products/Release`，并保存四份 executable/App.framework 哈希。
Debug 只构建，未另做 GUI。截图可在任务过程查看；仓库归档步骤与测试文件，不声称有截图附件。

1. example 使用默认完整语料，在 Source 末尾真实输入 `SOURCEFIDELITY`。逐步确认焦点后
   执行 Live→Read→Source，标记仍存在；Save 出现 `Host save callback invoked`，Reset 回到
   原始示例。原生 GUI 未对自定义 CRLF 整篇复制、全部选区与撤销/重做作精确验收，这些由
   两个主应用自动回归覆盖，实际键盘链路仍随 L08 完成。
2. app 打开专用临时目录的 `source.md`（208 字节、15 处 CRLF，无末尾换行）。内容含 YAML、
   中文、emoji、转义管道符、尾随空格、tab 和代码块。通过 View 菜单在 Source/Live/Read/Source
   往返；追加 `UNSAVEDRECOVERY` 后仍显示 Edited/CRLF。
3. 同时打开干净的 `second.md`，再新建无路径草稿并输入 `UNTITLEDRECOVERY`。草稿为活动
   标签，模式 Source。检查恢复存储中的完整测试原文精确相等，而 `source.md` 磁盘仍是原文。
4. 通过 ⌘Q 正常退出，确认旧 PID 不再存在，再启动同一个 Release bundle。原本地工作区、
   干净标签、带原路径的脏 source 文档、未命名草稿及其 Source 模式恢复；活动标签为草稿。
   该测试间隔已超过自动存储 debounce，退出前 350 ms 内输入不丢失的证明来自可控退出回归。
5. 打开恢复后的 source，画面显示完整语料和末尾标记、Edited、UTF-8、CRLF。⌘S 后文件
   **逐字节等于原文加标记**：223 字节、15 处 CRLF、无裸 LF、无末尾换行。关闭后从侧栏
   重开，显示相同内容和 Saved。恢复草稿随后另存为 `recovered-draft.md`，字节等于标记。
6. 原有 6 个文档的正文和已保存基线核对未变。只在专用测试目录写入；原始会话备份、
   访问书签和用户文档不进入仓库，仅发布测试文件及过滤后的布尔核验结果。

Computer Use 的 AX 文本有时落后于实际界面；同一调用内连续聚焦、选择和粘贴曾出现仅 AX
值改变、实际模型未变。这些尝试不计通过，重新按焦点/输入/模式切换分步操作，并以实际
存储和文件字节核验。ASCII 自动输入和载入中文内容均不是中文 IME 组合输入验收。

## 剩余工作和交付

L01 的自动全文/历史契约及 app 实际字节路径、L04 的本地恢复路径已完成本批验证。
L02/L03 沿用前一批并在本批复验相关路径。接下来按顺序推进：

1. L05：真实文件保存后继续输入，结合既有保存竞态/文件监视测试。
2. L06：两个主入口系统剪贴板、本地链接/图片，以及 app Read 的 Mermaid 和资源回退。
3. L07：两个主入口实际超预算大文档编辑、保存或复制，记录完整原文和实际延迟。
4. L08：真实中文 IME、候选取消、键盘选区/撤销/焦点；按需求验证读屏。

R3-03 随批维护门禁与文档，最终 PR 头需通过 Core required 和 Native integrations 后合入。
本批不等待上游 AOT，不启动独立宿主，不恢复外部项目作为前置要求；不新增性能基线结论。
证据总索引：[validation.json](results/2026-10-12-source-recovery/validation.json)。

CRLF 前后样本以 `source-before.md.gz` / `source-after.md.gz` 保存；解压后比较字节，避免文本换行转换或清理尾随空格改变证据。
