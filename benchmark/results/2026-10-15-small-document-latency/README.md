# R4-03 小文档诊断与候选证据

`diagnostics/` 全部为独立归因协议，不计正式性能验收。

- `runs/r403-small-tk*` 保留本轮两种 TextKit 对照、受观察者效应影响的早期轮次及两次失焦无效轮，不拼接。其他运行是上一批的副本，仅保留上下文，不纳入本轮结果。
- `builds/` 是两个实际 main 的构建冻结；Dart 相同，只切换两宿主原生 override。
- `instrumentation/` 保留临时保存分段补丁和辅助文件，已从生产代码移除；原 TextKit 1 宿主实现已恢复。
- `cpu/` 保存区间内全部样本；仅省去从未出现在样本栈里的函数表项，按 `originalFunctionIndex` 映射新下标。原完整 VM JSON 的 SHA 保存在 `originalSha256`，原件留在本地 build 目录。统计由样本栈重算，递归函数每样本计一次。
- `tk1-app-cpu` / `tk1-example-cpu` 在动作之间查询 VM，存在观察者效应。其余带 `deferred` 的 CPU 提取均在整轮完成后进行。失焦轮未提取 CPU。
- `summary.json` 区分本轮与旧上下文；无效轮带错误，必须排除。result / trace 使用无时间戳 gzip，receipt 的 SHA 对应解压后的原文件。

正式候选结果随后单独归档。测量与决定见 [报告](../../SMALL-DOCUMENT-LATENCY-2026-10-15.md)。
