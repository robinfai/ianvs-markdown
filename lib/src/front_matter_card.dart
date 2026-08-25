import 'package:flutter/material.dart';

import 'front_matter.dart';
import 'theme.dart';

const int _collapsedMetadataItems = 6;

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
  });

  final List<MarkdownMetadataEntry> entries;
  final IanvsMarkdownThemeData? theme;
  final String title;
  final String formatLabel;
  final String Function(int count)? itemCountLabel;
  final bool compact;
  final bool initiallyExpanded;
  final bool showDocumentTitle;

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
                        _ObsidianMetadataRow(entry: entry, colors: colors),
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
  const _ObsidianMetadataRow({required this.entry, required this.colors});

  final MarkdownMetadataEntry entry;
  final IanvsMarkdownThemeData colors;

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
                  child: Text(
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
            ),
          ),
        ],
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
  });

  final MarkdownMetadataEntry entry;
  final String normalizedKey;
  final List<String> items;
  final IanvsMarkdownThemeData colors;

  @override
  Widget build(BuildContext context) {
    final valueKey = ValueKey('ianvs-markdown-front-matter-value-${entry.key}');
    if (entry.type == MarkdownMetadataValueType.boolean) {
      final checked = entry.value == 'true';
      return Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          checked: checked,
          label: '${entry.key}: ${checked ? '已启用' : '未启用'}',
          child: Icon(
            checked
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            key: valueKey,
            size: 15,
            color: checked ? colors.headingAccent(4) : colors.textTertiary,
          ),
        ),
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
    if (items.isNotEmpty) {
      final tags = normalizedKey == 'tags' || normalizedKey == 'tag';
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
              colors: colors,
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

class _ObsidianMetadataChip extends StatelessWidget {
  const _ObsidianMetadataChip({
    super.key,
    required this.value,
    required this.tag,
    required this.colors,
  });

  final String value;
  final bool tag;
  final IanvsMarkdownThemeData colors;

  @override
  Widget build(BuildContext context) {
    final wikiLabel = _propertyWikiLabel(value);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: tag ? 7 : 0, vertical: 2),
      decoration: BoxDecoration(
        color: tag ? colors.accentMist : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            wikiLabel ?? value,
            style: TextStyle(
              color: tag || wikiLabel != null
                  ? colors.accentDark
                  : colors.textPrimary,
              fontSize: 10.5,
              height: 1.25,
              fontWeight: FontWeight.w500,
              decoration: wikiLabel == null
                  ? TextDecoration.none
                  : TextDecoration.underline,
              decorationColor: colors.accentDark,
            ),
          ),
          Text(
            ' ×',
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 9.5,
              height: 1.25,
            ),
          ),
        ],
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

String? _propertyWikiLabel(String value) {
  if (!value.startsWith('[[') || !value.endsWith(']]')) return null;
  final source = value.substring(2, value.length - 2);
  final separator = source.indexOf('|');
  final target = (separator < 0 ? source : source.substring(0, separator))
      .trim();
  if (target.isEmpty) return null;
  if (separator >= 0) {
    final alias = source.substring(separator + 1).trim();
    if (alias.isNotEmpty) return alias;
  }
  final hash = target.indexOf('#');
  if (hash < 0 || hash == target.length - 1) return target;
  final note = target.substring(0, hash).trim();
  final subpath = target.substring(hash + 1).trim();
  return note.isEmpty ? subpath : '$note > $subpath';
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
