import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 1000, height: 720, child: child)),
);

void _expectTarget(
  IanvsMarkdownLinkTarget target, {
  required String text,
  required String href,
  required IanvsMarkdownLinkKind kind,
  String title = '',
}) {
  expect(target.text, text);
  expect(target.href, href);
  expect(target.kind, kind);
  expect(target.title, title);
}

void main() {
  testWidgets('reading preserves typed Wiki alias and raw fragment', (
    tester,
  ) async {
    final taps = <IanvsMarkdownLinkTarget>[];
    var legacyCalls = 0;
    await tester.pumpWidget(
      _app(
        IanvsMarkdown(
          data: '[[folder/Note#^block|Alias]] [[#Heading]] [[Note.pdf]]',
          onTapLinkTarget: taps.add,
          onTapLink: (_, _, _) => legacyCalls++,
        ),
      ),
    );
    await tester.tap(find.text('Alias'));
    await tester.tap(find.text('Heading'));
    await tester.tap(find.text('Note.pdf'));
    expect(taps, hasLength(3));
    _expectTarget(
      taps[0],
      text: 'Alias',
      href: 'folder/Note#^block',
      kind: IanvsMarkdownLinkKind.wiki,
    );
    _expectTarget(
      taps[1],
      text: 'Heading',
      href: '#Heading',
      kind: IanvsMarkdownLinkKind.wiki,
    );
    _expectTarget(
      taps[2],
      text: 'Note.pdf',
      href: 'Note.pdf',
      kind: IanvsMarkdownLinkKind.wiki,
    );
    expect(legacyCalls, 0);
  });

  testWidgets('same href and label retain distinct parsed link kinds', (
    tester,
  ) async {
    final taps = <IanvsMarkdownLinkTarget>[];
    await tester.pumpWidget(
      _app(
        IanvsMarkdown(
          data: '[[Note.md#Heading|Same]] [Same](Note.md#Heading "Title")',
          enableFileLinkChips: true,
          onTapLinkTarget: taps.add,
        ),
      ),
    );
    await tester.tap(find.text('Same').first);
    await tester.tap(find.text('Same').last);
    expect(taps, hasLength(2));
    _expectTarget(
      taps[0],
      text: 'Same',
      href: 'Note.md#Heading',
      kind: IanvsMarkdownLinkKind.wiki,
    );
    _expectTarget(
      taps[1],
      text: 'Same',
      href: 'Note.md#Heading',
      title: 'Title',
      kind: IanvsMarkdownLinkKind.markdown,
    );
  });

  testWidgets('reading distinguishes tags and Markdown anchors', (
    tester,
  ) async {
    final taps = <IanvsMarkdownLinkTarget>[];
    await tester.pumpWidget(
      _app(
        IanvsMarkdown(
          data: '#topic [Anchor](#topic) <a href="#topic">HTML</a>',
          onTapLinkTarget: taps.add,
        ),
      ),
    );
    await tester.tap(find.text('#topic'));
    await tester.tap(find.text('Anchor'));
    await tester.tap(find.text('HTML'));
    expect(taps, hasLength(3));
    _expectTarget(
      taps[0],
      text: '#topic',
      href: 'tag:#topic',
      kind: IanvsMarkdownLinkKind.tag,
    );
    for (var i = 1; i < taps.length; i++) {
      expect(taps[i].href, '#topic');
      expect(taps[i].kind, IanvsMarkdownLinkKind.markdown);
    }
  });

  testWidgets('legacy callback remains a single compatible fallback', (
    tester,
  ) async {
    final taps = <(String, String?, String)>[];
    await tester.pumpWidget(
      _app(
        IanvsMarkdown(
          data: '[[Note#Section|Wiki]] [Markdown](#Section "Title") #tag',
          onTapLink: (text, href, title) => taps.add((text, href, title)),
        ),
      ),
    );
    await tester.tap(find.text('Wiki'));
    await tester.tap(find.text('Markdown'));
    await tester.tap(find.text('#tag'));
    expect(taps, [
      ('Wiki', 'Note#Section', ''),
      ('Markdown', '#Section', 'Title'),
      ('#tag', 'tag:#tag', ''),
    ]);
  });

  testWidgets('standard renderer delivers Markdown targets without chips', (
    tester,
  ) async {
    final taps = <IanvsMarkdownLinkTarget>[];
    await tester.pumpWidget(
      _app(
        IanvsMarkdown(
          data: '[Anchor](#local "Title")',
          selectable: false,
          syntaxPreset: IanvsMarkdownSyntaxPreset.standard,
          onTapLinkTarget: taps.add,
        ),
      ),
    );
    await tester.tap(find.text('Anchor', findRichText: true));
    expect(taps, hasLength(1));
    _expectTarget(
      taps.single,
      text: 'Anchor',
      href: '#local',
      title: 'Title',
      kind: IanvsMarkdownLinkKind.markdown,
    );
  });

  testWidgets(
    'host-added Wiki syntax retains origin through fallback renderer',
    (tester) async {
      final taps = <IanvsMarkdownLinkTarget>[];
      await tester.pumpWidget(
        _app(
          IanvsMarkdown(
            data: '[[Note#Heading|Alias]]',
            selectable: false,
            syntaxPreset: IanvsMarkdownSyntaxPreset.standard,
            inlineSyntaxes: [IanvsMarkdownWikiLinkSyntax()],
            onTapLinkTarget: taps.add,
          ),
        ),
      );
      await tester.tap(find.text('Alias', findRichText: true));
      expect(taps, hasLength(1));
      _expectTarget(
        taps.single,
        text: 'Alias',
        href: 'Note#Heading',
        kind: IanvsMarkdownLinkKind.wiki,
      );
    },
  );

  testWidgets('nested callout and HTML surfaces forward typed callbacks', (
    tester,
  ) async {
    final taps = <IanvsMarkdownLinkTarget>[];
    await tester.pumpWidget(
      _app(
        IanvsMarkdown(
          data:
              '> [!note] [[Title#Top|Title alias]]\n> [[Body#Part|Body alias]]\n\n'
              '<details open><summary>Details</summary>\n\n'
              '[[Nested#Part|Nested alias]]\n\n</details>',
          onTapLinkTarget: taps.add,
        ),
      ),
    );
    for (final label in ['Title alias', 'Body alias', 'Nested alias']) {
      await tester.tap(find.text(label));
    }
    expect(taps.map((target) => target.href), [
      'Title#Top',
      'Body#Part',
      'Nested#Part',
    ]);
    expect(
      taps.every((target) => target.kind == IanvsMarkdownLinkKind.wiki),
      isTrue,
    );
  });

  for (final live in [false, true]) {
    testWidgets(
      'frontmatter and embed retain Wiki origin in ${live ? 'Live' : 'View'}',
      (tester) async {
        const source =
            '---\nwiki: "[[Meta#Heading|Property alias]]"\n'
            'url: https://example.com\n'
            'links: ["[[List#^id|List alias]]"]\n---\n\n'
            '![[Embed#^block|Embed alias]]';
        final controller = IanvsMarkdownController(text: source);
        addTearDown(controller.dispose);
        final taps = <IanvsMarkdownLinkTarget>[];
        var legacyCalls = 0;
        await tester.pumpWidget(
          _app(
            live
                ? IanvsMarkdownLiveEditor(
                    controller: controller,
                    showFrontMatter: true,
                    onTapLinkTarget: taps.add,
                    onTapLink: (_, _, _) => legacyCalls++,
                  )
                : IanvsMarkdownView(
                    data: source,
                    showFrontMatter: true,
                    onTapLinkTarget: taps.add,
                    onTapLink: (_, _, _) => legacyCalls++,
                  ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Property alias'));
        await tester.tap(find.text('List alias'));
        await tester.tap(find.text('https://example.com'));
        await tester.tap(
          find.byKey(const ValueKey('ianvs-markdown-wiki-embed-open')),
        );
        await tester.pump();
        expect(taps.map((target) => target.href), [
          'Meta#Heading',
          'List#^id',
          'https://example.com',
          'Embed#^block',
        ]);
        expect(taps.map((target) => target.kind), [
          IanvsMarkdownLinkKind.wiki,
          IanvsMarkdownLinkKind.wiki,
          IanvsMarkdownLinkKind.markdown,
          IanvsMarkdownLinkKind.wiki,
        ]);
        expect(taps.last.text, 'Embed alias');
        expect(legacyCalls, 0);
        expect(controller.text, source);
        expect(controller.isDirty, isFalse);
      },
    );
  }

  testWidgets(
    'Live uses parsed kind and preserves source across Reading switch',
    (tester) async {
      const source = '[[Note#Part|Same]] [Same](Note#Part) [Anchor](#Part)';
      final controller = IanvsMarkdownController(text: source);
      addTearDown(controller.dispose);
      final taps = <IanvsMarkdownLinkTarget>[];
      var legacyCalls = 0;
      await tester.pumpWidget(
        _app(
          IanvsMarkdownLiveEditor(
            controller: controller,
            onTapLinkTarget: taps.add,
            onTapLink: (_, _, _) => legacyCalls++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Same').first);
      await tester.pump();
      expect(taps, hasLength(1));
      _expectTarget(
        taps.single,
        text: 'Same',
        href: 'Note#Part',
        kind: IanvsMarkdownLinkKind.wiki,
      );
      await tester.tap(find.text('Same').last);
      await tester.tap(find.text('Anchor'));
      await tester.pump();
      expect(taps, hasLength(1));
      expect(
        find.byKey(const ValueKey('ianvs-markdown-active-block')),
        findsNothing,
      );
      expect(controller.text, source);
      expect(controller.isDirty, isFalse);
      controller.mode = IanvsMarkdownEditorMode.preview;
      await tester.pumpAndSettle();
      await tester.tap(find.text('Same').last);
      await tester.tap(find.text('Anchor'));
      expect(taps.map((target) => target.kind), [
        IanvsMarkdownLinkKind.wiki,
        IanvsMarkdownLinkKind.markdown,
        IanvsMarkdownLinkKind.markdown,
      ]);
      expect(taps.last.href, '#Part');
      expect(legacyCalls, 0);
      expect(controller.text, source);
    },
  );

  testWidgets('Live formatted Wiki aliases navigate without source matching', (
    tester,
  ) async {
    const source =
        'Before [[folder/Note%20one#Some heading|**Alias**]] after.\r\n';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    final taps = <IanvsMarkdownLinkTarget>[];
    await tester.pumpWidget(
      _app(
        IanvsMarkdownLiveEditor(
          controller: controller,
          onTapLinkTarget: taps.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alias'));
    await tester.pump();
    expect(taps, hasLength(1));
    _expectTarget(
      taps.single,
      text: 'Alias',
      href: 'folder/Note%20one#Some heading',
      kind: IanvsMarkdownLinkKind.wiki,
    );
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-block')),
      findsNothing,
    );
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
  });

  testWidgets('footnote callbacks keep Markdown origin and typed precedence', (
    tester,
  ) async {
    final taps = <IanvsMarkdownLinkTarget>[];
    var legacyCalls = 0;
    await tester.pumpWidget(
      _app(
        IanvsMarkdown(
          data: 'Text[^note]\n\n[^note]: Footnote body',
          onTapLinkTarget: taps.add,
          onTapLink: (_, _, _) => legacyCalls++,
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('ianvs-markdown-footnote-reference')),
    );
    expect(taps, hasLength(1));
    expect(taps.single.kind, IanvsMarkdownLinkKind.markdown);
    expect(taps.single.href, '#fn-note');
    expect(legacyCalls, 0);
  });

  testWidgets('replacing callbacks updates unchanged rendered links', (
    tester,
  ) async {
    final first = <IanvsMarkdownLinkTarget>[];
    final second = <IanvsMarkdownLinkTarget>[];
    final legacy = <String?>[];
    final sheet = MarkdownStyleSheet(p: const TextStyle(fontSize: 16));
    Widget body(IanvsMarkdownTapLinkTargetCallback? typed) => _app(
      IanvsMarkdown(
        data: '[[Note#Heading|Alias]]',
        styleSheet: sheet,
        onTapLinkTarget: typed,
        onTapLink: (_, href, _) => legacy.add(href),
      ),
    );
    await tester.pumpWidget(body(first.add));
    await tester.tap(find.text('Alias'));
    await tester.pumpWidget(body(second.add));
    await tester.tap(find.text('Alias'));
    await tester.pumpWidget(body(null));
    await tester.tap(find.text('Alias'));
    expect(first, hasLength(1));
    expect(second, hasLength(1));
    expect(legacy, ['Note#Heading']);
  });

  testWidgets('Live tag clicks retain editing with typed callbacks installed', (
    tester,
  ) async {
    const source = 'Before #topic after';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    final taps = <IanvsMarkdownLinkTarget>[];
    await tester.pumpWidget(
      _app(
        IanvsMarkdownLiveEditor(
          controller: controller,
          onTapLinkTarget: taps.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('#topic'));
    await tester.pumpAndSettle();
    expect(taps, isEmpty);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-active-block')),
      findsOneWidget,
    );
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
  });
}
