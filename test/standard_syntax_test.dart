import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart'
    show MarkdownBody;
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:markdown/markdown.dart' as md;

const standard = IanvsMarkdownSyntaxPreset.standard;

Widget app(Widget child) => MaterialApp(
  theme: ThemeData(platform: TargetPlatform.macOS),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 600, child: child),
    ),
  ),
);

String visibleText(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((widget) => widget.text.toPlainText())
    .join('\n');

void main() {
  final contract =
      jsonDecode(
            File(
              'test/fixtures/standard_syntax_contract.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  for (final fixture in contract['fixtures'] as List<dynamic>) {
    testWidgets('standard contract: ${fixture['id']}', (tester) async {
      await tester.pumpWidget(
        app(
          IanvsMarkdown(
            data: fixture['source'] as String,
            syntaxPreset: standard,
          ),
        ),
      );
      final text = visibleText(tester);
      for (final expected in fixture['contains'] as List<dynamic>) {
        expect(text, contains(expected as String));
      }
      for (final unexpected
          in fixture['doesNotContain'] as List<dynamic>? ?? []) {
        expect(text, isNot(contains(unexpected as String)));
      }
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(IanvsMarkdownCallout), findsNothing);
      if (fixture['id'] == 'html-keeps-upstream-gfm-behavior') {
        await tester.pumpWidget(
          app(
            MarkdownBody(
              data: fixture['source'] as String,
              extensionSet: md.ExtensionSet.gitHubFlavored,
            ),
          ),
        );
        expect(visibleText(tester), text);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('standard blocks every default image path before I/O', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const IanvsMarkdown(
          syntaxPreset: standard,
          data:
              '![remote](https://example.com/a.png)\n\n'
              '![local](file:///private/not-an-image.png)\n\n'
              '![data](data:image/png;base64,AA==)\n\n'
              '![reference][image]\n\n[image]: https://example.com/b.png\n\n'
              '<img src="https://example.com/html.png">\n\n![[wiki.png]]',
        ),
      ),
    );
    expect(find.byType(IanvsMarkdownBlockedImage), findsNWidgets(4));
    expect(find.byType(Image), findsNothing);
    // Unsupported raw HTML blocks follow MarkdownBody's GFM behavior. They
    // must not turn into a loading image or an interactive HTML control.
    expect(visibleText(tester), contains('![[wiki.png]]'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('standard forwards exact image alt and host link actions', (
    tester,
  ) async {
    final images = <(Uri, String?, String?)>[];
    final links = <String?>[];
    await tester.pumpWidget(
      app(
        IanvsMarkdown(
          syntaxPreset: standard,
          data:
              '![literal|250](asset.png "Title")\n\n[Open](file:///notes/one.md)',
          imageBuilder: (uri, title, alt) {
            images.add((uri, title, alt));
            return const Text('Approved image');
          },
          onTapLink: (_, href, _) => links.add(href),
        ),
      ),
    );
    expect(images, [(Uri.parse('asset.png'), 'Title', 'literal|250')]);
    await tester.tap(find.text('Open'));
    expect(links, ['file:///notes/one.md']);
  });

  testWidgets('standard pre and link builders override defaults', (
    tester,
  ) async {
    final pre = RecordingBuilder('host code', block: true);
    final link = RecordingBuilder('host link');
    var diagrams = 0;
    await tester.pumpWidget(
      app(
        IanvsMarkdown(
          syntaxPreset: standard,
          data: '[**Label**](note.md)\n\n```mermaid\ngraph TD; A-->B\n```',
          diagramBuilder: (_, _) {
            diagrams++;
            return const Text('Default diagram');
          },
          builders: {'pre': pre, 'a': link},
        ),
      ),
    );
    expect(pre.sources, ['graph TD; A-->B\n']);
    expect(link.sources, ['Label']);
    expect(find.text('host code'), findsOneWidget);
    expect(find.text('host link'), findsOneWidget);
    expect(diagrams, 0);
  });

  testWidgets('standard routes Mermaid through the default pre hook', (
    tester,
  ) async {
    final diagrams = <String>[];
    await tester.pumpWidget(
      app(
        IanvsMarkdown(
          syntaxPreset: standard,
          data: '```mermaid\ngraph TD; A-->B\n```',
          diagramBuilder: (_, source) {
            diagrams.add(source);
            return const Text('Approved diagram');
          },
        ),
      ),
    );
    expect(diagrams, ['graph TD; A-->B']);
    expect(find.text('Approved diagram'), findsOneWidget);
  });

  testWidgets('standard preserves GFM tasks and host heading styles', (
    tester,
  ) async {
    final checks = <bool>[];
    await tester.pumpWidget(
      app(
        IanvsMarkdown(
          syntaxPreset: standard,
          data: '# Host heading\n\n- [ ] Todo\n- [x] Done\n- [?] Literal',
          styleSheet: MarkdownStyleSheet(
            h1: const TextStyle(fontSize: 31, color: Colors.red),
          ),
          checkboxBuilder: (checked) {
            checks.add(checked);
            return const SizedBox(width: 16, height: 16);
          },
        ),
      ),
    );
    expect(checks, [false, true]);
    expect(visibleText(tester), contains('[?] Literal'));
    final heading = tester.widget<RichText>(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText() == 'Host heading',
      ),
    );
    final headingSpan = heading.text.getSpanForPosition(
      const TextPosition(offset: 0),
    );
    expect(headingSpan?.style?.fontSize, 31);
    expect(headingSpan?.style?.color, Colors.red);
  });

  testWidgets('standard honors custom inline syntax', (tester) async {
    await tester.pumpWidget(
      app(
        IanvsMarkdown(
          syntaxPreset: standard,
          data: 'Before :host: after',
          inlineSyntaxes: [HostSyntax()],
        ),
      ),
    );
    expect(visibleText(tester), contains('Before host extension after'));
  });

  testWidgets('preset and soft line breaks update without changing source', (
    tester,
  ) async {
    const source = 'Before %%visible%% after\nNext';
    await tester.pumpWidget(app(const IanvsMarkdown(data: source)));
    expect(visibleText(tester), isNot(contains('%%visible%%')));
    await tester.pumpWidget(
      app(
        const IanvsMarkdown(
          data: source,
          syntaxPreset: standard,
          softLineBreak: false,
        ),
      ),
    );
    expect(visibleText(tester), contains('Before %%visible%% after Next'));
    await tester.pumpWidget(
      app(
        const IanvsMarkdown(
          data: source,
          syntaxPreset: standard,
          softLineBreak: true,
        ),
      ),
    );
    expect(visibleText(tester), contains('Before %%visible%% after\nNext'));
    await tester.pumpWidget(app(const IanvsMarkdown(data: source)));
    expect(visibleText(tester), isNot(contains('%%visible%%')));
  });

  testWidgets(
    'standard updates an incomplete fence and copies current source',
    (tester) async {
      String? copied;
      for (final code in ['par', 'part\nnext']) {
        await tester.pumpWidget(
          app(
            IanvsMarkdown(
              syntaxPreset: standard,
              data: '```text\n$code',
              onCopyCode: (source) => copied = source,
            ),
          ),
        );
        expect(
          tester
              .widget<IanvsMarkdownCodeBlock>(
                find.byType(IanvsMarkdownCodeBlock),
              )
              .source,
          code,
        );
      }
      await tester.pumpWidget(
        app(
          IanvsMarkdown(
            syntaxPreset: standard,
            data: '```text\npart\nnext\n```',
            onCopyCode: (source) => copied = source,
          ),
        ),
      );
      expect(
        tester
            .widget<IanvsMarkdownCodeBlock>(find.byType(IanvsMarkdownCodeBlock))
            .source,
        'part\nnext',
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byType(IanvsMarkdownCodeBlock)));
      await tester.pump();
      await tester.tap(find.byTooltip('复制'));
      await tester.pump();
      expect(copied, 'part\nnext');
      await mouse.removePointer();
    },
  );

  testWidgets('standard budgets before parsing or invoking host builders', (
    tester,
  ) async {
    var images = 0;
    IanvsMarkdownRenderDecision? fallback;
    await tester.pumpWidget(
      app(
        IanvsMarkdown(
          syntaxPreset: standard,
          data: '**😀😀** ![image](https://example.com/a.png)',
          renderBudget: const IanvsMarkdownRenderBudget(
            maxSyntaxTokens: 0,
            maxFallbackBytes: 6,
          ),
          imageBuilder: (_, _, _) {
            images++;
            return const SizedBox();
          },
          fallbackBuilder: (_, decision) {
            fallback = decision;
            return Text('Omitted: ${decision.text}');
          },
        ),
      ),
    );
    expect(images, 0);
    expect(fallback?.text, '**😀');
    expect(fallback?.truncated, isTrue);
    expect(find.text('Omitted: **😀'), findsOneWidget);
    await tester.pumpWidget(
      app(
        const IanvsMarkdown(
          syntaxPreset: standard,
          data: r'$$$$',
          renderBudget: IanvsMarkdownRenderBudget(maxSyntaxTokens: 0),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('ianvs-markdown-plain-fallback')),
      findsNothing,
    );
    expect(visibleText(tester), contains(r'$$$$'));
  });

  testWidgets('standard whole-document copy retains literal metadata', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      const source = '# Title\n\nBody %%literal%% ^block-id and **bold**.';
      IanvsMarkdownClipboardData? copied;
      String? selected;
      await tester.pumpWidget(
        app(
          IanvsMarkdown(
            syntaxPreset: standard,
            data: source,
            clipboardWriter: (value) async => copied = value,
            onSelectionChanged: (text, _, _) => selected = text,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Body %%literal%%'));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(selected, contains('Body %%literal%%'));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(copied?.markdown, source);
      expect(copied?.html, contains('%%literal%% ^block-id'));
      expect(copied?.html, contains('<strong>bold</strong>'));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

class RecordingBuilder extends MarkdownElementBuilder {
  RecordingBuilder(this.label, {this.block = false});
  final String label;
  final bool block;
  final sources = <String>[];

  @override
  bool isBlockElement() => block;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    sources.add(element.textContent);
    return Text(label);
  }
}

class HostSyntax extends md.InlineSyntax {
  HostSyntax() : super(':host:');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Text('host extension'));
    return true;
  }
}
