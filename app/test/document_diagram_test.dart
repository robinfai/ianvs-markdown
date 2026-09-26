import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_mermaid/ianvs_mermaid.dart';
import 'package:linefold/src/widgets/document_diagram.dart';

const _svg =
    '<svg viewBox="0 0 400 200"><path d="M10 10H390V190H10Z" fill="red"/></svg>';

class _Renderer implements MermaidRenderer {
  final requests = <String, Completer<MermaidRenderResult>>{};
  bool immediate = true;
  int calls = 0;

  @override
  Future<MermaidRenderResult> render(
    String source, {
    MermaidRenderOptions options = MermaidRenderOptions.flutterSvgDefault,
    bool includeLayout = false,
  }) {
    calls++;
    if (immediate) return Future.value(result(source));
    return (requests[source] = Completer<MermaidRenderResult>()).future;
  }

  MermaidRenderResult result(String source) => MermaidRenderResult(
    source: source,
    svg: _svg.replaceFirst('red', source == 'new' ? 'blue' : 'red'),
    optionsJson: '{}',
    width: 400,
    height: 200,
  );
  @override
  void dispose() {}
  @override
  Future<String> layoutJson(
    String source, {
    MermaidRenderOptions options = MermaidRenderOptions.flutterSvgDefault,
  }) async => '{}';
  @override
  Future<MermaidValidationResult> validate(
    String source, {
    MermaidRenderOptions options = MermaidRenderOptions.flutterSvgDefault,
  }) async => const MermaidValidationResult(valid: true);
}

void main() {
  for (final mode in [
    IanvsMarkdownEditorMode.preview,
    IanvsMarkdownEditorMode.livePreview,
  ]) {
    testWidgets(
      '${mode.name}: diagrams pass wheel, trackpad and boundary scrolls to the editor',
      (tester) async {
        final source =
            'Before diagram\n\n```mermaid\nflowchart LR\nA-->B\n```\n\n${List.filled(50, 'Text after diagram.\n\n').join()}';
        final editor = IanvsMarkdownController(text: source, mode: mode);
        final scroll = ScrollController();
        final renderer = _Renderer();
        addTearDown(editor.dispose);
        addTearDown(scroll.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: IanvsMarkdownLiveEditor(
                controller: editor,
                scrollController: scroll,
                showToolbar: false,
                showNavigationPane: false,
                contentMaxWidth: 400,
                diagramBuilder: (_, code) =>
                    DocumentDiagram(source: code, renderer: renderer),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SvgPicture), findsOneWidget);
        expect(find.byType(AppKitView), findsNothing);
        expect(find.byType(InteractiveViewer), findsNothing);
        final diagram = find.byType(DocumentDiagram);
        final initial = scroll.offset;
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(diagram),
            scrollDelta: const Offset(0, 40),
          ),
        );
        await tester.pumpAndSettle();
        expect(scroll.offset, greaterThan(initial));
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(diagram),
            scrollDelta: const Offset(0, -40),
          ),
        );
        await tester.pumpAndSettle();
        expect(scroll.offset, closeTo(initial, 0.1));

        final trackpad = await tester.createGesture(
          kind: PointerDeviceKind.trackpad,
        );
        final start = tester.getCenter(diagram);
        await trackpad.panZoomStart(start);
        // Continue past the bottom of the diagram without transferring ownership.
        await trackpad.panZoomUpdate(start, pan: const Offset(0, -50));
        await tester.pump();
        await trackpad.panZoomUpdate(
          start + const Offset(0, 250),
          pan: const Offset(0, -120),
        );
        await tester.pump();
        expect(scroll.offset, greaterThan(initial));
        await trackpad.panZoomEnd();
        await tester.pumpAndSettle();
        scroll.jumpTo(initial);
        await tester.pumpAndSettle();
        if (mode == IanvsMarkdownEditorMode.livePreview) {
          await tester.tapAt(tester.getCenter(diagram));
          await tester.pumpAndSettle();
          expect(find.byType(EditableText), findsWidgets);
        }
        expect(editor.text, source);
        expect(editor.isDirty, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets(
    'rapid edits, out-of-order completion, errors and disposal never show stale diagrams',
    (tester) async {
      final renderer = _Renderer()..immediate = false;
      Future<void> show(String source) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 400,
                child: DocumentDiagram(source: source, renderer: renderer),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }

      await show('old');
      await show('new');
      renderer.requests['new']!.complete(renderer.result('new'));
      await tester.pumpAndSettle();
      final currentLoader = tester
          .widget<SvgPicture>(find.byType(SvgPicture))
          .bytesLoader;
      renderer.requests['old']!.complete(renderer.result('old'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SvgPicture>(find.byType(SvgPicture)).bytesLoader,
        currentLoader,
      );
      await show('error');
      expect(find.byType(SvgPicture), findsNothing);
      renderer.requests['error']!.completeError(StateError('Invalid diagram'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Unable to render diagram'), findsOneWidget);
      await show('closing');
      await tester.pumpWidget(const SizedBox.shrink());
      renderer.requests['closing']!.complete(renderer.result('closing'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await show('reopened');
      renderer.requests['reopened']!.complete(renderer.result('reopened'));
      await tester.pumpAndSettle();
      expect(find.byType(SvgPicture), findsOneWidget);
    },
  );
}
