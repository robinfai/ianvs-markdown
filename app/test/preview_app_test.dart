import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/preview/preview_app.dart';
import 'package:linefold/src/preview/preview_controller.dart';
import 'package:linefold/src/preview/preview_library.dart';
import 'package:linefold/src/preview/preview_platform.dart';
import 'package:linefold/src/services/apple_workspace_service.dart';
import 'package:linefold/src/models/document_sync_status.dart';

void main() {
  testWidgets(
    'folder selection is explicit and shared imports return to the default workspace',
    (tester) async {
      final platform = _Platform();
      final controller = PreviewController(library: _WorkspaceLibrary());

      await tester.pumpWidget(
        LinefoldPreviewApp(controller: controller, platform: platform),
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
        LinefoldPreviewApp(controller: controller, platform: platform),
      );
      await tester.pumpAndSettle();
      expect(find.text('共享文档.md'), findsOneWidget);
      expect(find.byType(IanvsMarkdownView), findsOneWidget);
      expect(find.byType(EditableText), findsNothing);
      await tester.tap(find.text('目录'));
      await tester.pumpAndSettle();
      expect(find.text('文档目录'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, '第二节'));
      await tester.pumpAndSettle();
      expect(find.text('文档目录'), findsNothing);
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
      LinefoldPreviewApp(controller: controller, platform: platform),
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
        LinefoldPreviewApp(controller: controller, platform: platform),
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
      LinefoldPreviewApp(controller: controller, platform: platform),
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
      LinefoldPreviewApp(controller: controller, platform: platform),
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
      LinefoldPreviewApp(controller: controller, platform: platform),
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
