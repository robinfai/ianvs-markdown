import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/src/task_syntax.dart';

void main() {
  test('projects every Obsidian task marker without touching code', () {
    const source = '''
---
sample: "- [!] property"
---

- [ ] Open
- [x] Done
- [!] Important
- [/] Progress
1. [?] Ordered
> - [b] Quoted
- Parent
    - [u] Nested

```md
- [c] fenced literal
```

    - [d] indented literal

Paragraph - [p] literal
''';

    final projection = projectObsidianTaskMarkers(source);

    expect(projection.tasks.map((task) => task.marker), <String>[
      ' ',
      'x',
      '!',
      '/',
      '?',
      'b',
      'u',
    ]);
    for (final task in projection.tasks) {
      expect(source.substring(task.offset, task.offset + 1), task.marker);
    }
    expect(projection.data, contains('- [x] Important'));
    expect(projection.data, contains('- [x] Progress'));
    expect(projection.data, contains('1. [x] Ordered'));
    expect(projection.data, contains('> - [x] Quoted'));
    expect(projection.data, contains('    - [x] Nested'));
    expect(projection.data, contains('- [c] fenced literal'));
    expect(projection.data, contains('    - [d] indented literal'));
    expect(projection.data, contains('Paragraph - [p] literal'));
    expect(projection.data.length, source.length);
  });

  test('keeps all Border marker offsets stable in mixed lists', () {
    const markers = <String>[
      ' ',
      'x',
      '/',
      '-',
      '>',
      '<',
      '?',
      '!',
      '*',
      'i',
      'I',
      'l',
      'b',
      'n',
      'p',
      'c',
      '"',
      '“',
      'S',
      'u',
      'd',
      'k',
      ']',
    ];
    final source = markers
        .map((marker) => '- [$marker] $marker state')
        .join('\n');

    final projection = projectObsidianTaskMarkers(source);

    expect(projection.tasks.map((task) => task.marker), markers);
    expect(projection.data.split('\n').skip(2), everyElement(contains('[x]')));
  });

  test('orders nested markers the same way the renderer builds widgets', () {
    const source = '''
- [!] Parent
  - [b] Child
    - [/] Grandchild
  - Plain child
    - [?] Nested below plain child
- [x] Sibling
''';

    final projection = projectObsidianTaskMarkers(source);

    expect(projection.tasks.map((task) => task.marker), <String>[
      '/',
      'b',
      '?',
      '!',
      'x',
    ]);
    for (final task in projection.tasks) {
      expect(source.substring(task.offset, task.offset + 1), task.marker);
    }
  });
}
