import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'inline_code.dart';
import 'theme.dart';

typedef IanvsMarkdownWikiLinkExists = bool Function(String target);

const _obsidianCurrentNoteHref = 'app://obsidian.md/index.html';

class IanvsMarkdownInlineLinkBuilder extends MarkdownElementBuilder {
  IanvsMarkdownInlineLinkBuilder({
    required this.onTapLink,
    this.onTapAutolink,
    required this.enableFileLinkChips,
    this.wikiLinkExists,
    this.theme,
  });

  final MarkdownTapLinkCallback? onTapLink;
  final MarkdownTapLinkCallback? onTapAutolink;
  final bool enableFileLinkChips;
  final IanvsMarkdownWikiLinkExists? wikiLinkExists;
  final IanvsMarkdownThemeData? theme;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final label = element.textContent.trim();
    final sourceHref = element.attributes['href'];
    final wikiLink = element.attributes['data-ianvs-wiki-link'] == 'true';
    final tagLink = element.attributes['data-ianvs-tag'] == 'true';
    final autolink = element.attributes['data-ianvs-autolink'] == 'true';
    // `<www.example.com>` is not a valid angle autolink. The Obsidian parser
    // intentionally renders it as a literal `<` plus the bare-link fallback
    // `www.example.com>`, whose click keeps the existing source-edit path.
    final angleWwwFallback =
        autolink &&
        label.toLowerCase().startsWith('www.') &&
        label.endsWith('>');
    // Obsidian resolves both `()` and `(<>)` to the current note instead of
    // exposing an empty destination to link interaction callbacks.
    final href = !wikiLink && !tagLink && sourceHref?.isEmpty == true
        ? _obsidianCurrentNoteHref
        : sourceHref;
    final labelSegments = _markdownLinkLabelSegments(element);
    var effectivePreferredStyle = _mergeMarkdownLinkStyles(
      parentStyle,
      preferredStyle,
    );
    final fullyStruckLabel =
        labelSegments.isNotEmpty &&
        labelSegments.every((segment) => segment.strikethrough);
    if (element.attributes['data-ianvs-outer-strikethrough'] == 'true' ||
        fullyStruckLabel) {
      effectivePreferredStyle = (effectivePreferredStyle ?? const TextStyle())
          .copyWith(
            decoration: _combineMarkdownLinkDecorations(
              effectivePreferredStyle?.decoration,
              TextDecoration.lineThrough,
            ),
          );
    }
    final link = _MarkdownInlineLink(
      label: label,
      labelSegments: labelSegments,
      href: href,
      title: element.attributes['title'] ?? '',
      wikiLink: wikiLink,
      wikiLinkResolved: wikiLink && href != null
          ? wikiLinkExists?.call(href)
          : null,
      tagLink: tagLink,
      preferredStyle: effectivePreferredStyle,
      onTapLink: autolink && !angleWwwFallback
          ? onTapAutolink ?? onTapLink
          : onTapLink,
      enableFileLinkChips: enableFileLinkChips,
      theme: theme,
    );
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: link,
          ),
        ],
      ),
    );
  }
}

class _MarkdownInlineLink extends StatefulWidget {
  const _MarkdownInlineLink({
    required this.label,
    required this.labelSegments,
    required this.href,
    required this.title,
    required this.wikiLink,
    required this.wikiLinkResolved,
    required this.tagLink,
    required this.preferredStyle,
    required this.onTapLink,
    required this.enableFileLinkChips,
    required this.theme,
  });

  final String label;
  final List<_MarkdownLinkLabelSegment> labelSegments;
  final String? href;
  final String title;
  final bool wikiLink;
  final bool? wikiLinkResolved;
  final bool tagLink;
  final TextStyle? preferredStyle;
  final MarkdownTapLinkCallback? onTapLink;
  final bool enableFileLinkChips;
  final IanvsMarkdownThemeData? theme;

  @override
  State<_MarkdownInlineLink> createState() => _MarkdownInlineLinkState();
}

class _MarkdownInlineLinkState extends State<_MarkdownInlineLink> {
  var _hovered = false;

  bool get _enabled => widget.onTapLink != null;

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context, widget.theme);
    final fileReference =
        !widget.wikiLink &&
        !widget.tagLink &&
        widget.enableFileLinkChips &&
        looksLikeMarkdownFileReference(widget.href, widget.label);
    final link = widget.tagLink
        ? _tagReference(colors)
        : widget.wikiLink
        ? _wikiReference(colors)
        : fileReference
        ? _fileReference(colors)
        : _ordinaryLink(colors);
    final href = widget.href?.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Tooltip(
        message: widget.title.trim().isNotEmpty
            ? widget.title
            : href?.isNotEmpty == true
            ? href!
            : widget.label,
        child: Semantics(
          link: true,
          enabled: _enabled,
          label: widget.label,
          child: MouseRegion(
            cursor: _enabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(
                  widget.tagLink
                      ? 10
                      : fileReference
                      ? 6
                      : 3,
                ),
                onTap: _enabled
                    ? () => widget.onTapLink!(
                        widget.label,
                        widget.href,
                        widget.title,
                      )
                    : null,
                child: link,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fileReference(IanvsMarkdownThemeData colors) {
    return AnimatedContainer(
      key: const ValueKey('ianvs-markdown-file-reference'),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      padding: const EdgeInsets.fromLTRB(5, 2, 7, 2),
      decoration: BoxDecoration(
        color: _hovered ? colors.surfaceHover : colors.surfaceRaised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hovered ? colors.border : colors.borderSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.description_outlined,
            size: 13,
            color: colors.textTertiary,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: widget.preferredStyle?.copyWith(
                color: colors.textPrimary,
                backgroundColor: Colors.transparent,
                decoration: _markdownLinkStrikethroughOnly(
                  widget.preferredStyle?.decoration,
                ),
                fontSize: 12.5,
                height: 1.25,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ordinaryLink(IanvsMarkdownThemeData colors) {
    final href = widget.href?.trim();
    final scheme = href == null ? '' : Uri.tryParse(href)?.scheme.toLowerCase();
    final external = scheme == 'http' || scheme == 'https';
    final style = (widget.preferredStyle ?? const TextStyle()).copyWith(
      color: colors.accentDark,
      backgroundColor: Colors.transparent,
      decoration: _combineMarkdownLinkDecorations(
        _markdownLinkStrikethroughOnly(widget.preferredStyle?.decoration),
        TextDecoration.underline,
      ),
      decorationColor: colors.accentDark,
      decorationThickness: 1,
    );
    final effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
    return AnimatedContainer(
      key: const ValueKey('ianvs-markdown-ordinary-link'),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: _hovered ? colors.accentMist : Colors.transparent,
        borderRadius: BorderRadius.circular(3),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final label = TextSpan(
            style: effectiveStyle,
            children: [
              for (final segment in widget.labelSegments)
                TextSpan(
                  text: segment.text,
                  style: _markdownLinkSegmentStyle(segment, colors),
                ),
            ],
          );
          final painter = TextPainter(
            text: label,
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          )..layout();
          final preferredWidth =
              painter.width.ceilToDouble() + (external ? 14 : 1);
          final availableWidth = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : preferredWidth;
          final width = preferredWidth.clamp(0.0, availableWidth).toDouble();

          return SizedBox(
            width: width,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Text.rich(
                    label,
                    style: effectiveStyle,
                    softWrap: true,
                  ),
                ),
                if (external) ...[
                  const SizedBox(width: 2),
                  Icon(
                    Icons.open_in_new_rounded,
                    key: const ValueKey('ianvs-markdown-external-link-icon'),
                    size: 11,
                    color: colors.textTertiary,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  TextStyle? _markdownLinkSegmentStyle(
    _MarkdownLinkLabelSegment segment,
    IanvsMarkdownThemeData colors,
  ) {
    if (!segment.bold &&
        !segment.italic &&
        !segment.code &&
        !segment.strikethrough) {
      return null;
    }
    return (segment.code
            ? ianvsMarkdownInlineCodeStyle(
                colors,
              ).copyWith(color: colors.accentDark)
            : const TextStyle())
        .copyWith(
          fontWeight: segment.bold ? FontWeight.w600 : null,
          fontStyle: segment.italic ? FontStyle.italic : null,
          decoration: segment.strikethrough
              ? TextDecoration.combine(<TextDecoration>[
                  TextDecoration.underline,
                  TextDecoration.lineThrough,
                ])
              : null,
        );
  }

  Widget _wikiReference(IanvsMarkdownThemeData colors) {
    final unresolved = widget.wikiLinkResolved == false;
    final color = unresolved ? colors.headingAccent(6) : colors.accentDark;
    return AnimatedContainer(
      key: ValueKey(
        unresolved
            ? 'ianvs-markdown-wiki-link-unresolved'
            : 'ianvs-markdown-wiki-link',
      ),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: _hovered
            ? unresolved
                  ? color.withValues(alpha: .1)
                  : colors.accentMist
            : Colors.transparent,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        widget.label,
        style: widget.preferredStyle?.copyWith(
          color: color,
          backgroundColor: Colors.transparent,
          decoration: unresolved
              ? _markdownLinkStrikethroughOnly(
                  widget.preferredStyle?.decoration,
                )
              : _combineMarkdownLinkDecorations(
                  _markdownLinkStrikethroughOnly(
                    widget.preferredStyle?.decoration,
                  ),
                  TextDecoration.underline,
                ),
          decorationColor: color,
          decorationThickness: 1,
          fontWeight: unresolved ? FontWeight.w500 : FontWeight.w600,
        ),
      ),
    );
  }

  Widget _tagReference(IanvsMarkdownThemeData colors) {
    return AnimatedContainer(
      key: const ValueKey('ianvs-markdown-tag'),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: _hovered ? colors.surfaceHover : colors.accentMist,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        widget.label,
        style: widget.preferredStyle?.copyWith(
          color: colors.accentDark,
          backgroundColor: Colors.transparent,
          decoration: _markdownLinkStrikethroughOnly(
            widget.preferredStyle?.decoration,
          ),
          fontSize: 12.5,
          height: 1.25,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

TextStyle? _mergeMarkdownLinkStyles(
  TextStyle? parentStyle,
  TextStyle? preferredStyle,
) {
  if (parentStyle == null) return preferredStyle;
  if (preferredStyle == null) return parentStyle;
  return parentStyle
      .merge(preferredStyle)
      .copyWith(
        decoration: _combineMarkdownLinkDecorations(
          parentStyle.decoration,
          preferredStyle.decoration,
        ),
      );
}

TextDecoration? _combineMarkdownLinkDecorations(
  TextDecoration? inherited,
  TextDecoration? overlay,
) {
  if (inherited != null && inherited == overlay) return inherited;
  final decorations = <TextDecoration>[
    if (inherited != null && inherited != TextDecoration.none) inherited,
    if (overlay != null && overlay != TextDecoration.none) overlay,
  ];
  if (decorations.isEmpty) return null;
  if (decorations.length == 1) return decorations.single;
  return TextDecoration.combine(decorations);
}

TextDecoration _markdownLinkStrikethroughOnly(TextDecoration? decoration) =>
    decoration?.contains(TextDecoration.lineThrough) == true
    ? TextDecoration.lineThrough
    : TextDecoration.none;

class _MarkdownLinkLabelSegment {
  const _MarkdownLinkLabelSegment({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.code = false,
    this.strikethrough = false,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool code;
  final bool strikethrough;

  _MarkdownLinkLabelSegment copyWith({
    String? text,
    bool? bold,
    bool? italic,
    bool? code,
    bool? strikethrough,
  }) {
    return _MarkdownLinkLabelSegment(
      text: text ?? this.text,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      code: code ?? this.code,
      strikethrough: strikethrough ?? this.strikethrough,
    );
  }

  bool hasSameStyle(_MarkdownLinkLabelSegment other) =>
      bold == other.bold &&
      italic == other.italic &&
      code == other.code &&
      strikethrough == other.strikethrough;
}

List<_MarkdownLinkLabelSegment> _markdownLinkLabelSegments(md.Element element) {
  final segments = <_MarkdownLinkLabelSegment>[];

  void append(String text, _MarkdownLinkLabelSegment style) {
    if (text.isEmpty) return;
    final segment = style.copyWith(text: text);
    if (segments.isNotEmpty && segments.last.hasSameStyle(segment)) {
      segments[segments.length - 1] = segments.last.copyWith(
        text: '${segments.last.text}$text',
      );
      return;
    }
    segments.add(segment);
  }

  void visit(md.Node node, _MarkdownLinkLabelSegment inherited) {
    if (node is md.Text) {
      append(node.text, inherited);
      return;
    }
    if (node is! md.Element) return;
    final styled = inherited.copyWith(
      bold: inherited.bold || node.tag == 'strong' || node.tag == 'b',
      italic: inherited.italic || node.tag == 'em' || node.tag == 'i',
      code:
          inherited.code ||
          node.tag == 'code' ||
          node.tag == 'ianvs-inline-code',
      strikethrough:
          inherited.strikethrough || node.tag == 'del' || node.tag == 's',
    );
    for (final child in node.children ?? const <md.Node>[]) {
      visit(child, styled);
    }
  }

  const plain = _MarkdownLinkLabelSegment(text: '');
  for (final child in element.children ?? const <md.Node>[]) {
    visit(child, plain);
  }
  final raw = segments.map((segment) => segment.text).join();
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const <_MarkdownLinkLabelSegment>[];
  final trimStart = raw.indexOf(trimmed);
  final trimEnd = trimStart + trimmed.length;
  var cursor = 0;
  final result = <_MarkdownLinkLabelSegment>[];
  for (final segment in segments) {
    final segmentStart = cursor;
    final segmentEnd = cursor + segment.text.length;
    cursor = segmentEnd;
    final start = segmentStart < trimStart ? trimStart : segmentStart;
    final end = segmentEnd > trimEnd ? trimEnd : segmentEnd;
    if (start >= end) continue;
    result.add(
      segment.copyWith(
        text: segment.text.substring(start - segmentStart, end - segmentStart),
      ),
    );
  }
  return List<_MarkdownLinkLabelSegment>.unmodifiable(result);
}

bool looksLikeMarkdownFileReference(String? href, String label) {
  final source = href?.trim();
  if (source == null || source.isEmpty) return false;
  final uri = Uri.tryParse(source);
  final scheme = uri?.scheme.toLowerCase() ?? '';
  if (scheme == 'http' ||
      scheme == 'https' ||
      scheme == 'mailto' ||
      scheme == 'tel') {
    return false;
  }
  if (scheme == 'file') return true;

  final path = (uri?.path.isNotEmpty == true ? uri!.path : source)
      .split('#')
      .first
      .split('?')
      .first;
  if (path.startsWith('/') || path.contains('/')) return true;
  return RegExp(r'\.[A-Za-z0-9]{1,10}$').hasMatch(path) ||
      RegExp(r'\.[A-Za-z0-9]{1,10}$').hasMatch(label.trim());
}
