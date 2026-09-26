import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/app.dart';
import 'package:linefold/src/controllers/file_association_controller.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/services/workspace_session_store.dart';
import 'package:linefold/src/widgets/app_settings_dialog.dart';

import 'support/fakes.dart';

void main() {
  void configure(WidgetTester tester) {
    tester.view.physicalSize = const Size(840, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.menu,
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.menu,
        null,
      ),
    );
  }

  Future<WorkspaceController> launch(
    WidgetTester tester,
    MemoryFileAssociationService preferences, {
    MemoryMarkdownFileService? fileService,
    WorkspaceSessionStore? sessionStore,
    MemoryIncomingFilesService? incoming,
  }) async {
    final files = fileService ?? MemoryMarkdownFileService();
    final workspace = WorkspaceController(
      fileService: files,
      sessionStore: sessionStore ?? MemoryWorkspaceSessionStore(),
    );
    final controller = FileAssociationController(service: preferences);
    addTearDown(workspace.dispose);
    addTearDown(files.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      LinefoldApp(
        workspaceController: workspace,
        fileAssociationController: controller,
        incomingFilesService: incoming ?? MemoryIncomingFilesService(),
      ),
    );
    return workspace;
  }

  Future<void> openSettings(WidgetTester tester) async {
    final menu = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));
    final appMenu = menu.menus.whereType<PlatformMenu>().singleWhere(
      (item) => item.label == 'Linefold',
    );
    final settings = appMenu.menus
        .whereType<PlatformMenuItemGroup>()
        .expand((item) => item.members)
        .singleWhere((item) => item.label == 'Settings…');
    expect(
      (settings.shortcut as SingleActivator).trigger,
      LogicalKeyboardKey.comma,
    );
    settings.onSelected!();
    await tester.pumpAndSettle();
  }

  testWidgets(
    'declining first-run association is remembered on the next launch',
    (tester) async {
      configure(tester);
      final preferences = MemoryFileAssociationService();
      await launch(tester, preferences);
      await tester.pumpAndSettle();
      expect(find.byType(DefaultMarkdownAppPrompt), findsOneWidget);
      await tester.tap(find.text('Keep Current App'));
      await tester.pumpAndSettle();
      expect(preferences.preference, isFalse);
      expect(find.byType(DefaultMarkdownAppPrompt), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await launch(tester, preferences);
      await tester.pumpAndSettle();
      expect(find.byType(DefaultMarkdownAppPrompt), findsNothing);
      expect(preferences.changes, [false]);
      await tester.pump(const Duration(milliseconds: 400));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'Escape remembers keeping the current application',
    (tester) async {
      configure(tester);
      final preferences = MemoryFileAssociationService();
      await launch(tester, preferences);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(DefaultMarkdownAppPrompt), findsNothing);
      expect(preferences.preference, isFalse);
      expect(preferences.isDefault, isFalse);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'a cancelled opt-out can be retried from settings after restarting',
    (tester) async {
      configure(tester);
      final preferences = MemoryFileAssociationService()
        ..preference = false
        ..isDefault = true;
      await launch(tester, preferences);
      await tester.pumpAndSettle();
      expect(find.byType(DefaultMarkdownAppPrompt), findsNothing);
      await openSettings(tester);
      expect(find.text('Current default: Linefold'), findsOneWidget);
      await tester.tap(find.text('Restore Previous Default'));
      await tester.pumpAndSettle();
      expect(find.text('Current default: Other Editor'), findsOneWidget);
      expect(preferences.changes, [false]);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'acceptance can be changed later from the native settings menu',
    (tester) async {
      configure(tester);
      final preferences = MemoryFileAssociationService();
      await launch(tester, preferences);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use Linefold'));
      await tester.pumpAndSettle();
      expect(preferences.preference, isTrue);
      await openSettings(tester);
      expect(find.text('Current default: Linefold'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('default-markdown-app-preference')),
      );
      await tester.pumpAndSettle();
      expect(preferences.preference, isFalse);
      expect(find.text('Current default: Other Editor'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(AppSettingsDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'a denied association shows the saved preference and real system status',
    (tester) async {
      configure(tester);
      final preferences = MemoryFileAssociationService()..rejectChange = true;
      await launch(tester, preferences);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use Linefold'));
      await tester.pumpAndSettle();
      expect(find.byType(AppSettingsDialog), findsOneWidget);
      expect(find.textContaining('macOS did not change'), findsOneWidget);
      expect(find.text('Current default: Other Editor'), findsOneWidget);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
      );
      preferences.rejectChange = false;
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();
      expect(find.text('Current default: Linefold'), findsOneWidget);
      expect(find.text('Try Again'), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'Command comma opens settings and refreshes the external default',
    (tester) async {
      configure(tester);
      final preferences = MemoryFileAssociationService()..preference = false;
      await launch(tester, preferences);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(EditableText).first);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.comma);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(find.byType(AppSettingsDialog), findsOneWidget);
      expect(find.text('Current default: Other Editor'), findsOneWidget);
      preferences.isDefault = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Current default: Linefold'), findsOneWidget);
      expect(preferences.changes, isEmpty);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'Finder files wait for recovery and live opens reuse existing tabs',
    (tester) async {
      configure(tester);
      final preferences = MemoryFileAssociationService()..preference = false;
      final store = _DelayedSessionStore();
      final incoming = MemoryIncomingFilesService()
        ..initialPaths = ['/notes/cold.md'];
      final files = MemoryMarkdownFileService()
        ..files['/notes/cold.md'] = '# Cold start'
        ..files['/notes/live.md'] = '# Live open';
      final workspace = await launch(
        tester,
        preferences,
        fileService: files,
        sessionStore: store,
        incoming: incoming,
      );
      expect(incoming.onOpen, isNull);
      store.ready.complete(null);
      await tester.pumpAndSettle();
      expect(workspace.activeDocument!.path, '/notes/cold.md');
      workspace.activeDocument!.controller.text = 'Unsaved local changes';
      await incoming.deliver([
        '/notes/cold.md',
        '/notes/missing.md',
        '/notes/live.md',
      ]);
      await tester.pumpAndSettle();
      final cold = workspace.documents.where(
        (document) => document.path == '/notes/cold.md',
      );
      expect(cold, hasLength(1));
      expect(cold.single.controller.text, 'Unsaved local changes');
      expect(workspace.activeDocument!.path, '/notes/live.md');
      expect(
        find.textContaining('Unable to open /notes/missing.md'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}

class _DelayedSessionStore extends MemoryWorkspaceSessionStore {
  final ready = Completer<WorkspaceSnapshot?>();

  @override
  Future<WorkspaceSnapshot?> load() => ready.future;
}
