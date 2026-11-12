import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/desktop_theme.dart';
import 'package:linefold/src/desktop_typography.dart';
import 'package:linefold/src/services/workspace_index.dart';
import 'package:linefold/src/services/workspace_move_tree.dart';
import 'package:linefold/src/services/workspace_note_move_plan.dart';
import 'package:linefold/src/services/workspace_note_transaction.dart';
import 'package:linefold/src/services/workspace_reference_index.dart';
import 'package:linefold/src/widgets/workspace_note_move_preview.dart';

import 'support/workflow_screenshot.dart';
import 'workspace_directory_move_plan_test.dart' show treeFor;
import 'workspace_note_move_plan_test.dart' show MovePlanSource;

const _capture = bool.fromEnvironment('CAPTURE_ACCEPTANCE');

void main() {
  for (final scenario in [(false, false), (true, false), (false, true)]) {
    final (blocked, dark) = scenario;
    testWidgets(
      'Chinese rename overview discloses partial coverage; blocked=$blocked, dark=$dark',
      (tester) async {
        if (_capture) {
          final icons = FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await icons.load();
          await tester.runAsync(() async {
            for (final entry in {
              DesktopTypography.fontFamily:
                  '/System/Library/Fonts/STHeiti Light.ttc',
              'Heiti SC': '/System/Library/Fonts/STHeiti Light.ttc',
            }.entries) {
              final font = File(entry.value);
              if (font.existsSync()) {
                await (FontLoader(entry.key)..addFont(
                      Future.value(
                        ByteData.sublistView(await font.readAsBytes()),
                      ),
                    ))
                    .load();
              }
            }
          });
        }
        tester.view.physicalSize = const Size(1000, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final plan = (await tester.runAsync(() async {
          final source = MovePlanSource()
            ..note('最近删除/项目资料/笔记.md', '# 笔记')
            ..note('其他目录/离线.md', 'offline');
          source.offline.add('其他目录/离线.md');
          final index = WorkspaceIndex(source: source)..configure('/vault');
          final references = WorkspaceReferenceIndex(
            index,
            normalize: (paths) async =>
                paths.map((p) => p.toLowerCase()).toList(),
          );
          addTearDown(references.dispose);
          addTearDown(index.dispose);
          return WorkspaceNoteMovePlanner(references).buildDirectory(
            snapshot: await references.refresh(),
            sourcePath: '最近删除/项目资料',
            destinationPath: '最近删除/项目资料-2',
            dirtySessionIds: {},
            tree: treeFor(
              source,
              '最近删除/项目资料',
              issues: [
                if (blocked)
                  const WorkspaceMoveTreeIssue('offline', path: '最近删除/项目资料'),
              ],
            ),
          );
        }))!;
        expect(
          plan.canExecute,
          !blocked,
          reason: plan.blockers
              .map((b) => '${b.code}: ${b.message}')
              .join('; '),
        );
        final boundary = GlobalKey();
        var calls = 0;
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: const Locale('zh'),
              supportedLocales: const [Locale('en'), Locale('zh')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: desktopTheme(dark ? Brightness.dark : Brightness.light)
                  .copyWith(
                    textTheme: desktopTheme(
                      Brightness.light,
                    ).textTheme.apply(fontFamilyFallback: const ['Heiti SC']),
                  ),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    child: const Text('Open'),
                    onPressed: () => showWorkspaceNoteMovePreview(
                      context: context,
                      sources: ['/vault/最近删除/项目资料'],
                      destinations: ['/vault/最近删除/项目资料-2'],
                      displayRoot: '/vault',
                      preview: Future.value(plan),
                      onMaintain: (approved) async {
                        expect(identical(approved, plan), isTrue);
                        calls++;
                        return WorkspaceNoteMoveRecord(
                          transactionId: 'test',
                          phase: 'completed',
                          entries: [
                            WorkspaceNoteMoveReceipt(
                              path: plan.files.first.path,
                              destinationPath: plan.files.first.destination,
                              state: 'applied',
                              verified: true,
                              actualPath: plan.files.first.destination,
                              revision: 'new',
                            ),
                          ],
                        );
                      },
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
        expect(find.text('影响概览'), findsOneWidget);
        expect(find.text('2 项目录内容'), findsNWidgets(2));
        expect(find.text('1 篇涉及笔记'), findsNWidgets(2));
        expect(find.textContaining('offline'), findsNothing);
        expect(find.textContaining('/vault/'), findsNothing);
        expect(find.text('其他目录/离线.md'), findsNothing);
        expect(find.text('Line 1:'), findsNothing);
        final action = find.byKey(const ValueKey('move-and-update-links'));
        expect(tester.widget<FilledButton>(action).onPressed != null, !blocked);
        expect(find.text(blocked ? '重命名并更新链接' : '重命名并更新已确认链接'), findsOneWidget);
        expect(find.text(blocked ? '链接维护检查未通过' : '部分链接尚未检查'), findsOneWidget);
        if (_capture) {
          await captureWorkflowScreenshot(
            tester,
            boundary,
            blocked
                ? 'rename-blocked-zh'
                : dark
                ? 'rename-partial-dark-zh'
                : 'rename-partial-zh',
          );
        }
        await tester.ensureVisible(
          find.byKey(const ValueKey('move-check-details')),
        );
        await tester.tap(find.byKey(const ValueKey('move-check-details')));
        await tester.pumpAndSettle();
        expect(find.text('其他目录/离线.md'), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const ValueKey('move-check-details')),
        );
        await tester.tap(find.byKey(const ValueKey('move-check-details')));
        await tester.pumpAndSettle();
        if (!blocked) {
          await tester.tap(action);
          await tester.pumpAndSettle();
          expect(calls, 1);
          expect(find.text('已验证重命名及已确认链接的更新，未检查的链接可能仍需处理。'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
