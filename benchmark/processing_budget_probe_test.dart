// Run through tool/check_processing_budget.py: each case needs its own process
// and an external timeout, since a blocked synchronous parser cannot yield to
// flutter_test's in-process timeout.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final fixture in [
    'bracket',
    'plain',
    'dense',
    'lines',
    'line_boundary',
    'line_overflow',
    'carriage_returns',
    'bracket_lines',
  ]) {
    for (final operation in ['controller', 'document', 'html', 'partial']) {
      test('$fixture/$operation', () {
        const size = 1024 * 1024;
        final source = switch (fixture) {
          'bracket' => '[${'a' * (size - 1)}',
          'plain' => 'a' * size,
          'dense' => '[x](y) ' * (size ~/ 7),
          'lines' => '${'a' * 127}\n' * (size ~/ 128),
          'line_boundary' => '[${'a' * (4 * 1024 - 1)}',
          'line_overflow' => '[${'a' * (4 * 1024)}',
          'carriage_returns' => 'a\r' * (size ~/ 2),
          'bracket_lines' => '[${'${'a' * 126}\n' * (size ~/ 127 - 1)}',
          _ => throw StateError(fixture),
        };
        // ignore: avoid_print
        print('PROBE_READY $fixture/$operation');
        final watch = Stopwatch()..start();
        final int result;
        final rejected = ![
          'lines',
          'line_boundary',
          'bracket_lines',
        ].contains(fixture);
        switch (operation) {
          case 'controller':
            final controller = IanvsMarkdownController(text: source);
            expect(controller.text, source);
            expect(controller.parseDecision.useMarkdown, !rejected);
            controller.text = '$source\n';
            controller.undo();
            expect(controller.text, source);
            controller.redo();
            expect(controller.text, '$source\n');
            result = controller.text.length;
            controller.dispose();
          case 'document':
            final document = IanvsMarkdownDocument.parse(source);
            expect(document.source, source);
            expect(document.body, source);
            expect(document.parseDecision!.useMarkdown, !rejected);
            for (final preset in IanvsMarkdownSyntaxPreset.values) {
              final folds = IanvsMarkdownHeadingFoldModel.parse(
                source,
                syntaxPreset: preset,
              );
              expect(folds.budgetExceeded != null, rejected);
              expect(folds.source, source);
            }
            result = document.headings.length;
          case 'partial':
            final selection = fixture == 'dense' ? 'x' : 'aaaa';
            final data = ianvsMarkdownSelectionClipboardData(source, selection);
            expect(data.hasHtml, !rejected);
            expect(data.budgetExceeded != null, rejected);
            result = data.markdown.length;
          case 'html':
            final data = ianvsMarkdownDocumentClipboardData(source);
            expect(data.markdown, source);
            expect(data.hasHtml, !rejected);
            expect(data.budgetExceeded != null, rejected);
            expect(ianvsMarkdownClipboardHtml(source).isEmpty, rejected);
            result = data.html.length;
          default:
            throw StateError(operation);
        }
        // ignore: avoid_print
        print(
          'PROBE_RESULT ${jsonEncode({'microseconds': watch.elapsedMicroseconds, 'resultLength': result, 'sourceCodeUnits': source.length, 'rejected': rejected})}',
        );
      });
    }
  }
}
