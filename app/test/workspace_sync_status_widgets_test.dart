import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/desktop_theme.dart';
import 'package:linefold/src/models/document_sync_status.dart';
import 'package:linefold/src/widgets/editor_shell.dart';

import 'support/fakes.dart';

class _Metadata implements DocumentSyncSource {
  @override
  Future<DocumentSyncMetadata> readSyncMetadata(String path) async =>
      DocumentSyncMetadata(
        state: CloudSyncState.uploadPending,
        observedAt: DateTime.now(),
      );
}

void main() {
  testWidgets('routine cloud activity stays silent in a short 3x window', (
    tester,
  ) async {
    final files = MemoryMarkdownFileService()
      ..files['/synthetic/note.md'] = '# Synthetic fixture';
    final workspace = WorkspaceController(
      fileService: files,
      sessionStore: MemoryWorkspaceSessionStore(),
      syncSource: _Metadata(),
    );
    await workspace.initialize();
    await workspace.openPath('/synthetic/note.md');
    await tester.binding.setSurfaceSize(const Size(840, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: desktopTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(3)),
          child: child!,
        ),
        home: EditorShell(
          workspace: workspace,
          dark: false,
          onToggleTheme: () {},
          enableFileDrop: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Saved locally'), findsOneWidget);
    expect(find.text('iCloud upload pending'), findsNothing);
    expect(find.byTooltip('Cloud status details and retry'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    semantics.dispose();
    workspace.dispose();
    await files.dispose();
  });
}
