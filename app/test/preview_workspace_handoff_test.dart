import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:linefold/src/preview/preview_app.dart';
import 'package:linefold/src/preview/preview_editor_controller.dart';
import 'package:linefold/src/preview/preview_draft_store.dart';
import 'preview_test_support.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/preview/preview_controller.dart';
import 'package:linefold/src/preview/preview_library.dart';
import 'package:linefold/src/preview/preview_platform.dart';
import 'package:linefold/src/services/apple_workspace_service.dart';
import 'package:linefold/src/models/document_sync_status.dart';

class GrantLibrary extends PreviewLibrary {
  GrantLibrary() : super(workspaceService: const AppleWorkspaceService()) {
    workspace = const PreviewWorkspace(
      path: '/vault',
      name: 'vault',
      isCloud: false,
      workspaceToken: 'epoch-a',
    );
  }
  @override
  Future<String> read(String path) async => '# Existing';
  @override
  Future<String> readSource(String path) async => '# Existing';
  @override
  Future<List<PreviewDocument>> list() async => [];
  @override
  Future<DocumentSyncMetadata> readSyncMetadata(String path) async =>
      const DocumentSyncMetadata();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late GrantLibrary library;
  late PreviewController controller;
  late Completer<void> called;
  late Completer<Map<String, dynamic>?> reply;
  late List<Future<Map<String, dynamic>?>> responses;
  late int selectionCalls;
  late String nativeRoot, nativeToken;
  setUp(() {
    library = GrantLibrary();
    controller = PreviewController(
      library: library,
      operationTimeout: const Duration(milliseconds: 30),
    );
    called = Completer<void>();
    reply = Completer<Map<String, dynamic>?>();
    responses = [];
    selectionCalls = 0;
    nativeRoot = '/vault';
    nativeToken = 'epoch-a';
    messenger.setMockMethodCallHandler(PreviewPlatform.channel, (call) async {
      if (call.method == 'defaultWorkspace' ||
          call.method == 'chooseWorkspace') {
        ++selectionCalls;
        if (!called.isCompleted) called.complete();
        final result = await (responses.isNotEmpty
            ? responses.removeAt(0)
            : reply.future);
        if (result != null) {
          nativeRoot = result['path'] as String;
          nativeToken = result['workspaceToken'] as String;
        }
        return result;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(AppleWorkspaceService.channel, (
      call,
    ) async {
      if (call.method == 'createWorkspaceNote' ||
          call.method == 'writeWorkspaceNoteGuarded') {
        if (call.arguments['path'] != nativeRoot ||
            call.arguments['workspaceToken'] != nativeToken) {
          throw PlatformException(
            code: 'workspace_unavailable',
            message: 'revoked native grant',
          );
        }
        return true;
      }
      return null;
    });
  });
  tearDown(() {
    controller.dispose();
    messenger.setMockMethodCallHandler(PreviewPlatform.channel, null);
    messenger.setMockMethodCallHandler(AppleWorkspaceService.channel, null);
  });
  Future<void> activateAndReply() async {
    // Native WorkspaceWriteAuthority.activate replaces the active grant before
    // the main-thread Flutter result is delivered, including late results.
    reply.complete({
      'path': '/default',
      'name': 'default',
      'isCloud': false,
      'workspaceToken': 'epoch-b',
    });
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> assertNoAdvertisedRevokedGrant() async {
    final revoked =
        library.workspace?.path != nativeRoot ||
        library.workspace?.workspaceToken != nativeToken;
    if (library.canWrite && revoked) {
      await expectLater(
        library.createNote('new.md', generation: library.workspaceGeneration),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(
        library.writeSource(
          '/vault/note.md',
          '# Edited',
          expectedContents: '# Existing',
          generation: library.workspaceGeneration,
        ),
        throwsA(isA<PlatformException>()),
      );
    }
    expect(library.canWrite, isTrue);
    await library.createNote('new.md', generation: library.workspaceGeneration);
    await library.writeSource(
      '$nativeRoot/note.md',
      '# Edited',
      expectedContents: '# Existing',
      generation: library.workspaceGeneration,
    );
    expect(
      library.canWrite && revoked,
      isFalse,
      reason:
          'Dart advertises writable ${library.workspace?.workspaceToken}, while native grant is $nativeToken. Both Save and Create were denied.',
    );
  }

  test(
    'cancelled delivery must not advertise a grant revoked by its late native default result',
    () async {
      await controller.open('/vault/note.md');
      final pending = controller.receive(['/default/import.md']);
      await called.future;
      controller.showLibrary();
      controller.cancelPendingOperation();
      await controller.open('/vault/other.md');
      expect(controller.selectingWorkspace, isTrue);
      expect(library.canWrite, isFalse);
      expect(controller.activePath, '/vault/note.md');
      await activateAndReply();
      await pending;
      await assertNoAdvertisedRevokedGrant();
    },
  );
  test(
    'timed-out delivery must reconcile its late native default activation',
    () async {
      await controller.open('/vault/note.md');
      final pending = controller.receive(['/default/import.md']);
      await called.future;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(controller.error, isNotNull);
      expect(controller.selectingWorkspace, isTrue);
      expect(library.canWrite, isFalse);
      await activateAndReply();
      await pending;
      await assertNoAdvertisedRevokedGrant();
    },
  );
  test(
    'superseded folder selection must not advertise a revoked previous grant',
    () async {
      await controller.open('/vault/note.md');
      final pending = controller.changeWorkspace();
      await called.future;
      controller.showLibrary();
      controller.cancelPendingOperation();
      await controller.open('/vault/other.md');
      expect(controller.selectingWorkspace, isTrue);
      expect(library.canWrite, isFalse);
      expect(controller.activePath, '/vault/note.md');
      await activateAndReply();
      await pending;
      await assertNoAdvertisedRevokedGrant();
    },
  );
  for (final cancel in [true, false]) {
    test(
      'picker ${cancel ? 'cancel' : 'failure'} retains the current native capability',
      () async {
        await controller.open('/vault/note.md');
        final pending = controller.changeWorkspace();
        await called.future;
        expect(library.canWrite, isFalse);
        if (cancel) {
          reply.complete(null);
        } else {
          reply.completeError(PlatformException(code: 'folder_unavailable'));
        }
        await pending;
        expect(controller.activePath, '/vault/note.md');
        expect(library.workspace!.workspaceToken, 'epoch-a');
        expect(controller.selectingWorkspace, isFalse);
        await assertNoAdvertisedRevokedGrant();
      },
    );
  }

  test(
    'fallback refresh cannot be cancelled during its native handoff',
    () async {
      library.workspace = const PreviewWorkspace(
        path: '/vault',
        name: 'vault',
        isCloud: false,
        workspaceToken: 'epoch-a',
        notice: 'fallback',
      );
      final pending = controller.refresh();
      await called.future;
      controller.cancelPendingOperation();
      await controller.open('/vault/note.md');
      expect(controller.busy, isTrue);
      expect(controller.activePath, isNull);
      await activateAndReply();
      await pending;
      await assertNoAdvertisedRevokedGrant();
    },
  );

  for (final reuseLibrary in [true, false]) {
    test(
      'dispose/recreate consumes old activation and serializes new selection; shared=$reuseLibrary',
      () async {
        final oldLibrary = library;
        final oldSelection = controller.changeWorkspace(useCloud: true);
        await called.future;
        controller.dispose();
        if (!reuseLibrary) library = GrantLibrary();
        controller = PreviewController(library: library);
        final nextReply = Completer<Map<String, dynamic>?>();
        responses.add(nextReply.future);
        final newInitialization = controller.initialize();
        await Future<void>.delayed(Duration.zero);
        expect(
          selectionCalls,
          1,
          reason:
              'A recreated controller must await the outstanding native handoff',
        );
        await activateAndReply();
        await oldSelection;
        expect(oldLibrary.workspace!.workspaceToken, 'epoch-b');
        expect(library.canWrite, isFalse);
        expect(selectionCalls, 2);
        nextReply.complete({
          'path': '/replacement',
          'name': 'replacement',
          'isCloud': false,
          'workspaceToken': 'epoch-c',
        });
        await newInitialization;
        expect(controller.initialized, isTrue);
        expect(library.workspace!.workspaceToken, 'epoch-c');
        await assertNoAdvertisedRevokedGrant();
      },
    );
  }

  test(
    'foreground incoming files wait for the handoff then open with the matching grant',
    () async {
      final first = controller.changeWorkspace(useCloud: true);
      await called.future;
      final nextReply = Completer<Map<String, dynamic>?>();
      responses.add(nextReply.future);
      await controller.receive(['/default/import.md']);
      expect(selectionCalls, 1);
      await activateAndReply();
      await first;
      expect(selectionCalls, 2);
      nextReply.complete({
        'path': '/default',
        'name': 'default',
        'isCloud': false,
        'workspaceToken': 'epoch-c',
      });
      for (var i = 0; i < 8; ++i) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(controller.activePath, '/default/import.md');
      expect(controller.selectingWorkspace, isFalse);
      await assertNoAdvertisedRevokedGrant();
    },
  );

  test(
    'Source and recovery cannot acquire an old grant during handoff',
    () async {
      final store = MemoryPreviewDraftStore()
        ..draft = const PreviewDraft(
          root: '/vault',
          path: '/vault/note.md',
          text: 'unsaved',
          baseline: '# Existing',
        );
      final editor = PreviewEditorController(library: library, store: store);
      addTearDown(editor.dispose);
      await editor.initialize();
      final pending = controller.changeWorkspace(useCloud: true);
      await called.future;
      expect(editor.canBegin, isFalse);
      expect(editor.canRecover, isFalse);
      expect(await editor.begin('/vault/note.md', restore: true), isFalse);
      expect(await editor.create('new'), isNull);
      expect(editor.recovery!.text, 'unsaved');
      await activateAndReply();
      await pending;
      expect(editor.recovery!.text, 'unsaved');
    },
  );

  test(
    'initialization retry cannot switch authority while Source owns navigation',
    () async {
      controller.blocksNavigation = () => true;
      await controller.initialize();
      expect(selectionCalls, 0);
      expect(library.workspace!.workspaceToken, 'epoch-a');
    },
  );

  testWidgets(
    'slow handoff shows truthful waiting state without a false Cancel or edit action',
    (tester) async {
      // Use the widget test's fake-async zone for a deliberately pending reply.
      called = Completer<void>();
      reply = Completer<Map<String, dynamic>?>();
      await tester.pumpWidget(
        LinefoldPreviewApp(
          controller: controller,
          platform: MemoryPreviewPlatform()..initial = [],
          draftStore: MemoryPreviewDraftStore(),
        ),
      );
      await tester.pump();
      expect(controller.selectingWorkspace, isTrue);
      expect(find.textContaining('正在切换文件夹'), findsOneWidget);
      expect(find.byTooltip('取消等待'), findsNothing);
      expect(find.byTooltip('编辑源码'), findsNothing);
      expect(find.byTooltip('新建笔记'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 60));
      expect(controller.selectingWorkspace, isTrue);
      expect(selectionCalls, 1);
      expect(find.textContaining('仍在处理中'), findsOneWidget);
      reply.complete({
        'path': '/default',
        'name': 'default',
        'isCloud': false,
        'workspaceToken': 'epoch-b',
      });
      await tester.pumpAndSettle();
      expect(controller.selectingWorkspace, isFalse);
      expect(find.byTooltip('新建笔记'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
