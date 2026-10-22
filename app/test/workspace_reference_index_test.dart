import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/services/wiki_note_resolver.dart';
import 'package:linefold/src/services/workspace_index.dart';
import 'package:linefold/src/services/workspace_index_source.dart';
import 'package:linefold/src/services/workspace_reference_index.dart';

import 'workspace_index_test.dart' show FakeIndexSource;

void main() {
  late FakeIndexSource source;
  late WorkspaceIndex index;
  late WorkspaceReferenceIndex references;
  setUp(() {
    source = FakeIndexSource();
    index = WorkspaceIndex(source: source)..configure('/vault');
    references = WorkspaceReferenceIndex(index);
  });
  tearDown(() {
    references.dispose();
    index.dispose();
  });

  test(
    'same snapshot derives outgoing, backlinks, tags and definition identity',
    () async {
      const text =
          '\ufeff😀\r\n[[Target#Heading|label]] #project/work\r\n[x](Target.md#Heading "title")\r\n[x][ref] ![x][ref]\r\n\r\n[ref]: Target.md#Heading\r\n';
      source.note('Origin.md', text);
      source.note(
        'Target.md',
        '---\naliases: [Other]\ntags: [project/work]\n---\n# Heading',
      );
      final result = await references.refresh();
      expect(result.complete, isTrue, reason: result.issues.toString());
      expect(result.backlinks('Target.md'), hasLength(4));
      expect(result.tags['project/work'], hasLength(2));
      for (final edge in result.backlinks('Target.md')) {
        expect(
          edge.reference.destinationRange.textInside(text),
          anyOf('Target', 'Target.md'),
        );
        expect(edge.reference.fragment, 'Heading');
      }
      final uses = result.edges
          .where(
            (edge) =>
                edge.reference.kind ==
                    IanvsMarkdownSourceReferenceKind.markdownReferenceLink ||
                edge.reference.kind ==
                    IanvsMarkdownSourceReferenceKind.markdownReferenceImage,
          )
          .toList();
      expect(uses, hasLength(2));
      expect(
        uses[0].reference.definitionIdentity,
        uses[1].reference.definitionIdentity,
      );
      expect(
        uses[0].reference.destinationRange,
        uses[1].reference.destinationRange,
      );
      expect(result.impact('Target.md').references, hasLength(5));
      expect(source.downloads, 0);
    },
  );

  test(
    'dirty overlay replaces old outgoing and tags on every text revision',
    () async {
      source.note('Origin.md', '[[Old]] #old');
      source.note('Old.md', 'old');
      source.note('New.md', 'new');
      await references.refresh();
      void edit(String text) => index.updateBuffer(
        sessionId: 'open',
        path: '/vault/Origin.md',
        name: 'Origin.md',
        text: text,
      );
      edit('[[New]] #new');
      var result = await references.refresh();
      expect(result.backlinks('Old.md'), isEmpty);
      expect(result.backlinks('New.md'), hasLength(1));
      expect(result.tags.containsKey('old'), isFalse);
      expect(result.tags['new']!.single.note.source.fromBuffer, isTrue);
      final parsed = references.parseCount;
      edit('[[Old]] #again');
      result = await references.refresh();
      expect(result.backlinks('New.md'), isEmpty);
      expect(result.backlinks('Old.md'), hasLength(1));
      expect(references.parseCount, parsed + 1);
      final unchanged = references.parseCount;
      edit('[[Old]] #again');
      await references.refresh();
      expect(references.parseCount, unchanged);
      index.removeBuffer('open');
      result = await references.refresh();
      expect(result.tags.containsKey('again'), isFalse);
      expect(result.tags['old'], hasLength(1));
    },
  );

  test(
    'all bounded aliases and keys are indexed, without UI truncation',
    () async {
      final prefix = List.generate(45, (i) => 'key$i: value').join('\n');
      final aliases = List.generate(20, (i) => 'Alias$i').join(', ');
      source.note('Origin.md', '[[Alias19]]');
      source.note('Target.md', '---\n$prefix\naliases: [$aliases]\n---\nbody');
      final result = await references.refresh();
      expect(result.aliases.complete, isTrue);
      expect(result.aliases.byPath['Target.md'], hasLength(20));
      expect(result.backlinks('Target.md'), hasLength(1));
      final resolution = await references.resolveWiki(
        'Alias19',
        originPath: '/vault/Origin.md',
      );
      expect(resolution.status, WikiNoteStatus.resolved);
      expect(resolution.candidates.single.relativePath, 'Target.md');
    },
  );

  test(
    'alias does not override filename and independent alias conflicts require a choice',
    () async {
      source.note('Origin.md', '[[Same]]');
      source.note('Same.md', 'body');
      source.note('Other.md', '---\naliases: [Same]\n---\nbody');
      final result = await references.refresh();
      expect(result.backlinks('Same.md'), isEmpty);
      final edge = result.edges.single;
      expect(edge.status, WorkspaceReferenceStatus.ambiguous);
      expect(edge.candidatePaths, ['Other.md', 'Same.md']);
      final resolution = await references.resolveWiki(
        'Same',
        originPath: '/vault/Origin.md',
      );
      expect(resolution.status, WikiNoteStatus.ambiguous);
      final explicit = await references.resolveWiki(
        '/Same.md',
        originPath: '/vault/Origin.md',
      );
      expect(explicit.status, WikiNoteStatus.resolved);
      expect(explicit.candidates.single.relativePath, 'Same.md');
      expect(result.impact('Same.md').complete, isFalse);
      expect(result.impact('Same.md').possibleReferences, hasLength(1));
    },
  );

  test(
    'offline and unsupported YAML remain unknown, never download or create',
    () async {
      source.note('Origin.md', '[[Target]]');
      source.note('Target.md', 'body');
      source.note('Cloud.md', '---\naliases: [Target]\n---', local: false);
      final result = await references.refresh();
      expect(result.complete, isFalse);
      expect(result.aliases.complete, isFalse);
      expect(result.backlinks('Target.md'), isEmpty);
      expect(result.edges.single.status, WorkspaceReferenceStatus.unknown);
      expect(source.readCounts['/vault/Cloud.md'], isNull);
      expect(source.downloads, 0);
      expect(
        (await references.resolveWiki(
          'Missing',
          originPath: '/vault/Origin.md',
        )).status,
        WikiNoteStatus.unavailable,
      );
      expect(
        (await references.resolveWiki(
          '/Target.md',
          originPath: '/vault/Origin.md',
        )).status,
        WikiNoteStatus.resolved,
      );
    },
  );

  test(
    'Markdown percent destinations decode once, and fragments do not change identity',
    () async {
      source.note(
        'Origin.md',
        '[space](A%20B.md#Heading) [percent](A%2520B.md)',
      );
      source.note('A B.md', 'body');
      source.note('A%20B.md', 'body');
      final result = await references.refresh();
      expect(result.backlinks('A B.md'), hasLength(1));
      expect(result.backlinks('A%20B.md'), hasLength(1));
      expect(
        result
            .backlinks('A B.md')
            .single
            .reference
            .destinationRange
            .textInside(result.notes['/vault/Origin.md']!.source.text),
        'A%20B.md',
      );
    },
  );

  test(
    'a leading FEFF filename is not bound to a different note after URI decoding',
    () async {
      references.dispose();
      references = WorkspaceReferenceIndex(
        index,
        normalize: (paths) async =>
            paths.map((path) => path.toLowerCase()).toList(),
      );
      source.note('Origin.md', '[raw](\ufeffA.md) [encoded](%EF%BB%BFA.md)');
      source.note('\ufeffA.md', 'actual target');
      source.note('A.md', 'distinct filename');
      final result = await references.refresh();
      expect(result.complete, isTrue, reason: result.issues.toString());
      expect(result.backlinks('\ufeffA.md'), hasLength(2));
      expect(result.backlinks('A.md'), isEmpty);
      expect(result.impact('A.md').references, isEmpty);
    },
  );

  test(
    'catalog changes re-resolve unchanged text and remove old edges',
    () async {
      source.note('Origin.md', '[[Same]]');
      source.note('Same.md', 'body');
      var result = await references.refresh();
      expect(result.backlinks('Same.md'), hasLength(1));
      final parsed = references.parseCount;
      source.note('same.md', 'different real file');
      result = await references.refresh(refreshMetadata: true);
      expect(result.backlinks('Same.md'), isEmpty);
      expect(result.edges.single.status, WorkspaceReferenceStatus.ambiguous);
      expect(references.parseCount, parsed + 1);
    },
  );

  test('old asynchronous read cannot overwrite newer dirty overlay', () async {
    source.note('Origin.md', '[[Old]]');
    source.note('Old.md', 'old');
    source.note('New.md', 'new');
    final gate = Completer<WorkspaceTextRead>();
    source.onRead = (_, path) => path == 'Origin.md'
        ? gate.future
        : Future.value(source.texts['/vault/$path']);
    final future = references.refresh();
    await Future<void>.delayed(Duration.zero);
    index.updateBuffer(
      sessionId: 'open',
      path: '/vault/Origin.md',
      name: 'Origin.md',
      text: '[[New]] #current',
    );
    gate.complete(const WorkspaceTextRead('[[Old]]', 'v1'));
    final result = await future;
    expect(result.backlinks('Old.md'), isEmpty);
    expect(result.backlinks('New.md'), hasLength(1));
    expect(
      result.notes['/vault/Origin.md']!.source.revision,
      startsWith('buffer:'),
    );
  });

  test(
    'byte and document limits are visible and never masquerade as absence',
    () async {
      references.dispose();
      references = WorkspaceReferenceIndex(
        index,
        maximumSourceBytes: 64,
        maximumDocuments: 2,
      );
      for (var i = 0; i < 1000; i++) {
        source.note('$i.md', '[[Target]] #tag');
      }
      final result = await references.refresh();
      expect(result.knownDocuments, 1000);
      expect(result.notes.length, lessThanOrEqualTo(2));
      expect(references.cachedBytes, lessThanOrEqualTo(64));
      expect(result.complete, isFalse);
      expect(result.aliases.complete, isFalse);
      expect(source.readCounts.length, lessThanOrEqualTo(3));
    },
  );

  test('standalone buffers derive tags without parent enumeration', () async {
    index.configure(null);
    index.updateBuffer(
      sessionId: 'draft',
      path: null,
      name: 'Untitled',
      text: '#hello',
    );
    final result = await references.refresh();
    expect(result.tags['hello'], hasLength(1));
    expect(result.complete, isTrue);
    expect(source.listCounts, isEmpty);
    expect(source.readCounts, isEmpty);
  });
  test(
    'cancelled scan never publishes and a later explicit refresh can retry',
    () async {
      source.note('Origin.md', '[[Target]]');
      source.note('Target.md', 'body');
      final gate = Completer<WorkspaceTextRead>();
      source.onRead = (_, path) => path == 'Origin.md'
          ? gate.future
          : Future.value(source.texts['/vault/$path']);
      final future = references.refresh();
      await Future<void>.delayed(Duration.zero);
      references.cancel();
      final rejected = expectLater(
        future,
        throwsA(isA<WorkspaceIndexFailure>()),
      );
      gate.complete(const WorkspaceTextRead('[[Target]]', 'v1'));
      await rejected;
      expect(references.snapshot, isNull);
      expect(references.stale, isTrue);
      expect(references.previewImpact('Target.md').complete, isFalse);
      final result = await references.refresh();
      expect(result.backlinks('Target.md'), hasLength(1));
      expect(references.cancelled, isFalse);
    },
  );

  test(
    'root switch and return never restores old note revision edges',
    () async {
      source.note('Origin.md', '[[Target]]');
      source.note('Target.md', 'body');
      final before = await references.refresh();
      expect(before.backlinks('Target.md'), hasLength(1));
      index.configure('/other');
      expect(references.snapshot, isNull);
      final other = await references.refresh();
      expect(other.edges, isEmpty);
      source.note('Origin.md', 'new source #changed', revision: 'v2');
      index.configure('/vault');
      final after = await references.refresh();
      expect(after.backlinks('Target.md'), isEmpty);
      expect(after.tags['changed'], hasLength(1));
      expect(after.epoch, isNot(before.epoch));
    },
  );

  test(
    'image Wiki embeds are not mistaken for similarly named Markdown files',
    () async {
      source.note('Origin.md', '![[photo.png|120]]\n\n[[photo.png]]');
      source.note('photo.png.md', 'note');
      final result = await references.refresh();
      final image = result.edges.firstWhere(
        (edge) =>
            edge.reference.kind == IanvsMarkdownSourceReferenceKind.wikiEmbed,
      );
      expect(image.status, WorkspaceReferenceStatus.external);
      expect(result.backlinks('photo.png.md'), hasLength(1));
    },
  );

  test(
    'fragment-only references have no rename-affected destination',
    () async {
      source.note('Origin.md', '[here](#Heading) [[#Heading]]');
      final result = await references.refresh();
      expect(result.backlinks('Origin.md'), hasLength(2));
      expect(result.impact('Origin.md').references, isEmpty);
      expect(
        result.edges.every(
          (edge) => edge.reference.destinationRange.isCollapsed,
        ),
        isTrue,
      );
    },
  );
  for (final count in [10000, 50000]) {
    test(
      'catalog of $count notes keeps a bounded semantic body cache',
      () async {
        references.dispose();
        references = WorkspaceReferenceIndex(
          index,
          maximumSourceBytes: 64,
          maximumDocuments: 2,
        );
        source.directories['/vault/'] = WorkspaceDirectorySnapshot([
          for (var i = 0; i < count; i++)
            WorkspaceMetadata(
              relativePath: '$i.md',
              isDirectory: false,
              revision: 'v1',
              size: 14,
              local: true,
            ),
        ]);
        source.onRead = (_, _) async =>
            const WorkspaceTextRead('[[Target]] #tag', 'v1');
        final result = await references.refresh();
        expect(result.knownDocuments, count);
        expect(result.notes.length, lessThanOrEqualTo(2));
        expect(references.cachedBytes, lessThanOrEqualTo(64));
        expect(result.complete, isFalse);
        expect(result.aliases.complete, isFalse);
        expect(source.readCounts.length, lessThanOrEqualTo(3));
        expect(source.downloads, 0);
      },
    );
  }

  test(
    'unsupported file URI and stale impact never claim an empty safe rename',
    () async {
      source.note('Origin.md', '[local](file:///vault/Target.md)');
      source.note('Target.md', 'body');
      final result = await references.refresh();
      expect(result.edges.single.status, WorkspaceReferenceStatus.unknown);
      expect(result.complete, isFalse);
      expect(references.previewImpact('Target.md').complete, isFalse);
      index.updateBuffer(
        sessionId: 'origin',
        path: '/vault/Origin.md',
        name: 'Origin.md',
        text: '[[Target]]',
      );
      expect(references.previewImpact('Target.md').complete, isFalse);
      await references.refresh();
      expect(references.previewImpact('Target.md').references, hasLength(1));
      expect(references.previewImpact('../Target.md').complete, isFalse);
      final rechecking = references.refresh(refreshMetadata: true);
      expect(references.previewImpact('Target.md').complete, isFalse);
      await rechecking;
      expect(references.previewImpact('Target.md').complete, isTrue);
    },
  );

  for (final initiallyForced in [false, true]) {
    test(
      'forced refresh during a captured scan (forced=$initiallyForced) rechecks new alias identities before publication',
      () async {
        source.note('Origin.md', '[[NewAlias]]');
        final entered = Completer<void>();
        final release = Completer<void>();
        source.onRead = (root, path) async {
          if (path == 'Origin.md' && !entered.isCompleted) {
            entered.complete();
            await release.future;
          }
          return source.texts['$root/$path']!;
        };
        final scanning = references.refresh(refreshMetadata: initiallyForced);
        await entered.future;
        source.note('New.md', '---\naliases: [NewAlias]\n---\nbody');
        final forced = references.resolveWiki(
          'NewAlias',
          originPath: '/vault/Origin.md',
          refreshMetadata: true,
        );
        release.complete();
        final resolution = await forced;
        final snapshot = await scanning;
        expect(resolution.status, WikiNoteStatus.resolved);
        expect(snapshot.backlinks('New.md'), hasLength(1));
        expect(snapshot.aliases.byPath['New.md'], {'newalias'});
        expect(source.listCounts['/vault/'], 2);
        expect(source.downloads, 0);
      },
    );
  }

  test(
    'per-cell table parsing cannot manufacture cross-cell backlinks',
    () async {
      source.note(
        'Origin.md',
        '| a | b |\n| --- | --- |\n| [[Target | Alias]] |\n\n[[Target]] #outside',
      );
      source.note('Target.md', 'target');
      final result = await references.refresh();
      expect(result.backlinks('Target.md'), hasLength(1));
      expect(result.complete, isTrue);
      expect(result.aliases.complete, isTrue);
      expect(references.previewImpact('Target.md').complete, isTrue);
      expect(result.tags.keys, ['outside']);
    },
  );

  test(
    'body coverage unknown does not silently discard complete YAML aliases',
    () async {
      source.note('Origin.md', '[[Alias]]');
      source.note(
        'Target.md',
        '---\naliases: [Alias]\n---\n<div>unsupported</div>',
      );
      final result = await references.refresh();
      expect(result.complete, isFalse);
      expect(result.aliases.complete, isTrue);
      expect(result.backlinks('Target.md'), hasLength(1));
      expect(result.impact('Target.md').complete, isFalse);
    },
  );
}
