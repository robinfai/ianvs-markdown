import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/workspace_session_store.dart';

class PreviewDraft {
  const PreviewDraft({
    required this.root,
    required this.path,
    required this.text,
    required this.baseline,
    this.notice,
  });
  final String root;
  final String path;
  final String text;
  final String baseline;
  final String? notice;
}

abstract class PreviewDraftStore {
  Future<PreviewDraft?> load();
  Future<void> save(PreviewDraft? draft);
}

/// Reuses the verified atomic primary/backup mechanism, in an isolated mobile
/// namespace. No desktop tabs, security tokens or grants are ever restored.
class ReliablePreviewDraftStore implements PreviewDraftStore {
  ReliablePreviewDraftStore({this.directory});
  final Directory? directory;
  Future<WorkspaceSessionStore> _store() async => DesktopWorkspaceSessionStore(
    directory:
        directory ??
        Directory(
          p.join(
            (await getApplicationSupportDirectory()).path,
            'LinefoldMobileDraft',
          ),
        ),
  );

  @override
  Future<PreviewDraft?> load() async {
    final snapshot = await (await _store()).load();
    if (snapshot == null || snapshot.documents.isEmpty) return null;
    final record = snapshot.documents.single;
    final root = snapshot.workspaceRoot;
    final path = record['path'];
    if (root == null ||
        path is! String ||
        !p.isAbsolute(root) ||
        !p.isWithin(root, path)) {
      throw const FormatException('Invalid mobile recovery scope');
    }
    return PreviewDraft(
      root: root,
      path: path,
      text: record['text'] as String,
      baseline: record['persistedText'] as String,
      notice: snapshot.recoveryNotice,
    );
  }

  @override
  Future<void> save(PreviewDraft? draft) async {
    await (await _store()).save(
      WorkspaceSnapshot(
        documents: draft == null
            ? []
            : [
                {
                  'id': 'mobile-draft',
                  'name': p.basename(draft.path),
                  'path': draft.path,
                  'text': draft.text,
                  'persistedText': draft.baseline,
                },
              ],
        activeDocumentId: draft == null ? null : 'mobile-draft',
        workspaceRoot: draft?.root,
        workspaceAccessToken: null,
        sidebarVisible: false,
        outlineVisible: false,
      ),
    );
  }
}
