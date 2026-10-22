import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/services/markdown_file_service.dart';
import 'wiki_note_navigation_test.dart' show WikiFiles;
import 'support/fakes.dart' show MemoryWorkspaceSessionStore;

class ScopedFiles extends WikiFiles {
  final scopes = <String>{};
  @override
  Future<String?> createPersistentAccessToken(String path) async {
    scopes.add(path);
    return 'access:$path';
  }

  @override
  Future<String?> restorePersistentAccess(String token) async {
    final path = await super.restorePersistentAccess(token);
    if (path != null) scopes.add(path);
    return path;
  }

  @override
  bool fileExists(String path) =>
      super.fileExists(path) &&
      scopes.any((s) => path == s || path.startsWith('$s/'));
}

void main() {
  test(
    'Wiki-opened target must survive workspace change and sandbox restart',
    () async {
      final files = ScopedFiles()
        ..selectedFolder = '/vault'
        ..files.addAll({
          '/vault/Origin.md': '[[Target]]',
          '/vault/Target.md': 'disk',
        });
      files.directories['/vault'] = [
        const WorkspaceEntry(
          path: '/vault/Origin.md',
          name: 'Origin.md',
          isDirectory: false,
        ),
        const WorkspaceEntry(
          path: '/vault/Target.md',
          name: 'Target.md',
          isDirectory: false,
        ),
      ];
      files.directories['/other'] = [];
      final store = MemoryWorkspaceSessionStore();
      final workspace = WorkspaceController(
        fileService: files,
        sessionStore: store,
      );
      await workspace.initialize();
      await workspace.chooseWorkspaceFolder();
      await workspace.openPath('/vault/Origin.md');
      final target = await workspace.openIndexedNote(
        'Target.md',
        epoch: workspace.index.epoch,
        isCurrent: () => true,
      );
      expect(target?.accessToken, 'access:/vault/Target.md');
      files.selectedFolder = '/other';
      await workspace.chooseWorkspaceFolder();
      await workspace.flushSession();
      workspace.dispose();
      files.scopes.clear();
      final restored = WorkspaceController(
        fileService: files,
        sessionStore: store,
      );
      addTearDown(restored.dispose);
      addTearDown(files.dispose);
      await restored.initialize();
      expect(files.scopes, contains('/vault/Target.md'));
      expect(
        restored.documents.any((d) => d.path == '/vault/Target.md'),
        isTrue,
      );
    },
  );
}
