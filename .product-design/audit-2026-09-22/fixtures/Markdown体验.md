---
title: Linefold 体验样本
tags: [writing, audit]
---

# Linefold Markdown 体验

普通段落：点击这行前后，文字基线、行高和下方内容的位置应保持不变。English text 123 和中文一起排版。

这一段包含 **粗体**、*斜体*、~~删除线~~、==高亮==、`inline code` 和 [示例链接](https://example.com)。

## 列表与引用

- 普通列表第一项
- 普通列表第二项：**重点** 与 `code`
  - 嵌套子项

1. 有序列表第一项
2. 有序列表第二项

- [ ] 待办事项：点击复选框
- [x] 已完成事项

> 引用第一行，点击后保持字体和行距一致。
> 引用第二行，后面的区块不应跳动。

## 代码与表格

```dart
final greeting = 'Hello, 折行';
print(greeting);
```

    indented code line one
    indented code line two

| 功能 | 状态 | 数量 |
| :--- | :---: | ---: |
| 编辑 | 可用 | 12 |
| 阅读 | 检查 | 8 |

## 扩展 Markdown

> [!note] 提示
> 点击内容进入编辑，箭头负责折叠。

> [!tip]- 可折叠提示
> 折叠后再次展开，内容应完整保留。

行内数学 $E = mc^2$，块级公式：

$$
\int_0^1 x^2 dx = \frac{1}{3}
$$

标准脚注[^note]、Wiki [[Second#目标标题|第二篇笔记]] 和 #writing/audit。

![本地样例图片](sample.png)

```mermaid
flowchart LR
  A[Write] --> B[Read]
```

[^note]: 这是脚注说明，可检查阅读模式的编号和回链。

Setext 标题
------------

结尾段落：用于检查大纲跳转、搜索、连续选区与保存。
