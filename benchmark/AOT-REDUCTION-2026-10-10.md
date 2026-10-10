# R3-01 AOT 缩小复现记录

日期：2026-10-10。组件输入为已合入 `0974263adb24f400eaaf8034af0011ab0ad46cf3`。
工具链为未修改 Flutter 3.47.7 / Dart 3.13.5，SDK revision
`abaf9c523780a608bd46686fd5e53740a07077f8`，本机 macOS arm64。

## 结论

公共 `IanvsMarkdownView` 的 12 行入口在直接 AOT 编译中继续触发
`_window_macos.dart / _Rect`、`Class with illegal cid, full-aot`，快照生成退出 -6。
十个纯 Flutter 对照及一个独立 Dart FFI 对照均通过。随后用正式隔离工具重放
纯文本、公共 View、独立 FFI 三组，结果一致。没有得到不依赖组件库的失败复现，
也没有证明某个 Markdown 功能或框架控件是根因。

本轮只运行编译器：Flutter frontend 生成 product kernel，再执行 arm64
`gen_snapshot --snapshot_kind=app-aot-assembly`；独立 FFI 使用 `dart compile aot-snapshot`。
没有生成或启动完整 macOS bundle，不计入此前的 Profile/Release 候选构建次数，
也不构成真实 IME、剪贴板、VoiceOver 或外部宿主验收。R3-01 仍进行中。

## 实际对照

| 输入 | 结果 | 能说明的边界 |
| --- | --- | --- |
| `Text` | 通过 | 最小 MaterialApp/Scaffold 可完成该编译路径 |
| `SelectionArea` + Text | 通过 | 单独的文档选择面不足以触发本次错误 |
| `SelectableText` | 通过 | 单独的可选文本不足以触发 |
| `TextField` | 通过 | 单独输入控件不足以触发 |
| `Tooltip` | 通过 | 单独提示控件不足以触发 |
| 选择面、输入框、Tooltip、PopupMenuButton 的组合 | 通过 | 该小型组合不足以触发；不代表任意组合都通过 |
| `Scrollable.ensureVisible` | 通过 | 单独保留滚动定位路径不足以触发 |
| `findAncestorStateOfType<EditableTextState>` | 通过 | 单独查找可编辑祖先不足以触发 |
| `visitAncestorElements` | 通过 | 单独遍历祖先不足以触发 |
| `dependOnInheritedWidgetOfExactType<InheritedWidget>` | 通过 | 该继承查询对照不足以触发 |
| 公共 `IanvsMarkdownView` | frontend 通过，快照失败 -6 | 与完整 Reading 候选构建的 framework 类名和错误签名相同 |
| 独立 Dart `NativeCallable` 返回 Struct 指针 | 通过 | 该 FFI 回调形状本身不足以复现；未执行任何原生回调 |

纯 Flutter 对照的直接依赖只有 Flutter SDK；独立 Dart 对照只有 `dart:ffi`。
公共 View 仍依赖组件库及其依赖图，不能称为纯 Flutter 最小失败样例。
这些是特定程序上的编译结果，不排除全程序类型分析或其他组合影响。
[上游同签名报告 #191575](https://github.com/flutter/flutter/issues/191575)
提出了全程序类型分析的假设；本轮没有独立证实这一原因，没有发送上游消息。

## 可复验工具

[reproduce_macos_aot.py](../tool/reproduce_macos_aot.py) 为每次运行创建新的临时宿主，
拒绝修改过的 SDK 与重复标签。`--component` 复制当前跟踪的核心源码到隔离目录，
记录输入哈希、宿主解析锁文件并核对实际依赖路径。前后检查 SDK 和输入是否变化；
日志、源码副本、工具哈希和摘要写入 `build/aot-reduction/<label>`，临时产物自动清理。
工具限定 macOS arm64，既不替代 `flutter build macos`，也不自动修复 SDK。

从仓库根目录执行，每次换新标签：

```sh
python3 tool/reproduce_macos_aot.py \
  --flutter /path/to/stock/flutter/bin/flutter \
  --source benchmark/results/2026-10-10-aot-reduction/text.dart.txt \
  --label control-new-run

python3 tool/reproduce_macos_aot.py \
  --flutter /path/to/stock/flutter/bin/flutter \
  --source tool/fixtures/macos_view_aot.dart --component \
  --label view-new-run

python3 tool/reproduce_macos_aot.py \
  --flutter /path/to/stock/flutter/bin/flutter \
  --source benchmark/results/2026-10-10-aot-reduction/ffi_callback.dart.txt \
  --dart-only --label ffi-new-run
```

当前 SDK 下第二条命令预期退出 1，摘要为 `complete: true`、`passed: false`、
`windowingAotFailure: true`。它表示工具完整执行且目标编译失败，不能记作平台通过。
其他纯 Flutter 源码也可通过更换 `--source` 单独复验。

## 证据与验证

[证据目录](results/2026-10-10-aot-reduction/) 保留探索阶段的四份摘要、全部源码、
实际临时脚本、锁文件、压缩原始日志，以及正式工具的三个独立重放目录。
探索脚本保留当时的临时路径，仅作为过程证据；后续复验使用上述正式工具。
`.dart.txt` 保存受测源码的原始字节，避免后续格式化改写历史哈希。
`.log.gz` 解压后与摘要中的原始 `logSha256` 对应，压缩文件自身由
[SHA256.json](results/2026-10-10-aot-reduction/SHA256.json) 索引。

正式工具的三个重放均完成，SDK 前后无修改。View 的隔离输入哈希逐项匹配
`0974263` 的提交内容；源码、工具与日志哈希均核验。补丁 SDK、重复标签、冲突模式、
非正超时的拒绝检查通过，重复标签检查后已有证据保持不变。Python 语法检查和现有
10 项工具回归通过。本轮没有改动运行库或示例，没有重跑已经验收的全量 GUI 性能基线。

下一步仍是在干净 SDK 的修复候选上先复验公共 View，再重跑
[完整候选矩阵](MACOS-CANDIDATES-2026-10-10.md)，之后补平台交互证据。
两个真实外部宿主按用户安排留到最后提醒操作；本轮临时宿主不抵扣 R3-02。
