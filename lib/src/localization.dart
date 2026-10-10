import 'package:flutter/material.dart';

/// Library-owned interface messages. Document text, YAML keys, code language
/// names, and host-provided labels are never translated.
/// Templates accept named arguments such as {index}, {label}, or {count}.
enum IanvsMarkdownMessage {
  calloutNote('笔记', 'Note', legacyEnglish: true),
  calloutAbstract('摘要', 'Abstract', legacyEnglish: true),
  calloutSummary('总结', 'Summary', legacyEnglish: true),
  calloutTldr('简述', 'TL;DR', legacyEnglish: true),
  calloutInfo('信息', 'Info', legacyEnglish: true),
  calloutTodo('待办', 'Todo', legacyEnglish: true),
  calloutTip('提示', 'Tip', legacyEnglish: true),
  calloutHint('提示', 'Hint', legacyEnglish: true),
  calloutImportant('重要', 'Important', legacyEnglish: true),
  calloutSuccess('成功', 'Success', legacyEnglish: true),
  calloutCheck('检查', 'Check', legacyEnglish: true),
  calloutDone('完成', 'Done', legacyEnglish: true),
  calloutQuestion('问题', 'Question', legacyEnglish: true),
  calloutHelp('帮助', 'Help', legacyEnglish: true),
  calloutFaq('常见问题', 'FAQ', legacyEnglish: true),
  calloutWarning('警告', 'Warning', legacyEnglish: true),
  calloutCaution('注意', 'Caution', legacyEnglish: true),
  calloutAttention('留意', 'Attention', legacyEnglish: true),
  calloutFailure('失败', 'Failure', legacyEnglish: true),
  calloutMissing('缺失', 'Missing', legacyEnglish: true),
  calloutDanger('危险', 'Danger', legacyEnglish: true),
  calloutError('错误', 'Error', legacyEnglish: true),
  calloutBug('缺陷', 'Bug', legacyEnglish: true),
  calloutExample('示例', 'Example', legacyEnglish: true),
  calloutQuote('引用', 'Quote', legacyEnglish: true),

  livePreview('实时预览', 'Live preview'),
  sourceMode('源码模式', 'Source mode'),
  readingMode('阅读模式', 'Reading mode'),
  undo('撤销', 'Undo'),
  redo('重做', 'Redo'),
  bold('粗体', 'Bold'),
  italic('斜体', 'Italic'),
  inlineCode('行内代码', 'Inline code'),
  link('链接', 'Link'),
  heading('标题', 'Heading'),
  bulletList('项目列表', 'Bullet list'),
  taskList('任务列表', 'Task list'),
  codeBlock('代码块', 'Code block'),
  save('保存', 'Save'),
  saved('已保存', 'Saved'),
  expandOutline('展开文档大纲', 'Show document outline'),
  collapseOutline('收起文档大纲', 'Hide document outline'),
  documentOutline('文档大纲', 'Document outline'),
  expandHeading('展开标题内容', 'Expand heading'),
  collapseHeading('折叠标题内容', 'Collapse heading'),
  editBlankLine(
    '编辑空白 Markdown 行',
    'Edit blank Markdown line',
    legacyEnglish: true,
  ),
  editBlock('编辑 Markdown 块', 'Edit Markdown block', legacyEnglish: true),
  editableTable(
    '可编辑 Markdown 表格',
    'Editable Markdown table',
    legacyEnglish: true,
  ),
  addColumn('在右侧新增列', 'Add column to the right'),
  addRow('在下方新增行', 'Add row below'),
  dragRow('拖动表格第 {index} 行', 'Drag table row {index}'),
  dragColumn('拖动表格第 {index} 列', 'Drag table column {index}'),
  modeSection('模式', 'MODE', legacyEnglish: true),
  outlineSection('大纲', 'OUTLINE', legacyEnglish: true),
  previewLabel('预览', 'Preview', legacyEnglish: true),
  sourceLabel('源码', 'Source', legacyEnglish: true),
  readLabel('阅读', 'Read', legacyEnglish: true),
  codeTooLarge(
    '代码过大，已回退为纯文本以保持预览流畅',
    'Code is too large; showing plain text to keep the preview responsive',
  ),
  collapseCode('收起', 'Collapse'),
  expandCode('展开', 'Expand'),
  copy('复制', 'Copy'),
  copied('已复制到剪贴板', 'Copied to clipboard'),
  cut('剪切', 'Cut'),
  paste('粘贴', 'Paste'),
  selectAll('全选', 'Select all'),
  delete('删除', 'Delete'),
  liveTextInput('扫描文本', 'Scan text'),
  lookUp('查询', 'Look up'),
  searchWeb('搜索网页', 'Search web'),
  share('共享', 'Share'),
  zoomImage('放大图片', 'Zoom image', legacyEnglish: true),
  editImage('编辑图片块', 'Edit image block', legacyEnglish: true),
  closeImage('关闭图片查看器', 'Close image viewer', legacyEnglish: true),
  image('图片', 'Image', legacyEnglish: true),
  localSource('本地', 'local', legacyEnglish: true),
  imageBlocked(
    '图片已阻止 · {source}',
    'Image blocked · {source}',
    legacyEnglish: true,
  ),
  openEmbed('打开 {label}', 'Open {label}'),
  datePicker('日期选择器', 'Date picker', legacyEnglish: true),
  showDatePicker('显示日期选择器', 'Show date picker', legacyEnglish: true),
  timePicker('时间选择器', 'Time picker', legacyEnglish: true),
  showTimePicker('显示时间选择器', 'Show time picker', legacyEnglish: true),
  editingMetadata(
    'Obsidian {kind} 编辑元数据',
    'Obsidian {kind} editing metadata',
    legacyEnglish: true,
  ),
  properties('笔记属性', 'Note properties'),
  itemCount('{count} 项', '{count} items'),
  collapseMetadata('收起元数据', 'Collapse properties'),
  expandMetadata('展开全部元数据', 'Expand all properties'),
  addProperty('添加笔记属性', 'Add note property'),
  enabled('已启用', 'Enabled'),
  disabled('未启用', 'Disabled'),
  addTag('添加标签', 'Add tag'),
  addAlias('添加别名', 'Add alias'),
  noValue('没有值', 'No value'),
  chooseDate('选择日期', 'Choose date'),
  year('年', 'Year'),
  month('月', 'Month'),
  day('日', 'Day'),
  removeValue('删除 {label}', 'Remove {label}'),
  propertyTitle('标题', 'Title'),
  propertySubtitle('副标题', 'Subtitle'),
  propertySummary('摘要', 'Summary'),
  propertyAuthor('作者', 'Author'),
  propertyDate('日期', 'Date'),
  propertyCreated('创建时间', 'Created'),
  propertyUpdated('更新时间', 'Updated'),
  propertyTags('标签', 'Tags'),
  propertyCategories('分类', 'Categories'),
  propertyStatus('状态', 'Status'),
  propertyDraft('草稿', 'Draft'),
  propertySlug('路径', 'Slug'),
  propertyVersion('版本', 'Version'),
  propertyLanguage('语言', 'Language'),
  taskIncomplete('未完成任务', 'Incomplete task', legacyEnglish: true),
  taskCompleted('已完成任务', 'Completed task', legacyEnglish: true),
  taskInProgress('进行中任务', 'In progress task', legacyEnglish: true),
  taskCancelled('已取消任务', 'Cancelled task', legacyEnglish: true),
  taskForwarded('已转交任务', 'Forwarded task', legacyEnglish: true),
  taskScheduled('已安排任务', 'Scheduled task', legacyEnglish: true),
  taskQuestion('问题任务', 'Question task', legacyEnglish: true),
  taskImportant('重要任务', 'Important task', legacyEnglish: true),
  taskStarred('星标任务', 'Starred task', legacyEnglish: true),
  taskInformation('信息任务', 'Information task', legacyEnglish: true),
  taskIdea('想法任务', 'Idea task', legacyEnglish: true),
  taskLocation('位置任务', 'Location task', legacyEnglish: true),
  taskBookmark('书签任务', 'Bookmark task', legacyEnglish: true),
  taskNote('笔记任务', 'Note task', legacyEnglish: true),
  taskPositive('正面任务', 'Positive task', legacyEnglish: true),
  taskNegative('负面任务', 'Negative task', legacyEnglish: true),
  taskQuote('引用任务', 'Quote task', legacyEnglish: true),
  taskSavings('储蓄任务', 'Savings task', legacyEnglish: true),
  taskUp('向上任务', 'Up task', legacyEnglish: true),
  taskDown('向下任务', 'Down task', legacyEnglish: true),
  taskChecked('已勾选任务 {marker}', 'Checked task {marker}', legacyEnglish: true);

  const IanvsMarkdownMessage(
    this._chinese,
    this._english, {
    this.legacyEnglish = false,
  });
  final String _chinese;
  final String _english;
  final bool legacyEnglish;

  String resolve(
    BuildContext context, {
    Map<String, Object> arguments = const {},
  }) => IanvsMarkdownLocalization.of(context).text(this, arguments: arguments);
}

enum _MessageLanguage { legacy, chinese, english }

/// Immutable message configuration. Supply an immutable [overrides] map and
/// replace this object when changing messages. Missing overrides use the chosen
/// built-in language; legacy preserves the library's pre-0.4 mixed-language UI.
@immutable
class IanvsMarkdownStrings {
  static final _argumentPattern = RegExp(r'\{(\w+)\}');
  const IanvsMarkdownStrings.legacy({this.overrides = const {}})
    : _language = _MessageLanguage.legacy;
  const IanvsMarkdownStrings.chinese({this.overrides = const {}})
    : _language = _MessageLanguage.chinese;
  const IanvsMarkdownStrings.english({this.overrides = const {}})
    : _language = _MessageLanguage.english;

  final _MessageLanguage _language;
  final Map<IanvsMarkdownMessage, String> overrides;

  String text(
    IanvsMarkdownMessage message, {
    Map<String, Object> arguments = const {},
  }) {
    final template =
        overrides[message] ??
        switch (_language) {
          _MessageLanguage.chinese => message._chinese,
          _MessageLanguage.english => message._english,
          _MessageLanguage.legacy =>
            message.legacyEnglish ? message._english : message._chinese,
        };
    if (arguments.isEmpty) return template;
    // Substitute once: braces in document text are data, not nested templates.
    return template.replaceAllMapped(
      _argumentPattern,
      (match) => arguments[match[1]]?.toString() ?? match[0]!,
    );
  }

  String? _selectionLabel(ContextMenuButtonType type) {
    final message = switch (type) {
      ContextMenuButtonType.delete => IanvsMarkdownMessage.delete,
      ContextMenuButtonType.liveTextInput => IanvsMarkdownMessage.liveTextInput,
      ContextMenuButtonType.copy => IanvsMarkdownMessage.copy,
      ContextMenuButtonType.cut => IanvsMarkdownMessage.cut,
      ContextMenuButtonType.paste => IanvsMarkdownMessage.paste,
      ContextMenuButtonType.selectAll => IanvsMarkdownMessage.selectAll,
      ContextMenuButtonType.lookUp => IanvsMarkdownMessage.lookUp,
      ContextMenuButtonType.searchWeb => IanvsMarkdownMessage.searchWeb,
      ContextMenuButtonType.share => IanvsMarkdownMessage.share,
      _ => null,
    };
    if (message == null) return null;
    // Preserve Flutter/host labels unless a language or message was selected.
    if (_language == _MessageLanguage.legacy &&
        !overrides.containsKey(message)) {
      return null;
    }
    return text(message);
  }
}

/// Applies messages to all Markdown components below it, including overlays
/// captured by Flutter's dialog/theme APIs. No global locale state is changed.
class IanvsMarkdownLocalization extends InheritedTheme {
  const IanvsMarkdownLocalization({
    super.key,
    required this.strings,
    required super.child,
  });

  final IanvsMarkdownStrings strings;
  static IanvsMarkdownStrings of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<IanvsMarkdownLocalization>()
          ?.strings ??
      const IanvsMarkdownStrings.legacy();

  @override
  bool updateShouldNotify(IanvsMarkdownLocalization oldWidget) =>
      !identical(strings, oldWidget.strings);

  @override
  Widget wrap(BuildContext context, Widget child) =>
      IanvsMarkdownLocalization(strings: strings, child: child);
}

List<ContextMenuButtonItem> localizeMarkdownContextMenu(
  BuildContext context,
  List<ContextMenuButtonItem> items,
) {
  final strings = IanvsMarkdownLocalization.of(context);
  return [
    for (final item in items)
      if (strings._selectionLabel(item.type) case final label?)
        item.copyWith(label: label)
      else
        item,
  ];
}

Widget buildMarkdownTextContextMenu(
  BuildContext context,
  EditableTextState state,
) {
  final strings = IanvsMarkdownLocalization.of(context);
  final customized = ContextMenuButtonType.values.any(
    (type) => strings._selectionLabel(type) != null,
  );
  if (!customized && SystemContextMenu.isSupportedByField(state)) {
    return SystemContextMenu.editableText(editableTextState: state);
  }
  return buildMarkdownSelectableContextMenu(context, state);
}

Widget buildMarkdownSelectableContextMenu(
  BuildContext context,
  EditableTextState state,
) => AdaptiveTextSelectionToolbar.buttonItems(
  anchors: state.contextMenuAnchors,
  buttonItems: localizeMarkdownContextMenu(
    context,
    state.contextMenuButtonItems,
  ),
);

String localizeMarkdownPropertyLabel(
  BuildContext context,
  String key,
  String fallback,
) {
  final message = switch (key.toLowerCase().replaceAll('-', '_')) {
    'title' => IanvsMarkdownMessage.propertyTitle,
    'subtitle' => IanvsMarkdownMessage.propertySubtitle,
    'description' => IanvsMarkdownMessage.propertySummary,
    'summary' => IanvsMarkdownMessage.propertySummary,
    'author' => IanvsMarkdownMessage.propertyAuthor,
    'authors' => IanvsMarkdownMessage.propertyAuthor,
    'date' => IanvsMarkdownMessage.propertyDate,
    'created' => IanvsMarkdownMessage.propertyCreated,
    'updated' => IanvsMarkdownMessage.propertyUpdated,
    'last_modified' => IanvsMarkdownMessage.propertyUpdated,
    'tags' => IanvsMarkdownMessage.propertyTags,
    'tag' => IanvsMarkdownMessage.propertyTags,
    'categories' => IanvsMarkdownMessage.propertyCategories,
    'category' => IanvsMarkdownMessage.propertyCategories,
    'status' => IanvsMarkdownMessage.propertyStatus,
    'draft' => IanvsMarkdownMessage.propertyDraft,
    'slug' => IanvsMarkdownMessage.propertySlug,
    'version' => IanvsMarkdownMessage.propertyVersion,
    'lang' => IanvsMarkdownMessage.propertyLanguage,
    'language' => IanvsMarkdownMessage.propertyLanguage,
    _ => null,
  };
  return message?.resolve(context) ?? fallback;
}

String localizeMarkdownCalloutTitle(
  BuildContext context,
  String type,
  String fallback,
) {
  final message = switch (type) {
    'note' => IanvsMarkdownMessage.calloutNote,
    'abstract' => IanvsMarkdownMessage.calloutAbstract,
    'summary' => IanvsMarkdownMessage.calloutSummary,
    'tldr' => IanvsMarkdownMessage.calloutTldr,
    'info' => IanvsMarkdownMessage.calloutInfo,
    'todo' => IanvsMarkdownMessage.calloutTodo,
    'tip' => IanvsMarkdownMessage.calloutTip,
    'hint' => IanvsMarkdownMessage.calloutHint,
    'important' => IanvsMarkdownMessage.calloutImportant,
    'success' => IanvsMarkdownMessage.calloutSuccess,
    'check' => IanvsMarkdownMessage.calloutCheck,
    'done' => IanvsMarkdownMessage.calloutDone,
    'question' => IanvsMarkdownMessage.calloutQuestion,
    'help' => IanvsMarkdownMessage.calloutHelp,
    'faq' => IanvsMarkdownMessage.calloutFaq,
    'warning' => IanvsMarkdownMessage.calloutWarning,
    'caution' => IanvsMarkdownMessage.calloutCaution,
    'attention' => IanvsMarkdownMessage.calloutAttention,
    'failure' => IanvsMarkdownMessage.calloutFailure,
    'missing' => IanvsMarkdownMessage.calloutMissing,
    'danger' => IanvsMarkdownMessage.calloutDanger,
    'error' => IanvsMarkdownMessage.calloutError,
    'bug' => IanvsMarkdownMessage.calloutBug,
    'example' => IanvsMarkdownMessage.calloutExample,
    'quote' => IanvsMarkdownMessage.calloutQuote,
    'fail' => IanvsMarkdownMessage.calloutFailure,
    'cite' => IanvsMarkdownMessage.calloutQuote,
    _ => null,
  };
  return message?.resolve(context) ?? fallback;
}
