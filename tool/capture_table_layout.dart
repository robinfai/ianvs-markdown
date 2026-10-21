// Run from the repository root with:
// flutter test --no-pub tool/capture_table_layout.dart --reporter expanded
// This optional visual-evidence harness uses bundled CJK text and local fonts.
// PNGs and geometry are written under build/table-layout/.
// Requires Linux DejaVu Sans / Sans Mono under /usr/share/fonts/truetype/dejavu.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

const _out = 'build/table-layout';
const _font = 'TableCapture';
const _mono = 'TableCaptureMono';

const _description = '''
| ID | Description / 说明 | Amount |
| :--- | :--- | ---: |
| A1 | This longer description should receive useful room while the ID stays compact. | 18.50 |
| B2 | 混合中文与 English：根据内容分配列宽，避免短字段占据大量空白。 | 120.00 |
| C3 | Short note | 9.99 |
''';

const _manyColumns = '''
| ID | Schedule | Owner | Status | Amount | Region | Document | Notes |
| :--- | :--- | :--- | :--- | ---: | :--- | :--- | :--- |
| A1 | Wednesday morning delivery | Product design and engineering | Review in progress | 12345.67 | Asia Pacific / 亚太 | Technical specification | Final column remains reachable by horizontal scrolling |
| B2 | Next release | Robin | Ready | 18.50 | Europe | Release notes | End of table |
''';

const _urlCode = '''
| Type | Content |
| :--- | :--- |
| URL | <https://example.com/docs/a-very-long-path-without-spaces/0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ?release=2026-10-21> |
| Code | `VeryLongUnbrokenIdentifierThatMustWrapWithoutOverlappingTheNextCell0123456789` |
| File | [release-notes.pdf](release-notes.pdf) |
| End | The last row must remain below wrapped text. |
''';

const _rtlSource =
    '| מזהה | תיאור | סכום |\n| --- | --- | ---: |\n'
    '| א1 | תיאור ארוך עם טקסט בעברית וגם English mixed content | 18.50 |\n'
    '| ב2 | הטקסט צריך להישאר קריא גם בתצוגה צרה | 120.00 |';

class _Scenario {
  const _Scenario(
    this.name,
    this.title,
    this.source, {
    this.width = 520,
    this.height = 370,
    this.scale = 1,
    this.direction = TextDirection.ltr,
    this.captureScrollEnd = false,
    this.fileChips = false,
  });
  final String name;
  final String title;
  final String source;
  final double width;
  final double height;
  final double scale;
  final TextDirection direction;
  final bool captureScrollEnd;
  final bool fileChips;
}

const _scenarios = [
  _Scenario(
    '01-compact',
    'Compact values stay compact',
    '| ID | State |\n| --- | --- |\n| A1 | Done |\n| B2 | New |',
    width: 520,
    height: 210,
  ),
  _Scenario(
    '02-prose-wide',
    'Short IDs, mixed-language prose, aligned amounts',
    _description,
    width: 600,
    height: 320,
  ),
  _Scenario(
    '03-prose-narrow',
    'The same content at a narrow viewport',
    _description,
    width: 320,
    height: 500,
  ),
  _Scenario(
    '04-url-code',
    'Long URLs, monospace code and file labels',
    _urlCode,
    width: 360,
    height: 540,
    fileChips: true,
  ),
  _Scenario(
    '05-many-columns',
    'Eight columns retain readable widths',
    _manyColumns,
    width: 320,
    height: 450,
    captureScrollEnd: true,
  ),
  _Scenario(
    '06-large-text',
    'Narrow viewport with 2x accessibility text',
    _description,
    width: 320,
    height: 620,
    scale: 2,
    captureScrollEnd: true,
  ),
  _Scenario(
    '07-many-large-text',
    'Eight columns at 2x accessibility text',
    _manyColumns,
    width: 320,
    height: 660,
    scale: 2,
    captureScrollEnd: true,
  ),
  _Scenario(
    '08-rtl',
    'RTL content with Hebrew and English',
    _rtlSource,
    width: 320,
    height: 460,
    direction: TextDirection.rtl,
  ),
  _Scenario(
    '09-rtl-large-text',
    'RTL at 2x: scroll to the opposite end',
    _rtlSource,
    width: 320,
    height: 620,
    scale: 2,
    direction: TextDirection.rtl,
    captureScrollEnd: true,
  ),
];

Future<void> _loadFont(String name, String path) async {
  final bytes = await File(path).readAsBytes();
  final loader = FontLoader(name)
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

Future<void> _savePng(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await File('$_out/$name.png').writeAsBytes(bytes.buffer.asUint8List());
    image.dispose();
  });
}

List<ScrollableState> _horizontalStates(WidgetTester tester) => [
  for (final state in tester.stateList<ScrollableState>(
    find.byType(Scrollable),
  ))
    if (state.position.axis == Axis.horizontal) state,
];

Widget _panel(
  BuildContext context,
  _Scenario scenario,
  String label,
  Widget child,
) => SizedBox(
  width: scenario.width,
  height: scenario.height + 34,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xff25666b),
        ),
      ),
      const SizedBox(height: 10),
      Expanded(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xffc8d4d4)),
          ),
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scenario.scale)),
            child: Directionality(
              textDirection: scenario.direction,
              child: child,
            ),
          ),
        ),
      ),
    ],
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await Directory(_out).create(recursive: true);
    final configFile = File('.dart_tool/package_config.json').absolute;
    final config =
        jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
    final flutter = (config['packages'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((package) => package['name'] == 'flutter');
    final flutterPackageUri = configFile.uri.resolve('${flutter['rootUri']}/');
    await _loadFont(
      'MaterialIcons',
      File.fromUri(
        flutterPackageUri.resolve(
          '../../bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ),
      ).path,
    );
    await _loadFont(
      _font,
      'packages/ianvs_mermaid/rust/fonts/NotoSansCJKsc-Regular.otf',
    );
    await _loadFont(
      _mono,
      '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
    );
    await _loadFont(
      'TableCaptureRTL',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    );
  });

  for (final scenario in _scenarios) {
    testWidgets('capture ${scenario.name}', (tester) async {
      final boundary = GlobalKey();
      final controller = IanvsMarkdownController(text: scenario.source);
      final font = scenario.direction == TextDirection.rtl
          ? 'TableCaptureRTL'
          : _font;
      final markdownTheme = IanvsMarkdownThemeData.light.copyWith(
        monoFontFamily: _mono,
        monoFontFamilyFallback: const [_font],
      );
      await tester.binding.setSurfaceSize(
        Size(scenario.width * 2 + 72, scenario.height + 154),
      );
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
        controller.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: font, brightness: Brightness.light),
          home: Scaffold(
            body: RepaintBoundary(
              key: boundary,
              child: ColoredBox(
                color: const Color(0xffedf3f3),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Builder(
                    builder: (context) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          scenario.title,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                            color: Color(0xff20363a),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${scenario.width.toInt()} px per viewport · '
                          '${scenario.scale.toStringAsFixed(1)}x text · '
                          '${scenario.direction.name.toUpperCase()} · real Flutter widgets',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xff536d70),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _panel(
                              context,
                              scenario,
                              'READING',
                              SingleChildScrollView(
                                child: IanvsMarkdown(
                                  data: scenario.source,
                                  theme: markdownTheme,
                                  enableFileLinkChips: scenario.fileChips,
                                ),
                              ),
                            ),
                            const SizedBox(width: 24),
                            _panel(
                              context,
                              scenario,
                              'LIVE EDITOR',
                              IanvsMarkdownLiveEditor(
                                controller: controller,
                                showToolbar: false,
                                showNavigationPane: false,
                                contentMaxWidth: 1200,
                                padding: EdgeInsets.zero,
                                theme: markdownTheme,
                                enableFileLinkChips: scenario.fileChips,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(Table), findsNWidgets(2));
      final tables = tester
          .renderObjectList<RenderTable>(find.byType(Table))
          .toList();
      final geometry = <String, Object?>{
        'scenario': scenario.name,
        'viewport': scenario.width,
        'textScale': scenario.scale,
        'direction': scenario.direction.name,
        'tables': [
          for (var i = 0; i < tables.length; i++)
            {
              'mode': i == 0 ? 'reading' : 'live',
              'width': tables[i].size.width,
              'height': tables[i].size.height,
              'columns': [for (final cell in tables[i].row(0)) cell.size.width],
            },
        ],
        'editableDiagnostics': [
          for (final element in find.byType(EditableText).evaluate())
            (() {
              final widget = element.widget as EditableText;
              final render =
                  ((element as StatefulElement).state as EditableTextState)
                      .renderEditable;
              final text = render.text?.toPlainText() ?? '';
              final painter = TextPainter(
                text: render.text,
                textDirection: scenario.direction,
                textScaler: TextScaler.linear(scenario.scale),
              )..layout();
              final intrinsicWidth = painter.maxIntrinsicWidth;
              painter.dispose();
              return {
                'text': widget.controller.text,
                'width': render.size.width,
                'height': render.size.height,
                'intrinsicWidth': intrinsicWidth,
                'style': widget.style.toString(),
                'glyphBoxes': [
                  for (final box in render.getBoxesForSelection(
                    TextSelection(baseOffset: 0, extentOffset: text.length),
                  ))
                    [box.left, box.top, box.right, box.bottom],
                ],
              };
            })(),
        ],
        'horizontalExtents': [
          for (final state in _horizontalStates(tester))
            state.position.maxScrollExtent,
        ],
      };
      await _savePng(tester, boundary, scenario.name);
      if (scenario.captureScrollEnd) {
        for (final state in _horizontalStates(tester)) {
          state.position.jumpTo(state.position.maxScrollExtent);
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _savePng(tester, boundary, '${scenario.name}-scroll-end');
      }
      await tester.runAsync(
        () => File(
          '$_out/${scenario.name}.json',
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(geometry)),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
