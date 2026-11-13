import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/desktop_theme.dart';
import 'package:linefold/src/desktop_typography.dart';
import 'package:linefold/src/services/workspace_note_transaction.dart';
import 'package:linefold/src/widgets/workspace_note_move_preview.dart';

import 'support/workflow_screenshot.dart';

const _capture = bool.fromEnvironment('CAPTURE_ACCEPTANCE');
const _oldName = '2026-11-02 19-46-17.386658-15f4b311-2';
const _newName = '2026-11-02 19-46-17.386658-15f4b311-3';
const _source = '最近删除/$_oldName';
const _destination = '最近删除/$_newName';
const _file =
    'Untitled-28.mdCloud-Acceptance-20261102- conflict '
    '3153E855-ECC0-462E-BAD7-E105A7274FB2.md';

void main() {
  for (final scenario in [
    (width: 1000.0, dark: false, scale: 1.0),
    (width: 1000.0, dark: true, scale: 1.0),
    (width: 390.0, dark: false, scale: 2.0),
  ]) {
    testWidgets('result paths stay readable and copy exactly; $scenario', (
      tester,
    ) async {
      if (_capture) {
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        await tester.runAsync(() async {
          for (final name in [
            DesktopTypography.fontFamily,
            'Heiti SC',
            'monospace',
          ]) {
            final font = File(
              name == 'monospace'
                  ? '/System/Library/Fonts/Menlo.ttc'
                  : '/System/Library/Fonts/STHeiti Light.ttc',
            );
            if (font.existsSync()) {
              await (FontLoader(name)..addFont(
                    Future.value(
                      ByteData.sublistView(await font.readAsBytes()),
                    ),
                  ))
                  .load();
            }
          }
        });
      }
      tester.view.physicalSize = Size(scenario.width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final clipboard = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final boundary = GlobalKey();
      final theme = desktopTheme(
        scenario.dark ? Brightness.dark : Brightness.light,
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('zh'),
            supportedLocales: const [Locale('en'), Locale('zh')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: theme.copyWith(
              textTheme: theme.textTheme.apply(
                fontFamilyFallback: const ['Heiti SC'],
              ),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scenario.scale)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  child: const Text('Open'),
                  onPressed: () => showWorkspaceNoteMovePreview(
                    context: context,
                    sources: const [_source],
                    destinations: const [_destination],
                    initialRecord: WorkspaceNoteMoveRecord(
                      transactionId: '6a614dc9-f595-4506-ac7f-cb3483e356aa',
                      phase: 'completed',
                      version: 2,
                      namespace: const WorkspaceDirectoryMoveReceipt(
                        sourcePath: _source,
                        destinationPath: _destination,
                        actualPath: _destination,
                        identity: '1:2',
                        memberCount: 1,
                        moved: true,
                        synced: true,
                        verified: true,
                      ),
                      entries: const [
                        WorkspaceNoteMoveReceipt(
                          path: '$_source/$_file',
                          destinationPath: '$_destination/$_file',
                          actualPath: '$_destination/$_file',
                          state: 'applied',
                          verified: true,
                          revision: 'new',
                        ),
                      ],
                    ),
                    onRecoverCopies: (_) async =>
                        throw StateError('Not invoked'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/icons/move-preview-atlas.png'),
          tester.element(find.text('Open')),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      Future<void> expand(String key) async {
        final tile = find.byKey(ValueKey(key));
        await tester.ensureVisible(tile);
        await tester.tap(
          find.descendant(of: tile, matching: find.byType(ListTile)).first,
        );
        await tester.pumpAndSettle();
      }

      await expand('move-result-details');
      expect(find.textContaining('恢复记录：'), findsNothing);
      expect(find.text(_file), findsNothing);
      await expand('move-full-paths');
      expect(find.text(_source, findRichText: true), findsOneWidget);
      expect(find.text(_destination, findRichText: true), findsOneWidget);
      expect(find.textContaining('applied'), findsNothing);
      expect(tester.takeException(), isNull);
      if (_capture) {
        await captureWorkflowScreenshot(
          tester,
          boundary,
          scenario.width < 500
              ? 'move-result-narrow-zh'
              : scenario.dark
              ? 'move-result-dark-zh'
              : 'move-result-zh',
        );
      }
      for (final label in ['原路径', '新路径']) {
        final copy = find.byTooltip('复制$label');
        await tester.ensureVisible(copy);
        await tester.tap(copy);
        await tester.pumpAndSettle();
        expect(find.byTooltip('路径已复制'), findsOneWidget);
      }
      expect(clipboard, [_source, _destination]);
      await expand('move-full-paths');
      await expand('move-updated-files');
      expect(find.text(_file), findsOneWidget);
      expect(find.text('更新已验证'), findsOneWidget);
      expect(find.textContaining('恢复记录：'), findsNothing);
      expect(tester.takeException(), isNull);
      await expand('move-updated-files');
      await expand('move-technical-details');
      expect(find.textContaining('恢复记录：6a614dc9-'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
