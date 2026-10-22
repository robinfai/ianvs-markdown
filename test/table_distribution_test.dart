import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

Future<List<double>> widths(WidgetTester tester, String source) async {
  final controller = IanvsMarkdownController(text: source);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 720,
          child: IanvsMarkdownLiveEditor(
            key: UniqueKey(),
            controller: controller,
            showToolbar: false,
            showNavigationPane: false,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final result = <double>[
    for (var column = 0; column < 3; column++)
      tester
          .getSize(find.byKey(ValueKey('ianvs-markdown-table-1-$column')))
          .width,
  ];
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox());
  controller.dispose();
  return result;
}

void main() {
  testWidgets('short identifiers leave space for prose', (tester) async {
    final result = await widths(
      tester,
      '| 编号 | 当前进度 | 尚未满足的部分及下一步 |\n'
      '| --- | --- | --- |\n'
      '| S1 | 已完成协议联调和页面改进，正在补齐实际业务验收。 | '
      '需要明确接口调用方、验收时间、业务场景，并完成异常流程回归。 |\n'
      '| S2 | 已形成方案和验证记录。 | 继续核对实际运行情况并完善方案。 |',
    );
    expect(result[0], lessThan(result[1] / 2));
    expect(result[0], lessThan(result[2] / 2));
  });

  testWidgets('one character does not switch column allocation', (
    tester,
  ) async {
    String table(int length) =>
        '| ID | Progress | Next |\n|---|---|---|\n'
        '| A | ${'x' * length} | ${'x' * 100} |';
    final before = await widths(tester, table(79));
    final after = await widths(tester, table(80));
    for (var i = 0; i < 3; i++) {
      expect((after[i] - before[i]).abs(), lessThan(5));
    }
  });

  testWidgets('reference destination and label syntax do not consume width', (
    tester,
  ) async {
    String table(String link) =>
        '| ID | Evidence | Next |\n|---|---|---|\n'
        '| S1 | $link | Complete the remaining validation and record results |\n\n'
        '[a-very-long-reference-identifier]: docs/evidence.md';
    final inline = await widths(tester, table('[Report](docs/evidence.md)'));
    final reference = await widths(
      tester,
      table('[Report][a-very-long-reference-identifier]'),
    );
    for (var i = 0; i < 3; i++) {
      expect(reference[i], closeTo(inline[i], .5));
    }
  });
  testWidgets('allocation accounts for which cells share a row', (
    tester,
  ) async {
    var changed = false;
    for (final long in [200, 400, 600]) {
      for (final medium in [60, 100, 200]) {
        String table(bool shared) =>
            '| ID | Progress | Next |\n|---|---|---|\n'
            '| A | ${'x' * long} | ${'x' * (shared ? medium : 10)} |\n'
            '| B | ${'x' * 10} | ${'x' * (shared ? 10 : medium)} |';
        // Identical headers, column lengths, averages and maxima. Only the
        // pairing of long cells into rows changes, affecting total row height.
        final shared = await widths(tester, table(true));
        final separate = await widths(tester, table(false));
        if ((shared[1] - separate[1]).abs() > 5) changed = true;
      }
    }
    expect(
      changed,
      isTrue,
      reason: 'Column lengths alone cannot determine the table layout.',
    );
  });

  testWidgets('a long header receives width even when body cells are short', (
    tester,
  ) async {
    final result = await widths(
      tester,
      '| ID | Required validation evidence | Next |\n|---|---|---|\n'
      '| A | Done | OK |\n| B | Done | OK |',
    );
    expect(result[1], greaterThan(result[0] * 2));
    expect(result[1], greaterThan(result[2] * 2));
  });
}
