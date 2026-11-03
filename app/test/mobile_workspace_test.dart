import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/desktop_theme.dart';
import 'package:linefold/src/services/apple_workspace_service.dart';
import 'package:linefold/src/services/mobile_markdown_file_service.dart';
import 'package:linefold/src/preview/preview_platform.dart';
import 'package:linefold/src/widgets/editor_shell.dart';
import 'support/fakes.dart';

void main() {
  testWidgets('phone opens shared workspace and commands without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final files = MemoryMarkdownFileService();
    final workspace = WorkspaceController(
      fileService: files,
      sessionStore: MemoryWorkspaceSessionStore(),
    );
    await workspace.initialize();
    await tester.pumpWidget(
      MaterialApp(
        theme: desktopTheme(Brightness.light),
        home: EditorShell(
          workspace: workspace,
          dark: false,
          onToggleTheme: () {},
          enableFileDrop: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('保存'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('工作区'));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.byType(Drawer))).pop();
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('command-palette-button')),
    );
    await tester.tap(find.byKey(const ValueKey('command-palette-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('workspace-palette-query')),
      'Search workspace',
    );
    await tester.pumpAndSettle();
    expect(find.text('Search workspace'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    workspace.dispose();
    await files.dispose();
  });

  testWidgets(
    'iOS writes retain native workspace capability and exact baseline',
    (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        PreviewPlatform.channel,
        (call) async => {
          'path': '/vault',
          'name': 'Vault',
          'isCloud': true,
          'workspaceToken': 'native-token',
        },
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        AppleWorkspaceService.channel,
        (call) async {
          calls.add(call);
          if (call.method == 'createWorkspaceAttachment') {
            return {'relativePath': 'assets/image.png'};
          }
          return true;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          PreviewPlatform.channel,
          null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          AppleWorkspaceService.channel,
          null,
        );
      });
      final service = MobileMarkdownFileService();
      await service.defaultDirectory();
      await service.writeMarkdownFileGuarded(
        '/vault/note.md',
        'new\r\n',
        expectedContents: 'old\r\n',
      );
      expect(calls.single.method, 'writeWorkspaceNoteGuarded');
      expect(calls.single.arguments['workspaceToken'], 'native-token');
      expect(calls.single.arguments['relativePath'], 'note.md');
      expect(
        calls.single.arguments['expectedContentsBytes'],
        'old\r\n'.codeUnits,
      );
      await expectLater(
        service.writeMarkdownFileGuarded(
          '/outside/note.md',
          'text',
          expectedContents: null,
        ),
        throwsStateError,
      );
      expect(calls.length, 1);
      await service.createEntry(
        '/vault/new.md',
        directory: false,
        contents: '# New',
      );
      expect(calls.last.method, 'writeWorkspaceNoteGuarded');
      expect(calls.last.arguments['expectedContentsBytes'], isNull);
      final attachments = MobileAttachmentImportPlatform(service.library);
      await attachments.create(
        root: '/vault',
        relativeDirectory: 'assets',
        filename: 'image.png',
        bytes: Uint8List.fromList([1, 2]),
      );
      expect(calls.last.arguments['workspaceToken'], 'native-token');
    },
  );
}
