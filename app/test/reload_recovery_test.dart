import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';

import 'support/fakes.dart';

void main() {
  test(
    'reloading disk content preserves the local draft as one undo step',
    () async {
      final files = MemoryMarkdownFileService()
        ..files['/notes/audit.md'] = '# Saved\n\nOriginal text';
      final workspace = WorkspaceController(
        fileService: files,
        sessionStore: MemoryWorkspaceSessionStore(),
      );
      addTearDown(workspace.dispose);
      addTearDown(files.dispose);
      await workspace.initialize();
      final document = (await workspace.openPath('/notes/audit.md'))!;
      const draft = '# Saved\n\nLocal draft that must survive';
      const selection = TextSelection(baseOffset: 10, extentOffset: 15);
      document.controller.value = const TextEditingValue(
        text: draft,
        selection: selection,
      );
      document.hasExternalChanges = true;
      const disk = '# External\n\nA different version';
      files.files['/notes/audit.md'] = disk;

      await workspace.reloadFromDisk(document);

      expect(document.controller.text, disk);
      expect(document.persistedText, disk);
      expect(document.controller.isDirty, isFalse);
      expect(document.hasExternalChanges, isFalse);
      expect(document.controller.canUndo, isTrue);

      document.controller.undo();
      expect(document.controller.text, draft);
      expect(document.controller.selection, selection);
      expect(document.controller.isDirty, isTrue);
      expect(files.files['/notes/audit.md'], disk);

      document.controller.redo();
      expect(document.controller.text, disk);
      expect(document.controller.isDirty, isFalse);
    },
  );

  test('reload is separate from edits made immediately afterwards', () async {
    final files = MemoryMarkdownFileService()
      ..files['/notes/audit.md'] = 'Original';
    final workspace = WorkspaceController(
      fileService: files,
      sessionStore: MemoryWorkspaceSessionStore(),
    );
    addTearDown(workspace.dispose);
    addTearDown(files.dispose);
    await workspace.initialize();
    final document = (await workspace.openPath('/notes/audit.md'))!;
    document.controller.text = 'Local';
    files.files['/notes/audit.md'] = 'Disk';
    await workspace.reloadFromDisk(document);
    document.controller.value = const TextEditingValue(
      text: 'Disk!',
      selection: TextSelection.collapsed(offset: 5),
    );

    document.controller.undo();
    expect(document.controller.text, 'Disk');
    expect(document.controller.isDirty, isFalse);
    document.controller.undo();
    expect(document.controller.text, 'Local');
    expect(document.controller.isDirty, isTrue);
  });
}
