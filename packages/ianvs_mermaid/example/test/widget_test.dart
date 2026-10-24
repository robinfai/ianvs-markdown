import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_mermaid_example/main.dart';

void main() {
  test('example enables HTTP network images by default', () {
    final image = buildExampleNetworkImage(
      Uri.parse('https://example.com/image.png'),
      null,
      'Example',
    );

    expect(image, isA<Image>());
    expect((image as Image).image, isA<NetworkImage>());
    expect((image.image as NetworkImage).url, 'https://example.com/image.png');
  });

  testWidgets('example stays focused on package integration', (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    expect(find.byType(IanvsMarkdownLiveEditor), findsOneWidget);
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
  });
}
