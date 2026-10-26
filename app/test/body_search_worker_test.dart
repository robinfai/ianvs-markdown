import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/services/body_search_worker.dart';
import 'package:linefold/src/controllers/document_find_controller.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  test(
    'large body controller publishes real background results without moving selection',
    () async {
      final source = List.filled(
        3000,
        'visible phrase filler words\n\n',
      ).join();
      final document = IanvsMarkdownController(text: source);
      final before = document.value;
      final find = DocumentFindController(
        document: document,
        scope: DocumentFindScope.body,
        query: 'visible phrase',
      );
      addTearDown(find.dispose);
      addTearDown(document.dispose);
      final finished = Completer<void>();
      find.addListener(() {
        if (!find.isSearching && !finished.isCompleted) finished.complete();
      });
      await finished.future.timeout(const Duration(seconds: 10));
      expect(find.bodyUnavailable, isFalse);
      expect(find.count, 3000);
      expect(find.currentIndex, 0);
      expect(document.value, before);
      expect(document.canUndo, isFalse);
    },
  );

  test(
    'real worker caches source semantics across queries and updates source',
    () async {
      final worker = BodySearchWorker();
      addTearDown(worker.dispose);
      final source =
          'hello **world** [label](hidden)\n\n${List.filled(2999, 'hello world filler words\n\n').join()}';
      expect(source.length, greaterThanOrEqualTo(64 * 1024));
      final result = await worker.search(
        source: source,
        query: 'hello world',
        matchCase: false,
      );
      expect(result!.available, isTrue);
      expect(result.matches.length, 3000);
      expect(
        (await worker.search(
          source: source,
          query: 'hidden',
          matchCase: false,
        ))!.matches,
        isEmpty,
      );
      expect(
        (await worker.search(
          source: 'new text',
          query: 'new',
          matchCase: true,
        ))!.matches.length,
        1,
      );
    },
  );

  test(
    'worker coalesces queued requests and disposal settles pending futures',
    () async {
      final worker = BodySearchWorker();
      final first = worker.search(
        source: 'alpha beta',
        query: 'alpha',
        matchCase: false,
      );
      final second = worker.search(
        source: 'alpha beta',
        query: 'beta',
        matchCase: false,
      );
      final third = worker.search(
        source: 'alpha beta',
        query: 'missing',
        matchCase: false,
      );
      expect(await first, isNull);
      expect(await second, isNull);
      expect((await third)!.matches, isEmpty);
      final pending = worker.search(
        source: 'one',
        query: 'one',
        matchCase: false,
      );
      worker.dispose();
      expect(await pending, isNull);
      expect(
        await worker.search(source: '', query: '', matchCase: false),
        isNull,
      );
    },
  );

  test(
    'worker reports render-budget rejection separately from no matches',
    () async {
      final worker = BodySearchWorker();
      addTearDown(worker.dispose);
      final result = await worker.search(
        source: 'x' * 5000,
        query: 'x',
        matchCase: false,
      );
      expect(result!.available, isFalse);
      expect(result.matches, isEmpty);
    },
  );

  test(
    'controller ignores stale background results after scope switch and dispose',
    () async {
      final source = List.filled(
        4000,
        'visible phrase filler words\n\n',
      ).join();
      final document = IanvsMarkdownController(text: source);
      final find = DocumentFindController(
        document: document,
        scope: DocumentFindScope.body,
        query: 'visible phrase',
      );
      addTearDown(document.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 160));
      find.setScope(DocumentFindScope.source);
      find.query.text = 'absent';
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(find.scope, DocumentFindScope.source);
      expect(find.bodyMatches, isEmpty);
      expect(find.count, 0);
      find.setScope(DocumentFindScope.body);
      await Future<void>.delayed(const Duration(milliseconds: 160));
      find.dispose();
    },
  );
}
