import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:yaml/yaml.dart';

void main() {
  test('source coordinates and typed destinations preserve BOM CRLF emoji', () {
    const source =
        '\ufeff😀 [a](<Folder/A%20B.md#Head%20one> "title")\r\n'
        '[[ Folder/A%20B#Heading | Label ]] ![[Photo.png|200]]\r\n'
        '![alt](photo.png) [empty]() [[#^block]]';
    final result = parseIanvsMarkdownNoteSemantics(source);
    expect(result.issues.map((e) => e.code), isEmpty);
    expect(result.references, hasLength(6));
    final link = result.references[0];
    expect(link.kind, IanvsMarkdownSourceReferenceKind.markdownLink);
    expect(
      link.range.textInside(source),
      '[a](<Folder/A%20B.md#Head%20one> "title")',
    );
    expect(link.destinationRange.textInside(source), 'Folder/A%20B.md');
    expect(link.rawDestination, 'Folder/A%20B.md#Head%20one');
    expect(link.target, 'Folder/A B.md');
    expect(link.fragment, 'Head one');
    expect(link.title, 'title');
    final wiki = result.references[1];
    expect(wiki.target, 'Folder/A%20B');
    expect(wiki.alias, 'Label');
    expect(wiki.fragment, 'Heading');
    expect(wiki.destinationRange.textInside(source), 'Folder/A%20B');
    expect(
      result.references[2].kind,
      IanvsMarkdownSourceReferenceKind.wikiEmbed,
    );
    expect(
      result.references[3].kind,
      IanvsMarkdownSourceReferenceKind.markdownImage,
    );
    expect(result.references[4].target, '');
    expect(result.references[4].destinationRange.isCollapsed, isTrue);
    expect(result.references[5].target, '');
    expect(result.references[5].fragment, '^block');
    expect(link.range.start, 4);
  });

  test('definition precedence, uses and authoritative rewrite spans', () {
    const source =
        '[full][ Ref A ] [ref a][] [ref a] ![alt][REF A]\n\n'
        '[Ref A]: <Folder/Target%2520.md#Part>\n  "a title"\n'
        '[ref a]: Wrong.md "ignored"\n\n'
        '[wrong][missing]';
    final result = parseIanvsMarkdownNoteSemantics(source);
    expect(result.issues.map((e) => e.code), isEmpty);
    expect(result.references, hasLength(5));
    final definition = result.references.last;
    expect(
      definition.kind,
      IanvsMarkdownSourceReferenceKind.markdownDefinition,
    );
    expect(definition.target, 'Folder/Target%20.md');
    expect(definition.title, 'a title');
    for (final use in result.references.take(4)) {
      expect(use.target, definition.target);
      expect(use.destinationRange, definition.destinationRange);
      expect(use.definitionIdentity, definition.definitionIdentity);
      expect(use.definitionRange, definition.range);
      expect(use.destinationRange.textInside(source), 'Folder/Target%2520.md');
    }
    expect(
      result.references[3].kind,
      IanvsMarkdownSourceReferenceKind.markdownReferenceImage,
    );
    expect(definition.definitionIdentity, startsWith('ref a@'));
    expect(result.references.where((e) => e.target == 'Wrong.md'), isEmpty);
  });

  test('escapes entities balanced parentheses and multiline titles', () {
    const source =
        r'[escaped](a\(b\).md#x "title")'
        '\n'
        '[entity](A&amp;B.md&#35;Heading)\n'
        '[balanced](a(b).md\n "long\n title")\n'
        '[encoded](A%2520B.md)';
    final result = parseIanvsMarkdownNoteSemantics(source);
    expect(result.issues.map((e) => e.code), isEmpty);
    expect(result.references.map((e) => e.target), [
      'a(b).md',
      'A&B.md',
      'a(b).md',
      'A%20B.md',
    ]);
    expect(
      result.references[1].destinationRange.textInside(source),
      'A&amp;B.md',
    );
    expect(result.references[1].fragment, 'Heading');
  });

  test(
    'code, comments, escapes and frontmatter are not references or tags',
    () {
      const source =
          '---\naliases: [One]\ntags: [meta]\n---\n'
          r'\[[escaped]] \[escaped](no.md) \#escaped'
          '\n'
          '`[[inline]] [code](no.md) #code`\n\n'
          '```md\n[[fenced]] #fence\n```\n\n'
          '    [[indented]] #indent\n\n'
          '> ```\n> [[quoted code]] #quote\n> ```\n\n'
          '- item\n\n      [[list code]] #listcode\n\n'
          '%% [[comment]] #comment %%\n'
          '<!-- [[html comment]] #html -->\n\n'
          '[[real]] #yes #123 #中文/😀';
      final result = parseIanvsMarkdownNoteSemantics(source);
      expect(result.issues.map((e) => e.code), isEmpty);
      expect(result.references.map((e) => e.target), ['real']);
      expect(result.tags.map((e) => e.name), ['meta', 'yes', '中文/😀']);
      expect(result.aliases, ['One']);
    },
  );

  test('nested container projections preserve actual source offsets', () {
    const source =
        '> - [link](Folder/A.md) [[Wiki#H|alias]]\r\n'
        '>   #tag\r\n\r\n'
        '> [ref]: nested.md "title"\r\n'
        '> [ref]\r\n';
    final result = parseIanvsMarkdownNoteSemantics(source);
    expect(result.issues.map((e) => e.code), isEmpty);
    expect(result.references.map((e) => e.target), [
      'Folder/A.md',
      'Wiki',
      'nested.md',
      'nested.md',
    ]);
    expect(
      result.references[0].range.textInside(source),
      '[link](Folder/A.md)',
    );
    expect(result.references[1].destinationRange.textInside(source), 'Wiki');
    expect(
      result.references.last.destinationRange.textInside(source),
      'nested.md',
    );
    expect(result.tags.single.range.textInside(source), '#tag');
  });

  test('complete metadata is independent of UI truncation and body budget', () {
    final source =
        '\ufeff---\r\n'
        '${List.generate(45, (i) => 'key$i: value$i\r\n').join()}'
        'aliases:\r\n${List.generate(25, (i) => '  - Alias $i\r\n').join()}'
        'tags: [one, two]\r\n---\r\n[[Alias 24]]';
    final result = parseIanvsMarkdownNoteSemantics(source);
    expect(result.complete, isTrue);
    expect(result.aliasesComplete, isTrue);
    expect(result.aliases, hasLength(25));
    expect(result.aliases.last, 'Alias 24');
    expect(result.tags.map((e) => e.name), ['one', 'two']);
    expect(
      result.references.single.destinationRange.textInside(source),
      'Alias 24',
    );
    final large = parseIanvsMarkdownNoteSemantics('$source\n${'x' * 5000}');
    expect(large.complete, isFalse);
    expect(large.aliasesComplete, isTrue);
    expect(large.aliases, result.aliases);
    expect(large.issues.single.code, 'bodyBudget');
  });

  test(
    'unsupported metadata cannot become silently empty complete aliases',
    () {
      for (final content in [
        'aliases: [one, 42]',
        'aliases: {x: y}',
        'aliases: true',
        'aliases: []\naliases: [duplicate]',
        '[one, two]',
      ]) {
        final result = parseIanvsMarkdownNoteSemantics(
          '---\n$content\n---\n[[real]]',
        );
        expect(result.complete, isFalse, reason: content);
        expect(result.aliasesComplete, isFalse, reason: content);
        expect(result.aliases, isNot(contains('42')));
      }
      final tags = parseIanvsMarkdownNoteSemantics(
        '---\naliases: good\ntags: [42]\n---',
      );
      expect(tags.complete, isFalse);
      expect(tags.aliasesComplete, isTrue);
      expect(tags.aliases, ['good']);
    },
  );

  test('leading Wiki pipe is a path not an alias', () {
    final result = parseIanvsMarkdownNoteSemantics(
      '[[|Alias]] [[Target|Alias]] [[#Header]]',
    );
    expect(result.complete, isTrue);
    expect(result.references.first.target, '|Alias');
    expect(result.references.first.alias, isNull);
    expect(result.references[1].alias, 'Alias');
    expect(result.references.last.destinationRange.isCollapsed, isTrue);
  });

  test('URI query fragment and encoded filename boundaries decode once', () {
    const source =
        r'[a](A%3F%23%2520.md?x=1#H) [b](B\?x=2\#Part) '
        '[c](C.md&quest;x=3&#x0023;Head) [[Wiki?literal#H]]';
    final result = parseIanvsMarkdownNoteSemantics(source);
    expect(result.issues.map((e) => e.code), isEmpty);
    expect(result.references.map((e) => e.target), [
      'A?#%20.md',
      'B',
      'C.md',
      'Wiki?literal',
    ]);
    expect(result.references[0].query, 'x=1');
    expect(
      result.references[0].destinationRange.textInside(source),
      'A%3F%23%2520.md',
    );
    expect(result.references[1].destinationRange.textInside(source), 'B');
    expect(result.references[1].fragment, 'Part');
    expect(result.references[2].destinationRange.textInside(source), 'C.md');
    expect(result.references[2].query, 'x=3');
    expect(result.references[2].fragment, 'Head');
  });

  test('reference labels use authoritative Unicode case folding', () {
    const source = '[one][STRASSE] [two][Straẞe]\n\n[Straẞe]: Target.md';
    final result = parseIanvsMarkdownNoteSemantics(source);
    expect(result.issues.map((e) => e.code), isEmpty);
    expect(result.references, hasLength(3));
    expect(result.references.map((e) => e.target).toSet(), {'Target.md'});
    expect(
      result.references.map((e) => e.definitionIdentity).toSet(),
      hasLength(1),
    );
  });

  test(
    'renderer projection retains literal backslashes and Wiki embed rules',
    () {
      const source = r'[x](A\\\(B\\\).md) ![[Note|]] ![[|invalid]] [[|valid]]';
      final result = parseIanvsMarkdownNoteSemantics(source);
      expect(result.issues.map((e) => e.code), isEmpty);
      expect(result.references.map((e) => e.target), [
        r'A\(B\).md',
        'Note',
        '|valid',
      ]);
      expect(
        result.references[1].kind,
        IanvsMarkdownSourceReferenceKind.wikiEmbed,
      );
      expect(result.references[1].alias, isNull);
    },
  );

  test(
    'comment projection keeps surrounding links and reports split paths',
    () {
      const source =
          '%%hidden%% [real](A.md) #ta%%hidden%%g\n'
          '[label%%hidden%%](B.md) [[Ta%%hidden%%rget]]';
      final result = parseIanvsMarkdownNoteSemantics(source);
      expect(result.complete, isFalse);
      expect(result.issues.map((e) => e.code), ['nonContiguousDestination']);
      expect(result.references.map((e) => e.target), ['A.md', 'B.md']);
      expect(result.tags.single.name, 'tag');
      expect(result.tags.single.range.textInside(source), '#ta%%hidden%%g');
      expect(
        result.references.last.destinationRange.textInside(source),
        'B.md',
      );
    },
  );

  test('reference parsing does not override footnote or HTML authority', () {
    const source =
        '[^foot]: [[Footnote]]\n\ntext <a href="Other.md">label</a> [[real]]';
    final result = parseIanvsMarkdownNoteSemantics(source);
    expect(result.complete, isFalse);
    expect(
      result.issues.map((e) => e.code),
      containsAll(['footnoteContext', 'htmlContext']),
    );
    expect(result.references.map((e) => e.target), ['real']);
  });

  test('pathological input stays incomplete without throwing', () {
    final depth = parseIanvsMarkdownNoteSemantics('${'> ' * 70}[[deep]]');
    expect(depth.complete, isFalse);
    expect(depth.issues.single.code, 'parserLimit');
    final oversized = parseIanvsMarkdownNoteSemantics(
      '---\naliases: ${'é' * 33000}\n---\n[[after]]',
    );
    expect(oversized.complete, isFalse);
    expect(oversized.aliasesComplete, isFalse);
    expect(oversized.issues.map((e) => e.code), contains('frontMatterBudget'));
    final tooMany = parseIanvsMarkdownNoteSemantics(
      '---\naliases:\n${List.generate(1025, (i) => '  - a$i\n').join()}---',
    );
    expect(tooMany.aliasesComplete, isFalse);
    expect(tooMany.issues.map((e) => e.code), contains('metadataCount'));
    final malformed = parseIanvsMarkdownNoteSemantics('[invalid](A%FF.md)');
    expect(malformed.complete, isFalse);
    expect(malformed.issues.single.code, 'destinationEncoding');
  });

  test('YAML tags validate names and anchors stay explicitly unknown', () {
    const source =
        '---\ntags: ["two words", "#", "123", "valid/nested", "#中文/😀"]\n---';
    final tags = parseIanvsMarkdownNoteSemantics(source);
    expect(tags.complete, isFalse);
    expect(tags.aliasesComplete, isTrue);
    expect(tags.tags.map((e) => e.name), ['valid/nested', '中文/😀']);
    expect(tags.issues.map((e) => e.code), [
      'metadataTag',
      'metadataTag',
      'metadataTag',
    ]);
    for (final yaml in [
      'base: &a Foo\naliases: *a',
      'aliases: [&a Foo, *a]',
      'aliases: &a [Foo]',
      'base: &a {aliases: [Foo]}\n<<: *a',
    ]) {
      final result = parseIanvsMarkdownNoteSemantics('---\n$yaml\n---');
      expect(result.complete, isFalse, reason: yaml);
      expect(result.aliasesComplete, isFalse, reason: yaml);
      expect(result.aliases, isEmpty, reason: yaml);
    }
    final quoted = parseIanvsMarkdownNoteSemantics(
      '---\naliases: "&abc quoted"\n---',
    );
    expect(quoted.complete, isTrue);
    expect(quoted.aliases, ['&abc quoted']);
  });

  test(
    'automatic URLs are explicit; nested links and label tags follow grammar',
    () {
      const source =
          '<https://example.com>\n\n'
          '[outer [inner](inner.md)](outer.md) [label #tag](A.md "#title") '
          '![alt](B.md#destination)';
      final result = parseIanvsMarkdownNoteSemantics(source);
      expect(result.complete, isFalse);
      expect(result.issues.map((e) => e.code), ['autolinkContext']);
      expect(result.references.map((e) => e.target), [
        'inner.md',
        'A.md',
        'B.md',
      ]);
      expect(result.tags.map((e) => e.name), ['tag']);
    },
  );

  test(
    'image descriptions flatten nested references and Wiki alias markup is explicit',
    () {
      const source =
          '![alt [inner](Hidden.md) [[HiddenWiki]] #hidden](Visible.png) '
          '[![alt](Nested.png)](Target.md) [[Note|#nested]]';
      final result = parseIanvsMarkdownNoteSemantics(source);
      expect(result.references.map((e) => e.target), [
        'Visible.png',
        'Target.md',
        'Nested.png',
        'Note',
      ]);
      expect(result.tags, isEmpty);
      expect(result.complete, isFalse);
      expect(result.issues.map((e) => e.code), ['wikiAliasMarkup']);
    },
  );

  test(
    'semantic occurrence allocation is bounded even without syntax tokens',
    () {
      // Each line is short enough for the renderer preflight.
      final line = '${'#tag ' * 200}\n';
      final source =
          '---\naliases: retained\ntags: metadata\n---\n[link](Note)\n${line * 50}';
      final result = parseIanvsMarkdownNoteSemantics(source);
      expect(result.complete, isFalse);
      expect(result.aliasesComplete, isTrue);
      expect(result.aliases, ['retained']);
      expect(result.references.length + result.tags.length, 4096);
      expect(result.issues.map((e) => e.code), ['occurrenceBudget']);
      expect(result.references.single.target, 'Note');
      expect(result.tags.first.name, 'metadata');
      final atLimit = parseIanvsMarkdownNoteSemantics(
        '${line * 20}${'#tag ' * 96}',
      );
      expect(atLimit.complete, isTrue);
      expect(atLimit.tags.length, 4096);

      final urlLine = '${'https://example.test ' * 100}\n';
      final urls = parseIanvsMarkdownNoteSemantics(urlLine * 50);
      expect(urls.complete, isFalse);
      expect(urls.issues.length, 4097);
      expect(urls.issues.last.code, 'occurrenceBudget');
    },
  );

  test(
    'native definition destination includes unmatched closing parentheses',
    () {
      const source = '[x]\n\n[x]: a).md\n';
      final result = parseIanvsMarkdownNoteSemantics(source);
      expect(result.complete, isTrue);
      expect(result.references, hasLength(2));
      for (final reference in result.references) {
        expect(reference.target, 'a).md');
        expect(reference.rawDestination, 'a).md');
        expect(reference.destinationRange.textInside(source), 'a).md');
      }
    },
  );

  test(
    'native destination whitespace keeps NBSP and embedded tab spelling',
    () {
      const source =
          '[x](\u00a0A.md) ![image](<\u00a0B.md>)\n\n'
          '[tab](C.md\t"Title")\n\n[ref]\n\n[ref]: D.md\t"Title"\n';
      final result = parseIanvsMarkdownNoteSemantics(source);
      expect(result.complete, isTrue);
      expect(result.references.map((e) => e.target), [
        '\u00a0A.md',
        '\u00a0B.md',
        'C.md\t"Title"',
        'D.md\t"Title"',
        'D.md\t"Title"',
      ]);
      for (final reference in result.references) {
        expect(reference.rawDestination, reference.target);
        expect(reference.destinationRange.textInside(source), reference.target);
        expect(reference.title, isNull);
      }
      for (final character in ['\u00a0', '\u2003', '\ufeff']) {
        final unicodeSource =
            '😀 [inline](${character}A.md)\r\n\r\n'
            '[ref]\r\n\r\n[ref]: ${character}B.md\r\n';
        final native = md.Document();
        native.parse(unicodeSource);
        expect(native.linkReferences['ref']!.destination, '${character}B.md');
        final nativeLink =
            md.Document().parseInline('[x](${character}A.md)').single
                as md.Element;
        expect(
          nativeLink.attributes['href'],
          '${Uri.encodeComponent(character)}A.md',
        );
        final unicode = parseIanvsMarkdownNoteSemantics(unicodeSource);
        expect(unicode.complete, isTrue);
        expect(unicode.references.map((e) => e.target), [
          '${character}A.md',
          '${character}B.md',
          '${character}B.md',
        ]);
        expect(unicode.references.first.range.start, 3);
        for (final reference in unicode.references) {
          expect(reference.rawDestination, reference.target);
          expect(
            reference.destinationRange.textInside(unicodeSource),
            reference.target,
          );
          expect(
            reference.destinationRange.start,
            unicodeSource.indexOf(reference.target),
          );
        }
      }
      const encodedSource = '[x](%EF%BB%BFA.md?%EF%BB%BF#%EF%BB%BF)';
      final encoded = parseIanvsMarkdownNoteSemantics(encodedSource);
      expect(encoded.complete, isTrue);
      expect(encoded.references.single.target, '\ufeffA.md');
      expect(encoded.references.single.query, '\ufeff');
      expect(encoded.references.single.fragment, '\ufeff');
      expect(
        encoded.references.single.destinationRange.textInside(encodedSource),
        '%EF%BB%BFA.md',
      );
      // This native definition grammar rejects a suffix after a balanced pair.
      final literal = parseIanvsMarkdownNoteSemantics('[x]\n\n[x]: a(b).md\n');
      expect(literal.complete, isTrue);
      expect(literal.references, isEmpty);
    },
  );

  test('YAML tags cannot hide anchors or reuse a different scalar span', () {
    for (final yaml in [
      'base: !!str &a Hello\ntags: [*a]',
      'base: &a !!str Hello\ntags: [*a]',
      'tags: [!!str &a Hello, *a]',
      'base: ! &a Hello\ntags: [*a]',
    ]) {
      expect(() => loadYamlNode(yaml), returnsNormally, reason: yaml);
      final result = parseIanvsMarkdownNoteSemantics('---\n$yaml\n---');
      expect(result.complete, isFalse, reason: yaml);
      expect(result.tags, isEmpty, reason: yaml);
      expect(result.aliasesComplete, isTrue, reason: yaml);
      expect(result.issues.map((e) => e.code), everyElement('metadataAnchor'));
    }
    for (final yaml in [
      'aliases: [!!str &a Hello, *a]',
      'aliases: [! &a Hello, *a]',
      'aliases: [!!str # property comment\n  &a Hello, *a]',
    ]) {
      expect(() => loadYamlNode(yaml), returnsNormally, reason: yaml);
      final result = parseIanvsMarkdownNoteSemantics('---\n$yaml\n---');
      expect(result.complete, isFalse, reason: yaml);
      expect(result.aliasesComplete, isFalse, reason: yaml);
      expect(result.aliases, isEmpty, reason: yaml);
      expect(result.issues.map((e) => e.code), everyElement('metadataAnchor'));
    }
    final quoted = parseIanvsMarkdownNoteSemantics(
      '---\naliases: [!!str "&abc", !!str "*a", "!!str &a"]\n---',
    );
    expect(quoted.complete, isTrue);
    expect(quoted.aliases, ['&abc', '*a', '!!str &a']);
  });

  test('tables are unknown rather than guessed across cell boundaries', () {
    for (final row in [
      r'| `one | [[Hidden]]` |',
      r'| [[Target | Alias]] |',
      r'| [[Target\|Alias]] | #table |',
      r'| [link](A.md) | [ref] |',
      r'| ![image](A.png) | ![[Embed]] | [[Extra]] |',
    ]) {
      final source =
          '---\naliases: Complete\n---\n'
          '| one | two |\n| --- | --- |\n$row\n\n'
          '[ref]: B.md\n\n[[Outside]] #outside';
      final result = parseIanvsMarkdownNoteSemantics(source);
      expect(result.complete, isFalse, reason: row);
      expect(result.aliasesComplete, isTrue, reason: row);
      expect(result.aliases, ['Complete']);
      expect(result.issues.map((e) => e.code), ['tableContext']);
      expect(result.references.map((e) => e.target), ['B.md', 'Outside']);
      expect(
        result.references.first.kind,
        IanvsMarkdownSourceReferenceKind.markdownDefinition,
      );
      expect(result.tags.map((e) => e.name), ['outside']);
    }
  });

  test('immutable snapshot and unsupported HTML are explicit', () {
    final result = parseIanvsMarkdownNoteSemantics('<div>[[raw]]</div>');
    expect(result.complete, isFalse);
    expect(result.issues.single.code, 'htmlContext');
    expect(result.references, isEmpty);
    expect(() => result.aliases.add('x'), throwsUnsupportedError);
    expect(
      () => result.tags.add(
        const IanvsMarkdownSourceTag(name: 'x', range: TextRange.empty),
      ),
      throwsUnsupportedError,
    );
  });
}
