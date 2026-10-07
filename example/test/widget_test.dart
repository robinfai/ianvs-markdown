import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_markdown_example/main.dart';

void main() {
  test('default document covers common Markdown elements', () {
    expect(exampleMarkdown, contains('**bold**'));
    expect(exampleMarkdown, contains('[[Project Notes]]'));
    expect(exampleMarkdown, contains('- [x] Completed task'));
    expect(exampleMarkdown, contains('| Capability | Example | Supported |'));
    expect(exampleMarkdown, contains('```dart'));
    expect(exampleMarkdown, contains('```mermaid'));
    expect(exampleMarkdown, contains('> [!note] Live Preview'));
    expect(exampleMarkdown, contains('[^source]'));
    expect(
      exampleMarkdown,
      contains(
        'https://robinfai.github.io/ianvs-terminal/assets/images/frame-diff/principle-advantages.png',
      ),
    );
    expect(exampleMarkdown.split('\n').length, greaterThan(120));
  });

  testWidgets('default integration leaves resources host-controlled', (
    tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();
    final editor = tester.widget<IanvsMarkdownLiveEditor>(
      find.byType(IanvsMarkdownLiveEditor),
    );
    expect(editor.imageBuilder, isNull);
    expect(editor.diagramBuilder, isNull);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('example stays focused on package integration', (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    expect(find.byType(IanvsMarkdownLiveEditor), findsOneWidget);
    expect(find.text('Render and edit together'), findsWidgets);
    expect(find.byTooltip('新建 Markdown 文件'), findsNothing);

    await tester.tap(find.byTooltip('源码模式'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('ianvs-markdown-source-field')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('ianvs-markdown-source-field')),
      '# Changed',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('保存'));
    await tester.pumpAndSettle();
    expect(find.text('Host save callback invoked'), findsOneWidget);

    await tester.tap(find.byTooltip('Use dark theme'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Use light theme'), findsOneWidget);
  });
}
