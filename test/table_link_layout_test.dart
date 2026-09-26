import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  testWidgets('wrapped directory links stay inside their table row', (
    tester,
  ) async {
    const label = '13 · 为什么第一个 Token 和后续 Token 速度不同？';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 540,
              child: IanvsMarkdown(
                data:
                    '| 篇号与文章 | 范围 | 独立核查 |\n'
                    '|---|---|---|\n'
                    '| [$label](articles/13.md) | 短说明 | [核查记录](checks/13.md) |\n'
                    '| 下一篇 | 内容 | 核查 |',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final table = tester.renderObject<RenderTable>(find.byType(Table));
    final text = tester.renderObject<RenderBox>(find.text(label));
    final offset = text.localToGlobal(Offset.zero, ancestor: table);
    final row = table.getRowBox(1);
    expect(text.size.height, greaterThan(30));
    expect(offset.dy, greaterThanOrEqualTo(row.top));
    expect(
      offset.dy + text.size.height,
      lessThanOrEqualTo(row.bottom),
      reason: 'The full multiline title must fit before the next row.',
    );
    expect(tester.takeException(), isNull);
  });
}
