// Supplement native Finder/app measurements with separately killable phase
// attribution. Pass LARGE_DOCUMENT_PATH and LARGE_DOCUMENT_MODE defines.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_markdown/src/editor/editor_diagnostics.dart';
// The production host policy is deliberately shared with this repo-local probe.
// ignore: avoid_relative_lib_imports
import '../app/lib/src/document_render_policy.dart';

void main() {
  testWidgets('large document probe', (tester) async {
    const path = String.fromEnvironment('LARGE_DOCUMENT_PATH');
    const mode = String.fromEnvironment(
      'LARGE_DOCUMENT_MODE',
      defaultValue: 'finder',
    );
    final source = File(path).readAsStringSync();
    final decision = scanMarkdownForRendering(
      source,
      budget: linefoldDocumentRenderBudget,
    );
    expect(
      decision.useMarkdown,
      !const bool.fromEnvironment('LARGE_DOCUMENT_REJECTED'),
    );
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    IanvsMarkdownEditorDiagnostics.resetPhases();
    // ignore: avoid_print
    print('PROBE_READY $mode');
    final rssBefore = ProcessInfo.currentRss;
    final watch = Stopwatch()..start();
    final controller = IanvsMarkdownController(
      text: source,
      parseBudget: linefoldDocumentRenderBudget,
    );
    addTearDown(controller.dispose);
    final Widget body = switch (mode) {
      'finder' => IanvsMarkdown(
        data: source,
        scrollable: true,
        renderBudget: linefoldDocumentRenderBudget,
      ),
      'read' => IanvsMarkdownView(
        data: source,
        renderBudget: linefoldDocumentRenderBudget,
        showOutline: false,
      ),
      'live' => IanvsMarkdownLiveEditor(
        controller: controller,
        renderBudget: linefoldDocumentRenderBudget,
      ),
      _ => throw ArgumentError(mode),
    };
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
    await tester.pumpAndSettle();
    watch.stop();
    expect(tester.takeException(), isNull);
    // ignore: avoid_print
    print(
      'PROBE_RESULT ${jsonEncode({'mode': mode, 'sourceCodeUnits': source.length, 'elapsedUs': watch.elapsedMicroseconds, 'rssBefore': rssBefore, 'rssBytes': ProcessInfo.currentRss, 'peakRssBytes': ProcessInfo.maxRss, 'phases': IanvsMarkdownEditorDiagnostics.phaseSnapshot()})}',
    );
  });
}
