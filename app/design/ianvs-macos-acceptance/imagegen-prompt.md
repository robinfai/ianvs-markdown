# ImageGen 视觉验收图提示词

使用内置 `image_gen` 工具。生成图仅作视觉汇总；原始 Flutter 截图与实际测试日志是验收依据。

参考图：`desktop-light.png`、`desktop-dark.png`、`desktop-root-drop.png`、`desktop-narrow-large-text.png`。

```text
Create a single polished visual acceptance review board for Linefold, a macOS Markdown editor. Use the four provided images as the actual UI evidence: image 1 is the final light theme, image 2 is the final dark theme, image 3 shows a file hovering over the workspace-root drop target, and image 4 is the minimum window at 200% text size.

This is a review presentation of an implemented product, not a new UI concept. Preserve the referenced screens' layout, UI colors, filenames, hierarchy, document text and controls as faithfully as possible. Do not add invented features or change the interface. Do not add Apple logos, macOS traffic-light controls, or certification seals.

Composition: a spacious landscape review sheet with a warm off-white background, understated graphite typography and small blue checkmarks. Two large, equally weighted light/dark screen panels across the upper portion. Below, two generous detail panels: a close view of the root-drop area from image 3, showing the complete “Move to Linefold” label and sidebar-design.md drag chip; a close view from image 4 showing the enlarged toolbar, search and file rows. Keep text in screenshots legible and preserve aspect ratios. Use quiet dividers, consistent spacing and restrained rounded corners. Avoid decorative device frames or exaggerated shadows.

Exact outside labels in Simplified Chinese:
Main title: “Linefold · Ianvs Design”
Subtitle: “macOS 视觉验收 · 2026.09.29”
Panel 1: “浅色主题”
Panel 2: “深色主题”
Panel 3: “根目录落点清晰”
Panel 4: “200% 文字可用”
Small summary: “视觉检查通过”
Small evidence line: “147 项自动化测试通过 · macOS 构建通过”
Footer must clearly state: “ImageGen 辅助展示 · 原始截图与测试记录见验收报告”

The test result line is supplied from completed independent test execution; the generated board must not imply it ran the tests. Include only the exact labels above and the preserved screenshot content. Prioritize a credible, readable design-review artifact.
```
