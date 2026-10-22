import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/preview/preview_controller.dart';
import 'package:linefold/src/preview/preview_library.dart';
import 'package:linefold/src/preview/preview_platform.dart';
import 'package:linefold/src/services/apple_workspace_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('retrying initialization clears an earlier failure', () async {
    final library = _Library()..listFailure = StateError('offline');
    final controller = PreviewController(library: library);
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.canRetry, isTrue);
    expect(controller.error, isNotNull);
    library.listFailure = null;
    await controller.retry();
    expect(controller.initialized, isTrue);
    expect(controller.error, isNull);
    expect(controller.canRetry, isFalse);
  });

  test(
    'manual refresh rereads only active body and refreshes the list',
    () async {
      final library = _Library();
      final controller = PreviewController(library: library);
      addTearDown(controller.dispose);
      await controller.open('/a/note.md');
      library.text = '# Remote update';
      await controller.refresh();
      expect(controller.contents, '# Remote update');
      expect(library.reads, ['/a/note.md']);
      expect(library.refreshReads, ['/a/note.md']);
      expect(library.listCalls, 2);
      expect(controller.busy, isFalse);
    },
  );

  test(
    'failed refresh preserves body, path and root and allows retry',
    () async {
      final library = _Library()..workspace = _workspace('/a');
      final controller = PreviewController(library: library);
      addTearDown(controller.dispose);
      await controller.open('/a/note.md');
      library.refreshFailure = StateError('offline');
      await controller.refresh();
      expect(controller.contents, '# Original');
      expect(controller.activePath, '/a/note.md');
      expect(controller.activeRoot, '/a');
      expect(controller.error, contains('已保留当前内容'));
      expect(controller.canRetry, isTrue);
      library.refreshFailure = null;
      library.text = '# Retry result';
      await controller.retry();
      expect(controller.contents, '# Retry result');
      expect(controller.error, isNull);
      expect(controller.canRetry, isFalse);
    },
  );

  test('body failure still publishes refreshed library entries', () async {
    final library = _Library();
    final controller = PreviewController(library: library);
    addTearDown(controller.dispose);
    await controller.open('/a/note.md');
    library.refreshFailure = StateError('body offline');
    library.entries = [_document('/a/new.md')];
    await controller.refresh();
    expect(controller.contents, '# Original');
    expect(controller.documents.single.path, '/a/new.md');
    expect(library.listCalls, 2);
    expect(controller.error, contains('正文刷新失败'));
    expect(controller.canRetry, isTrue);
  });

  testWidgets('slow body does not hold back list, and failures combine', (
    tester,
  ) async {
    final library = _Library();
    final controller = PreviewController(
      library: library,
      operationTimeout: const Duration(seconds: 1),
    );
    addTearDown(controller.dispose);
    await controller.open('/a/note.md');
    final pending = Completer<String>();
    library.pendingRefresh = pending;
    library.entries = [_document('/a/new.md')];
    final refresh = controller.refresh();
    await tester.pump();
    expect(controller.documents.single.path, '/a/new.md');
    expect(controller.busy, isTrue);
    await tester.pump(const Duration(seconds: 1));
    await refresh;
    expect(controller.contents, '# Original');
    expect(controller.error, contains('正文刷新超时'));
    pending.complete('# Late');
    await tester.pump();
    expect(controller.contents, '# Original');
    library.pendingRefresh = null;
    library.refreshFailure = StateError('body offline');
    library.listFailure = StateError('list offline');
    await controller.retry();
    expect(controller.error, contains('正文刷新失败'));
    expect(controller.error, contains('列表刷新失败'));
    expect(controller.contents, '# Original');
    expect(controller.documents.single.path, '/a/new.md');
  });

  test(
    'native busy preserves body while list completes and retry recovers',
    () async {
      final library = _Library();
      final controller = PreviewController(library: library);
      addTearDown(controller.dispose);
      await controller.open('/a/note.md');
      library.refreshFailure = PlatformException(code: 'workspace_busy');
      library.entries = [_document('/a/new.md')];
      await controller.refresh();
      expect(controller.contents, '# Original');
      expect(controller.documents.single.path, '/a/new.md');
      expect(controller.error, contains('正文读取繁忙'));
      expect(controller.busy, isFalse);
      expect(controller.canRetry, isTrue);
      library.refreshFailure = null;
      library.text = '# Retry after native worker completed';
      await controller.retry();
      expect(controller.contents, '# Retry after native worker completed');
      expect(controller.error, isNull);
    },
  );

  test('failed list does not discard successfully refreshed body', () async {
    final library = _Library();
    final controller = PreviewController(library: library);
    addTearDown(controller.dispose);
    await controller.open('/a/note.md');
    library.text = '# Updated';
    library.listFailure = StateError('listing offline');
    await controller.refresh();
    expect(controller.contents, '# Updated');
    expect(controller.canRetry, isTrue);
    expect(controller.busy, isFalse);
  });

  for (final action in ['new open', 'library', 'cancel', 'workspace ABA']) {
    test('late body cannot overwrite $action', () async {
      final library = _Library()..workspace = _workspace('/a');
      final controller = PreviewController(library: library);
      addTearDown(controller.dispose);
      await controller.open('/a/note.md');
      final pending = Completer<String>();
      library.pendingRefresh = pending;
      final refresh = controller.refresh();
      switch (action) {
        case 'new open':
          library.text = '# New document';
          await controller.open('/a/new.md');
        case 'library':
          controller.showLibrary();
        case 'cancel':
          controller.cancelPendingOperation();
        case 'workspace ABA':
          library.workspace = _workspace('/b');
          library.workspace = _workspace('/a');
      }
      pending.complete('# Stale');
      await refresh;
      expect(controller.contents, switch (action) {
        'new open' => '# New document',
        'library' => null,
        _ => '# Original',
      });
      expect(controller.error, isNull);
      expect(controller.busy, isFalse);
    });
  }

  test(
    'a pending open is invalidated even when workspace returns to same root',
    () async {
      final library = _Library()..workspace = _workspace('/a');
      final controller = PreviewController(library: library);
      addTearDown(controller.dispose);
      await controller.open('/a/note.md');
      final pending = Completer<String>();
      library.pendingRead = pending;
      final opening = controller.open('/a/old.md');
      library.workspace = _workspace('/b');
      library.workspace = _workspace('/a');
      pending.complete('# Stale');
      await opening;
      expect(controller.activePath, '/a/note.md');
      expect(controller.contents, '# Original');
      expect(controller.busy, isFalse);
      expect(controller.error, isNull);
    },
  );

  test('late failure cannot surface after newer open', () async {
    final library = _Library();
    final controller = PreviewController(library: library);
    addTearDown(controller.dispose);
    await controller.open('/a/note.md');
    final pending = Completer<String>();
    library.pendingRefresh = pending;
    final refresh = controller.refresh();
    await controller.open('/a/new.md');
    pending.completeError(StateError('old error'));
    await refresh;
    expect(controller.error, isNull);
    expect(controller.activePath, '/a/new.md');
  });

  test(
    'late list cannot overwrite a newer scope after refreshed body',
    () async {
      final library = _Library();
      final controller = PreviewController(library: library);
      addTearDown(controller.dispose);
      await controller.open('/a/note.md');
      final pending = Completer<List<PreviewDocument>>();
      library.pendingList = pending;
      final refresh = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      library.pendingList = null;
      await controller.open('/a/new.md');
      final currentDocuments = controller.documents;
      pending.complete([_document('/a/stale.md')]);
      await refresh;
      expect(controller.documents, same(currentDocuments));
      expect(controller.activePath, '/a/new.md');
    },
  );

  test('overlapping explicit refreshes share one body read', () async {
    final library = _Library();
    final controller = PreviewController(library: library);
    addTearDown(controller.dispose);
    await controller.open('/a/note.md');
    final pending = Completer<String>();
    library.pendingRefresh = pending;
    final first = controller.refresh();
    final second = controller.refresh();
    expect(second, same(first));
    expect(library.refreshReads, hasLength(1));
    pending.complete('# Updated');
    await Future.wait([first, second]);
    expect(library.listCalls, 2);
  });

  testWidgets('cloud bursts throttle and coalesce one trailing refresh', (
    tester,
  ) async {
    final library = _Library();
    final controller = PreviewController(library: library);
    addTearDown(controller.dispose);
    await controller.open('/a/note.md');
    final pending = Completer<String>();
    library.pendingRefresh = pending;
    for (var i = 0; i < 20; ++i) {
      controller.notifyCloudChange();
    }
    await tester.pump(const Duration(milliseconds: 499));
    expect(library.refreshReads, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(library.refreshReads, hasLength(1));
    for (var i = 0; i < 20; ++i) {
      controller.notifyCloudChange();
    }
    await tester.pump(const Duration(seconds: 1));
    expect(library.refreshReads, hasLength(1));
    library.pendingRefresh = null;
    library.text = '# Latest';
    pending.complete('# First');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(library.refreshReads, hasLength(2));
    expect(controller.contents, '# Latest');
    expect(controller.busy, isFalse);
  });

  testWidgets('timeout clears busy, retries and ignores eventual old result', (
    tester,
  ) async {
    final library = _Library();
    final controller = PreviewController(
      library: library,
      operationTimeout: const Duration(seconds: 1),
    );
    addTearDown(controller.dispose);
    await controller.open('/a/note.md');
    final pending = Completer<String>();
    library.pendingRefresh = pending;
    final refresh = controller.refresh();
    expect(controller.busy, isTrue);
    await tester.pump(const Duration(seconds: 1));
    await refresh;
    expect(controller.busy, isFalse);
    expect(controller.contents, '# Original');
    expect(controller.error, contains('超时'));
    library.pendingRefresh = null;
    library.text = '# Retry';
    await controller.retry();
    pending.complete('# Late');
    await tester.pump();
    expect(controller.contents, '# Retry');
    expect(controller.error, isNull);
  });

  test(
    'picker cancel retains current document while invalidating old read',
    () async {
      final library = _Library();
      final controller = PreviewController(library: library);
      addTearDown(controller.dispose);
      await controller.open('/a/note.md');
      final pending = Completer<String>();
      library.pendingRefresh = pending;
      final refresh = controller.refresh();
      await controller.changeWorkspace();
      pending.complete('# Stale');
      await refresh;
      expect(controller.activePath, '/a/note.md');
      expect(controller.contents, '# Original');
      expect(controller.busy, isFalse);
    },
  );

  test(
    'pending workspace handoff cannot be superseded by navigation',
    () async {
      final pending = Completer<Map<String, Object>>();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(PreviewPlatform.channel, (call) async {
        if (call.method == 'chooseWorkspace') return pending.future;
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(PreviewPlatform.channel, null),
      );
      final library = _Library(workspaceService: const AppleWorkspaceService())
        ..workspace = _workspace('/a');
      final controller = PreviewController(library: library);
      addTearDown(controller.dispose);
      final selection = controller.changeWorkspace();
      controller.showLibrary();
      expect(controller.selectingWorkspace, isTrue);
      pending.complete({'path': '/b', 'name': 'B', 'isCloud': false});
      await selection;
      expect(library.workspace!.path, '/b');
      expect(controller.selectingWorkspace, isFalse);
      expect(controller.contents, isNull);
      expect(controller.error, isNull);
    },
  );

  test('receive stops remaining files after a newer user intent', () async {
    final library = _Library();
    final controller = PreviewController(library: library);
    addTearDown(controller.dispose);
    final pending = Completer<String>();
    library.pendingRead = pending;
    final receive = controller.receive(['/a/one.md', '/a/two.md']);
    await Future<void>.delayed(Duration.zero);
    controller.showLibrary();
    pending.complete('# Stale delivery');
    await receive;
    expect(library.reads, ['/a/one.md']);
    expect(controller.contents, isNull);
    expect(controller.error, isNull);
  });

  test(
    'disposing with an in-flight refresh suppresses notification and results',
    () async {
      final library = _Library();
      final controller = PreviewController(library: library);
      await controller.open('/a/note.md');
      final pending = Completer<String>();
      library.pendingRefresh = pending;
      final refresh = controller.refresh();
      controller.dispose();
      pending.complete('# After dispose');
      await refresh;
      expect(controller.contents, '# Original');
    },
  );
}

PreviewWorkspace _workspace(String path) =>
    PreviewWorkspace(path: path, name: path, isCloud: false);

PreviewDocument _document(String path) =>
    PreviewDocument(path: path, name: path, openedAt: DateTime(2026));

class _Library extends PreviewLibrary {
  _Library({super.workspaceService});
  String text = '# Original';
  Object? refreshFailure;
  Object? listFailure;
  Completer<String>? pendingRead;
  Completer<String>? pendingRefresh;
  Completer<List<PreviewDocument>>? pendingList;
  final reads = <String>[];
  final refreshReads = <String>[];
  int listCalls = 0;
  List<PreviewDocument> entries = [_document('/a/note.md')];

  @override
  Future<String> read(String path) async {
    reads.add(path);
    return pendingRead?.future ?? text;
  }

  @override
  Future<String> refreshContent(String path) async {
    refreshReads.add(path);
    if (refreshFailure case final failure?) throw failure;
    return pendingRefresh?.future ?? text;
  }

  @override
  Future<List<PreviewDocument>> list() async {
    ++listCalls;
    if (listFailure case final failure?) throw failure;
    return pendingList?.future ?? entries;
  }
}
