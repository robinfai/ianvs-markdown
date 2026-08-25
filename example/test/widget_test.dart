import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

import 'package:ianvs_markdown_example/main.dart';

void main() {
  testWidgets('playground demonstrates all three editor modes', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    expect(find.byType(IanvsMarkdownLiveEditor), findsOneWidget);
    expect(find.text('Render and edit together'), findsWidgets);
    expect(find.byTooltip('实时预览'), findsOneWidget);
    expect(find.byTooltip('源码模式'), findsOneWidget);
    expect(find.byTooltip('阅读模式'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-navigation-pane')),
      findsOneWidget,
    );
    expect(find.text('MODE'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-front-matter-toggle')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('example-mermaid-renderer')),
      360,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('ianvs-markdown-live-blocks')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('example-mermaid-renderer')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('源码模式'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('ianvs-markdown-source-field')),
      findsOneWidget,
    );
    expect(find.text('Source'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('ianvs-markdown-source-field')),
      '# Edited in the example',
    );
    await tester.pump();
    expect(find.text('Unsaved'), findsOneWidget);

    await tester.tap(find.byTooltip('实时预览'));
    await tester.pumpAndSettle();
    expect(find.text('Edited in the example'), findsWidgets);

    await tester.tap(find.byTooltip('保存'));
    await tester.pump();
    expect(find.text('Saved locally by the host app'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);

    await tester.tap(find.byTooltip('阅读模式'));
    await tester.pumpAndSettle();
    expect(find.text('Read'), findsOneWidget);
  });
}
