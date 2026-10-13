import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_markdown/src/diagnostics/local_performance/corpus.dart';
import 'package:ianvs_markdown/src/diagnostics/local_performance/probe.dart';

void main() {
  test('fixed corpus covers full Markdown and default-budget fallback', () {
    final outcomes = <bool>[];
    for (final bytes in localCorpusSizes) {
      final text = localCorpus(bytes);
      expect(utf8.encode(text).length, bytes);
      expect(text, contains('中文'));
      expect(text, contains('😀'));
      expect(text.split('\n').every((line) => line.length < 4096), isTrue);
      final controller = IanvsMarkdownController(text: text);
      outcomes.add(controller.parseDecision.useMarkdown);
      expect(controller.text, text);
      if (!controller.parseDecision.useMarkdown) {
        expect(
          controller.parseDecision.budgetExceeded,
          IanvsMarkdownBudgetExceeded.syntaxTokens,
        );
        expect(
          utf8.encode(controller.parseDecision.text).length,
          lessThanOrEqualTo(65536),
        );
      }
      controller.dispose();
    }
    expect(outcomes.first, isTrue);
    expect(outcomes.last, isFalse);
  });
  test('window policy rejects focus, occlusion and minimization loss', () {
    final window = <String, Object?>{
      'active': true,
      'visible': true,
      'occlusionVisible': true,
      'onActiveSpace': true,
      'miniaturized': false,
      'appHidden': false,
    };
    expect(LocalWindowEnvironment.visible(window), isTrue);
    for (final key in window.keys) {
      expect(
        LocalWindowEnvironment.visible({
          ...window,
          key: !(window[key] as bool),
        }),
        isFalse,
      );
    }
    final environment = LocalWindowEnvironment()..invalidate('closed');
    expect(environment.throwIfInvalid, throwsStateError);
  });
}
