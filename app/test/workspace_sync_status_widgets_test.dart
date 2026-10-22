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
  testWidgets('desktop status details remain reachable in a short 3x window', (
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
    expect(find.text('iCloud upload pending'), findsOneWidget);
    final status = find.byTooltip('Cloud status details and retry');
    await tester.ensureVisible(status);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getSemantics(find.text('iCloud upload pending')).label,
      'iCloud upload pending',
    );
    await tester.tap(status);
    await tester.pumpAndSettle();
    expect(find.text('Cloud status'), findsOneWidget);
    expect(
      find.text(
        'iCloud has not reported this item uploaded. Pending does not identify a network problem.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    semantics.dispose();
    workspace.dispose();
    await files.dispose();
  });
}
