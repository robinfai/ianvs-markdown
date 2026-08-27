import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  test('parses and bounds YAML front matter', () {
    final document = parseMarkdownFrontMatter('''
---
title: SSH Internals
author: Robin
tags: [ssh, security]
settings:
  status: ready
---
# Body
''');

    expect(document.hasFrontMatter, isTrue);
    expect(document.body, '# Body\n');
    expect(document.entries.first.key, 'title');
    expect(document.entries[1].key, 'author');
    expect(
      document.entries.firstWhere((entry) => entry.key == 'tags').items,
      <String>['ssh', 'security'],
    );
    expect(
      document.entries.firstWhere((entry) => entry.key == 'settings').value,
      '{"status":"ready"}',
    );
    expect(
      document.entries.firstWhere((entry) => entry.key == 'settings').type,
      MarkdownMetadataValueType.object,
    );
  });

  test('preserves YAML value types for Obsidian property presentation', () {
    final document = parseMarkdownFrontMatter('''
---
enabled: true
archived: false
score: 42
ratio: 3.5
due: 2026-08-24
moment: 2026-08-24T18:05:00
zoned: 2026-08-27T10:20:30+08:00
quoted_number: "42"
items: [alpha, beta]
settings:
  owner: Codex
empty:
---
Body
''');

    MarkdownMetadataEntry entry(String key) =>
        document.entries.firstWhere((item) => item.key == key);

    expect(entry('enabled').type, MarkdownMetadataValueType.boolean);
    expect(entry('archived').type, MarkdownMetadataValueType.boolean);
    expect(entry('score').type, MarkdownMetadataValueType.number);
    expect(entry('ratio').type, MarkdownMetadataValueType.number);
    expect(entry('due').type, MarkdownMetadataValueType.date);
    expect(entry('due').value, '2026-08-24');
    expect(entry('moment').type, MarkdownMetadataValueType.text);
    expect(entry('moment').value, '2026-08-24T18:05:00');
    expect(entry('zoned').type, MarkdownMetadataValueType.text);
    expect(entry('zoned').value, '2026-08-27T10:20:30+08:00');
    expect(entry('quoted_number').type, MarkdownMetadataValueType.text);
    expect(entry('quoted_number').value, '42');
    expect(entry('items').type, MarkdownMetadataValueType.list);
    expect(entry('items').items, <String>['alpha', 'beta']);
    expect(entry('settings').type, MarkdownMetadataValueType.object);
    expect(entry('settings').value, '{"owner":"Codex"}');
    expect(entry('empty').type, MarkdownMetadataValueType.empty);
  });

  test('keeps invalid and unclosed front matter in the body', () {
    const invalid = '---\n- one\n- two\n---\nBody';
    const unclosed = '---\ntitle: Missing close\nBody';

    expect(parseMarkdownFrontMatter(invalid).hasFrontMatter, isFalse);
    expect(parseMarkdownFrontMatter(invalid).body, invalid);
    expect(parseMarkdownFrontMatter(unclosed).hasFrontMatter, isFalse);
    expect(parseMarkdownFrontMatter(unclosed).body, unclosed);
  });

  test('preserves explicit empty properties for the presentation layer', () {
    final document = parseMarkdownFrontMatter('''
---
empty:
blank: ""
status: ready
---
Body
''');

    expect(document.hasFrontMatter, isTrue);
    expect(
      document.entries.map((entry) => (entry.key, entry.value)),
      <(String, String)>[('empty', ''), ('blank', ''), ('status', 'ready')],
    );
  });

  test('preserves source key order instead of promoting title or author', () {
    final document = parseMarkdownFrontMatter('''
---
status: draft
author: Robin
title: Later title
tags: [one]
---
Body
''');

    expect(document.entries.map((entry) => entry.key), <String>[
      'status',
      'author',
      'title',
      'tags',
    ]);
  });

  test('accepts only the Obsidian triple-dash closing marker', () {
    const invalidSources = <String>[
      '---\ntitle: Ellipsis\n...\nBody',
      ' ---\ntitle: Opening prefix\n---\nBody',
      '--- \ntitle: Opening suffix\n---\nBody',
      '---\ntitle: Closing prefix\n ---\nBody',
      '---\ntitle: Closing suffix\n--- \nBody',
      '\ufeff---\ntitle: BOM\n---\nBody',
    ];

    for (final source in invalidSources) {
      expect(
        parseMarkdownFrontMatter(source).hasFrontMatter,
        isFalse,
        reason: source,
      );
      expect(parseMarkdownFrontMatter(source).body, source, reason: source);
    }
  });

  test(
    'extracts all GFM heading levels without code-block false positives',
    () {
      const source = '''
# First

## Second *with emphasis*

```markdown
# Not a heading
```

##### Fifth

###### Sixth

Setext one
==========

Setext two
----------
''';
      final headings = parseMarkdownHeadings(source);

      expect(headings.map((heading) => heading.level), <int>[1, 2, 5, 6, 1, 2]);
      expect(headings.map((heading) => heading.text), <String>[
        'First',
        'Second with emphasis',
        'Fifth',
        'Sixth',
        'Setext one',
        'Setext two',
      ]);
      expect(
        parseMarkdownHeadings(
          source,
          maximumLevel: 4,
        ).map((heading) => heading.text),
        <String>['First', 'Second with emphasis', 'Setext one', 'Setext two'],
      );
    },
  );
}
