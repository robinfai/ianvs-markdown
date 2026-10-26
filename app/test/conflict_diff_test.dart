import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:linefold/src/widgets/save_conflict_diff_dialog.dart';
import 'package:linefold/src/models/conflict_diff.dart';

void main() {
  testWidgets('comparison exposes complete read-only rows to accessibility', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SaveConflictDiffDialog(
            disk: '共同\n\n磁盘旧文\r\n',
            local: '共同\n\n本地新文',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in [
      'Unchanged, disk line 1, local line 1. 共同. LF',
      'Unchanged, disk line 2, local line 2. Blank line. LF',
      'Removed, disk line 3. 磁盘旧文. CRLF',
      'Added, local line 3. 本地新文. No newline',
    ]) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
    expect(
      tester
          .widgetList<EditableText>(find.byType(EditableText))
          .every((text) => text.readOnly),
      isTrue,
    );
  });

  for (final scale in [1.0, 3.0]) {
    testWidgets('comparison remains usable in a small window at scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(840, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: SaveConflictDiffDialog(disk: 'old\r\n', local: 'new\n'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Back to conflict').hitTestable(), findsOneWidget);
      expect(
        tester
            .widgetList<EditableText>(find.byType(EditableText))
            .every((text) => text.readOnly),
        isTrue,
      );
    });
  }

  for (final pair in [
    ('same\nold\nend', 'same\nnew\nend'),
    ('', 'added\n'),
    ('removed\r\n', ''),
    ('中\r\n文\r', '中\n文'),
    ('a\nb\na\n', 'b\na\nb\n'),
  ]) {
    test('diff reconstructs both exact versions $pair', () {
      final diff = ConflictDiff.compare(pair.$1, pair.$2);
      expect(
        diff.lines
            .where((l) => l.kind != ConflictDiffKind.added)
            .map((l) => l.text)
            .join(),
        pair.$1,
      );
      expect(
        diff.lines
            .where((l) => l.kind != ConflictDiffKind.removed)
            .map((l) => l.text)
            .join(),
        pair.$2,
      );
      expect(
        diff.lines.where((l) => l.diskLine != null).map((l) => l.diskLine),
        orderedEquals(
          List.generate(
            diff.lines.where((l) => l.diskLine != null).length,
            (i) => i + 1,
          ),
        ),
      );
    });
  }
  test('large changed middle is complete with bounded comparison work', () {
    final disk =
        'prefix\n${List.generate(1500, (i) => 'old $i\n').join()}suffix';
    final local =
        'prefix\n${List.generate(1500, (i) => 'new $i\n').join()}suffix';
    final diff = ConflictDiff.compare(disk, local);
    expect(diff.coarse, isTrue);
    expect(diff.lines.first.kind, ConflictDiffKind.unchanged);
    expect(diff.lines.last.kind, ConflictDiffKind.unchanged);
    expect(
      diff.lines
          .where((l) => l.kind != ConflictDiffKind.added)
          .map((l) => l.text)
          .join(),
      disk,
    );
    expect(
      diff.lines
          .where((l) => l.kind != ConflictDiffKind.removed)
          .map((l) => l.text)
          .join(),
      local,
    );
  });
}
