import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/app.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';

import '../../test/fixtures/large_documents.dart';
import 'support/fakes.dart';

void main() {
  for (final entry in largeDocuments.entries) {
    testWidgets(
      'app preserves default-budget ${entry.key} through edit, Read and reopen',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.menu,
          (_) async => null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.menu,
            null,
          ),
        );
        final files = MemoryMarkdownFileService()
          ..files['/notes/large.md'] = entry.value;
        final workspace = WorkspaceController(
          fileService: files,
          sessionStore: MemoryWorkspaceSessionStore(),
        );
        addTearDown(workspace.dispose);
        addTearDown(files.dispose);
        await tester.pumpWidget(LinefoldApp(workspaceController: workspace));
        await tester.pumpAndSettle();
        final document = (await workspace.openPath('/notes/large.md'))!;
        await tester.pumpAndSettle();
        expect(
          document.controller.parseDecision.budgetExceeded?.name,
          entry.key,
        );
        final field = find.byKey(const ValueKey('ianvs-markdown-source-field'));
        expect(field, findsOneWidget);
        expect(
          find.byKey(const ValueKey('ianvs-markdown-budget-notice')),
          findsOneWidget,
        );
        final edited = '${entry.value} saved';
        await tester.enterText(field, edited);
        await tester.pumpAndSettle();
        Future<void> mode(String name) async {
          await tester.tap(find.byTooltip('Editor mode'));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(ValueKey('editor-mode-$name')));
          await tester.pumpAndSettle();
        }

        await mode('preview');
        expect(
          find.byKey(const ValueKey('ianvs-markdown-plain-fallback')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('ianvs-markdown-budget-notice')),
          findsOneWidget,
        );
        expect(document.controller.text == edited, isTrue);
        await mode('source');
        await tester.tap(field);
        await tester.pumpAndSettle();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();
        expect(files.files['/notes/large.md'] == edited, isTrue);
        expect(document.controller.isDirty, isFalse);
        workspace.removeDocument(document);
        final reopened = (await workspace.openPath('/notes/large.md'))!;
        await tester.pumpAndSettle();
        expect(reopened.controller.text == edited, isTrue);
        expect(reopened.controller.isDirty, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 600));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }
}
