# 原生菜单与命令路由（R4-01）

入口固定为 `example/lib/main.dart` 与 `app/lib/main.dart`。基线 bd77b32，
原版 Flutter 3.44.8 / Dart 3.12.2。当前阶段：修复与专项回归已完成，全量门禁和 Release 验收执行中。

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

## 实现与专项结果

新增一个公开静态 `IanvsMarkdownShortcuts.invoke(command, controller: ...)`，复用现有局部
命令链；没有增加命令 enum。controller 只校验归属，返回 true 包含 composing 抑制，不能
理解成异步保存完成。两个 main 的 Edit/View 及 app Save 去掉重复 accelerator；其他宿主
菜单键保留，普通控件回退到自身 Actions。工具栏使用文本 TapRegion，属性草稿支持局部
撤销与保存，Read 历史按钮禁用，未定义局部语义的结构格式按钮不操作属性/表格。
app 窗口模式选择器在 composing 时不弹出；Save As 同样检查当前单元格的局部 composing。

专项：核心命令配置/调用 45、example main 5、app main 5 全部通过；Live/流式相关 426 项
已通过。主入口覆盖 Source、Live、属性、表格、Read、重映射/禁用、非编辑 Search Files、
保存/另存为与窗口模式选择器；组件测试另验 controller 替换、卸载和非 Markdown 焦点。
保存结果、选区/composing 与源文分别断言，不只检查 UI 标签。

首次全量发现默认 Tab 接管改变日期分段输入，以及新工具栏读取已脱离树的旧焦点；保留
默认 Tab 的控件处理并拒绝已脱离渲染树的焦点。随后发现监听表格局部 controller 会在
表格重建时触发工具栏重建，改为仅监听属性局部输入；表格使用已有文档通知和调用时校验。
这些中间失败不计为通过。表格/正文现有历史分组规则未改，本项不承诺整段输入法候选
只有一个撤销步骤；覆盖的是命令触发期间不会确认、撤销或丢弃正在组合的输入。

公共基线仍为 183 个导出，声明 1,146 → 1,147，仅 `invoke` 一项；契约、接入指南、迁移、
CHANGELOG 和两个入口说明已同步。全量门禁、包快照、Release 实操及人工 IME 尚待最终记录。
