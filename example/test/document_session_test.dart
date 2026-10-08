import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

import 'package:ianvs_markdown_example/document_session.dart';

void main() {
  test(
    'serializes captured writes with the original document identity',
    () async {
      final started = <String>[];
      final firstWrite = Completer<void>();
      final session = ExampleDocumentSession(
        id: 'document-a',
        source: 'initial',
        write: (id, source) async {
          started.add('$id:$source');
          if (source == 'first') await firstWrite.future;
        },
      );
      addTearDown(session.dispose);
      final first = session.persist('first');
      final second = session.persist('second');
      await Future<void>.delayed(Duration.zero);
      expect(started, ['document-a:first']);
      firstWrite.complete();
      await Future.wait([first, second]);
      expect(started, ['document-a:first', 'document-a:second']);
      expect(session.controller.text, 'initial');
    },
  );

  test('a failed write does not poison the retry queue', () async {
    final completed = <String>[];
    final session = ExampleDocumentSession(
      id: 'document-a',
      source: 'initial',
      write: (id, source) async {
        if (source == 'failed') throw StateError('storage unavailable');
        completed.add(source);
      },
    );
    addTearDown(session.dispose);
    await expectLater(session.persist('failed'), throwsStateError);
    await session.persist('retry');
    expect(completed, ['retry']);
  });

  test(
    'closing lets the active write finish and rejects queued writes',
    () async {
      final started = <String>[];
      final active = Completer<void>();
      final session = ExampleDocumentSession(
        id: 'document-a',
        source: 'initial',
        write: (id, source) async {
          started.add(source);
          await active.future;
        },
      );
      final first = session.persist('active');
      final second = session.persist('queued');
      final cancelled = expectLater(
        second,
        throwsA(isA<IanvsMarkdownSaveCancelledException>()),
      );
      await Future<void>.delayed(Duration.zero);
      session.dispose();
      active.complete();
      await first;
      await cancelled;
      expect(started, ['active']);
      await expectLater(
        session.persist('after-close'),
        throwsA(isA<IanvsMarkdownSaveCancelledException>()),
      );
    },
  );
}
