import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cases =
      (jsonDecode(await rootBundle.loadString('assets/cases.json')) as List)
          .cast<Map<String, dynamic>>();
  runApp(ComparisonApp(cases: cases));
}

class ComparisonApp extends StatelessWidget {
  const ComparisonApp({super.key, required this.cases});
  final List<Map<String, dynamic>> cases;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Mermaid Rendering Lab',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff256b62)),
      scaffoldBackgroundColor: const Color(0xfff3f5f4),
      fontFamily: 'Hiragino Sans GB',
      useMaterial3: true,
    ),
    home: ComparisonPage(cases: cases),
  );
}

class ComparisonPage extends StatefulWidget {
  const ComparisonPage({super.key, required this.cases});
  final List<Map<String, dynamic>> cases;
  @override
  State<ComparisonPage> createState() => _ComparisonPageState();
}

class _ComparisonPageState extends State<ComparisonPage> {
  int _index = 0;
  int _ratio = 2;
  double _zoom = 1;
  bool _baseline = false;
  bool _reading = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.cases[_index];
    final id = item['id'] as String;
    final rust = item['rust'] as Map<String, dynamic>;
    final raster = (rust['raster'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((sample) => sample['ratio'] == _ratio);
    final aspect = (rust['width'] as num) / (rust['height'] as num);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 22, 28, 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MERMAID / RENDERING LAB',
                          style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 2,
                            color: Color(0xff256b62),
                          ),
                        ),
                        SizedBox(height: 7),
                        Text(
                          '同一张图，两条原生渲染路线',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Text(
                    'Rust merman 0.7.0  ·  resvg 0.45.1\nFlutter SVG 2.3.0  ·  无 WebView',
                    textAlign: TextAlign.right,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
              child: Wrap(
                spacing: 20,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<int>(
                    value: _index,
                    items: [
                      for (var i = 0; i < widget.cases.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(widget.cases[i]['title'] as String),
                        ),
                    ],
                    onChanged: (value) => setState(() => _index = value!),
                  ),
                  SizedBox(
                    width: 230,
                    child: Row(
                      children: [
                        Text('${(_zoom * 100).round()}%'),
                        Expanded(
                          child: Slider(
                            value: _zoom,
                            min: 1,
                            max: 4,
                            divisions: 6,
                            onChanged: (value) => setState(() => _zoom = value),
                          ),
                        ),
                      ],
                    ),
                  ),
                  DropdownButton<int>(
                    value: _ratio,
                    items: [
                      for (final n in [1, 2, 4])
                        DropdownMenuItem(
                          value: n,
                          child: Text('位图 ${n}x · ${640 * n}px'),
                        ),
                    ],
                    onChanged: (value) => setState(() => _ratio = value!),
                  ),
                  FilterChip(
                    label: const Text('未经 usvg 处理的基线'),
                    selected: _baseline,
                    onSelected: (value) => setState(() => _baseline = value),
                  ),
                  FilterChip(
                    label: const Text('长文滚动测试'),
                    selected: _reading,
                    onSelected: (value) => setState(() => _reading = value),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey('document-scroll'),
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_reading)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 24),
                        child: Text(
                          '阅读测试：鼠标停在任一图表上，用触摸板上下滚动。两侧都由 Flutter 控件显示，滚动应当继续传给整篇文档。',
                          style: TextStyle(fontSize: 18, height: 1.8),
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _panel(
                            title: _baseline
                                ? '基线 · 直接 flutter_svg'
                                : 'A · Flutter 矢量',
                            subtitle: _baseline
                                ? 'resvg-safe + CSS 内联；未展开 marker'
                                : 'Rust usvg 展开箭头与字形 → flutter_svg',
                            child: DiagramSurface(
                              id: id,
                              vector: true,
                              baseline: _baseline,
                              aspect: aspect,
                              zoom: _zoom,
                              reading: _reading,
                              rasterRatio: _ratio,
                            ),
                            metrics:
                                'SVG ${_kb(_baseline ? rust['input_bytes'] : rust['vector_bytes'])}  ·  usvg 解析 ${_ms(rust['parse_median_ms'])}\n文字转为路径：缩放保持矢量；文字选择需另做语义层。',
                          ),
                        ),
                        const SizedBox(width: 22),
                        Expanded(
                          child: _panel(
                            title: 'B · Rust 位图',
                            subtitle: '同一份 SVG → resvg → Flutter Image',
                            child: DiagramSurface(
                              id: id,
                              vector: false,
                              aspect: aspect,
                              zoom: _zoom,
                              reading: _reading,
                              rasterRatio: _ratio,
                            ),
                            metrics:
                                '绘制 ${_ms(raster['render_median_ms'])}  ·  RGBA ${_mb(raster['rgba_bytes'])}  ·  PNG ${_kb(raster['png_bytes'])}\n位图档位固定；放大后切到更高分辨率查看重绘效果。',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      '检查：箭头是否完整、中文是否缺字、虚线与细线是否一致。放大后比较边缘，并在右侧切换 1x / 2x / 4x。',
                      style: TextStyle(fontSize: 15, height: 1.7),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '指标为本机离线阶段测量：Rust release，每步 10 次暖态中位数，不含文件 I/O。A 的解析与 B 的光栅化是不同阶段，不能直接当作端到端快慢。共同 merman 生成：${_ms(item['merman_median_ms'])}。',
                      style: const TextStyle(
                        color: Color(0xff5e6b66),
                        height: 1.7,
                      ),
                    ),
                    const SizedBox(height: 18),
                    ExpansionTile(
                      title: const Text('查看此图 Mermaid 源码'),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(
                            item['source'] as String,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_reading)
                      ...List.generate(
                        12,
                        (i) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 22),
                          child: Text(
                            '正文段落 ${i + 1}：图表是文档的一部分。鼠标从文字移入图形后，上下滚动应保持连贯。两条路线共用 Flutter 的布局与滚动容器。',
                            style: const TextStyle(fontSize: 18, height: 1.9),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel({
    required String title,
    required String subtitle,
    required Widget child,
    required String metrics,
  }) => Card(
    margin: EdgeInsets.zero,
    color: Colors.white,
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(subtitle, style: const TextStyle(color: Color(0xff5e6b66))),
            ],
          ),
        ),
        const Divider(height: 1),
        child,
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            metrics,
            style: const TextStyle(height: 1.8, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

class DiagramSurface extends StatelessWidget {
  const DiagramSurface({
    super.key,
    required this.id,
    required this.vector,
    required this.aspect,
    this.baseline = false,
    this.zoom = 1,
    this.rasterRatio = 2,
    this.reading = false,
  });
  final String id;
  final bool vector;
  final bool baseline;
  final double aspect;
  final double zoom;
  final int rasterRatio;
  final bool reading;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth - 24;
      final fittedWidth = reading
          ? width
          : (width < 440 * aspect ? width : 440 * aspect);
      final height = reading ? width / aspect : 464.0;
      return SizedBox(
        height: height,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.center,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: SizedBox(
              width: fittedWidth * zoom,
              height: fittedWidth / aspect * zoom,
              child: vector
                  ? SvgPicture.asset(
                      'assets/$id/${baseline ? 'input' : 'vector'}.svg',
                      fit: BoxFit.contain,
                    )
                  : Image.asset(
                      'assets/$id/raster-${rasterRatio}x.png',
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                    ),
            ),
          ),
        ),
      );
    },
  );
}

String _ms(dynamic n) => '${(n as num).toStringAsFixed(2)} ms';
String _kb(dynamic n) => '${((n as num) / 1024).toStringAsFixed(1)} KB';
String _mb(dynamic n) => '${((n as num) / 1048576).toStringAsFixed(1)} MB';
