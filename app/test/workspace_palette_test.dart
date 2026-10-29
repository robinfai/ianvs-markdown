import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/app.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/models/document_session.dart';
import 'package:linefold/src/widgets/workspace_palette.dart';

import 'support/fakes.dart';

void main() {
  test('closed notes retain recent rank after workspace recovery', () async {
    final files = MemoryMarkdownFileService();
    files.files['/notes/recent.md'] = '# Recent';
    final store = MemoryWorkspaceSessionStore();
    final workspace = WorkspaceController(
      fileService: files,
      sessionStore: store,
    );
    await workspace.initialize();
    final note = (await workspace.openPath('/notes/recent.md'))!;
    workspace.removeDocument(note);
    await workspace.flushSession();
    final rank = workspace.recentNoteActivation('/notes/recent.md');
    expect(rank, greaterThan(0));
    workspace.dispose();
    final restored = WorkspaceController(
      fileService: files,
      sessionStore: store,
    );
    await restored.initialize();
    expect(restored.recentNoteActivation('/notes/recent.md'), rank);
    restored.dispose();
    await files.dispose();
  });

  test(
    'note titles prefer metadata and fall back to headings and filenames',
    () {
      expect(
        paletteNoteTitle('---\ntitle: Reading\n---\n# Other', 'a'),
        'Reading',
      );
      expect(paletteNoteTitle('# Heading\nBody', 'a'), 'Heading');
      expect(paletteNoteTitle('Body', 'a.md'), 'a.md');
      expect(paletteNoteTitle('```\n# fake\n```\n# Real', 'a'), 'Real');
    },
  );

  test('recent activation survives session serialization', () {
    final document = DocumentSession(id: 'one', name: 'one.md', text: 'body');
    document.lastActivated = 1234;
    final restored = DocumentSession.fromJson(document.toJson());
    expect(restored.lastActivated, 1234);
    expect(restored.controller.text, 'body');
    document.dispose();
    restored.dispose();
  });

  testWidgets('filter aliases, choose with keys, and create unmatched note', (
    tester,
  ) async {
    WorkspacePaletteSelection? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<WorkspacePaletteSelection>(
                context: context,
                builder: (_) => const WorkspacePalette(
                  title: 'Quick switcher',
                  allowCreate: true,
                  entries: [
                    WorkspacePaletteEntry(
                      id: 'a',
                      title: 'Alpha',
                      searchTerms: 'project launch',
                      detail: 'work/Alpha.md',
                    ),
                    WorkspacePaletteEntry(id: 'b', title: 'Beta', recency: 10),
                  ],
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final query = find.byKey(const ValueKey('workspace-palette-query'));
    expect(
      tester.getTopLeft(find.text('Beta')).dy,
      lessThan(tester.getTopLeft(find.text('Alpha')).dy),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(result?.id, 'a');
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(query, 'launch');
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);
    await tester.enterText(query, 'New idea');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create “New idea”'));
    await tester.pumpAndSettle();
    expect(result?.id, 'New idea');
    expect(result?.create, isTrue);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('shell palette creates a named draft and commands change mode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final files = MemoryMarkdownFileService();
    final workspace = WorkspaceController(
      fileService: files,
      sessionStore: MemoryWorkspaceSessionStore(),
    );
    addTearDown(workspace.dispose);
    addTearDown(files.dispose);
    await tester.pumpWidget(LinefoldApp(workspaceController: workspace));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-switcher-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('workspace-palette-query')),
      'Research plan',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create “Research plan”'));
    await tester.pumpAndSettle();
    expect(workspace.activeDocument?.name, 'Research plan.md');
    await tester.tap(find.byKey(const ValueKey('command-palette-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('workspace-palette-query')),
      'Source mode',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('palette-entry-Source mode')));
    await tester.pumpAndSettle();
    expect(workspace.activeDocument?.controller.mode.name, 'source');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 600));
  });
}
