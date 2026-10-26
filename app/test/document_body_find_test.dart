import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/controllers/document_find_controller.dart';

void main() {
  testWidgets('next body match navigates to the second repeated list item', (
    tester,
  ) async {
    final document = IanvsMarkdownController(text: '- same\n- same');
    final find = DocumentFindController(
      document: document,
      scope: DocumentFindScope.body,
      query: 'same',
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.count, 2);
    expect(document.sourceNavigation.value!.range.start, 0);
    find.next();
    expect(document.sourceNavigation.value!.range.start, 7);
    expect(find.currentBodyMatch!.sourceRange.start, 0);
    expect(find.currentBodyMatch!.navigationRange.start, 7);
    find.dispose();
    document.dispose();
  });

  testWidgets(
    'body navigation preserves editing state and disallows replacement',
    (tester) async {
      final document = IanvsMarkdownController(
        text: 'hello **world** hello world',
      );
      document.selection = const TextSelection.collapsed(offset: 2);
      final before = document.value;
      final find = DocumentFindController(
        document: document,
        scope: DocumentFindScope.body,
        query: 'hello world',
      );
      addTearDown(() {
        find.dispose();
        document.dispose();
      });
      expect(find.isSearching, isTrue);
      await tester.pump(const Duration(milliseconds: 160));
      expect(find.count, 2);
      expect(find.currentIndex, 0);
      expect(find.currentBodyMatch!.textRange.start, 0);
      expect(document.sourceNavigation.value, isNotNull);
      expect(document.value, before);
      expect(find.canReplace, isFalse);
      expect(find.replaceAll(), 0);
      find.next();
      expect(find.currentIndex, 1);
      expect(find.currentBodyMatch!.textRange.start, 12);
      find.next();
      expect(find.currentIndex, 0);
      find.next(backwards: true);
      expect(find.currentIndex, 1);
      expect(document.value, before);
      expect(document.canUndo, isFalse);
    },
  );

  testWidgets('scope switching preserves source replacement semantics', (
    tester,
  ) async {
    final document = IanvsMarkdownController(text: '[label](secret) label');
    final find = DocumentFindController(
      document: document,
      scope: DocumentFindScope.body,
      query: 'secret',
    );
    addTearDown(() {
      find.dispose();
      document.dispose();
    });
    await tester.pump(const Duration(milliseconds: 160));
    expect(find.count, 0);
    find.query.text = 'label';
    find.query.text = 'secret';
    await tester.pump(const Duration(milliseconds: 160));
    expect(find.count, 0);
    find.setScope(DocumentFindScope.source);
    expect(find.count, 1);
    expect(find.canReplace, isTrue);
    find.replacement.text = 'destination';
    expect(find.replaceCurrent(), isTrue);
    expect(document.text, '[label](destination) label');
  });

  testWidgets('edits and composition invalidate pending body search', (
    tester,
  ) async {
    final document = IanvsMarkdownController(text: 'old text');
    final find = DocumentFindController(
      document: document,
      scope: DocumentFindScope.body,
      query: 'old',
    );
    addTearDown(() {
      find.dispose();
      document.dispose();
    });
    document.text = 'new text';
    await tester.pump(const Duration(milliseconds: 160));
    expect(find.count, 0);
    expect(document.sourceNavigation.value, isNull);
    find.query.value = const TextEditingValue(
      text: 'new',
      composing: TextRange(start: 0, end: 3),
    );
    await tester.pump(const Duration(milliseconds: 160));
    expect(find.canNavigate, isFalse);
    expect(find.count, 0);
    find.query.value = const TextEditingValue(text: 'new');
    await tester.pump(const Duration(milliseconds: 160));
    expect(find.count, 1);
    expect(find.currentBodyMatch!.text, 'new text');
    document.commitHistoryGroup();
  });
}
