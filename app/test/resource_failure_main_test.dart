import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/app.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';

import 'support/fakes.dart';

void main() {
  for (final missing in [false, true]) {
    testWidgets(
      'main Read image link shows recoverable error; missing=$missing',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final directory = await tester.runAsync(
          () => Directory.systemTemp.createTemp('ianvs-resource-test-'),
        );
        addTearDown(() => directory!.delete(recursive: true));
        if (!missing) {
          await tester.runAsync(
            () => File(
              '${directory!.path}/bad.svg',
            ).writeAsBytes([0xff, 0xfe, 0xff]),
          );
        }
        const source = '[Test image](bad.svg)\n\nSource remains intact.';
        final files = MemoryMarkdownFileService()
          ..files['${directory!.path}/index.md'] = source;
        final workspace = WorkspaceController(
          fileService: files,
          sessionStore: MemoryWorkspaceSessionStore(),
        );
        addTearDown(workspace.dispose);
        addTearDown(files.dispose);
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
        await workspace.initialize();
        final document = (await workspace.openPath(
          '${directory.path}/index.md',
        ))!;
        document.controller.mode = IanvsMarkdownEditorMode.preview;
        await tester.pumpWidget(LinefoldApp(workspaceController: workspace));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Test image'));
        await tester.pump();
        for (
          var i = 0;
          i < 100 &&
              find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(tester.takeException(), isNull);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(ErrorWidget), findsNothing);
        expect(
          find.textContaining(missing ? 'Cannot open file' : 'FormatException'),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('Close image'));
        await tester.pumpAndSettle();
        expect(document.controller.text, source);
        expect(document.controller.isDirty, isFalse);
        expect(find.text('Source remains intact.'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 600));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }
}
