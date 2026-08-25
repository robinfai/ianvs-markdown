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
}
