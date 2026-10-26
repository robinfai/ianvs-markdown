# R4-02：两个实际主入口的性能采样协议 v1

本协议在正式测量前冻结。入口只用 `example/lib/main.dart`、`app/lib/main.dart`，
保留 Playground、Linefold 的页面树、工具栏、侧栏与文件工作流；不运行独立 benchmark main。
`IANVS_LOCAL_PERFORMANCE=true` 才显示 Run R4-02，普通构建默认关闭，公共 API 不变。
共享采样代码在未导出的 `lib/src/diagnostics/local_performance/`，仅供仓库主入口使用。

## 固定负载

语料生成器 `corpus.dart` v1：UTF-8 精确 10,240 / 102,400 / 1,048,576 字节，
包含中文、emoji、标题、段落、列表、代码与表格；行长度有界，不加载网络图片或原生图表。
每轮保留原始 corpus 文件，采集工具计算 SHA-256。默认预算不改，记录实际超限原因、
完整源文长度及 Reading 降级长度；不预设三份语料都走 Markdown。

每入口、每尺寸、每动作固定 5 次预热、20 次正式样本。每次动作前恢复同一文本，
清空历史，选择 UTF-16 offset 2，滚动到顶部，固定起始模式并等待两帧与宿主持久化。
准备、数据记录、文本完整性断言均在计时区间之外。每组采样后等待 1.1 秒接收批量帧报告。

| 动作 | 起点与计时范围 |
| --- | --- |
| sourceType / liveType | 对焦点 EditableText 调用 updateEditingValue 插入 ASCII a；包括输入格式器、组件和宿主同步通知 |
| sourcePaste / livePaste | 固定重复 32 次的 `paste 中文 😀 plain text. `，从 EditableText.userUpdateTextEditingValue 插入边界计时；与 Flutter 剪贴板读取后的插入路径一致，排除 OS 剪贴板读取，不改系统剪贴板 |
| liveToSource / sourceToRead / readToLive | 通过各主入口的模式命令回调切换；分别恢复 Live / Source / Read 后再测量 |
| sourceTail / liveTail | 实际滚动控制器逐帧 jumpTo 当前 maxScrollExtent，连续两帧 offset 与最大范围稳定才返回，最多 100 帧；callbackMs 包含懒布局收敛，记录 tailPasses，随后下一帧再次核对；不是键盘选区导航或通用 reveal API |
| app open | 先关闭测试文档并完成准备帧，再通过 WorkspaceController.openPath 读取同一临时文件并装载实际主页面；包含文档构建/通知/书签，另记文件读取耗时 |
| app save | 准备唯一的 `saved-阶段-索引` 后缀，通过 WorkspaceController.saveActive 原子保存；包括宿主完整异步回调，另记文件写入耗时；随后逐字验证磁盘文本和 dirty |

example 共 27 组 / 540 正式样本，app 共 33 组 / 660 正式样本。两轮分别重新启动进程，
串行完成 example-1、example-2、app-1、app-2；总计 2,400 正式样本、600 预热。
不按测量结果删慢项，不以旧独立入口数据补样本。

## 计时与环境

- callbackMs：动作调用到返回/异步完成；nextFrameMs：同一起点到下一帧 endOfFrame。
  frameWaitMs 是两者差值。endOfFrame 不代表像素已到显示器，不称物理输入到显示延迟。
- FrameTiming 按引擎共享 frameNumber 的 `(起始帧, 完成帧]` 归属动作，分别保存 build、raster、
  totalSpan、frameNumber 及 vsync 原始时钟；begin-frame 时间戳与 vsync 可有微秒差，不用于帧身份匹配。记录所有原始样本，再计算 nearest-rank P50/P95/max。
- RSS 是进程采样值，包含完整宿主、引擎与缓存；不是组件堆用量或泄漏结论。
  app 的文件读写时间嵌套于 callbackMs，不将两者相加；临时文件是暖缓存本地文件，
  不代表 iCloud 同步、冷盘或文件选择面板耗时。
  当前保存走 guarded 写入，write 计时覆盖该调用完整等待（包括原生冲突检查及协调写入），
  并非仅系统磁盘写 syscall 时间。2026-10-26 enhancement 四轮旧采样遗漏 guarded 方法，
  其中保存 diskMs=0 不可用；动作总耗时与下一帧数据保留，不能用这些零值解释保存变慢。
- 输入和批量插入均为框架合成输入。物理 IME、系统剪贴板、CUA 往返不混入延迟样本。
- 使用干净的原版 SDK。先构建两个实际 main 的 Profile；若失败保留日志并评估同模式
  Release。不能修改 SDK 或新增替代宿主来取得通过。
- 编译时冻结 revision 与输入清单摘要，采集时核对源码、SDK、锁文件、构建模式与二进制。
  记录 OS/Xcode、窗口尺寸/位置/屏幕/scale、像素尺寸、文字缩放、主题和输入字体配置。
  两轮同入口环境一致；两个入口保留各自默认窗口宽度，不要求横向成绩直接可比。
- 原生窗口状态通道仅诊断时订阅：失去前台、隐藏、遮挡、移到其他 Space、缩放/移动窗口，
  或变化后恢复，均使当前轮无效。记录完整失败和部分样本，不拼接补齐。
- 运行异常、缺少帧、源文/保存校验失败、缺样本、输入清单变化均无效；每帧等待上限 30 秒。
  正式运行期间不并行构建、测试或操作其他窗口。
- app 仍使用真实 DesktopMarkdownFileService/AppleWorkspaceService。诊断模式使用独立临时
  会话目录，不恢复用户文档，不触发文件关联提示/变更，不连接 iCloud 默认工作区；
  这些隔离条件是固定基线边界，后续候选必须相同。

## 交付与后续配对

每入口至少两次完整有效结果。有效性校验同时读取 result、trace、冻结清单和语料；
拒绝重复 PID、重叠运行、窗口变化、重复/缺少事件、不同源文件/SDK/构建条件。
观察线预先采用两轮 P95 最大值的 1.20 倍与“最大值 + 2 ms”中的较大值；
RSS、帧耗时另报，不把观察线称为统计显著性或跨机器 SLA。
R4-03 先选两轮可复现的热点，再冻结候选改善目标；本项不宣称性能改善。

命令和正式结果在本批验收报告中补齐。实现/协议、校验器、最终测量证据分步提交。
外部产品验收仍留到最终分发阶段。
