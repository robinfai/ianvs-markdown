import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/services/wiki_note_resolver.dart';
import 'package:linefold/src/widgets/wiki_note_picker.dart';

void main() {
  for (final query in ['Café', 'Cafe\u0301', 'caf', '中文']) {
    testWidgets('picker canonical lookup preserves original spelling: $query', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WikiNotePicker(
            title: 'Insert note link',
            initialQuery: query,
            normalize: (paths) async => paths
                .map((s) => s.replaceAll('e\u0301', 'é').toLowerCase())
                .toList(),
            notes: const [
              WikiNoteCandidate(
                relativePath: '中文/Cafe\u0301.md',
                comparisonPath: '中文/café.md',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('wiki-note-中文/Cafe\u0301.md')),
        findsOneWidget,
      );
    });
  }
}
