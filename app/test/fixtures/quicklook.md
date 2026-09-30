# Linefold 系统预览

无需启动编辑器，即可在 Finder 中按 **空格** 阅读 Markdown。

## 文档内容

| 能力 | 状态 | 说明 |
| :--- | :---: | ---: |
| 中文与英文 | 支持 | UTF-8 / UTF-16 |
| 表格与代码 | 支持 | 离线渲染 |
| Mermaid 图表 | 支持 | 原生引擎 |

- [x] 标题、**粗体**、*斜体*和 ~~删除线~~
- [x] 表格、引用与代码块
- [ ] 在 Linefold 中继续编辑

> 快速预览读取磁盘上的文件，不会修改文档。

```mermaid
flowchart LR
  A[选择 Markdown] --> B[按下空格]
  B --> C[阅读系统预览]
```

## 代码与链接

```dart
final message = '你好，Quick Look';
print(message);
```

[Apple Quick Look](https://developer.apple.com/documentation/quicklookui/)

## 错误恢复

下面的错误图表保留源码，后续正文仍然可读。

```mermaid
this is not a valid diagram
```

**文档结尾：预览完整。**
