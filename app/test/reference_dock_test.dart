import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/widgets/reference_dock.dart';

import 'support/fakes.dart';

void main() {
  testWidgets(
    'pinned open note follows edits without changing active document',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
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
      await workspace.initialize();
      final reference = workspace.newDocument(name: 'Reference.md');
      reference.controller.text = 'Reference content';
      final draft = workspace.newDocument(name: 'Draft.md');
      String? inserted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: ReferenceDock(
                workspace: workspace,
                onClose: () {},
                onInsert: (value) => inserted = value,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reference.md'));
      await tester.pumpAndSettle();
      expect(workspace.activeDocument, same(draft));
      reference.controller.text = 'Updated reference';
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Insert reference at cursor'));
      expect(inserted, 'Updated reference');
      expect(workspace.activeDocument, same(draft));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    },
  );
}
