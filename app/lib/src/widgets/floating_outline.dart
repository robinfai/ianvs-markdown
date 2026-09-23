import 'package:flutter/material.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

import '../models/document_session.dart';
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
                    final headings = _headings(value.text);
                    if (headings.isEmpty) {
                      return Center(
                        child: Padding(
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
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 2, 8, 12),
                      itemCount: headings.length,
                      itemBuilder: (context, index) {
                        final heading = headings[index];
                        final selected = _isSelectedHeading(
                          headings,
                          index,
                          value.selection.extentOffset,
                        );
                        return _OutlineTile(
                          heading: heading,
                          selected: selected,
                          onTap: () =>
                              document.controller.revealHeading(heading.offset),
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

class _OutlineHeading {
  const _OutlineHeading({
    required this.offset,
    required this.level,
    required this.text,
  });

  final int offset;
  final int level;
  final String text;
}

List<_OutlineHeading> _headings(String source) {
  final result = <_OutlineHeading>[];
  for (final block in parseMarkdownBlocks(source)) {
    if (block.type != IanvsMarkdownBlockType.heading) continue;
    final parsed = parseMarkdownHeadings(block.source);
    if (parsed.isEmpty) continue;
    result.add(
      _OutlineHeading(
        offset: block.start,
        level: parsed.first.level,
        text: parsed.first.text,
      ),
    );
  }
  return result;
}

bool _isSelectedHeading(List<_OutlineHeading> headings, int index, int offset) {
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

  final _OutlineHeading heading;
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
