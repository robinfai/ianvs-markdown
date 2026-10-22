import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/controllers/workspace_controller.dart';
import 'package:linefold/src/desktop_theme.dart';
import 'package:linefold/src/widgets/editor_shell.dart';
import 'package:linefold/src/services/workspace_index_source.dart';
import 'package:linefold/src/widgets/workspace_references_panel.dart';
import 'package:linefold/src/widgets/wiki_note_picker.dart';

import 'wiki_note_navigation_test.dart'
    show WikiFiles, IdentityWikiFiles, wikiWorkspace;

void main() {
  late WikiFiles files;
  late WorkspaceController workspace;
  Future<void> open(
    WidgetTester tester, {
    WikiFiles? filesystem,
    Size size = const Size(1100, 850),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    files = (filesystem ?? WikiFiles())
      ..files.addAll({
        '/vault/Origin.md':
            'before [[Target|label]] #project\n`#project [[Target]]`',
        '/vault/Target.md': '---\ntags: [project]\n---\nTarget body',
      });
    workspace = await wikiWorkspace(files);
    addTearDown(workspace.dispose);
    addTearDown(files.dispose);
    workspace.setMode(IanvsMarkdownEditorMode.livePreview);
    await tester.pumpWidget(
      MaterialApp(
        theme: desktopTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: EditorShell(
          workspace: workspace,
          dark: false,
          onToggleTheme: () {},
          enableFileDrop: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> backlinks(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('workspace-backlinks-button')));
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets(
    'backlink opens exact source occurrence in existing dirty tab and preserves mode',
    (tester) async {
      await open(tester);
      final origin = workspace.activeDocument!;
      origin.controller.text = '😀 dirty [[Target|label]] #project';
      final target = (await workspace.openPath('/vault/Target.md'))!;
      await tester.pumpAndSettle();
      await backlinks(tester);
      expect(find.byType(WorkspaceReferencesPanel), findsOneWidget);
      expect(
        find.byKey(const ValueKey('workspace-reference-result-0')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('workspace-reference-result-0')),
      );
      await tester.pumpAndSettle();
      expect(workspace.activeDocument, same(origin));
      expect(origin.controller.text, '😀 dirty [[Target|label]] #project');
      expect(origin.controller.isDirty, isTrue);
      expect(origin.controller.mode, IanvsMarkdownEditorMode.livePreview);
      expect(
        origin.controller.selection.textInside(origin.controller.text),
        '[[Target|label]]',
      );
      expect(workspace.documents, contains(target));
      expect(files.files['/vault/Origin.md'], startsWith('before'));
      await finish(tester);
    },
  );

  testWidgets(
    'real rendered tag tap opens semantic postings in Read mode, excluding code',
    (tester) async {
      await open(tester);
      workspace.setMode(IanvsMarkdownEditorMode.preview);
      await tester.pumpAndSettle();
      final tagChip = find.byKey(const ValueKey('ianvs-markdown-tag'));
      expect(tagChip, findsOneWidget);
      await tester.tap(tagChip);
      await tester.pumpAndSettle();
      expect(find.text('Tag · #project'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('workspace-reference-result-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('workspace-reference-result-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('workspace-reference-result-2')),
        findsNothing,
      );
      await tester.tap(find.byTooltip('Close references'));
      await tester.pumpAndSettle();
      expect(workspace.activeDocument!.controller.text, startsWith('before'));
      await finish(tester);
    },
  );

  testWidgets(
    'captured stale backlink cannot apply old offsets after another dirty edit',
    (tester) async {
      await open(tester);
      final origin = workspace.activeDocument!;
      final target = (await workspace.openPath('/vault/Target.md'))!;
      await tester.pumpAndSettle();
      await backlinks(tester);
      final tile = tester.widget<ListTile>(
        find.byKey(const ValueKey('workspace-reference-result-0')),
      );
      origin.controller.text = 'rewritten source without that link';
      tile.onTap!();
      await tester.pumpAndSettle();
      expect(workspace.activeDocument, same(target));
      expect(origin.controller.text, 'rewritten source without that link');
      expect(
        find.text(
          'Source changed since this result. Search again to use current offsets.',
        ),
        findsOneWidget,
      );
      await finish(tester);
    },
  );

  testWidgets(
    'verified case alias uses canonical backlink identity and dirty source',
    (tester) async {
      final identity = IdentityWikiFiles()
        ..aliases['/vault/target.md'] = '/vault/Target.md';
      await open(tester, filesystem: identity);
      await workspace.openPath('/vault/target.md');
      await tester.pumpAndSettle();
      await backlinks(tester);
      expect(
        find.byKey(const ValueKey('workspace-reference-result-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('workspace-reference-result-1')),
        findsNothing,
      );
      await tester.tap(find.byTooltip('Close references'));
      await tester.pumpAndSettle();
      await finish(tester);
    },
  );

  testWidgets(
    'source selection alone does not parse again and IME blocks opening',
    (tester) async {
      await open(tester);
      final c = workspace.activeDocument!.controller;
      await tester.runAsync(() => workspace.references.refresh());
      final parsed = workspace.references.parseCount;
      c.selection = const TextSelection.collapsed(offset: 3);
      await tester.runAsync(() => workspace.references.refresh());
      expect(workspace.references.parseCount, parsed);
      workspace.setMode(IanvsMarkdownEditorMode.source);
      await tester.pumpAndSettle();
      c.value = c.value.copyWith(composing: const TextRange(start: 0, end: 3));
      await tester.pump();
      await backlinks(tester);
      expect(find.byType(WorkspaceReferencesPanel), findsNothing);
      c.value = c.value.copyWith(composing: TextRange.empty);
      await finish(tester);
    },
  );
  testWidgets(
    'backlinks stay reachable in a short 3x window with a long title',
    (tester) async {
      await open(tester, size: const Size(840, 480), textScale: 3);
      const name =
          'A very long document name with many words and a lengthy suffix.md';
      files.files['/vault/$name'] = '';
      await workspace.openPath('/vault/$name');
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('workspace-backlinks-button'));
      final bounds = tester.getRect(button);
      final row = tester.getRect(
        find.byKey(const ValueKey('document-context-row')),
      );
      expect(row.contains(bounds.topLeft), isTrue);
      expect(row.contains(bounds.bottomRight), isTrue);
      expect(
        bounds.right,
        lessThanOrEqualTo(
          tester
              .getRect(find.byKey(const ValueKey('insert-wiki-link-button')))
              .left,
        ),
      );
      expect(tester.takeException(), isNull);
      await backlinks(tester);
      expect(find.byType(WorkspaceReferencesPanel), findsOneWidget);
      await tester.drag(
        find.byType(CustomScrollView).last,
        const Offset(0, -800),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close references'));
      await tester.pumpAndSettle();
      expect(find.byType(WorkspaceReferencesPanel), findsNothing);
      await finish(tester);
    },
  );

  testWidgets(
    'slow alias resolution is visible and cancellation never navigates',
    (tester) async {
      await open(tester);
      final origin = workspace.activeDocument!;
      final gate = Completer<WorkspaceTextRead>();
      files.onText = (_) => gate.future;
      final editor = tester.widget<IanvsMarkdownLiveEditor>(
        find.byType(IanvsMarkdownLiveEditor),
      );
      editor.onTapLinkTarget!(
        const IanvsMarkdownLinkTarget(
          text: 'Target',
          href: 'Target',
          kind: IanvsMarkdownLinkKind.wiki,
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.text('Resolving local note names and aliases…'),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Cancel'));
      gate.complete(const WorkspaceTextRead('body', '1'));
      await tester.pumpAndSettle();
      expect(workspace.activeDocument, same(origin));
      expect(workspace.references.cancelled, isTrue);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );
  testWidgets(
    'dirty YAML alias and filename collision require choosing a real note',
    (tester) async {
      final filesystem = WikiFiles()
        ..files['/vault/Alias.md'] = 'filename identity';
      await open(tester, filesystem: filesystem);
      final origin = workspace.activeDocument!;
      final target = (await workspace.openPath('/vault/Target.md'))!;
      target.controller.text = '---\naliases: [Alias]\n---\ndirty target';
      workspace.selectDocument(workspace.documents.indexOf(origin));
      await tester.pumpAndSettle();
      final editor = tester.widget<IanvsMarkdownLiveEditor>(
        find.byType(IanvsMarkdownLiveEditor),
      );
      editor.onTapLinkTarget!(
        const IanvsMarkdownLinkTarget(
          text: 'Alias',
          href: 'Alias',
          kind: IanvsMarkdownLinkKind.wiki,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WikiNotePicker), findsOneWidget);
      expect(find.byKey(const ValueKey('wiki-note-Alias.md')), findsOneWidget);
      expect(find.text('Target.md'), findsWidgets);
      await tester.tap(
        find.descendant(
          of: find.byType(WikiNotePicker),
          matching: find.text('Target.md'),
        ),
      );
      await tester.pumpAndSettle();
      expect(workspace.activeDocument, same(target));
      expect(target.controller.isDirty, isTrue);
      expect(target.controller.text, contains('dirty target'));
      expect(files.files['/vault/Target.md'], isNot(contains('aliases')));
      await finish(tester);
    },
  );

  testWidgets('a scope change hides old backlinks and rejects a captured row', (
    tester,
  ) async {
    await open(tester);
    final target = (await workspace.openPath('/vault/Target.md'))!;
    await tester.pumpAndSettle();
    await backlinks(tester);
    final row = tester.widget<ListTile>(
      find.byKey(const ValueKey('workspace-reference-result-0')),
    );
    workspace.index.configure('/other');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('workspace-reference-result-0')),
      findsNothing,
    );
    expect(
      find.text('Workspace changed. Close and reopen references.'),
      findsOneWidget,
    );
    row.onTap!();
    await tester.pumpAndSettle();
    expect(workspace.activeDocument, same(target));
    expect(find.byKey(const ValueKey('document-find-query')), findsNothing);
    await finish(tester);
  });
  testWidgets(
    'verified non-md path alias indexes only the dirty buffer, not duplicate disk source',
    (tester) async {
      final filesystem = IdentityWikiFiles();
      filesystem.files['/vault/Other.markdown'] = '[old](Target.md)';
      filesystem.aliases['/vault/OTHER.MARKDOWN'] = '/vault/Other.markdown';
      await open(tester, filesystem: filesystem);
      final alias = (await workspace.openPath('/vault/OTHER.MARKDOWN'))!;
      alias.controller.text = '😀 [new](Target.md) #dirty [here](#Heading)';
      await workspace.openPath('/vault/Target.md');
      await tester.pumpAndSettle();
      await backlinks(tester);
      expect(
        workspace.references.snapshot!.backlinks('Target.md'),
        hasLength(2),
      );
      expect(
        workspace.references.snapshot!.notes.containsKey(
          '/vault/Other.markdown',
        ),
        isTrue,
      );
      expect(
        workspace.references.snapshot!.notes.containsKey(
          '/vault/OTHER.MARKDOWN',
        ),
        isFalse,
      );
      final refs = workspace.references.snapshot!
          .backlinks('Target.md')
          .where((edge) => edge.note.source.sessionId == alias.id);
      expect(
        workspace.references.snapshot!.backlinks('Other.markdown'),
        hasLength(1),
      );
      expect(refs, hasLength(1));
      expect(
        refs.single.reference.range.textInside(refs.single.note.source.text),
        '[new](Target.md)',
      );
      expect(
        workspace.references.snapshot!.wikiCandidates.where(
          (candidate) => candidate.relativePath.endsWith('.markdown'),
        ),
        isEmpty,
      );
      await finish(tester);
    },
  );
}
