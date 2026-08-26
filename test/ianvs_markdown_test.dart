import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_markdown/src/code_surface.dart';
import 'package:ianvs_markdown/src/list_guide.dart';

void main() {
  Widget app(Widget child, {ThemeData? theme}) {
    return MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 900, height: 700, child: child),
        ),
      ),
    );
  }

  test('code theme colors are customizable and interpolate', () {
    const customPrimary = Color(0xff123456);
    const customCode = Color(0xff345678);
    const customInline = Color(0xff654321);
    final fallback = IanvsMarkdownThemeData.light.copyWith(
      textPrimary: customPrimary,
      codeForeground: customCode,
      inlineCodeForeground: customInline,
    );

    expect(fallback.codeForeground, customCode);
    expect(fallback.inlineCodeForeground, customInline);
    expect(
      IanvsMarkdownThemeData.light
          .lerp(IanvsMarkdownThemeData.dark, .5)
          .codeForeground,
      Color.lerp(
        IanvsMarkdownThemeData.light.codeForeground,
        IanvsMarkdownThemeData.dark.codeForeground,
        .5,
      ),
    );
    expect(
      IanvsMarkdownThemeData.light
          .lerp(IanvsMarkdownThemeData.dark, .5)
          .inlineCodeForeground,
      Color.lerp(
        IanvsMarkdownThemeData.light.inlineCodeForeground,
        IanvsMarkdownThemeData.dark.inlineCodeForeground,
        .5,
      ),
    );
  });

  test('Border list guide colors are exact and interpolate', () {
    const customGuide = Color(0xff123456);
    const customActive = Color(0xff654321);
    final customized = IanvsMarkdownThemeData.light.copyWith(
      listGuideColor: customGuide,
      listGuideActiveColor: customActive,
    );

    expect(
      IanvsMarkdownThemeData.light.listGuideColor,
      const Color(0x1f000000),
    );
    expect(IanvsMarkdownThemeData.dark.listGuideColor, const Color(0x1fffffff));
    expect(customized.listGuideColor, customGuide);
    expect(customized.listGuideActiveColor, customActive);
    final midpoint = IanvsMarkdownThemeData.light.lerp(
      IanvsMarkdownThemeData.dark,
      .5,
    );
    expect(
      midpoint.listGuideColor,
      Color.lerp(
        IanvsMarkdownThemeData.light.listGuideColor,
        IanvsMarkdownThemeData.dark.listGuideColor,
        .5,
      ),
    );
  });

  testWidgets('nested lists paint one-pixel guides on 28px marker steps', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const IanvsMarkdown(
          data: '- Parent\n  - Nested\n    - Deep\n- Sibling',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final surface = tester.renderObject<IanvsMarkdownListGuideRenderBox>(
      find.byType(IanvsMarkdownListGuideSurface),
    );
    final segments = surface.debugGuideSegments();

    expect(surface.width, 1);
    expect(surface.color, IanvsMarkdownThemeData.light.listGuideColor);
    expect(segments, isNotEmpty);
    expect(segments.map((segment) => segment.level).toSet(), <int>{0, 1});
    final rootX = segments.firstWhere((segment) => segment.level == 0).start.dx;
    final nestedX = segments
        .firstWhere((segment) => segment.level == 1)
        .start
        .dx;
    expect((nestedX - rootX).abs(), closeTo(28, .01));
    for (var index = 1; index < segments.length; index += 1) {
      final previous = segments[index - 1];
      final current = segments[index];
      if (previous.level == current.level &&
          (previous.start.dx - current.start.dx).abs() < .01) {
        expect(current.start.dy, greaterThan(previous.end.dy));
      }
    }
  });

  testWidgets('flat lists do not paint an indentation guide', (tester) async {
    await tester.pumpWidget(
      app(const IanvsMarkdown(data: '1. First\n2. Second')),
    );
    await tester.pumpAndSettle();

    final surface = tester.renderObject<IanvsMarkdownListGuideRenderBox>(
      find.byType(IanvsMarkdownListGuideSurface),
    );
    expect(surface.debugGuideSegments(), isEmpty);
  });

  testWidgets('RTL list guides follow logical nesting direction', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const Directionality(
          textDirection: TextDirection.rtl,
          child: IanvsMarkdown(data: '- Parent\n  - Nested\n    - Deep'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final surface = tester.renderObject<IanvsMarkdownListGuideRenderBox>(
      find.byType(IanvsMarkdownListGuideSurface),
    );
    final segments = surface.debugGuideSegments();
    final rootX = segments.firstWhere((segment) => segment.level == 0).start.dx;
    final nestedX = segments
        .firstWhere((segment) => segment.level == 1)
        .start
        .dx;
    expect(rootX - nestedX, closeTo(28, .01));
  });

  test('Border code pattern paints two one-pixel dots per 4px tile', () async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const painter = IanvsMarkdownCodePatternPainter(color: Color(0x1f000000));
    painter.paint(canvas, const Size(4, 4));
    final image = await recorder.endRecording().toImage(4, 4);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = data!.buffer.asUint8List();

    List<int> pixel(int x, int y) {
      final offset = (y * 4 + x) * 4;
      return bytes.sublist(offset, offset + 4);
    }

    expect(pixel(1, 3), <int>[0, 0, 0, 31]);
    expect(pixel(3, 1), <int>[0, 0, 0, 31]);
    expect(pixel(0, 0), <int>[0, 0, 0, 0]);
    expect(pixel(2, 2), <int>[0, 0, 0, 0]);
  });

  test('Border quote surface insets its three-pixel accent rail', () async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const painter = IanvsMarkdownQuoteSurfacePainter(
      backgroundColor: Color(0x00000000),
      patternColor: Color(0x1f000000),
      railColor: Color(0xffff0000),
      radius: 4,
      inset: 8,
      railWidth: 3,
    );
    painter.paint(canvas, const Size(24, 24));
    final image = await recorder.endRecording().toImage(24, 24);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = data!.buffer.asUint8List();

    List<int> pixel(int x, int y) {
      final offset = (y * 24 + x) * 4;
      return bytes.sublist(offset, offset + 4);
    }

    expect(pixel(3, 1), <int>[0, 0, 0, 31]);
    expect(pixel(9, 11), <int>[255, 0, 0, 255]);
    expect(pixel(9, 12), <int>[255, 0, 0, 255]);
    expect(pixel(8, 7), isNot(<int>[255, 0, 0, 255]));
    expect(pixel(11, 8), isNot(<int>[255, 0, 0, 255]));

    final rtlRecorder = ui.PictureRecorder();
    const IanvsMarkdownQuoteSurfacePainter(
      backgroundColor: Color(0x00000000),
      patternColor: Color(0x1f000000),
      railColor: Color(0xffff0000),
      textDirection: TextDirection.rtl,
    ).paint(Canvas(rtlRecorder), const Size(24, 24));
    final rtlImage = await rtlRecorder.endRecording().toImage(24, 24);
    final rtlData = await rtlImage.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    final rtlBytes = rtlData!.buffer.asUint8List();

    List<int> rtlPixel(int x, int y) {
      final offset = (y * 24 + x) * 4;
      return rtlBytes.sublist(offset, offset + 4);
    }

    expect(rtlPixel(14, 11), <int>[255, 0, 0, 255]);
    expect(rtlPixel(9, 11), isNot(<int>[255, 0, 0, 255]));
  });

  test('strong and emphasis theme colors customize and interpolate', () {
    const customStrong = Color(0xff123456);
    const customEmphasis = Color(0xff654321);
    final customized = IanvsMarkdownThemeData.light.copyWith(
      strongForeground: customStrong,
      emphasisForeground: customEmphasis,
    );

    expect(customized.strongForeground, customStrong);
    expect(customized.emphasisForeground, customEmphasis);
    final midpoint = IanvsMarkdownThemeData.light.lerp(
      IanvsMarkdownThemeData.dark,
      .5,
    );
    expect(
      midpoint.strongForeground,
      Color.lerp(
        IanvsMarkdownThemeData.light.strongForeground,
        IanvsMarkdownThemeData.dark.strongForeground,
        .5,
      ),
    );
    expect(
      midpoint.emphasisForeground,
      Color.lerp(
        IanvsMarkdownThemeData.light.emphasisForeground,
        IanvsMarkdownThemeData.dark.emphasisForeground,
        .5,
      ),
    );
  });

  test('task checkbox theme colors customize and interpolate', () {
    const checked = Color(0xff123456);
    const border = Color(0xff234567);
    const outline = Color(0x40345678);
    const done = Color(0xff456789);
    const red = Color(0xff56789a);
    const yellow = Color(0xff6789ab);
    const cyan = Color(0xff789abc);
    const purple = Color(0xff89abcd);
    final customized = IanvsMarkdownThemeData.light.copyWith(
      taskCheckboxColor: checked,
      taskCheckboxBorderColor: border,
      taskCheckboxHoverOutlineColor: outline,
      taskDoneColor: done,
      taskStatusRed: red,
      taskStatusYellow: yellow,
      taskStatusCyan: cyan,
      taskStatusPurple: purple,
    );

    expect(customized.taskCheckboxColor, checked);
    expect(customized.taskCheckboxBorderColor, border);
    expect(customized.taskCheckboxHoverOutlineColor, outline);
    expect(customized.taskDoneColor, done);
    expect(customized.taskStatusRed, red);
    expect(customized.taskStatusYellow, yellow);
    expect(customized.taskStatusCyan, cyan);
    expect(customized.taskStatusPurple, purple);
    final midpoint = IanvsMarkdownThemeData.light.lerp(
      IanvsMarkdownThemeData.dark,
      .5,
    );
    expect(
      midpoint.taskCheckboxColor,
      Color.lerp(
        IanvsMarkdownThemeData.light.taskCheckboxColor,
        IanvsMarkdownThemeData.dark.taskCheckboxColor,
        .5,
      ),
    );
    expect(
      midpoint.taskDoneColor,
      Color.lerp(
        IanvsMarkdownThemeData.light.taskDoneColor,
        IanvsMarkdownThemeData.dark.taskDoneColor,
        .5,
      ),
    );
    expect(
      midpoint.taskStatusPurple,
      Color.lerp(
        IanvsMarkdownThemeData.light.taskStatusPurple,
        IanvsMarkdownThemeData.dark.taskStatusPurple,
        .5,
      ),
    );
  });

  testWidgets('renders GFM, file links, and interactive fenced code', (
    tester,
  ) async {
    String? copied;
    String? tappedHref;
    await tester.pumpWidget(
      app(
        SingleChildScrollView(
          child: IanvsMarkdown(
            data: '''
# Example

- [x] ready

[guide.md](docs/guide.md)

```dart
final answer = 42;
```
''',
            onTapLink: (text, href, title) => tappedHref = href,
            onCopyCode: (source) => copied = source,
            enableFileLinkChips: true,
          ),
        ),
      ),
    );

    expect(find.text('Example'), findsOneWidget);
    expect(find.text('ready'), findsOneWidget);
    final taskCheckbox = tester.widget<IanvsMarkdownTaskCheckbox>(
      find.byType(IanvsMarkdownTaskCheckbox),
    );
    expect(taskCheckbox.value, isTrue);
    expect(taskCheckbox.onChanged, isNull);
    expect(
      tester.getSize(
        find.byKey(const ValueKey('ianvs-markdown-task-checkbox-outline')),
      ),
      const Size.square(24),
    );
    final taskBox = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('ianvs-markdown-task-checkbox-box')),
    );
    final taskDecoration = taskBox.decoration! as BoxDecoration;
    expect(taskBox.constraints?.maxWidth, 16);
    expect(taskBox.constraints?.maxHeight, 16);
    expect(
      taskDecoration.color,
      IanvsMarkdownThemeData.light.taskCheckboxColor,
    );
    expect(
      (taskDecoration.border! as Border).top.color,
      IanvsMarkdownThemeData.light.taskCheckboxColor,
    );
    expect(taskDecoration.borderRadius, BorderRadius.circular(6));
    expect(
      find.byKey(const ValueKey('ianvs-markdown-task-checkbox-check')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Completed task'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-file-reference')),
      findsOneWidget,
    );
    expect(find.byType(IanvsMarkdownCodeBlock), findsOneWidget);
    expect(find.text('Dart'), findsNothing);

    await tester.tap(find.text('guide.md'));
    await tester.pump();
    expect(tappedHref, 'docs/guide.md');

    await tester.tap(find.byTooltip('复制'));
    await tester.pump();
    expect(copied, 'final answer = 42;');
    expect(find.byTooltip('已复制到剪贴板'), findsOneWidget);
    expect(find.byTooltip('关闭自动换行'), findsNothing);
    expect(find.byTooltip('自动换行'), findsNothing);
  });

  testWidgets('task checkbox uses the Border dark palette', (tester) async {
    await tester.pumpWidget(
      app(
        const IanvsMarkdownTaskCheckbox(value: true),
        theme: ThemeData.dark(),
      ),
    );

    final box = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('ianvs-markdown-task-checkbox-box')),
    );
    final decoration = box.decoration! as BoxDecoration;
    expect(decoration.color, const Color(0xff7cd37c));
    expect((decoration.border! as Border).top.color, const Color(0xff7cd37c));
    final check = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('ianvs-markdown-task-checkbox-check')),
    );
    expect(check.painter, isNotNull);
  });

  testWidgets(
    'renders every Border alternate task state and unknown fallback',
    (tester) async {
      const markers = <String>[
        ' ',
        'x',
        '/',
        '-',
        '>',
        '<',
        '?',
        '!',
        '*',
        'i',
        'I',
        'l',
        'b',
        'n',
        'p',
        'c',
        '"',
        '“',
        'S',
        'u',
        'd',
        'k',
        ']',
      ];
      final source = markers
          .map(
            (marker) =>
                '- [$marker] marker ${marker == ' ' ? 'space' : marker}',
          )
          .join('\n');

      await tester.pumpWidget(
        app(
          SingleChildScrollView(
            child: IanvsMarkdown(data: source, fitContent: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final checkboxes = tester
          .widgetList<IanvsMarkdownTaskCheckbox>(
            find.byType(IanvsMarkdownTaskCheckbox),
          )
          .toList();
      expect(checkboxes, hasLength(markers.length));
      expect(checkboxes.map((checkbox) => checkbox.marker), markers);
      expect(checkboxes.map((checkbox) => checkbox.value), <bool>[
        false,
        ...List<bool>.filled(markers.length - 1, true),
      ]);
      expect(
        find.byKey(
          const ValueKey('ianvs-markdown-task-checkbox-alternative-icon'),
        ),
        findsNWidgets(19),
      );
      expect(
        find.byKey(const ValueKey('ianvs-markdown-task-checkbox-check')),
        findsNWidgets(3),
      );
      expect(find.bySemanticsLabel('Important task'), findsOneWidget);
      expect(find.bySemanticsLabel('Scheduled task'), findsOneWidget);
      expect(find.bySemanticsLabel('Checked task k'), findsOneWidget);

      final boxes = tester
          .widgetList<AnimatedContainer>(
            find.byKey(const ValueKey('ianvs-markdown-task-checkbox-box')),
          )
          .toList();
      BoxDecoration decorationFor(String marker) {
        final index = markers.indexOf(marker);
        return boxes[index].decoration! as BoxDecoration;
      }

      expect(
        decorationFor('!').color,
        IanvsMarkdownThemeData.light.taskStatusOrange,
      );
      expect(
        decorationFor('?').color,
        IanvsMarkdownThemeData.light.taskStatusPink,
      );
      expect(decorationFor('*').color, Colors.transparent);
      expect(decorationFor('*').border, isNull);
      expect(decorationFor('*').borderRadius, BorderRadius.zero);
      expect(decorationFor('/').color, Colors.transparent);
      expect(
        (decorationFor('/').border! as Border).top,
        BorderSide(
          color: IanvsMarkdownThemeData.light.taskStatusYellow,
          width: 2,
        ),
      );
      expect(
        decorationFor('k').color,
        IanvsMarkdownThemeData.light.taskCheckboxColor,
      );
    },
  );

  testWidgets('alternate task colors follow the Border dark palette', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const IanvsMarkdownTaskCheckbox(value: true, marker: '?'),
        theme: ThemeData.dark(),
      ),
    );

    final box = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('ianvs-markdown-task-checkbox-box')),
    );
    expect((box.decoration! as BoxDecoration).color, const Color(0xfff2b6de));
    expect(find.bySemanticsLabel('Question task'), findsOneWidget);
  });

  testWidgets('alternate marker changes rebuild when projected GFM is equal', (
    tester,
  ) async {
    Future<void> pump(String marker) async {
      await tester.pumpWidget(app(IanvsMarkdown(data: '- [$marker] State')));
      await tester.pumpAndSettle();
    }

    await pump('!');
    expect(
      tester
          .widget<IanvsMarkdownTaskCheckbox>(
            find.byType(IanvsMarkdownTaskCheckbox),
          )
          .marker,
      '!',
    );

    await pump('?');
    expect(
      tester
          .widget<IanvsMarkdownTaskCheckbox>(
            find.byType(IanvsMarkdownTaskCheckbox),
          )
          .marker,
      '?',
    );
    expect(find.bySemanticsLabel('Question task'), findsOneWidget);
  });

  testWidgets('alternate tasks render through nested ordered and quote lists', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const SingleChildScrollView(
          child: IanvsMarkdown(
            data:
                '- [!] Root\n  - [b] Nested\n\n1. [/] Ordered\n\n> - [?] Quoted',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widgetList<IanvsMarkdownTaskCheckbox>(
            find.byType(IanvsMarkdownTaskCheckbox),
          )
          .map((checkbox) => checkbox.marker),
      <String>['!', 'b', '/', '?'],
    );
    expect(find.text('Root'), findsOneWidget);
    expect(find.text('Nested'), findsOneWidget);
    expect(find.text('Ordered'), findsOneWidget);
    expect(find.text('Quoted'), findsOneWidget);
  });

  testWidgets('renders full, collapsed, and shortcut reference links', (
    tester,
  ) async {
    String? tappedHref;
    await tester.pumpWidget(
      app(
        IanvsMarkdown(
          data:
              'Full [Reference label][guide-ref].\n\n'
              'Collapsed [Collapsed][] and [shortcut].\n\n'
              '[guide-ref]: docs/guide.md "Reference title"\n'
              '[Collapsed]: docs/collapsed.md\n'
              '[shortcut]: docs/shortcut.md',
          onTapLink: (text, href, title) => tappedHref = href,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reference label'), findsOneWidget);
    expect(find.text('Collapsed'), findsOneWidget);
    expect(find.text('shortcut'), findsOneWidget);
    expect(find.textContaining('[guide-ref]:'), findsNothing);

    await tester.tap(find.text('Reference label'));
    await tester.pump();
    expect(tappedHref, 'docs/guide.md');
  });

  testWidgets('reading tables retain extra cells and pad missing cells', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    await tester.pumpWidget(
      app(
        const IanvsMarkdown(
          data:
              '| A | B | C |\n'
              '| --- | :---: | ---: |\n'
              '| one |\n'
              '| x | y | z | extra |',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final table = tester.widget<Table>(find.byType(Table));
    expect(table.children, hasLength(3));
    expect(table.children.map((row) => row.children.length), everyElement(4));
    expect(tester.getSemantics(find.byType(Table)).role, SemanticsRole.table);
    expect(find.text('extra'), findsOneWidget);
    semanticsHandle.dispose();
  });

  testWidgets('reading mode accepts Obsidian minimum-width alignments', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const IanvsMarkdown(
          data: '| A | B | C |\n| :-: | --: | :-- |\n| 1 | 2 | 3 |',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Table), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('table projection ignores fenced source and missing delimiters', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const IanvsMarkdown(
          data:
              '```text\n'
              '| A | B |\n'
              '| --- | --- |\n'
              '| x | y | extra |\n'
              '```\n\n'
              '| Plain | text |\n'
              '| without | delimiter |',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Table), findsNothing);
    expect(find.byType(IanvsMarkdownCodeBlock), findsOneWidget);
    expect(find.textContaining('| Plain | text |'), findsOneWidget);
  });

  testWidgets('renders local links as Obsidian-style text by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const IanvsMarkdown(
          data: '[Local](docs/guide.md) and [[Target|Wiki]].',
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('ianvs-markdown-file-reference')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ianvs-markdown-ordinary-link')),
      findsOneWidget,
    );

    final local = tester.widget<Text>(find.text('Local'));
    final wiki = tester.widget<Text>(find.text('Wiki'));
    expect(local.style?.color, IanvsMarkdownThemeData.light.accentDark);
    expect(local.style?.decoration, TextDecoration.underline);
    expect(wiki.style?.color, IanvsMarkdownThemeData.light.accentDark);
    expect(wiki.style?.decoration, TextDecoration.underline);
  });

  testWidgets('ordinary link labels preserve nested styles and soft wrap', (
    tester,
  ) async {
    const markdown =
        '[*italic* **bold** `code` and a very long linked label]'
        '(https://example.com/a/very/long/path)';
    await tester.pumpWidget(
      app(
        const Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 220, child: IanvsMarkdown(data: markdown)),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(_renderedTextIsItalic(tester, 'italic'), isTrue);
    expect(_renderedTextIsBold(tester, 'bold'), isTrue);
    expect(_renderedTextHasBackground(tester, 'code'), isTrue);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('ianvs-markdown-ordinary-link')))
          .width,
      lessThanOrEqualTo(220),
    );
  });

  testWidgets('short ordinary links only occupy their intrinsic width', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const SizedBox(
          width: 600,
          child: IanvsMarkdown(data: '[Short](https://example.com).'),
        ),
      ),
    );

    expect(
      tester
          .getSize(find.byKey(const ValueKey('ianvs-markdown-ordinary-link')))
          .width,
      lessThan(100),
    );
  });

  testWidgets('links preserve empty labels, titles, and angle destinations', (
    tester,
  ) async {
    final taps = <(String, String?, String)>[];
    await tester.pumpWidget(
      app(
        IanvsMarkdown(
          data:
              '[]() [Label]() '
              '[Angle](<https://example.com/a b>) '
              '[Titled](https://example.com "Title help")',
          onTapLink: (text, href, title) => taps.add((text, href, title)),
        ),
      ),
    );

    final linkSemantics = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .where((widget) => widget.properties.link == true)
        .toList();
    expect(linkSemantics, hasLength(4));
    expect(
      linkSemantics.any((widget) => widget.properties.label?.isEmpty ?? true),
      isTrue,
    );
    expect(find.byTooltip('Title help'), findsOneWidget);

    await tester.tap(find.text('Angle'));
    await tester.pump();
    expect(taps.single.$1, 'Angle');
    expect(taps.single.$2, 'https://example.com/a%20b');

    await tester.tap(find.text('Titled'));
    await tester.pump();
    expect(taps.last, ('Titled', 'https://example.com', 'Title help'));
  });

  testWidgets('renders a safe Obsidian inline HTML subset', (tester) async {
    String? tappedHref;
    await tester.pumpWidget(
      app(
        IanvsMarkdown(
          data: '''
Before <strong>bold <em>italic</em></strong> after.

Underline <u>under</u>; strike <s>gone</s>; mark <mark>marked</mark>.

Code <code>inline code</code>; super x<sup>2</sup>; sub H<sub>2</sub>O.

Key <kbd>Ctrl K</kbd>; color <span style="color:red" onclick="bad()">red</span>.

Break first<br/>second; unknown <not-a-real-tag>body</not-a-real-tag>.

Link <a href="https://example.com" onclick="bad()">example</a>; unsafe <a href="javascript:alert(1)">plain</a>.

Comment before <!-- hidden --> after. Script before <script>window.bad = true</script> after.

Escaped \\<span>literal \\</span> after.
''',
          onTapLink: (text, href, title) => tappedHref = href,
        ),
      ),
    );

    expect(_renderedTextIsBold(tester, 'bold'), isTrue);
    expect(_renderedTextIsItalic(tester, 'italic'), isTrue);
    expect(
      _renderedTextHasDecoration(tester, 'under', TextDecoration.underline),
      isTrue,
    );
    expect(
      _renderedTextHasDecoration(tester, 'gone', TextDecoration.lineThrough),
      isTrue,
    );
    expect(_renderedTextHasBackground(tester, 'marked'), isTrue);
    expect(_renderedPlainTextContains(tester, 'first\nsecond'), isTrue);
    expect(_renderedPlainTextContains(tester, 'body'), isTrue);
    expect(_renderedPlainTextContains(tester, 'not-a-real-tag'), isFalse);
    expect(_renderedPlainTextContains(tester, 'hidden'), isFalse);
    expect(_renderedPlainTextContains(tester, 'window.bad'), isFalse);
    expect(_renderedPlainTextContains(tester, '<strong>'), isFalse);
    expect(
      _renderedPlainTextContains(tester, r'Escaped \literal \ after.'),
      isTrue,
    );
    expect(
      _renderedTextHasColor(tester, 'red', const Color(0xffff0000)),
      isTrue,
    );
    expect(_renderedTextHasBackground(tester, 'Ctrl K'), isTrue);

    await tester.tap(find.text('example'));
    await tester.pump();
    expect(tappedHref, 'https://example.com');
    expect(_renderedPlainTextContains(tester, 'plain'), isTrue);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-ordinary-link')),
      findsOneWidget,
    );
    expect(tappedHref, 'https://example.com');
  });

  testWidgets('renders Obsidian autolink boundaries and word-adjacent URLs', (
    tester,
  ) async {
    final taps = <(String, String?)>[];
    await tester.pumpWidget(
      app(
        IanvsMarkdown(
          data: r'''
Word prefixhttps://word.example/path tail.
Punctuation https://punct.example/a_(b).,;:!? tail.
Quote "https://quote.example/path" tail.
Bracket https://bracket.example/a] tail.
Chinese https://cn.example/路径。， tail.
Escaped \<https://escaped.example/path> tail.
Unclosed <https://open.example/path tail.
''',
          onTapLink: (text, href, title) => taps.add((text, href)),
        ),
      ),
    );

    expect(find.text('https://word.example/path'), findsOneWidget);
    expect(find.text('https://punct.example/a_(b)'), findsOneWidget);
    expect(find.text('https://quote.example/path"'), findsOneWidget);
    expect(find.text('https://bracket.example/a]'), findsOneWidget);
    expect(find.text('https://cn.example/路径。，'), findsOneWidget);
    expect(find.text('https://escaped.example/path'), findsOneWidget);
    expect(find.text('https://open.example/path'), findsOneWidget);

    await tester.tap(find.text('https://quote.example/path"'));
    await tester.pump();
    expect(taps.single, (
      'https://quote.example/path"',
      'https://quote.example/path%22',
    ));
  });

  testWidgets('preserves Obsidian-style soft breaks by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(const IanvsMarkdown(data: 'Soft alpha\nsoft beta')),
    );

    expect(_renderedPlainTextContains(tester, 'Soft alpha\nsoft beta'), isTrue);

    await tester.pumpWidget(
      app(
        const IanvsMarkdown(
          data: 'Soft alpha\nsoft beta',
          softLineBreak: false,
        ),
      ),
    );

    expect(_renderedPlainTextContains(tester, 'Soft alpha soft beta'), isTrue);
  });

  testWidgets('rendered paragraphs collapse internal spaces and tabs', (
    tester,
  ) async {
    const source = 'Alpha   beta\tgamma  \nnext line';
    await tester.pumpWidget(
      app(
        const IanvsMarkdown(
          data: source,
          obsidianMetadataMode: IanvsMarkdownObsidianMetadataMode.editing,
        ),
      ),
    );

    expect(
      _renderedPlainTextContains(tester, 'Alpha beta gamma\nnext line'),
      isTrue,
    );
    expect(_renderedPlainTextContains(tester, 'Alpha   beta'), isFalse);
    expect(_renderedPlainTextContains(tester, 'beta\tgamma'), isFalse);
  });

  testWidgets('editing view preserves entities and backslash hard breaks', (
    tester,
  ) async {
    const source =
        'Entities: &copy; &#169; &notanentity; &#xZZ; &copy without.\n\n'
        'Backslash hard break\\\nnext line.';
    await tester.pumpWidget(
      app(
        const IanvsMarkdown(
          data: source,
          obsidianMetadataMode: IanvsMarkdownObsidianMetadataMode.editing,
        ),
      ),
    );

    expect(
      _renderedPlainTextContains(
        tester,
        'Entities: &copy; &#169; &notanentity; &#xZZ; &copy without.',
      ),
      isTrue,
    );
    expect(
      _renderedPlainTextContains(tester, 'Backslash hard break\\\nnext line.'),
      isTrue,
    );
    expect(find.byKey(const ValueKey('ianvs-markdown-tag')), findsNothing);
  });

  testWidgets('reading view follows Obsidian HTML entity boundaries', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const IanvsMarkdown(
          data: 'Entities: &copy; &#169; &notanentity; &#xZZ; &copy without.',
        ),
      ),
    );

    expect(
      _renderedPlainTextContains(
        tester,
        'Entities: © © ¬anentity; &#xZZ; © without.',
      ),
      isTrue,
    );
    expect(find.byKey(const ValueKey('ianvs-markdown-tag')), findsNothing);
  });

  testWidgets('code spans normalize internal whitespace like Obsidian', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const IanvsMarkdown(
          data: 'Single: ` code ` / `  code  ` / `a   b` / `a\tb`.',
        ),
      ),
    );

    expect(
      _renderedPlainTextContains(tester, 'Single: code /  code  / a b / a b.'),
      isTrue,
    );
  });

  testWidgets(
    'live preview code spans trim one edge pair and preserve source whitespace',
    (tester) async {
      const source = '''
Internal:A`a   b`Z
Edges:A`  a  `Z
One:A` `Z
Two:A`  `Z
Literal:A``Z
''';
      await tester.pumpWidget(
        app(
          const IanvsMarkdown(
            data: source,
            obsidianMetadataMode: IanvsMarkdownObsidianMetadataMode.editing,
          ),
        ),
      );

      expect(_renderedPlainTextContains(tester, 'Internal:Aa   bZ'), isTrue);
      expect(_renderedPlainTextContains(tester, 'Edges:A a Z'), isTrue);
      expect(_renderedPlainTextContains(tester, 'One:A Z'), isTrue);
      expect(_renderedPlainTextContains(tester, 'Two:A  Z'), isTrue);
      expect(_renderedPlainTextContains(tester, 'Literal:A``Z'), isTrue);

      await tester.pumpWidget(
        app(const IanvsMarkdown(key: ValueKey('reading-spaces'), data: source)),
      );

      expect(_renderedPlainTextContains(tester, 'Internal:Aa bZ'), isTrue);
      expect(_renderedPlainTextContains(tester, 'Edges:A a Z'), isTrue);
      expect(_renderedPlainTextContains(tester, 'One:A Z'), isTrue);
      expect(_renderedPlainTextContains(tester, 'Two:A Z'), isTrue);
      expect(_renderedPlainTextContains(tester, 'Literal:A``Z'), isTrue);
    },
  );

  testWidgets('inline code uses compact mono styling inside outer formats', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const IanvsMarkdown(
          data:
              'Plain `code` and **`strong code`** and '
              '*`italic code`* and ~~`struck code`~~ and '
              '==marked `highlight code`==.',
        ),
      ),
    );

    for (final text in <String>[
      'code',
      'strong code',
      'italic code',
      'struck code',
      'highlight code',
    ]) {
      expect(
        _renderedTextUsesInlineCodeStyle(
          tester,
          text,
          IanvsMarkdownThemeData.light,
        ),
        isTrue,
      );
    }
    expect(_renderedTextIsBold(tester, 'strong code'), isTrue);
    expect(_renderedTextIsItalic(tester, 'italic code'), isTrue);
    expect(
      _renderedTextHasDecoration(
        tester,
        'struck code',
        TextDecoration.lineThrough,
      ),
      isTrue,
    );
    expect(
      _renderedTextHasBackground(
        tester,
        'highlight code',
        color: IanvsMarkdownThemeData.light.surfaceHover,
      ),
      isTrue,
    );
  });

  testWidgets('reading matches Obsidian intraword underscore emphasis', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const IanvsMarkdown(
          data:
              'Single foo_single_word and a_short_c. '
              'Double foo__double__word. Standalone _standalone_.',
        ),
      ),
    );

    expect(_renderedPlainTextContains(tester, 'foo_single_word'), isTrue);
    expect(_renderedPlainTextContains(tester, 'a_short_c'), isTrue);
    expect(_renderedPlainTextContains(tester, 'foodoubleword'), isTrue);
    expect(
      _renderedPlainTextContains(tester, 'Standalone standalone.'),
      isTrue,
    );
    expect(_renderedTextIsBold(tester, 'double'), isTrue);
    expect(_renderedTextIsItalic(tester, 'standalone'), isTrue);
    expect(
      _renderedTextHasColor(
        tester,
        'double',
        IanvsMarkdownThemeData.light.strongForeground,
      ),
      isTrue,
    );
    expect(
      _renderedTextHasColor(
        tester,
        'standalone',
        IanvsMarkdownThemeData.light.emphasisForeground,
      ),
      isTrue,
    );
    expect(_renderedTextIsItalic(tester, 'single'), isFalse);
    expect(_renderedTextIsItalic(tester, 'short'), isFalse);
  });

  testWidgets('reading keeps delimited formatting across soft line breaks', (
    tester,
  ) async {
    const source =
        'Italic *italic one\nitalic two* tail.\n\n'
        'Strong **strong one\nstrong two** tail.\n\n'
        'Strike ~~strike one\nstrike two~~ tail.\n\n'
        'Highlight ==mark one\nmark two== tail.';
    await tester.pumpWidget(app(const IanvsMarkdown(data: source)));

    expect(_renderedTextIsItalic(tester, 'italic one\nitalic two'), isTrue);
    expect(_renderedTextIsBold(tester, 'strong one\nstrong two'), isTrue);
    expect(
      _renderedTextHasDecoration(
        tester,
        'strike one\nstrike two',
        TextDecoration.lineThrough,
      ),
      isTrue,
    );
    expect(_renderedTextHasBackground(tester, 'mark one'), isTrue);
    expect(_renderedTextHasBackground(tester, 'mark two'), isTrue);
  });

  testWidgets(
    'editing code spans preserve source breaks while reading normalizes them',
    (tester) async {
      const source = 'Before ` alpha   beta\n gamma ` after.';
      await tester.pumpWidget(
        app(
          const IanvsMarkdown(
            key: ValueKey('editing-code-span'),
            data: source,
            obsidianMetadataMode: IanvsMarkdownObsidianMetadataMode.editing,
          ),
        ),
      );

      expect(
        _renderedPlainTextContains(tester, 'alpha   beta\n gamma'),
        isTrue,
      );
      expect(
        _renderedTextHasBackground(tester, 'alpha   beta\n gamma'),
        isTrue,
      );

      await tester.pumpWidget(
        app(
          const IanvsMarkdown(key: ValueKey('reading-code-span'), data: source),
        ),
      );

      expect(
        _renderedPlainTextContains(tester, 'Before alpha beta gamma after.'),
        isTrue,
      );
      expect(_renderedPlainTextContains(tester, 'beta\n gamma'), isFalse);
    },
  );

  testWidgets('does not load Markdown images unless a builder is injected', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const IanvsMarkdown(
          data: '![diagram](https://images.example.com/diagram.png)',
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('ianvs-markdown-image-blocked')),
      findsOneWidget,
    );
    expect(find.textContaining('images.example.com'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('editing code blocks keep persistent copyable Border flair', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    String? copied;
    await tester.pumpWidget(
      app(
        IanvsMarkdown(
          data: '''
```dart
final first = 1;
final second = 2;
return first + second;
```
''',
          obsidianMetadataMode: IanvsMarkdownObsidianMetadataMode.editing,
          onCopyCode: (source) => copied = source,
        ),
        theme: ThemeData(platform: TargetPlatform.macOS),
      ),
    );

    expect(
      find.byKey(const ValueKey('ianvs-markdown-code-language-badge')),
      findsOneWidget,
    );
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('ianvs-markdown-code-language-badge')),
          )
          .label,
      'Dart',
    );
    expect(
      find.byKey(const ValueKey('ianvs-markdown-code-canvas')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ianvs-markdown-code-line-numbers')),
      findsNothing,
    );
    expect(find.text('3 LINES'), findsNothing);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-code-action-strip')),
      findsNothing,
    );
    expect(find.byTooltip('关闭自动换行'), findsNothing);
    expect(find.byTooltip('复制'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-code-flair')),
      findsOneWidget,
    );

    final surface = tester.widget<Container>(
      find.byKey(const ValueKey('ianvs-markdown-code-block')),
    );
    expect(surface.constraints?.minHeight, 38);
    final decoration = surface.decoration! as BoxDecoration;
    expect(decoration.boxShadow, isNull);
    expect(decoration.border, isNull);
    expect(decoration.color, IanvsMarkdownThemeData.light.surface);
    final idleFrame =
        surface.foregroundDecoration! as IanvsMarkdownDashedBorderDecoration;
    expect(idleFrame.strokeWidth, 1);
    expect(idleFrame.dashLength, 3);
    expect(idleFrame.gapLength, 3);
    expect(
      decoration.borderRadius,
      BorderRadius.circular(IanvsMarkdownThemeData.light.smallRadius / 2),
    );

    final canvas = tester.widget<Container>(
      find.byKey(const ValueKey('ianvs-markdown-code-canvas')),
    );
    expect(canvas.decoration, isNull);
    expect(canvas.color, isNull);

    final pattern = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('ianvs-markdown-code-pattern')),
    );
    final patternPainter = pattern.painter! as IanvsMarkdownCodePatternPainter;
    expect(patternPainter.tileSize, 4);
    expect(patternPainter.dotSize, 1);
    expect(patternPainter.color, Colors.black.withValues(alpha: .12));

    final contentPadding = tester.widget<Padding>(
      find.byKey(const ValueKey('ianvs-markdown-code-content-padding')),
    );
    expect(
      contentPadding.padding,
      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );

    final toolbar = tester.widget<Row>(
      find.byKey(const ValueKey('ianvs-markdown-code-toolbar')),
    );
    expect(toolbar.mainAxisSize, MainAxisSize.min);

    final flair = tester.widget<TextButton>(
      find.byKey(const ValueKey('ianvs-markdown-code-flair')),
    );
    expect(
      flair.style?.padding?.resolve(<WidgetState>{}),
      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
    expect(
      flair.style?.overlayColor?.resolve(<WidgetState>{WidgetState.hovered}),
      IanvsMarkdownThemeData.light.codeForeground.withValues(alpha: .2),
    );
    await tester.tap(find.byKey(const ValueKey('ianvs-markdown-code-flair')));
    await tester.pump();
    expect(
      copied,
      'final first = 1;\nfinal second = 2;\nreturn first + second;',
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('ianvs-markdown-code-block'))),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('ianvs-markdown-code-language-badge')),
      findsOneWidget,
    );
    expect(find.text('Dart'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-code-action-strip')),
      findsNothing,
    );
    expect(find.byTooltip('关闭自动换行'), findsNothing);
    expect(find.byTooltip('自动换行'), findsNothing);
    expect(find.byTooltip('复制'), findsOneWidget);
    final hoveredSurface = tester.widget<Container>(
      find.byKey(const ValueKey('ianvs-markdown-code-block')),
    );
    final hoveredFrame =
        hoveredSurface.foregroundDecoration!
            as IanvsMarkdownDashedBorderDecoration;
    expect(hoveredFrame.color, idleFrame.color);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('ianvs-markdown-code-toolbar')))
          .width,
      greaterThan(30),
    );
    final codeText = tester.widget<SelectableText>(
      find.descendant(
        of: find.byType(IanvsMarkdownCodeBlock),
        matching: find.byType(SelectableText),
      ),
    );
    expect(codeText.style?.fontSize, 14);
    expect(codeText.style?.height, 1.5);
    expect(codeText.style?.color, IanvsMarkdownThemeData.light.codeForeground);
    expect(
      tester
          .getSize(
            find.descendant(
              of: find.byType(IanvsMarkdownCodeBlock),
              matching: find.byType(SelectableText),
            ),
          )
          .height,
      63,
    );

    await mouse.moveTo(const Offset(-10, -10));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('ianvs-markdown-code-action-strip')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ianvs-markdown-code-language-badge')),
      findsOneWidget,
    );
    expect(find.text('Dart'), findsOneWidget);
    semanticsHandle.dispose();
  });

  testWidgets(
    'editing code blocks keep unlabeled copy visible and unknown labels literal',
    (tester) async {
      await tester.pumpWidget(
        app(
          const IanvsMarkdown(
            data: '''
```
```

```frobnicate
widget := unknown_token(42)
```
''',
            obsidianMetadataMode: IanvsMarkdownObsidianMetadataMode.editing,
          ),
          theme: ThemeData(platform: TargetPlatform.macOS),
        ),
      );

      expect(find.byType(IanvsMarkdownCodeBlock), findsNWidgets(2));
      expect(find.byTooltip('复制'), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('ianvs-markdown-code-flair')),
        findsNWidgets(2),
      );
      expect(find.byIcon(Icons.content_copy_rounded), findsOneWidget);
      expect(
        find.byKey(const ValueKey('ianvs-markdown-code-language-badge')),
        findsOneWidget,
      );
      expect(find.text('frobnicate'), findsOneWidget);
      expect(find.text('Frobnicate'), findsNothing);
      expect(
        tester.getSize(find.byType(IanvsMarkdownCodeBlock).first).height,
        greaterThanOrEqualTo(36),
      );
    },
  );

  testWidgets('blank code canvases follow reading and editing line geometry', (
    tester,
  ) async {
    const data = '```text\n\n```\n\n```text\n\n\n```';

    await tester.pumpWidget(
      app(
        const IanvsMarkdown(data: data),
        theme: ThemeData(platform: TargetPlatform.macOS),
      ),
    );

    var canvases = find.byKey(const ValueKey('ianvs-markdown-code-canvas'));
    expect(canvases, findsNWidgets(2));
    expect(tester.getSize(canvases.at(0)).height, 34);
    expect(tester.getSize(canvases.at(1)).height, 65);

    await tester.pumpWidget(
      app(
        const IanvsMarkdown(
          data: data,
          obsidianMetadataMode: IanvsMarkdownObsidianMetadataMode.editing,
        ),
        theme: ThemeData(platform: TargetPlatform.macOS),
      ),
    );

    canvases = find.byKey(const ValueKey('ianvs-markdown-code-canvas'));
    expect(canvases, findsNWidgets(2));
    expect(tester.getSize(canvases.at(0)).height, 58);
    expect(tester.getSize(canvases.at(1)).height, 78);
  });

  testWidgets(
    'code language labels normalize known names but preserve unknown casing',
    (tester) async {
      await tester.pumpWidget(
        app(
          const IanvsMarkdown(
            data: '''
~~~SHELL
echo ready
~~~

```FoObAr
widget := unknown_token(42)
```
''',
            obsidianMetadataMode: IanvsMarkdownObsidianMetadataMode.editing,
          ),
          theme: ThemeData(platform: TargetPlatform.macOS),
        ),
      );

      expect(find.text('Shell'), findsOneWidget);
      expect(find.text('FoObAr'), findsOneWidget);
      expect(find.text('foobar'), findsNothing);
    },
  );

  testWidgets('reading code blocks hide language and reveal only copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const IanvsMarkdown(data: '```dart\nfinal value = 1;\n```'),
        theme: ThemeData(platform: TargetPlatform.macOS),
      ),
    );

    expect(
      find.byKey(const ValueKey('ianvs-markdown-code-language-badge')),
      findsNothing,
    );
    expect(find.text('Dart'), findsNothing);
    expect(find.byTooltip('复制'), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('ianvs-markdown-code-block'))),
    );
    await tester.pump();

    expect(find.text('Dart'), findsNothing);
    expect(find.byTooltip('复制'), findsOneWidget);
    expect(find.byTooltip('关闭自动换行'), findsNothing);
    expect(find.byTooltip('自动换行'), findsNothing);
    final copyButton = tester.widget<IconButton>(
      find.descendant(
        of: find.byType(IanvsMarkdownCodeBlock),
        matching: find.byType(IconButton),
      ),
    );
    expect(
      copyButton.constraints,
      const BoxConstraints(minWidth: 32, minHeight: 28),
    );
    expect(
      copyButton.padding,
      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    );
    expect(
      copyButton.style?.backgroundColor?.resolve(<WidgetState>{}),
      Colors.transparent,
    );
    expect(
      copyButton.style?.overlayColor?.resolve(<WidgetState>{
        WidgetState.hovered,
      }),
      IanvsMarkdownThemeData.light.codeForeground.withValues(alpha: .2),
    );
  });

  testWidgets('dark code blocks use the white Border dot pattern', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const IanvsMarkdown(data: '```text\ndark\n```'),
        theme: ThemeData.dark(),
      ),
    );

    final surface = tester.widget<Container>(
      find.byKey(const ValueKey('ianvs-markdown-code-block')),
    );
    expect(
      (surface.decoration! as BoxDecoration).color,
      IanvsMarkdownThemeData.dark.surface,
    );
    final pattern = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('ianvs-markdown-code-pattern')),
    );
    expect(
      (pattern.painter! as IanvsMarkdownCodePatternPainter).color,
      Colors.white.withValues(alpha: .12),
    );
  });

  testWidgets('reading copy feedback matches Obsidian one-second check', (
    tester,
  ) async {
    String? copied;
    await tester.pumpWidget(
      app(
        IanvsMarkdown(
          data: '```text\ncopy me\n```',
          onCopyCode: (source) => copied = source,
        ),
        theme: ThemeData(platform: TargetPlatform.android),
      ),
    );

    await tester.tap(find.byTooltip('复制'));
    await tester.pump();
    expect(copied, 'copy me');
    expect(find.byTooltip('已复制到剪贴板'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 999));
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byTooltip('复制'), findsOneWidget);
    expect(find.byIcon(Icons.content_copy_rounded), findsOneWidget);
  });

  testWidgets('touch editing code blocks keep their copyable language flair', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const IanvsMarkdown(
          data: '```dart\nfinal value = 1;\n```',
          obsidianMetadataMode: IanvsMarkdownObsidianMetadataMode.editing,
        ),
        theme: ThemeData(platform: TargetPlatform.android),
      ),
    );

    expect(
      find.byKey(const ValueKey('ianvs-markdown-code-language-badge')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ianvs-markdown-code-action-strip')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ianvs-markdown-code-flair')),
      findsOneWidget,
    );
    expect(find.text('Dart'), findsOneWidget);
    expect(find.byTooltip('关闭自动换行'), findsNothing);
    expect(find.byTooltip('自动换行'), findsNothing);
    expect(find.byTooltip('复制'), findsOneWidget);
  });

  testWidgets('code blocks use four-column tab stops but copy source tabs', (
    tester,
  ) async {
    const source = 'root\n\tchild\na\tb';
    String? copied;
    await tester.pumpWidget(
      app(
        IanvsMarkdown(
          data: '```text\n$source\n```',
          obsidianMetadataMode: IanvsMarkdownObsidianMetadataMode.editing,
          onCopyCode: (value) => copied = value,
        ),
        theme: ThemeData(platform: TargetPlatform.android),
      ),
    );

    final rendered = tester.widget<SelectableText>(
      find.descendant(
        of: find.byType(IanvsMarkdownCodeBlock),
        matching: find.byType(SelectableText),
      ),
    );
    expect(rendered.textSpan?.toPlainText(), 'root\n    child\na   b');

    await tester.tap(find.byTooltip('复制'));
    await tester.pump();
    expect(copied, source);
  });

  testWidgets('code blocks soft-wrap long lines like Obsidian', (tester) async {
    const source =
        'final veryLongIdentifier = alpha + beta + gamma + delta + epsilon + '
        'zeta + eta + theta + iota + kappa;';
    Future<Size> renderedSize(double width) async {
      await tester.pumpWidget(
        app(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: const IanvsMarkdown(data: '```dart\n$source\n```'),
            ),
          ),
        ),
      );
      return tester.getSize(
        find.descendant(
          of: find.byType(IanvsMarkdownCodeBlock),
          matching: find.byType(SelectableText),
        ),
      );
    }

    final narrowSize = await renderedSize(180);
    final wideSize = await renderedSize(700);
    expect(
      narrowSize.height,
      greaterThan(wideSize.height),
      reason: 'narrow: $narrowSize, wide: $wideSize',
    );
    expect(
      find.descendant(
        of: find.byType(IanvsMarkdownCodeBlock),
        matching: find.byType(Scrollbar),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'unclosed fences render to the document end without copying a newline',
    (tester) async {
      const source = 'final value = 1;\ntail';
      String? copied;
      await tester.pumpWidget(
        app(
          IanvsMarkdown(
            data: '```DART extra\n$source',
            obsidianMetadataMode: IanvsMarkdownObsidianMetadataMode.editing,
            onCopyCode: (value) => copied = value,
          ),
          theme: ThemeData(platform: TargetPlatform.android),
        ),
      );

      expect(find.text('Dart'), findsOneWidget);
      final rendered = tester.widget<SelectableText>(
        find.descendant(
          of: find.byType(IanvsMarkdownCodeBlock),
          matching: find.byType(SelectableText),
        ),
      );
      expect(rendered.textSpan?.toPlainText(), source);

      await tester.tap(find.byTooltip('复制'));
      await tester.pump();
      expect(copied, source);
    },
  );

  testWidgets('four-backtick code blocks render and copy inner fences', (
    tester,
  ) async {
    const inner =
        '```dart\n'
        'final answer = 42;\n'
        '```';
    const markdown =
        '````markdown\n'
        '$inner\n'
        '````';
    String? copied;

    await tester.pumpWidget(
      app(
        IanvsMarkdown(
          data: markdown,
          obsidianMetadataMode: IanvsMarkdownObsidianMetadataMode.editing,
          onCopyCode: (value) => copied = value,
        ),
        theme: ThemeData(platform: TargetPlatform.android),
      ),
    );

    expect(find.byType(IanvsMarkdownCodeBlock), findsOneWidget);
    final rendered = tester.widget<SelectableText>(
      find.descendant(
        of: find.byType(IanvsMarkdownCodeBlock),
        matching: find.byType(SelectableText),
      ),
    );
    expect(rendered.textSpan?.toPlainText(), inner);

    await tester.tap(find.byTooltip('复制'));
    await tester.pump();
    expect(copied, inner);
  });

  testWidgets('indented code stays plain and dedented without fenced chrome', (
    tester,
  ) async {
    const markdown = '    const first = 1;\n\n\treturn first;';
    const code = 'const first = 1;\n\nreturn first;';

    await tester.pumpWidget(
      app(
        const IanvsMarkdown(
          data: markdown,
          obsidianMetadataMode: IanvsMarkdownObsidianMetadataMode.editing,
        ),
        theme: ThemeData(platform: TargetPlatform.android),
      ),
    );

    expect(find.byType(IanvsMarkdownCodeBlock), findsNothing);
    expect(find.byType(IanvsMarkdownIndentedCodeBlock), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-code-language-badge')),
      findsNothing,
    );
    expect(find.byTooltip('复制'), findsNothing);
    final rendered = tester.widget<SelectableText>(
      find.descendant(
        of: find.byType(IanvsMarkdownIndentedCodeBlock),
        matching: find.byType(SelectableText),
      ),
    );
    expect(rendered.data, code);
  });

  testWidgets('long code blocks stay fully expanded like Obsidian by default', (
    tester,
  ) async {
    final source = List.generate(
      32,
      (index) => 'line ${(index + 1).toString().padLeft(2, '0')}: value',
    ).join('\n');

    await tester.pumpWidget(
      app(
        SingleChildScrollView(
          child: IanvsMarkdown(data: '```text\n$source\n```'),
        ),
        theme: ThemeData(platform: TargetPlatform.android),
      ),
    );

    expect(
      find.byKey(const ValueKey('ianvs-markdown-code-scroll-region')),
      findsNothing,
    );
    expect(find.text('展开'), findsNothing);
    expect(
      tester.getSize(find.byType(IanvsMarkdownCodeBlock)).height,
      greaterThan(320),
    );
  });

  testWidgets('hosts can opt into collapsing long code blocks', (tester) async {
    final source = List.generate(
      32,
      (index) => 'line ${(index + 1).toString().padLeft(2, '0')}: value',
    ).join('\n');

    await tester.pumpWidget(
      app(
        SingleChildScrollView(
          child: IanvsMarkdownCodeBlock(
            source: source,
            language: 'text',
            collapseLongBlocks: true,
          ),
        ),
        theme: ThemeData(platform: TargetPlatform.android),
      ),
    );

    expect(
      find.byKey(const ValueKey('ianvs-markdown-code-scroll-region')),
      findsOneWidget,
    );
    expect(find.text('展开'), findsOneWidget);

    await tester.tap(find.text('展开'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ianvs-markdown-code-scroll-region')),
      findsNothing,
    );
    expect(find.text('收起'), findsOneWidget);
  });

  test('dark code highlighting uses the Border syntax palette', () {
    final span = markdownHighlightedCodeSpan(
      'final value = true;',
      language: 'dart',
      baseStyle: const TextStyle(color: Colors.white),
      dark: true,
    );

    expect(_textSpanContainsColor(span, const Color(0xfff2b6de)), isTrue);
  });

  test(
    'light code highlighting uses Border keyword string and value colors',
    () {
      final span = markdownHighlightedCodeSpan(
        'final message = "ready"; final count = 42;',
        language: 'dart',
        baseStyle: const TextStyle(color: Colors.black),
      );

      expect(_textSpanContainsColor(span, const Color(0xffdd1399)), isTrue);
      expect(_textSpanContainsColor(span, const Color(0xff1da51d)), isTrue);
      expect(_textSpanContainsColor(span, const Color(0xff8f47e1)), isTrue);
    },
  );

  testWidgets('renders Obsidian Wiki links, aliases, and tag chips', (
    tester,
  ) async {
    final taps = <(String, String?)>[];
    await tester.pumpWidget(
      app(
        IanvsMarkdown(
          data:
              '[[Target Note]] [[folder/Source|Alias]] [[|Leading Pipe]] '
              '[[]] #project/flutter [external](https://example.com)',
          onTapLink: (text, href, title) => taps.add((text, href)),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('ianvs-markdown-wiki-link')),
      findsNWidgets(3),
    );
    expect(find.byKey(const ValueKey('ianvs-markdown-tag')), findsOneWidget);
    expect(find.text('Target Note'), findsOneWidget);
    expect(find.text('Alias'), findsOneWidget);
    expect(find.text('|Leading Pipe'), findsOneWidget);
    expect(find.textContaining('[[]]'), findsOneWidget);
    expect(find.text('#project/flutter'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-external-link-icon')),
      findsOneWidget,
    );
    expect(find.textContaining('[[Target Note]]'), findsNothing);
    expect(find.textContaining('[[folder/Source|Alias]]'), findsNothing);
    expect(find.textContaining('[[|Leading Pipe]]'), findsNothing);

    await tester.tap(find.text('Alias'));
    await tester.pump();
    await tester.tap(find.text('|Leading Pipe'));
    await tester.pump();
    await tester.tap(find.text('#project/flutter'));
    await tester.pump();
    expect(taps, <(String, String?)>[
      ('Alias', 'folder/Source'),
      ('|Leading Pipe', '|Leading Pipe'),
      ('#project/flutter', 'tag:#project/flutter'),
    ]);
  });

  testWidgets('formats Wiki heading targets by presentation mode', (
    tester,
  ) async {
    final taps = <(String, String?)>[];
    await tester.pumpWidget(
      app(
        IanvsMarkdown(
          data:
              '[[Note#Heading]] [[#Local Heading]] [[Note#^block]] '
              '[[folder/Note#Heading]] [[Note#Heading|Alias]]',
          onTapLink: (text, href, title) => taps.add((text, href)),
        ),
      ),
    );

    expect(find.text('Note > Heading'), findsOneWidget);
    expect(find.text('Local Heading'), findsOneWidget);
    expect(find.text('Note > ^block'), findsOneWidget);
    expect(find.text('folder/Note > Heading'), findsOneWidget);
    expect(find.text('Alias'), findsOneWidget);
    expect(find.textContaining('Note#Heading'), findsNothing);

    await tester.tap(find.text('Note > Heading'));
    await tester.pump();
    expect(taps, <(String, String?)>[('Note > Heading', 'Note#Heading')]);

    await tester.pumpWidget(
      app(
        const IanvsMarkdown(
          data: '[[Note#Heading]] [[#Local Heading]] [[Note#Heading|Alias]]',
          obsidianMetadataMode: IanvsMarkdownObsidianMetadataMode.editing,
        ),
      ),
    );

    expect(find.text('Note#Heading'), findsOneWidget);
    expect(find.text('Local Heading'), findsOneWidget);
    expect(find.text('Alias'), findsOneWidget);
    expect(find.textContaining(' > '), findsNothing);
  });

  testWidgets('renders Obsidian inline and display math with safe boundaries', (
    tester,
  ) async {
    final rendered = <({String expression, bool displayMode})>[];
    await tester.pumpWidget(
      app(
        IanvsMarkdown(
          data: r'''
Inline $E = mc^2$ and same-line $$x^2 + 1$$.

Escaped \$E = mc^2\$; currency $5 and total $10; code `$not_math$`.

$$
\int_0^1 x^2\,dx = \frac{1}{3}
$$
''',
          mathBuilder: (context, expression, {required displayMode}) {
            rendered.add((expression: expression, displayMode: displayMode));
            return Text('${displayMode ? 'display' : 'inline'}:$expression');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(rendered, <({String expression, bool displayMode})>[
      (expression: 'E = mc^2', displayMode: false),
      (expression: 'x^2 + 1', displayMode: true),
      (expression: r'\int_0^1 x^2\,dx = \frac{1}{3}', displayMode: true),
    ]);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-inline-math')),
      findsNWidgets(2),
    );
    expect(
      find.byKey(const ValueKey('ianvs-markdown-display-math')),
      findsOneWidget,
    );
  });

  testWidgets('invalid TeX uses an Obsidian-style visible fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(const IanvsMarkdown(data: r'Broken: $\frac{1}{$ tail.')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ianvs-markdown-math-error')),
      findsOneWidget,
    );
    expect(find.text(r'\frac{1}{'), findsOneWidget);
  });

  testWidgets('styles host-resolved missing Wiki links like Obsidian', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        IanvsMarkdown(
          data: '[[Existing Note]] [[Missing Note#Ghost Heading]]',
          wikiLinkExists: (target) => !target.startsWith('Missing Note'),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('ianvs-markdown-wiki-link')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ianvs-markdown-wiki-link-unresolved')),
      findsOneWidget,
    );
    final existing = tester.widget<Text>(find.text('Existing Note'));
    final missing = tester.widget<Text>(
      find.text('Missing Note > Ghost Heading'),
    );
    expect(existing.style?.decoration, TextDecoration.underline);
    expect(missing.style?.decoration, TextDecoration.none);
    expect(missing.style?.color, IanvsMarkdownThemeData.light.headingAccent(6));
  });

  testWidgets('renders Obsidian note, heading, and block embeds', (
    tester,
  ) async {
    final references = <String, IanvsMarkdownWikiEmbedReference>{};
    final taps = <(String, String?)>[];
    await tester.pumpWidget(
      app(
        IanvsMarkdown(
          data: '''
![[Target Note]]

![[Target Note#Section A|Section alias]]

![[Target Note#^target-block]]
''',
          wikiEmbedBuilder: (context, reference) {
            references[reference.target] = reference;
            return Text('Resolved: ${reference.displayLabel}');
          },
          onTapLink: (text, href, title) => taps.add((text, href)),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('ianvs-markdown-wiki-embed')),
      findsNWidgets(3),
    );
    expect(find.text('Resolved: Target Note'), findsOneWidget);
    expect(find.text('Resolved: Section alias'), findsOneWidget);
    expect(find.text('Resolved: Target Note#^target-block'), findsOneWidget);
    expect(find.textContaining('![['), findsNothing);

    expect(references['Target Note']?.note, 'Target Note');
    expect(references['Target Note']?.subpath, isNull);
    expect(references['Target Note#Section A']?.note, 'Target Note');
    expect(references['Target Note#Section A']?.subpath, 'Section A');
    expect(references['Target Note#Section A']?.isHeadingReference, isTrue);
    expect(references['Target Note#Section A']?.alias, 'Section alias');
    expect(references['Target Note#^target-block']?.subpath, '^target-block');
    expect(references['Target Note#^target-block']?.isBlockReference, isTrue);

    await tester.tap(
      find.byKey(const ValueKey('ianvs-markdown-wiki-embed-open')).at(1),
    );
    await tester.pump();
    expect(taps, <(String, String?)>[
      ('Section alias', 'Target Note#Section A'),
    ]);
  });

  testWidgets('uses a safe fallback for unresolved Obsidian embeds', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(const IanvsMarkdown(data: '![[Missing Note#Details]]')),
    );

    expect(find.byType(IanvsMarkdownWikiEmbed), findsOneWidget);
    expect(find.text('Missing Note#Details'), findsOneWidget);
    expect(find.byIcon(Icons.note_outlined), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('ianvs-markdown-wiki-embed-open')),
          )
          .onPressed,
      isNull,
    );
    expect(find.textContaining('![['), findsNothing);
  });

  testWidgets('keeps Obsidian embed syntax literal inside fenced code', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const IanvsMarkdown(
          data: '''
```text
![[Target Note#Section A]]
```
''',
        ),
      ),
    );

    expect(find.byType(IanvsMarkdownWikiEmbed), findsNothing);
    expect(find.textContaining('![[Target Note#Section A]]'), findsOneWidget);
    expect(find.byType(IanvsMarkdownCodeBlock), findsOneWidget);
  });

  testWidgets('renders Obsidian highlights and collapsible callouts', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const IanvsMarkdown(
          data: '''
Before ==highlighted **bold**== after.

> [!note] Note title
> Callout body with ==marked text==.

> [!warning]- Folded warning
> Hidden body line.
''',
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('ianvs-markdown-callout-note')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ianvs-markdown-callout-warning')),
      findsOneWidget,
    );
    expect(find.text('Note title'), findsOneWidget);
    expect(find.textContaining('Callout body with'), findsOneWidget);
    expect(find.text('Folded warning'), findsOneWidget);
    expect(find.textContaining('Hidden body line.'), findsNothing);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-highlight')),
      findsNWidgets(2),
    );
    expect(_renderedTextHasBackground(tester, 'highlighted'), isTrue);
    expect(_renderedTextHasBackground(tester, 'marked text'), isTrue);

    await tester.tap(
      find.byKey(const ValueKey('ianvs-markdown-callout-toggle-warning')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Hidden body line.'), findsOneWidget);
  });

  testWidgets('Border callout cards keep Obsidian color and spacing rhythm', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const IanvsMarkdown(
          data:
              '> [!note] Default note\n'
              '> First paragraph.\n'
              '>\n'
              '> Second paragraph.\n\n'
              '> [!tip]+ Expandable tip\n'
              '> Expanded body line 1.\n'
              '> Expanded body line 2.\n\n'
              '> [!error]- Collapsed error\n'
              '> Hidden body line.',
        ),
        theme: ThemeData.dark(),
      ),
    );

    final note = find.byKey(const ValueKey('ianvs-markdown-callout-note'));
    final tip = find.byKey(const ValueKey('ianvs-markdown-callout-tip'));
    final error = find.byKey(const ValueKey('ianvs-markdown-callout-error'));
    expect(tester.getSize(note).height, inInclusiveRange(123, 127));
    expect(tester.getSize(tip).height, inInclusiveRange(111, 114));
    expect(tester.getSize(error).height, 42);

    final noteDecoration =
        tester.widget<AnimatedContainer>(note).decoration! as BoxDecoration;
    final tipDecoration =
        tester.widget<AnimatedContainer>(tip).decoration! as BoxDecoration;
    final errorDecoration =
        tester.widget<AnimatedContainer>(error).decoration! as BoxDecoration;
    expect(noteDecoration.border, isNull);
    expect(tipDecoration.border, isNull);
    expect(errorDecoration.border, isNull);
    expect(
      noteDecoration.color,
      IanvsMarkdownThemeData.dark.taskStatusBlue.withValues(alpha: .14),
    );
    expect(
      tipDecoration.color,
      IanvsMarkdownThemeData.dark.taskStatusCyan.withValues(alpha: .14),
    );
    expect(
      errorDecoration.color,
      IanvsMarkdownThemeData.dark.taskStatusRed.withValues(alpha: .14),
    );

    final noteBody = find.byKey(
      const ValueKey('ianvs-markdown-callout-body-note'),
    );
    expect(
      tester
              .getRect(
                find.descendant(
                  of: noteBody,
                  matching: find.byType(IanvsMarkdown),
                ),
              )
              .left -
          tester.getRect(note).left,
      20,
    );
    expect(
      tester
              .getRect(
                find.descendant(of: note, matching: find.byType(Icon)).first,
              )
              .left -
          tester.getRect(note).left,
      20,
    );
  });

  testWidgets('callouts retain lazy bodies and Markdown-formatted titles', (
    tester,
  ) async {
    const source = '''
> [!warning]- **Bold warning** with `code`
> Quoted body.
Unmarked lazy body.
> Quoted tail.
> > [!note] Nested note
> > Nested body.
---
Outside callout.
''';
    await tester.pumpWidget(app(const IanvsMarkdown(data: source)));

    final warning = find.byKey(
      const ValueKey('ianvs-markdown-callout-warning'),
    );
    expect(warning, findsOneWidget);
    expect(_renderedTextIsBold(tester, 'Bold warning'), isTrue);
    expect(_renderedTextHasBackground(tester, 'code'), isTrue);
    expect(find.textContaining('Unmarked lazy body.'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('ianvs-markdown-callout-toggle-warning')),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: warning,
        matching: find.textContaining('Unmarked lazy body.'),
      ),
      findsOneWidget,
    );
    final nestedNote = find.descendant(
      of: warning,
      matching: find.byKey(const ValueKey('ianvs-markdown-callout-note')),
    );
    expect(nestedNote, findsOneWidget);
    expect(tester.getRect(nestedNote).left - tester.getRect(warning).left, 20);
    expect(find.text('Outside callout.'), findsOneWidget);
  });

  testWidgets('renders Obsidian comments, block IDs, and inline footnotes', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const IanvsMarkdown(
          data: '''
Visible before %%inline secret%% visible after.

Paragraph with a block identifier. ^probe-block

Footnotes[^standard] and inline ^[Inline footnote with **bold**].

[^standard]: Standard footnote body.

%%
Hidden block comment.
Second hidden line.
%%
''',
        ),
      ),
    );

    expect(find.textContaining('Visible before'), findsOneWidget);
    expect(
      find.textContaining('Paragraph with a block identifier.'),
      findsOneWidget,
    );
    expect(find.textContaining('inline secret'), findsNothing);
    expect(find.textContaining('probe-block'), findsNothing);
    expect(find.textContaining('Hidden block comment'), findsNothing);
    expect(find.textContaining('Second hidden line'), findsNothing);
    expect(find.textContaining('Standard footnote body.'), findsOneWidget);
    expect(find.textContaining('Inline footnote with'), findsOneWidget);
    expect(_renderedTextIsBold(tester, 'bold'), isTrue);
  });

  testWidgets('editing metadata mode preserves and subdues Obsidian source', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const IanvsMarkdown(
          data: '''
Visible %%inline secret%% then %%second secret%% after. ^probe-block

Standard[^standard] and inline ^[inline footnote body].

[^standard]: Definition source.
''',
          obsidianMetadataMode: IanvsMarkdownObsidianMetadataMode.editing,
        ),
      ),
    );

    expect(find.text('%%inline secret%%'), findsOneWidget);
    expect(find.text('%%second secret%%'), findsOneWidget);
    expect(find.text(' ^probe-block'), findsOneWidget);
    expect(find.text('[^standard]'), findsOneWidget);
    expect(find.text('^[inline footnote body]'), findsOneWidget);
    expect(find.text('[^standard]: Definition source.'), findsOneWidget);

    final comment = tester.widget<Text>(find.text('%%inline secret%%'));
    expect(comment.style?.fontFamily, isNotNull);
    expect(comment.style?.color, isNotNull);
  });

  test('Obsidian rendering preprocessing preserves literal code', () {
    const source = '''
Text %%hidden%% ^[visible note] ^block-id

`%%inline code%% ^[not a footnote] ^not-an-id`

```text
%%fenced comment%%
^[not a footnote] ^fenced-id
```
''';

    final rendered = prepareObsidianMarkdownForRendering(source);

    expect(rendered, isNot(contains('hidden')));
    expect(rendered, isNot(contains('^block-id')));
    expect(rendered, contains('[^ianvs-inline-footnote-1]'));
    expect(rendered, contains('[^ianvs-inline-footnote-1]: visible note'));
    expect(
      rendered,
      contains('`%%inline code%% ^[not a footnote] ^not-an-id`'),
    );
    expect(rendered, contains('%%fenced comment%%'));
    expect(rendered, contains('^[not a footnote] ^fenced-id'));
  });

  test('collects standard footnote order outside comments and code', () {
    const source = '''
Second[^b], first[^a], repeated[^b], and inline ^[not standard].

%% hidden[^hidden] %% and `code[^code]`.

```text
fenced[^fenced]
```

[^a]: Alpha.
[^b]: Beta.
''';

    expect(collectObsidianStandardFootnoteOrdinals(source), <String, int>{
      'b': 1,
      'a': 2,
    });
    expect(
      prepareObsidianFootnoteDefinitionForEditing(
        '[^b]: **Beta** definition.',
        document: source,
      ),
      '1. **Beta** definition.',
    );
    expect(
      prepareObsidianMarkdownForRendering(
        source,
        mode: IanvsMarkdownObsidianMetadataMode.editing,
      ),
      source,
    );
  });

  testWidgets('supports custom image and Mermaid renderers', (tester) async {
    Uri? imageUri;
    String? diagramSource;
    await tester.pumpWidget(
      app(
        IanvsMarkdown(
          data: '''
![local](diagram.png)

```mermaid
graph TD; A-->B
```
''',
          imageBuilder: (uri, title, alt) {
            imageUri = uri;
            return Text('custom image: $alt');
          },
          diagramBuilder: (context, source) {
            diagramSource = source;
            return const Text('custom diagram');
          },
        ),
      ),
    );

    expect(imageUri, Uri.parse('diagram.png'));
    expect(find.text('custom image: local'), findsOneWidget);
    expect(diagramSource, 'graph TD; A-->B');
    expect(find.text('custom diagram'), findsOneWidget);
  });

  testWidgets('full view renders front matter and navigable outline', (
    tester,
  ) async {
    IanvsMarkdownHeading? selected;
    final longBody = List<String>.generate(
      35,
      (index) => 'Paragraph $index with enough text to create height.',
    ).join('\n\n');
    await tester.pumpWidget(
      app(
        IanvsMarkdownView(
          data:
              '''
---
title: Extracted renderer
author: Ianvs
tags: [flutter, markdown]
---
# Intro

$longBody

## Details

Done.
''',
          onHeadingSelected: (heading) => selected = heading,
        ),
      ),
    );

    expect(find.byType(IanvsMarkdownFrontMatterCard), findsOneWidget);
    expect(find.text('Extracted renderer'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-outline')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ianvs-markdown-outline-heading-1')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('收起文档大纲'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('展开文档大纲'), findsOneWidget);
    await tester.tap(find.byTooltip('展开文档大纲'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('ianvs-markdown-outline-heading-1')),
    );
    await tester.pumpAndSettle();
    expect(selected?.text, 'Details');
    final scroll = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('ianvs-markdown-scroll-view')),
    );
    expect(scroll.controller?.offset, greaterThan(0));
  });

  testWidgets('uses a complete descending H1-H6 scale and outline', (
    tester,
  ) async {
    MarkdownStyleSheet? styleSheet;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) {
            styleSheet = ianvsMarkdownStyleSheet(context);
            return const IanvsMarkdownView(
              data:
                  '# One\n\n## Two\n\n### Three\n\n#### Four\n\n##### Five\n\n###### Six',
              outlineBreakpoint: 0,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      <double?>[
        styleSheet?.h1?.fontSize,
        styleSheet?.h2?.fontSize,
        styleSheet?.h3?.fontSize,
        styleSheet?.h4?.fontSize,
        styleSheet?.h5?.fontSize,
        styleSheet?.h6?.fontSize,
      ],
      <double>[26, 21, 18, 16, 14.5, 13.5],
    );
    expect(
      find.byKey(const ValueKey('ianvs-markdown-outline-heading-5')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ianvs-markdown-heading-rail-5')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ianvs-markdown-heading-rail-6')),
      findsOneWidget,
    );
  });

  testWidgets('standalone headings keep Obsidian level-color rails', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(const IanvsMarkdown(data: '## Embedded heading')),
    );

    final rail = tester.widget<Container>(
      find.byKey(const ValueKey('ianvs-markdown-standalone-heading-rail-2')),
    );
    final decoration = rail.decoration! as BoxDecoration;
    final border = decoration.border! as Border;
    expect(border.left.color, IanvsMarkdownThemeData.light.headingAccent(2));
    expect(find.text('Embedded heading'), findsOneWidget);
  });

  testWidgets('falls back to bounded plain text after syntax overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const IanvsMarkdown(
          data: '**one** **two**',
          renderBudget: IanvsMarkdownRenderBudget(
            maxSyntaxTokens: 1,
            maxFallbackBytes: 8,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('ianvs-markdown-plain-fallback')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('ianvs-markdown-body')), findsNothing);
  });

  testWidgets('uses ThemeExtension colors', (tester) async {
    const customSurface = Color(0xff123456);
    const customCode = Color(0xffabcdef);
    final theme = ThemeData(
      extensions: <ThemeExtension<dynamic>>[
        IanvsMarkdownThemeData.light.copyWith(
          surface: customSurface,
          codeForeground: customCode,
        ),
      ],
    );
    await tester.pumpWidget(
      app(const IanvsMarkdown(data: '```text\nhello\n```'), theme: theme),
    );

    final surface = tester.widget<Container>(
      find.byKey(const ValueKey('ianvs-markdown-code-block')),
    );
    expect((surface.decoration! as BoxDecoration).color, customSurface);
    final code = tester.widget<SelectableText>(
      find.descendant(
        of: find.byType(IanvsMarkdownCodeBlock),
        matching: find.byType(SelectableText),
      ),
    );
    expect(code.style?.color, customCode);
  });

  testWidgets('uses Border quote surfaces and Obsidian horizontal rules', (
    tester,
  ) async {
    late MarkdownStyleSheet styleSheet;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) {
            styleSheet = ianvsMarkdownStyleSheet(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final quote =
        styleSheet.blockquoteDecoration! as IanvsMarkdownQuoteDecoration;
    expect(quote.backgroundColor, IanvsMarkdownThemeData.light.surface);
    expect(quote.patternColor, Colors.black.withValues(alpha: .12));
    expect(quote.railColor, IanvsMarkdownThemeData.light.accent);
    expect(quote.railWidth, 3);
    expect(quote.inset, 8);
    expect(quote.radius, 4);
    expect(
      styleSheet.blockquotePadding,
      const EdgeInsets.fromLTRB(27, 8, 8, 8),
    );

    final rule = styleSheet.horizontalRuleDecoration! as BoxDecoration;
    final ruleBorder = rule.border! as Border;
    expect(ruleBorder.top.color, IanvsMarkdownThemeData.light.borderSoft);
    expect(ruleBorder.top.width, 2);

    final tableBorder = styleSheet.tableBorder!;
    expect(tableBorder.top.color, IanvsMarkdownThemeData.light.borderSoft);
    expect(
      styleSheet.tableCellsPadding,
      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    );
  });

  testWidgets('Border quote dots switch to white in dark mode', (tester) async {
    late MarkdownStyleSheet styleSheet;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) {
            styleSheet = ianvsMarkdownStyleSheet(context);
            return const IanvsMarkdown(data: '> Dark quote');
          },
        ),
        theme: ThemeData.dark(),
      ),
    );

    final quote =
        styleSheet.blockquoteDecoration! as IanvsMarkdownQuoteDecoration;
    expect(quote.backgroundColor, IanvsMarkdownThemeData.dark.surface);
    expect(quote.patternColor, Colors.white.withValues(alpha: .12));
    expect(quote.railColor, IanvsMarkdownThemeData.dark.accent);
    expect(
      tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .where((widget) => widget.decoration is IanvsMarkdownQuoteDecoration),
      hasLength(1),
    );
  });

  testWidgets('compact front matter follows Obsidian property rows', (
    tester,
  ) async {
    const entries = <MarkdownMetadataEntry>[
      MarkdownMetadataEntry(
        key: 'title',
        label: '标题',
        value: 'Properties probe',
      ),
      MarkdownMetadataEntry(key: 'status', label: '状态', value: 'draft'),
      MarkdownMetadataEntry(
        key: 'aliases',
        label: '别名',
        value: 'Probe alias',
        items: <String>['Probe alias'],
      ),
      MarkdownMetadataEntry(
        key: 'tags',
        label: '标签',
        value: 'probe/properties',
        items: <String>['probe/properties'],
      ),
      MarkdownMetadataEntry(key: 'empty', label: 'empty', value: ''),
    ];
    await tester.pumpWidget(
      app(
        const IanvsMarkdownFrontMatterCard(
          entries: entries,
          compact: true,
          showDocumentTitle: true,
          initiallyExpanded: false,
        ),
      ),
    );

    expect(find.text('Properties probe'), findsOneWidget);
    expect(find.text('笔记属性'), findsOneWidget);
    expect(find.text('YAML front matter'), findsNothing);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-front-matter-row-status')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('ianvs-markdown-front-matter-toggle')),
    );
    await tester.pumpAndSettle();

    expect(find.text('status'), findsOneWidget);
    expect(find.text('draft'), findsOneWidget);
    expect(find.text('aliases'), findsOneWidget);
    expect(find.text('Probe alias'), findsOneWidget);
    expect(find.text('tags'), findsOneWidget);
    expect(find.text('probe/properties'), findsOneWidget);
    expect(find.text('没有值'), findsOneWidget);
    expect(find.text('添加笔记属性'), findsOneWidget);
    expect(find.text('状态'), findsNothing);
    expect(
      find.byKey(const ValueKey('ianvs-markdown-front-matter-chip-tags-0')),
      findsOneWidget,
    );
  });

  testWidgets('compact properties preserve typed YAML presentation', (
    tester,
  ) async {
    const entries = <MarkdownMetadataEntry>[
      MarkdownMetadataEntry(
        key: 'enabled',
        label: 'enabled',
        value: 'true',
        type: MarkdownMetadataValueType.boolean,
      ),
      MarkdownMetadataEntry(
        key: 'score',
        label: 'score',
        value: '42',
        type: MarkdownMetadataValueType.number,
      ),
      MarkdownMetadataEntry(
        key: 'due',
        label: 'due',
        value: '2026-08-24',
        type: MarkdownMetadataValueType.date,
      ),
      MarkdownMetadataEntry(
        key: 'related',
        label: 'related',
        value: '[[Project Notes]] · [[Probe#Metadata]]',
        items: <String>['[[Project Notes]]', '[[Probe#Metadata]]'],
        type: MarkdownMetadataValueType.list,
      ),
      MarkdownMetadataEntry(
        key: 'nested',
        label: 'nested',
        value: '{"owner":"Codex"}',
        type: MarkdownMetadataValueType.object,
      ),
    ];
    await tester.pumpWidget(
      app(
        const IanvsMarkdownFrontMatterCard(
          entries: entries,
          compact: true,
          initiallyExpanded: true,
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('ianvs-markdown-front-matter-value-enabled')),
      findsOneWidget,
    );
    expect(find.text('true'), findsNothing);
    expect(find.text('2026 / 08 / 24'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.textContaining('Project Notes'), findsOneWidget);
    expect(find.textContaining('Probe > Metadata'), findsOneWidget);
    expect(find.text('{"owner":"Codex"}'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('ianvs-markdown-front-matter-type-score'),
        ),
        matching: find.text('01'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('uses distinct Obsidian markers for nested unordered lists', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const IanvsMarkdown(
          data: '- Parent\n  - Nested\n    - Deep\n      - Deeper',
        ),
      ),
    );

    IanvsMarkdownUnorderedListMarker marker(int level) => tester.widget(
      find.byKey(ValueKey('ianvs-markdown-unordered-marker-$level')),
    );

    expect(marker(0).shape, IanvsMarkdownUnorderedListMarkerShape.circle);
    expect(marker(1).shape, IanvsMarkdownUnorderedListMarkerShape.square);
    expect(marker(2).shape, IanvsMarkdownUnorderedListMarkerShape.diamond);
    expect(marker(3).shape, IanvsMarkdownUnorderedListMarkerShape.ring);
  });
}

bool _renderedTextHasBackground(
  WidgetTester tester,
  String text, {
  Color? color,
}) {
  bool hasBackground(InlineSpan span, [Color? inheritedBackground]) {
    if (span is! TextSpan) return false;
    final background = span.style?.backgroundColor ?? inheritedBackground;
    if ((span.text?.contains(text) ?? false) &&
        background != null &&
        (color == null || background == color)) {
      return true;
    }
    return (span.children ?? const <InlineSpan>[]).any(
      (child) => hasBackground(child, background),
    );
  }

  return tester
          .widgetList<RichText>(find.byType(RichText))
          .any((widget) => hasBackground(widget.text)) ||
      tester
          .widgetList<Text>(find.byType(Text))
          .any(
            (widget) =>
                widget.textSpan != null && hasBackground(widget.textSpan!),
          ) ||
      tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .any(
            (widget) =>
                widget.textSpan != null && hasBackground(widget.textSpan!),
          );
}

bool _renderedTextUsesInlineCodeStyle(
  WidgetTester tester,
  String text,
  IanvsMarkdownThemeData colors,
) {
  bool hasStyle(InlineSpan span, [TextStyle inherited = const TextStyle()]) {
    if (span is! TextSpan) return false;
    final style = inherited.merge(span.style);
    if ((span.text?.contains(text) ?? false) &&
        style.fontFamily == colors.monoFontFamily &&
        style.fontSize == 12 &&
        style.height == 1.35 &&
        style.color == colors.inlineCodeForeground &&
        style.backgroundColor == colors.surfaceHover) {
      return true;
    }
    return (span.children ?? const <InlineSpan>[]).any(
      (child) => hasStyle(child, style),
    );
  }

  return tester
          .widgetList<RichText>(find.byType(RichText))
          .any((widget) => hasStyle(widget.text)) ||
      tester
          .widgetList<Text>(find.byType(Text))
          .any(
            (widget) => widget.textSpan != null && hasStyle(widget.textSpan!),
          ) ||
      tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .any(
            (widget) => widget.textSpan != null && hasStyle(widget.textSpan!),
          );
}

bool _renderedPlainTextContains(WidgetTester tester, String text) {
  return tester
          .widgetList<RichText>(find.byType(RichText))
          .any((widget) => widget.text.toPlainText().contains(text)) ||
      tester
          .widgetList<Text>(find.byType(Text))
          .any(
            (widget) =>
                widget.textSpan?.toPlainText().contains(text) ??
                widget.data?.contains(text) ??
                false,
          ) ||
      tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .any(
            (widget) =>
                widget.textSpan?.toPlainText().contains(text) ??
                widget.data?.contains(text) ??
                false,
          );
}

bool _textSpanContainsColor(InlineSpan span, Color color) {
  if (span is! TextSpan) return false;
  if (span.style?.color == color) return true;
  return (span.children ?? const <InlineSpan>[]).any(
    (child) => _textSpanContainsColor(child, color),
  );
}

bool _renderedTextIsBold(WidgetTester tester, String text) {
  bool isBold(InlineSpan span, [FontWeight? inheritedWeight]) {
    if (span is! TextSpan) return false;
    final weight = span.style?.fontWeight ?? inheritedWeight;
    if ((span.text?.contains(text) ?? false) &&
        weight != null &&
        weight.value >= FontWeight.w600.value) {
      return true;
    }
    return (span.children ?? const <InlineSpan>[]).any(
      (child) => isBold(child, weight),
    );
  }

  return tester
          .widgetList<RichText>(find.byType(RichText))
          .any((widget) => isBold(widget.text)) ||
      tester
          .widgetList<Text>(find.byType(Text))
          .any(
            (widget) => widget.textSpan != null && isBold(widget.textSpan!),
          ) ||
      tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .any((widget) => widget.textSpan != null && isBold(widget.textSpan!));
}

bool _renderedTextIsItalic(WidgetTester tester, String text) {
  bool isItalic(InlineSpan span, [FontStyle? inheritedStyle]) {
    if (span is! TextSpan) return false;
    final style = span.style?.fontStyle ?? inheritedStyle;
    if ((span.text?.contains(text) ?? false) && style == FontStyle.italic) {
      return true;
    }
    return (span.children ?? const <InlineSpan>[]).any(
      (child) => isItalic(child, style),
    );
  }

  return tester
          .widgetList<RichText>(find.byType(RichText))
          .any((widget) => isItalic(widget.text)) ||
      tester
          .widgetList<Text>(find.byType(Text))
          .any(
            (widget) => widget.textSpan != null && isItalic(widget.textSpan!),
          ) ||
      tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .any(
            (widget) => widget.textSpan != null && isItalic(widget.textSpan!),
          );
}

bool _renderedTextHasDecoration(
  WidgetTester tester,
  String text,
  TextDecoration decoration,
) {
  bool hasDecoration(InlineSpan span, [TextDecoration? inheritedDecoration]) {
    if (span is! TextSpan) return false;
    final current = span.style?.decoration ?? inheritedDecoration;
    if ((span.text?.contains(text) ?? false) && current == decoration) {
      return true;
    }
    return (span.children ?? const <InlineSpan>[]).any(
      (child) => hasDecoration(child, current),
    );
  }

  return tester
          .widgetList<RichText>(find.byType(RichText))
          .any((widget) => hasDecoration(widget.text)) ||
      tester
          .widgetList<Text>(find.byType(Text))
          .any(
            (widget) =>
                widget.textSpan != null && hasDecoration(widget.textSpan!),
          ) ||
      tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .any(
            (widget) =>
                widget.textSpan != null && hasDecoration(widget.textSpan!),
          );
}

bool _renderedTextHasColor(WidgetTester tester, String text, Color color) {
  bool hasColor(InlineSpan span, [Color? inheritedColor]) {
    if (span is! TextSpan) return false;
    final current = span.style?.color ?? inheritedColor;
    if ((span.text?.contains(text) ?? false) && current == color) return true;
    return (span.children ?? const <InlineSpan>[]).any(
      (child) => hasColor(child, current),
    );
  }

  return tester
          .widgetList<RichText>(find.byType(RichText))
          .any((widget) => hasColor(widget.text)) ||
      tester
          .widgetList<Text>(find.byType(Text))
          .any(
            (widget) => widget.textSpan != null && hasColor(widget.textSpan!),
          ) ||
      tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .any(
            (widget) => widget.textSpan != null && hasColor(widget.textSpan!),
          );
}
