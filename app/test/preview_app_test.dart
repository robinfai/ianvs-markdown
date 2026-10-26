import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/preview/preview_app.dart';
import 'package:linefold/src/preview/preview_controller.dart';
import 'package:linefold/src/preview/preview_library.dart';
import 'package:linefold/src/preview/preview_platform.dart';

import 'preview_test_support.dart';
import 'support/fakes.dart' show MemoryWorkspaceSessionStore;
import 'package:linefold/src/preview/preview_reading_positions.dart';
import 'package:linefold/src/services/apple_workspace_service.dart';
import 'package:linefold/src/models/document_sync_status.dart';

void main() {
  testWidgets('mobile cross-document return restores origins after local jumps', (
    tester,
  ) async {
    final library = MemoryPreviewLibrary();
    final long = List.generate(100, (i) => 'Paragraph $i\n\n').join();
    library.files.addAll({
      '/vault/a.md': '# A\n\n$long## OriginEnd\n\nOriginal destination',
      '/vault/b.md': '# B\n\n$long## Middle\n\n$long## End\n\nEnd body',
      '/vault/c.md': '# C',
    });
    final controller = PreviewController(library: library);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      LinefoldPreviewApp(
        controller: controller,
        platform: MemoryPreviewPlatform(),
        draftStore: MemoryPreviewDraftStore(),
        readingPositions: memoryPreviewReadingPositions(),
      ),
    );
    await tester.pumpAndSettle();
    await controller.open('/vault/a.md');
    await tester.pumpAndSettle();
    ScrollPosition scroll() => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(IanvsMarkdownView),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    Future<void> follow(String href) async {
      tester
          .widget<IanvsMarkdownView>(find.byType(IanvsMarkdownView))
          .onTapLinkTarget!(
        IanvsMarkdownLinkTarget(
          text: href,
          href: href,
          kind: IanvsMarkdownLinkKind.markdown,
        ),
      );
      await tester.pumpAndSettle();
    }

    final back = find.byKey(const ValueKey('preview-navigation-back-button'));
    scroll().jumpTo(1200);
    await tester.pumpAndSettle();
    await follow('#originend');
    final originEnd = scroll().pixels;
    expect(originEnd, greaterThan(1200));
    await follow('b.md#middle');
    expect(controller.activePath, '/vault/b.md');
    final middlePosition = scroll().pixels;
    expect(middlePosition, greaterThan(1200));
    await follow('b.md#end');
    expect(scroll().pixels, greaterThan(middlePosition));
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(controller.activePath, '/vault/b.md');
    expect(scroll().pixels, closeTo(middlePosition, 1));
    await follow('c.md');
    expect(controller.activePath, '/vault/c.md');
    library.readFailure = true;
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(controller.activePath, '/vault/c.md');
    expect(tester.widget<TextButton>(back).onPressed, isNotNull);
    library.readFailure = false;
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(controller.activePath, '/vault/b.md');
    expect(scroll().pixels, closeTo(middlePosition, 1));
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(controller.activePath, '/vault/a.md');
    expect(scroll().pixels, closeTo(originEnd, 1));
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(controller.activePath, '/vault/a.md');
    expect(scroll().pixels, closeTo(1200, 1));
    expect(tester.widget<TextButton>(back).onPressed, isNull);
    expect(library.writes, isEmpty);
    // Eviction must release inactive readers without disposing listeners
    // still mounted during a document transition.
    for (var i = 0; i < 26; i++) {
      final path = '/vault/extra$i.md';
      library.files[path] = '# Extra $i';
      await controller.open(path);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await controller.open('/vault/a.md');
    await tester.pumpAndSettle();
    expect(
      scroll().pixels,
      0,
      reason:
          'Both reading metadata and session history have bounded LRU retention',
    );
    expect(tester.widget<TextButton>(back).onPressed, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets(
    'mobile reading position survives a fresh app and document controller',
    (tester) async {
      final library = _Library()
        ..text = List.generate(100, (i) => 'Paragraph $i\n\n').join();
      final store = MemoryWorkspaceSessionStore();
      var positions = PreviewReadingPositions(store: store);
      var controller = PreviewController(library: library);
      Widget app() => LinefoldPreviewApp(
        draftStore: MemoryPreviewDraftStore(),
        readingPositions: positions,
        controller: controller,
        platform: _Platform()..initial = ['/import/共享文档.md'],
      );
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      ScrollPosition scroll() => tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(IanvsMarkdownView),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      scroll().jumpTo(1200);
      await tester.pumpAndSettle();
      await positions.flush();
      expect(store.snapshot, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      positions.dispose();
      positions = PreviewReadingPositions(store: store);
      controller = PreviewController(library: library);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(scroll().pixels, closeTo(1200, 1));
      expect(controller.contents, library.text);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await positions.flush();
      positions.dispose();
      controller.dispose();
    },
  );

  testWidgets('mobile find fits 320px with large text and keyboard', (
    tester,
  ) async {
    final platform = _Platform()..initial = ['/import/共享文档.md'];
    final controller = PreviewController(library: _Library());
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      LinefoldPreviewApp(
        readingPositions: memoryPreviewReadingPositions(),
        draftStore: MemoryPreviewDraftStore(),
        controller: controller,
        platform: platform,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('preview-find-button')));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('preview-find-query')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('preview-find-close')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('preview-find-close')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets(
    'mobile body search stays in Read and closes at the current match',
    (tester) async {
      final library = _Library()
        ..text =
            '# Start\n\n[link](hidden-address)\n\n${List.generate(60, (i) => 'Paragraph $i\n\n').join()}FIRST NEEDLE\n\n${List.generate(25, (i) => 'Between $i\n\n').join()}SECOND NEEDLE';
      final platform = _Platform()..initial = ['/import/共享文档.md'];
      final controller = PreviewController(library: library);
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        LinefoldPreviewApp(
          readingPositions: memoryPreviewReadingPositions(),
          draftStore: MemoryPreviewDraftStore(),
          controller: controller,
          platform: platform,
        ),
      );
      await tester.pumpAndSettle();
      final viewElement = tester.element(find.byType(IanvsMarkdownView));
      await tester.tap(find.byKey(const ValueKey('preview-find-button')));
      await tester.pumpAndSettle();
      final query = find.byKey(const ValueKey('preview-find-query'));
      await tester.enterText(query, 'hidden-address');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('无匹配'), findsOneWidget);
      await tester.enterText(query, 'NEEDLE');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);
      expect(
        find.text('FIRST NEEDLE', findRichText: true).hitTestable(),
        findsOneWidget,
      );
      expect(tester.element(find.byType(IanvsMarkdownView)), same(viewElement));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'NEEDLE',
          selection: TextSelection.collapsed(offset: 6),
          composing: TextRange(start: 0, end: 6),
        ),
      );
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('preview-find-close')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('preview-find-next')))
            .onPressed,
        isNull,
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'NEEDLE',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('preview-find-next')));
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      expect(
        find.text('SECOND NEEDLE', findRichText: true).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('preview-find-close')));
      await tester.pumpAndSettle();
      expect(query, findsNothing);
      expect(
        find.text('SECOND NEEDLE', findRichText: true).hitTestable(),
        findsOneWidget,
      );
      expect(tester.element(find.byType(IanvsMarkdownView)), same(viewElement));
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('preview-navigation-back-button')),
            )
            .onPressed,
        isNull,
      );
      expect(controller.contents, library.text);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets(
    'mobile outline and inline footnote return to original reading position',
    (tester) async {
      final library = _Library()
        ..text =
            '# Start\n\nTop^[INLINE NOTE]\n\n${List.generate(70, (i) => 'Paragraph $i\n\n').join()}## Destination\n\nDestination body';
      final platform = _Platform()..initial = ['/import/共享文档.md'];
      final controller = PreviewController(library: library);
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        LinefoldPreviewApp(
          readingPositions: memoryPreviewReadingPositions(),
          draftStore: MemoryPreviewDraftStore(),
          controller: controller,
          platform: platform,
        ),
      );
      await tester.pumpAndSettle();
      final start = find.text('Start', findRichText: true);
      final originalTop = tester.getTopLeft(start).dy;
      await tester.tap(find.text('目录'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Destination'));
      await tester.pumpAndSettle();
      expect(
        find.text('Destination body', findRichText: true).hitTestable(),
        findsOneWidget,
      );
      final back = find.byKey(const ValueKey('preview-navigation-back-button'));
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(start).dy, closeTo(originalTop, 1));
      // Exercise the actual renderer callback used by a footnote link.
      final view = tester.widget<IanvsMarkdownView>(
        find.byType(IanvsMarkdownView),
      );
      view.onTapLinkTarget!(
        const IanvsMarkdownLinkTarget(
          text: '[1]',
          href: '#fn-ianvs-inline-footnote-1',
          kind: IanvsMarkdownLinkKind.markdown,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('INLINE NOTE', findRichText: true).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(start).dy, closeTo(originalTop, 1));
      expect(find.byType(EditableText), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets(
    'folder selection is explicit and shared imports return to the default workspace',
    (tester) async {
      final platform = _Platform();
      final controller = PreviewController(library: _WorkspaceLibrary());

      await tester.pumpWidget(
        LinefoldPreviewApp(
          readingPositions: memoryPreviewReadingPositions(),
          draftStore: MemoryPreviewDraftStore(),
          controller: controller,
          platform: platform,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('iCloud · Linefold'), findsOneWidget);
      await tester.tap(find.byTooltip('切换文件夹'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择其他文件夹…'));
      await tester.pumpAndSettle();
      expect(find.text('手动选择的文件夹'), findsOneWidget);
      await platform.deliver(['/cloud/shared.md']);
      await tester.pumpAndSettle();
      expect(find.byType(IanvsMarkdownView), findsOneWidget);
      await tester.tap(find.byTooltip('最近文档'));
      await tester.pumpAndSettle();
      expect(find.text('iCloud · Linefold'), findsOneWidget);
      expect(find.text('手动选择的文件夹'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets(
    'shared file opens in read mode and remains available from recent documents',
    (tester) async {
      final platform = _Platform()..initial = ['/import/共享文档.md'];
      final controller = PreviewController(library: _Library());

      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        LinefoldPreviewApp(
          readingPositions: memoryPreviewReadingPositions(),
          draftStore: MemoryPreviewDraftStore(),
          controller: controller,
          platform: platform,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('共享文档.md'), findsOneWidget);
      expect(find.byType(IanvsMarkdownView), findsOneWidget);
      expect(find.byType(EditableText), findsNothing);
      final back = find.byKey(const ValueKey('preview-navigation-back-button'));
      expect(tester.widget<TextButton>(back).onPressed, isNull);
      await tester.tap(find.text('目录'));
      await tester.pumpAndSettle();
      expect(find.text('文档目录'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, '第二节'));
      await tester.pumpAndSettle();
      expect(find.text('文档目录'), findsNothing);
      expect(tester.widget<TextButton>(back).onPressed, isNotNull);
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(back).onPressed, isNull);
      expect(find.byType(EditableText), findsNothing);
      await tester.tap(find.byTooltip('最近文档'));
      await tester.pumpAndSettle();
      expect(find.text('最近文档'), findsOneWidget);
      await tester.tap(find.text('共享文档.md'));
      await tester.pumpAndSettle();
      expect(find.byType(IanvsMarkdownView), findsOneWidget);
      await platform.deliver(['/import/运行时.md']);
      await tester.pumpAndSettle();
      expect(find.text('运行时.md'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('empty library and reader fit narrow landscape and large text', (
    tester,
  ) async {
    final platform = _Platform();
    final controller = PreviewController(library: _Library());

    tester.platformDispatcher.textScaleFactorTestValue = 2;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      LinefoldPreviewApp(
        readingPositions: memoryPreviewReadingPositions(),
        draftStore: MemoryPreviewDraftStore(),
        controller: controller,
        platform: platform,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('打开文件'));
    expect(platform.pickerOpened, isTrue);
    await platform.deliver(['/import/共享文档.md']);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(const Size(844, 390));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets(
    '320px and 3x text keep refresh failure, retry and reader usable',
    (tester) async {
      final library = _Library();
      final platform = _Platform()..initial = ['/import/共享文档.md'];
      final controller = PreviewController(library: library);

      tester.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        LinefoldPreviewApp(
          readingPositions: memoryPreviewReadingPositions(),
          draftStore: MemoryPreviewDraftStore(),
          controller: controller,
          platform: platform,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final original = controller.contents;
      library.refreshFailure = StateError('offline');
      await tester.tap(find.byTooltip('刷新文档'));
      await tester.pumpAndSettle();
      expect(controller.contents, original);
      expect(find.byType(IanvsMarkdownView), findsOneWidget);
      expect(tester.takeException(), isNull);
      library.refreshFailure = null;
      library.text = '# Remote revision';
      await tester.ensureVisible(find.text('重试'));
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<IanvsMarkdownView>(find.byType(IanvsMarkdownView)).data,
        '# Remote revision',
      );
      expect(find.text('重试'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('打开文件'));
      await tester.pumpAndSettle();
      expect(platform.pickerOpened, isTrue);
      expect(controller.contents, '# Remote revision');
      await tester.tap(find.byTooltip('最近文档'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('resume refresh replaces active reader body without reopening', (
    tester,
  ) async {
    final library = _Library();
    final platform = _Platform()..initial = ['/import/共享文档.md'];
    final controller = PreviewController(library: library);

    await tester.pumpWidget(
      LinefoldPreviewApp(
        readingPositions: memoryPreviewReadingPositions(),
        draftStore: MemoryPreviewDraftStore(),
        controller: controller,
        platform: platform,
      ),
    );
    await tester.pumpAndSettle();
    library.text = '# Resume revision';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(controller.contents, '# Resume revision');
    expect(
      tester.widget<IanvsMarkdownView>(find.byType(IanvsMarkdownView)).data,
      '# Resume revision',
    );
    expect(platform.refreshes, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('cloud status is separate from readable body at 320px and 3x', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    final library = _WorkspaceLibrary()
      ..metadata = DocumentSyncMetadata(
        state: CloudSyncState.uploadPending,
        observedAt: DateTime.now(),
      );
    final controller = PreviewController(library: library);
    final platform = _Platform()..initial = ['/cloud/shared.md'];
    await tester.pumpWidget(
      LinefoldPreviewApp(
        readingPositions: memoryPreviewReadingPositions(),
        draftStore: MemoryPreviewDraftStore(),
        controller: controller,
        platform: platform,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('iCloud upload pending'), findsOneWidget);
    expect(find.byType(IanvsMarkdownView), findsOneWidget);
    expect(tester.takeException(), isNull);
    library.metadata = DocumentSyncMetadata(
      state: CloudSyncState.failure,
      observedAt: DateTime.now(),
      detail: 'System reported an offline upload error.',
    );
    await controller.sync.refresh();
    await tester.pumpAndSettle();
    expect(find.text('iCloud transfer failed'), findsOneWidget);
    expect(controller.contents, '# Shared');
    await tester.tap(find.text('iCloud transfer failed'));
    await tester.pumpAndSettle();
    expect(
      find.text('System reported an offline upload error.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('cloud notification refreshes the active reader body', (
    tester,
  ) async {
    final changes = StreamController<void>.broadcast();
    addTearDown(changes.close);
    final library = _WorkspaceLibrary(service: _CloudService(changes.stream));
    final platform = _Platform()..initial = ['/cloud/shared.md'];
    final controller = PreviewController(library: library);

    await tester.pumpWidget(
      LinefoldPreviewApp(
        readingPositions: memoryPreviewReadingPositions(),
        draftStore: MemoryPreviewDraftStore(),
        controller: controller,
        platform: platform,
      ),
    );
    await tester.pumpAndSettle();
    library.refreshText = '# Cloud revision';
    changes.add(null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(controller.contents, '# Cloud revision');
    expect(
      tester.widget<IanvsMarkdownView>(find.byType(IanvsMarkdownView)).data,
      '# Cloud revision',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

class _Library extends PreviewLibrary {
  String text = '# 分享预览\n\n正文 **加粗**。\n\n## 第二节\n\n- 项目一\n- 项目二';
  Object? refreshFailure;

  @override
  Future<String> refreshContent(String path) async {
    if (refreshFailure case final failure?) throw failure;
    return text;
  }

  @override
  Future<List<PreviewDocument>> list() async => [
    PreviewDocument(
      path: '/import/共享文档.md',
      name: '共享文档.md',
      openedAt: DateTime(2026, 10, 4),
    ),
  ];

  @override
  Future<String> read(String path) async => text;
}

class _WorkspaceLibrary extends PreviewLibrary {
  _WorkspaceLibrary({AppleWorkspaceService? service})
    : super(workspaceService: service ?? const AppleWorkspaceService());

  String refreshText = '# Shared';
  DocumentSyncMetadata metadata = const DocumentSyncMetadata();

  @override
  Future<DocumentSyncMetadata> readSyncMetadata(String path) async => metadata;

  @override
  Future<String> refreshContent(String path) async => refreshText;

  @override
  Future<void> useDefaultWorkspace() async {
    workspace = const PreviewWorkspace(
      path: '/cloud',
      name: 'iCloud · Linefold',
      isCloud: true,
    );
  }

  @override
  Future<bool> chooseWorkspace() async {
    workspace = const PreviewWorkspace(
      path: '/manual',
      name: '手动选择的文件夹',
      isCloud: false,
    );
    return true;
  }

  @override
  Future<List<PreviewDocument>> list() async => [];

  @override
  Future<String> read(String path) async => '# Shared';
}

class _Platform extends PreviewPlatform {
  List<String> initial = [];
  PreviewDelivery? onFiles;
  bool pickerOpened = false;
  int refreshes = 0;

  @override
  Future<void> refresh() async {
    ++refreshes;
  }

  @override
  Future<void> start(
    PreviewDelivery onFiles,
    void Function(String) onError,
  ) async {
    this.onFiles = onFiles;
    if (initial.isNotEmpty) await onFiles(initial);
  }

  Future<void> deliver(List<String> paths) => onFiles!(paths);

  @override
  Future<void> chooseFiles() async {
    pickerOpened = true;
  }

  @override
  void dispose() {}
}

class _CloudService extends AppleWorkspaceService {
  const _CloudService(this.changes);

  @override
  final Stream<void> changes;
}
