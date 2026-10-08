import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_markdown/src/editor/reference_links.dart';
import 'package:markdown/markdown.dart' as md;

void main() {
  test('reference-free megabyte line can be opened, edited and restored', () {
    final source = 'a' * (1024 * 1024);
    expect(MarkdownLinkReferenceContext.parse(source).references, isEmpty);
    expect(parseMarkdownLinkReferenceDefinitions(source), isEmpty);
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    controller.text = 'next $source';
    expect(controller.text, 'next $source');
    controller.undo();
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
    controller.redo();
    expect(controller.text, 'next $source');
  });

  test(
    'brackets retain parser authority across containers and literal code',
    () {
      for (final source in [
        '> [ref]: /quoted',
        '- [ref]: /listed',
        '```md\n[ref]: /literal\n```',
        '<div>\n[ref]: /literal\n</div>',
        '[ref]: /real\n\ntext',
      ]) {
        final upstream = md.Document(
          extensionSet: md.ExtensionSet.gitHubFlavored,
        )..parseLines(source.split('\n'));
        final actual = MarkdownLinkReferenceContext.parse(source).references;
        expect(actual.keys, upstream.linkReferences.keys, reason: source);
        for (final key in actual.keys) {
          expect(
            actual[key]!.destination,
            upstream.linkReferences[key]!.destination,
          );
        }
      }
    },
  );

  test('isolated reference definitions preserve destination and title', () {
    const documents = <String>[
      '[label][ref]\n\n[ref]: docs/a\\)b "A \\"title\\""',
      '[label][ref]\n\n[ref]: <docs/a b> \'Single title\'',
      '[label][ref]\n\n[ref]: <docs/a\\>b> "Angle"',
    ];

    for (final source in documents) {
      final context = MarkdownLinkReferenceContext.parse(source);
      final isolated = context.appendDefinitionsTo('[label][ref]');
      expect(
        md.markdownToHtml(
          isolated,
          extensionSet: md.ExtensionSet.gitHubFlavored,
        ),
        md.markdownToHtml(source, extensionSet: md.ExtensionSet.gitHubFlavored),
        reason: source,
      );
    }
  });

  test('isolated reference definitions preserve multiline titles', () {
    const document =
        '[click][ref]\n\n'
        '[ref]: /docs\n'
        '"line one\n'
        'line two"';
    final context = MarkdownLinkReferenceContext.parse(document);
    final isolated = context.appendDefinitionsTo('[click][ref]');

    expect(isolated, '[click][ref]\n\n[ref]: </docs> "line one\nline two"');
    expect(
      md.markdownToHtml(isolated, extensionSet: md.ExtensionSet.gitHubFlavored),
      md.markdownToHtml(document, extensionSet: md.ExtensionSet.gitHubFlavored),
    );
  });

  test('isolated blocks receive only definitions they reference', () {
    const source =
        '[first]: docs/first.md\n'
        '[second]: docs/second.md "Second"';
    final context = MarkdownLinkReferenceContext.parse(source);

    expect(
      context.appendDefinitionsTo('Open [one][first].'),
      'Open [one][first].\n\n[first]: <docs/first.md>',
    );
    expect(context.appendDefinitionsTo('Plain text.'), 'Plain text.');
  });

  test('isolated blocks do not inject normalized whitespace references', () {
    final context = MarkdownLinkReferenceContext.parse('[Ref A]: docs/ref.md');

    expect(
      context.appendDefinitionsTo('[Case][ref a]'),
      '[Case][ref a]\n\n[ref a]: <docs/ref.md>',
    );
    expect(
      context.appendDefinitionsTo('[Whitespace   Ref][  Ref   A  ]'),
      '[Whitespace   Ref][  Ref   A  ]',
    );
  });

  test('isolated blocks preserve parser resolution and inline fallback', () {
    const source =
        r'[ref\]part]: docs/escaped.md'
        '\n[fallback]: docs/fallback.md';
    final context = MarkdownLinkReferenceContext.parse(source);

    expect(
      context.appendDefinitionsTo(r'[label][ref\]part]'),
      r'[label][ref\]part]',
    );
    expect(
      context.appendDefinitionsTo('[fallback](target "unclosed)'),
      '[fallback](target "unclosed)\n\n'
      '[fallback]: <docs/fallback.md>',
    );
  });
}
