import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/src/editor/reference_links.dart';
import 'package:markdown/markdown.dart' as md;

void main() {
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
