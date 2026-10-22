import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/workspace_controller.dart';
import '../services/attachment_repository.dart';
import '../services/document_export_service.dart';

/// One explicit export at a time. No source save, session mutation, background
/// export, upload, or third-party send is part of this workflow.
class DocumentExportFlow {
  bool _pending = false;
  bool _disposed = false;

  VoidCallback? _cancelNative;

  void dispose() {
    _disposed = true;
    _cancelNative?.call();
  }

  Future<void> run(
    BuildContext context,
    WorkspaceController workspace,
    DocumentExportAction action, {
    AttachmentSource attachmentSource = const AppleAttachmentSource(),
    DocumentExportPlatform platform = const AppleDocumentExportPlatform(),
  }) async {
    if (_pending || _disposed) return;
    final current = workspace.activeDocument;
    if (current == null) return;
    final snapshot = DocumentExportSnapshot(
      documentId: current.id,
      title: current.name,
      source: current.controller.text,
      documentPath: current.path,
      root: workspace.workspaceRoot,
      protectedPaths: List.unmodifiable([
        for (final document in workspace.documents) ?document.path,
      ]),
    );
    var stale = false;
    bool isCurrent() => !_disposed && !stale && context.mounted;
    void observe() {
      final wasStale = stale;
      // Once invalidated, switching away and back never revives the operation.
      stale =
          stale ||
          !identical(workspace.activeDocument, current) ||
          current.path != snapshot.documentPath ||
          workspace.workspaceRoot != snapshot.root ||
          workspace.documents.any(
            (document) =>
                document.path != null &&
                !snapshot.protectedPaths.contains(document.path),
          );
      if (stale && !wasStale) _cancelNative?.call();
    }

    _pending = true;
    workspace.addListener(observe);
    try {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            'Export ${action == DocumentExportAction.markdown ? 'Markdown copy' : 'HTML'}',
          ),
          content: Text(
            '${action == DocumentExportAction.markdown ? documentExportMarkdownNotice : documentExportFidelityNotice}\n\n'
            'This exports the complete document, including unsaved changes, '
            'as it was when you opened this dialog. Later edits are not included.\n\n'
            'Cancelling the Save dialog writes nothing. After Save is confirmed, '
            'the copy may be committed even if you switch tabs.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (proceed != true || !isCurrent()) return;
      final service = DocumentExportService(attachmentSource: attachmentSource);
      final document = action == DocumentExportAction.markdown
          ? service.buildMarkdown(snapshot, isCurrent: isCurrent)
          : await service.build(snapshot, isCurrent: isCurrent);
      if (!isCurrent()) return;
      // All values below are immutable. Native code never reads the source.
      _cancelNative = () {
        // Before final approval, invalidation also fails the native handshake.
        // Once approved, a synchronous commit cannot be recalled by this
        // later cross-bridge message. Never revive a stale snapshot.
        unawaited(platform.cancel(snapshot).catchError((Object _) {}));
      };
      final completed = await platform.output(
        action: action,
        document: document,
        snapshot: snapshot,
        isCurrent: isCurrent,
      );
      if (context.mounted && !_disposed && completed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${action == DocumentExportAction.markdown ? 'Markdown copy' : 'HTML'} exported. Original unchanged.',
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (context.mounted && !_disposed) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Export was not completed'),
            content: Text('$error'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      _cancelNative = null;
      workspace.removeListener(observe);
      _pending = false;
    }
  }
}
