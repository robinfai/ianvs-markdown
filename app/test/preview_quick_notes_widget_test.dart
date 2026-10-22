import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/preview/preview_app.dart';
import 'package:linefold/src/preview/preview_controller.dart';
import 'package:linefold/src/preview/preview_draft_store.dart';
import 'package:linefold/src/preview/preview_library.dart';

import 'preview_test_support.dart';

void main() {
  late MemoryPreviewLibrary library;
  late MemoryPreviewDraftStore store;
  late MemoryPreviewPlatform platform;
  late PreviewController preview;
  setUp(() {
    library = MemoryPreviewLibrary();
    store = MemoryPreviewDraftStore();
    platform = MemoryPreviewPlatform();
    preview = PreviewController(library: library);
  });
  Future<void> launch(WidgetTester tester) async {
    await tester.pumpWidget(
      LinefoldPreviewApp(
        controller: preview,
        platform: platform,
        draftStore: store,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    preview.dispose();
  }

  final source = find.byKey(const ValueKey('mobile-source'));

  testWidgets(
    'foreground native-canonical import enters Source and saves in the selected root',
    (tester) async {
      const canonicalRoot = '/private/vault';
      const importedPath = '$canonicalRoot/Imports/copy/中文 分享.MD';
      const original =
          '\ufeff# Shared\r\n- [ ] Task 📝\r\n![图](../图片/照片.png)\r\n';
      const edited =
          '\ufeff# Shared\r\n- [x] Task 📝\r\n![图](../图片/照片.png)\r\n';
      library.workspace = const PreviewWorkspace(
        path: canonicalRoot,
        name: 'App-owned copies',
        isCloud: false,
        workspaceToken: 'native-epoch',
      );
      library.files
        ..clear()
        ..[importedPath] = original;
      platform.initial = [];
      await launch(tester);
      await platform.onFiles!([importedPath]);
      await tester.pumpAndSettle();
      expect(preview.activeRoot, canonicalRoot);
      expect(preview.activePath, importedPath);
      await tester.tap(find.byTooltip('编辑源码'));
      await tester.pumpAndSettle();
      expect(source, findsOneWidget);
      expect(tester.widget<TextField>(source).controller!.text, original);
      await tester.enterText(source, edited);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(library.writes, [(importedPath, edited, original)]);
      expect(library.files[importedPath], edited);
      expect(source, findsNothing);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'explicit source editing task toggle Save returns reader, Cancel confirms dirty loss',
    (tester) async {
      await launch(tester);
      expect(find.byType(IanvsMarkdownView), findsOneWidget);
      expect(source, findsNothing);
      await tester.tap(find.byTooltip('编辑源码'));
      await tester.pumpAndSettle();
      expect(source, findsOneWidget);
      await tester.enterText(source, '# Changed\r\n- [x] Task 📝\r\n');
      expect(library.writes, isEmpty);
      await tester.tap(find.byTooltip('取消编辑'));
      await tester.pumpAndSettle();
      expect(find.text('保留这次修改？'), findsOneWidget);
      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();
      expect(source, findsOneWidget);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(library.files['/vault/note.md'], '# Changed\r\n- [x] Task 📝\r\n');
      expect(source, findsNothing);
      expect(find.byType(IanvsMarkdownView), findsOneWidget);
      await tester.tap(find.byTooltip('编辑源码'));
      await tester.pumpAndSettle();
      await tester.enterText(source, 'discard me');
      await tester.tap(find.byTooltip('取消编辑'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('丢弃草稿'));
      await tester.pumpAndSettle();
      expect(source, findsNothing);
      expect(library.files['/vault/note.md'], isNot('discard me'));
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'conflict Cancel Keep Both and observed overwrite are explicit actions',
    (tester) async {
      await launch(tester);
      await tester.tap(find.byTooltip('编辑源码'));
      await tester.pumpAndSettle();
      await tester.enterText(source, 'local');
      library.files['/vault/note.md'] = 'external';
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('文件已在其他地方改变'), findsOneWidget);
      expect(find.text('external'), findsOneWidget);
      await tester.tap(find.text('取消保存'));
      await tester.pumpAndSettle();
      expect(source, findsOneWidget);
      expect(library.files['/vault/note.md'], 'external');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保留两份'));
      await tester.pumpAndSettle();
      expect(library.creates, hasLength(1));
      expect(library.files[library.creates.single], 'local');
      expect(library.files['/vault/note.md'], 'external');
      await tester.tap(find.byTooltip('编辑源码'));
      await tester.pumpAndSettle();
      await tester.enterText(source, 'second local');
      library.files[library.creates.single] = 'second external';
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('second external'), findsOneWidget);
      await tester.tap(find.text('覆盖此版本'));
      await tester.pumpAndSettle();
      expect(library.files[library.creates.single], 'second local');
      expect(find.byType(IanvsMarkdownView), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'pending save disables all navigation and preserves incoming imports for later',
    (tester) async {
      await launch(tester);
      await tester.tap(find.byTooltip('编辑源码'));
      await tester.pumpAndSettle();
      await tester.enterText(source, 'pending');
      library.pendingWrite = Completer<void>();
      await tester.tap(find.text('保存'));
      await tester.pump();
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '保存'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == '取消编辑',
              ),
            )
            .onPressed,
        isNull,
      );
      await platform.onFiles!(['/vault/incoming.md']);
      await tester.pump();
      expect(preview.activePath, '/vault/note.md');
      expect(source, findsOneWidget);
      library.pendingWrite!.complete();
      await tester.pumpAndSettle();
      expect(library.files['/vault/note.md'], 'pending');
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    '375 390 768 1024 portrait landscape keyboard preserve source focus selection IME and undo',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(390, 844);
      await launch(tester);
      await tester.tap(find.byTooltip('编辑源码'));
      await tester.pumpAndSettle();
      await tester.enterText(source, '# First\r\n![](photos/图%20片.png)\r\n😀');
      await tester.pump(const Duration(seconds: 1));
      final controller = tester.widget<TextField>(source).controller!;
      final focus = tester.widget<TextField>(source).focusNode;
      const composing = TextEditingValue(
        text: '# First\r\n![](photos/图%20片.png)\r\n😀拼音',
        selection: TextSelection.collapsed(offset: 37),
        composing: TextRange(start: 35, end: 37),
      );
      // Valid offsets are expressed in UTF-16, not code points.
      final value = composing.copyWith(
        selection: TextSelection.collapsed(offset: composing.text.length),
        composing: TextRange(
          start: composing.text.length - 2,
          end: composing.text.length,
        ),
      );
      tester.testTextInput.updateEditingValue(value);
      await tester.pump();
      for (final size in const [
        Size(375, 812),
        Size(390, 844),
        Size(768, 1024),
        Size(1024, 768),
        Size(812, 375),
        Size(844, 390),
      ]) {
        tester.view.physicalSize = size;
        tester.view.viewInsets = FakeViewPadding(
          bottom: size.height < 500 ? 160 : 300,
        );
        await tester.pumpAndSettle();
        final field = tester.widget<TextField>(source);
        expect(field.smartDashesType, SmartDashesType.disabled);
        expect(field.smartQuotesType, SmartQuotesType.disabled);
        expect(field.controller, same(controller));
        expect(field.focusNode, same(focus));
        expect(field.focusNode!.hasFocus, isTrue);
        expect(controller.value, value);
        expect(tester.getSize(source).height, greaterThan(40));
        expect(tester.takeException(), isNull, reason: '$size with keyboard');
      }
      // Finish composing without resetting selection, then keyboard undo remains available.
      tester.testTextInput.updateEditingValue(
        value.copyWith(composing: TextRange.empty),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(controller.text, '# First\r\n![](photos/图%20片.png)\r\n😀');
      expect(tester.takeException(), isNull);
      library.files['/vault/note.md'] = 'external on small landscape';
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('文件已在其他地方改变'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消保存'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = FakeViewPadding.zero;
      await finish(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'background flush restores draft without writing original then explicit save conflicts safely',
    (tester) async {
      await launch(tester);
      await tester.tap(find.byTooltip('编辑源码'));
      await tester.pumpAndSettle();
      await tester.enterText(source, 'recover me');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      await tester.pump();
      expect(store.draft?.text, 'recover me');
      expect(library.writes, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await finish(tester);
      library.files['/vault/note.md'] = 'external after restart';
      preview = PreviewController(library: library);
      platform = MemoryPreviewPlatform()..initial = [];
      await launch(tester);
      expect(source, findsNothing);
      expect(find.text('恢复草稿'), findsOneWidget);
      await tester.tap(find.text('恢复草稿'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(source).controller!.text, 'recover me');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('文件已在其他地方改变'), findsOneWidget);
      await tester.tap(find.text('取消保存'));
      await tester.pumpAndSettle();
      expect(library.files['/vault/note.md'], 'external after restart');
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'new note library filename search and current-root Markdown Wiki navigation',
    (tester) async {
      library.files['/vault/Target.md'] = '# Target';
      library.files['/vault/note.md'] = '[next](Target.md) and [[Target]]';
      await launch(tester);
      await tester.tap(find.text('next'));
      await tester.pumpAndSettle();
      expect(preview.activePath, '/vault/Target.md');
      await tester.tap(find.byTooltip('最近文档'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'note.md'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Target').first);
      await tester.pumpAndSettle();
      expect(preview.activePath, '/vault/Target.md');
      await tester.tap(find.byTooltip('最近文档'));
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('mobile-note-search'));
      await tester.ensureVisible(search);
      await tester.enterText(search, 'target');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Target.md'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'note.md'), findsNothing);
      await tester.tap(find.byTooltip('新建笔记'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Quick');
      await tester.tap(find.text('新建'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(library.creates, contains('/vault/Quick.md'));
      expect(source, findsOneWidget);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'recovery from unselected root never opens or changes source scope automatically',
    (tester) async {
      store.draft = const PreviewDraft(
        root: '/other',
        path: '/other/note.md',
        text: 'private',
        baseline: 'old',
      );
      platform.initial = [];
      await launch(tester);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '恢复草稿'))
            .onPressed,
        isNull,
      );
      expect(source, findsNothing);
      expect(library.workspace!.path, '/vault');
      expect(library.writes, isEmpty);
      await tester.tap(find.text('恢复为新笔记'));
      await tester.pumpAndSettle();
      expect(library.creates, isEmpty);
      await tester.tap(find.text('创建恢复副本'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(source).controller!.text, 'private');
      expect(library.creates.single, startsWith('/vault/Recovered '));
      expect(library.writes, isEmpty);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
  testWidgets(
    'opening another reader note cannot start Source on the stale displayed note',
    (tester) async {
      await launch(tester);
      library.pendingRead = Completer<String>();
      final opening = preview.open('/vault/Target.md');
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == '编辑源码',
              ),
            )
            .onPressed,
        isNull,
      );
      library.pendingRead!.complete('# Target');
      await opening;
      await tester.pumpAndSettle();
      expect(preview.activePath, '/vault/Target.md');
      expect(source, findsNothing);
      await finish(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
