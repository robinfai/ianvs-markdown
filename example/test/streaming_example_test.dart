import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown_example/async_diagram.dart';
import 'package:ianvs_markdown_example/streaming.dart';

const first = (documentId: 'A', revision: 1, source: 'A --> B');
const second = (documentId: 'B', revision: 1, source: 'A --> B');
Widget host(ExampleDiagramRequest request, ExampleDiagramLoader loader) =>
    MaterialApp(
      home: Scaffold(
        body: ExampleAsyncDiagram(request: request, load: loader),
      ),
    );

class Loader {
  final pending = <Completer<String>>[];
  Future<String> load(ExampleDiagramRequest request) {
    final result = Completer<String>();
    pending.add(result);
    return result.future;
  }
}

ScrollController scrollOf(WidgetTester tester) => tester
    .widget<SingleChildScrollView>(
      find.byKey(const ValueKey('streaming-scroll')),
    )
    .controller!;
Future<void> append(WidgetTester tester) async {
  await tester.tap(find.text('Append fragment'));
  await tester.pumpAndSettle();
}

void main() {
  for (final changed in ['document', 'revision', 'source', 'loader']) {
    testWidgets('async diagram clears old result on $changed change', (
      tester,
    ) async {
      final loader = Loader();
      Future<String> replacement(ExampleDiagramRequest request) =>
          loader.load(request);
      await tester.pumpWidget(host(first, loader.load));
      loader.pending.single.complete('First preview');
      await tester.pumpAndSettle();
      expect(find.text('First preview'), findsOneWidget);
      final next = (
        documentId: changed == 'document' ? 'B' : 'A',
        revision: changed == 'revision' ? 2 : 1,
        source: changed == 'source' ? 'A --> C' : first.source,
      );
      await tester.pumpWidget(
        host(next, changed == 'loader' ? replacement : loader.load),
      );
      expect(loader.pending, hasLength(2));
      expect(find.text('First preview'), findsNothing);
      expect(find.text('Loading diagram preview…'), findsOneWidget);
      loader.pending.last.complete('Current preview');
      await tester.pumpAndSettle();
      expect(find.text('Current preview'), findsOneWidget);
    });
  }
  for (final failure in [false, true]) {
    testWidgets(
      'late ${failure ? 'error' : 'success'} cannot replace newer diagram',
      (tester) async {
        final loader = Loader();
        await tester.pumpWidget(host(first, loader.load));
        await tester.pumpWidget(host(second, loader.load));
        loader.pending.last.complete('New document preview');
        await tester.pumpAndSettle();
        if (failure) {
          loader.pending.first.completeError(StateError('stale'));
        } else {
          loader.pending.first.complete('Old document preview');
        }
        await tester.pumpAndSettle();
        expect(find.text('New document preview'), findsOneWidget);
        expect(find.text('Old document preview'), findsNothing);
        expect(find.text('Diagram preview unavailable'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('same request reuses work; identity round trip starts fresh', (
    tester,
  ) async {
    final loader = Loader();
    await tester.pumpWidget(host(first, loader.load));
    await tester.pumpWidget(host(first, loader.load));
    expect(loader.pending, hasLength(1));
    await tester.pumpWidget(host(second, loader.load));
    await tester.pumpWidget(host(first, loader.load));
    expect(loader.pending, hasLength(3));
    loader.pending.last.complete('Current A');
    loader.pending.first.complete('Previous A');
    loader.pending[1].complete('Previous B');
    await tester.pumpAndSettle();
    expect(find.text('Current A'), findsOneWidget);
    expect(find.textContaining('Previous'), findsNothing);
  });
  testWidgets('errors retry; completion after disposal is ignored', (
    tester,
  ) async {
    final loader = Loader();
    await tester.pumpWidget(host(first, loader.load));
    loader.pending.first.completeError(StateError('current failure'));
    await tester.pumpAndSettle();
    expect(find.text('Diagram preview unavailable'), findsOneWidget);
    await tester.tap(find.text('Retry diagram'));
    await tester.pumpAndSettle();
    expect(find.text('Loading diagram preview…'), findsOneWidget);
    loader.pending.last.complete('Retried preview');
    await tester.pumpAndSettle();
    expect(find.text('Retried preview'), findsOneWidget);
    await tester.pumpWidget(host(second, loader.load));
    await tester.pumpWidget(const SizedBox());
    loader.pending.last.completeError(StateError('disposed request'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('stream host follows, pauses, resumes and resets documents', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      StreamingExampleApp(loadDiagram: (_) async => 'Preview'),
    );
    await tester.pumpAndSettle();
    final viewport = find.byKey(const ValueKey('streaming-scroll'));
    final scroll = scrollOf(tester);
    expect(scroll.position.maxScrollExtent, greaterThan(100));
    expect(scroll.position.extentAfter, lessThan(1));
    await append(tester);
    expect(scroll.position.extentAfter, lessThan(1));
    await tester.drag(viewport, const Offset(0, 150));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    final paused = scroll.offset;
    await append(tester);
    expect(scroll.offset, closeTo(paused, 1));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(scroll.position.extentAfter, lessThan(1));
    for (var i = 2; i < streamingFragments.length; i += 1) {
      await append(tester);
    }
    expect(find.text('Fragment 6 / 6'), findsOneWidget);
    expect(find.text('Complete.', findRichText: true), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Append fragment'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Switch document'));
    await tester.pumpAndSettle();
    expect(find.text('Fragment 0 / 6'), findsOneWidget);
    expect(scroll.offset, 0);
    expect(find.text('Complete.', findRichText: true), findsNothing);
    expect(find.byType(ExampleAsyncDiagram), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
  testWidgets('async height changes follow only the current document', (
    tester,
  ) async {
    final loader = Loader();
    await tester.pumpWidget(StreamingExampleApp(loadDiagram: loader.load));
    await tester.pumpAndSettle();
    final scroll = scrollOf(tester);
    await append(tester);
    loader.pending.single.complete(List.filled(50, 'Large preview').join('\n'));
    await tester.pumpAndSettle();
    expect(scroll.position.extentAfter, lessThan(1));
    await append(tester);
    await tester.tap(find.text('Switch document'));
    await tester.pumpAndSettle();
    loader.pending.last.complete('Stale diagram after switch');
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    expect(find.text('Stale diagram after switch'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
