import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/services/slash_insertion.dart';

void main() {
  TextEditingValue value(String text, {int? caret}) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: caret ?? text.length),
  );

  test('only a fresh slash on an empty body line opens insertion', () {
    expect(slashInsertionStart('', value('/')), 0);
    expect(slashInsertionStart('text\n', value('text\n/')), 5);
    expect(slashInsertionStart('text', value('text/')), isNull);
    expect(slashInsertionStart('', value('/path/to/note')), isNull);
    expect(slashInsertionStart('/', value('/')), isNull);
    expect(slashInsertionStart('suffix', value('/suffix', caret: 1)), isNull);
    expect(
      slashInsertionStart(
        '',
        value('/').copyWith(composing: const TextRange(start: 0, end: 1)),
      ),
      isNull,
    );
  });
}
