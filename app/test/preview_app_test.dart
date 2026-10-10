import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/preview/preview_app.dart';
import 'package:linefold/src/preview/preview_controller.dart';
import 'package:linefold/src/preview/preview_library.dart';
import 'package:linefold/src/preview/preview_platform.dart';
import 'package:linefold/src/services/apple_workspace_service.dart';

void main() {
  testWidgets(
    'folder selection is explicit and shared imports return to the default workspace',
    (tester) async {
      final platform = _Platform();
      final controller = PreviewController(library: _WorkspaceLibrary());
      addTearDown(controller.dispose);
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
    },
  );

  testWidgets(
    'shared file opens in read mode and remains available from recent documents',
    (tester) async {
      final platform = _Platform()..initial = ['/import/共享文档.md'];
      final controller = PreviewController(library: _Library());
      addTearDown(controller.dispose);
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
    },
  );

  testWidgets('empty library and reader fit narrow landscape and large text', (
    tester,
  ) async {
    final platform = _Platform();
    final controller = PreviewController(library: _Library());
    addTearDown(controller.dispose);
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
  });
}

class _Library extends PreviewLibrary {
  @override
  Future<List<PreviewDocument>> list() async => [
    PreviewDocument(
      path: '/import/共享文档.md',
      name: '共享文档.md',
      openedAt: DateTime(2026, 10, 4),
    ),
  ];

  @override
  Future<String> read(String path) async =>
      '# 分享预览\n\n正文 **加粗**。\n\n## 第二节\n\n- 项目一\n- 项目二';
}

class _WorkspaceLibrary extends PreviewLibrary {
  _WorkspaceLibrary() : super(workspaceService: const AppleWorkspaceService());

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
