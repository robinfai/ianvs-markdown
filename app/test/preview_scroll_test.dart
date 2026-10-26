import 'preview_test_support.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/preview/preview_app.dart';
import 'package:linefold/src/preview/preview_controller.dart';
import 'package:linefold/src/preview/preview_library.dart';
import 'package:linefold/src/preview/preview_platform.dart';

String _longBody() => List.generate(
  80,
  (i) => '# Section $i\n\nParagraph $i with enough content to scroll.',
).join('\n\n');

Finder _readerScroll() => find.descendant(
  of: find.byType(IanvsMarkdownView),
  matching: find.byKey(const ValueKey('ianvs-markdown-scroll-view')),
);

ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(of: _readerScroll(), matching: find.byType(Scrollable))
          .first,
    )
    .position;

void main() {
  testWidgets('same-document refresh preserves position; shorter text clamps', (
    tester,
  ) async {
    final library = _Library();
    final controller = PreviewController(library: library);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      LinefoldPreviewApp(
        readingPositions: memoryPreviewReadingPositions(),
        controller: controller,
        platform: _Platform(),
      ),
    );
    await tester.pumpAndSettle();
    await controller.open('/a/note.md');
    await tester.pumpAndSettle();
    final position = _position(tester);
    position.jumpTo(1200);
    await tester.pumpAndSettle();
    library.body += '\n\n# Appended section\n\nNew text.';
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(_position(tester), same(position));
    expect(position.pixels, 1200);
    library.body = '# Short\n\nOnly this.';
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(position.pixels, position.maxScrollExtent);
    expect(position.pixels, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'user scrolling after refresh starts is never restored backwards',
    (tester) async {
      final library = _Library();
      final controller = PreviewController(library: library);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        LinefoldPreviewApp(
          readingPositions: memoryPreviewReadingPositions(),
          controller: controller,
          platform: _Platform(),
        ),
      );
      await tester.pumpAndSettle();
      await controller.open('/a/note.md');
      await tester.pumpAndSettle();
      final position = _position(tester);
      position.jumpTo(1200);
      await tester.pumpAndSettle();
      final pending = Completer<String>();
      library.pending = pending;
      final refresh = controller.refresh();
      await tester.pump();
      await tester.timedDrag(
        _readerScroll(),
        const Offset(0, -300),
        const Duration(seconds: 1),
      );
      await tester.pump(const Duration(seconds: 1));
      // End any remaining platform-specific ballistic activity at the position
      // chosen by the later gesture, before the document response arrives.
      position.jumpTo(position.pixels);
      final latest = position.pixels;
      expect(latest, greaterThan(1200));
      pending.complete('${library.body}\n\nAn appended remote revision.');
      await refresh;
      await tester.pumpAndSettle();
      expect(position.pixels, latest);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'new documents start at top and returning workspace restores its own position',
    (tester) async {
      final library = _Library()..workspace = _workspace('/a');
      final controller = PreviewController(library: library);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        LinefoldPreviewApp(
          readingPositions: memoryPreviewReadingPositions(),
          controller: controller,
          platform: _Platform(),
        ),
      );
      await tester.pumpAndSettle();
      await controller.open('/a/note.md');
      await tester.pumpAndSettle();
      _position(tester).jumpTo(1200);
      await tester.pumpAndSettle();
      await controller.open('/a/other.md');
      await tester.pumpAndSettle();
      expect(_position(tester).pixels, 0);
      _position(tester).jumpTo(1200);
      await tester.pumpAndSettle();
      library.workspace = _workspace('/b');
      await controller.open('/b/other.md');
      await tester.pumpAndSettle();
      expect(_position(tester).pixels, 0);
      library.workspace = _workspace('/a');
      await controller.open('/a/other.md');
      await tester.pumpAndSettle();
      expect(_position(tester).pixels, closeTo(1200, 1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

PreviewWorkspace _workspace(String path) =>
    PreviewWorkspace(path: path, name: path, isCloud: false);

class _Library extends PreviewLibrary {
  String body = _longBody();
  Completer<String>? pending;

  @override
  Future<String> read(String path) async => body;

  @override
  Future<String> refreshContent(String path) async => pending?.future ?? body;

  @override
  Future<List<PreviewDocument>> list() async => [];
}

class _Platform extends PreviewPlatform {
  @override
  Future<void> start(
    PreviewDelivery onFiles,
    void Function(String) onError,
  ) async {}

  @override
  void dispose() {}
}
