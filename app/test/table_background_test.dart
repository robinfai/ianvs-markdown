import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/desktop_theme.dart';
import 'package:linefold/src/desktop_typography.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('table backgrounds stay uniform with ${brightness.name} form theme', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      // Widget tests do not resolve the platform's CJK font fallback.
      final font = File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf');
      if (font.existsSync()) {
        await tester.runAsync(() async {
          final loader = FontLoader(DesktopTypography.fontFamily)
            ..addFont(
              Future.value(ByteData.sublistView(await font.readAsBytes())),
            );
          await loader.load();
        });
      }
      final controller = IanvsMarkdownController(
        text:
            '| ID | 功能与入口 | 结果 / 边界 | 证据 |\n'
            '| --- | --- | --- | --- |\n'
            '| A01 | 新建文档：加号、File、⌘N | ${List.filled(6, '创建独立文档；Live / Source / Read 共享同一份 Markdown。').join(' ')} | U/T |\n'
            '| A02 | 文件树 | 目录按需加载，筛选支持的文件类型。 | U/T |',
      );
      addTearDown(controller.dispose);
      final theme = desktopTheme(brightness);
      final colors = theme.extension<IanvsMarkdownThemeData>()!;
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: RepaintBoundary(
            key: boundaryKey,
            child: Scaffold(
              body: IanvsMarkdownLiveEditor(
                controller: controller,
                showToolbar: false,
                showNavigationPane: false,
                contentMaxWidth: 720,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final table = tester.renderObject<RenderTable>(find.byType(Table));
      final shortCell = find.byKey(const ValueKey('ianvs-markdown-table-1-0'));
      expect(
        table.getRowBox(1).height,
        greaterThan(tester.getSize(shortCell).height + 10),
      );

      Future<void> checkBackground(String state, {bool save = false}) async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final origin = table.localToGlobal(Offset.zero, ancestor: boundary);
        final header = table.getRowBox(0);
        final headerCells = [
          for (final cell in table.row(0))
            cell.localToGlobal(Offset.zero, ancestor: table) & cell.size,
        ];
        final row = table.getRowBox(1);
        late Color headerColor, bodyTop, bodyMiddle, bodyBottom;
        final headerSamples = <Offset, Color>{};
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final pixels = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          Color sample(double y, {double x = 4}) {
            // Stay inside cell padding, away from text, cursor and grid lines.
            final index =
                ((origin.dy + y).floor() * image.width +
                    (origin.dx + x).floor()) *
                4;
            return Color.fromARGB(
              pixels.getUint8(index + 3),
              pixels.getUint8(index),
              pixels.getUint8(index + 1),
              pixels.getUint8(index + 2),
            );
          }

          headerColor = sample(header.center.dy);
          for (final cell in headerCells) {
            for (final x in [cell.left + 4, cell.center.dx, cell.right - 4]) {
              for (final y in [header.top + 3, header.bottom - 3]) {
                headerSamples[Offset(x, y)] = sample(y, x: x);
              }
            }
          }
          bodyTop = sample(row.top + 4);
          bodyMiddle = sample(row.center.dy);
          bodyBottom = sample(row.bottom - 4);
          if (save) {
            final directory = Directory('build/table-background-acceptance');
            await directory.create(recursive: true);
            final png = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            await File(
              '${directory.path}/table-${brightness.name}${state == 'long unbroken content' ? '-wide-content' : ''}.png',
            ).writeAsBytes(png.buffer.asUint8List());
          }
          image.dispose();
        });
        expect(
          bodyMiddle,
          colors.surface,
          reason:
              '$state: a short cell must not paint the form field fill over the document',
        );
        expect(
          bodyTop,
          bodyMiddle,
          reason: '$state: no stripe above short cell',
        );
        expect(
          bodyBottom,
          bodyMiddle,
          reason: '$state: no stripe below short cell',
        );
        expect(
          headerColor,
          colors.surfaceMuted,
          reason:
              '$state: the header background remains visible through its editor',
        );
        for (final sample in headerSamples.entries) {
          expect(
            sample.value,
            colors.surfaceMuted,
            reason: '$state: header background must cover ${sample.key}',
          );
        }
        for (final cell in headerCells) {
          expect(
            cell.right,
            lessThanOrEqualTo(table.size.width + .01),
            reason: '$state: columns must fit the painted table bounds',
          );
        }
      }

      await checkBackground('idle', save: true);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(880, 420));
      await mouse.moveTo(tester.getCenter(shortCell));
      await tester.pumpAndSettle();
      await checkBackground('hover');
      await tester.tap(shortCell);
      await tester.pump();
      await checkBackground('focus');
      await tester.enterText(shortCell, 'A03');
      await tester.pump();
      expect(controller.text, contains('| A03 |'));
      await checkBackground('editing');
      final wideCell = find.byKey(const ValueKey('ianvs-markdown-table-2-2'));
      await tester.tap(wideCell);
      await tester.pumpAndSettle();
      final longToken = List.filled(60, 'W').join();
      await tester.enterText(wideCell, longToken);
      await tester.pumpAndSettle();
      expect(controller.text, contains(longToken));
      await checkBackground('long unbroken content', save: true);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }
}
