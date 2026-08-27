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

  test('retains top-level YAML spans for property field edits', () {
    const source = '''
---
title: Alpha
enabled: true
tags: [one, two]
---
Body
''';
    final document = parseMarkdownFrontMatter(source);
    final title = document.entries.firstWhere((entry) => entry.key == 'title');
    final enabled = document.entries.firstWhere(
      (entry) => entry.key == 'enabled',
    );

    expect(
      source.substring(title.sourceKeyStart!, title.sourceKeyEnd),
      'title',
    );
    expect(
      source.substring(title.sourceValueStart!, title.sourceValueEnd),
      'Alpha',
    );
    expect(
      source.substring(enabled.sourceValueStart!, enabled.sourceValueEnd),
      'true',
    );
  });

  test('property commits match Obsidian flow-list canonicalization', () {
    const source = '''
---
title: Alpha
enabled: true
quoted_number: "42"
tags: [one, two]
cssclasses: [wide]
---
Body
''';
    final document = parseMarkdownFrontMatter(source);
    MarkdownMetadataEntry entry(String key) =>
        document.entries.firstWhere((item) => item.key == key);

    expect(
      replaceMarkdownFrontMatterTextValue(source, entry('title'), 'Beta'),
      '''
---
title: Beta
enabled: true
quoted_number: "42"
tags:
  - one
  - two
cssclasses:
  - wide
---
Body
''',
    );
    expect(
      replaceMarkdownFrontMatterBooleanValue(source, entry('enabled'), false),
      '''
---
title: Alpha
enabled: false
quoted_number: "42"
tags: [one, two]
cssclasses: [wide]
---
Body
''',
    );
    expect(
      replaceMarkdownFrontMatterTextValue(source, entry('quoted_number'), '43'),
      contains('quoted_number: "43"'),
    );
  });

  test('number property rewrites canonicalize lists and reject non-finite', () {
    const source = '''
---
count: 42
ratio: 3.5
tags: [one, two]
---
Body
''';
    final document = parseMarkdownFrontMatter(source);
    MarkdownMetadataEntry entry(String key) =>
        document.entries.firstWhere((item) => item.key == key);

    expect(
      replaceMarkdownFrontMatterNumberValue(source, entry('count'), 43),
      '''
---
count: 43
ratio: 3.5
tags:
  - one
  - two
---
Body
''',
    );
    expect(
      replaceMarkdownFrontMatterNumberValue(source, entry('ratio'), 4.5),
      '''
---
count: 42
ratio: 4.5
tags:
  - one
  - two
---
Body
''',
    );
    expect(
      replaceMarkdownFrontMatterNumberValue(source, entry('count'), double.nan),
      source,
    );
    expect(
      replaceMarkdownFrontMatterNumberValue(
        source,
        entry('count'),
        double.infinity,
      ),
      source,
    );
  });

  test(
    'property key renames preserve order, value type, and YAML validity',
    () {
      const source = '''
---
title: Alpha
count: 42
tags: [one, two]
---
Body
''';
      final document = parseMarkdownFrontMatter(source);
      MarkdownMetadataEntry entry(String key) =>
          document.entries.firstWhere((item) => item.key == key);
      final count = entry('count');

      expect(count.keyEditable, isTrue);
      final renamed = replaceMarkdownFrontMatterKey(source, count, 'weight');
      expect(renamed, '''
---
title: Alpha
weight: 42
tags:
  - one
  - two
---
Body
''');
      final renamedDocument = parseMarkdownFrontMatter(renamed);
      expect(renamedDocument.entries.map((entry) => entry.key), const <String>[
        'title',
        'weight',
        'tags',
      ]);
      expect(renamedDocument.entries[1].type, MarkdownMetadataValueType.number);

      expect(replaceMarkdownFrontMatterKey(source, count, 'title'), source);
      expect(replaceMarkdownFrontMatterKey(source, count, 'TITLE'), source);
      expect(replaceMarkdownFrontMatterKey(source, count, 'Count'), source);
      expect(replaceMarkdownFrontMatterKey(source, count, ''), source);
      expect(replaceMarkdownFrontMatterKey(source, count, 'bad\nkey'), source);
      expect(
        replaceMarkdownFrontMatterKey(
          source.replaceFirst('title:', 'draft: true\ntitle:'),
          count,
          'weight',
        ),
        source.replaceFirst('title:', 'draft: true\ntitle:'),
      );

      expect(
        replaceMarkdownFrontMatterKey(source, count, 'true'),
        contains('"true": 42'),
      );
      expect(
        replaceMarkdownFrontMatterKey(source, count, 'display name'),
        contains('display name: 42'),
      );
      expect(
        parseMarkdownFrontMatter(
          replaceMarkdownFrontMatterKey(source, count, 'foo: bar'),
        ).entries[1].key,
        'foo: bar',
      );
    },
  );

  test('only complete string keys opt into structured rename', () {
    final longKey = List<String>.filled(81, 'a').join();
    final document = parseMarkdownFrontMatter('''
---
42: numeric key
"display name": quoted key
$longKey: long key
---
''');

    expect(document.entries[0].keyEditable, isFalse);
    expect(document.entries[1].keyEditable, isTrue);
    expect(document.entries[2].keyEditable, isFalse);
  });

  test(
    'date values commit exact calendar dates and canonicalize flow lists',
    () {
      const source = '''
---
title: Alpha
due: 2026-08-28
tags: [one, two]
---
Body
''';
      final document = parseMarkdownFrontMatter(source);
      final due = document.entries.firstWhere((entry) => entry.key == 'due');

      final updated = replaceMarkdownFrontMatterDateValue(
        source,
        due,
        '2026-08-27',
      );
      expect(updated, '''
---
title: Alpha
due: 2026-08-27
tags:
  - one
  - two
---
Body
''');
      final updatedDocument = parseMarkdownFrontMatter(updated);
      expect(updatedDocument.entries.map((entry) => entry.key), const <String>[
        'title',
        'due',
        'tags',
      ]);
      expect(updatedDocument.entries[1].type, MarkdownMetadataValueType.date);

      for (final invalid in <String>[
        '2026-02-30',
        '2026-2-03',
        '2026-02-3',
        '0000-01-01',
        'abc',
        '',
      ]) {
        expect(
          replaceMarkdownFrontMatterDateValue(source, due, invalid),
          source,
        );
      }
      final shifted = source.replaceFirst('title:', 'draft: true\ntitle:');
      expect(
        replaceMarkdownFrontMatterDateValue(shifted, due, '2026-08-27'),
        shifted,
      );
    },
  );

  test('safe string-list properties rewrite as typed block scalars', () {
    const source = '''
---
tags: [one, two]
aliases: [Alias One]
typed: [one, 2]
---
Body
''';
    final document = parseMarkdownFrontMatter(source);
    MarkdownMetadataEntry entry(String key) =>
        document.entries.firstWhere((item) => item.key == key);

    expect(entry('tags').listValuesEditable, isTrue);
    expect(entry('aliases').listValuesEditable, isTrue);
    expect(entry('typed').listValuesEditable, isFalse);
    expect(
      replaceMarkdownFrontMatterListValue(source, entry('tags'), <String>[
        'one',
        'three',
        'true',
        '42',
        '#hash',
      ]),
      '''
---
tags:
  - one
  - three
  - "true"
  - "42"
  - "#hash"
aliases:
  - Alias One
typed:
  - one
  - 2
---
Body
''',
    );
    expect(
      replaceMarkdownFrontMatterListValue(
        source,
        entry('tags'),
        const <String>[],
      ),
      '''
---
tags:
aliases:
  - Alias One
typed:
  - one
  - 2
---
Body
''',
    );
    expect(
      replaceMarkdownFrontMatterListValue(
        source,
        entry('aliases'),
        const <String>[],
      ),
      '''
---
tags:
  - one
  - two
aliases:
typed:
  - one
  - 2
---
Body
''',
    );

    final stale = source.replaceFirst('tags:', 'draft: true\ntags:');
    expect(
      replaceMarkdownFrontMatterListValue(stale, entry('tags'), const ['one']),
      stale,
    );
    expect(
      replaceMarkdownFrontMatterListValue(source, entry('typed'), const [
        'one',
      ]),
      source,
    );

    final longList = parseMarkdownFrontMatter(
      '---\ntags: [${List<String>.generate(17, (index) => 'tag$index').join(', ')}]\n---\n',
    ).entries.single;
    expect(longList.listValuesEditable, isFalse);
  });

  test('empty known list properties can accept a new block-list value', () {
    const source = '''
---
title: Alpha
tags:
aliases:
empty:
---
Body
''';
    final document = parseMarkdownFrontMatter(source);
    final tags = document.entries.firstWhere((entry) => entry.key == 'tags');
    final aliases = document.entries.firstWhere(
      (entry) => entry.key == 'aliases',
    );
    final empty = document.entries.firstWhere((entry) => entry.key == 'empty');

    expect(tags.type, MarkdownMetadataValueType.empty);
    expect(tags.listValuesEditable, isTrue);
    expect(aliases.listValuesEditable, isTrue);
    expect(empty.listValuesEditable, isFalse);
    expect(
      replaceMarkdownFrontMatterListValue(source, tags, const ['three']),
      '''
---
title: Alpha
tags:
  - three
aliases:
empty:
---
Body
''',
    );
    expect(
      replaceMarkdownFrontMatterListValue(source, aliases, const [
        'Alias Three',
      ]),
      '''
---
title: Alpha
tags:
aliases:
  - Alias Three
empty:
---
Body
''',
    );
  });

  test('populated block-list properties retain their trailing line break', () {
    const source = '''
---
aliases:
  - Alias One
tags:
  - one
---
Body
''';
    final document = parseMarkdownFrontMatter(source);
    final aliases = document.entries.firstWhere(
      (entry) => entry.key == 'aliases',
    );

    expect(
      replaceMarkdownFrontMatterListValue(source, aliases, const [
        'Alias One',
        'Alias Two',
      ]),
      '''
---
aliases:
  - Alias One
  - Alias Two
tags:
  - one
---
Body
''',
    );
  });

  test('list property rewrites preserve CRLF around empty values', () {
    const source =
        '---\r\n'
        'tags:\r\n'
        '  - one\r\n'
        '---\r\n'
        'Body';
    final tags = parseMarkdownFrontMatter(source).entries.single;

    expect(
      replaceMarkdownFrontMatterListValue(source, tags, const <String>[]),
      '---\r\n'
      'tags:\r\n'
      '---\r\n'
      'Body',
    );
    final emptyTags = parseMarkdownFrontMatter(
      '---\r\ntags:\r\n---\r\nBody',
    ).entries.single;
    expect(
      replaceMarkdownFrontMatterListValue(
        '---\r\ntags:\r\n---\r\nBody',
        emptyTags,
        const ['two'],
      ),
      '---\r\n'
      'tags:\r\n'
      '  - two\r\n'
      '---\r\n'
      'Body',
    );
  });

  test(
    'property rewrites preserve CRLF and avoid stale or commented spans',
    () {
      const crlf =
          '---\r\n'
          'title: Alpha\r\n'
          'tags: [one, two]\r\n'
          '---\r\n'
          'Body';
      final crlfTitle = parseMarkdownFrontMatter(
        crlf,
      ).entries.firstWhere((entry) => entry.key == 'title');
      expect(
        replaceMarkdownFrontMatterTextValue(crlf, crlfTitle, 'Beta'),
        '---\r\n'
        'title: Beta\r\n'
        'tags:\r\n'
        '  - one\r\n'
        '  - two\r\n'
        '---\r\n'
        'Body',
      );

      const commented = '''
---
title: Alpha
tags: [one, two] # preserve this unsupported source comment
---
Body
''';
      final commentedTitle = parseMarkdownFrontMatter(
        commented,
      ).entries.firstWhere((entry) => entry.key == 'title');
      expect(
        replaceMarkdownFrontMatterTextValue(commented, commentedTitle, 'Beta'),
        commented.replaceFirst('title: Alpha', 'title: Beta'),
      );

      final staleSource = commented.replaceFirst(
        'title: Alpha',
        'draft: true\ntitle: Alpha',
      );
      expect(
        replaceMarkdownFrontMatterTextValue(
          staleSource,
          commentedTitle,
          'Beta',
        ),
        staleSource,
      );
    },
  );

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
