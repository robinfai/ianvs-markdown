import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

Widget host(Widget child, IanvsMarkdownStrings strings) => MaterialApp(
  home: Scaffold(
    body: IanvsMarkdownLocalization(strings: strings, child: child),
  ),
);

void main() {
  test(
    'template arguments remain data even when they contain placeholders',
    () {
      const strings = IanvsMarkdownStrings.english(
        overrides: {IanvsMarkdownMessage.openEmbed: 'Open «{label}»'},
      );
      expect(
        strings.text(
          IanvsMarkdownMessage.openEmbed,
          arguments: {'label': '{label} <笔记>'},
        ),
        'Open «{label} <笔记>»',
      );
    },
  );

  for (final live in [false, true]) {
    testWidgets('${live ? 'Live' : 'Source'} updates scoped toolbar labels', (
      tester,
    ) async {
      final controller = IanvsMarkdownController(text: 'Original text');
      addTearDown(controller.dispose);
      final editor = live
          ? IanvsMarkdownLiveEditor(controller: controller)
          : IanvsMarkdownEditor(controller: controller);
      await tester.pumpWidget(
        host(editor, const IanvsMarkdownStrings.legacy()),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('粗体'), findsOneWidget);
      await tester.pumpWidget(
        host(editor, const IanvsMarkdownStrings.english()),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Bold'), findsOneWidget);
      expect(find.byTooltip('粗体'), findsNothing);
      expect(find.byTooltip('Source mode'), findsOneWidget);
      expect(controller.text, 'Original text');
      expect(controller.canUndo, isFalse);
      await tester.pumpWidget(
        host(editor, const IanvsMarkdownStrings.chinese()),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('粗体'), findsOneWidget);
    });
  }

  testWidgets(
    'View localizes outline and heading controls without changing data',
    (tester) async {
      const source = '# 标题\n\nOriginal content.';
      const view = IanvsMarkdownView(data: source, enableHeadingFolding: true);
      await tester.pumpWidget(host(view, const IanvsMarkdownStrings.english()));
      await tester.pumpAndSettle();
      expect(find.text('Document outline'), findsOneWidget);
      expect(find.byTooltip('Hide document outline'), findsOneWidget);
      expect(find.byTooltip('Collapse heading'), findsOneWidget);
      await tester.tap(find.byTooltip('Collapse heading'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Expand heading'), findsOneWidget);
      expect(
        tester.widget<IanvsMarkdownView>(find.byType(IanvsMarkdownView)).data,
        source,
      );
    },
  );

  testWidgets(
    'body messages localize generated text and preserve authored titles',
    (tester) async {
      const body = IanvsMarkdown(
        data:
            '> [!note]\n> Body\n\n> [!note] Note\n> Custom title\n\n![Alt](local.png)',
      );
      await tester.pumpWidget(host(body, const IanvsMarkdownStrings.chinese()));
      await tester.pumpAndSettle();
      final callouts = tester.widgetList<IanvsMarkdownCallout>(
        find.byType(IanvsMarkdownCallout),
      );
      expect(callouts.map((callout) => callout.title), ['笔记', 'Note']);
      expect(find.text('图片已阻止 · 本地\nAlt'), findsOneWidget);
      await tester.pumpWidget(host(body, const IanvsMarkdownStrings.english()));
      await tester.pumpAndSettle();
      expect(find.text('Image blocked · local\nAlt'), findsOneWidget);
    },
  );

  testWidgets('metadata localizes only parser-owned labels and omitted title', (
    tester,
  ) async {
    final entries = parseMarkdownFrontMatter(
      '---\nauthor: Alice\n---\n',
    ).entries;
    Widget card({String? title}) => IanvsMarkdownFrontMatterCard(
      title: title,
      entries: [
        ...entries,
        const MarkdownMetadataEntry(
          key: 'title',
          label: '标题',
          value: 'User value',
        ),
      ],
    );
    await tester.pumpWidget(host(card(), const IanvsMarkdownStrings.english()));
    await tester.pumpAndSettle();
    expect(find.text('Note properties'), findsOneWidget);
    expect(find.text('Author'), findsOneWidget);
    expect(find.text('标题'), findsOneWidget);
    expect(find.text('2 items'), findsOneWidget);
    await tester.pumpWidget(
      host(card(title: '笔记属性'), const IanvsMarkdownStrings.english()),
    );
    await tester.pumpAndSettle();
    expect(find.text('笔记属性'), findsOneWidget);
    expect(find.text('Note properties'), findsNothing);
    expect(entries.single.label, '作者');
  });

  testWidgets(
    'nested scope overrides semantics and table controls independently',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = IanvsMarkdownController(
        text: '| A | B |\n| --- | --- |\n| C | D |',
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(
          Column(
            children: [
              const IanvsMarkdownTaskCheckbox(value: false),
              Expanded(
                child: IanvsMarkdownLocalization(
                  strings: const IanvsMarkdownStrings.english(
                    overrides: {
                      IanvsMarkdownMessage.addRow: 'Append a record',
                      IanvsMarkdownMessage.editableTable: 'Host data table',
                    },
                  ),
                  child: IanvsMarkdownLiveEditor(
                    controller: controller,
                    showToolbar: false,
                  ),
                ),
              ),
            ],
          ),
          const IanvsMarkdownStrings.chinese(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('未完成任务'), findsOneWidget);
      expect(find.bySemanticsLabel('Host data table'), findsOneWidget);
      expect(find.byTooltip('Append a record'), findsOneWidget);
      expect(find.byTooltip('Add column to the right'), findsOneWidget);
      await tester.tap(find.byTooltip('Append a record'));
      await tester.pumpAndSettle();
      expect(controller.isDirty, isTrue);
      controller.undo();
      await tester.pumpAndSettle();
      expect(controller.text, '| A | B |\n| --- | --- |\n| C | D |');
      semantics.dispose();
    },
  );

  testWidgets('custom selection menu labels retain actual copy callback', (
    tester,
  ) async {
    final controller = IanvsMarkdownController(text: 'Copy me');
    addTearDown(controller.dispose);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        if (call.method == 'Clipboard.hasStrings') return {'value': false};
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      host(
        IanvsMarkdownEditor(
          controller: controller,
          showToolbar: false,
          autofocus: true,
        ),
        const IanvsMarkdownStrings.english(
          overrides: {IanvsMarkdownMessage.copy: 'Copy source'},
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 7);
    await tester.pump();
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    editable.toggleToolbar();
    await tester.pumpAndSettle();
    expect(find.text('Copy source'), findsOneWidget);
    await tester.tap(find.text('Copy source'));
    await tester.pumpAndSettle();
    expect(controller.text, 'Copy me');
    expect(controller.isDirty, isFalse);
    expect(copied, 'Copy me');
    expect(find.text('Copy source'), findsNothing);
  });

  testWidgets('image dialog retains a nested message scope outside the body', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        IanvsMarkdownInteractiveImage(
          openViewerOnTap: true,
          expandedImageBuilder: (_) => const SizedBox(width: 80, height: 80),
          child: const SizedBox(
            width: 80,
            height: 80,
            child: ColoredBox(color: Colors.blue),
          ),
        ),
        const IanvsMarkdownStrings.english(
          overrides: {IanvsMarkdownMessage.closeImage: 'Dismiss photo'},
        ),
      ),
    );
    await tester.tap(find.byType(IanvsMarkdownInteractiveImage));
    await tester.pumpAndSettle();
    expect(find.text('Image'), findsOneWidget);
    expect(find.byTooltip('Dismiss photo'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss photo'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('ianvs-markdown-image-viewer')),
      findsNothing,
    );
  });

  testWidgets(
    'localized code copy preserves the exact code and host callback',
    (tester) async {
      String? copied;
      await tester.pumpWidget(
        host(
          IanvsMarkdownCodeFlair(
            source: '  exact\nsource  ',
            language: 'dart',
            onCopyCode: (source) => copied = source,
          ),
          const IanvsMarkdownStrings.chinese(
            overrides: {IanvsMarkdownMessage.copy: '拷贝代码'},
          ),
        ),
      );
      expect(find.byTooltip('拷贝代码'), findsOneWidget);
      expect(find.text('Dart'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ianvs-markdown-code-flair')));
      await tester.pumpAndSettle();
      expect(copied, '  exact\nsource  ');
    },
  );

  testWidgets('table selection overlay retains owner messages and copy', (
    tester,
  ) async {
    const source = '| Original | B |\n| --- | --- |\n| C | D |';
    final controller = IanvsMarkdownController(text: source);
    addTearDown(controller.dispose);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        if (call.method == 'Clipboard.hasStrings') return {'value': false};
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      host(
        IanvsMarkdownLiveEditor(controller: controller, showToolbar: false),
        const IanvsMarkdownStrings.english(
          overrides: {IanvsMarkdownMessage.copy: 'Copy cell'},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final cell = find.byKey(const ValueKey('ianvs-markdown-table-0-0'));
    await tester.tap(cell);
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(cell);
    field.controller!.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 8,
    );
    await tester.pump();
    tester
        .state<EditableTextState>(
          find.descendant(of: cell, matching: find.byType(EditableText)),
        )
        .toggleToolbar();
    await tester.pumpAndSettle();
    expect(find.text('Copy cell'), findsOneWidget);
    await tester.tap(find.text('Copy cell'));
    await tester.pumpAndSettle();
    expect(copied, 'Original');
    expect(controller.text, source);
    expect(controller.isDirty, isFalse);
  });

  for (final heading in [false, true]) {
    testWidgets(
      '${heading ? 'Body heading' : 'Live indented code'} menu uses owner messages',
      (tester) async {
        final controller = IanvsMarkdownController(text: '    Original');
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          host(
            heading
                ? const IanvsMarkdown(
                    data: '# Original\n\nBody',
                    documentSelection: false,
                  )
                : IanvsMarkdownLiveEditor(
                    controller: controller,
                    showToolbar: false,
                  ),
            const IanvsMarkdownStrings.english(
              overrides: {IanvsMarkdownMessage.copy: 'Copy selected source'},
            ),
          ),
        );
        await tester.pumpAndSettle();
        final text = find.byWidgetPredicate(
          (widget) => widget is SelectableText && widget.data == 'Original',
        );
        expect(text, findsOneWidget);
        final editable = tester.state<EditableTextState>(
          find.descendant(of: text, matching: find.byType(EditableText)),
        );
        editable.selectAll(SelectionChangedCause.keyboard);
        await tester.pump();
        editable.toggleToolbar();
        await tester.pumpAndSettle();
        expect(find.text('Copy selected source'), findsOneWidget);
        expect(controller.text, '    Original');
        expect(controller.isDirty, isFalse);
      },
    );
  }

  for (final view in [false, true]) {
    testWidgets(
      '${view ? 'View' : 'body'} selection overlay uses owner messages',
      (tester) async {
        IanvsMarkdownClipboardData? copied;
        Future<void> write(IanvsMarkdownClipboardData data) async =>
            copied = data;
        await tester.pumpWidget(
          host(
            view
                ? IanvsMarkdownView(data: 'Original', clipboardWriter: write)
                : IanvsMarkdown(data: 'Original', clipboardWriter: write),
            const IanvsMarkdownStrings.english(
              overrides: {IanvsMarkdownMessage.copy: 'Copy document'},
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.longPress(find.text('Original'));
        await tester.pumpAndSettle();
        expect(find.text('Copy document'), findsOneWidget);
        await tester.tap(find.text('Copy document'));
        await tester.pumpAndSettle();
        expect(copied?.markdown, 'Original');
        expect(copied?.html, contains('Original'));
      },
    );
  }
}
