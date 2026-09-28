import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/widgets/file_context_menu.dart';
import 'package:linefold/src/widgets/title_tabs_bar.dart';
import 'package:linefold/src/widgets/workspace_sidebar.dart';
import 'support/fakes.dart';

void main() {
  late MemoryMarkdownFileService files;
  late WorkspaceController workspace;
  final calls = <MethodCall>[];
  setUp(() async {
    files = MemoryMarkdownFileService();
    workspace = WorkspaceController(
      fileService: files,
      sessionStore: MemoryWorkspaceSessionStore(),
    );
    await workspace.initialize();
    files.files['/notes/first.md'] = '# First';
    files.files['/notes/second.md'] = '# Second';
    await workspace.openPath('/notes/first.md');
    await workspace.openPath('/notes/second.md');
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(FileContextMenu.channel, (call) async {
          calls.add(call);
          return null;
        });
  });
  tearDown(() async {
    workspace.dispose();
    await files.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(FileContextMenu.channel, null);
  });
  Future<void> rightClick(WidgetTester tester, Finder target) async {
    await tester.tap(target, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
  }

  testWidgets('sidebar reveals clicked file and folder without selecting', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceSidebar(
            workspace: workspace,
            onError: (error) => fail(error),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await rightClick(tester, find.text('first.md'));
    expect(workspace.activeDocument!.name, 'second.md');
    await tester.tap(find.text('Reveal in Finder'));
    await tester.pumpAndSettle();
    expect(calls.single.method, 'revealInFinder');
    expect(calls.single.arguments, {'path': '/notes/first.md'});
    await rightClick(tester, find.text('/notes'));
    expect(find.text('Collapse Folder'), findsOneWidget);
    await tester.tap(find.text('Reveal in Finder'));
    await tester.pumpAndSettle();
    expect(calls.last.arguments, {'path': '/notes'});
  });
  testWidgets('tab saves and closes clicked inactive document', (tester) async {
    final first = workspace.documents.firstWhere(
      (doc) => doc.name == 'first.md',
    );
    first.controller.text = '# Edited';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TitleTabsBar(
            workspace: workspace,
            onClose: workspace.removeDocument,
          ),
        ),
      ),
    );
    await rightClick(tester, find.text('first.md'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(files.files['/notes/first.md'], '# Edited');
    expect(workspace.activeDocument!.name, 'second.md');
    await rightClick(tester, find.text('first.md'));
    await tester.tap(find.text('Close Tab'));
    await tester.pumpAndSettle();
    expect(workspace.documents, isNot(contains(first)));
  });
  testWidgets('unsaved tab omits filesystem actions', (tester) async {
    workspace.newDocument();
    final document = workspace.activeDocument!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TitleTabsBar(
            workspace: workspace,
            onClose: workspace.removeDocument,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await rightClick(tester, find.text(document.name).last);
    expect(find.text('Save As…'), findsOneWidget);
    expect(find.text('Copy Path'), findsNothing);
    expect(find.text('Reveal in Finder'), findsNothing);
  });
}
