import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_markdown/src/editor/editor_controller.dart'
    show ianvsMarkdownInlineSourceRangeAt;

void main() {
  test('controller owns mode, dirty state, and document-wide history', () {
    final controller = IanvsMarkdownController(text: 'Alpha');
    addTearDown(controller.dispose);

    expect(controller.mode, IanvsMarkdownEditorMode.livePreview);
    expect(controller.isDirty, isFalse);

    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    controller.toggleInline('**');
    expect(controller.text, '**Alpha**');
    expect(controller.isDirty, isTrue);
    expect(controller.canUndo, isTrue);

    controller.undo();
    expect(controller.text, 'Alpha');
    expect(controller.canRedo, isTrue);

    controller.redo();
    expect(controller.text, '**Alpha**');
    controller.markSaved();
    expect(controller.isDirty, isFalse);

    controller.mode = IanvsMarkdownEditorMode.preview;
    expect(controller.mode, IanvsMarkdownEditorMode.preview);
  });

  test('formatting commands preserve and update selections', () {
    final controller = IanvsMarkdownController(text: 'hello');
    addTearDown(controller.dispose);

    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    controller.insertLink(destination: 'guide.md');
    expect(controller.text, '[hello](guide.md)');
    expect(controller.selection.textInside(controller.text), 'hello');

    controller
      ..value = const TextEditingValue(
        text: 'one\ntwo',
        selection: TextSelection(baseOffset: 0, extentOffset: 7),
      )
      ..toggleLinePrefix('- ');
    expect(controller.text, '- one\n- two');

    controller.toggleLinePrefix('- ');
    expect(controller.text, 'one\ntwo');
  });

  test(
    'collapsed inline commands wrap the current word and preserve the caret',
    () {
      final controller = IanvsMarkdownController(text: 'PAIR_TARGET');
      addTearDown(controller.dispose);

      controller.selection = const TextSelection.collapsed(offset: 4);
      controller.toggleInline('**');
      expect(controller.text, '**PAIR_TARGET**');
      expect(controller.selection, const TextSelection.collapsed(offset: 6));

      controller.toggleInline('**');
      expect(controller.text, 'PAIR_TARGET');
      expect(controller.selection, const TextSelection.collapsed(offset: 4));

      controller.toggleInline('*');
      expect(controller.text, '*PAIR_TARGET*');
      expect(controller.selection, const TextSelection.collapsed(offset: 5));

      controller.value = const TextEditingValue(
        text: 'PAIR_TARGET',
        selection: TextSelection.collapsed(offset: 0),
      );
      controller.toggleInline('**');
      expect(controller.text, '****PAIR_TARGET');
      expect(controller.selection, const TextSelection.collapsed(offset: 2));
    },
  );

  test('link insertion follows selection-aware editing behavior', () {
    final controller = IanvsMarkdownController(text: 'hello');
    addTearDown(controller.dispose);

    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    controller.insertLink();
    expect(controller.text, '[hello]()');
    expect(controller.selection, const TextSelection.collapsed(offset: 8));

    controller
      ..value = const TextEditingValue(
        text: 'hello',
        selection: TextSelection.collapsed(offset: 5),
      )
      ..insertLink();
    expect(controller.text, 'hello[]()');
    expect(controller.selection, const TextSelection.collapsed(offset: 6));

    controller
      ..value = const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      )
      ..insertLink(fallbackLabel: 'link');
    expect(controller.text, '[link]()');
    expect(controller.selection, const TextSelection.collapsed(offset: 7));
  });

  test('moving the caret ends the active undo group', () {
    final controller = IanvsMarkdownController(
      text: 'alpha',
      historyCoalescingDuration: const Duration(minutes: 1),
    );
    addTearDown(controller.dispose);

    controller.value = const TextEditingValue(
      text: 'Xalpha',
      selection: TextSelection.collapsed(offset: 1),
    );
    controller.selection = const TextSelection.collapsed(offset: 6);
    controller.value = const TextEditingValue(
      text: 'XalphaY',
      selection: TextSelection.collapsed(offset: 7),
    );

    controller.undo();
    expect(controller.text, 'Xalpha');
    expect(controller.selection, const TextSelection.collapsed(offset: 6));

    controller.undo();
    expect(controller.text, 'alpha');
  });

  test('indentation preserves a collapsed caret', () {
    final controller = IanvsMarkdownController(text: '- first\n- second');
    addTearDown(controller.dispose);
    controller.selection = const TextSelection.collapsed(offset: 16);

    controller.indentSelection();
    expect(controller.text, '- first\n    - second');
    expect(controller.selection, const TextSelection.collapsed(offset: 20));

    controller.indentSelection(outdent: true);
    expect(controller.text, '- first\n- second');
    expect(controller.selection, const TextSelection.collapsed(offset: 16));
  });

  test('indentation starts after quote containers and uses four spaces', () {
    final controller = IanvsMarkdownController(text: '> - item');
    addTearDown(controller.dispose);
    controller.selection = const TextSelection.collapsed(offset: 8);

    controller.indentSelection();
    expect(controller.text, '>     - item');
    expect(controller.selection, const TextSelection.collapsed(offset: 12));

    controller.indentSelection(outdent: true);
    expect(controller.text, '> - item');
    expect(controller.selection, const TextSelection.collapsed(offset: 8));

    controller.value = const TextEditingValue(
      text: '> > quote',
      selection: TextSelection.collapsed(offset: 9),
    );
    controller.indentSelection();
    expect(controller.text, '> >     quote');
    expect(controller.selection, const TextSelection.collapsed(offset: 13));
  });

  test('indentation renumbers affected ordered-list levels', () {
    final controller = IanvsMarkdownController(text: '9. item')
      ..selection = const TextSelection.collapsed(offset: 7);
    addTearDown(controller.dispose);

    controller.indentSelection();
    expect(controller.text, '    1. item');
    expect(controller.selection, const TextSelection.collapsed(offset: 11));

    controller.value = const TextEditingValue(
      text: '> 9. item',
      selection: TextSelection.collapsed(offset: 9),
    );
    controller.indentSelection();
    expect(controller.text, '>     1. item');
    expect(controller.selection, const TextSelection.collapsed(offset: 13));

    controller.value = const TextEditingValue(
      text: '9) item',
      selection: TextSelection.collapsed(offset: 7),
    );
    controller.indentSelection();
    expect(controller.text, '    1) item');

    controller.value = const TextEditingValue(
      text: '8. first\n9. second',
      selection: TextSelection(baseOffset: 0, extentOffset: 18),
    );
    controller.indentSelection();
    expect(controller.text, '    1. first\n    2. second');
    expect(
      controller.selection,
      const TextSelection(baseOffset: 4, extentOffset: 26),
    );

    controller.value = const TextEditingValue(
      text: '1. A\n2. B\n3. C',
      selection: TextSelection.collapsed(offset: 9),
    );
    controller.indentSelection();
    expect(controller.text, '1. A\n    1. B\n2. C');
    expect(controller.selection, const TextSelection.collapsed(offset: 13));

    controller.indentSelection(outdent: true);
    expect(controller.text, '1. A\n2. B\n3. C');
    expect(controller.selection, const TextSelection.collapsed(offset: 9));

    controller.value = const TextEditingValue(
      text: '8. A\n9. B\n10. C',
      selection: TextSelection.collapsed(offset: 9),
    );
    controller.indentSelection();
    expect(controller.text, '8. A\n    1. B\n9. C');
    expect(controller.selection, const TextSelection.collapsed(offset: 13));
  });

  test('ordered numbering continues across period and parenthesis markers', () {
    const source = '1. A\n2. B\n4. C\n1) D\n2) E';
    final formatter = IanvsMarkdownEditingFormatter();

    final normalized = formatter.renumberOrderedLists(
      const TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: source.length),
      ),
      touchedLineStarts: const {0},
    );

    expect(normalized.text, '1. A\n2. B\n3. C\n4) D\n5) E');
    expect(
      normalized.selection,
      const TextSelection.collapsed(offset: source.length),
    );
  });

  test('indentation never renumbers ordered-looking fenced code', () {
    final controller = IanvsMarkdownController(text: '```text\n9. code\n```')
      ..selection = const TextSelection.collapsed(offset: 15);
    addTearDown(controller.dispose);

    controller.indentSelection();
    expect(controller.text, '```text\n    9. code\n```');
    expect(controller.selection, const TextSelection.collapsed(offset: 19));
  });

  test('code indentation follows Obsidian four-space behavior', () {
    final controller = IanvsMarkdownController(text: '```dart\nalpha\n```');
    addTearDown(controller.dispose);
    controller.selection = const TextSelection.collapsed(offset: 13);

    expect(controller.canIndentSelection, isTrue);
    controller.indentSelection();
    expect(controller.text, '```dart\n    alpha\n```');
    expect(controller.selection, const TextSelection.collapsed(offset: 17));

    controller.value = const TextEditingValue(
      text: '```dart\n    alpha\n```',
      selection: TextSelection.collapsed(offset: 17),
    );
    controller.indentSelection(outdent: true);
    expect(controller.text, '```dart\nalpha\n```');
    expect(controller.selection, const TextSelection.collapsed(offset: 13));

    controller.value = const TextEditingValue(
      text: '```dart\nalpha\n```',
      selection: TextSelection(baseOffset: 8, extentOffset: 13),
    );
    controller.indentSelection();
    expect(controller.text, '```dart\n    alpha\n```');
    expect(
      controller.selection,
      const TextSelection(baseOffset: 12, extentOffset: 17),
    );
  });

  test('only Markdown structures consume Tab at a collapsed caret', () {
    final controller = IanvsMarkdownController(
      text: 'Plain\n- Bullet\n2. Ordered\n> Quote',
    );
    addTearDown(controller.dispose);

    controller.selection = const TextSelection.collapsed(offset: 3);
    expect(controller.canIndentSelection, isFalse);

    controller.selection = const TextSelection.collapsed(offset: 10);
    expect(controller.canIndentSelection, isTrue);

    controller.selection = const TextSelection.collapsed(offset: 20);
    expect(controller.canIndentSelection, isTrue);

    controller.selection = const TextSelection.collapsed(offset: 31);
    expect(controller.canIndentSelection, isTrue);

    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    expect(controller.canIndentSelection, isTrue);
  });

  test('delete selected lines preserves the next line column', () {
    const source = 'alpha\nbeta\ngamma';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);

    controller.selection = const TextSelection.collapsed(offset: 8);
    expect(controller.deleteSelectedLines(), isTrue);
    expect(controller.text, 'alpha\ngamma');
    expect(controller.selection, const TextSelection.collapsed(offset: 8));
    expect(controller.isDirty, isTrue);

    controller.undo();
    expect(controller.text, source);
    expect(controller.selection, const TextSelection.collapsed(offset: 8));

    controller.selection = const TextSelection.collapsed(offset: 2);
    expect(controller.deleteSelectedLines(), isTrue);
    expect(controller.text, 'beta\ngamma');
    expect(controller.selection, const TextSelection.collapsed(offset: 2));

    controller.undo();
    controller.selection = const TextSelection.collapsed(offset: 13);
    expect(controller.deleteSelectedLines(), isTrue);
    expect(controller.text, 'alpha\nbeta');
    expect(controller.selection, const TextSelection.collapsed(offset: 10));
  });

  test('delete selected lines expands selections to physical lines', () {
    const source = 'one\ntwo\nthree\nfour';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);

    controller.selection = const TextSelection(baseOffset: 4, extentOffset: 14);
    expect(controller.deleteSelectedLines(), isTrue);
    expect(controller.text, 'one\nfour');
    expect(controller.selection, const TextSelection.collapsed(offset: 4));

    controller.undo();
    controller.selection = const TextSelection.collapsed(offset: 4);
    expect(controller.deleteSelectedLines(), isTrue);
    expect(controller.text, 'one\nthree\nfour');
    expect(controller.selection, const TextSelection.collapsed(offset: 4));
  });

  test('delete selected lines removes blank and Markdown structure lines', () {
    final controller = IanvsMarkdownController(
      text: 'alpha\n\n- item\n> quote\nlast',
    );
    addTearDown(controller.dispose);

    controller.selection = const TextSelection.collapsed(offset: 6);
    expect(controller.deleteSelectedLines(), isTrue);
    expect(controller.text, 'alpha\n- item\n> quote\nlast');
    expect(controller.selection, const TextSelection.collapsed(offset: 6));

    expect(controller.deleteSelectedLines(), isTrue);
    expect(controller.text, 'alpha\n> quote\nlast');
    expect(controller.selection, const TextSelection.collapsed(offset: 6));
  });

  test('delete selected lines renumbers only the affected ordered levels', () {
    final controller = IanvsMarkdownController(text: '1. A\n2. B\n3. C')
      ..selection = const TextSelection.collapsed(offset: 9);
    addTearDown(controller.dispose);

    expect(controller.deleteSelectedLines(), isTrue);
    expect(controller.text, '1. A\n2. C');
    expect(controller.selection, const TextSelection.collapsed(offset: 9));

    controller.undo();
    controller.value = const TextEditingValue(
      text: '1. A\n    1. B\n    2. C\n2. D',
      selection: TextSelection.collapsed(offset: 13),
    );
    expect(controller.deleteSelectedLines(), isTrue);
    expect(controller.text, '1. A\n    1. C\n2. D');
    expect(controller.selection, const TextSelection.collapsed(offset: 13));

    controller.value = const TextEditingValue(
      text: '8. A\n9. B\n10. C',
      selection: TextSelection.collapsed(offset: 4),
    );
    expect(controller.deleteSelectedLines(), isTrue);
    expect(controller.text, '8. B\n9. C');
    expect(controller.selection, const TextSelection.collapsed(offset: 4));

    controller.value = const TextEditingValue(
      text: '1. A\n2. B\n\n9. separate',
      selection: TextSelection.collapsed(offset: 4),
    );
    expect(controller.deleteSelectedLines(), isTrue);
    expect(controller.text, '1. B\n\n9. separate');

    controller.value = const TextEditingValue(
      text: 'intro\n\n1. A\n2. B',
      selection: TextSelection.collapsed(offset: 11),
    );
    expect(controller.deleteSelectedLines(), isTrue);
    expect(controller.text, 'intro\n\n1. B');
  });

  test('Markdown punctuation is deleted as its own word segment', () {
    final controller = IanvsMarkdownController(text: '**bold**');
    addTearDown(controller.dispose);
    controller.selection = const TextSelection.collapsed(offset: 8);

    expect(controller.deleteMarkdownPunctuationSegment(forward: false), isTrue);
    expect(controller.text, '**bold');
    expect(controller.selection, const TextSelection.collapsed(offset: 6));
    expect(
      controller.deleteMarkdownPunctuationSegment(forward: false),
      isFalse,
    );

    controller.value = const TextEditingValue(
      text: '[label](url)',
      selection: TextSelection.collapsed(offset: 0),
    );
    expect(controller.deleteMarkdownPunctuationSegment(forward: true), isTrue);
    expect(controller.text, 'label](url)');
    expect(controller.selection, const TextSelection.collapsed(offset: 0));
  });

  test(
    'caret movement treats Markdown punctuation as its own word segment',
    () {
      final controller = IanvsMarkdownController(text: '**bold**');
      addTearDown(controller.dispose);
      controller.selection = const TextSelection.collapsed(offset: 8);

      expect(
        controller.moveAcrossMarkdownPunctuation(
          forward: false,
          extendSelection: false,
        ),
        isTrue,
      );
      expect(controller.selection, const TextSelection.collapsed(offset: 6));
      expect(
        controller.moveAcrossMarkdownPunctuation(
          forward: false,
          extendSelection: false,
        ),
        isFalse,
      );

      controller.selection = const TextSelection.collapsed(offset: 0);
      expect(
        controller.moveAcrossMarkdownPunctuation(
          forward: true,
          extendSelection: true,
        ),
        isTrue,
      );
      expect(
        controller.selection,
        const TextSelection(
          baseOffset: 0,
          extentOffset: 2,
          isDirectional: true,
        ),
      );
      expect(controller.selection.textInside(controller.text), '**');
    },
  );

  group('IanvsMarkdownEditingFormatter', () {
    final formatter = IanvsMarkdownEditingFormatter();

    test('auto-completes Markdown pairs and skips their existing closers', () {
      for (final pair in <(String, String)>[
        ('[', ']'),
        ('(', ')'),
        ('{', '}'),
        ('`', '`'),
        ('*', '*'),
        ('_', '_'),
        ('"', '"'),
        ("'", "'"),
      ]) {
        final opened = _typeCharacter(formatter, '', 0, pair.$1);
        expect(opened.text, '${pair.$1}${pair.$2}');
        expect(opened.selection, const TextSelection.collapsed(offset: 1));

        final closed = _typeCharacter(
          formatter,
          opened.text,
          opened.selection.extentOffset,
          pair.$2,
        );
        expect(closed.text, opened.text);
        expect(closed.selection, const TextSelection.collapsed(offset: 2));
      }
    });

    test('auto-completes brackets only before whitespace or line end', () {
      for (final pair in <(String, String)>[
        ('[', ']'),
        ('(', ')'),
        ('{', '}'),
      ]) {
        final atLineEnd = _typeCharacter(formatter, 'word', 4, pair.$1);
        expect(atLineEnd.text, 'word${pair.$1}${pair.$2}');
        expect(atLineEnd.selection, const TextSelection.collapsed(offset: 5));

        expect(
          _typeCharacter(formatter, 'word', 0, pair.$1).text,
          '${pair.$1}word',
        );
        expect(
          _typeCharacter(formatter, 'word', 2, pair.$1).text,
          'wo${pair.$1}rd',
        );
        expect(
          _typeCharacter(formatter, 'a b', 1, pair.$1).text,
          'a${pair.$1}${pair.$2} b',
        );
        expect(
          _typeCharacter(formatter, 'a,b', 1, pair.$1).text,
          'a${pair.$1},b',
        );
      }
    });

    test('auto-completes brackets before Markdown close-before characters', () {
      for (final pair in <(String, String)>[
        ('[', ']'),
        ('(', ')'),
        ('{', '}'),
      ]) {
        final outer = _typeCharacter(formatter, '', 0, pair.$1);
        final nested = _typeCharacter(formatter, outer.text, 1, pair.$1);
        expect(nested.text, '${pair.$1}${pair.$1}${pair.$2}${pair.$2}');
        expect(nested.selection, const TextSelection.collapsed(offset: 2));
      }

      for (final next in <String>[')', ']', '}', "'", '"', ':', ';', '>']) {
        expect(
          _typeCharacter(formatter, 'a${next}b', 1, '(').text,
          'a()${next}b',
        );
      }
    });

    test('does not auto-complete quote characters inside words', () {
      expect(_typeCharacter(formatter, 'don', 3, "'").text, "don'");
      expect(_typeCharacter(formatter, 'word', 4, '"').text, 'word"');
      expect(_typeCharacter(formatter, '词', 1, '"').text, '词"');
    });

    test('auto-completes emphasis only at Markdown boundaries', () {
      for (final marker in <String>['*', '_']) {
        final atLineEnd = _typeCharacter(formatter, '', 0, marker);
        expect(atLineEnd.text, '$marker$marker');
        expect(atLineEnd.selection, const TextSelection.collapsed(offset: 1));

        final afterSpace = _typeCharacter(formatter, 'word ', 5, marker);
        expect(afterSpace.text, 'word $marker$marker');
        expect(afterSpace.selection, const TextSelection.collapsed(offset: 6));

        expect(
          _typeCharacter(formatter, 'word', 4, marker).text,
          'word$marker',
        );
        expect(
          _typeCharacter(formatter, 'word', 0, marker).text,
          '${marker}word',
        );
        expect(
          _typeCharacter(formatter, 'word', 2, marker).text,
          'wo${marker}rd',
        );
      }
    });

    test('repeated emphasis markers grow without an extra closing mate', () {
      TextEditingValue typeSequence(String characters) {
        var value = const TextEditingValue(
          selection: TextSelection.collapsed(offset: 0),
        );
        for (final character in characters.split('')) {
          value = _typeCharacter(
            formatter,
            value.text,
            value.selection.extentOffset,
            character,
          );
        }
        return value;
      }

      expect(
        typeSequence('*x*'),
        const TextEditingValue(
          text: '*x*',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      expect(
        typeSequence('**x**'),
        const TextEditingValue(
          text: '**x**',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      expect(
        typeSequence('__x__'),
        const TextEditingValue(
          text: '__x__',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      expect(
        typeSequence('***x***'),
        const TextEditingValue(
          text: '***x***',
          selection: TextSelection.collapsed(offset: 7),
        ),
      );
    });

    test('word-adjacent backticks stay single but still grow into a fence', () {
      expect(_typeCharacter(formatter, 'word', 4, '`').text, 'word`');
      expect(_typeCharacter(formatter, 'word', 0, '`').text, '`word');
      expect(_typeCharacter(formatter, '42', 2, '`').text, '42`');
      expect(_typeCharacter(formatter, '词', 1, '`').text, '词`');

      final afterSpace = _typeCharacter(formatter, 'word ', 5, '`');
      expect(afterSpace.text, 'word ``');
      expect(afterSpace.selection, const TextSelection.collapsed(offset: 6));

      final first = _typeCharacter(formatter, 'abc', 3, '`');
      expect(first.text, 'abc`');
      final second = _typeCharacter(
        formatter,
        first.text,
        first.selection.extentOffset,
        '`',
      );
      expect(second.text, 'abc``');
      expect(
        _typeCharacter(
          formatter,
          second.text,
          second.selection.extentOffset,
          '`',
        ),
        const TextEditingValue(
          text: 'abc```\n```',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
    });

    test('wraps selected text in a typed Markdown pair', () {
      const oldValue = TextEditingValue(
        text: 'word',
        selection: TextSelection(baseOffset: 0, extentOffset: 4),
      );
      const nativeReplacement = TextEditingValue(
        text: '[',
        selection: TextSelection.collapsed(offset: 1),
      );

      expect(
        formatter.formatEditUpdate(oldValue, nativeReplacement),
        const TextEditingValue(
          text: '[word]',
          selection: TextSelection(baseOffset: 1, extentOffset: 5),
        ),
      );
    });

    test('repeated Markdown-only characters grow selected delimiters', () {
      TextEditingValue surround(TextEditingValue oldValue, String character) {
        final start = oldValue.selection.start;
        final end = oldValue.selection.end;
        final nativeReplacement = TextEditingValue(
          text: oldValue.text.replaceRange(start, end, character),
          selection: TextSelection.collapsed(offset: start + 1),
        );
        return formatter.formatEditUpdate(oldValue, nativeReplacement);
      }

      for (final marker in <String>['*', '_', '=', '~', r'$', '%']) {
        var value = const TextEditingValue(
          text: 'word',
          selection: TextSelection(baseOffset: 0, extentOffset: 4),
        );
        value = surround(value, marker);
        expect(value.text, '${marker}word$marker');
        expect(
          value.selection,
          const TextSelection(baseOffset: 1, extentOffset: 5),
        );

        value = surround(value, marker);
        expect(value.text, '$marker${marker}word$marker$marker');
        expect(
          value.selection,
          const TextSelection(baseOffset: 2, extentOffset: 6),
        );
      }

      for (final marker in <String>['=', '~', r'$', '%']) {
        expect(_typeCharacter(formatter, '', 0, marker).text, marker);
      }
    });

    test('Backspace removes untouched Markdown pairs one nesting level', () {
      const oldValue = TextEditingValue(
        text: '()',
        selection: TextSelection.collapsed(offset: 1),
      );
      const nativeBackspace = TextEditingValue(
        text: ')',
        selection: TextSelection.collapsed(offset: 0),
      );

      expect(
        formatter.formatEditUpdate(oldValue, nativeBackspace),
        const TextEditingValue(selection: TextSelection.collapsed(offset: 0)),
      );

      const nested = TextEditingValue(
        text: '[[]]',
        selection: TextSelection.collapsed(offset: 2),
      );
      final outer = formatter.formatEditUpdate(
        nested,
        const TextEditingValue(
          text: '[]]',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      expect(
        outer,
        const TextEditingValue(
          text: '[]',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      expect(
        formatter.formatEditUpdate(
          outer,
          const TextEditingValue(
            text: ']',
            selection: TextSelection.collapsed(offset: 0),
          ),
        ),
        const TextEditingValue(selection: TextSelection.collapsed(offset: 0)),
      );

      for (final marker in <String>['*', '_']) {
        final opened = _typeCharacter(formatter, '', 0, marker);
        final nativeMarkerBackspace = TextEditingValue(
          text: marker,
          selection: const TextSelection.collapsed(offset: 0),
        );
        expect(
          formatter.formatEditUpdate(opened, nativeMarkerBackspace),
          const TextEditingValue(selection: TextSelection.collapsed(offset: 0)),
        );
      }
    });

    test('Backspace steps down ATX levels before leaving heading syntax', () {
      const h2 = TextEditingValue(
        text: '## H2 ATX',
        selection: TextSelection.collapsed(offset: 3),
      );
      final h1 = formatter.formatEditUpdate(
        h2,
        const TextEditingValue(
          text: '##H2 ATX',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      expect(
        h1,
        const TextEditingValue(
          text: '# H2 ATX',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );

      expect(
        formatter.formatEditUpdate(
          h1,
          const TextEditingValue(
            text: '#H2 ATX',
            selection: TextSelection.collapsed(offset: 1),
          ),
        ),
        const TextEditingValue(
          text: 'H2 ATX',
          selection: TextSelection.collapsed(offset: 0),
        ),
      );
    });

    test('Backspace retreats code indentation to the previous tab stop', () {
      const fourSpaces = TextEditingValue(
        text: '```dart\n    alpha\n```',
        selection: TextSelection.collapsed(offset: 12),
      );
      const nativeFourSpaceBackspace = TextEditingValue(
        text: '```dart\n   alpha\n```',
        selection: TextSelection.collapsed(offset: 11),
      );
      expect(
        formatter.formatEditUpdate(fourSpaces, nativeFourSpaceBackspace),
        const TextEditingValue(
          text: '```dart\nalpha\n```',
          selection: TextSelection.collapsed(offset: 8),
        ),
      );

      const sixSpaces = TextEditingValue(
        text: '```dart\n      beta\n```',
        selection: TextSelection.collapsed(offset: 14),
      );
      const nativeSixSpaceBackspace = TextEditingValue(
        text: '```dart\n     beta\n```',
        selection: TextSelection.collapsed(offset: 13),
      );
      expect(
        formatter.formatEditUpdate(sixSpaces, nativeSixSpaceBackspace),
        const TextEditingValue(
          text: '```dart\n    beta\n```',
          selection: TextSelection.collapsed(offset: 12),
        ),
      );
    });

    test(
      'Backspace before a list marker outdents to the previous tab stop',
      () {
        const nestedBullet = TextEditingValue(
          text: '- parent\n  - child',
          selection: TextSelection.collapsed(offset: 11),
        );
        const nativeBulletBackspace = TextEditingValue(
          text: '- parent\n - child',
          selection: TextSelection.collapsed(offset: 10),
        );
        expect(
          formatter.formatEditUpdate(nestedBullet, nativeBulletBackspace),
          const TextEditingValue(
            text: '- parent\n- child',
            selection: TextSelection.collapsed(offset: 9),
          ),
        );

        const nestedOrdered = TextEditingValue(
          text: '1. parent\n  12. child',
          selection: TextSelection.collapsed(offset: 12),
        );
        const nativeOrderedBackspace = TextEditingValue(
          text: '1. parent\n 12. child',
          selection: TextSelection.collapsed(offset: 11),
        );
        expect(
          formatter.formatEditUpdate(nestedOrdered, nativeOrderedBackspace),
          const TextEditingValue(
            text: '1. parent\n2. child',
            selection: TextSelection.collapsed(offset: 10),
          ),
        );
      },
    );

    test('code indentation Backspace leaves unrelated deletions native', () {
      const outsideCode = TextEditingValue(
        text: '   alpha',
        selection: TextSelection.collapsed(offset: 3),
      );
      const nativeOutsideBackspace = TextEditingValue(
        text: '  alpha',
        selection: TextSelection.collapsed(offset: 2),
      );
      expect(
        formatter.formatEditUpdate(outsideCode, nativeOutsideBackspace),
        nativeOutsideBackspace,
      );

      const contentDeletion = TextEditingValue(
        text: '```dart\nalpha\n```',
        selection: TextSelection.collapsed(offset: 13),
      );
      const nativeContentBackspace = TextEditingValue(
        text: '```dart\nalph\n```',
        selection: TextSelection.collapsed(offset: 12),
      );
      expect(
        formatter.formatEditUpdate(contentDeletion, nativeContentBackspace),
        nativeContentBackspace,
      );
    });

    test('three typed backticks progress from a pair into a fence', () {
      final first = _typeCharacter(formatter, '', 0, '`');
      expect(
        first,
        const TextEditingValue(
          text: '``',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      final second = _typeCharacter(
        formatter,
        first.text,
        first.selection.extentOffset,
        '`',
      );
      expect(
        second,
        const TextEditingValue(
          text: '``',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      expect(
        _typeCharacter(
          formatter,
          second.text,
          second.selection.extentOffset,
          '`',
        ),
        const TextEditingValue(
          text: '```\n```',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
    });

    test('third backtick completes an Obsidian-style fenced code pair', () {
      expect(
        _typeCharacter(formatter, '``', 2, '`'),
        const TextEditingValue(
          text: '```\n```',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      expect(
        _typeCharacter(formatter, 'abc ``tail', 6, '`'),
        const TextEditingValue(
          text: 'abc ```\n```tail',
          selection: TextSelection.collapsed(offset: 7),
        ),
      );
    });

    test('third backtick closes an existing fence without another pair', () {
      const paired = '```dart\n``\n```';
      expect(
        _typeCharacter(formatter, paired, 10, '`'),
        const TextEditingValue(
          text: '```dart\n```\n```',
          selection: TextSelection.collapsed(offset: 11),
        ),
      );

      const unclosed = '```dart\n``';
      expect(
        _typeCharacter(formatter, unclosed, 10, '`'),
        const TextEditingValue(
          text: '```dart\n```',
          selection: TextSelection.collapsed(offset: 11),
        ),
      );
    });

    test('fence completion mirrors Obsidian block indentation', () {
      expect(_typeCharacter(formatter, '  ``', 4, '`').text, '  ```\n  ```');
      expect(_typeCharacter(formatter, '> ``', 4, '`').text, '> ```\n> ```');
      expect(_typeCharacter(formatter, '- ``', 4, '`').text, '- ```\n  ```');
      expect(
        _typeCharacter(formatter, '12. ``', 6, '`').text,
        '12. ```\n    ```',
      );
      expect(
        _typeCharacter(formatter, '- [ ] ``', 8, '`').text,
        '- [ ] ```\n      ```',
      );
      expect(
        _typeCharacter(formatter, '> - ``', 6, '`').text,
        '> - ```\n>   ```',
      );
    });

    test('fence completion ignores tildes, longer runs, and paste', () {
      expect(_typeCharacter(formatter, '~~', 2, '~').text, '~~~');
      expect(_typeCharacter(formatter, '```', 3, '`').text, '````');

      const oldValue = TextEditingValue(
        selection: TextSelection.collapsed(offset: 0),
      );
      const pasted = TextEditingValue(
        text: '```',
        selection: TextSelection.collapsed(offset: 3),
      );
      expect(formatter.formatEditUpdate(oldValue, pasted), pasted);
    });

    test('pasting an HTTP URL over selected text creates a Markdown link', () {
      const oldValue = TextEditingValue(
        text: 'Label',
        selection: TextSelection(baseOffset: 0, extentOffset: 5),
      );
      const nativePaste = TextEditingValue(
        text: 'https://example.com',
        selection: TextSelection.collapsed(offset: 19),
      );

      expect(
        formatter.formatEditUpdate(oldValue, nativePaste),
        const TextEditingValue(
          text: '[Label](https://example.com)',
          selection: TextSelection.collapsed(offset: 28),
        ),
      );
    });

    test(
      'smart URL paste also wraps a selected URL and existing link label',
      () {
        const url = 'https://example.com';
        const selectedUrl = TextEditingValue(
          text: url,
          selection: TextSelection(baseOffset: 0, extentOffset: 19),
        );
        const nativeSameUrlPaste = TextEditingValue(
          text: url,
          selection: TextSelection.collapsed(offset: 19),
        );
        expect(
          formatter.formatEditUpdate(selectedUrl, nativeSameUrlPaste).text,
          '[$url]($url)',
        );

        const existingLink = TextEditingValue(
          text: '[Label](https://old.example)',
          selection: TextSelection(baseOffset: 1, extentOffset: 6),
        );
        const nativeLinkLabelPaste = TextEditingValue(
          text: '[https://new.example](https://old.example)',
          selection: TextSelection.collapsed(offset: 20),
        );
        expect(
          formatter.formatEditUpdate(existingLink, nativeLinkLabelPaste).text,
          '[[Label](https://new.example)](https://old.example)',
        );
      },
    );

    test('smart URL paste leaves collapsed and non-URL pastes native', () {
      const collapsed = TextEditingValue(
        text: 'Label',
        selection: TextSelection.collapsed(offset: 5),
      );
      const bareUrlPaste = TextEditingValue(
        text: 'Labelhttps://example.com',
        selection: TextSelection.collapsed(offset: 24),
      );
      expect(formatter.formatEditUpdate(collapsed, bareUrlPaste), bareUrlPaste);

      const selected = TextEditingValue(
        text: 'Label',
        selection: TextSelection(baseOffset: 0, extentOffset: 5),
      );
      const plainPaste = TextEditingValue(
        text: 'plain text',
        selection: TextSelection.collapsed(offset: 10),
      );
      const newlineUrlPaste = TextEditingValue(
        text: 'https://example.com\n',
        selection: TextSelection.collapsed(offset: 20),
      );
      expect(formatter.formatEditUpdate(selected, plainPaste), plainPaste);
      expect(
        formatter.formatEditUpdate(selected, newlineUrlPaste),
        newlineUrlPaste,
      );
    });

    test('code newlines preserve indentation and source continuations', () {
      const indented = '```dart\n    alpha\n```';
      final indentedCaret = indented.indexOf('\n```');
      expect(
        _pressEnterAt(formatter, indented, indentedCaret),
        TextEditingValue(
          text: '```dart\n    alpha\n    \n```',
          selection: TextSelection.collapsed(offset: indentedCaret + 5),
        ),
      );

      const blank = '```\n    \n```';
      final blankCaret = blank.indexOf('\n```', 4);
      expect(
        _pressEnterAt(formatter, blank, blankCaret).text,
        '```\n    \n    \n```',
      );

      const listLike = '```\n- item\n```';
      final listCaret = listLike.indexOf('\n```', 4);
      expect(
        _pressEnterAt(formatter, listLike, listCaret).text,
        '```\n- item\n\n```',
      );
    });

    test('paired fence info keeps repeated empty code lines active', () {
      var value = _typeCharacter(formatter, '``', 2, '`');
      for (final character in 'dart'.split('')) {
        value = _typeCharacter(
          formatter,
          value.text,
          value.selection.extentOffset,
          character,
        );
      }
      expect(
        value,
        const TextEditingValue(
          text: '```dart\n```',
          selection: TextSelection.collapsed(offset: 7),
        ),
      );

      final firstEmptyLine = _pressEnterAt(
        formatter,
        value.text,
        value.selection.extentOffset,
      );
      expect(
        firstEmptyLine,
        const TextEditingValue(
          text: '```dart\n\n```',
          selection: TextSelection.collapsed(offset: 8),
        ),
      );
      expect(
        _pressEnterAt(
          formatter,
          firstEmptyLine.text,
          firstEmptyLine.selection.extentOffset,
        ),
        const TextEditingValue(
          text: '```dart\n\n\n```',
          selection: TextSelection.collapsed(offset: 9),
        ),
      );
    });

    test('closing fence boundaries keep native Enter and Backspace edits', () {
      const source = '```dart\nline\n```\n\nAfter code.';
      const closingStart = 13;
      const closingEnd = 16;

      expect(
        _pressEnterAt(formatter, source, closingStart),
        const TextEditingValue(
          text: '```dart\nline\n\n```\n\nAfter code.',
          selection: TextSelection.collapsed(offset: closingStart + 1),
        ),
      );
      expect(
        _pressEnterAt(formatter, source, closingEnd),
        const TextEditingValue(
          text: '```dart\nline\n```\n\n\nAfter code.',
          selection: TextSelection.collapsed(offset: closingEnd + 1),
        ),
      );

      const atClosingStart = TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: closingStart),
      );
      const nativeBackspace = TextEditingValue(
        text: '```dart\nline```\n\nAfter code.',
        selection: TextSelection.collapsed(offset: closingStart - 1),
      );
      expect(
        formatter.formatEditUpdate(atClosingStart, nativeBackspace),
        nativeBackspace,
      );
    });

    test('inline-code marker Backspace edits stay native', () {
      const single = 'Plain `alpha beta` tail.';
      final singleClosing = single.lastIndexOf('`') + 1;
      final atSingleClosing = TextEditingValue(
        text: single,
        selection: TextSelection.collapsed(offset: singleClosing),
      );
      final deletedSingleClosing = TextEditingValue(
        text: single.replaceRange(singleClosing - 1, singleClosing, ''),
        selection: TextSelection.collapsed(offset: singleClosing - 1),
      );
      expect(
        formatter.formatEditUpdate(atSingleClosing, deletedSingleClosing),
        deletedSingleClosing,
      );

      final singleOpening = single.indexOf('`') + 1;
      final atSingleOpening = TextEditingValue(
        text: single,
        selection: TextSelection.collapsed(offset: singleOpening),
      );
      final deletedSingleOpening = TextEditingValue(
        text: single.replaceRange(singleOpening - 1, singleOpening, ''),
        selection: TextSelection.collapsed(offset: singleOpening - 1),
      );
      expect(
        formatter.formatEditUpdate(atSingleOpening, deletedSingleOpening),
        deletedSingleOpening,
      );

      const double = 'Double ``alpha ` beta`` tail.';
      final doubleClosing = double.lastIndexOf('``') + 2;
      final atDoubleClosing = TextEditingValue(
        text: double,
        selection: TextSelection.collapsed(offset: doubleClosing),
      );
      final deletedOneDoubleClosing = TextEditingValue(
        text: double.replaceRange(doubleClosing - 1, doubleClosing, ''),
        selection: TextSelection.collapsed(offset: doubleClosing - 1),
      );
      expect(
        formatter.formatEditUpdate(atDoubleClosing, deletedOneDoubleClosing),
        deletedOneDoubleClosing,
      );
    });

    test('emphasis marker Backspace removes one source character', () {
      for (final (source, caret, expected) in <(String, int, String)>[
        (
          'Strong **bold text** tail.',
          'Strong **bold text**'.length,
          'Strong **bold text* tail.',
        ),
        (
          'Strong **bold text** tail.',
          'Strong **'.length,
          'Strong *bold text** tail.',
        ),
        (
          'Highlight ==marked text== tail.',
          'Highlight ==marked text=='.length,
          'Highlight ==marked text= tail.',
        ),
      ]) {
        final oldValue = TextEditingValue(
          text: source,
          selection: TextSelection.collapsed(offset: caret),
        );
        final nativeBackspace = TextEditingValue(
          text: source.replaceRange(caret - 1, caret, ''),
          selection: TextSelection.collapsed(offset: caret - 1),
        );
        expect(nativeBackspace.text, expected);
        expect(
          formatter.formatEditUpdate(oldValue, nativeBackspace),
          nativeBackspace,
        );
      }
    });

    test('four-backtick fences keep inner triple runs active on Enter', () {
      const source =
          '````markdown\n'
          'literal ``` inner\n'
          '````\n\n'
          'After code.';
      const expected =
          '````markdown\n'
          'literal ``` inner\n'
          '\n'
          '````\n\n'
          'After code.';
      final bodyEnd = source.indexOf('\n````');
      final closingStart = bodyEnd + 1;

      expect(
        _pressEnterAt(formatter, source, bodyEnd),
        TextEditingValue(
          text: expected,
          selection: TextSelection.collapsed(offset: bodyEnd + 1),
        ),
      );
      expect(
        _pressEnterAt(formatter, source, closingStart),
        TextEditingValue(
          text: expected,
          selection: TextSelection.collapsed(offset: closingStart + 1),
        ),
      );
    });

    test('syntax fences indent after opening delimiters', () {
      const braced = '```dart\nif (ready) {\n}\n```';
      final bracedCaret = braced.indexOf('\n}');
      expect(
        _pressEnterAt(formatter, braced, bracedCaret),
        TextEditingValue(
          text: '```dart\nif (ready) {\n    \n}\n```',
          selection: TextSelection.collapsed(offset: bracedCaret + 5),
        ),
      );

      const nested = '```javascript\n    final values = [\n]\n```';
      final nestedCaret = nested.indexOf('\n]');
      expect(
        _pressEnterAt(formatter, nested, nestedCaret).text,
        '```javascript\n    final values = [\n        \n]\n```',
      );
    });

    test('typed code closers outdent whitespace-only lines', () {
      const emptyLine = '```dart\n    \n```';
      expect(
        _typeCharacter(formatter, emptyLine, 12, '}'),
        const TextEditingValue(
          text: '```dart\n}\n```',
          selection: TextSelection.collapsed(offset: 9),
        ),
      );

      const existingCloser = '```dart\n    }\n```';
      expect(
        _typeCharacter(formatter, existingCloser, 12, '}'),
        const TextEditingValue(
          text: '```dart\n}\n```',
          selection: TextSelection.collapsed(offset: 9),
        ),
      );

      expect(_typeCharacter(formatter, '    ', 4, '}').text, '    }');
      expect(
        _typeCharacter(formatter, '```text\n    \n```', 12, '}').text,
        '```text\n    }\n```',
      );
    });

    test('continues unordered, task, ordered, and quote markers', () {
      expect(_pressEnter(formatter, '- item').text, '- item\n- ');
      expect(_pressEnter(formatter, '- [x] done').text, '- [x] done\n- [ ] ');
      expect(
        _pressEnter(formatter, '- [!] important').text,
        '- [!] important\n- [ ] ',
      );
      expect(_pressEnter(formatter, '9. item').text, '9. item\n10. ');
      expect(
        _pressEnter(formatter, '9. [/] ongoing').text,
        '9. [/] ongoing\n10. [ ] ',
      );
      expect(_pressEnter(formatter, '> quote').text, '> quote\n> ');
      expect(_pressEnter(formatter, '>quote').text, '>quote\n> ');
      expect(_pressEnter(formatter, '>>child').text, '>>child\n>> ');
    });

    test('renumbers following ordered items when Enter inserts a sibling', () {
      expect(
        _pressEnterAt(formatter, '1. A\n2. B', 4),
        const TextEditingValue(
          text: '1. A\n2. \n3. B',
          selection: TextSelection.collapsed(offset: 8),
        ),
      );
      expect(
        _pressEnterAt(formatter, '8. A\n9. B', 4).text,
        '8. A\n9. \n10. B',
      );
      expect(
        _pressEnterAt(formatter, '1. A\n    1. B\n    2. C\n2. D', 13),
        const TextEditingValue(
          text: '1. A\n    1. B\n    2. \n    3. C\n2. D',
          selection: TextSelection.collapsed(offset: 21),
        ),
      );
      expect(
        _pressEnterAt(formatter, '> 1. A\n> 2. B', 6).text,
        '> 1. A\n> 2. \n> 3. B',
      );
    });

    test('empty ordered items preserve Obsidian list structure', () {
      final rootInserted = _pressEnterAt(formatter, '1. A\n2. B', 4);
      expect(
        _pressEnterAt(
          formatter,
          rootInserted.text,
          rootInserted.selection.extentOffset,
        ),
        const TextEditingValue(
          text: '1. A\n\n2. B',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );

      final nestedInserted = _pressEnterAt(
        formatter,
        '1. A\n    1. B\n    2. C\n2. D',
        13,
      );
      expect(
        _pressEnterAt(
          formatter,
          nestedInserted.text,
          nestedInserted.selection.extentOffset,
        ),
        const TextEditingValue(
          text: '1. A\n    1. B\n2. \n    1. C\n3. D',
          selection: TextSelection.collapsed(offset: 17),
        ),
      );
    });

    test('continues lists and nested quotes inside block quotes', () {
      expect(_pressEnter(formatter, '> - item').text, '> - item\n> - ');
      expect(_pressEnter(formatter, '> + item').text, '> + item\n> + ');
      expect(_pressEnter(formatter, '> 9. item').text, '> 9. item\n> 10. ');
      expect(
        _pressEnter(formatter, '> - [x] done').text,
        '> - [x] done\n> - [ ] ',
      );
      expect(
        _pressEnter(formatter, '> - [?] question').text,
        '> - [?] question\n> - [ ] ',
      );
      expect(_pressEnter(formatter, '> > quote').text, '> > quote\n> > ');
      expect(
        _pressEnter(formatter, '>     - item').text,
        '>     - item\n>     - ',
      );
      expect(
        _pressEnter(formatter, '>     - [x] done').text,
        '>     - [x] done\n>     - [ ] ',
      );
      expect(
        _pressEnter(formatter, '>     1. item').text,
        '>     1. item\n>     2. ',
      );
    });

    test('matches Obsidian list exits and literal-tab boundaries', () {
      final firstExit = _pressEnter(formatter, '- first\n        - ');
      expect(firstExit.text, '- first\n    - ');
      final secondExit = _pressEnterAt(
        formatter,
        firstExit.text,
        firstExit.selection.extentOffset,
      );
      expect(secondExit.text, '- first\n- ');

      expect(_pressEnter(formatter, '    - code').text, '    - code\n    - ');
      expect(_pressEnter(formatter, '\t- code').text, '\t- code\n\t- ');

      const comment = '%%\n- item\n%%';
      expect(
        _pressEnterAt(formatter, comment, comment.indexOf('\n%%')).text,
        '%%\n- item\n- \n%%',
      );

      expect(_pressEnter(formatter, '-\tone').text, '-\tone\n');
    });

    testWidgets('Shift+Enter aligns soft continuations under markers', (
      tester,
    ) async {
      Future<TextEditingValue> shiftEnter(String text) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
        final result = _pressEnter(formatter, text);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
        return result;
      }

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      try {
        expect((await shiftEnter('- item')).text, '- item\n  ');
        expect((await shiftEnter('- [x] done')).text, '- [x] done\n      ');
        expect((await shiftEnter('9. item')).text, '9. item\n   ');
        expect((await shiftEnter('10. item')).text, '10. item\n    ');
        expect((await shiftEnter('> quote')).text, '> quote\n> ');
        expect((await shiftEnter('>quote')).text, '>quote\n> ');
        expect((await shiftEnter('> - item')).text, '> - item\n>   ');
        expect((await shiftEnter('> 9. item')).text, '> 9. item\n>    ');
        expect(
          (await shiftEnter('> - [x] done')).text,
          '> - [x] done\n>       ',
        );
        expect(
          (await shiftEnter('>     - item')).text,
          '>     - item\n>       ',
        );
        expect((await shiftEnter('> > quote')).text, '> > quote\n> > ');
        expect((await shiftEnter('    - nested')).text, '    - nested\n      ');
        expect((await shiftEnter('-\tone')).text, '-\tone\n');
      } finally {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      }

      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      expect(_pressEnter(formatter, '- item').text, '- item\n- ');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    });

    testWidgets(
      'plain paragraph newlines preserve trailing whitespace exactly',
      (tester) async {
        expect(_pressEnter(formatter, 'zero').text, 'zero\n');
        expect(_pressEnter(formatter, 'one ').text, 'one \n');
        expect(_pressEnter(formatter, 'two  ').text, 'two  \n');
        expect(_pressEnter(formatter, 'three   ').text, 'three   \n');
        expect(_pressEnter(formatter, 'alpha\n').text, 'alpha\n\n');

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
        try {
          expect(_pressEnter(formatter, 'shiftone ').text, 'shiftone \n');
          expect(_pressEnter(formatter, 'alpha\n').text, 'alpha\n\n');
        } finally {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        }
      },
    );

    test('backslash hard breaks keep native newline and Backspace edits', () {
      const source = 'Backslash alpha\\';
      final entered = _pressEnter(formatter, source);
      expect(
        entered,
        TextEditingValue(
          text: '$source\n',
          selection: TextSelection.collapsed(offset: source.length + 1),
        ),
      );

      final merged = TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: source.length),
      );
      expect(formatter.formatEditUpdate(entered, merged), merged);

      const withoutBackslash = 'Backslash alpha';
      final deletedBackslash = TextEditingValue(
        text: withoutBackslash,
        selection: TextSelection.collapsed(offset: withoutBackslash.length),
      );
      expect(
        formatter.formatEditUpdate(merged, deletedBackslash),
        deletedBackslash,
      );
    });

    test('empty nested items outdent once before root items exit', () {
      expect(_pressEnter(formatter, '- first\n  - ').text, '- first\n- ');
      expect(
        _pressEnter(formatter, '- first\n        - ').text,
        '- first\n    - ',
      );
      expect(
        _pressEnter(formatter, '- parent\n    - [ ] ').text,
        '- parent\n- [ ] ',
      );
      expect(
        _pressEnter(formatter, '1. parent\n    7. ').text,
        '1. parent\n7. ',
      );
      final exitedRoot = _pressEnter(formatter, '- first\n- ');
      expect(
        exitedRoot,
        const TextEditingValue(
          text: '- first\n',
          selection: TextSelection.collapsed(offset: 8),
        ),
      );
      expect(
        _typeCharacter(
          formatter,
          exitedRoot.text,
          exitedRoot.selection.extentOffset,
          'plain',
        ).text,
        '- first\nplain',
      );
      expect(
        _pressEnter(formatter, '- [ ] '),
        const TextEditingValue(
          text: '',
          selection: TextSelection.collapsed(offset: 0),
        ),
      );
      expect(_pressEnter(formatter, '> quote\n> ').text, '> quote\n\n');
      expect(_pressEnter(formatter, '> - item\n> - ').text, '> - item\n> ');
      expect(
        _pressEnter(formatter, '>     - item\n>     - ').text,
        '>     - item\n> - ',
      );
      expect(
        _pressEnter(formatter, '>         - item\n>         - ').text,
        '>         - item\n>     - ',
      );
      expect(_pressEnter(formatter, '> 9. item\n> 10. ').text, '> 9. item\n> ');
      expect(_pressEnter(formatter, '> > ').text, '> ');
      final nestedQuote = _pressEnter(formatter, '> > child');
      expect(nestedQuote.text, '> > child\n> > ');
      final outdentedQuote = _pressEnterAt(
        formatter,
        nestedQuote.text,
        nestedQuote.selection.extentOffset,
      );
      expect(outdentedQuote.text, '> > child\n> ');
      final exitedQuote = _pressEnterAt(
        formatter,
        outdentedQuote.text,
        outdentedQuote.selection.extentOffset,
      );
      expect(exitedQuote.text, '> > child\n\n');
    });

    test('splitting at item content start preserves the empty marker', () {
      const oldTask = TextEditingValue(
        text: '- [ ] Task',
        selection: TextSelection.collapsed(offset: 6),
      );
      const newTask = TextEditingValue(
        text: '- [ ] \nTask',
        selection: TextSelection.collapsed(offset: 7),
      );
      expect(formatter.formatEditUpdate(oldTask, newTask), newTask);

      const oldBullet = TextEditingValue(
        text: '- Item',
        selection: TextSelection.collapsed(offset: 2),
      );
      const newBullet = TextEditingValue(
        text: '- \nItem',
        selection: TextSelection.collapsed(offset: 3),
      );
      expect(formatter.formatEditUpdate(oldBullet, newBullet), newBullet);
    });

    test('narrows native word deletion to adjacent Markdown punctuation', () {
      const oldBackward = TextEditingValue(
        text: '**bold**',
        selection: TextSelection.collapsed(offset: 8),
      );
      const nativeBackward = TextEditingValue(
        text: '**',
        selection: TextSelection.collapsed(offset: 2),
      );
      expect(
        formatter.formatEditUpdate(oldBackward, nativeBackward),
        const TextEditingValue(
          text: '**bold',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );

      const oldForward = TextEditingValue(
        text: '[label](url)',
        selection: TextSelection.collapsed(offset: 0),
      );
      const nativeForward = TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
      expect(
        formatter.formatEditUpdate(oldForward, nativeForward),
        const TextEditingValue(
          text: 'label](url)',
          selection: TextSelection.collapsed(offset: 0),
        ),
      );
    });

    test('preserves ordinary character, word, and selection deletion', () {
      const oldCharacter = TextEditingValue(
        text: '**bold**',
        selection: TextSelection.collapsed(offset: 8),
      );
      const newCharacter = TextEditingValue(
        text: '**bold*',
        selection: TextSelection.collapsed(offset: 7),
      );
      expect(
        formatter.formatEditUpdate(oldCharacter, newCharacter),
        newCharacter,
      );

      const oldWord = TextEditingValue(
        text: 'foo-bar_baz',
        selection: TextSelection.collapsed(offset: 11),
      );
      const newWord = TextEditingValue(
        text: 'foo-',
        selection: TextSelection.collapsed(offset: 4),
      );
      expect(formatter.formatEditUpdate(oldWord, newWord), newWord);

      const oldSelection = TextEditingValue(
        text: '**bold**',
        selection: TextSelection(baseOffset: 2, extentOffset: 8),
      );
      const newSelection = TextEditingValue(
        text: '**',
        selection: TextSelection.collapsed(offset: 2),
      );
      expect(
        formatter.formatEditUpdate(oldSelection, newSelection),
        newSelection,
      );
    });

    test('preserves character-by-character deletion through list prefixes', () {
      for (final (oldValue, nativeBackspace)
          in <(TextEditingValue, TextEditingValue)>[
            (
              const TextEditingValue(
                text: '- root item',
                selection: TextSelection.collapsed(offset: 2),
              ),
              const TextEditingValue(
                text: '-root item',
                selection: TextSelection.collapsed(offset: 1),
              ),
            ),
            (
              const TextEditingValue(
                text: '- [ ] task item',
                selection: TextSelection.collapsed(offset: 6),
              ),
              const TextEditingValue(
                text: '- [ ]task item',
                selection: TextSelection.collapsed(offset: 5),
              ),
            ),
            (
              const TextEditingValue(
                text: '12. ordered item',
                selection: TextSelection.collapsed(offset: 4),
              ),
              const TextEditingValue(
                text: '12.ordered item',
                selection: TextSelection.collapsed(offset: 3),
              ),
            ),
            (
              const TextEditingValue(
                text: '  - nested item',
                selection: TextSelection.collapsed(offset: 4),
              ),
              const TextEditingValue(
                text: '  -nested item',
                selection: TextSelection.collapsed(offset: 3),
              ),
            ),
          ]) {
        expect(
          formatter.formatEditUpdate(oldValue, nativeBackspace),
          nativeBackspace,
        );
      }
    });

    test('does not rewrite composing input', () {
      const oldValue = TextEditingValue(
        text: '- 输入',
        selection: TextSelection.collapsed(offset: 4),
      );
      const newValue = TextEditingValue(
        text: '- 输入\n',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 2, end: 4),
      );

      expect(formatter.formatEditUpdate(oldValue, newValue), newValue);
    });
  });

  test('live preview reveals only markers around the active inline format', () {
    const syntax = IanvsMarkdownSyntaxTheme(
      heading: TextStyle(fontWeight: FontWeight.w600),
      marker: TextStyle(color: Color(0xff777777)),
      link: TextStyle(decoration: TextDecoration.underline),
      code: TextStyle(fontFamily: 'monospace'),
      comment: TextStyle(fontStyle: FontStyle.italic),
      highlight: TextStyle(backgroundColor: Color(0xffffe184)),
    );
    const base = TextStyle(fontSize: 14);
    const source =
        'Plain **bold** and *italic* with `code` and [link](docs.md), '
        '[[vault/Target|Target Note]], #tag, and ==highlighted text==.';

    TextSpan build(int caret) => buildMarkdownSourceTextSpan(
      TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: caret),
      ),
      style: base,
      syntaxTheme: syntax,
      withComposing: false,
      hideInactiveInlineMarkers: true,
    );

    final inactive = build(0).children!.cast<TextSpan>().toList();
    final hiddenMarkers = inactive.where(
      (span) => span.text == '**' || span.text == '*',
    );
    expect(hiddenMarkers, isNotEmpty);
    expect(hiddenMarkers.every((span) => span.style?.fontSize == .01), isTrue);
    expect(
      inactive.singleWhere((span) => span.text == 'bold').style?.fontWeight,
      FontWeight.w700,
    );
    expect(
      inactive.singleWhere((span) => span.text == 'italic').style?.fontStyle,
      FontStyle.italic,
    );

    final active = build(10).children!.cast<TextSpan>().toList();
    final boldMarkers = active.where((span) => span.text == '**').toList();
    expect(boldMarkers, hasLength(2));
    expect(boldMarkers.every((span) => span.style?.fontSize == 14), isTrue);
    final italicMarkers = active.where((span) => span.text == '*').toList();
    expect(italicMarkers.every((span) => span.style?.fontSize == .01), isTrue);

    final boldStart = source.indexOf('**bold**');
    final boldEnd = boldStart + '**bold**'.length;
    final atOpeningBoundary = build(
      boldStart,
    ).children!.cast<TextSpan>().where((span) => span.text == '**').toList();
    expect(
      atOpeningBoundary.every((span) => span.style?.fontSize == 14),
      isTrue,
    );
    final afterClosingBoundary = build(
      boldEnd,
    ).children!.cast<TextSpan>().where((span) => span.text == '**').toList();
    expect(
      afterClosingBoundary.every((span) => span.style?.fontSize == .01),
      isTrue,
    );

    final linkActive = build(
      source.indexOf('link'),
    ).children!.cast<TextSpan>().toList();
    expect(
      linkActive.singleWhere((span) => span.text == 'link').style?.decoration,
      TextDecoration.underline,
    );
    expect(
      linkActive
          .singleWhere((span) => span.text == '](docs.md)')
          .style
          ?.fontSize,
      14,
    );
    final inactiveWiki = inactive.where(
      (span) => span.text == '[[vault/Target|' || span.text == ']]',
    );
    expect(inactiveWiki, hasLength(2));
    expect(inactiveWiki.every((span) => span.style?.fontSize == .01), isTrue);
    expect(
      inactive
          .singleWhere((span) => span.text == 'Target Note')
          .style
          ?.fontWeight,
      FontWeight.w600,
    );

    final wikiActive = build(
      source.indexOf('Target Note') + 2,
    ).children!.cast<TextSpan>().toList();
    final activeWikiMarkers = wikiActive.where(
      (span) => span.text == '[[vault/Target|' || span.text == ']]',
    );
    expect(
      activeWikiMarkers.every((span) => span.style?.fontSize == 14),
      isTrue,
    );
    expect(
      inactive.singleWhere((span) => span.text == '#tag').style?.fontWeight,
      FontWeight.w600,
    );
    final inactiveHighlightMarkers = inactive
        .where((span) => span.text == '==')
        .toList();
    expect(inactiveHighlightMarkers, hasLength(2));
    expect(
      inactiveHighlightMarkers.every((span) => span.style?.fontSize == .01),
      isTrue,
    );
    expect(
      inactive
          .singleWhere((span) => span.text == 'highlighted text')
          .style
          ?.backgroundColor,
      const Color(0xffffe184),
    );

    final highlightActive = build(
      source.indexOf('highlighted text'),
    ).children!.cast<TextSpan>().toList();
    final activeHighlightMarkers = highlightActive
        .where((span) => span.text == '==')
        .toList();
    expect(activeHighlightMarkers, hasLength(2));
    expect(
      activeHighlightMarkers.every((span) => span.style?.fontSize == 14),
      isTrue,
    );
    expect(
      inactive.singleWhere((span) => span.text == 'code').style?.fontFamily,
      'monospace',
    );
  });

  test('source tag styling shares Obsidian lexical boundaries', () {
    const tagColor = Color(0xff123456);
    const syntax = IanvsMarkdownSyntaxTheme(
      heading: TextStyle(),
      marker: TextStyle(),
      link: TextStyle(),
      code: TextStyle(fontFamily: 'monospace'),
      comment: TextStyle(),
      tag: TextStyle(color: tagColor),
    );
    const source =
        '#café #123 #123tag (#paren) #nested/sub; '
        'word#tight https://example.com/#fragment ：#after-colon '
        r'\#escaped \\#double #one#two '
        '#fullwidth。tail `text #code`';

    final spans = buildMarkdownSourceTextSpan(
      const TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: 0),
      ),
      style: const TextStyle(fontSize: 14),
      syntaxTheme: syntax,
      withComposing: false,
    ).children!.cast<TextSpan>().toList();

    expect(
      spans
          .where((span) => span.style?.color == tagColor)
          .map((span) => span.text),
      <String>[
        '#café',
        '#123tag',
        '#nested/sub',
        '#after-colon',
        '#double',
        '#one',
        '#two',
        '#fullwidth。tail',
      ],
    );
    expect(
      spans.singleWhere((span) => span.text == 'text #code').style?.fontFamily,
      'monospace',
    );
  });

  test(
    'source highlight styling hides full runs and stops unclosed at EOL',
    () {
      const markerColor = Color(0xff777777);
      const highlightColor = Color(0xffffe184);
      const syntax = IanvsMarkdownSyntaxTheme(
        heading: TextStyle(),
        marker: TextStyle(color: markerColor),
        link: TextStyle(),
        code: TextStyle(fontFamily: 'monospace'),
        comment: TextStyle(),
        highlight: TextStyle(backgroundColor: highlightColor),
      );
      const source = 'L====x===R M==openR\n\nnextR N== leading==R';

      List<TextSpan> build(int caret) => buildMarkdownSourceTextSpan(
        TextEditingValue(
          text: source,
          selection: TextSelection.collapsed(offset: caret),
        ),
        style: const TextStyle(fontSize: 14),
        syntaxTheme: syntax,
        withComposing: false,
        hideInactiveInlineMarkers: true,
      ).children!.cast<TextSpan>().toList();

      TextSpan spanAt(List<TextSpan> spans, int offset) {
        var cursor = 0;
        for (final span in spans) {
          final end = cursor + (span.text?.length ?? 0);
          if (offset >= cursor && offset < end) return span;
          cursor = end;
        }
        throw StateError('No span at $offset');
      }

      final inactive = build(source.indexOf('nextR'));
      expect(
        inactive.singleWhere((span) => span.text == '====').style?.fontSize,
        .01,
      );
      expect(
        inactive.singleWhere((span) => span.text == '===').style?.fontSize,
        .01,
      );
      expect(
        spanAt(inactive, source.indexOf('x')).style?.backgroundColor,
        highlightColor,
      );
      expect(
        spanAt(inactive, source.indexOf('openR')).style?.backgroundColor,
        highlightColor,
      );
      expect(
        spanAt(inactive, source.indexOf('nextR')).style?.backgroundColor,
        isNot(highlightColor),
      );
      expect(
        spanAt(inactive, source.indexOf('leading')).style?.backgroundColor,
        isNot(highlightColor),
      );

      final active = build(source.indexOf('x'));
      expect(
        active.singleWhere((span) => span.text == '====').style?.fontSize,
        14,
      );
      expect(
        active.singleWhere((span) => span.text == '===').style?.fontSize,
        14,
      );
      final inlineRange = ianvsMarkdownInlineSourceRangeAt(
        source,
        TextRange(start: source.indexOf('x'), end: source.indexOf('x') + 1),
      );
      expect(inlineRange?.textInside(source), '====x===');
    },
  );

  test(
    'source strikethrough shares Obsidian runs and invalid marker hiding',
    () {
      const syntax = IanvsMarkdownSyntaxTheme(
        heading: TextStyle(),
        marker: TextStyle(color: Color(0xff777777)),
        link: TextStyle(),
        code: TextStyle(fontFamily: 'monospace'),
        comment: TextStyle(),
        strikethrough: TextStyle(decoration: TextDecoration.lineThrough),
      );
      const source =
          'A~single~Z\n\n'
          'B~~~~alpha~~Z\n\n'
          'C~~bravo~~~~Z\n\n'
          'D~~openZ\nnextZ\n\n'
          'E~~ echo~~Z\n\n'
          'F~~foxtrot ~~Z';

      List<TextSpan> build(int caret) => buildMarkdownSourceTextSpan(
        TextEditingValue(
          text: source,
          selection: TextSelection.collapsed(offset: caret),
        ),
        style: const TextStyle(fontSize: 14),
        syntaxTheme: syntax,
        withComposing: false,
        hideInactiveInlineMarkers: true,
      ).children!.cast<TextSpan>().toList();

      TextSpan spanAt(List<TextSpan> spans, int offset) {
        var cursor = 0;
        for (final span in spans) {
          final end = cursor + (span.text?.length ?? 0);
          if (offset >= cursor && offset < end) return span;
          cursor = end;
        }
        throw StateError('No span at $offset');
      }

      final inactive = build(source.indexOf('nextZ'));
      expect(spanAt(inactive, source.indexOf('~single')).style?.fontSize, 14);

      final alpha = source.indexOf('alpha');
      expect(spanAt(inactive, alpha - 4).style?.fontSize, .01);
      expect(spanAt(inactive, alpha + 'alpha'.length).style?.fontSize, .01);
      expect(
        spanAt(
          inactive,
          alpha,
        ).style?.decoration?.contains(TextDecoration.lineThrough),
        isTrue,
      );

      final bravo = source.indexOf('bravo');
      expect(spanAt(inactive, bravo - 2).style?.fontSize, .01);
      expect(spanAt(inactive, bravo + 'bravo'.length).style?.fontSize, .01);
      expect(
        spanAt(
          inactive,
          bravo,
        ).style?.decoration?.contains(TextDecoration.lineThrough),
        isTrue,
      );

      final open = source.indexOf('openZ');
      expect(
        spanAt(
          inactive,
          open,
        ).style?.decoration?.contains(TextDecoration.lineThrough),
        isTrue,
      );
      expect(
        spanAt(
          inactive,
          source.indexOf('nextZ'),
        ).style?.decoration?.contains(TextDecoration.lineThrough),
        isNot(true),
      );

      final echo = source.indexOf('echo');
      expect(spanAt(inactive, echo - 3).style?.fontSize, 14);
      expect(
        spanAt(inactive, source.indexOf('~~Z', echo)).style?.fontSize,
        .01,
      );
      expect(
        spanAt(
          inactive,
          echo,
        ).style?.decoration?.contains(TextDecoration.lineThrough),
        isNot(true),
      );

      final foxtrot = source.indexOf('foxtrot');
      expect(spanAt(inactive, foxtrot - 2).style?.fontSize, .01);
      expect(
        spanAt(inactive, source.indexOf('~~Z', foxtrot)).style?.fontSize,
        .01,
      );
      expect(
        spanAt(
          inactive,
          foxtrot,
        ).style?.decoration?.contains(TextDecoration.lineThrough),
        isNot(true),
      );

      final active = build(alpha);
      expect(spanAt(active, alpha - 4).style?.fontSize, 14);
      expect(spanAt(active, alpha + 'alpha'.length).style?.fontSize, 14);
      expect(
        ianvsMarkdownInlineSourceRangeAt(
          source,
          TextRange(start: alpha, end: alpha + 'alpha'.length),
        )?.textInside(source),
        '~~~~alpha~~',
      );
      expect(inactive.map((span) => span.text).join(), source);
    },
  );

  test(
    'leading-pipe Wiki links keep the pipe visible outside their markers',
    () {
      const source = 'A [[|Alias]] B [[ ]] C [[]]';
      const syntax = IanvsMarkdownSyntaxTheme(
        heading: TextStyle(),
        marker: TextStyle(color: Color(0xff777777)),
        link: TextStyle(),
        code: TextStyle(),
        comment: TextStyle(),
        wikiLink: TextStyle(fontWeight: FontWeight.w600),
      );
      final spans = buildMarkdownSourceTextSpan(
        const TextEditingValue(
          text: source,
          selection: TextSelection.collapsed(offset: 0),
        ),
        style: const TextStyle(fontSize: 14),
        syntaxTheme: syntax,
        withComposing: false,
        hideInactiveInlineMarkers: true,
      ).children!.cast<TextSpan>().toList();

      expect(spans.map((span) => span.text).join(), source);
      expect(
        spans.singleWhere((span) => span.text == '|Alias').style?.fontWeight,
        FontWeight.w600,
      );
      final markers = spans
          .where((span) => span.text == '[[' || span.text == ']]')
          .toList();
      expect(markers, hasLength(2));
      expect(markers.every((span) => span.style?.fontSize == .01), isTrue);
      final literal = spans.singleWhere(
        (span) => span.text?.contains('[[ ]] C [[]]') ?? false,
      );
      expect(literal.style?.fontSize, 14);
    },
  );

  test('live preview hides safe inline HTML and reveals its active range', () {
    const syntax = IanvsMarkdownSyntaxTheme(
      heading: TextStyle(fontWeight: FontWeight.w600),
      marker: TextStyle(color: Color(0xff777777)),
      link: TextStyle(decoration: TextDecoration.underline),
      code: TextStyle(fontFamily: 'monospace'),
      comment: TextStyle(fontStyle: FontStyle.italic),
      highlight: TextStyle(backgroundColor: Color(0xffffe184)),
    );
    const base = TextStyle(fontSize: 14);
    const source =
        'A <strong>bold <em>italic</em></strong>, '
        '<u>under</u>, <span style="color:red">red</span>, '
        '<not-a-real-tag>unknown</not-a-real-tag>, <br> tail; '
        '<!-- visible source --> <script>visible source</script>.';

    List<TextSpan> build(int caret) => buildMarkdownSourceTextSpan(
      TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: caret),
      ),
      style: base,
      syntaxTheme: syntax,
      withComposing: false,
      hideInactiveInlineMarkers: true,
    ).children!.cast<TextSpan>().toList();

    final inactive = build(0);
    for (final marker in <String>[
      '<strong>',
      '</strong>',
      '<em>',
      '</em>',
      '<u>',
      '</u>',
      '<span style="color:red">',
      '</span>',
      '<not-a-real-tag>',
      '</not-a-real-tag>',
      '<br>',
    ]) {
      final matching = inactive.where((span) => span.text == marker).toList();
      expect(
        matching,
        hasLength(1),
        reason:
            '$marker in ${inactive.map((span) => span.text).whereType<String>().toList()}',
      );
      expect(matching.single.style?.fontSize, .01, reason: marker);
    }
    expect(
      inactive.singleWhere((span) => span.text == 'bold ').style?.fontWeight,
      FontWeight.w700,
    );
    final italic = inactive.singleWhere((span) => span.text == 'italic');
    expect(italic.style?.fontWeight, FontWeight.w700);
    expect(italic.style?.fontStyle, FontStyle.italic);
    expect(
      inactive.singleWhere((span) => span.text == 'under').style?.decoration,
      TextDecoration.underline,
    );
    expect(
      inactive.singleWhere((span) => span.text == 'red').style?.color,
      const Color(0xffff0000),
    );
    expect(
      inactive
          .singleWhere((span) => span.text == '<!-- visible source -->')
          .style
          ?.fontSize,
      14,
    );
    expect(
      inactive
          .singleWhere(
            (span) =>
                span.text?.contains('<script>visible source</script>') ?? false,
          )
          .style
          ?.fontSize,
      14,
    );

    final active = build(source.indexOf('italic') + 2);
    for (final marker in <String>['<strong>', '</strong>', '<em>', '</em>']) {
      expect(
        active.singleWhere((span) => span.text == marker).style?.fontSize,
        14,
        reason: marker,
      );
    }
    expect(
      active.singleWhere((span) => span.text == '<u>').style?.fontSize,
      .01,
    );
  });

  test(
    'combined strong emphasis keeps one reveal boundary and both styles',
    () {
      const syntax = IanvsMarkdownSyntaxTheme(
        heading: TextStyle(fontWeight: FontWeight.w600),
        marker: TextStyle(color: Color(0xff777777)),
        link: TextStyle(decoration: TextDecoration.underline),
        code: TextStyle(fontFamily: 'monospace'),
        comment: TextStyle(fontStyle: FontStyle.italic),
      );
      const base = TextStyle(fontSize: 14);
      const source = 'Nested ***bold italic*** tail';

      List<TextSpan> build(int caret) => buildMarkdownSourceTextSpan(
        TextEditingValue(
          text: source,
          selection: TextSelection.collapsed(offset: caret),
        ),
        style: base,
        syntaxTheme: syntax,
        withComposing: false,
        hideInactiveInlineMarkers: true,
      ).children!.cast<TextSpan>().toList();

      final inactive = build(0);
      final hiddenMarkers = inactive
          .where((span) => span.text == '***')
          .toList();
      expect(hiddenMarkers, hasLength(2));
      expect(
        hiddenMarkers.every((span) => span.style?.fontSize == .01),
        isTrue,
      );
      final content = inactive.singleWhere(
        (span) => span.text == 'bold italic',
      );
      expect(content.style?.fontWeight, FontWeight.w700);
      expect(content.style?.fontStyle, FontStyle.italic);

      final active = build(source.indexOf('italic'));
      final revealedMarkers = active
          .where((span) => span.text == '***')
          .toList();
      expect(revealedMarkers, hasLength(2));
      expect(
        revealedMarkers.every((span) => span.style?.fontSize == 14),
        isTrue,
      );
      expect(active.map((span) => span.text).join(), source);
    },
  );

  test('intraword single and double underscores stay literal', () {
    const syntax = IanvsMarkdownSyntaxTheme(
      heading: TextStyle(fontWeight: FontWeight.w600),
      marker: TextStyle(color: Color(0xff777777)),
      link: TextStyle(decoration: TextDecoration.underline),
      code: TextStyle(fontFamily: 'monospace'),
      comment: TextStyle(fontStyle: FontStyle.italic),
    );
    const source = 'foo_single_word foo__double__word a_short_c _standalone_';
    final spans = buildMarkdownSourceTextSpan(
      const TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: 0),
      ),
      style: const TextStyle(fontSize: 14),
      syntaxTheme: syntax,
      withComposing: false,
      hideInactiveInlineMarkers: true,
    ).children!.cast<TextSpan>().toList();

    TextSpan spanAt(int offset) {
      var cursor = 0;
      for (final span in spans) {
        final end = cursor + (span.text?.length ?? 0);
        if (offset >= cursor && offset < end) return span;
        cursor = end;
      }
      throw StateError('No span at $offset');
    }

    final single = source.indexOf('single');
    final double = source.indexOf('double');
    final short = source.indexOf('short');
    final standalone = source.indexOf('standalone');
    expect(spanAt(single).style?.fontStyle, isNull);
    expect(spanAt(short).style?.fontStyle, isNull);
    expect(spanAt(double).style?.fontWeight, isNull);
    expect(spanAt(standalone).style?.fontStyle, FontStyle.italic);
    expect(spanAt(single - 1).style?.fontSize, 14);
    expect(spanAt(short - 1).style?.fontSize, 14);
    expect(spanAt(double - 2).style?.fontSize, 14);
    expect(spanAt(standalone - 1).style?.fontSize, .01);
    expect(spans.map((span) => span.text).join(), source);
  });

  test('emphasis source ranges cover complete participating runs', () {
    const source =
        '***triple***\n\n'
        '****quad****\n\n'
        '***left**\n\n'
        'foo******deep*********baz\n\n'
        'foo__literal__baz\n\n'
        'a*"quoted"*';

    TextRange? rangeFor(String content) {
      final start = source.indexOf(content);
      return ianvsMarkdownInlineSourceRangeAt(
        source,
        TextRange(start: start, end: start + content.length),
      );
    }

    expect(rangeFor('triple')!.textInside(source), '***triple***');
    expect(rangeFor('quad')!.textInside(source), '****quad****');
    expect(rangeFor('left')!.textInside(source), '***left**');
    expect(rangeFor('deep')!.textInside(source), '******deep******');
    expect(rangeFor('literal'), isNull);
    expect(rangeFor('quoted'), isNull);
  });

  test(
    'nested inline syntax composes styles and keeps local reveal ranges',
    () {
      const syntax = IanvsMarkdownSyntaxTheme(
        heading: TextStyle(fontWeight: FontWeight.w600),
        marker: TextStyle(color: Color(0xff777777)),
        link: TextStyle(decoration: TextDecoration.underline),
        code: TextStyle(
          fontFamily: 'monospace',
          backgroundColor: Color(0xffeeeeee),
        ),
        comment: TextStyle(fontStyle: FontStyle.italic),
        strong: TextStyle(
          color: Color(0xffff0000),
          fontWeight: FontWeight.w700,
        ),
        emphasis: TextStyle(
          color: Color(0xffff8800),
          fontStyle: FontStyle.italic,
        ),
        highlight: TextStyle(backgroundColor: Color(0xffffe184)),
      );
      const base = TextStyle(fontSize: 14);
      const source =
          'Nested **outer *inner* strong tail**. '
          'Link [*bold label* and `code`](https://example.com/path). '
          'Mixed ~~strike ==highlight== deleted tail~~.';

      List<TextSpan> build(int caret) => buildMarkdownSourceTextSpan(
        TextEditingValue(
          text: source,
          selection: TextSelection.collapsed(offset: caret),
        ),
        style: base,
        syntaxTheme: syntax,
        withComposing: false,
        hideInactiveInlineMarkers: true,
      ).children!.cast<TextSpan>().toList();

      final inactive = build(0);
      TextSpan inactiveSpan(String text) =>
          inactive.singleWhere((span) => span.text == text);

      expect(inactiveSpan('outer ').style?.fontWeight, FontWeight.w700);
      expect(inactiveSpan('inner').style?.fontWeight, FontWeight.w700);
      expect(inactiveSpan('inner').style?.fontStyle, FontStyle.italic);
      expect(inactiveSpan(' strong tail').style?.fontWeight, FontWeight.w700);

      final linkLabel = inactiveSpan('bold label');
      expect(linkLabel.style?.fontStyle, FontStyle.italic);
      expect(linkLabel.style?.decoration, TextDecoration.underline);
      final linkCode = inactiveSpan('code');
      expect(linkCode.style?.fontFamily, 'monospace');
      expect(linkCode.style?.backgroundColor, const Color(0xffeeeeee));
      expect(linkCode.style?.decoration, TextDecoration.underline);

      expect(
        inactiveSpan('strike ').style?.decoration,
        TextDecoration.lineThrough,
      );
      final highlightedStrike = inactiveSpan('highlight');
      expect(
        highlightedStrike.style?.decoration?.contains(
          TextDecoration.lineThrough,
        ),
        isTrue,
      );
      expect(highlightedStrike.style?.backgroundColor, const Color(0xffffe184));
      expect(
        inactiveSpan(' deleted tail').style?.decoration,
        TextDecoration.lineThrough,
      );

      final hiddenMarkers = inactive.where(
        (span) => <String>{
          '**',
          '*',
          '[',
          '](https://example.com/path)',
          '~~',
          '==',
        }.contains(span.text),
      );
      expect(hiddenMarkers, isNotEmpty);
      expect(
        hiddenMarkers.every((span) => span.style?.fontSize == .01),
        isTrue,
      );
      expect(
        inactive
            .where((span) => span.text == '`')
            .every((span) => span.style?.fontSize == 14),
        isTrue,
      );

      final innerActive = build(source.indexOf('inner') + 2);
      final innerActiveMarkers = innerActive
          .where((span) => span.text == '**' || span.text == '*')
          .toList();
      expect(
        innerActiveMarkers.take(4).every((span) => span.style?.fontSize == 14),
        isTrue,
      );
      expect(
        innerActiveMarkers.skip(4).every((span) => span.style?.fontSize == .01),
        isTrue,
      );
      expect(
        innerActive
            .where((span) => span.text == '**')
            .take(2)
            .every((span) => span.style?.color == const Color(0xffff0000)),
        isTrue,
      );
      expect(
        innerActive
            .where((span) => span.text == '*')
            .take(2)
            .every((span) => span.style?.color == const Color(0xffff8800)),
        isTrue,
      );

      final codeActive = build(source.indexOf('code') + 2);
      expect(
        codeActive
            .where(
              (span) =>
                  span.text == '[' ||
                  span.text == '](https://example.com/path)' ||
                  span.text == '`',
            )
            .every((span) => span.style?.fontSize == 14),
        isTrue,
      );
      expect(
        codeActive
            .where((span) => span.text == '*')
            .every((span) => span.style?.fontSize == .01),
        isTrue,
      );
      expect(inactive.map((span) => span.text).join(), source);
    },
  );

  test('Wiki targets stay literal while aliases compose inline styles', () {
    const syntax = IanvsMarkdownSyntaxTheme(
      heading: TextStyle(),
      marker: TextStyle(color: Color(0xff777777)),
      link: TextStyle(),
      code: TextStyle(),
      comment: TextStyle(),
      wikiLink: TextStyle(fontWeight: FontWeight.w600),
      highlight: TextStyle(backgroundColor: Color(0xffffe184)),
    );
    const source = '[[L==before==]] [[Target|==alias==]]';
    final spans = buildMarkdownSourceTextSpan(
      const TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: 0),
      ),
      style: const TextStyle(fontSize: 14),
      syntaxTheme: syntax,
      withComposing: false,
      hideInactiveInlineMarkers: true,
    ).children!.cast<TextSpan>().toList();

    TextSpan spanAt(int offset) {
      var cursor = 0;
      for (final span in spans) {
        final end = cursor + (span.text?.length ?? 0);
        if (offset >= cursor && offset < end) return span;
        cursor = end;
      }
      throw StateError('No span at $offset');
    }

    final targetContent = source.indexOf('before');
    final targetEquals = source.indexOf('==');
    final aliasContent = source.indexOf('alias');
    expect(spanAt(targetContent).style?.backgroundColor, isNull);
    expect(spanAt(targetContent).style?.fontWeight, FontWeight.w600);
    expect(spanAt(targetEquals).style?.fontSize, 14);
    expect(
      spanAt(aliasContent).style?.backgroundColor,
      const Color(0xffffe184),
    );
    expect(
      ianvsMarkdownInlineSourceRangeAt(
        source,
        TextRange(start: targetContent, end: targetContent + 1),
      )?.textInside(source),
      '[[L==before==]]',
    );
    expect(
      ianvsMarkdownInlineSourceRangeAt(
        source,
        TextRange(start: aliasContent, end: aliasContent + 1),
      )?.textInside(source),
      '==alias==',
    );
  });

  test('link source ranges contain nested inline footnotes', () {
    const syntax = IanvsMarkdownSyntaxTheme(
      heading: TextStyle(),
      marker: TextStyle(color: Color(0xff777777)),
      link: TextStyle(decoration: TextDecoration.underline),
      code: TextStyle(),
      comment: TextStyle(fontStyle: FontStyle.italic),
    );
    const source =
        'Inline [link ^[note]](https://example.com).\n\n'
        'Reference [ref ^[other]][target].\n\n'
        '[target]: https://example.com';

    TextRange? rangeFor(String content) {
      final start = source.indexOf(content);
      return ianvsMarkdownInlineSourceRangeAt(
        source,
        TextRange(start: start, end: start + content.length),
      );
    }

    expect(
      rangeFor('link')?.textInside(source),
      '[link ^[note]](https://example.com)',
    );
    expect(rangeFor('ref')?.textInside(source), '[ref ^[other]][target]');

    final spans = buildMarkdownSourceTextSpan(
      const TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: 0),
      ),
      style: const TextStyle(fontSize: 14),
      syntaxTheme: syntax,
      withComposing: false,
      hideInactiveInlineMarkers: false,
    ).children!.cast<TextSpan>().toList();

    TextSpan spanAt(int offset) {
      var cursor = 0;
      for (final span in spans) {
        final end = cursor + (span.text?.length ?? 0);
        if (offset >= cursor && offset < end) return span;
        cursor = end;
      }
      throw StateError('No span at $offset');
    }

    expect(
      spanAt(source.indexOf('link')).style?.decoration,
      TextDecoration.underline,
    );
    final inlineFootnote = spanAt(source.indexOf('note'));
    expect(inlineFootnote.style?.decoration, TextDecoration.underline);
    expect(inlineFootnote.style?.fontStyle, FontStyle.italic);
    expect(
      spanAt(source.indexOf('ref')).style?.decoration,
      TextDecoration.underline,
    );
  });

  test('multiline delimited syntax keeps styles and reveals local markers', () {
    const syntax = IanvsMarkdownSyntaxTheme(
      heading: TextStyle(fontWeight: FontWeight.w600),
      marker: TextStyle(color: Color(0xff777777)),
      link: TextStyle(decoration: TextDecoration.underline),
      code: TextStyle(fontFamily: 'monospace'),
      comment: TextStyle(fontStyle: FontStyle.italic),
      strong: TextStyle(color: Color(0xffff0000), fontWeight: FontWeight.w700),
      emphasis: TextStyle(
        color: Color(0xffff8800),
        fontStyle: FontStyle.italic,
      ),
      strikethrough: TextStyle(decoration: TextDecoration.lineThrough),
      highlight: TextStyle(backgroundColor: Color(0xffffe184)),
    );
    const source =
        'Italic *italic one\nitalic two* tail.\n\n'
        'Strong **strong one\nstrong two** tail.\n\n'
        'Strike ~~strike one\nstrike two~~ tail.\n\n'
        'Highlight ==mark one\nmark two== tail.';

    List<TextSpan> build(int caret) => buildMarkdownSourceTextSpan(
      TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: caret),
      ),
      style: const TextStyle(fontSize: 14),
      syntaxTheme: syntax,
      withComposing: false,
      hideInactiveInlineMarkers: true,
    ).children!.cast<TextSpan>().toList();

    TextSpan spanAt(List<TextSpan> spans, int offset) {
      var cursor = 0;
      for (final span in spans) {
        final end = cursor + (span.text?.length ?? 0);
        if (offset >= cursor && offset < end) return span;
        cursor = end;
      }
      throw StateError('No span at $offset');
    }

    final formats = <({int opening, int closing, int first, int second})>[
      (
        opening: source.indexOf('*italic one'),
        closing: source.indexOf('* tail.'),
        first: source.indexOf('italic one'),
        second: source.indexOf('italic two'),
      ),
      (
        opening: source.indexOf('**strong one'),
        closing: source.indexOf('** tail.', source.indexOf('Strong')),
        first: source.indexOf('strong one'),
        second: source.indexOf('strong two'),
      ),
      (
        opening: source.indexOf('~~strike one'),
        closing: source.indexOf('~~ tail.'),
        first: source.indexOf('strike one'),
        second: source.indexOf('strike two'),
      ),
      (
        opening: source.indexOf('==mark one'),
        closing: source.indexOf('== tail.'),
        first: source.indexOf('mark one'),
        second: source.indexOf('mark two'),
      ),
    ];

    final inactive = build(0);
    for (final format in formats) {
      expect(spanAt(inactive, format.opening).style?.fontSize, .01);
      expect(spanAt(inactive, format.closing).style?.fontSize, .01);

      final firstLineActive = build(format.first);
      expect(spanAt(firstLineActive, format.opening).style?.fontSize, 14);
      expect(spanAt(firstLineActive, format.closing).style?.fontSize, .01);

      final secondLineActive = build(format.second);
      expect(spanAt(secondLineActive, format.opening).style?.fontSize, .01);
      expect(spanAt(secondLineActive, format.closing).style?.fontSize, 14);
    }

    expect(
      spanAt(inactive, source.indexOf('italic two')).style?.fontStyle,
      FontStyle.italic,
    );
    expect(
      spanAt(inactive, source.indexOf('italic two')).style?.color,
      const Color(0xffff8800),
    );
    expect(
      spanAt(inactive, source.indexOf('strong two')).style?.fontWeight,
      FontWeight.w700,
    );
    expect(
      spanAt(inactive, source.indexOf('strong two')).style?.color,
      const Color(0xffff0000),
    );
    expect(
      spanAt(inactive, source.indexOf('strike two')).style?.decoration,
      TextDecoration.lineThrough,
    );
    expect(
      spanAt(inactive, source.indexOf('mark two')).style?.backgroundColor,
      const Color(0xffffe184),
    );
    expect(inactive.map((span) => span.text).join(), source);
  });

  test('delimited syntax never crosses a Markdown paragraph break', () {
    const syntax = IanvsMarkdownSyntaxTheme(
      heading: TextStyle(fontWeight: FontWeight.w600),
      marker: TextStyle(color: Color(0xff777777)),
      link: TextStyle(decoration: TextDecoration.underline),
      code: TextStyle(fontFamily: 'monospace'),
      comment: TextStyle(fontStyle: FontStyle.italic),
    );
    const source = 'Before **first\n\nsecond** after.';
    final spans = buildMarkdownSourceTextSpan(
      const TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: 0),
      ),
      style: const TextStyle(fontSize: 14),
      syntaxTheme: syntax,
      withComposing: false,
      hideInactiveInlineMarkers: true,
    ).children!.cast<TextSpan>().toList();

    TextSpan spanAt(int offset) {
      var cursor = 0;
      for (final span in spans) {
        final end = cursor + (span.text?.length ?? 0);
        if (offset >= cursor && offset < end) return span;
        cursor = end;
      }
      throw StateError('No span at $offset');
    }

    expect(spanAt(source.indexOf('first')).style?.fontWeight, isNull);
    expect(spanAt(source.indexOf('second')).style?.fontWeight, isNull);
    expect(spanAt(source.indexOf('**')).style?.fontSize, 14);
    expect(spans.map((span) => span.text).join(), source);
  });

  test('escaped inline delimiters remain literal source', () {
    const syntax = IanvsMarkdownSyntaxTheme(
      heading: TextStyle(fontWeight: FontWeight.w600),
      marker: TextStyle(color: Color(0xff777777)),
      link: TextStyle(decoration: TextDecoration.underline),
      code: TextStyle(fontFamily: 'monospace'),
      comment: TextStyle(fontStyle: FontStyle.italic),
    );
    const source = r'Escaped \*\*not bold\*\* and \`not code\`.';

    final spans = buildMarkdownSourceTextSpan(
      const TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: 0),
      ),
      style: const TextStyle(fontSize: 14),
      syntaxTheme: syntax,
      withComposing: false,
      hideInactiveInlineMarkers: true,
    ).children!.cast<TextSpan>().toList();

    expect(spans, hasLength(1));
    expect(spans.single.text, source);
    expect(spans.single.style?.fontSize, 14);
    expect(spans.single.style?.fontWeight, isNull);
    expect(spans.single.style?.fontFamily, isNull);
  });

  test('inactive escape markers follow consecutive backslash parity', () {
    const syntax = IanvsMarkdownSyntaxTheme(
      heading: TextStyle(fontWeight: FontWeight.w600),
      marker: TextStyle(color: Color(0xff777777)),
      link: TextStyle(decoration: TextDecoration.underline),
      code: TextStyle(fontFamily: 'monospace'),
      comment: TextStyle(fontStyle: FontStyle.italic),
    );
    const source =
        r'one \*literal* two \\*emphasis* three \\\*literal* end \\\\';
    final spans = buildMarkdownSourceTextSpan(
      const TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: -1),
      ),
      style: const TextStyle(fontSize: 14),
      syntaxTheme: syntax,
      withComposing: false,
      hideInactiveInlineMarkers: true,
      hideInactiveEscapeMarkers: true,
    ).children!.cast<TextSpan>().toList();

    TextSpan spanAt(int offset) {
      var cursor = 0;
      for (final span in spans) {
        final end = cursor + (span.text?.length ?? 0);
        if (offset >= cursor && offset < end) return span;
        cursor = end;
      }
      throw StateError('No span at $offset');
    }

    final single = source.indexOf(r'\*literal');
    expect(spanAt(single).style?.fontSize, .01);

    final double = source.indexOf(r'\\*emphasis');
    expect(spanAt(double).style?.fontSize, .01);
    expect(spanAt(double + 1).style?.fontSize, 14);

    final triple = source.indexOf(r'\\\*literal');
    expect(spanAt(triple).style?.fontSize, .01);
    expect(spanAt(triple + 1).style?.fontSize, 14);
    expect(spanAt(triple + 2).style?.fontSize, .01);
    expect(spanAt(triple + 3).style?.fontSize, 14);

    final trailing = source.lastIndexOf(r'\\\\');
    expect(spanAt(trailing).style?.fontSize, .01);
    expect(spanAt(trailing + 1).style?.fontSize, 14);
    expect(spanAt(trailing + 2).style?.fontSize, .01);
    expect(spanAt(trailing + 3).style?.fontSize, 14);
  });

  test(
    'inline code follows backtick runs and keeps nested Markdown literal',
    () {
      const syntax = IanvsMarkdownSyntaxTheme(
        heading: TextStyle(fontWeight: FontWeight.w600),
        marker: TextStyle(color: Color(0xff777777)),
        link: TextStyle(decoration: TextDecoration.underline),
        code: TextStyle(
          fontFamily: 'monospace',
          backgroundColor: Color(0xffeeeeee),
        ),
        comment: TextStyle(fontStyle: FontStyle.italic),
        highlight: TextStyle(backgroundColor: Color(0xffffe184)),
      );
      const source =
          'Inner ``code with ` tick``. '
          'Literal ``**bold** and [link](docs.md) and ==mark==``. '
          'Padded ` code `. Adjacent `one``two`.';

      List<TextSpan> build(int caret) => buildMarkdownSourceTextSpan(
        TextEditingValue(
          text: source,
          selection: TextSelection.collapsed(offset: caret),
        ),
        style: const TextStyle(fontSize: 14),
        syntaxTheme: syntax,
        withComposing: false,
        hideInactiveInlineMarkers: true,
      ).children!.cast<TextSpan>().toList();

      TextSpan spanAt(List<TextSpan> spans, int offset) {
        var cursor = 0;
        for (final span in spans) {
          final end = cursor + (span.text?.length ?? 0);
          if (offset >= cursor && offset < end) return span;
          cursor = end;
        }
        throw StateError('No span at $offset');
      }

      final inactive = build(0);
      final innerContent = inactive.singleWhere(
        (span) => span.text == 'code with ` tick',
      );
      expect(innerContent.style?.fontFamily, 'monospace');
      expect(innerContent.style?.backgroundColor, const Color(0xffeeeeee));
      final literalContent = inactive.singleWhere(
        (span) => span.text == '**bold** and [link](docs.md) and ==mark==',
      );
      expect(literalContent.style?.fontFamily, 'monospace');
      expect(literalContent.style?.decoration, isNull);
      expect(
        inactive
            .where((span) => span.text == '``')
            .every((span) => span.style?.fontSize == 14),
        isTrue,
      );

      final paddedOpen = source.indexOf('` code `');
      expect(spanAt(inactive, paddedOpen).style?.fontSize, 14);
      expect(spanAt(inactive, paddedOpen + 1).style?.fontSize, .01);
      expect(spanAt(inactive, paddedOpen + 2).style?.fontFamily, 'monospace');
      expect(spanAt(inactive, paddedOpen + 6).style?.fontSize, .01);
      expect(spanAt(inactive, paddedOpen + 7).style?.fontSize, 14);

      final adjacentOne = source.indexOf('one');
      expect(spanAt(inactive, adjacentOne).text, 'one``two');
      expect(spanAt(inactive, adjacentOne).style?.fontFamily, 'monospace');

      final active = build(source.indexOf('tick'));
      final activeOuterMarkers = active
          .where((span) => span.text == '``')
          .take(2);
      expect(
        activeOuterMarkers.every((span) => span.style?.fontSize == 14),
        isTrue,
      );
      expect(
        active
            .singleWhere((span) => span.text == 'code with ` tick')
            .style
            ?.fontFamily,
        'monospace',
      );
      expect(inactive.map((span) => span.text).join(), source);
      final word = source.indexOf('code with');
      expect(
        ianvsMarkdownInlineSourceRangeAt(
          source,
          TextRange(start: word, end: word + 4),
        ),
        isNull,
      );
    },
  );

  test('multiline inline code keeps styling and visible markers', () {
    const syntax = IanvsMarkdownSyntaxTheme(
      heading: TextStyle(fontWeight: FontWeight.w600),
      marker: TextStyle(color: Color(0xff777777)),
      link: TextStyle(decoration: TextDecoration.underline),
      code: TextStyle(
        fontFamily: 'monospace',
        backgroundColor: Color(0xffeeeeee),
      ),
      comment: TextStyle(fontStyle: FontStyle.italic),
    );
    const source = 'Before `line one\nline two` after.';
    final opening = source.indexOf('`');
    final closing = source.lastIndexOf('`');

    List<TextSpan> build(int caret) => buildMarkdownSourceTextSpan(
      TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: caret),
      ),
      style: const TextStyle(fontSize: 14),
      syntaxTheme: syntax,
      withComposing: false,
      hideInactiveInlineMarkers: true,
    ).children!.cast<TextSpan>().toList();

    TextSpan spanAt(List<TextSpan> spans, int offset) {
      var cursor = 0;
      for (final span in spans) {
        final end = cursor + (span.text?.length ?? 0);
        if (offset >= cursor && offset < end) return span;
        cursor = end;
      }
      throw StateError('No span at $offset');
    }

    final inactive = build(0);
    expect(spanAt(inactive, opening).style?.fontSize, 14);
    expect(spanAt(inactive, closing).style?.fontSize, 14);
    expect(
      spanAt(inactive, source.indexOf('line one')).style?.fontFamily,
      'monospace',
    );
    expect(
      spanAt(inactive, source.indexOf('line two')).style?.fontFamily,
      'monospace',
    );

    final firstLineActive = build(source.indexOf('one'));
    expect(spanAt(firstLineActive, opening).style?.fontSize, 14);
    expect(spanAt(firstLineActive, closing).style?.fontSize, 14);

    final secondLineActive = build(source.indexOf('two'));
    expect(spanAt(secondLineActive, opening).style?.fontSize, 14);
    expect(spanAt(secondLineActive, closing).style?.fontSize, 14);
    expect(inactive.map((span) => span.text).join(), source);
  });

  test('inline math keeps native word selection and exposes exact ranges', () {
    const source =
        r'Alpha $bravo + charlie$ omega and `literal $not_math$ code`.';
    final matches = ianvsMarkdownInlineMathSources(source);

    expect(matches, hasLength(1));
    expect(matches.single.sourceRange.textInside(source), r'$bravo + charlie$');
    expect(matches.single.contentRange.textInside(source), 'bravo + charlie');
    expect(matches.single.delimiterLength, 1);
    final bravo = source.indexOf('bravo');
    expect(
      ianvsMarkdownInlineSourceRangeAt(
        source,
        TextRange(start: bravo, end: bravo + 5),
      ),
      isNull,
    );
  });

  test('escaped first backtick leaves the remaining run as code', () {
    const syntax = IanvsMarkdownSyntaxTheme(
      heading: TextStyle(fontWeight: FontWeight.w600),
      marker: TextStyle(color: Color(0xff777777)),
      link: TextStyle(decoration: TextDecoration.underline),
      code: TextStyle(fontFamily: 'monospace'),
      comment: TextStyle(fontStyle: FontStyle.italic),
    );
    const source = r'''\``^[code]` and ^[visible]''';
    final spans = buildMarkdownSourceTextSpan(
      const TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: 0),
      ),
      style: const TextStyle(fontSize: 14),
      syntaxTheme: syntax,
      withComposing: false,
      hideInactiveInlineMarkers: true,
    ).children!.cast<TextSpan>().toList();

    TextSpan spanAt(int offset) {
      var cursor = 0;
      for (final span in spans) {
        final end = cursor + (span.text?.length ?? 0);
        if (offset >= cursor && offset < end) return span;
        cursor = end;
      }
      throw StateError('No span at $offset');
    }

    expect(spanAt(source.indexOf('^[code]')).style?.fontFamily, 'monospace');
    expect(
      spanAt(source.indexOf('^[code]')).style?.fontStyle,
      isNot(FontStyle.italic),
    );
    expect(
      spanAt(source.indexOf('^[visible]')).style?.fontStyle,
      FontStyle.italic,
    );
    expect(spans.map((span) => span.text).join(), source);
  });

  test('inline code never crosses a Markdown paragraph break', () {
    const syntax = IanvsMarkdownSyntaxTheme(
      heading: TextStyle(fontWeight: FontWeight.w600),
      marker: TextStyle(color: Color(0xff777777)),
      link: TextStyle(decoration: TextDecoration.underline),
      code: TextStyle(fontFamily: 'monospace'),
      comment: TextStyle(fontStyle: FontStyle.italic),
    );
    const source = 'Before `open.\n\nAfter `close`.';

    final spans = buildMarkdownSourceTextSpan(
      const TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: 0),
      ),
      style: const TextStyle(fontSize: 14),
      syntaxTheme: syntax,
      withComposing: false,
      hideInactiveInlineMarkers: true,
    ).children!.cast<TextSpan>().toList();

    TextSpan spanAt(int offset) {
      var cursor = 0;
      for (final span in spans) {
        final end = cursor + (span.text?.length ?? 0);
        if (offset >= cursor && offset < end) return span;
        cursor = end;
      }
      throw StateError('No span at $offset');
    }

    expect(spanAt(source.indexOf('open')).style?.fontFamily, isNull);
    expect(spanAt(source.indexOf('close')).style?.fontFamily, 'monospace');
  });

  test('Markdown links keep balanced and escaped destinations together', () {
    const syntax = IanvsMarkdownSyntaxTheme(
      heading: TextStyle(fontWeight: FontWeight.w600),
      marker: TextStyle(color: Color(0xff777777)),
      link: TextStyle(decoration: TextDecoration.underline),
      code: TextStyle(fontFamily: 'monospace'),
      comment: TextStyle(fontStyle: FontStyle.italic),
    );
    const source =
        'Paren [balanced](https://example.com/a_(b)) tail. '
        'Nested [deep](https://example.com/a_(b_(c))) tail. '
        r'Escaped [escaped](https://example.com/a\)b) tail. '
        'Title [*titled* and `code`](docs.md "Hover (title)") tail. '
        'Image ![alt](image_(1).png "Caption") tail. '
        'Broken [broken](docs_(x) tail.';

    List<TextSpan> build(int caret) => buildMarkdownSourceTextSpan(
      TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: caret),
      ),
      style: const TextStyle(fontSize: 14),
      syntaxTheme: syntax,
      withComposing: false,
      hideInactiveInlineMarkers: true,
    ).children!.cast<TextSpan>().toList();

    TextSpan spanAt(List<TextSpan> spans, int offset) {
      var cursor = 0;
      for (final span in spans) {
        final end = cursor + (span.text?.length ?? 0);
        if (offset >= cursor && offset < end) return span;
        cursor = end;
      }
      throw StateError('No span at $offset');
    }

    final inactive = build(0);
    for (final suffix in <String>[
      '](https://example.com/a_(b))',
      '](https://example.com/a_(b_(c)))',
      r'](https://example.com/a\)b)',
      '](docs.md "Hover (title)")',
      '](image_(1).png "Caption")',
    ]) {
      expect(
        inactive.singleWhere((span) => span.text == suffix).style?.fontSize,
        .01,
      );
    }
    expect(
      inactive.singleWhere((span) => span.text == '![').style?.fontSize,
      .01,
    );
    expect(
      inactive.singleWhere((span) => span.text == 'titled').style?.fontStyle,
      FontStyle.italic,
    );
    expect(
      inactive.singleWhere((span) => span.text == 'titled').style?.decoration,
      TextDecoration.underline,
    );
    expect(
      inactive.singleWhere((span) => span.text == 'code').style?.fontFamily,
      'monospace',
    );
    expect(
      inactive.singleWhere((span) => span.text == 'code').style?.decoration,
      TextDecoration.underline,
    );

    final brokenOffset = source.indexOf('broken');
    expect(spanAt(inactive, brokenOffset).style?.decoration, isNull);

    final balancedStart = source.indexOf('[balanced]');
    final active = build(source.indexOf('balanced') + 2);
    expect(spanAt(active, balancedStart).style?.fontSize, 14);
    expect(
      active
          .singleWhere((span) => span.text == '](https://example.com/a_(b))')
          .style
          ?.fontSize,
      14,
    );
    expect(
      active
          .singleWhere(
            (span) => span.text == '](https://example.com/a_(b_(c)))',
          )
          .style
          ?.fontSize,
      .01,
    );
    expect(inactive.map((span) => span.text).join(), source);
  });

  test(
    'Markdown link source styling validates titles and soft-line whitespace',
    () {
      const syntax = IanvsMarkdownSyntaxTheme(
        heading: TextStyle(fontWeight: FontWeight.w600),
        marker: TextStyle(color: Color(0xff777777)),
        link: TextStyle(decoration: TextDecoration.underline),
        code: TextStyle(fontFamily: 'monospace'),
        comment: TextStyle(fontStyle: FontStyle.italic),
      );
      const source =
          'Empty []() tail.\n'
          'Soft [soft](https://example.com\n"soft title") tail.\n'
          'Unclosed [unclosed](https://example.com "title) tail.\n'
          'Trailing [trailing](https://example.com "title" mystery) tail.';

      List<TextSpan> build(int caret) => buildMarkdownSourceTextSpan(
        TextEditingValue(
          text: source,
          selection: TextSelection.collapsed(offset: caret),
        ),
        style: const TextStyle(fontSize: 14),
        syntaxTheme: syntax,
        withComposing: false,
        hideInactiveInlineMarkers: true,
      ).children!.cast<TextSpan>().toList();

      TextSpan spanAt(List<TextSpan> spans, int offset) {
        var cursor = 0;
        for (final span in spans) {
          final end = cursor + (span.text?.length ?? 0);
          if (offset >= cursor && offset < end) return span;
          cursor = end;
        }
        throw StateError('No span at $offset');
      }

      final inactive = build(0);
      final emptyStart = source.indexOf('[]()');
      expect(spanAt(inactive, emptyStart).style?.fontSize, .01);
      expect(spanAt(inactive, emptyStart + 3).style?.fontSize, .01);

      final softStart = source.indexOf('[soft]');
      final softLabel = source.indexOf('soft', softStart);
      final softEnd = source.indexOf('")', softLabel) + 2;
      expect(
        spanAt(inactive, softLabel).style?.decoration,
        TextDecoration.underline,
      );
      expect(spanAt(inactive, softStart).style?.fontSize, .01);
      expect(spanAt(inactive, softEnd - 1).style?.fontSize, .01);
      expect(
        ianvsMarkdownInlineSourceRangeAt(
          source,
          TextRange(start: softLabel, end: softLabel + 4),
        )?.textInside(source),
        source.substring(softStart, softEnd),
      );

      expect(
        spanAt(inactive, source.indexOf('unclosed')).style?.decoration,
        isNull,
      );
      expect(
        spanAt(inactive, source.indexOf('trailing')).style?.decoration,
        isNull,
      );

      final active = build(softLabel + 1);
      expect(spanAt(active, softStart).style?.fontSize, 14);
      expect(spanAt(active, softEnd - 1).style?.fontSize, 14);
      expect(inactive.map((span) => span.text).join(), source);
    },
  );

  test(
    'reference links resolve document definitions before hiding markers',
    () {
      const syntax = IanvsMarkdownSyntaxTheme(
        heading: TextStyle(fontWeight: FontWeight.w600),
        marker: TextStyle(color: Color(0xff777777)),
        link: TextStyle(decoration: TextDecoration.underline),
        code: TextStyle(fontFamily: 'monospace'),
        comment: TextStyle(fontStyle: FontStyle.italic),
      );
      const source =
          'Full [Reference label][guide-ref]. '
          'Collapsed [Collapsed][]. Shortcut [shortcut]. '
          'Image ![Preview][guide-ref]. Undefined [Missing][unknown].\n\n'
          '- [x] complete\n\n'
          '[guide-ref]: docs/guide.md "Reference title"\n'
          '[Collapsed]: docs/collapsed.md\n'
          '[SHORTCUT]: docs/shortcut.md';

      List<TextSpan> build(int caret) => buildMarkdownSourceTextSpan(
        TextEditingValue(
          text: source,
          selection: TextSelection.collapsed(offset: caret),
        ),
        style: const TextStyle(fontSize: 14),
        syntaxTheme: syntax,
        withComposing: false,
        hideInactiveInlineMarkers: true,
      ).children!.cast<TextSpan>().toList();

      TextSpan spanAt(List<TextSpan> spans, int offset) {
        var cursor = 0;
        for (final span in spans) {
          final end = cursor + (span.text?.length ?? 0);
          if (offset >= cursor && offset < end) return span;
          cursor = end;
        }
        throw StateError('No span at $offset');
      }

      final inactive = build(0);
      for (final location in <String>[
        '[Reference label',
        '[Collapsed]',
        '[shortcut]',
        '[Preview]',
      ]) {
        expect(
          spanAt(inactive, source.indexOf(location) + 1).style?.decoration,
          TextDecoration.underline,
          reason: location,
        );
      }
      for (final marker in <String>['[Reference label', '][guide-ref]']) {
        expect(
          spanAt(inactive, source.indexOf(marker)).style?.fontSize,
          .01,
          reason: marker,
        );
      }
      expect(
        spanAt(inactive, source.indexOf('Missing')).style?.decoration,
        isNull,
      );
      expect(
        spanAt(inactive, source.indexOf('[x]') + 1).style?.decoration,
        isNull,
      );
      expect(
        spanAt(inactive, source.indexOf('[guide-ref]:')).style?.fontSize,
        14,
      );

      final active = build(source.indexOf('Reference label') + 2);
      expect(
        spanAt(active, source.indexOf('[Reference label')).style?.fontSize,
        14,
      );
      expect(
        spanAt(active, source.indexOf('][guide-ref]')).style?.fontSize,
        14,
      );
      expect(inactive.map((span) => span.text).join(), source);
    },
  );

  test('Obsidian autolinks share boundaries and hide angle wrappers', () {
    const syntax = IanvsMarkdownSyntaxTheme(
      heading: TextStyle(fontWeight: FontWeight.w600),
      marker: TextStyle(color: Color(0xff777777)),
      link: TextStyle(decoration: TextDecoration.underline),
      code: TextStyle(fontFamily: 'monospace'),
      comment: TextStyle(fontStyle: FontStyle.italic),
      tag: TextStyle(fontWeight: FontWeight.w600),
    );
    const source =
        'Bare https://bare.example/path?x=1#frag tail. '
        'WWW www.web.example/path tail. '
        'Email user@mail.example tail. '
        'Angle <https://angle.example/a_(b)> tail. '
        'Angle WWW <www.angle-www.example/path> tail. '
        r'Escaped \<https://escaped.example/path> tail. '
        'Mixed https://punct.example/a_(b).,;:!? tail. '
        'Bracket https://bracket.example/a] tail. '
        'Chinese https://cn.example/路径。， tail. '
        'Quote "https://quote.example/path" tail. '
        'Word prefixhttps://word.example/path tail. '
        'Code `https://code.example/path` tail.';

    List<TextSpan> build(int caret, {bool hideMarkers = true}) =>
        buildMarkdownSourceTextSpan(
          TextEditingValue(
            text: source,
            selection: TextSelection.collapsed(offset: caret),
          ),
          style: const TextStyle(fontSize: 14),
          syntaxTheme: syntax,
          withComposing: false,
          hideInactiveInlineMarkers: hideMarkers,
        ).children!.cast<TextSpan>().toList();

    TextSpan spanAt(List<TextSpan> spans, int offset) {
      var cursor = 0;
      for (final span in spans) {
        final end = cursor + (span.text?.length ?? 0);
        if (offset >= cursor && offset < end) return span;
        cursor = end;
      }
      throw StateError('No span at $offset');
    }

    final angleUrl = source.indexOf('https://angle.example');
    final inactive = build(angleUrl + 4);
    for (final link in <String>[
      'https://bare.example/path?x=1#frag',
      'www.web.example/path',
      'user@mail.example',
      'https://angle.example/a_(b)',
      'www.angle-www.example/path>',
      'https://escaped.example/path',
      'https://punct.example/a_(b)',
      'https://bracket.example/a]',
      'https://cn.example/路径。，',
      'https://quote.example/path"',
      'https://word.example/path',
    ]) {
      expect(
        spanAt(inactive, source.indexOf(link) + 2).style?.decoration,
        TextDecoration.underline,
        reason: link,
      );
    }
    expect(spanAt(inactive, source.indexOf('#frag')).style?.fontWeight, isNull);

    final mixed = source.indexOf('https://punct.example');
    final period = source.indexOf('.', source.indexOf(')', mixed));
    final comma = source.indexOf(',', mixed);
    expect(spanAt(inactive, period).style?.decoration, isNull);
    expect(spanAt(inactive, comma).style?.decoration, isNull);
    expect(spanAt(inactive, comma + 1).style?.decoration, isNull);

    final angleOpen = angleUrl - 1;
    final angleClose = source.indexOf('>', angleUrl);
    expect(spanAt(inactive, angleOpen).style?.fontSize, .01);
    expect(spanAt(inactive, angleClose).style?.fontSize, .01);
    final angleWww = source.indexOf('www.angle-www.example');
    expect(spanAt(inactive, angleWww - 1).style?.fontSize, 14);
    expect(
      spanAt(inactive, source.indexOf('>', angleWww)).style?.decoration,
      TextDecoration.underline,
    );
    final escapedUrl = source.indexOf('https://escaped.example');
    expect(spanAt(inactive, escapedUrl - 1).style?.fontSize, .01);
    expect(spanAt(inactive, escapedUrl - 2).style?.fontSize, 14);
    expect(
      spanAt(inactive, source.indexOf('prefix')).style?.decoration,
      isNull,
    );

    final codeUrl = source.indexOf('https://code.example');
    expect(spanAt(inactive, codeUrl).style?.fontFamily, 'monospace');
    expect(spanAt(inactive, codeUrl).style?.decoration, isNull);

    final sourceMode = build(angleUrl + 4, hideMarkers: false);
    expect(spanAt(sourceMode, angleOpen).style?.fontSize, 14);
    expect(spanAt(sourceMode, angleClose).style?.fontSize, 14);
    expect(inactive.map((span) => span.text).join(), source);
  });

  test('source styling distinguishes Setext titles from their underlines', () {
    const syntax = IanvsMarkdownSyntaxTheme(
      heading: TextStyle(color: Color(0xff222222), fontWeight: FontWeight.w600),
      marker: TextStyle(color: Color(0xff777777)),
      link: TextStyle(decoration: TextDecoration.underline),
      code: TextStyle(fontFamily: 'monospace'),
      comment: TextStyle(fontStyle: FontStyle.italic),
    );
    const source =
        'Setext one\n==========\n\n'
        'Setext two\n----------\n\n'
        'Multiline first\nMultiline second\n----------';
    final spans = buildMarkdownSourceTextSpan(
      const TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: 0),
      ),
      style: const TextStyle(fontSize: 14),
      syntaxTheme: syntax,
      withComposing: false,
    ).children!.cast<TextSpan>().toList();

    for (final title in <String>['Setext one', 'Setext two']) {
      expect(
        spans.singleWhere((span) => span.text == title).style?.fontWeight,
        FontWeight.w600,
      );
    }
    for (final underline in <String>['==========', '----------']) {
      expect(
        spans.firstWhere((span) => span.text == underline).style?.color,
        const Color(0xff777777),
      );
    }
    TextSpan spanAt(int offset) {
      var cursor = 0;
      for (final span in spans) {
        final end = cursor + (span.text?.length ?? 0);
        if (offset >= cursor && offset < end) return span;
        cursor = end;
      }
      throw StateError('No span at $offset');
    }

    expect(
      spanAt(source.indexOf('Multiline first')).style?.fontWeight,
      FontWeight.w600,
    );
    expect(
      spanAt(source.indexOf('Multiline second')).style?.fontWeight,
      FontWeight.w600,
    );
    expect(
      spanAt(source.lastIndexOf('----------')).style?.color,
      const Color(0xff777777),
    );
  });

  test('live source styles Obsidian editing metadata without hiding it', () {
    const syntax = IanvsMarkdownSyntaxTheme(
      heading: TextStyle(fontWeight: FontWeight.w600),
      marker: TextStyle(color: Color(0xff777777)),
      link: TextStyle(decoration: TextDecoration.underline),
      code: TextStyle(fontFamily: 'monospace'),
      comment: TextStyle(color: Color(0xff555555), fontStyle: FontStyle.italic),
      highlight: TextStyle(backgroundColor: Color(0xffffe184)),
    );
    const source = '''
Visible %%secret%% text. ^block-id

Reference[^1], inline ^[footnote body], empty ^[], and nested ^[outer ^[inner]].
%%
Hidden **source** block.
%%
''';

    final spans = buildMarkdownSourceTextSpan(
      const TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: 0),
      ),
      style: const TextStyle(fontSize: 14),
      syntaxTheme: syntax,
      withComposing: false,
      hideInactiveInlineMarkers: true,
    ).children!.cast<TextSpan>().toList();

    for (final metadata in <String>[
      '%%secret%%',
      ' ^block-id',
      '[^1]',
      '^[footnote body]',
      '^[]',
      '^[outer ^[inner]]',
      '%%\nHidden **source** block.\n%%',
    ]) {
      final span = spans.singleWhere((candidate) => candidate.text == metadata);
      expect(span.style?.color, const Color(0xff555555));
      expect(span.style?.fontSize, 14);
    }
  });

  test('live source comments require pairs and yield to code and escapes', () {
    const syntax = IanvsMarkdownSyntaxTheme(
      heading: TextStyle(),
      marker: TextStyle(),
      link: TextStyle(),
      code: TextStyle(fontFamily: 'monospace'),
      comment: TextStyle(color: Color(0xff555555)),
    );
    const source =
        'paired %%secret%%; '
        r'escaped \%%literal%%; '
        'code `%%code%%`; unclosed %% tail';

    final spans = buildMarkdownSourceTextSpan(
      const TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: 0),
      ),
      style: const TextStyle(fontSize: 14),
      syntaxTheme: syntax,
      withComposing: false,
    ).children!.cast<TextSpan>().toList();

    expect(
      spans.singleWhere((span) => span.text == '%%secret%%').style?.color,
      const Color(0xff555555),
    );
    expect(
      spans
          .where((span) => span.style?.color == const Color(0xff555555))
          .map((span) => span.text),
      <String>['%%secret%%'],
    );
    expect(
      spans.singleWhere((span) => span.text == '%%code%%').style?.fontFamily,
      'monospace',
    );
  });

  test('live source comments yield to true indented code blocks', () {
    const syntax = IanvsMarkdownSyntaxTheme(
      heading: TextStyle(),
      marker: TextStyle(),
      link: TextStyle(),
      code: TextStyle(fontFamily: 'monospace'),
      comment: TextStyle(color: Color(0xff555555)),
    );
    const source = '''
paired %%secret%%

    code %%inside%% tail
''';

    final spans = buildMarkdownSourceTextSpan(
      const TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: 0),
      ),
      style: const TextStyle(fontSize: 14),
      syntaxTheme: syntax,
      withComposing: false,
    ).children!.cast<TextSpan>().toList();

    expect(spans.map((span) => span.text).join(), source);
    expect(
      spans
          .where((span) => span.style?.color == const Color(0xff555555))
          .map((span) => span.text),
      <String>['%%secret%%'],
    );
  });

  test('live source footnotes yield to true indented code blocks', () {
    const syntax = IanvsMarkdownSyntaxTheme(
      heading: TextStyle(),
      marker: TextStyle(),
      link: TextStyle(),
      code: TextStyle(fontFamily: 'monospace'),
      comment: TextStyle(color: Color(0xff555555)),
    );
    const source = '''
    code ^[inside] and [^inside]

Outside ^[outside] and [^outside].
''';

    final spans = buildMarkdownSourceTextSpan(
      const TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: 0),
      ),
      style: const TextStyle(fontSize: 14),
      syntaxTheme: syntax,
      withComposing: false,
    ).children!.cast<TextSpan>().toList();

    expect(spans.map((span) => span.text).join(), source);
    final metadata = spans
        .where((span) => span.style?.color == const Color(0xff555555))
        .map((span) => span.text)
        .join();
    expect(metadata, contains('^[outside]'));
    expect(metadata, contains('[^outside]'));
    expect(metadata, isNot(contains('^[inside]')));
    expect(metadata, isNot(contains('[^inside]')));
  });

  test('live source metadata yields to code inside block quotes', () {
    const syntax = IanvsMarkdownSyntaxTheme(
      heading: TextStyle(),
      marker: TextStyle(color: Color(0xff777777)),
      link: TextStyle(),
      code: TextStyle(fontFamily: 'monospace'),
      comment: TextStyle(color: Color(0xff555555)),
    );
    const source = '''
>     code ^[inside] and [^inside] %%inside%% ^inside-id
>
> ```md
> fenced ^[fenced] and [^fenced] %%fenced%% ^fenced-id
> ```
>
> >     nested ^[nested] and [^nested] %%nested%% ^nested-id
>
> - item
>
>       list code ^[list] and [^list] %%list%% ^list-id

Outside ^[outside] and [^outside] %%outside%% ^outside-id
''';

    final spans = buildMarkdownSourceTextSpan(
      const TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: 0),
      ),
      style: const TextStyle(fontSize: 14),
      syntaxTheme: syntax,
      withComposing: false,
    ).children!.cast<TextSpan>().toList();

    expect(spans.map((span) => span.text).join(), source);
    final metadata = spans
        .where((span) => span.style?.color == const Color(0xff555555))
        .map((span) => span.text)
        .join();
    expect(
      spans
          .where((span) => span.style?.color == const Color(0xff777777))
          .map((span) => span.text)
          .where((text) => text?.startsWith('>') ?? false),
      hasLength(5),
    );
    for (final outside in <String>[
      '^[outside]',
      '[^outside]',
      '%%outside%%',
      ' ^outside-id',
    ]) {
      expect(metadata, contains(outside));
    }
    for (final inside in <String>[
      '^[inside]',
      '[^inside]',
      '%%inside%%',
      '^inside-id',
      '^[fenced]',
      '[^fenced]',
      '%%fenced%%',
      '^fenced-id',
      '^[nested]',
      '[^nested]',
      '%%nested%%',
      '^nested-id',
      '^[list]',
      '[^list]',
      '%%list%%',
      '^list-id',
    ]) {
      expect(metadata, isNot(contains(inside)));
    }
  });

  test('live source metadata yields to code inside list items', () {
    const syntax = IanvsMarkdownSyntaxTheme(
      heading: TextStyle(),
      marker: TextStyle(color: Color(0xff777777)),
      link: TextStyle(),
      code: TextStyle(fontFamily: 'monospace'),
      comment: TextStyle(color: Color(0xff555555)),
    );
    const source = '''
1.     ordered ^[ordered] and [^inside] %%ordered%% ^ordered-id
-
      empty ^[empty] and [^inside] %%empty%% ^empty-id
-
  -
        nested ^[nested] and [^inside] %%nested%% ^nested-id
- quote
  >     quoted ^[quoted] and [^inside] %%quoted%% ^quoted-id
-\t\tTabbed ^[tabbed] and [^inside] %%tabbed%% ^tabbed-id
- ```md
  fenced ^[fenced] and [^inside] %%fenced%% ^fenced-id
  ```

Outside ^[outside] and [^outside] %%outside%% ^outside-id
''';

    final spans = buildMarkdownSourceTextSpan(
      const TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: 0),
      ),
      style: const TextStyle(fontSize: 14),
      syntaxTheme: syntax,
      withComposing: false,
    ).children!.cast<TextSpan>().toList();

    expect(spans.map((span) => span.text).join(), source);
    final metadata = spans
        .where((span) => span.style?.color == const Color(0xff555555))
        .map((span) => span.text)
        .join();
    for (final outside in <String>[
      '^[outside]',
      '[^outside]',
      '%%outside%%',
      ' ^outside-id',
    ]) {
      expect(metadata, contains(outside));
    }
    for (final inside in <String>[
      '^[ordered]',
      '%%ordered%%',
      '^ordered-id',
      '^[empty]',
      '%%empty%%',
      '^empty-id',
      '^[nested]',
      '%%nested%%',
      '^nested-id',
      '^[quoted]',
      '%%quoted%%',
      '^quoted-id',
      '^[tabbed]',
      '%%tabbed%%',
      '^tabbed-id',
      '^[fenced]',
      '%%fenced%%',
      '^fenced-id',
    ]) {
      expect(metadata, isNot(contains(inside)));
    }
  });

  test('live source keeps code-shaped closers inside the outer comment', () {
    const syntax = IanvsMarkdownSyntaxTheme(
      heading: TextStyle(),
      marker: TextStyle(),
      link: TextStyle(),
      code: TextStyle(fontFamily: 'monospace'),
      comment: TextStyle(color: Color(0xff555555)),
    );
    const source = '%%open `%%inside%%` tail%% visible';

    final spans = buildMarkdownSourceTextSpan(
      const TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: 0),
      ),
      style: const TextStyle(fontSize: 14),
      syntaxTheme: syntax,
      withComposing: false,
    ).children!.cast<TextSpan>().toList();

    expect(spans.map((span) => span.text).join(), source);
    expect(
      spans
          .where((span) => span.style?.color == const Color(0xff555555))
          .map((span) => span.text)
          .join(),
      '%%open `%%inside%%` tail%%',
    );
    expect(
      spans.where((span) => span.style?.fontFamily == 'monospace'),
      isEmpty,
    );
  });

  test('live source block IDs share standalone and escape boundaries', () {
    const syntax = IanvsMarkdownSyntaxTheme(
      heading: TextStyle(),
      marker: TextStyle(),
      link: TextStyle(),
      code: TextStyle(fontFamily: 'monospace'),
      comment: TextStyle(color: Color(0xff555555)),
    );
    List<TextSpan> spansFor(String source) => buildMarkdownSourceTextSpan(
      TextEditingValue(
        text: source,
        selection: const TextSelection.collapsed(offset: 0),
      ),
      style: const TextStyle(fontSize: 14),
      syntaxTheme: syntax,
      withComposing: false,
    ).children!.cast<TextSpan>().toList();

    Iterable<String?> metadataFor(String source) => spansFor(source)
        .where((span) => span.style?.color == const Color(0xff555555))
        .map((span) => span.text);

    expect(metadataFor('valid ^under_score'), <String>[' ^under_score']);
    expect(metadataFor('^standalone-id'), <String>['^standalone-id']);
    expect(metadataFor(r'escaped \^literal-id'), isEmpty);
    expect(metadataFor(r'double \\^double-id'), <String>['^double-id']);
    expect(metadataFor('trailing ^space-id   '), <String>[' ^space-id   ']);

    final inlineCode = spansFor(
      r'`inline ^code-id`',
    ).singleWhere((span) => span.text?.contains('^code-id') ?? false);
    expect(inlineCode.style?.fontFamily, 'monospace');

    const indentedCode = '    code ^indented-id\n\t| ^indented-cell |';
    expect(metadataFor(indentedCode), isEmpty);
    expect(
      spansFor(indentedCode).map((span) => span.text).join(),
      indentedCode,
    );
  });

  test('live source only styles block IDs at Markdown block ends', () {
    const syntax = IanvsMarkdownSyntaxTheme(
      heading: TextStyle(),
      marker: TextStyle(),
      link: TextStyle(),
      code: TextStyle(fontFamily: 'monospace'),
      comment: TextStyle(color: Color(0xff555555)),
    );
    const source =
        'Soft first ^soft-id\n'
        'continuation.\n\n'
        'Final ^final-id';

    final spans = buildMarkdownSourceTextSpan(
      const TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: 0),
      ),
      style: const TextStyle(fontSize: 14),
      syntaxTheme: syntax,
      withComposing: false,
    ).children!.cast<TextSpan>().toList();

    expect(
      spans
          .where((span) => span.style?.color == const Color(0xff555555))
          .map((span) => span.text),
      <String>[' ^final-id'],
    );
    expect(spans.map((span) => span.text).join(), source);
  });

  test('full source keeps language highlighting inside fenced code', () {
    const syntax = IanvsMarkdownSyntaxTheme(
      heading: TextStyle(fontWeight: FontWeight.w600),
      marker: TextStyle(color: Color(0xff777777)),
      link: TextStyle(decoration: TextDecoration.underline),
      code: TextStyle(fontFamily: 'monospace'),
      codeBlock: TextStyle(color: Color(0xffeeeeee)),
      comment: TextStyle(color: Color(0xff555555)),
      darkCodeHighlighting: true,
    );
    const source = '```dart\nfinal value = true;\n```';

    final spans = buildMarkdownSourceTextSpan(
      const TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: 0),
      ),
      style: const TextStyle(fontSize: 14),
      syntaxTheme: syntax,
      withComposing: false,
    ).children!.cast<TextSpan>().toList();

    expect(spans.first.text, '```dart');
    expect(spans.first.style?.color, const Color(0xff777777));
    final keyword = spans.singleWhere(
      (span) => span.text?.contains('final') ?? false,
    );
    expect(keyword.style?.color, const Color(0xfff2b6de));
    expect(spans.last.text, '```');
    expect(spans.last.style?.color, const Color(0xff777777));
    expect(spans.map((span) => span.text).join(), source);
  });
}

TextEditingValue _pressEnter(
  IanvsMarkdownEditingFormatter formatter,
  String text,
) => _pressEnterAt(formatter, text, text.length);

TextEditingValue _pressEnterAt(
  IanvsMarkdownEditingFormatter formatter,
  String text,
  int caret,
) {
  final oldValue = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: caret),
  );
  final newValue = TextEditingValue(
    text: text.replaceRange(caret, caret, '\n'),
    selection: TextSelection.collapsed(offset: caret + 1),
  );
  return formatter.formatEditUpdate(oldValue, newValue);
}

TextEditingValue _typeCharacter(
  IanvsMarkdownEditingFormatter formatter,
  String text,
  int caret,
  String character,
) {
  final oldValue = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: caret),
  );
  final updated = text.replaceRange(caret, caret, character);
  final newValue = TextEditingValue(
    text: updated,
    selection: TextSelection.collapsed(offset: caret + character.length),
  );
  return formatter.formatEditUpdate(oldValue, newValue);
}
