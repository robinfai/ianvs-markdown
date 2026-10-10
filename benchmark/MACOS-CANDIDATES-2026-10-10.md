# R3-01 macOS 候选构建复核

日期：2026-10-10。组件输入基于已合入的 `6b2db7f7902a41835ed2a07469b99b0d0b6e98be`，
不包含独立 PR #9 的性能优化。验证工具见 [check_macos_candidates.py](../tool/check_macos_candidates.py)。
组件版本仍为 `0.3.1` + `Unreleased`，未发布新版本。

## 结论与支持边界

三套未修改 Flutter SDK 各完成 12 次构建，共 36 次：18 次成功，18 次在 AOT 阶段失败。
纯 Flutter 对照、正文 Body 和综合 playground 的 Profile/Release 均通过；
Reading、Editor、Streaming 在三个 SDK 的两种模式均触发 `_window_macos.dart / _Rect` 的
`Class with illegal cid, full-aot`，`gen_snapshot` 退出码为 -6。
最低 SDK 候选已实际执行，但完整矩阵没有通过，R3-01 保持「进行中」。

| 入口 | Flutter 3.44.0 / Dart 3.12.0 | Flutter 3.44.8 / Dart 3.12.2 | Flutter 3.47.6 / Dart 3.13.5 |
| --- | --- | --- | --- |
| 纯 Flutter 对照 | Profile、Release 通过 | Profile、Release 通过 | Profile、Release 通过 |
| `body.dart` | Profile、Release 通过 | Profile、Release 通过 | Profile、Release 通过 |
| `reading.dart` | Profile、Release AOT 失败 | Profile、Release AOT 失败 | Profile、Release AOT 失败 |
| `editor.dart` | Profile、Release AOT 失败 | Profile、Release AOT 失败 | Profile、Release AOT 失败 |
| `main.dart` | Profile、Release 通过 | Profile、Release 通过 | Profile、Release 通过 |
| `streaming.dart` | Profile、Release AOT 失败 | Profile、Release AOT 失败 | Profile、Release AOT 失败 |

三个 SDK 的日志均保留在 [证据目录](results/2026-10-10-platform-candidates/)。
[3.44.0 摘要](results/2026-10-10-platform-candidates/stock-3.44.0/summary.json)、
[3.44.8 摘要](results/2026-10-10-platform-candidates/stock-3.44.8/summary.json)、
[3.47.6 摘要](results/2026-10-10-platform-candidates/stock-3.47.6/summary.json)
包含逐入口命令、工具链、源码及日志 SHA-256、耗时、退出码和成功产物的架构/哈希。
`complete: true` 表示所有构建都已执行；`passed: false` 表示矩阵没有通过，runner 退出 1。

该结果仅覆盖本机 macOS 27.0.1、arm64、Xcode 27.0 (27A266a) 的构建。
没有启动这些候选产物，没有验证 macOS 12、x64、真实 IME、跨应用复制、VoiceOver 或其他平台。
构建耗时受并行编译与缓存影响，不用于性能比较。R2 的 GUI 基准在全部构建结束后才启动。

## Flutter 3.47.7 的 Reading 定向复测

2026-10-10 补测未修改 Flutter 3.47.7 / Dart 3.13.5，SDK revision 为
`abaf9c523780a608bd46686fd5e53740a07077f8`。官方
[3.47.6…3.47.7 差异](https://github.com/flutter/flutter/compare/3.47.6...3.47.7)
记录了 iOS OverlayPortal 无障碍修复和版本同步，不能由版本升级推断本问题已修复。
[标签和比较结果](results/2026-10-10-platform-3477/)随原始证据归档。

分别使用两个已提交的组件输入，各构建纯 Flutter 对照和 Reading 的 Profile/Release：

| 组件输入 | 纯 Flutter 对照 | Reading | 证据 |
| --- | --- | --- | --- |
| 已合入的 `3234d44` | 两种模式通过 | 两种模式均 `_Rect` AOT 失败 | [摘要](results/2026-10-10-platform-3477/stock-3.47.7-reading/summary.json) |
| PR #9 优化版本 `d882078` | 两种模式通过 | 两种模式均 `_Rect` AOT 失败 | [摘要](results/2026-10-10-platform-3477/stock-3.47.7-optimized-reading/summary.json) |

新增 8 次构建中 4 次通过、4 次失败，两次执行均 `complete: true`、`passed: false`，
没有超时或 runner 错误。`3234d44` 的全部输入哈希与上述 3.47.6 历史矩阵一致；
`d882078` 包含 renderer 隔离、引用/标题解析和 Source 背景布局优化。
每份输入哈希均与各自提交内容匹配，日志哈希已核验；每组使用独立临时宿主并在结束后清理。
这表明已实施的 R2 优化没有消除该 Reading 构建失败，不能用旧源码失败替代此验证。

此次没有在 3.47.7 重跑 Body、Editor、playground、Streaming，也未启动产物或执行设备交互；
不把定向结果扩大为第四套完整矩阵。R3-01 仍在进行中，最低 SDK 与 CI 配置保持原约束。
复测命令使用前述工具，增加 `--target reading --include-control`，每次使用新标签。
全部 20 个证据文件见 [SHA256.json](results/2026-10-10-platform-3477/SHA256.json)，历史三 SDK 目录未覆盖。

## 复现与证据约束

从仓库根目录执行，每次使用新标签与未修改 SDK。完整矩阵失败退出是本次已知结果：

```sh
python3 tool/check_macos_candidates.py \
  --flutter /path/to/stock/flutter/bin/flutter \
  --label candidate-new-run --include-control --keep-host
```

工具复制 Git 跟踪的库及 example 输入到仓库外的全新目录，单独解析依赖。
它检查实际 Flutter 和组件依赖路径，保存解析后的锁文件，拒绝未跟踪的库/示例输入。
SDK 检查前后必须没有跟踪文件改动，且版本 JSON 与 Git revision 一致；
运行期间源码输入哈希必须不变。工作区已有的跟踪文件修改会按实际内容复制并记录 diff 哈希。
每次构建先移除该临时目录中本模式的旧 bundle，成功退出后还验证新产物的
Info.plist、可执行文件、App.framework 和本机架构，避免把旧产物计作本次通过。
超时只终止本次构建的进程组。默认清理临时宿主，`--keep-host` 可保留诊断现场。

三套 SDK 均使用 `CARGO_PROFILE_RELEASE_STRIP=none`、`FLUTTER_XCODE_ARCHS=arm64`；
3.44.0 与 3.47.6 来自临时 SDK 副本切换到对应标签并 precache，3.44.8 使用日常 SDK。
没有把 R2 临时 windowing 补丁用于候选构建。
[补丁 SDK 拒绝记录](results/2026-10-10-platform-candidates/patched-sdk-rejected.log)
证明 runner 在创建候选输出前拒绝该 SDK；
[重复标签拒绝记录](results/2026-10-10-platform-candidates/duplicate-label-rejected.log)
证明已有输出不会被覆盖，拒绝后原证据哈希保持不变。

## 公共 View API 的最小入口

[12 行诊断入口](../tool/fixtures/macos_view_aot.dart) 只创建 MaterialApp、Scaffold 和
IanvsMarkdownView，通过公共 API 展示一小段 Markdown。它在上述保留的 3.44.8 宿主中
以 Release 构建仍然复现同一错误；
[结果](results/2026-10-10-platform-candidates/minimal-view-summary.json) 与
[原始日志](results/2026-10-10-platform-candidates/minimal-view-release.log) 已保存。
“最小”指缩小后的应用入口，仍依赖本组件完整源码，不是纯 Flutter 的独立最小复现。

复现时先运行上面的 `--keep-host` 矩阵，再读取其 summary 使用相同临时宿主：

```sh
python3 - <<'REPRO'
import json
import os
from pathlib import Path
import shutil
import subprocess

report = json.loads(Path('build/platform-candidates/candidate-new-run/summary.json').read_text())
host = Path(report['hostDirectory']) / 'example'
shutil.copy2('tool/fixtures/macos_view_aot.dart', host / 'lib/aot_minimal_view.dart')
flutter = report['dependencyResolution']['command'][0]
result = subprocess.run([flutter, 'build', 'macos', '--release', '--no-pub',
                         '--target', 'lib/aot_minimal_view.dart'], cwd=host,
                        env=dict(os.environ, **report['environment']))
raise SystemExit(result.returncode)
REPRO
```

## 与上游问题的关系及后续动作

截至 2026-10-10，[Flutter #191575](https://github.com/flutter/flutter/issues/191575)
仍为 Open，报告了相同 framework 类名与 AOT 失败签名。
本机矩阵及缩小入口为可重复的本地证据；签名一致不能单独证明全部根因相同。
本次没有向上游发送 issue 或评论，也没有修改 SDK 或公共组件行为来绕过编译失败。

1. 保留本报告为当前三个 SDK 的入口限制；不能用综合示例成功覆盖最小阅读/编辑入口失败。
2. 在干净 SDK 或上游候选修复上重跑同一矩阵及缩小入口；只有对应入口实际通过才更新支持结论。
3. R2 优化落地后，按最终组件输入重验目标 SDK 构建，并进行真实 IME、复制、焦点和读屏检查。
4. R3-02 两个仓库外宿主仍需候选包接入与实际平台交互；本工具的临时构建宿主不抵扣该任务。

所有证据文件的索引为 [SHA256.json](results/2026-10-10-platform-candidates/SHA256.json)。
源码输入、工具版本、SDK、锁文件与失败记录共同限定这次结论，后续复测新增目录而不覆盖历史。
