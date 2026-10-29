import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/outline_operations.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

import '../models/document_session.dart';
import '../models/document_analysis.dart';
import '../desktop_theme.dart';
import '../desktop_typography.dart';
import '../app_icons.dart';

class FloatingOutline extends StatelessWidget {
  const FloatingOutline({super.key, required this.document});

  final DocumentSession document;

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context);
    return SizedBox(
      width: DesktopMetrics.inspectorWidth,
      child: Material(
        color: colors.surfaceMuted,
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: colors.borderSoft)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 7, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Outline',
                        style: DesktopTypography.sectionLabel.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: document.controller,
                  builder: (context, value, _) {
                    final headings = document.analysis.headings(value.text);
                    if (headings.isEmpty) {
                      return Center(
                        child: SingleChildScrollView(
                          key: const ValueKey('empty-outline-scroll'),
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                AppIcons.outline,
                                size: 26,
                                color: colors.textTertiary,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'No Headings',
                                style: DesktopTypography.emphasizedBody
                                    .copyWith(color: colors.textSecondary),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'Add headings to navigate your document.',
                                textAlign: TextAlign.center,
                                style: DesktopTypography.callout.copyWith(
                                  color: colors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      onReorder: (oldIndex, newIndex) => applyOutlineEdit(
                        document.controller,
                        value.text,
                        moveChapter(value.text, oldIndex, newIndex),
                      ),
                      padding: const EdgeInsets.fromLTRB(8, 2, 8, 12),
                      itemCount: headings.length,
                      itemBuilder: (context, index) {
                        final heading = headings[index];
                        final selected = _isSelectedHeading(
                          headings,
                          index,
                          value.selection.extentOffset,
                        );
                        return Row(
                          key: ValueKey('outline-${heading.offset}'),
                          children: [
                            ReorderableDragStartListener(
                              index: index,
                              child: const Icon(Icons.drag_indicator, size: 14),
                            ),
                            Expanded(
                              child: _OutlineTile(
                                heading: heading,
                                selected: selected,
                                onTap: () => document.controller.revealHeading(
                                  heading.offset,
                                ),
                              ),
                            ),
                            PopupMenuButton<String>(
                              tooltip: 'Chapter actions',
                              iconSize: 14,
                              onSelected: (action) {
                                if (action == 'copy') {
                                  final target = Uri(
                                    path: document.path ?? document.name,
                                    fragment: chapterLinkFragment(headings, index),
                                  );
                                  Clipboard.setData(
                                    ClipboardData(text: '[Chapter](<$target>)'),
                                  );
                                } else {
                                  applyOutlineEdit(
                                    document.controller,
                                    value.text,
                                    changeChapterLevel(
                                      value.text,
                                      index,
                                      action == 'promote' ? -1 : 1,
                                    ),
                                  );
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'promote',
                                  child: Text('Promote chapter'),
                                ),
                                PopupMenuItem(
                                  value: 'demote',
                                  child: Text('Demote chapter'),
                                ),
                                PopupMenuItem(
                                  value: 'copy',
                                  child: Text('Copy chapter link'),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _isSelectedHeading(List<DocumentHeading> headings, int index, int offset) {
  final current = headings[index];
  final next = index + 1 < headings.length ? headings[index + 1] : null;
  return offset >= current.offset && (next == null || offset < next.offset);
}

class _OutlineTile extends StatelessWidget {
  const _OutlineTile({
    required this.heading,
    required this.selected,
    required this.onTap,
  });

  final DocumentHeading heading;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected ? colors.surfaceHover : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              8 + (heading.level - 1).clamp(0, 4) * 12,
              6,
              8,
              6,
            ),
            child: Text(
              heading.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DesktopTypography.body.copyWith(
                color: selected ? colors.textPrimary : colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
