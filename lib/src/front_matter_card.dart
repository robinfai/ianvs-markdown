import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'front_matter.dart';
import 'theme.dart';

const int _collapsedMetadataItems = 6;

typedef IanvsMarkdownMetadataTextChanged =
    void Function(MarkdownMetadataEntry entry, String value);
typedef IanvsMarkdownMetadataBooleanChanged =
    void Function(MarkdownMetadataEntry entry, bool value);
typedef IanvsMarkdownMetadataNumberChanged =
    void Function(MarkdownMetadataEntry entry, num value);
typedef IanvsMarkdownMetadataDateChanged =
    void Function(MarkdownMetadataEntry entry, String value);
typedef IanvsMarkdownMetadataListChanged =
    void Function(MarkdownMetadataEntry entry, List<String> values);
typedef IanvsMarkdownMetadataKeyChanged =
    void Function(MarkdownMetadataEntry entry, String key);

class IanvsMarkdownFrontMatterCard extends StatefulWidget {
  const IanvsMarkdownFrontMatterCard({
    super.key,
    required this.entries,
    this.theme,
    this.title = '笔记属性',
    this.formatLabel = 'YAML',
    this.itemCountLabel,
    this.compact = false,
    this.initiallyExpanded = true,
    this.showDocumentTitle = false,
    this.onTapLink,
    this.onTextChanged,
    this.onBooleanChanged,
    this.onNumberChanged,
    this.onDateChanged,
    this.onListChanged,
    this.onKeyChanged,
  });

  final List<MarkdownMetadataEntry> entries;
  final IanvsMarkdownThemeData? theme;
  final String title;
  final String formatLabel;
  final String Function(int count)? itemCountLabel;
  final bool compact;
  final bool initiallyExpanded;
  final bool showDocumentTitle;
  final MarkdownTapLinkCallback? onTapLink;
  final IanvsMarkdownMetadataTextChanged? onTextChanged;
  final IanvsMarkdownMetadataBooleanChanged? onBooleanChanged;
  final IanvsMarkdownMetadataNumberChanged? onNumberChanged;
  final IanvsMarkdownMetadataDateChanged? onDateChanged;
  final IanvsMarkdownMetadataListChanged? onListChanged;
  final IanvsMarkdownMetadataKeyChanged? onKeyChanged;

  @override
  State<IanvsMarkdownFrontMatterCard> createState() =>
      _IanvsMarkdownFrontMatterCardState();
}

class _IanvsMarkdownFrontMatterCardState
    extends State<IanvsMarkdownFrontMatterCard> {
  var _expanded = false;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  void didUpdateWidget(covariant IanvsMarkdownFrontMatterCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.entries, widget.entries) ||
        oldWidget.compact != widget.compact ||
        oldWidget.initiallyExpanded != widget.initiallyExpanded ||
        oldWidget.showDocumentTitle != widget.showDocumentTitle) {
      _expanded = widget.initiallyExpanded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context, widget.theme);
    if (widget.compact) return _buildCompact(context, colors);
    final canExpand = widget.entries.length > _collapsedMetadataItems;
    final entries = canExpand && !_expanded
        ? widget.entries.take(_collapsedMetadataItems)
        : widget.entries;
    return Container(
      key: const ValueKey('ianvs-markdown-front-matter'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        border: Border.all(color: colors.accentSoft),
        borderRadius: BorderRadius.circular(colors.largeRadius),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.description_outlined,
                size: 17,
                color: colors.accentDark,
              ),
              const SizedBox(width: 8),
              Text(
                widget.title,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.accentSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  widget.formatLabel,
                  style: TextStyle(
                    color: colors.accentDark,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .5,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                widget.itemCountLabel?.call(widget.entries.length) ??
                    '${widget.entries.length} 项',
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (canExpand) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: _expanded ? '收起元数据' : '展开全部元数据',
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 17,
                  ),
                  color: colors.textSecondary,
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
          const SizedBox(height: 9),
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 8.0;
              final twoColumns = constraints.maxWidth >= 500;
              final halfWidth = twoColumns
                  ? (constraints.maxWidth - spacing) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final entry in entries)
                    SizedBox(
                      width: twoColumns && !entry.isLong
                          ? halfWidth
                          : constraints.maxWidth,
                      child: _MetadataEntryTile(entry: entry, colors: colors),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCompact(BuildContext context, IanvsMarkdownThemeData colors) {
    MarkdownMetadataEntry? titleEntry;
    for (final entry in widget.entries) {
      if (entry.key.toLowerCase().replaceAll('-', '_') == 'title') {
        titleEntry = entry;
        break;
      }
    }
    final detailEntries = widget.showDocumentTitle && titleEntry != null
        ? widget.entries
              .where((entry) => !identical(entry, titleEntry))
              .toList()
        : widget.entries;
    final existingKeys = widget.entries.map((entry) => entry.key).toSet();
    return Column(
      key: const ValueKey('ianvs-markdown-front-matter'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showDocumentTitle && titleEntry != null) ...[
          SelectableText(
            titleEntry.value,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 38,
              height: 1.12,
              fontWeight: FontWeight.w700,
              letterSpacing: -.8,
            ),
          ),
          const SizedBox(height: 14),
        ],
        Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('ianvs-markdown-front-matter-toggle'),
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(colors.smallRadius),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _expanded ? .25 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: Icon(
                      Icons.arrow_right_rounded,
                      size: 16,
                      color: colors.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    widget.title,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final entry in detailEntries)
                        _ObsidianMetadataRow(
                          entry: entry,
                          colors: colors,
                          onTapLink: widget.onTapLink,
                          onTextChanged: widget.onTextChanged,
                          onBooleanChanged: widget.onBooleanChanged,
                          onNumberChanged: widget.onNumberChanged,
                          onDateChanged: widget.onDateChanged,
                          onListChanged: widget.onListChanged,
                          onKeyChanged: widget.onKeyChanged,
                          existingKeys: existingKeys,
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(7, 4, 7, 2),
                        child: Row(
                          children: [
                            Icon(
                              Icons.add_rounded,
                              size: 14,
                              color: colors.textTertiary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '添加笔记属性',
                              key: const ValueKey(
                                'ianvs-markdown-front-matter-add-hint',
                              ),
                              style: TextStyle(
                                color: colors.textTertiary,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _ObsidianMetadataRow extends StatelessWidget {
  const _ObsidianMetadataRow({
    required this.entry,
    required this.colors,
    required this.onTapLink,
    required this.onTextChanged,
    required this.onBooleanChanged,
    required this.onNumberChanged,
    required this.onDateChanged,
    required this.onListChanged,
    required this.onKeyChanged,
    required this.existingKeys,
  });

  final MarkdownMetadataEntry entry;
  final IanvsMarkdownThemeData colors;
  final MarkdownTapLinkCallback? onTapLink;
  final IanvsMarkdownMetadataTextChanged? onTextChanged;
  final IanvsMarkdownMetadataBooleanChanged? onBooleanChanged;
  final IanvsMarkdownMetadataNumberChanged? onNumberChanged;
  final IanvsMarkdownMetadataDateChanged? onDateChanged;
  final IanvsMarkdownMetadataListChanged? onListChanged;
  final IanvsMarkdownMetadataKeyChanged? onKeyChanged;
  final Set<String> existingKeys;

  @override
  Widget build(BuildContext context) {
    final normalizedKey = entry.key.toLowerCase().replaceAll('-', '_');
    final items = entry.items;
    return Container(
      key: ValueKey('ianvs-markdown-front-matter-row-${entry.key}'),
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Row(
              children: [
                _MetadataTypeIcon(
                  key: ValueKey(
                    'ianvs-markdown-front-matter-type-${entry.key}',
                  ),
                  icon: _metadataIcon(normalizedKey, entry),
                  number: entry.type == MarkdownMetadataValueType.number,
                  colors: colors,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: entry.keyEditable && onKeyChanged != null
                      ? _ObsidianEditableKey(
                          key: ValueKey(
                            'ianvs-markdown-front-matter-key-editor-${entry.key}',
                          ),
                          entry: entry,
                          colors: colors,
                          existingKeys: existingKeys,
                          onChanged: onKeyChanged!,
                        )
                      : Text(
                          entry.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 11.5,
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ObsidianMetadataValue(
              entry: entry,
              normalizedKey: normalizedKey,
              items: items,
              colors: colors,
              onTapLink: onTapLink,
              onTextChanged: onTextChanged,
              onBooleanChanged: onBooleanChanged,
              onNumberChanged: onNumberChanged,
              onDateChanged: onDateChanged,
              onListChanged: onListChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _ObsidianEditableKey extends StatefulWidget {
  const _ObsidianEditableKey({
    super.key,
    required this.entry,
    required this.colors,
    required this.existingKeys,
    required this.onChanged,
  });

  final MarkdownMetadataEntry entry;
  final IanvsMarkdownThemeData colors;
  final Set<String> existingKeys;
  final IanvsMarkdownMetadataKeyChanged onChanged;

  @override
  State<_ObsidianEditableKey> createState() => _ObsidianEditableKeyState();
}

class _ObsidianEditableKeyState extends State<_ObsidianEditableKey> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late String _committedKey;
  var _cancelled = false;

  @override
  void initState() {
    super.initState();
    _committedKey = widget.entry.key;
    _controller = TextEditingController(text: _committedKey);
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _ObsidianEditableKey oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.key != widget.entry.key) {
      _committedKey = widget.entry.key;
      _restore();
    }
  }

  bool _validKey(String value) {
    return value.isNotEmpty &&
        value.length <= 80 &&
        value.trim() == value &&
        !value.contains('\n') &&
        !value.contains('\r') &&
        !value.codeUnits.any((unit) => unit < 0x20) &&
        (value == _committedKey ||
            !widget.existingKeys.any(
              (key) => key.toLowerCase() == value.toLowerCase(),
            ));
  }

  void _restore() {
    _controller.value = TextEditingValue(
      text: _committedKey,
      selection: TextSelection.collapsed(offset: _committedKey.length),
    );
  }

  void _handleFocusChanged() {
    if (_focusNode.hasFocus) {
      _cancelled = false;
      return;
    }
    if (_cancelled) {
      _cancelled = false;
      return;
    }
    _commit();
  }

  void _commit() {
    final value = _controller.text;
    if (!_validKey(value)) {
      _restore();
      return;
    }
    if (value == _committedKey) return;
    _committedKey = value;
    widget.onChanged(widget.entry, value);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    _cancelled = true;
    _restore();
    node.unfocus();
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: TextField(
        key: ValueKey(
          'ianvs-markdown-front-matter-key-input-${widget.entry.key}',
        ),
        controller: _controller,
        focusNode: _focusNode,
        maxLines: 1,
        textInputAction: TextInputAction.done,
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
        autocorrect: false,
        enableSuggestions: false,
        onSubmitted: (_) {
          _commit();
          _focusNode.unfocus();
        },
        onTapOutside: (_) => _focusNode.unfocus(),
        style: TextStyle(
          color: widget.colors.textSecondary,
          fontSize: 11.5,
          height: 1.35,
          fontWeight: FontWeight.w500,
        ),
        cursorColor: widget.colors.accent,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: widget.colors.accentSoft),
          ),
        ),
      ),
    );
  }
}

class _MetadataTypeIcon extends StatelessWidget {
  const _MetadataTypeIcon({
    super.key,
    required this.icon,
    required this.number,
    required this.colors,
  });

  final IconData icon;
  final bool number;
  final IanvsMarkdownThemeData colors;

  @override
  Widget build(BuildContext context) {
    if (number) {
      return SizedBox(
        width: 13,
        child: Text(
          '01',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.textTertiary,
            fontFamily: colors.monoFontFamily,
            fontFamilyFallback: colors.monoFontFamilyFallback,
            fontSize: 7.5,
            height: 1,
            letterSpacing: -1.1,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return Icon(icon, size: 13, color: colors.textTertiary);
  }
}

class _ObsidianMetadataValue extends StatelessWidget {
  const _ObsidianMetadataValue({
    required this.entry,
    required this.normalizedKey,
    required this.items,
    required this.colors,
    required this.onTapLink,
    required this.onTextChanged,
    required this.onBooleanChanged,
    required this.onNumberChanged,
    required this.onDateChanged,
    required this.onListChanged,
  });

  final MarkdownMetadataEntry entry;
  final String normalizedKey;
  final List<String> items;
  final IanvsMarkdownThemeData colors;
  final MarkdownTapLinkCallback? onTapLink;
  final IanvsMarkdownMetadataTextChanged? onTextChanged;
  final IanvsMarkdownMetadataBooleanChanged? onBooleanChanged;
  final IanvsMarkdownMetadataNumberChanged? onNumberChanged;
  final IanvsMarkdownMetadataDateChanged? onDateChanged;
  final IanvsMarkdownMetadataListChanged? onListChanged;

  @override
  Widget build(BuildContext context) {
    final valueKey = ValueKey('ianvs-markdown-front-matter-value-${entry.key}');
    if (entry.type == MarkdownMetadataValueType.boolean) {
      final checked = entry.value == 'true';
      return Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          checked: checked,
          enabled: onBooleanChanged != null,
          label: '${entry.key}: ${checked ? '已启用' : '未启用'}',
          child: InkWell(
            key: ValueKey('ianvs-markdown-front-matter-boolean-${entry.key}'),
            onTap: onBooleanChanged == null
                ? null
                : () => onBooleanChanged!(entry, !checked),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(
                checked
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                key: valueKey,
                size: 15,
                color: checked ? colors.headingAccent(4) : colors.textTertiary,
              ),
            ),
          ),
        ),
      );
    }
    if (entry.type == MarkdownMetadataValueType.number &&
        onNumberChanged != null) {
      return _ObsidianEditableNumberValue(
        key: ValueKey('ianvs-markdown-front-matter-number-editor-${entry.key}'),
        entry: entry,
        colors: colors,
        onChanged: onNumberChanged!,
      );
    }
    if (entry.type == MarkdownMetadataValueType.date && onDateChanged != null) {
      return _ObsidianEditableDateValue(
        key: ValueKey('ianvs-markdown-front-matter-date-editor-${entry.key}'),
        entry: entry,
        colors: colors,
        onChanged: onDateChanged!,
      );
    }
    if (entry.type == MarkdownMetadataValueType.date) {
      return Row(
        key: valueKey,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: 11.5,
            color: colors.textTertiary,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              _displayMetadataDate(entry.value),
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      );
    }
    final propertyLink = _propertyLink(entry.value);
    if (entry.type == MarkdownMetadataValueType.text &&
        onTextChanged != null &&
        propertyLink == null &&
        !entry.value.contains('\n')) {
      return _ObsidianEditableTextValue(
        key: ValueKey('ianvs-markdown-front-matter-editor-${entry.key}'),
        entry: entry,
        colors: colors,
        onChanged: onTextChanged!,
      );
    }
    if (entry.type == MarkdownMetadataValueType.text && propertyLink != null) {
      return _ObsidianMetadataLink(
        key: valueKey,
        link: propertyLink,
        colors: colors,
        onTapLink: onTapLink,
      );
    }
    final tags = normalizedKey == 'tags' || normalizedKey == 'tag';
    final aliases = normalizedKey == 'aliases' || normalizedKey == 'alias';
    if ((tags || aliases) &&
        entry.listValuesEditable &&
        onListChanged != null) {
      return _ObsidianEditableListValue(
        key: ValueKey('ianvs-markdown-front-matter-list-editor-${entry.key}'),
        entry: entry,
        colors: colors,
        tag: tags,
        hintText: tags ? '添加标签' : '添加别名',
        commitOnSubmitted: tags,
        onChanged: onListChanged!,
      );
    }
    if (items.isNotEmpty) {
      final cssClasses =
          normalizedKey == 'cssclasses' || normalizedKey == 'cssclass';
      if (cssClasses) {
        return Text(
          items.join(', '),
          key: valueKey,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 11.5,
            height: 1.35,
          ),
        );
      }
      return Wrap(
        key: valueKey,
        spacing: 5,
        runSpacing: 4,
        children: [
          for (var index = 0; index < items.length; index += 1)
            _ObsidianMetadataChip(
              key: ValueKey(
                'ianvs-markdown-front-matter-chip-${entry.key}-$index',
              ),
              value: items[index],
              tag: tags,
              linksEnabled: !tags && !aliases,
              colors: colors,
              onTapLink: onTapLink,
            ),
        ],
      );
    }
    final empty =
        entry.type == MarkdownMetadataValueType.empty || entry.value.isEmpty;
    final object = entry.type == MarkdownMetadataValueType.object;
    return Text(
      empty ? '没有值' : entry.value,
      key: valueKey,
      style: TextStyle(
        color: empty
            ? colors.textTertiary
            : object
            ? colors.headingAccent(2)
            : colors.textPrimary,
        fontFamily: object ? colors.monoFontFamily : null,
        fontFamilyFallback: object ? colors.monoFontFamilyFallback : null,
        fontSize: object ? 10.5 : 11.5,
        height: 1.35,
        fontStyle: empty ? FontStyle.italic : FontStyle.normal,
      ),
    );
  }
}

class _ObsidianEditableListValue extends StatefulWidget {
  const _ObsidianEditableListValue({
    super.key,
    required this.entry,
    required this.colors,
    required this.tag,
    required this.hintText,
    required this.commitOnSubmitted,
    required this.onChanged,
  });

  final MarkdownMetadataEntry entry;
  final IanvsMarkdownThemeData colors;
  final bool tag;
  final String hintText;
  final bool commitOnSubmitted;
  final IanvsMarkdownMetadataListChanged onChanged;

  @override
  State<_ObsidianEditableListValue> createState() =>
      _ObsidianEditableListValueState();
}

class _ObsidianEditableListValueState
    extends State<_ObsidianEditableListValue> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late List<String> _items;

  @override
  void initState() {
    super.initState();
    _items = List<String>.of(widget.entry.items);
    _controller = TextEditingController();
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _ObsidianEditableListValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.entry, widget.entry) &&
        !listEquals(_items, widget.entry.items)) {
      _items = List<String>.of(widget.entry.items);
    }
  }

  bool _validItem(String value) {
    return value.isNotEmpty &&
        value.length <= 160 &&
        !value.contains('\n') &&
        !value.contains('\r') &&
        !value.codeUnits.any((unit) => unit < 0x20);
  }

  void _emit(List<String> values) {
    setState(() => _items = values);
    widget.onChanged(widget.entry, List<String>.unmodifiable(values));
  }

  void _commitInput() {
    final value = _controller.text.trim();
    if (!_validItem(value) || _items.length >= 16) return;
    _controller.clear();
    _emit(<String>[..._items, value]);
  }

  void _removeAt(int index) {
    if (index < 0 || index >= _items.length) return;
    final values = List<String>.of(_items)..removeAt(index);
    _emit(values);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _controller.clear();
      node.unfocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      _commitInput();
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      key: ValueKey('ianvs-markdown-front-matter-value-${widget.entry.key}'),
      spacing: 5,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var index = 0; index < _items.length; index += 1)
          _ObsidianMetadataChip(
            key: ValueKey(
              'ianvs-markdown-front-matter-chip-${widget.entry.key}-$index',
            ),
            value: _items[index],
            tag: widget.tag,
            linksEnabled: false,
            colors: widget.colors,
            onTapLink: null,
            removeKey: ValueKey(
              'ianvs-markdown-front-matter-chip-remove-${widget.entry.key}-$index',
            ),
            onRemove: () => _removeAt(index),
          ),
        if (_items.length < 16)
          SizedBox(
            width: 92,
            child: Focus(
              onKeyEvent: _handleKeyEvent,
              child: TextField(
                key: ValueKey(
                  'ianvs-markdown-front-matter-list-input-${widget.entry.key}',
                ),
                controller: _controller,
                focusNode: _focusNode,
                maxLines: 1,
                textInputAction: TextInputAction.done,
                smartDashesType: SmartDashesType.disabled,
                smartQuotesType: SmartQuotesType.disabled,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: widget.commitOnSubmitted
                    ? (_) => _commitInput()
                    : null,
                onTapOutside: (_) => _focusNode.unfocus(),
                style: TextStyle(
                  color: widget.colors.textPrimary,
                  fontSize: 10.5,
                  height: 1.25,
                ),
                cursorColor: widget.colors.accent,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: _items.isEmpty ? widget.hintText : null,
                  hintStyle: TextStyle(
                    color: widget.colors.textTertiary,
                    fontSize: 10.5,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 2),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: widget.colors.accentSoft),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ObsidianEditableDateValue extends StatefulWidget {
  const _ObsidianEditableDateValue({
    super.key,
    required this.entry,
    required this.colors,
    required this.onChanged,
  });

  final MarkdownMetadataEntry entry;
  final IanvsMarkdownThemeData colors;
  final IanvsMarkdownMetadataDateChanged onChanged;

  @override
  State<_ObsidianEditableDateValue> createState() =>
      _ObsidianEditableDateValueState();
}

class _ObsidianEditableDateValueState
    extends State<_ObsidianEditableDateValue> {
  late final TextEditingController _yearController;
  late final TextEditingController _monthController;
  late final TextEditingController _dayController;
  late final FocusNode _yearFocusNode;
  late final FocusNode _monthFocusNode;
  late final FocusNode _dayFocusNode;
  late String _committedValue;

  @override
  void initState() {
    super.initState();
    _committedValue = widget.entry.value;
    _yearController = TextEditingController();
    _monthController = TextEditingController();
    _dayController = TextEditingController();
    _yearFocusNode = FocusNode();
    _monthFocusNode = FocusNode();
    _dayFocusNode = FocusNode();
    _setControllerDate(_committedValue);
  }

  @override
  void didUpdateWidget(covariant _ObsidianEditableDateValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.value != widget.entry.value) {
      _committedValue = widget.entry.value;
      _setControllerDate(_committedValue);
    }
  }

  void _setControllerValue(TextEditingController controller, String value) {
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _setControllerDate(String value) {
    final parts = value.split('-');
    if (parts.length != 3) return;
    _setControllerValue(_yearController, parts[0]);
    _setControllerValue(_monthController, parts[1]);
    _setControllerValue(_dayController, parts[2]);
  }

  DateTime? _pendingDate() {
    final yearText = _yearController.text;
    final monthText = _monthController.text;
    final dayText = _dayController.text;
    if (yearText.length != 4 || monthText.length != 2 || dayText.length != 2) {
      return null;
    }
    final year = int.tryParse(yearText);
    final month = int.tryParse(monthText);
    final day = int.tryParse(dayText);
    if (year == null ||
        month == null ||
        day == null ||
        year < 1 ||
        year > 9999 ||
        month < 1 ||
        month > 12 ||
        day < 1) {
      return null;
    }
    final date = DateTime.utc(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }

  String _serializeDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  void _commit() {
    final date = _pendingDate();
    if (date == null) return;
    final value = _serializeDate(date);
    if (value == _committedValue) return;
    _committedValue = value;
    widget.onChanged(widget.entry, value);
  }

  void _submit() {
    _commit();
    _yearFocusNode.unfocus();
    _monthFocusNode.unfocus();
    _dayFocusNode.unfocus();
  }

  Future<void> _showDatePicker() async {
    final committed = DateTime.tryParse(_committedValue);
    final initial = _pendingDate() ?? committed ?? DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
    );
    if (!mounted || selected == null) return;
    _setControllerDate(_serializeDate(selected));
    _dayFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _yearController.dispose();
    _monthController.dispose();
    _dayController.dispose();
    _yearFocusNode.dispose();
    _monthFocusNode.dispose();
    _dayFocusNode.dispose();
    super.dispose();
  }

  Widget _segment({
    required String label,
    required String keySuffix,
    required double width,
    required int maximumLength,
    required TextEditingController controller,
    required FocusNode focusNode,
  }) {
    return Semantics(
      label: '${widget.entry.key} $label',
      child: SizedBox(
        width: width,
        child: TextField(
          key: ValueKey(
            'ianvs-markdown-front-matter-date-$keySuffix-${widget.entry.key}',
          ),
          controller: controller,
          focusNode: focusNode,
          maxLines: 1,
          maxLength: maximumLength,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          textAlign: TextAlign.center,
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
          autocorrect: false,
          enableSuggestions: false,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (_) => _submit(),
          style: TextStyle(
            color: widget.colors.textPrimary,
            fontSize: 11.5,
            height: 1.35,
          ),
          cursorColor: widget.colors.accent,
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(vertical: 2),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: widget.colors.accentSoft),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final separatorStyle = TextStyle(
      color: widget.colors.textTertiary,
      fontSize: 11.5,
      height: 1.35,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: ValueKey(
            'ianvs-markdown-front-matter-date-picker-${widget.entry.key}',
          ),
          onPressed: _showDatePicker,
          tooltip: '选择日期',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 20, height: 20),
          icon: Icon(
            Icons.calendar_today_outlined,
            size: 11.5,
            color: widget.colors.textTertiary,
          ),
        ),
        const SizedBox(width: 3),
        _segment(
          label: '年',
          keySuffix: 'year',
          width: 34,
          maximumLength: 4,
          controller: _yearController,
          focusNode: _yearFocusNode,
        ),
        Text(' / ', style: separatorStyle),
        _segment(
          label: '月',
          keySuffix: 'month',
          width: 20,
          maximumLength: 2,
          controller: _monthController,
          focusNode: _monthFocusNode,
        ),
        Text(' / ', style: separatorStyle),
        _segment(
          label: '日',
          keySuffix: 'day',
          width: 20,
          maximumLength: 2,
          controller: _dayController,
          focusNode: _dayFocusNode,
        ),
      ],
    );
  }
}

class _ObsidianEditableNumberValue extends StatefulWidget {
  const _ObsidianEditableNumberValue({
    super.key,
    required this.entry,
    required this.colors,
    required this.onChanged,
  });

  final MarkdownMetadataEntry entry;
  final IanvsMarkdownThemeData colors;
  final IanvsMarkdownMetadataNumberChanged onChanged;

  @override
  State<_ObsidianEditableNumberValue> createState() =>
      _ObsidianEditableNumberValueState();
}

class _ObsidianEditableNumberValueState
    extends State<_ObsidianEditableNumberValue> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late String _committedValue;
  var _cancelled = false;

  @override
  void initState() {
    super.initState();
    _committedValue = widget.entry.value;
    _controller = TextEditingController(text: _committedValue);
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _ObsidianEditableNumberValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.value != widget.entry.value) {
      _committedValue = widget.entry.value;
      _setControllerText(_committedValue);
    }
  }

  void _handleFocusChanged() {
    if (_focusNode.hasFocus) {
      _cancelled = false;
      return;
    }
    if (_cancelled) {
      _cancelled = false;
      return;
    }
    _commit();
  }

  num? _finiteNumber(String source) {
    final value = num.tryParse(source.trim());
    return value != null && value.isFinite ? value : null;
  }

  void _setControllerText(String value) {
    _controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _restore() => _setControllerText(_committedValue);

  void _commit() {
    final value = _finiteNumber(_controller.text);
    if (value == null) {
      _restore();
      return;
    }
    _commitValue(value);
  }

  void _commitValue(num value) {
    if (!value.isFinite) {
      _restore();
      return;
    }
    final serialized = '$value';
    _setControllerText(serialized);
    if (serialized == _committedValue) return;
    _committedValue = serialized;
    widget.onChanged(widget.entry, value);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    _cancelled = true;
    _restore();
    node.unfocus();
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: TextField(
        key: ValueKey(
          'ianvs-markdown-front-matter-number-input-${widget.entry.key}',
        ),
        controller: _controller,
        focusNode: _focusNode,
        maxLines: 1,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        textInputAction: TextInputAction.done,
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
        autocorrect: false,
        enableSuggestions: false,
        onSubmitted: (_) {
          _commit();
          _focusNode.unfocus();
        },
        onTapOutside: (_) => _focusNode.unfocus(),
        style: TextStyle(
          color: widget.colors.textPrimary,
          fontSize: 11.5,
          height: 1.35,
        ),
        cursorColor: widget.colors.accent,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 2),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: widget.colors.accentSoft),
          ),
        ),
      ),
    );
  }
}

class _ObsidianEditableTextValue extends StatefulWidget {
  const _ObsidianEditableTextValue({
    super.key,
    required this.entry,
    required this.colors,
    required this.onChanged,
  });

  final MarkdownMetadataEntry entry;
  final IanvsMarkdownThemeData colors;
  final IanvsMarkdownMetadataTextChanged onChanged;

  @override
  State<_ObsidianEditableTextValue> createState() =>
      _ObsidianEditableTextValueState();
}

class _ObsidianEditableTextValueState
    extends State<_ObsidianEditableTextValue> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late String _committedValue;
  var _cancelled = false;

  @override
  void initState() {
    super.initState();
    _committedValue = widget.entry.value;
    _controller = TextEditingController(text: _committedValue);
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _ObsidianEditableTextValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.value != widget.entry.value) {
      _committedValue = widget.entry.value;
      _controller.value = TextEditingValue(
        text: _committedValue,
        selection: TextSelection.collapsed(offset: _committedValue.length),
      );
    }
  }

  void _handleFocusChanged() {
    if (_focusNode.hasFocus) {
      _cancelled = false;
      return;
    }
    if (_cancelled) {
      _cancelled = false;
      return;
    }
    _commit();
  }

  void _commit() {
    final value = _controller.text;
    if (value == _committedValue) return;
    _committedValue = value;
    widget.onChanged(widget.entry, value);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    _cancelled = true;
    _controller.value = TextEditingValue(
      text: _committedValue,
      selection: TextSelection.collapsed(offset: _committedValue.length),
    );
    node.unfocus();
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: TextField(
        key: ValueKey('ianvs-markdown-front-matter-input-${widget.entry.key}'),
        controller: _controller,
        focusNode: _focusNode,
        maxLines: 1,
        keyboardType: TextInputType.text,
        textInputAction: TextInputAction.done,
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
        autocorrect: false,
        enableSuggestions: false,
        onSubmitted: (_) {
          _commit();
          _focusNode.unfocus();
        },
        onTapOutside: (_) => _focusNode.unfocus(),
        style: TextStyle(
          color: widget.colors.textPrimary,
          fontSize: 11.5,
          height: 1.35,
        ),
        cursorColor: widget.colors.accent,
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.entry.value.isEmpty ? '没有值' : null,
          hintStyle: TextStyle(
            color: widget.colors.textTertiary,
            fontSize: 11.5,
            fontStyle: FontStyle.italic,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 2),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: widget.colors.accentSoft),
          ),
        ),
      ),
    );
  }
}

class _ObsidianMetadataChip extends StatelessWidget {
  const _ObsidianMetadataChip({
    super.key,
    required this.value,
    required this.tag,
    required this.linksEnabled,
    required this.colors,
    required this.onTapLink,
    this.removeKey,
    this.onRemove,
  });

  final String value;
  final bool tag;
  final bool linksEnabled;
  final IanvsMarkdownThemeData colors;
  final MarkdownTapLinkCallback? onTapLink;
  final Key? removeKey;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final link = linksEnabled ? _propertyLink(value) : null;
    final label = link?.label ?? value;
    final linked = link != null;
    return Semantics(
      link: linked,
      enabled: linked ? onTapLink != null : null,
      label: label,
      child: InkWell(
        onTap: linked && onTapLink != null
            ? () => onTapLink!(link.label, link.href, '')
            : null,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: tag ? 7 : 0, vertical: 2),
          decoration: BoxDecoration(
            color: tag ? colors.accentMist : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: tag || linked ? colors.accentDark : colors.textPrimary,
                  fontSize: 10.5,
                  height: 1.25,
                  fontWeight: FontWeight.w500,
                  decoration: linked
                      ? TextDecoration.underline
                      : TextDecoration.none,
                  decorationColor: colors.accentDark,
                ),
              ),
              if (onRemove == null)
                Text(
                  ' ×',
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 9.5,
                    height: 1.25,
                  ),
                )
              else
                Semantics(
                  button: true,
                  label: '删除 $label',
                  child: InkWell(
                    key: removeKey,
                    onTap: onRemove,
                    borderRadius: BorderRadius.circular(3),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 3),
                      child: Text(
                        '×',
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 9.5,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ObsidianMetadataLink extends StatelessWidget {
  const _ObsidianMetadataLink({
    super.key,
    required this.link,
    required this.colors,
    required this.onTapLink,
  });

  final _PropertyLink link;
  final IanvsMarkdownThemeData colors;
  final MarkdownTapLinkCallback? onTapLink;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        link: true,
        enabled: onTapLink != null,
        label: link.label,
        child: InkWell(
          onTap: onTapLink == null
              ? null
              : () => onTapLink!(link.label, link.href, ''),
          borderRadius: BorderRadius.circular(3),
          child: Text(
            link.label,
            style: TextStyle(
              color: colors.accentDark,
              fontSize: 11.5,
              height: 1.35,
              decoration: TextDecoration.underline,
              decorationColor: colors.accentDark,
            ),
          ),
        ),
      ),
    );
  }
}

IconData _metadataIcon(String key, MarkdownMetadataEntry entry) {
  if (key == 'aliases' || key == 'alias') return Icons.redo_rounded;
  if (key == 'tags' || key == 'tag') return Icons.sell_outlined;
  return switch (entry.type) {
    MarkdownMetadataValueType.boolean => Icons.check_box_outlined,
    MarkdownMetadataValueType.number => Icons.numbers_rounded,
    MarkdownMetadataValueType.date => Icons.calendar_today_outlined,
    MarkdownMetadataValueType.list => Icons.format_list_bulleted_rounded,
    MarkdownMetadataValueType.object => Icons.help_outline_rounded,
    MarkdownMetadataValueType.text ||
    MarkdownMetadataValueType.empty => Icons.drag_handle_rounded,
  };
}

String _displayMetadataDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return value;
  return '${match.group(1)} / ${match.group(2)} / ${match.group(3)}';
}

final class _PropertyLink {
  const _PropertyLink({required this.label, required this.href});

  final String label;
  final String href;
}

_PropertyLink? _propertyLink(String value) {
  final wiki = _propertyWikiLink(value);
  if (wiki != null) return wiki;
  final uri = Uri.tryParse(value);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  return _PropertyLink(label: value, href: value);
}

_PropertyLink? _propertyWikiLink(String value) {
  if (!value.startsWith('[[') || !value.endsWith(']]')) return null;
  final source = value.substring(2, value.length - 2);
  final separator = source.indexOf('|');
  final target = (separator < 0 ? source : source.substring(0, separator))
      .trim();
  if (target.isEmpty) return null;
  String label;
  if (separator >= 0) {
    final alias = source.substring(separator + 1).trim();
    if (alias.isNotEmpty) {
      label = alias;
      return _PropertyLink(label: label, href: target);
    }
  }
  final hash = target.indexOf('#');
  if (hash < 0 || hash == target.length - 1) {
    return _PropertyLink(label: target, href: target);
  }
  final note = target.substring(0, hash).trim();
  final subpath = target.substring(hash + 1).trim();
  label = note.isEmpty ? subpath : '$note > $subpath';
  return _PropertyLink(label: label, href: target);
}

class _MetadataEntryTile extends StatelessWidget {
  const _MetadataEntryTile({required this.entry, required this.colors});

  final MarkdownMetadataEntry entry;
  final IanvsMarkdownThemeData colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: .82),
        border: Border.all(color: colors.borderSoft),
        borderRadius: BorderRadius.circular(colors.mediumRadius),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          if (entry.items.length > 1)
            Wrap(
              spacing: 5,
              runSpacing: 4,
              children: [
                for (final item in entry.items.take(12))
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colors.accentMist,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      item,
                      style: TextStyle(
                        color: colors.accentDark,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            )
          else
            SelectableText(
              entry.value,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 11.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}
