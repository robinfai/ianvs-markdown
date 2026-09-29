# Sidebar 三期验收记录

实现范围来自 [原始三期清单](sidebar-enhancement-plan.md)。完整验收入口：

```sh
bash app/tool/verify_sidebar.sh
```

脚本在 `app/build/sidebar-acceptance/` 保存格式、静态分析、应用测试、原生文件测试、macOS 构建日志及三张侧栏截图。测试使用独立内存文件服务或专用临时文件；原生废纸篓测试会恢复它创建的测试目录后清理。

## 本次结果（2026-09-29）

| 门禁 | 结果 |
| --- | --- |
| Dart 格式检查 | 52 个文件，0 项格式变更 |
| Flutter 静态分析 | No issues found |
| 完整应用测试 | 143 通过，1 个既有外部语料测试跳过 |
| macOS 原生文件操作 | 独占创建、复制、碰撞、自包含拒绝、目录移动、废纸篓及恢复全部通过 |
| macOS debug 构建 | 成功生成 `build/macos/Build/Products/Debug/Linefold.app` |
| 截图检查 | normal / narrow / search 三态已生成并检查 |
| Patch 空白检查 | `git diff --check` 通过 |

## 需求与证据

| 阶段 | 需求 | 实现 / 自动化证据 |
| --- | --- | --- |
| 一 | 定位当前文档、展开祖先、滚动和短暂强调 | `FileBrowserController.reveal` 与侧栏 reveal revision / 1.2 秒强调；controller reveal/follow 测试、widget reveal/search 测试 |
| 一 | 可选自动跟随，默认关闭 | controller opt-in 测试；widget `folder retry and optional follow…` 验证菜单开启并自动展开深层文档 |
| 一 | 按工作区恢复展开、滚动、排序 | controller JSON recovery；widget 1000 行列表搜索返回、卸载重挂载及创建新 WorkspaceController 后恢复真实滚动位置 |
| 一 | 刷新不折叠或跳回顶部 | `workspace_tree_refresh_test.dart` 的 Save As、搜索刷新、滚动保持回归 |
| 一 | ↑↓、←→、Enter、Escape 与独立焦点 | widget keyboard 测试验证移动焦点不切文档、Enter 打开、父子导航；搜索 Escape 回到树 |
| 一 | 文件名/路径搜索、排名、高亮、父路径 | controller ranking/path 测试；widget search/reveal/relative-path copy；`sidebar-search.png` 真实字体/图标渲染 |
| 一 | 结果数量、200 条上限与过期查询取消 | controller 260 条命中测试、阻塞旧查询后取消测试、跨工作区迟到读取测试 |
| 一 | 自然排序、修改时间排序，目录优先 | controller natural/modified 测试，包含大整数；external metadata 测试验证外部文件自身修改时间排序且不扫描父目录 |
| 一 | 未保存圆点、空目录、错误重试 | widget dirty indicator 和 folder retry；空目录由 BrowserRow 状态行呈现；宽窄截图无布局异常 |
| 一 | 180 pt 最小宽度可用 | widget 最小宽度下菜单定位与行内编辑；`sidebar-narrow.png` 截断与布局检查 |
| 二 | 行内新建文件/目录、默认 .md、重名和非法名校验 | widget inline create/collision/folder/Escape；controller Unicode、非法路径名、同名拒绝；native exclusive create 测试 |
| 二 | 重命名保留扩展名选区、脏内容与标签身份 | widget rename 选区和未保存内容；controller 目录重命名同步所有打开后代、收藏、展开路径及恢复快照 |
| 二 | 创建副本 | controller 连续副本唯一命名，复制磁盘已保存内容；widget Duplicate Saved Copy |
| 二 | 移动选择器、跨目录、拒绝覆盖/自包含 | widget 多选目录选择器和碰撞预检；controller root/descendant/collision 测试；native move/copy no-replace 测试 |
| 二 | 保存与文件操作时序一致 | controller 并发 move/save 使用新路径；失败 move 保持旧身份；已删除会话的排队保存不会重新创建文件 |
| 二 | 废纸篓及后代文档 Save / Discard / Cancel | widget 三条交互路径；controller 未授权丢弃拒绝、后代保护；native 真实 Trash/restore |
| 二 | 删除期间的新编辑可恢复 | controller 阻塞 Trash 期间输入新内容，验证保留无路径草稿及恢复快照 |
| 二 | 外部文件授权与目录边界 | widget 创建外部文件时的授权对话框；controller 不扫描外部父目录；合成外部目录没有整目录改名/删除入口，batch Trash 仅处理已打开文件并保留未展示文件 |
| 二 | 相对路径复制、相对链接影响说明 | widget mock clipboard 校验 `docs/deep.md`；重命名和移动成功反馈明确链接未被改写 |
| 三 | 文件/目录收藏、按需展示、恢复 | widget 添加/删除/序列化收藏；controller 外部文件关闭后保留 bookmark 并恢复打开；外部目录收藏先取得目录授权 |
| 三 | Command/Control 与 Shift 多选、批量操作 | widget 多选移动、Shift 范围选择、批量部分失败计数；批量目标去重且去除重复子路径 |
| 三 | 拖拽到目录及工作区根 | widget pointer drag 测试覆盖根标题、树下空白、根文件行三种投放；子目录拖回根保留脏后代会话；同目录投放不误移到根；合成外部目录仅作目标/分组，不能作为整目录拖动源 |
| 三 | 大列表虚拟化与增量索引 | widget 1000 行只创建有限可见 Draggable；controller 第二次搜索不重新读取目录，文件事件只重新读取受影响目录 |
| 三 | 外部事件和异步生命周期 | controller 局部刷新、取消、root epoch 和 reveal generation 测试；widget 文件事件更新可见行 |

## 验收范围说明

- `flutter test` 覆盖完整应用测试集；既有 `llm_series_render_test.dart` 在未提供 `LLM_SERIES_DIR` 时跳过外部语料验收，与侧栏功能无关。
- 原生测试直接运行应用使用的 `WorkspaceFileOperations`，不是替代实现；macOS debug 构建验证同一实现及 MethodChannel 桥接编译。
- 截图由真实 Flutter 侧栏、系统字体和 Material 图标生成，覆盖正常、180 pt 窄栏及搜索态；截图不是整个原生窗口的端到端交互测试。
- 按设计，全文内容搜索与自动改写 Markdown 链接不属于本次三期范围。复制副本使用已保存内容；外部目录分组不代表磁盘完整目录。

## 根目录拖拽回归

用户反馈“从子目录拖动到根目录失败”。修复前新增的空白区域投放测试确实失败；
此前只覆盖了标题条。现将树末尾空白作为独立根目录目标，文件行则指向其父目录，
悬停显示实际目标。使用独立目标而非包裹整棵树，避免被拒绝的子目录投放意外落到根。
回归覆盖直接纵向拖到标题、空白区域、根文件行、同目录无操作、文件夹及脏文档路径同步。
