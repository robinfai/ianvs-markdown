import 'dart:typed_data';
import 'dart:io';
import 'package:linefold/src/desktop_theme.dart';
import 'package:linefold/src/services/markdown_file_service.dart';
import 'package:linefold/src/widgets/editor_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/controllers/document_sync_controller.dart';
import 'package:linefold/src/models/document_sync_status.dart';
import 'package:linefold/src/services/apple_workspace_service.dart';
import 'package:linefold/src/services/mobile_markdown_file_service.dart';
import 'package:linefold/src/services/cloud_conflict_service.dart';
import 'package:linefold/src/preview/preview_platform.dart';
import 'package:linefold/src/widgets/cloud_conflict_dialog.dart';
import 'package:linefold/src/widgets/file_context_menu.dart';
import 'package:linefold/src/widgets/document_sync_indicator.dart';
import 'support/fakes.dart';

void main() {
  testWidgets('operation picker keeps active workspace and sends both grants', (
    tester,
  ) async {
    final calls = <Map>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      PreviewPlatform.channel,
      (call) async => {
        'path': call.method == 'chooseOperationFolder' ? '/other' : '/vault',
        'name': 'Fixture',
        'isCloud': false,
        'workspaceToken': call.method == 'chooseOperationFolder'
            ? 'other-token'
            : 'vault-token',
      },
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      AppleWorkspaceService.channel,
      (call) async {
        calls.add(call.arguments as Map);
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
    final files = MobileMarkdownFileService();
    await files.defaultDirectory();
    expect(files.isCloudPath('/vault'), isFalse);
    expect(files.workspaceName('/vault'), 'Fixture');
    final generation = files.library.workspaceGeneration;
    await files.chooseOperationFolder();
    expect(files.library.workspace!.path, '/vault');
    expect(files.library.workspaceGeneration, generation);
    await files.createEntry('/vault/folder', directory: true);
    expect(calls.last['operation'], 'createDirectory');
    await files.moveEntry('/vault/folder', '/other/folder');
    expect(calls.last['workspaceToken'], 'vault-token');
    expect(calls.last['destinationToken'], 'other-token');
    expect(calls.last['destinationRoot'], '/other');
    await files.copyEntry('/other/folder', '/vault/copy');
    expect(calls.last['operation'], 'copy');
    expect(calls.last['workspaceToken'], 'other-token');
    await tester.runAsync(() => files.trashEntry('/other/folder'));
    expect(calls.last['operation'], 'move');
    expect(calls.last['destination'], startsWith('最近删除/'));
    expect(calls.last['destination'], endsWith('/folder'));
    expect(calls.last['workspaceToken'], 'other-token');
    await files.writeMarkdownFileGuarded(
      '/other/moved.md',
      'edits',
      expectedContents: 'original',
    );
    expect(calls.last['workspaceToken'], 'other-token');
    final count = calls.length;
    await expectLater(
      files.moveEntry('/vault/a.md', '/unselected/a.md'),
      throwsStateError,
    );
    expect(calls.length, count);
  });

  test(
    'mobile watcher emits directory changes without dart:io watching',
    () async {
      final files = MobileMarkdownFileService();
      final received = files.watchDirectory('/vault').first;
      await Future<void>.delayed(Duration.zero);
      files.refreshExternalChanges();
      final event = await received;
      expect(event, isA<FileSystemModifyEvent>());
      expect(event.path, '/vault');
      expect(event.isDirectory, isTrue);
    },
  );

  testWidgets(
    'actual iOS sidebar long press beats tooltip and tap closes drawer',
    (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final files = MemoryMarkdownFileService()..selectedFolder = '/vault';
      files.files['/vault/note.md'] = '# Note';
      files.directories['/vault'] = [
        WorkspaceEntry(
          path: '/vault/note.md',
          name: 'note.md',
          isDirectory: false,
        ),
      ];
      final workspace = WorkspaceController(
        fileService: files,
        sessionStore: MemoryWorkspaceSessionStore(),
      );
      await workspace.initialize();
      await workspace.chooseWorkspaceFolder();
      await tester.pumpWidget(
        MaterialApp(
          theme: desktopTheme(Brightness.light, platform: TargetPlatform.iOS),
          home: EditorShell(
            workspace: workspace,
            dark: false,
            onToggleTheme: () {},
            enableFileDrop: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('工作区'));
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('workspace-file-/vault/note.md'));
      expect(tester.getSize(row).height, greaterThanOrEqualTo(42));
      await tester.longPress(row);
      await tester.pumpAndSettle();
      final rename = find.widgetWithText(
        PopupMenuItem<FileMenuAction>,
        'Rename',
      );
      expect(rename, findsOneWidget);
      expect(tester.getSize(rename).height, greaterThanOrEqualTo(48));
      Navigator.of(tester.element(rename)).pop();
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(workspace.activeDocument?.path, '/vault/note.md');
      expect(find.byType(Drawer), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      workspace.dispose();
      await files.dispose();
    },
  );

  testWidgets('long press exposes file actions on a phone', (tester) async {
    var renamed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FileContextMenu(
            path: '/fixture/note.md',
            actions: [FileMenuAction('Rename', () => renamed = true)],
            child: const ListTile(title: Text('note.md')),
          ),
        ),
      ),
    );
    await tester.longPress(find.text('note.md'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(renamed, isTrue);
  });

  testWidgets('conflict review compares before selecting a cloud version', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final review = CloudConflictReview({
      'session': 'review',
      'current': Uint8List.fromList('disk'.codeUnits),
      'versions': [
        {
          'id': '0',
          'name': 'Other device',
          'contents': Uint8List.fromList('remote'.codeUnits),
        },
      ],
    });
    String? choice;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('Review'),
              onPressed: () async {
                choice = await showDialog<String>(
                  context: context,
                  builder: (_) =>
                      CloudConflictDialog(review: review, local: 'unsaved'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '使用所选云端版本'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('比较'));
    await tester.pumpAndSettle();
    expect(find.text('Compare Changes'), findsOneWidget);
    Navigator.of(tester.element(find.text('Compare Changes'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用所选云端版本'));
    await tester.pumpAndSettle();
    expect(choice, '0');
    expect(tester.takeException(), isNull);
  });

  test(
    'edits made during native conflict resolution stay dirty and recoverable',
    () async {
      final files = MemoryMarkdownFileService()..files['/vault/a.md'] = 'disk';
      final workspace = WorkspaceController(
        fileService: files,
        sessionStore: MemoryWorkspaceSessionStore(),
      );
      await workspace.initialize();
      await workspace.openPath('/vault/a.md');
      final document = workspace.activeDocument!;
      document.controller.text = 'new typing';
      await workspace.acceptCloudResolution(
        document,
        path: '/vault/a.md',
        reviewedLocal: 'old typing',
        resolved: 'remote',
      );
      expect(document.controller.text, 'new typing');
      expect(document.persistedText, 'remote');
      expect(document.controller.isDirty, isTrue);
      workspace.dispose();
      await files.dispose();
    },
  );

  testWidgets(
    'known conflict survives expiry and failed checking until cleared',
    (tester) async {
      var observation = DocumentSyncMetadata(
        state: CloudSyncState.conflict,
        observedAt: DateTime.now(),
      );
      final sync = DocumentSyncController(read: (_) async => observation);
      sync.configure(path: '/fixture.md', identity: 'one');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DocumentSyncIndicator(controller: sync)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(minutes: 1));
      expect(find.text('iCloud conflict'), findsOneWidget);
      observation = const DocumentSyncMetadata();
      await sync.refresh();
      await tester.pump();
      expect(find.text('iCloud conflict'), findsOneWidget);
      observation = DocumentSyncMetadata(
        state: CloudSyncState.uploaded,
        observedAt: DateTime.now(),
      );
      await sync.refresh();
      await tester.pump();
      expect(find.text('iCloud conflict'), findsNothing);
      sync.dispose();
    },
  );
}
