// Local document verification; source documents and screenshots stay out of Git.
// flutter test tool/document_layout_probe.dart --dart-define=LAYOUT_DOCUMENT=/absolute/file.md
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  const path = String.fromEnvironment('LAYOUT_DOCUMENT');
  testWidgets('local document tables and reference definitions fit', (
    tester,
  ) async {
    final source = File(path).readAsStringSync();
    final tables = RegExp(
      r'^\|.*(?:\n\|.*)*',
      multiLine: true,
    ).allMatches(source).map((m) => m.group(0)!).toList();
    final definitions = RegExp(
      r'^\[[^\]]+\]:.*$',
      multiLine: true,
    ).allMatches(source).map((m) => m.group(0)!).join('\n');
    expect(tables, isNotEmpty);
    expect(definitions, isNotEmpty);
    await tester.runAsync(() async {
      final font = File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf');
      final loader = FontLoader('LayoutProbe')
        ..addFont(Future.value(ByteData.sublistView(await font.readAsBytes())));
      await loader.load();
    });
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final metrics = <String>[];
    for (final width in [480.0, 720.0, 1000.0]) {
      for (final scale in [1.0, 1.5]) {
        for (var index = 0; index <= tables.length; index++) {
          final referenceOnly = index == tables.length;
          final text = referenceOnly
              ? definitions
              : '${tables[index]}\n\n$definitions';
          final controller = IanvsMarkdownController(text: text);
          final boundaryKey = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(fontFamily: 'LayoutProbe'),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: width,
                      child: RepaintBoundary(
                        key: boundaryKey,
                        child: IanvsMarkdownLiveEditor(
                          key: UniqueKey(),
                          controller: controller,
                          contentMaxWidth: width,
                          showToolbar: false,
                          showNavigationPane: false,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (!referenceOnly) {
            final table = tester.renderObject<RenderTable>(find.byType(Table));
            for (var row = 0; row < table.rows; row++) {
              for (final cell in table.row(row)) {
                final rect =
                    cell.localToGlobal(Offset.zero, ancestor: table) &
                    cell.size;
                expect(rect.left, greaterThanOrEqualTo(-.1));
                expect(rect.right, lessThanOrEqualTo(table.size.width + .1));
              }
            }
            metrics.add(
              '$width/$scale table $index: columns ${table.row(0).map((c) => c.size.width.toStringAsFixed(1)).join(", ")}; height ${table.size.height.toStringAsFixed(1)}',
            );
          } else {
            final group = find.byKey(
              const ValueKey('ianvs-markdown-reference-definitions'),
            );
            final rows = find.descendant(
              of: group,
              matching: find.byType(IanvsMarkdown),
            );
            expect(rows, findsNWidgets(definitions.split('\n').length));
            for (var row = 0; row < rows.evaluate().length; row++) {
              final rect = tester.getRect(rows.at(row));
              final links = find.descendant(
                of: rows.at(row),
                matching: find.byType(Text),
              );
              for (final link in links.evaluate()) {
                final box = link.renderObject! as RenderBox;
                final bounds = box.localToGlobal(Offset.zero) & box.size;
                expect(bounds.bottom, lessThanOrEqualTo(rect.bottom + .1));
              }
              if (row > 0) {
                expect(
                  rect.top,
                  greaterThanOrEqualTo(
                    tester.getRect(rows.at(row - 1)).bottom - .1,
                  ),
                );
              }
            }
            metrics.add(
              '$width/$scale references: ${rows.evaluate().length} rows contained',
            );
          }
          expect(controller.text, text);
          expect(controller.isDirty, isFalse);
          expect(tester.takeException(), isNull);
          if (scale == 1 &&
              (index == 0 || index == 1 || index >= tables.length - 2)) {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                'build/document-layout/${width.toInt()}-$index.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
        }
      }
    }
    await tester.runAsync(() async {
      await File(
        'build/document-layout/metrics.txt',
      ).writeAsString(metrics.join('\n'));
    });
  }, skip: path.isEmpty);
}
