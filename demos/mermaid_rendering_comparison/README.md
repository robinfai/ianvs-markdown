# Mermaid rendering comparison

独立实验，不修改 Linefold 的生产渲染链路。7 个样例：中文流程、时序、类图、状态图、64 节点压力图，以及两张实际文章图。

## 结论

优先试行 **merman → usvg 展开文字与 marker → flutter_svg**。本批样例中它补齐了直接 flutter_svg 丢失的箭头，中文、类图空心箭头与菱形均能显示；任意缩放无需切换位图分辨率。

保留 **merman → resvg → Flutter Image** 作为复杂 SVG 的候选兜底或缩略图方案。它的绘制工作可以移出 Flutter 绘图阶段，但生产集成必须管理尺寸、后台渲染、缓存上限与过期请求。此 demo 没有证明哪条路线的生产帧率更高。

## 三个可操作的对照

- A：usvg 0.45.1 将 marker、文字转成普通路径，再交给 flutter_svg 2.3.0 / vector_graphics。
- B：同一输入用 resvg 0.45.1 光栅化，Flutter Image 显示。提供宽度 640、1280、2560 像素三档。
- 基线：使用现有的 resvg-safe + CSS 内联结果，直接交给 flutter_svg，复现丢箭头。勾选“未经 usvg 处理的基线”即可看见。

独立应用支持 7 个样例切换、100%～400% 同步缩放、位图档位切换、长文滚动、查看 Mermaid 源码。两侧图像预先生成，用于隔离显示效果；位图档位手动选择，尚未实现生产级按缩放自动重绘。

## 测量（本机，2026-09-26）

时间单位 ms，SVG 大小 KB，RGBA 内存 MiB。Rust 为 release 编译，丢弃一次预热，10 次暖态中位数，字体数据库共用；不含文件 I/O。**解析与光栅化是不同阶段，不能直接用这两列宣布 A/B 谁更快。B 同样需要解析；A 另需 SVG 序列化、Flutter 解析和绘制。**

| 样例 | usvg 解析 | resvg 2x 光栅化 | 展开后 SVG | 2x RGBA | 4x RGBA |
|---|---:|---:|---:|---:|---:|
| 中文流程 · 箭头与换行 | 5.40 | 0.98 | 58.8 | 1.48 | 5.94 |
| 时序图 · 虚线与激活条 | 12.78 | 3.39 | 107.0 | 4.35 | 17.38 |
| 类图 · 空心箭头与菱形 | 9.10 | 2.77 | 49.4 | 6.84 | 27.34 |
| 状态图 · 起止节点 | 9.34 | 4.90 | 185.0 | 10.68 | 42.73 |
| 压力样例 · 64 个节点 | 93.17 | 5.36 | 404.2 | 3.96 | 15.82 |
| 实际文章 · 01-01 | 27.68 | 5.84 | 230.7 | 8.96 | 35.86 |
| 实际文章 · 04-01 | 19.45 | 2.99 | 124.3 | 5.81 | 23.24 |

RGBA 为一张图单个像素缓冲的理论大小，不包含图像解码副本、GPU 纹理、并存缓存和应用其他内存。SVG 文件大小也不等于矢量方案的总运行内存。四倍宽高相对 1x 增加 16 倍像素内存。

位图的目标像素宽度应按“实际显示宽度 × 设备像素比 × 缩放倍率”计算。Retina 屏幕上 400% 放大可能需要接近 8x 图片；本 demo 仅提供到 4x，用于展示分辨率与内存的取舍，不能据此认为位图无法达到相同清晰度。

Flutter 的调试模式解析耗时与导出耗时保存于 `results/flutter-metrics.json`，不可与 Rust release 耗时直接比较，也不可当作桌面应用的帧率指标。

## 画面与测试证据

- `results/*-input-*.png`：真实 Flutter 引擎绘制未经 usvg 处理的 SVG。
- `results/*-vector-*.png`：真实 Flutter 引擎绘制经过 usvg 处理的 SVG。
- `assets/*/raster-*.png`：真实 Rust resvg 输出，不是浏览器模拟。
- 7 张图都完成了 1x / 2x / 4x Flutter 导出。A/B 的 2x 整幅图 RGB 平均绝对差值为 0.079～0.473（每通道 0～255）；超过平均 20 灰阶差值的像素占比约 0.058%～0.408%。这是辅助指标，白底会稀释差异，不能替代检查细线和箭头。
- 4 个 Flutter 测试通过：完整渲染导出、A 的滚轮与触摸板、B 的滚轮与触摸板、demo 控件交互。
- macOS Release 应用已实际打开：核对了两侧并排画面、400% 矢量与 1x 位图的边缘差异，以及光标位于两侧图表时正文可继续滚动。
- 这不是所有 Mermaid/SVG 特性的完整验收：两条路线共享 merman 输出和 usvg 解释，不能用两者相似来证明与 Mermaid.js 完全一致。滤镜、mask、渐变、emoji、其他字体和图类型需要补充覆盖。

## 取舍

| 项目 | A：Flutter 矢量 | B：resvg 位图 |
|---|---|---|
| 放大 | 保留路径，清晰度不依赖图片档位 | 超出当前像素密度会模糊，需要重新光栅化 |
| 文档滚动 | 普通 Flutter 绘图，无原生网页命中问题 | 普通 Flutter Image，无原生网页命中问题 |
| 内容更新 | usvg 处理 + Flutter 编译；应缓存，后台预处理 | usvg 处理 + 光栅化 + 像素传输；应后台生成 |
| 存储与内存 | 字形转路径后 SVG 可能变大，另有 Picture/GPU 开销 | 压缩 PNG 可小，但解码内存随像素面积增长 |
| SVG 特性 | 预处理不能弥补 Flutter 后端全部滤镜等限制 | 静态 SVG 支持更广；仍不是 HTML 浏览器 |
| 文本选择/无障碍 | 文字转路径后需要另外提供语义/文本层 | 位图同样需要语义/文本层 |

## 运行

在本目录执行：

```sh
flutter pub get
flutter run -d macos --release
```

已构建应用：`build/macos/Build/Products/Release/Mermaid Rendering Lab.app`。
`results/index.html` 可直接打开，用于查看固定倍率的实际渲染图片；真实矢量动态缩放请使用原生 demo。

## 重建素材与证据

```sh
# 使用项目 app 已解析的包配置，复用当前 merman 和 SVG 参数。
dart --packages=../../app/.dart_tool/package_config.json tool/generate.dart /path/to/llm-principles-series
CARGO_HOME="$PWD/.cargo-cache" cargo build --release --manifest-path rust/Cargo.toml
rust/target/release/mermaid-rendering-comparison assets
flutter test test/comparison_test.dart
python3 tool/build_report.py
```

素材生成只读取语料原文件。字体由 macOS 系统提供（Hiragino Sans GB、Helvetica、Arial），不分发字体；移植时需要显式替换字体加载策略。示例样式沿用现有 normalizer，未单独修复其 CSS 处理。

参考：[flutter_svg](https://pub.dev/packages/flutter_svg)、[usvg](https://github.com/linebender/resvg/tree/main/crates/usvg)、[resvg](https://github.com/linebender/resvg)。
