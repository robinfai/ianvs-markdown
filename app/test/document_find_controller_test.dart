import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/controllers/document_find_controller.dart';

void main() {
  late IanvsMarkdownController document;
  late DocumentFindController find;

  void open(
    String text, {
    String query = '',
    bool readOnly = false,
    bool revealInitialMatch = true,
  }) {
    document = IanvsMarkdownController(text: text);
    find = DocumentFindController(
      document: document,
      query: query,
      readOnly: readOnly,
      revealInitialMatch: revealInitialMatch,
    );
    addTearDown(() {
      find.dispose();
      document.dispose();
    });
  }

  test('empty queries and no matches do not create edits or selections', () {
    open('one');
    expect(find.count, 0);
    expect(find.currentIndex, -1);
    expect(find.highlight, isNull);
    expect(find.replaceAll(), 0);
    find.query.text = 'missing';
    find.next();
    expect(find.currentIndex, -1);
    expect(find.replaceCurrent(), isFalse);
    expect(document.text, 'one');
    expect(document.canUndo, isFalse);
  });

  test(
    'literal punctuation, nonoverlap and case option use source offsets',
    () {
      open('A.* a.* A.* aaa', query: 'a.*');
      expect(find.count, 3);
      expect(find.matches.first, const TextRange(start: 0, end: 3));
      find.setMatchCase(true);
      expect(find.matches, [const TextRange(start: 4, end: 7)]);
      find.query.text = 'aa';
      expect(find.count, 1);
      expect(find.matches.single, const TextRange(start: 12, end: 14));
    },
  );

  test('forward and backward wrap and reissue the same highlight', () {
    open('cat cat', query: 'cat');
    expect(find.currentIndex, 0);
    find.next(backwards: true);
    expect(find.currentIndex, 1);
    find.next();
    expect(find.currentIndex, 0);
    expect(
      document.selection,
      const TextSelection(baseOffset: 0, extentOffset: 3),
    );
    final old = find.highlight;
    find.query.text = 'cat cat';
    find.next();
    expect(find.currentIndex, 0);
    expect(identical(old, find.highlight), isFalse);
    expect(document.canUndo, isFalse);
  });

  test(
    'Chinese, emoji, combining marks and Unicode case retain exact source',
    () {
      open('🙂 中文 e\u0301 İ kelvin K 🙂 中文', query: '🙂');
      expect(find.matches.first, const TextRange(start: 0, end: 2));
      expect(find.count, 2);
      find.query.text = '中文';
      expect(find.count, 2);
      find.query.text = 'e\u0301';
      expect(find.count, 1);
      find.query.text = 'k';
      expect(find.count, 2);
      find.replacement.text = '中';
      find.replaceAll();
      expect(document.text, '🙂 中文 e\u0301 İ 中elvin 中 🙂 中文');
      document.undo();
      expect(document.text, '🙂 中文 e\u0301 İ kelvin K 🙂 中文');
    },
  );

  test(
    'current unsaved buffer is searched and replaces undo separately from typing',
    () {
      open('disk');
      document.text = 'draft draft';
      find.query.text = 'draft';
      find.replacement.text = 'new';
      expect(find.count, 2);
      expect(find.replaceCurrent(), isTrue);
      expect(document.text, 'new draft');
      expect(find.currentMatch, const TextRange(start: 4, end: 9));
      document.undo();
      expect(document.text, 'draft draft');
      expect(document.isDirty, isTrue);
      document.undo();
      expect(document.text, 'disk');
      expect(document.isDirty, isFalse);
      document.redo();
      document.redo();
      expect(document.text, 'new draft');
    },
  );

  test(
    'replace all is one snapshot, preserves CRLF and treats replacement literally',
    () {
      open(
        '\uFEFF---\r\ntitle: cat\r\n---\r\ncat [cat](cat)\r\n',
        query: 'cat',
      );
      final source = document.text;
      find.replacement.text = r'$1\new';
      expect(find.replaceAll(), 4);
      expect(
        document.text,
        '\uFEFF---\r\ntitle: \$1\\new\r\n---\r\n\$1\\new [\$1\\new](\$1\\new)\r\n',
      );
      document.undo();
      expect(document.text, source);
      expect(document.canUndo, isFalse);
      document.redo();
      expect(find.count, 0);
    },
  );

  test(
    'replacement containing the query is processed once and empty replacement deletes',
    () {
      open('a a', query: 'a');
      find.replacement.text = 'aa';
      expect(find.replaceAll(), 2);
      expect(document.text, 'aa aa');
      expect(find.count, 4);
      document.undo();
      find.replacement.text = '';
      expect(find.replaceAll(), 2);
      expect(document.text, ' ');
    },
  );

  test('no-op replacement adds no undo entry', () {
    open('a a', query: 'a');
    find.replacement.text = 'a';
    find.replaceAll();
    expect(document.text, 'a a');
    expect(document.canUndo, isFalse);
  });

  test('document typing refreshes matches without moving the new caret', () {
    open('one one', query: 'one');
    const value = TextEditingValue(
      text: 'one X one',
      selection: TextSelection.collapsed(offset: 5),
    );
    document.value = value;
    expect(find.count, 2);
    expect(document.value, value);
    expect(find.highlight, isNull);
    expect(find.replaceCurrent(), isFalse);
    expect(find.currentIndex, -1);
    find.next();
    expect(find.highlight!.source, value.text);
    expect(find.currentMatch, const TextRange(start: 6, end: 9));
  });

  for (final owner in ['query', 'replacement', 'document']) {
    test('active $owner composition blocks navigation and replacement', () {
      open('one one', query: 'one');
      final target = switch (owner) {
        'query' => find.query,
        'replacement' => find.replacement,
        _ => document,
      };
      target.value = TextEditingValue(
        text: target.text.isEmpty ? 'ni' : target.text,
        selection: const TextSelection.collapsed(offset: 1),
        composing: const TextRange(start: 0, end: 1),
      );
      final before = document.value;
      find.next();
      expect(find.replaceCurrent(), isFalse);
      expect(find.replaceAll(), 0);
      expect(document.value, before);
      target.value = target.value.copyWith(composing: TextRange.empty);
      expect(find.isComposing, isFalse);
    });
  }

  test('readonly searches never replace until explicitly enabled', () {
    open('one one', query: 'one', readOnly: true);
    find.replacement.text = 'two';
    find.next();
    expect(find.currentIndex, 1);
    expect(find.replaceCurrent(), isFalse);
    expect(find.replaceAll(), 0);
    find.readOnly = false;
    expect(find.replaceAll(), 2);
    expect(document.text, 'two two');
  });

  test('multiline literal search works without normalization', () {
    open('one\r\ntwo\none\ntwo', query: 'one\ntwo');
    expect(find.count, 1);
    expect(find.currentMatch, const TextRange(start: 9, end: 16));
  });

  test('deferred initial reveal does not react to query selection changes', () {
    document = IanvsMarkdownController(text: 'one two one');
    document.selection = const TextSelection.collapsed(offset: 4);
    find = DocumentFindController(
      document: document,
      query: 'one',
      revealInitialMatch: false,
    );
    addTearDown(() {
      find.dispose();
      document.dispose();
    });
    find.query.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
    expect(find.highlight, isNull);
    expect(document.selection, const TextSelection.collapsed(offset: 4));
    find.next();
    expect(find.currentMatch, const TextRange(start: 8, end: 11));
  });

  testWidgets('large match sets remain complete and Replace All has one undo', (
    tester,
  ) async {
    final source = 'a' * (1024 * 1024);
    open(source, query: 'a');
    expect(find.isSearching, isTrue);
    expect(find.count, 0);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.isSearching, isFalse);
    expect(find.count, source.length);
    find.replacement.text = 'b';
    expect(find.replaceAll(), source.length);
    expect(document.text, 'b' * source.length);
    document.undo();
    expect(document.text, source);
    expect(document.canUndo, isFalse);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.count, source.length);
  });

  testWidgets(
    'large search debounces and query selection does not restart it',
    (tester) async {
      open('A.* a.* ' * 10000, query: 'A');
      await tester.pump(const Duration(milliseconds: 100));
      find.query.text = 'a.*';
      expect(find.isSearching, isTrue);
      expect(find.matches, isEmpty);
      expect(find.highlight, isNull);
      expect(find.canNavigate, isFalse);
      expect(find.canReplace, isFalse);
      expect(find.canReplaceAll, isFalse);
      expect(find.replaceCurrent(), isFalse);
      expect(find.replaceAll(), 0);
      await tester.pump(const Duration(milliseconds: 100));
      find.query.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 3,
      );
      await tester.pump(const Duration(milliseconds: 49));
      expect(find.isSearching, isTrue);
      expect(find.count, 0);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.isSearching, isFalse);
      expect(find.count, 20000);
      find.setMatchCase(true);
      expect(find.isSearching, isTrue);
      expect(find.count, 0);
      expect(find.highlight, isNull);
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.count, 10000);
      expect(find.matches.first, const TextRange(start: 4, end: 7));
    },
  );

  testWidgets('a newer query cancels an in-progress chunked search', (
    tester,
  ) async {
    open('ab' * (128 * 1024), query: 'a');
    // This runs after the first window, before its queued continuation.
    Timer(const Duration(milliseconds: 150), () {
      expectSync(find.isSearching, isTrue);
      find.query.text = 'b';
    });
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.isSearching, isTrue);
    expect(find.count, 0);
    expect(find.highlight, isNull);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.count, 128 * 1024);
    expect(find.matches.first, const TextRange(start: 1, end: 2));
    expect(find.matches.last, const TextRange(start: 262143, end: 262144));
    find.query.text = '';
    expect(find.isSearching, isFalse);
    expect(find.matches, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(find.matches, isEmpty);
  });

  testWidgets('case changes cancel an in-progress search', (tester) async {
    open('A a ' * 20000, query: 'a');
    Timer(const Duration(milliseconds: 150), () => find.setMatchCase(true));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.isSearching, isTrue);
    expect(find.count, 0);
    expect(find.highlight, isNull);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.isSearching, isFalse);
    expect(find.count, 20000);
    expect(find.matches.first, const TextRange(start: 2, end: 3));
  });

  testWidgets(
    'source edits invalidate scanning and never apply stale results',
    (tester) async {
      open('a' * (128 * 1024), query: 'a');
      find.replacement.text = 'replacement';
      const edited = TextEditingValue(
        text: 'new a source',
        selection: TextSelection.collapsed(offset: 3),
      );
      Timer(const Duration(milliseconds: 150), () {
        expectSync(find.isSearching, isTrue);
        expectSync(find.replaceAll(), 0);
        document.value = edited;
      });
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.isSearching, isFalse);
      expect(find.matches, [const TextRange(start: 4, end: 5)]);
      expect(find.highlight, isNull);
      expect(find.replaceCurrent(), isFalse);
      expect(document.value, edited);
      await tester.pump(const Duration(seconds: 1));
      expect(document.value, edited);
      expect(find.count, 1);
    },
  );

  for (final owner in ['query', 'replacement', 'document']) {
    testWidgets('active $owner composition cancels scanning until committed', (
      tester,
    ) async {
      open('one ' * 20000, query: 'one');
      find.replacement.text = 'two';
      final target = switch (owner) {
        'query' => find.query,
        'replacement' => find.replacement,
        _ => document,
      };
      Timer(const Duration(milliseconds: 150), () {
        expectSync(find.isSearching, isTrue);
        target.value = target.value.copyWith(
          composing: const TextRange(start: 0, end: 1),
        );
      });
      await tester.pump(const Duration(milliseconds: 150));
      final before = document.value;
      expect(find.isComposing, isTrue);
      expect(find.isSearching, isFalse);
      expect(find.matches, isEmpty);
      expect(find.highlight, isNull);
      find.next();
      expect(find.replaceCurrent(), isFalse);
      expect(find.replaceAll(), 0);
      await tester.pump(const Duration(seconds: 1));
      expect(document.value, before);
      expect(find.matches, isEmpty);
      target.value = target.value.copyWith(composing: TextRange.empty);
      expect(find.isSearching, isTrue);
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.isComposing, isFalse);
      expect(find.count, 20000);
    });
  }

  for (final duringScan in [false, true]) {
    testWidgets(
      'dispose cancels ${duringScan ? 'in-flight' : 'debounced'} search',
      (tester) async {
        final localDocument = IanvsMarkdownController(text: 'a' * (128 * 1024));
        final localFind = DocumentFindController(
          document: localDocument,
          query: 'a',
        );
        var notifications = 0;
        localFind.addListener(() => notifications++);
        final original = localDocument.value;
        if (duringScan) {
          Timer(const Duration(milliseconds: 150), () => localFind.dispose());
        } else {
          localFind.dispose();
        }
        await tester.pump(const Duration(seconds: 1));
        expect(notifications, 0);
        expect(localDocument.value, original);
        expect(tester.takeException(), isNull);
        localDocument.dispose();
      },
    );
  }

  testWidgets('chunk boundaries preserve Unicode and exact UTF-16 ranges', (
    tester,
  ) async {
    final source =
        '${'x' * 16382}中文🙂e\u0301\r\n'
        '${'x' * 16370}🙂中文 K K ſ s 𐐀 𐐨 '
        '${'x' * 16383}🙂 '
        '${'x' * 16383}\uD83D end';
    open(source);
    for (final query in ['中文🙂e\u0301\r\n', '🙂', 'k', 's', '𐐀', '\uD83D']) {
      find.query.text = query;
      await tester.pump(const Duration(milliseconds: 150));
      final expected =
          RegExp(RegExp.escape(query), caseSensitive: false, unicode: true)
              .allMatches(source)
              .map((match) => TextRange(start: match.start, end: match.end));
      expect(find.isSearching, isFalse);
      expect(find.matches, expected.toList(), reason: 'query: $query');
      for (final range in find.matches) {
        expect(range.start, greaterThanOrEqualTo(0));
        expect(range.end, lessThanOrEqualTo(source.length));
      }
    }
  });

  testWidgets(
    'non-overlap carries across windows and replacement is one snapshot',
    (tester) async {
      final source = 'a' * (64 * 1024 + 5);
      open(source, query: 'aaa');
      await tester.pump(const Duration(milliseconds: 150));
      final expected = source.length ~/ 3;
      expect(find.count, expected);
      expect(
        find.matches.last,
        TextRange(start: (expected - 1) * 3, end: expected * 3),
      );
      find.replacement.text = 'aaaa';
      expect(find.replaceAll(), expected);
      expect(document.text, 'a' * (source.length + expected));
      expect(find.isSearching, isTrue);
      expect(find.replaceAll(), 0);
      document.undo();
      expect(document.text, source);
      expect(document.canUndo, isFalse);
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.count, expected);
    },
  );

  testWidgets('deferred reveal preserves navigation and skip-current intent', (
    tester,
  ) async {
    final source = 'one ${'x' * (64 * 1024)} one';
    open(source, query: 'one', revealInitialMatch: false);
    document.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
    find.query.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
    find.next(skipCurrentSelection: true);
    expect(find.highlight, isNull);
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      find.currentMatch,
      TextRange(start: source.length - 3, end: source.length),
    );
    expect(find.highlight, isNotNull);
    expect(document.canUndo, isFalse);
  });

  testWidgets('deferred search without navigation leaves the selection alone', (
    tester,
  ) async {
    open(
      'one ${'x' * (64 * 1024)} one',
      query: 'one',
      revealInitialMatch: false,
    );
    final selection = document.selection;
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.count, 2);
    expect(find.currentIndex, -1);
    expect(find.highlight, isNull);
    expect(document.selection, selection);
    find.next(backwards: true);
    expect(find.currentIndex, 1);
  });

  for (final navigate in [false, true]) {
    testWidgets(
      'moving source selection cancels delayed ${navigate ? 'navigation' : 'reveal'}',
      (tester) async {
        open('one ${'x' * (64 * 1024)} one', query: 'one');
        if (navigate) find.next();
        const moved = TextSelection.collapsed(offset: 10);
        document.selection = moved;
        await tester.pump(const Duration(milliseconds: 150));
        expect(find.count, 2);
        expect(find.currentIndex, -1);
        expect(find.highlight, isNull);
        expect(document.selection, moved);
        find.next();
        expect(find.currentIndex, 1);
      },
    );
  }

  test(
    'synchronous skip-current navigation shares deferred search semantics',
    () {
      open('one two one', query: 'one', revealInitialMatch: false);
      document.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
      find.next(skipCurrentSelection: true);
      expect(find.currentMatch, const TextRange(start: 8, end: 11));
    },
  );
}
