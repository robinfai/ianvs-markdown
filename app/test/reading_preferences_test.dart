import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/controllers/file_association_controller.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/models/reading_preferences.dart';
import 'package:linefold/src/reading_typography.dart';
import 'package:linefold/src/services/workspace_session_store.dart';
import 'package:linefold/src/widgets/app_settings_dialog.dart';

import 'support/fakes.dart';

void main() {
  test('old and malformed snapshots retain safe reading defaults', () {
    expect(
      WorkspaceSnapshot.fromJson({}).readingPreferences,
      ReadingPreferences.defaults,
    );
    expect(ReadingPreferences.fromJson('broken'), ReadingPreferences.defaults);
    expect(
      ReadingPreferences.fromJson({
        'fontSize': double.nan,
        'lineHeight': 'bad',
        'width': 'unknown',
      }),
      ReadingPreferences.defaults,
    );
    final clamped = ReadingPreferences(fontSize: 100, lineHeight: 0);
    expect(clamped.fontSize, 28);
    expect(clamped.lineHeight, 1.2);
  });

  test(
    'preferences survive serialized restart without editing documents',
    () async {
      final files = MemoryMarkdownFileService();
      final store = MemoryWorkspaceSessionStore();
      final workspace = WorkspaceController(
        fileService: files,
        sessionStore: store,
      );
      addTearDown(files.dispose);
      addTearDown(workspace.dispose);
      await workspace.initialize();
      final document = workspace.activeDocument!;
      final before = document.controller.value;
      final undo = document.controller.canUndo;
      final preferences = ReadingPreferences(
        fontSize: 20,
        wrapCode: false,
        lineHeight: 1.8,
        width: ReadingWidth.wide,
      );
      workspace.setReadingPreferences(preferences);
      expect(document.controller.value, before);
      expect(document.controller.canUndo, undo);
      await workspace.flushSession();
      store.snapshot = WorkspaceSnapshot.fromJson(
        Map<String, Object?>.from(
          jsonDecode(jsonEncode(store.snapshot!.toJson())) as Map,
        ),
      );
      final restarted = WorkspaceController(
        fileService: files,
        sessionStore: store,
      );
      addTearDown(restarted.dispose);
      await restarted.initialize();
      expect(restarted.readingPreferences, preferences);
      expect(restarted.activeDocument!.controller.text, before.text);
      await restarted.flushSession();
    },
  );

  testWidgets('reading styles scale body and headings with chosen spacing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final base = ianvsMarkdownStyleSheet(context);
            final style = readingStyleSheet(
              context,
              ReadingPreferences(fontSize: 20, lineHeight: 1.8),
            );
            expect(style.p!.fontSize, 20);
            expect(style.p!.height, 1.8);
            expect(
              style.h1!.fontSize,
              closeTo(base.h1!.fontSize! * 20 / 14.5, 0.001),
            );
            expect(style.tableBody!.fontSize, 20);
            expect(style.listBullet!.height, 1.8);
            return const SizedBox();
          },
        ),
      ),
    );
  });

  testWidgets('settings change and reset persisted reading preferences', (
    tester,
  ) async {
    final files = MemoryMarkdownFileService();
    final store = MemoryWorkspaceSessionStore();
    final workspace = WorkspaceController(
      fileService: files,
      sessionStore: store,
    );
    final association = FileAssociationController(
      service: MemoryFileAssociationService(),
    );
    addTearDown(files.dispose);
    addTearDown(workspace.dispose);
    addTearDown(association.dispose);
    await workspace.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSettingsDialog(
            fileAssociation: association,
            workspace: workspace,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('reading-font-size')));
    await tester.pumpAndSettle();
    expect(workspace.readingPreferences.fontSize, greaterThan(14.5));
    await tester.tap(find.byKey(const ValueKey('reading-line-height')));
    await tester.pumpAndSettle();
    expect(workspace.readingPreferences.lineHeight, closeTo(1.7, 0.03));
    await tester.tap(find.byKey(const ValueKey('reading-width')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wide body').last);
    await tester.pumpAndSettle();
    expect(workspace.readingPreferences.width, ReadingWidth.wide);
    await tester.ensureVisible(find.byKey(const ValueKey('reading-wrap-code')));
    await tester.tap(find.byKey(const ValueKey('reading-wrap-code')));
    await tester.pumpAndSettle();
    expect(workspace.readingPreferences.wrapCode, isFalse);
    await workspace.flushSession();
    expect(store.snapshot!.readingPreferences, workspace.readingPreferences);
    await tester.ensureVisible(find.text('Reset reading settings'));
    await tester.tap(find.text('Reset reading settings'));
    await tester.pumpAndSettle();
    expect(workspace.readingPreferences, ReadingPreferences.defaults);
    await workspace.flushSession();
    expect(store.snapshot!.readingPreferences, ReadingPreferences.defaults);
  });
}
