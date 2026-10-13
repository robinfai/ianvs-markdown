import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/services/workspace_session_store.dart';

void main() {
  test(
    'diagnostic session directory uses the normal persisted format in isolation',
    () async {
      final first = await Directory.systemTemp.createTemp('session-first-');
      final second = await Directory.systemTemp.createTemp('session-second-');
      addTearDown(() => first.delete(recursive: true));
      addTearDown(() => second.delete(recursive: true));
      final store = DesktopWorkspaceSessionStore(directory: first);
      const snapshot = WorkspaceSnapshot(
        documents: [],
        activeDocumentId: null,
        workspaceRoot: null,
        workspaceAccessToken: null,
        sidebarVisible: true,
        outlineVisible: false,
      );
      await store.save(snapshot);
      expect((await store.load())!.toJson(), snapshot.toJson());
      expect(
        await DesktopWorkspaceSessionStore(directory: second).load(),
        isNull,
      );
      expect(
        await File('${first.path}/ianvs-markdown/workspace.json.tmp').exists(),
        isFalse,
      );
    },
  );
}
