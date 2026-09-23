# 焦点几何修复与回归

日期：2026-09-22。实现遵循已完成的两轮 imagegen 评审及 `design-review-round-2.md`；生成图只用于设计约束，以下结论来自运行中的 Flutter 布局与交互测试。桌面应用最终截图复验由主代理执行。

## 已定位的原因

- 展示段落使用 `bodyMedium` 与 Markdown 样式合并，TextField 却隐式继承 `bodyLarge`；字距、字体以及 compact visual density 的内边距不同。最初普通段落、标题和列表聚焦后通常矮 6 px，首行基线上移 3 px。
- 引用进入编辑回退为正文字号；活动行的 `>` 进入正文宽度，引入重新折行。引用现在共享引用字号、内边距，并把活动标记绘制在固定边栏槽位。
- 列表的展示和编辑 gutter 不同，有序数字还可能在窄 marker 区内折成两行。结构 marker 现在保持完整源码 offset，但在正文流中占零宽；列表 marker 使用固定单行。
- Setext 的隐藏 underline 保留了一个具有正常 strut 的换行，增加一行高度。显示投影改为等长零宽字符，控制器和保存内容仍保留完整原文。
- 围栏和缩进代码的字体、背景、padding 不同；围栏源代码行原先又增加额外高度。现在围栏标记可编辑，并使用卡片原有的上下 inset；缩进代码保留与展示态相同的代码卡片。
- 普通链接的展示态是带外链图标的原子 inline widget，编辑态原先只是文字。未选中链接时复用同一个链接 renderer；选择进入链接范围后，沿用原来的源码展开和编辑规则。
- 高亮 renderer 的 `KeyedSubtree` 阻止 Markdown 合并行内 span。真实字体窄屏下会额外换行。高亮现在直接返回可合并的文字，完整样式保留在叶 span 中，背景与嵌套格式回归均通过。
- 有效 YAML 在 `showFrontMatter: false` 时落入通用 Markdown renderer，导致 title/tags 出现在正文。现在 Live 中零占位隐藏；autofocus、光标误入 YAML、向上导航均落到首个可见正文。Source 保留原文。

## 验证

`test/focus_geometry_test.dart` 共 107 项：

- 25 类内容 × 720/320 两档正文宽度 × 1.0/1.3 两档文本缩放，共 100 项；包含中英混排、长行、普通/软换行段落、粗斜体/删除线/高亮/行内代码/链接、H1–H6/Setext、无序/有序/嵌套/任务列表、同层多行/等深嵌套引用、围栏/缩进代码及长代码。
- 每项断言 block height、首行 payload baseline、后续 block 的 y 保持一致，误差不超过 0.01；scroll offset 不变；点击不改源文、不置 dirty、不新增 undo；失焦恢复相同块高度。
- 额外 7 项覆盖 YAML 隐藏与 Source/Live 切换、autofocus/向上导航、链接 URL 展开编辑和撤销，以及 0/1/2/4 空行的围栏代码卡片。
- 默认字体运行通过；macOS 真实 SF、SF Mono、宿主 CJK 字体运行也 107/107 通过。测试加载 CJK 字体替代 Flutter 测试的 Ahem fallback，以实际字形度量检查窄屏换行。

最终命令与结果：

```sh
flutter test --reporter expanded
# 874/874 通过，32 秒。

flutter test test/focus_geometry_test.dart --dart-define=LINEFOLD_SYSTEM_FONTS=true --reporter expanded
# 107/107 通过，9 秒。
```

日志：`/tmp/linefold-root-full.log`、`/tmp/linefold-focus-fonts-final.log`。

## 旧断言的调整理由

- 字体断言由 `null` 改为宿主主题解析后的字体；这保证两态继承同一字体。
- marker 字号由 4 改为 0；原文仍由控制器保留，显示 marker 由固定 gutter 提供。
- 引用不再断言活动行 `>` 进入正文；改为断言隐藏 prefix 数量与既有边栏绘制。
- Setext 不再要求隐藏的显示 span 含有字面 underline；改为等长、零字号检查，同时保留控制器原文断言。
- 代码外 margin 改为展示态原有的 8 px 加块外 3 px，缩进代码必须保留背景卡片；fence rail 直接对齐真实 caret 度量，替代只适用于正文字号的 14–16 px 常数。
- task 的既有点击测试原先用硬编码 19，改为所点击的可见 offset 6 对应的 `source.indexOf('bravo')`（20）。其他语法选择、键盘和精确源码 offset 断言保留。
- 高亮测试检查背景和嵌套格式本身，替代已移除 wrapper 的诊断 key；点击仍校验原来的 source offset。

## 保留的交互边界

普通正文获得焦点时保持上述布局。用户明确进入 inline 标记、URL 或公式的源码编辑范围时，保留现有源码展开能力；展开出的完整文字可能增加换行。这与未编辑链接本身时仅点击同段正文的稳定布局分开验证，不能把两者合并宣称为所有源码编辑均不增加高度。
