# 原生菜单与命令路由（R4-01）

入口固定为 `example/lib/main.dart` 与 `app/lib/main.dart`。基线 bd77b32，
原版 Flutter 3.44.8 / Dart 3.12.2。当前阶段：已复现，修复与 Release 验收待执行。

## 修复前复现

实际应用 Widget 挂载后，通过 `SystemChannels.menu` 的 `Menu.setMenus` 取得 ID，
发送 `Menu.selectedCallback`；并非直接调用待测 controller。合成 composing 不等同原生 IME。

| 场景 | 预期 | 基线实测 |
| --- | --- | --- |
| example 属性 author 局部输入后 Undo | 键盘和菜单均撤销属性草稿，正文不变 | Cmd+Z 成功；菜单 Undo 保留 Changed again，失败 |
| example Source composing 中菜单 Read | 保留 Source、选区与 composing | 切到 Read，失败 |
| example 将 Undo 改为 F3 | 原生菜单不注册冲突的默认 accelerator | 仍注册 Cmd+Z，失败 |
| app Source composing 中菜单 Undo | 输入值、选区与 composing 不变 | ni 被撤销、composing 清空，失败 |
| app Source composing 中菜单 Read | 保持 Source | 切到 Read，失败 |

example 三项、app 两项回归均在行为断言处失败。
[example 原始日志](results/2026-10-13-command-routing/example-before.log.gz)、
[app 原始日志](results/2026-10-13-command-routing/app-before.log.gz)。

## 路由策略与后续验证

- 菜单显式操作不受键位禁用/重映射影响；编辑命令 accelerator 由 Flutter 焦点路由拥有，
  原生 Edit/View 菜单不再重复注册。宿主 File/Window 命令仍由宿主决定。
- 按当前焦点由属性/表格/正文向外委派；属性撤销只改局部草稿，保存/切模式先提交草稿。
- composing 期间抑制编辑命令，不隐式确认或丢弃；键盘、菜单、工具栏均需覆盖。
- Read 的历史/修改命令不改正文；非编辑控件使用自身 Actions，不操作旧正文选区。
- 修复后补齐菜单/快捷键/工具栏、禁用/重映射、Read、表格、非编辑焦点与卸载隔离回归，
  执行全量门禁、两个实际 Release 菜单操作，重新人工确认中文 IME。
