import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/preview/preview_app.dart';
import 'package:linefold/src/preview/preview_controller.dart';
import 'package:linefold/src/preview/preview_draft_store.dart';
import 'package:linefold/src/preview/preview_library.dart';
import 'package:linefold/src/preview/preview_editor_controller.dart';
import 'preview_test_support.dart';

class CleanupStore extends MemoryPreviewDraftStore {
  final clearing = Completer<void>();
  final allowClear = Completer<void>();
  @override
  Future<void> save(PreviewDraft? value) async {
    if (value == null && !clearing.isCompleted) {
      clearing.complete();
      await allowClear.future;
    }
    await super.save(value);
  }
}

class SwitchingLibrary extends MemoryPreviewLibrary {
  bool switchOnDefault = false;
  @override
  Future<void> useDefaultWorkspace() async {
    if (switchOnDefault) {
      workspace = const PreviewWorkspace(
        path: '/default',
        name: 'Default',
        isCloud: false,
        workspaceToken: 'fresh-default-token',
      );
    }
  }
}

void main() {
  test(
    'late input during recovery cleanup remains dirty and recoverable',
    () async {
      final library = MemoryPreviewLibrary();
      final store = CleanupStore();
      final editor = PreviewEditorController(library: library, store: store);
      addTearDown(editor.dispose);
      await editor.initialize();
      await editor.begin('/vault/note.md');
      editor.source.text = 'captured A';
      final saving = editor.save((_) async => PreviewConflictChoice.cancel);
      await store.clearing.future;
      expect(library.files['/vault/note.md'], 'captured A');
      editor.source.text = 'late composition B';
      store.allowClear.complete();
      expect(await saving, isTrue);
      await editor.flushDraft();
      expect(
        editor.editing,
        isTrue,
        reason: 'unsaved newer source must keep editor open',
      );
      expect(editor.dirty, isTrue);
      expect(store.draft?.text, 'late composition B');
    },
  );
  testWidgets(
    'large accessibility text plus landscape keyboard and save error stays usable',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(812, 375);
      tester.view.viewInsets = const FakeViewPadding(bottom: 160);
      tester.platformDispatcher.textScaleFactorTestValue = 3.2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final library = MemoryPreviewLibrary();
      final preview = PreviewController(library: library);
      await tester.pumpWidget(
        LinefoldPreviewApp(
          readingPositions: memoryPreviewReadingPositions(),
          controller: preview,
          platform: MemoryPreviewPlatform(),
          draftStore: MemoryPreviewDraftStore(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('编辑源码'));
      await tester.pumpAndSettle();
      final source = find.byKey(const ValueKey('mobile-source'));
      await tester.enterText(source, 'unsaved');
      library.writeFailure = true;
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(source).height, greaterThan(40));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      preview.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
  testWidgets(
    'recovery banner large text landscape remains reachable',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(812, 375);
      tester.platformDispatcher.textScaleFactorTestValue = 3.2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final library = MemoryPreviewLibrary();
      final preview = PreviewController(library: library);
      final store = MemoryPreviewDraftStore()
        ..draft = PreviewDraft(
          root: '/old',
          path: '/old/${'草稿' * 90}.md',
          text: 'recover',
          baseline: 'old',
        );
      await tester.pumpWidget(
        LinefoldPreviewApp(
          readingPositions: memoryPreviewReadingPositions(),
          controller: preview,
          platform: MemoryPreviewPlatform()..initial = [],
          draftStore: store,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('恢复为新笔记'));
      await tester.pumpAndSettle();
      expect(find.text('恢复为新笔记').hitTestable(), findsOneWidget);
      await tester.tap(find.text('恢复为新笔记'));
      await tester.pumpAndSettle();
      expect(find.text('在当前文件夹恢复为新笔记？'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      preview.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
  testWidgets(
    'cancel Source refreshes the disk version changed while editing',
    (tester) async {
      final library = MemoryPreviewLibrary();
      final preview = PreviewController(library: library);
      await tester.pumpWidget(
        LinefoldPreviewApp(
          readingPositions: memoryPreviewReadingPositions(),
          controller: preview,
          platform: MemoryPreviewPlatform(),
          draftStore: MemoryPreviewDraftStore(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('编辑源码'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('mobile-source')),
        'local to discard',
      );
      library.files['/vault/note.md'] = '# External while editing';
      await preview.refresh();
      await tester.pumpAndSettle();
      expect(library.bodyRefreshes, 0);
      await tester.tap(find.byTooltip('取消编辑'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('丢弃草稿'));
      await tester.pumpAndSettle();
      expect(preview.contents, '# External while editing');
      expect(library.bodyRefreshes, 1);
      expect(library.writes, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      preview.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
  testWidgets(
    'new note dialog cannot silently rebind after incoming import switches root',
    (tester) async {
      final library = SwitchingLibrary();
      library.files['/default/incoming.md'] = 'incoming';
      final preview = PreviewController(library: library);
      final platform = MemoryPreviewPlatform()..initial = [];
      await tester.pumpWidget(
        LinefoldPreviewApp(
          readingPositions: memoryPreviewReadingPositions(),
          controller: preview,
          platform: platform,
          draftStore: MemoryPreviewDraftStore(),
        ),
      );
      await tester.pumpAndSettle();
      expect(library.workspace!.path, '/vault');
      await tester.tap(find.byTooltip('新建笔记'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'Intended for vault A',
      );
      library.switchOnDefault = true;
      await platform.onFiles!(['/default/incoming.md']);
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(
        library.creates,
        isNot(contains('/default/Intended for vault A.md')),
        reason:
            'Pending name dialog approved in /vault must not create in new /default root',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      preview.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
  testWidgets(
    'late platform IME update before busy repaint survives save cleanup',
    (tester) async {
      final library = MemoryPreviewLibrary();
      final preview = PreviewController(library: library);
      final store = CleanupStore();
      await tester.pumpWidget(
        LinefoldPreviewApp(
          readingPositions: memoryPreviewReadingPositions(),
          controller: preview,
          platform: MemoryPreviewPlatform(),
          draftStore: store,
        ),
      );
      await tester.pumpAndSettle();
      final source = find.byKey(const ValueKey('mobile-source'));
      await tester.tap(find.byTooltip('编辑源码'));
      await tester.pumpAndSettle();
      await tester.enterText(source, 'captured A');
      await tester.tap(find.text('保存'));
      // No frame has applied busy/readOnly yet. Native input can arrive between frames.
      await store.clearing.future;
      expect(tester.widget<TextField>(source).readOnly, isFalse);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'late platform B',
          selection: TextSelection.collapsed(offset: 15),
        ),
      );
      store.allowClear.complete();
      await tester.pumpAndSettle();
      expect(library.files['/vault/note.md'], 'captured A');
      expect(
        source,
        findsOneWidget,
        reason: 'Late platform update may not close unsaved Source',
      );
      expect(
        tester.widget<TextField>(source).controller!.text,
        'late platform B',
      );
      expect(store.draft?.text, 'late platform B');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      preview.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'recovery copy confirmation rejects a changed root epoch',
    (tester) async {
      final library = MemoryPreviewLibrary();
      final preview = PreviewController(library: library);
      const original = PreviewDraft(
        root: '/old',
        path: '/old/note.md',
        text: 'keep me',
        baseline: 'base',
      );
      final store = MemoryPreviewDraftStore()..draft = original;
      await tester.pumpWidget(
        LinefoldPreviewApp(
          readingPositions: memoryPreviewReadingPositions(),
          controller: preview,
          platform: MemoryPreviewPlatform()..initial = [],
          draftStore: store,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复为新笔记'));
      await tester.pumpAndSettle();
      library.workspace = library.workspace;
      await tester.tap(find.text('创建恢复副本'));
      await tester.pumpAndSettle();
      expect(library.creates, isEmpty);
      expect(library.writes, isEmpty);
      expect(store.draft, same(original));
      expect(find.byKey(const ValueKey('mobile-source')), findsNothing);
      expect(find.text('文件夹或恢复草稿已改变，请重新发起恢复。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      preview.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
