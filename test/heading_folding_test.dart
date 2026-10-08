import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  const source = '''
# Alpha

Alpha body.

## Beta

Beta body.

### Gamma

Gamma body.

## Delta

Delta body.

# Omega

Omega body.
''';

  test('heading sections stop at equal or higher heading levels', () {
    final model = IanvsMarkdownHeadingFoldModel.parse(source);
    final alpha = model.sections.firstWhere(
      (section) => section.text == 'Alpha',
    );
    final beta = model.sections.firstWhere((section) => section.text == 'Beta');
    final gamma = model.sections.firstWhere(
      (section) => section.text == 'Gamma',
    );
    final delta = model.sections.firstWhere(
      (section) => section.text == 'Delta',
    );
    final omega = model.sections.firstWhere(
      (section) => section.text == 'Omega',
    );

    expect(alpha.endBlockIndex, omega.headingBlockIndex);
    expect(beta.endBlockIndex, delta.headingBlockIndex);
    expect(gamma.endBlockIndex, delta.headingBlockIndex);
    expect(delta.endBlockIndex, omega.headingBlockIndex);
    expect(omega.endBlockIndex, model.blocks.length);
  });

  test('fold projection preserves nested state and stable identities', () {
    final controller = IanvsMarkdownHeadingFoldController();
    addTearDown(controller.dispose);
    final model = IanvsMarkdownHeadingFoldModel.parse(source);
    final alpha = model.sections.firstWhere(
      (section) => section.text == 'Alpha',
    );
    final beta = model.sections.firstWhere((section) => section.text == 'Beta');

    controller.toggleIdentity(beta.identity);
    var projection = model.project(controller);
    expect(projection.source, contains('## Beta'));
    expect(projection.source, isNot(contains('Beta body.')));
    expect(projection.source, isNot(contains('### Gamma')));
    expect(projection.source, contains('## Delta'));

    controller.toggleIdentity(alpha.identity);
    projection = model.project(controller);
    expect(projection.source, contains('# Alpha'));
    expect(projection.source, isNot(contains('## Beta')));
    expect(projection.source, isNot(contains('## Delta')));
    expect(projection.source, contains('# Omega'));

    controller.toggleIdentity(alpha.identity);
    projection = model.project(controller);
    expect(projection.source, contains('## Beta'));
    expect(projection.source, isNot(contains('Beta body.')));
    expect(projection.source, contains('## Delta'));

    final shifted = IanvsMarkdownHeadingFoldModel.parse(
      'Intro before headings.\n\n$source',
    );
    final shiftedBeta = shifted.sections.firstWhere(
      (section) => section.text == 'Beta',
    );
    expect(shiftedBeta.identity, beta.identity);
  });

  test('standard headings match GFM and preserve CRLF UTF-16 ranges', () {
    const source =
        '---\r\ntitle: 中文😀\r\n---\r\n\r\n'
        '> # Quoted\r\n\r\n- # Listed\r\n\r\n'
        '```md\r\n# Fenced\r\n```\r\n\r\n'
        '<div>\r\n# HTML\r\n</div>\r\n\r\n'
        '# [Named][ref]\r\n\r\nText.\r\n\r\n'
        '%%\r\n## In literal comment\r\n%%\r\n\r\n'
        r'$$'
        '\r\n## In literal math\r\n'
        r'$$'
        '\r\n\r\n'
        'Multiline\r\nsetext\r\n===\r\n\r\n'
        '[ref]: https://example.com\r\n';
    final model = IanvsMarkdownHeadingFoldModel.parse(
      source,
      syntaxPreset: IanvsMarkdownSyntaxPreset.standard,
    );
    expect(model.sections.map((s) => s.text), [
      'title: 中文😀',
      'Named',
      'In literal comment',
      'In literal math',
      'Multiline\nsetext',
    ]);
    expect(
      model.sections.map((s) => (s.level, s.text)),
      parseMarkdownHeadings(source).map((s) => (s.level, s.text)),
    );
    for (final block in model.blocks) {
      expect(source.substring(block.start, block.end), block.source);
      expect(block.source.endsWith('\r'), isFalse);
    }
    final named = model.sections[1];
    expect(
      model.blocks[named.headingBlockIndex].start,
      source.indexOf('# [Named]'),
    );
    final controller = IanvsMarkdownHeadingFoldController();
    addTearDown(controller.dispose);
    expect(model.project(controller).source, source);
    controller.toggleIdentity(named.identity);
    final folded = model.project(controller);
    expect(folded.source, contains('# [Named][ref]'));
    expect(folded.source, isNot(contains('In literal comment')));
    expect(folded.source, isNot(contains('In literal math')));
    expect(folded.source, contains('Multiline\r\nsetext\r\n==='));
  });

  test('standard parser retains GFM table precedence and empty headings', () {
    const source =
        '# Column | Value\n--- | ---\nA | B\n\n'
        '#\n\n## Actual\n\n# End';
    final model = IanvsMarkdownHeadingFoldModel.parse(
      source,
      syntaxPreset: IanvsMarkdownSyntaxPreset.standard,
    );
    expect(model.sections.map((s) => s.text), ['Actual', 'End']);
    expect(model.sections.map((s) => s.canFold), [false, false]);
    expect(
      model.sections.map((s) => s.text),
      parseMarkdownHeadings(source).map((s) => s.text),
    );
  });
}
