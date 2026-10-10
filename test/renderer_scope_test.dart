import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:markdown/markdown.dart' as md;

final class _RoleSyntax extends md.InlineSyntax {
  _RoleSyntax() : super(r'@token');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('r2-shared-role', 'token'));
    return true;
  }
}

final class _RoleBuilder extends MarkdownElementBuilder {
  _RoleBuilder({required this.block});

  final bool block;

  @override
  bool isBlockElement() => block;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => Text('token', key: const ValueKey('role-token'), style: parentStyle);
}

Widget _host(
  String identity, {
  required bool block,
  required IanvsMarkdownSyntaxPreset preset,
}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 500,
        child: IanvsMarkdown(
          key: ValueKey(identity),
          data: 'before @token after',
          syntaxPreset: preset,
          inlineSyntaxes: [_RoleSyntax()],
          builders: {'r2-shared-role': _RoleBuilder(block: block)},
        ),
      ),
    ),
  ),
);

List<Rect> _geometry(WidgetTester tester) => [
  tester.getRect(find.textContaining('before')),
  tester.getRect(find.byKey(const ValueKey('role-token'))),
  tester.getRect(find.textContaining('after')),
];

void main() {
  for (final preset in IanvsMarkdownSyntaxPreset.values) {
    testWidgets(
      '${preset.name}: a block builder cannot change another renderer',
      (tester) async {
        await tester.pumpWidget(
          _host('first-inline', block: false, preset: preset),
        );
        final expected = _geometry(tester);
        await tester.pumpWidget(
          _host('other-block', block: true, preset: preset),
        );
        expect(_geometry(tester), isNot(expected));
        await tester.pumpWidget(
          _host('second-inline', block: false, preset: preset),
        );
        expect(_geometry(tester), expected);
      },
    );
    testWidgets(
      '${preset.name}: repeated configuration changes do not retain block tags',
      (tester) async {
        await tester.pumpWidget(_host('reused', block: false, preset: preset));
        final expected = _geometry(tester);
        for (var iteration = 0; iteration < 20; iteration += 1) {
          await tester.pumpWidget(_host('reused', block: true, preset: preset));
          expect(_geometry(tester), isNot(expected));
          await tester.pumpWidget(
            _host('reused', block: false, preset: preset),
          );
          expect(_geometry(tester), expected, reason: 'iteration $iteration');
        }
      },
    );
  }
}
