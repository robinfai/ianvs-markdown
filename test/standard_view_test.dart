import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

Widget app(Widget child) => MaterialApp(
  theme: ThemeData(platform: TargetPlatform.macOS),
  home: Scaffold(body: child),
);

String visibleText(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((widget) => widget.text.toPlainText())
    .join('\n');

void main() {
  const standard = IanvsMarkdownSyntaxPreset.standard;
  const obsidian = IanvsMarkdownSyntaxPreset.obsidian;

  testWidgets('View switches presets, metadata and folded heading identities', (
    tester,
  ) async {
    const source =
        '---\ntitle: Literal YAML\n---\n\nBody %%visible%%.\n\n# End\n\nEnd body';
    final folds = IanvsMarkdownHeadingFoldController();
    addTearDown(folds.dispose);
    Widget view(IanvsMarkdownSyntaxPreset preset) => app(
      IanvsMarkdownView(
        data: source,
        syntaxPreset: preset,
        showFrontMatter: true,
        showOutline: false,
        enableHeadingFolding: true,
        headingFoldController: folds,
      ),
    );
    await tester.pumpWidget(view(standard));
    expect(visibleText(tester), contains('title: Literal YAML'));
    expect(visibleText(tester), contains('Body %%visible%%.'));
    expect(find.byType(IanvsMarkdownFrontMatterCard), findsNothing);
    final yaml = IanvsMarkdownHeadingFoldModel.parse(
      source,
      syntaxPreset: standard,
    ).sections.first;
    folds.toggleIdentity(yaml.identity);
    await tester.pumpAndSettle();
    expect(visibleText(tester), isNot(contains('Body %%visible%%.')));
    await tester.pumpWidget(view(obsidian));
    await tester.pumpAndSettle();
    expect(find.byType(IanvsMarkdownFrontMatterCard), findsOneWidget);
    expect(folds.isCollapsed(yaml.identity), isFalse);
    expect(visibleText(tester), isNot(contains('%%visible%%')));
    await tester.pumpWidget(view(standard));
    await tester.pumpAndSettle();
    expect(visibleText(tester), contains('Body %%visible%%.'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('View standard heading navigation unfolds GFM ancestors', (
    tester,
  ) async {
    const source =
        '---\ntitle: Literal YAML\n---\n\nBody\n\n### Child\n\nHidden child\n\n# End';
    final folds = IanvsMarkdownHeadingFoldController();
    final navigation = ValueNotifier<IanvsMarkdownHeadingNavigation?>(null);
    addTearDown(folds.dispose);
    addTearDown(navigation.dispose);
    final model = IanvsMarkdownHeadingFoldModel.parse(
      source,
      syntaxPreset: standard,
    );
    folds.toggleIdentity(model.sections.first.identity);
    String? selected;
    await tester.pumpWidget(
      app(
        IanvsMarkdownView(
          data: source,
          syntaxPreset: standard,
          enableHeadingFolding: true,
          headingFoldController: folds,
          headingNavigation: navigation,
          onHeadingSelected: (heading) => selected = heading.text,
        ),
      ),
    );
    expect(visibleText(tester), isNot(contains('Hidden child')));
    navigation.value = IanvsMarkdownHeadingNavigation(
      source.indexOf('### Child'),
    );
    await tester.pumpAndSettle();
    expect(selected, 'Child');
    expect(folds.isCollapsed(model.sections.first.identity), isFalse);
    expect(visibleText(tester), contains('Hidden child'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('View uses the same preset for budget, headings and rendering', (
    tester,
  ) async {
    const source =
        '# Title\n\n'
        r'$$$$';
    Widget view(IanvsMarkdownSyntaxPreset preset) => app(
      IanvsMarkdownView(
        data: source,
        syntaxPreset: preset,
        renderBudget: const IanvsMarkdownRenderBudget(maxSyntaxTokens: 1),
      ),
    );
    await tester.pumpWidget(view(standard));
    expect(
      find.byKey(const ValueKey('ianvs-markdown-plain-fallback')),
      findsNothing,
    );
    expect(find.text('Title'), findsNWidgets(2)); // Outline and body.
    await tester.pumpWidget(view(obsidian));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('ianvs-markdown-plain-fallback')),
      findsOneWidget,
    );
    expect(find.text('Title'), findsNothing);
    await tester.pumpWidget(view(standard));
    await tester.pumpAndSettle();
    expect(find.text('Title'), findsNWidgets(2));
  });

  for (final preset in [standard, obsidian]) {
    testWidgets(
      'View $preset fallback bypasses host builders and preserves full copy',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          const source =
              '---\ntitle: Metadata\n---\n\n**😀😀** ![image](asset.png)';
          IanvsMarkdownClipboardData? copied;
          IanvsMarkdownRenderDecision? fallback;
          var images = 0;
          await tester.pumpWidget(
            app(
              IanvsMarkdownView(
                data: source,
                syntaxPreset: preset,
                renderBudget: const IanvsMarkdownRenderBudget(
                  maxSyntaxTokens: 0,
                  maxFallbackBytes: 6,
                ),
                fallbackBuilder: (_, decision) {
                  fallback = decision;
                  return Text(decision.text);
                },
                imageBuilder: (_, _, _) {
                  images++;
                  return const SizedBox();
                },
                clipboardWriter: (data) async => copied = data,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(images, 0);
          expect(fallback?.truncated, isTrue);
          // Rejected documents skip YAML preprocessing as well as Markdown.
          expect(fallback?.text, '---\nti');
          await tester.tap(find.text(fallback!.text));
          await tester.pump();
          for (final key in [
            LogicalKeyboardKey.keyA,
            LogicalKeyboardKey.keyC,
          ]) {
            await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
            await tester.sendKeyEvent(key);
            await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
            await tester.pump();
          }
          expect(copied?.markdown, source);
          expect(copied?.html, contains('<strong>😀😀</strong>'));
          expect(copied?.html.contains('title: Metadata'), isTrue);
          expect(tester.takeException(), isNull);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }

  testWidgets('standard View preserves image and link host hooks', (
    tester,
  ) async {
    final images = <(Uri, String?, String?)>[];
    String? tapped;
    await tester.pumpWidget(
      app(
        IanvsMarkdownView(
          data:
              '![literal|250](asset.png "Title")\n\n[Open](file:///notes/one.md)',
          syntaxPreset: standard,
          imageBuilder: (uri, title, alt) {
            images.add((uri, title, alt));
            return const Text('Host image');
          },
          onTapLink: (_, href, _) => tapped = href,
        ),
      ),
    );
    expect(images, [(Uri.parse('asset.png'), 'Title', 'literal|250')]);
    await tester.tap(find.text('Open'));
    expect(tapped, 'file:///notes/one.md');
    expect(tester.takeException(), isNull);
  });
}
