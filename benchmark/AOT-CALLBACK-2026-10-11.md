# R3-01：独立 Dart AOT 复现与回调缓存实验

日期：2026-10-11。本机 macOS 27.0.1 / arm64，Xcode 27.0。组件输入固定为
`24ea2fc5a52b349173c6a1920506868745cdf8b2`；本轮不改组件运行库、公共 API 或发布版本。

## 结论与验收边界

已将此前公共 View 的 `_Rect / illegal cid, full-aot` 失败缩小为 **17 行纯 Dart**，
只依赖 `dart:ffi`。原版 Dart 3.12.2 和 3.13.5 均复现。Debug 快照生成器给出从
FFI trampoline 的签名到被移除 Struct 类型的引用链；清理编译期回调缓存的实验补丁，
使相同 View kernel 和独立复现的快照生成均从失败转为通过。

这些配对结果支持“优化后失效的回调仍被缓存保留”这一诊断，但补丁尚未经 Dart VM
完整 FFI 回归或实验 AOT 运行时验证。没有把补丁装入日常 Flutter SDK，也没有生成并
验收完整的修复版 Flutter 应用。**R3-01 仍进行中，roadmap 仍是 16 项完成 13 项、剩余 3 项。**
正式支持仍需未修改的修复版 SDK、完整候选构建和真实交互证据。

## 最小复现

源码：[ffi_callback_aot.dart](../tool/fixtures/ffi_callback_aot.dart)，提交 `38290c4`。
SHA-256：`7d58e50355ae9fe06acd7c9ad2d81d37b528000ff87571116aa76f85b5be2038`。

```dart
import 'dart:ffi';

final class Rect extends Struct {
  @Double()
  external double x;
}

Pointer<Rect> position(Pointer<Rect> rect) => rect;
void main() {
  if (<int>[1].length > 1) {
    final callback =
        NativeCallable<Pointer<Rect> Function(Pointer<Rect>)>.isolateLocal(
          position,
        );
    callback.close();
  }
}
```

从仓库根目录，用待测原版 Dart 执行：

```sh
mkdir -p build/aot-manual
/path/to/dart --version
/path/to/dart compile aot-snapshot tool/fixtures/ffi_callback_aot.dart \
  -o build/aot-manual/callback.aot
```

| 原版 SDK | 来源 / revision | 编译结果 |
| --- | --- | --- |
| Dart 3.12.2 | 未修改 Flutter 3.44.8 所带 SDK；`d684a576a6aa954ae107a03b2b4e1d61c3bebe93` | wrapper 退出 254，`Class with illegal cid, full-aot`，类为 `Rect` |
| Dart 3.13.5 | 官方 macOS arm64 SDK 压缩包，下载哈希与官方校验值匹配；`04bcd1036cdc799ac6564988f159ee454d42c822` | 同样退出 254、同一类和错误签名 |

这里无需 Flutter 项目、Markdown 包、原生插件或网络资源。失败发生在编译阶段。
`<int>[1].length > 1` 在执行时为假，但不要把它改写成字面量 `false`：后者在探索对照中
编译通过，不能走到同一问题路径。输出文件存在也不等于编译成功，须检查退出码和日志。

## 从 View 到 FFI 的证据链

原版 Flutter 3.44.8 对同一组件 View 运行 `--trace_precompiler`，先记录 `_Rect`
被丢弃，再在序列化时报告非法 cid。使用与其 Dart revision 完全一致、未改 C++ 源码的
Debug `gen_snapshot` 对**同一 kernel**重放，得到如下引用链（省略地址和私有类编号）：

```text
Class: _Rect
  ← Type: _Rect ← TypeArguments ← Type: Pointer<_Rect>
  ← callback signature returning Pointer<_Rect>
  ← TrampolineData: c_signature=(Pointer<_Size>, Pointer<_Rect>, Pointer<_Rect>) => Pointer<_Rect>
  ← Function '_FfiIsolateLocalCallback': ffi-trampoline-function
  ← _List len:11
```

独立 Dart 复现的 Debug 日志也沿 `Rect → Pointer<Rect> → position → TrampolineData
→ _FfiCallbackposition → _List len:11` 报告引用者。
在该 Dart revision 的 [callback.cc](https://github.com/dart-lang/sdk/blob/d684a576a6aa954ae107a03b2b4e1d61c3bebe93/runtime/vm/compiler/ffi/callback.cc#L103)
中，trampoline 被放进 `ffi_callback_functions` 去重表；
[program_visitor.cc](https://github.com/dart-lang/sdk/blob/d684a576a6aa954ae107a03b2b4e1d61c3bebe93/runtime/vm/program_visitor.cc#L258)
也显式遍历这个表。结合下列配对结果，缓存保留失效回调是本次失败的有力解释；
不能仅凭相同错误字符串把所有上游报告认定为同一原因。

## 实验补丁与配对

仅在临时 Dart 3.12.2 源码目录的 `Precompiler::DropFunctions()` 末尾，
清空 closure 表后增加一行：

```cpp
IG->object_store()->set_ffi_callback_functions(Object::null_array());
```

完整 [实验补丁](results/2026-10-11-aot-callback/experimental-callback-cache.patch) 另含两行意图注释。
“活跃回调由生成的对象池保留”是该补丁要验证的假设，当前两个编译样例不足以证明其对
所有回调形态、安全点和快照模式都成立。原版与实验版使用相同 Debug 构建及链接配置，
每对使用相同 kernel；二进制、kernel、源码和日志哈希均保存。

| 输入 | 未改源码 Debug snapshotter | 实验 snapshotter | 证据 |
| --- | --- | --- | --- |
| 最终 17 行 Dart 复现 | 退出 -6，引用链指向 `Rect` | 退出 0，生成 AOT ELF | `experimental-final-paired.json` |
| 活跃回调：调用 nativeFunction 并检查返回指针 | 退出 0 | 退出 0，生成 AOT ELF | 同上；只是编译对照 |
| 公共 View，Flutter 3.44.8 product kernel | 退出 -6，引用链指向 `_Rect` | 退出 0，生成 AOT assembly | `debug-snapshot-backtrace.json` / `experimental-view.json` |

活跃回调另在**原版 SDK 的 JIT**下实际执行通过；它不等于实验版 AOT 的运行时验证。
Debug snapshotter 的 -6 是直接子进程终止码，与 `dart compile` 包装层报告的 254 分开记录。
早期 18 行含 `print` 的样例也做过跨版本及配对测试，原始源码单独归档为
`repro-with-print.dart.txt`；最终 17 行又完整复验，未把两个版本的哈希混用。

## 对照与构建过程

探索中的阴性结果一并保留，避免只选择成功定位的样例：

- 五种 Struct 创建、sizeof、NativeFunction 参数/返回值布局对照均编译通过。
- 三个仅保留 Flutter 内部 WindowScope/Dialog controller 路径的入口均编译通过；未运行内部窗口 API。
- 五个回调分支变体中，仅列表长度条件复现；空列表、字面量 false、常量函数和抛出路径四组通过。
- 2026-10-10 的十个纯 Flutter 对照及一个独立 FFI 对照仍保留在[前一份报告](AOT-REDUCTION-2026-10-10.md)。

Debug 工具从 Dart tag 3.12.2 对应的 `d684a576…` 构建，depot_tools 固定在
`a03dfbf7f2d1cefa2795d81d59ca4f16c8616a8f`。按该版本
[构建说明](https://github.com/dart-lang/sdk/blob/d684a576a6aa954ae107a03b2b4e1d61c3bebe93/docs/Building.md)
同步 DEPS，实际 `.gclient` 配置和脚本随证据保存。主要命令在 SDK 根目录执行：

```sh
python3 tools/gn.py -a simarm64 -m debug --no-rbe
buildtools/ninja/ninja -C xcodebuild/DebugSIMARM64 -j 8 gen_snapshot
```

本机经历三次构建环境问题，原失败日志均保留：depot_tools 的 Python 环境下载 TLS
握手失败，改用系统 Python 执行同一 `gclient.py` 完成依赖同步；首次不支持的 `--no-ide`
参数删除后 GN 通过；旧 LLVM linker 不识别 Xcode 27 SDK 的 TAPI 描述，链接命令改用
Xcode 自带 `ld` 后完成。未关闭 TLS 校验。原版与实验版均使用相同链接器，链接命令及
生成的构建规则差异已归档；日常 Flutter SDK 的跟踪源码保持干净。

## 证据、验证与后续执行

[归档目录](results/2026-10-11-aot-callback/) 含 128 份证据及
[SHA256.json](results/2026-10-11-aot-callback/SHA256.json)。原始日志使用确定性 gzip，
解压后匹配各摘要 `logSha256`；源码以 `.dart.txt` 保留原始字节，脚本以 `.py.txt` 保存
当时过程，临时绝对路径仅供溯源。kernel、二进制、assembly 和 SDK checkout 不进入 Git。
官方版本 JSON 的 CRLF 与补丁的上下文空格按原样保留，文本空白检查对这两份原始证据单独排除。
[validation.json](results/2026-10-11-aot-callback/validation.json) 记录 52 处日志哈希校验、
84 个 View 输入与固定提交逐项匹配，以及原版/实验版的配对关系。
最小复现的静态分析无问题、格式零改动，现有 Python 工具回归 10 项通过。

后续按以下顺序执行，操作步骤和留证字段见 [R3 执行清单](../doc/R3_ACCEPTANCE.md)：

1. 已获用户授权，将最小复现、Debug 引用链和实验边界发布到 [Flutter #191575](https://github.com/flutter/flutter/issues/191575#issuecomment-6110222678)，并回读核对。见[英文报告与发布记录](UPSTREAM-AOT-REPRO-2026-10-11.md)；下一步等待上游确认和正式修复候选，发布报告不代表补丁已被接受。
2. 出现正式修复候选后，先用本最小复现及公共 View 筛查，再对干净 SDK 执行完整六入口 Profile/Release 矩阵。当前实验补丁不能解除门禁。
3. 对通过构建的同一候选补真实 IME、键盘/焦点、跨应用复制及 VoiceOver；下一平台按实际宿主需求确定。
4. R3-02 两个真实外部宿主按用户安排留到最后提醒操作；通过后完成 R3-03 的 API、迁移与发布候选核对。目前不发布新版本。
