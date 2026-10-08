import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void edit(IanvsMarkdownController controller, String text) {
  controller.commitHistoryGroup();
  controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
  controller.commitHistoryGroup();
}

void main() {
  test('entry cap retains the newest contiguous undo and redo states', () {
    final controller = IanvsMarkdownController(
      text: 'A',
      historyPolicy: const IanvsMarkdownHistoryPolicy(maxEntries: 3),
    );
    addTearDown(controller.dispose);
    final notifications = <(bool, bool)>[];
    controller.historyListenable.addListener(() {
      final state = controller.historyListenable.value;
      notifications.add((state.canUndo, state.canRedo));
    });
    for (final text in ['B', 'C', 'D']) {
      edit(controller, text);
    }
    expect(controller.retainedHistoryEntries, 3);
    expect(controller.retainedHistoryTextBytes, 6);
    controller.undo();
    expect(controller.text, 'C');
    controller.undo();
    expect(controller.text, 'B');
    expect(controller.canUndo, isFalse);
    controller.undo();
    expect(controller.text, 'B');
    controller.redo();
    controller.redo();
    expect(controller.text, 'D');
    expect(controller.selection.extentOffset, 1);
    expect(notifications.last, (true, false));
    expect(controller.retainedHistoryTextBytes, 6);
  });

  test('byte cap counts UTF-16 units and includes the exact boundary', () {
    final controller = IanvsMarkdownController(
      text: '中',
      historyPolicy: const IanvsMarkdownHistoryPolicy(maxTextBytes: 14),
    );
    addTearDown(controller.dispose);
    edit(controller, '😀');
    edit(controller, 'ab😀');
    expect(controller.retainedHistoryEntries, 3);
    expect(controller.retainedHistoryTextBytes, 14); // 2 + 4 + 8.
    edit(controller, '🌟a');
    expect(controller.retainedHistoryEntries, 2);
    expect(controller.retainedHistoryTextBytes, 14); // 8 + 6.
    controller.undo();
    expect(controller.text, 'ab😀');
    expect(controller.canUndo, isFalse);
  });

  test(
    'oversized current state is kept whole and old states are discarded',
    () {
      final controller = IanvsMarkdownController(
        text: 'ok',
        historyPolicy: const IanvsMarkdownHistoryPolicy(maxTextBytes: 8),
      );
      addTearDown(controller.dispose);
      edit(controller, 'oversized 😀');
      expect(controller.text, 'oversized 😀');
      expect(controller.retainedHistoryEntries, 1);
      expect(controller.retainedHistoryTextBytes, controller.text.length * 2);
      expect(controller.canUndo, isFalse);
      expect(controller.isDirty, isTrue);
      edit(controller, 'ok');
      expect(controller.retainedHistoryEntries, 1);
      expect(controller.retainedHistoryTextBytes, 4);
      expect(controller.canUndo, isFalse);
      expect(controller.isDirty, isFalse);
    },
  );

  test('oversized initial content is never truncated', () {
    final controller = IanvsMarkdownController(
      text: '中文😀',
      historyPolicy: const IanvsMarkdownHistoryPolicy(maxTextBytes: 1),
    );
    addTearDown(controller.dispose);
    expect(controller.text, '中文😀');
    expect(controller.retainedHistoryTextBytes, 8);
    expect(controller.retainedHistoryEntries, 1);
    expect(controller.isDirty, isFalse);
    expect(controller.canUndo, isFalse);
  });

  for (final policy in [
    const IanvsMarkdownHistoryPolicy(maxEntries: 1),
    const IanvsMarkdownHistoryPolicy(maxTextBytes: 0),
  ]) {
    test(
      'single-current policy $policy disables undo without changing saves',
      () {
        final controller = IanvsMarkdownController(
          text: 'saved',
          historyPolicy: policy,
        );
        addTearDown(controller.dispose);
        edit(controller, 'changed');
        expect(controller.canUndo, isFalse);
        expect(controller.retainedHistoryEntries, 1);
        expect(controller.isDirty, isTrue);
        controller.markSaved();
        expect(controller.isDirty, isFalse);
        edit(controller, '');
        expect(controller.retainedHistoryTextBytes, 0);
        expect(controller.canUndo, isFalse);
      },
    );
  }

  test('evicting the saved state does not move the save baseline', () {
    final controller = IanvsMarkdownController(
      text: 'A',
      historyPolicy: const IanvsMarkdownHistoryPolicy(maxEntries: 2),
    );
    addTearDown(controller.dispose);
    edit(controller, 'B');
    edit(controller, 'C');
    controller.undo();
    expect(controller.text, 'B');
    expect(controller.isDirty, isTrue);
    controller.markSaved(savedText: 'A');
    expect(controller.isDirty, isTrue);
    edit(controller, 'A');
    expect(controller.isDirty, isFalse);
    controller.undo();
    expect(controller.text, 'B');
    expect(controller.isDirty, isTrue);
    controller.redo();
    expect(controller.isDirty, isFalse);
  });

  test('editing after undo frees the redo branch before applying limits', () {
    final controller = IanvsMarkdownController(
      text: 'a',
      historyPolicy: const IanvsMarkdownHistoryPolicy(maxTextBytes: 20),
    );
    addTearDown(controller.dispose);
    edit(controller, 'bb');
    edit(controller, 'cccc');
    controller.undo();
    edit(controller, 'ddd');
    expect(controller.canRedo, isFalse);
    expect(controller.retainedHistoryTextBytes, 12); // a + bb + ddd.
    expect(controller.retainedHistoryEntries, 3);
    controller.undo();
    expect(controller.text, 'bb');
    controller.undo();
    expect(controller.text, 'a');
  });

  test('coalesced typing updates capacity and preserves the undo group', () {
    final controller = IanvsMarkdownController(
      text: 'a',
      historyCoalescingDuration: const Duration(minutes: 1),
      historyPolicy: const IanvsMarkdownHistoryPolicy(maxTextBytes: 12),
    );
    addTearDown(controller.dispose);
    for (final text in ['ab', 'abc', 'abcd']) {
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    expect(controller.retainedHistoryEntries, 2);
    expect(controller.retainedHistoryTextBytes, 10);
    controller.undo();
    expect(controller.text, 'a');
    controller.redo();
    expect(controller.text, 'abcd');
  });

  test(
    'selection and composing-only updates do not consume history capacity',
    () {
      final controller = IanvsMarkdownController(
        text: 'alpha',
        historyPolicy: const IanvsMarkdownHistoryPolicy(maxEntries: 2),
      );
      addTearDown(controller.dispose);
      edit(controller, 'beta');
      controller.selection = const TextSelection.collapsed(offset: 2);
      controller.value = controller.value.copyWith(
        composing: const TextRange(start: 0, end: 2),
      );
      expect(controller.retainedHistoryEntries, 2);
      expect(controller.retainedHistoryTextBytes, 18);
      expect(controller.value.composing, const TextRange(start: 0, end: 2));
      controller.undo();
      controller.redo();
      expect(controller.selection.extentOffset, 2);
      expect(controller.value.composing, TextRange.empty);
    },
  );

  test('bounded history preserves existing IME grouping until eviction', () {
    final bounded = IanvsMarkdownController(
      historyPolicy: const IanvsMarkdownHistoryPolicy(maxEntries: 3),
    );
    final legacy = IanvsMarkdownController(historyPolicy: null);
    addTearDown(bounded.dispose);
    addTearDown(legacy.dispose);
    for (final text in ['n', 'ni', '你']) {
      final value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
        composing: TextRange(start: 0, end: text.length),
      );
      bounded.value = value;
      legacy.value = value;
      expect(bounded.value, value);
    }
    bounded.clearComposing();
    legacy.clearComposing();
    while (legacy.canUndo) {
      legacy.undo();
      bounded.undo();
      expect(bounded.value, legacy.value);
    }
    expect(bounded.canUndo, isFalse);
    while (legacy.canRedo) {
      legacy.redo();
      bounded.redo();
      expect(bounded.value, legacy.value);
    }
  });

  test(
    'clearHistory resets accounting while preserving current dirty state',
    () {
      final controller = IanvsMarkdownController(text: 'saved');
      addTearDown(controller.dispose);
      edit(controller, 'first');
      edit(controller, 'next');
      controller.undo();
      controller.clearHistory();
      expect(controller.text, 'first');
      expect(controller.isDirty, isTrue);
      expect(controller.retainedHistoryEntries, 1);
      expect(controller.retainedHistoryTextBytes, 10);
      expect(controller.canUndo, isFalse);
      expect(controller.canRedo, isFalse);
    },
  );

  test('default policy bounds long editing and null keeps legacy history', () {
    final bounded = IanvsMarkdownController();
    final legacy = IanvsMarkdownController(historyPolicy: null);
    addTearDown(bounded.dispose);
    addTearDown(legacy.dispose);
    for (var i = 0; i < 1000; i++) {
      edit(bounded, 'edit $i');
      edit(legacy, 'edit $i');
    }
    expect(bounded.retainedHistoryEntries, 200);
    expect(legacy.retainedHistoryEntries, 1001);
    var undone = 0;
    while (bounded.canUndo) {
      bounded.undo();
      undone++;
    }
    expect(undone, 199);
    expect(bounded.text, 'edit 800');
    expect(bounded.isDirty, isTrue);
  });

  test('default byte capacity limits large replacement snapshots', () {
    final controller = IanvsMarkdownController();
    addTearDown(controller.dispose);
    final megabyte = ('a' * 127 + '\n') * 8192;
    for (var i = 0; i < 24; i++) {
      edit(controller, '$i$megabyte');
    }
    expect(controller.text, '23$megabyte');
    expect(controller.retainedHistoryEntries, 15);
    expect(
      controller.retainedHistoryTextBytes,
      lessThanOrEqualTo(32 * 1024 * 1024),
    );
    var undone = 0;
    while (controller.canUndo) {
      controller.undo();
      undone++;
    }
    expect(undone, 14);
    expect(controller.text, '9$megabyte');
  });
}
