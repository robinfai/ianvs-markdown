# Ianvs Markdown macOS Playground

这是 `ianvs_markdown` 的可运行 macOS 示例应用，集中展示：

- 块级实时预览编辑
- 完整 Markdown 源码编辑
- 阅读模式与文档大纲
- 编辑工具栏、撤销/重做和保存回调
- Front matter、任务列表、表格和代码高亮
- 基于 `merman` + `flutter_svg` 的真实 Mermaid renderer 注入
- 默认阻止远端图片加载
- 亮色与暗色主题

在仓库根目录运行：

```sh
cd example
flutter pub get --offline
flutter run -d macos
```

Mermaid 渲染沿用 `ianvs-acp` 的原生管线：`merman` 通过 FFI 生成
`resvg-safe` SVG，内联 Mermaid 样式后交给 `flutter_svg` 显示。示例要求
macOS 11.0 或更高版本。macOS 构建阶段还会把 `merman` 发布产物中的绝对
dylib 路径规范化为应用内的 `@rpath/libmerman_ffi.dylib`，并重新签名。

构建应用：

```sh
flutter build macos
```

示例中的“保存”只演示宿主回调并更新 dirty 状态，不会写入文件。
