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

  void dispose() => _disposed = true;

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
    }

    _pending = true;
    workspace.addListener(observe);
    try {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            action == DocumentExportAction.print
                ? 'Print document'
                : 'Export ${action.name.toUpperCase()}',
          ),
          content: const Text(
            '$documentExportFidelityNotice\n\n'
            'This exports the complete document, including unsaved changes, '
            'as it was when you opened this dialog. Later edits are not included.',
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
      final document = await DocumentExportService(
        attachmentSource: attachmentSource,
      ).build(snapshot, isCurrent: isCurrent);
      if (!isCurrent()) return;
      // All values below are immutable. Native code never reads the source.
      final completed = await platform.output(
        action: action,
        document: document,
        snapshot: snapshot,
      );
      if (context.mounted && completed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == DocumentExportAction.print
                  ? 'Print operation completed.'
                  : '${action.name.toUpperCase()} exported. Markdown original unchanged.',
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
      workspace.removeListener(observe);
      _pending = false;
    }
  }
}
