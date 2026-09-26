import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_mermaid/ianvs_mermaid.dart';
import 'package:linefold/src/widgets/svg_document_view.dart';

const _svg = '<svg viewBox="0 0 400 200"><path d="M20 20H380V180H20Z"/></svg>';
const _result = SvgRenderResult(svg: _svg, width: 400, height: 200);
Future<SvgRenderResult> _render(String _) async => _result;

void main() {
  testWidgets('wheel, trackpad and clicks pass through a vector SVG', (
    tester,
  ) async {
    final scroll = ScrollController(initialScrollOffset: 100);
    addTearDown(scroll.dispose);
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: scroll,
            child: Column(
              children: [
                const SizedBox(height: 180),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  child: const SizedBox(
                    width: 400,
                    child: SvgDocumentView(svg: _svg, render: _render),
                  ),
                ),
                const SizedBox(height: 1600),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final diagram = find.byType(SvgDocumentView);
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byType(AppKitView), findsNothing);
    for (final dy in [60.0, -60.0]) {
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(diagram),
          scrollDelta: Offset(0, dy),
        ),
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, dy > 0 ? 160 : 100);
    }
    final trackpad = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    for (final dy in [-60.0, 60.0]) {
      final before = scroll.offset;
      final position = tester.getCenter(diagram);
      await trackpad.panZoomStart(position);
      await trackpad.panZoomUpdate(position, pan: Offset(0, dy / 2));
      await tester.pump();
      await trackpad.panZoomUpdate(position, pan: Offset(0, dy));
      await tester.pump();
      expect(scroll.offset, dy < 0 ? greaterThan(before) : lessThan(before));
      await trackpad.panZoomEnd();
      await tester.pumpAndSettle();
    }
    await tester.tapAt(tester.getCenter(diagram));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'updates discard stale SVGs, offer external viewing on errors and dispose safely',
    (tester) async {
      final pending = <String, Completer<SvgRenderResult>>{};
      Future<SvgRenderResult> render(String source) =>
          (pending[source] = Completer<SvgRenderResult>()).future;
      var externalOpens = 0;
      Future<void> show(String source) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  child: SvgDocumentView(
                    svg: source,
                    render: render,
                    onOpenExternal: () => externalOpens++,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }

      await show('old');
      await show('new');
      pending['new']!.complete(
        const SvgRenderResult(
          svg: '<svg viewBox="0 0 400 100"><path d="M0 0H400V100H0Z"/></svg>',
          width: 400,
          height: 100,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(SvgDocumentView)),
        const Size(400, 100),
      );
      final picture = tester
          .widget<SvgPicture>(find.byType(SvgPicture))
          .bytesLoader;
      pending['old']!.complete(_result);
      await tester.pumpAndSettle();
      expect(
        tester.widget<SvgPicture>(find.byType(SvgPicture)).bytesLoader,
        picture,
      );
      await show('unsupported');
      expect(find.byType(SvgPicture), findsNothing);
      pending['unsupported']!.completeError(StateError('foreignObject'));
      await tester.pumpAndSettle();
      expect(find.textContaining('cannot be displayed'), findsOneWidget);
      await tester.tap(find.text('Open in default app'));
      expect(externalOpens, 1);
      await show('closing');
      await tester.pumpWidget(const SizedBox.shrink());
      pending['closing']!.complete(_result);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await show('reopened');
      pending['reopened']!.complete(_result);
      await tester.pumpAndSettle();
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.byType(AppKitView), findsNothing);
    },
  );
}
