import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/csharp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/diff.dart';
import 'package:re_highlight/languages/dockerfile.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/graphql.dart';
import 'package:re_highlight/languages/ini.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/objectivec.dart';
import 'package:re_highlight/languages/php.dart';
import 'package:re_highlight/languages/plaintext.dart';
import 'package:re_highlight/languages/powershell.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/ruby.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/shell.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';

import 'code_surface.dart';
import 'scroll_fade_region.dart';
import 'theme.dart';

const int markdownCodeHighlightCharacterLimit = 200 * 1024;
const int markdownCodeHighlightLineLimit = 2000;
const int markdownCodeTabSize = 4;

typedef IanvsMarkdownDiagramBuilder =
    Widget Function(BuildContext context, String source);
typedef IanvsMarkdownCodeCopyHandler = FutureOr<void> Function(String source);

enum IanvsMarkdownCodeBlockPresentation { reading, editing }

const _ianvsIndentedCodeAttribute = 'data-ianvs-indented-code';

/// Marks four-space and tab-indented code before the Markdown renderer loses
/// the distinction between it and an unlabeled fenced block.
class IanvsMarkdownIndentedCodeBlockSyntax extends md.CodeBlockSyntax {
  const IanvsMarkdownIndentedCodeBlockSyntax();

  @override
  md.Node parse(md.BlockParser parser) {
    final node = super.parse(parser);
    if (node is md.Element) {
      node.attributes[_ianvsIndentedCodeAttribute] = 'true';
    }
    return node;
  }
}

class IanvsMarkdownCodeBlockBuilder extends MarkdownElementBuilder {
  IanvsMarkdownCodeBlockBuilder({
    this.theme,
    this.maxWidth,
    this.diagramBuilder,
    this.onCopyCode,
    this.onTap,
    this.presentation = IanvsMarkdownCodeBlockPresentation.reading,
    this.collapseLongBlocks = false,
  });

  final IanvsMarkdownThemeData? theme;
  final double? maxWidth;
  final IanvsMarkdownDiagramBuilder? diagramBuilder;
  final IanvsMarkdownCodeCopyHandler? onCopyCode;
  final VoidCallback? onTap;
  final IanvsMarkdownCodeBlockPresentation presentation;
  final bool collapseLongBlocks;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = _codeChild(element);
    if (code == null) return null;
    final source = _stripMarkdownTerminalNewline(code.textContent);
    if (element.attributes[_ianvsIndentedCodeAttribute] == 'true') {
      return IanvsMarkdownIndentedCodeBlock(
        source: source,
        theme: theme,
        maxWidth: maxWidth,
        onCopyCode: onCopyCode,
        onTap: onTap,
        presentation: presentation,
        collapseLongBlocks: collapseLongBlocks,
      );
    }
    final language = markdownCodeLanguage(code);
    if (normalizeMarkdownCodeLanguage(language) == 'mermaid' &&
        source.trim().isNotEmpty &&
        diagramBuilder != null) {
      return diagramBuilder!(context, source);
    }
    return IanvsMarkdownCodeBlock(
      source: source,
      language: language,
      theme: theme,
      maxWidth: maxWidth,
      onCopyCode: onCopyCode,
      onTap: onTap,
      presentation: presentation,
      collapseLongBlocks: collapseLongBlocks,
    );
  }
}

class IanvsMarkdownIndentedCodeBlock extends StatelessWidget {
  const IanvsMarkdownIndentedCodeBlock({
    super.key,
    required this.source,
    this.theme,
    this.maxWidth,
    this.onCopyCode,
    this.onTap,
    this.presentation = IanvsMarkdownCodeBlockPresentation.reading,
    this.collapseLongBlocks = false,
  });

  final String source;
  final IanvsMarkdownThemeData? theme;
  final double? maxWidth;
  final IanvsMarkdownCodeCopyHandler? onCopyCode;
  final VoidCallback? onTap;
  final IanvsMarkdownCodeBlockPresentation presentation;
  final bool collapseLongBlocks;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('ianvs-markdown-indented-code-block'),
      child: IanvsMarkdownCodeBlock(
        source: source,
        theme: theme,
        maxWidth: maxWidth,
        onCopyCode: onCopyCode,
        onTap: onTap,
        presentation: presentation,
        collapseLongBlocks: collapseLongBlocks,
      ),
    );
  }
}

class IanvsMarkdownCodeBlock extends StatefulWidget {
  const IanvsMarkdownCodeBlock({
    super.key,
    required this.source,
    this.language,
    this.theme,
    this.maxWidth,
    this.onCopyCode,
    this.onTap,
    this.presentation = IanvsMarkdownCodeBlockPresentation.reading,
    this.collapseLongBlocks = false,
    this.collapsedHeight = 320,
    this.longLineThreshold = 24,
    this.longCharacterThreshold = 2400,
  });

  final String source;
  final String? language;
  final IanvsMarkdownThemeData? theme;
  final double? maxWidth;
  final IanvsMarkdownCodeCopyHandler? onCopyCode;
  final VoidCallback? onTap;
  final IanvsMarkdownCodeBlockPresentation presentation;
  final bool collapseLongBlocks;
  final double collapsedHeight;
  final int longLineThreshold;
  final int longCharacterThreshold;

  @override
  State<IanvsMarkdownCodeBlock> createState() => _IanvsMarkdownCodeBlockState();
}

class _IanvsMarkdownCodeBlockState extends State<IanvsMarkdownCodeBlock> {
  final ScrollController _verticalController = ScrollController();
  Timer? _copiedTimer;
  var _expanded = false;
  var _copied = false;
  var _hovered = false;

  int get _lineCount => markdownCodeLineCount(widget.source);

  bool get _isLong =>
      _lineCount > widget.longLineThreshold ||
      widget.source.length > widget.longCharacterThreshold;

  bool get _isCollapsible => widget.collapseLongBlocks && _isLong;

  @override
  void didUpdateWidget(covariant IanvsMarkdownCodeBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _expanded = false;
      _copied = false;
      _copiedTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context, widget.theme);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = colors.smallRadius / 2;
    final canvasColor = colors.surface;
    final patternColor = (dark ? Colors.white : Colors.black).withValues(
      alpha: .12,
    );
    final frameColor = colors.borderSoft;
    final baseStyle = TextStyle(
      color: colors.codeForeground,
      fontFamily: colors.monoFontFamily,
      fontFamilyFallback: colors.monoFontFamilyFallback,
      fontSize: 14,
      height: 1.5,
      letterSpacing: 0,
    );
    final normalizedLanguage = normalizeMarkdownCodeLanguage(widget.language);
    final highlightSkipped =
        normalizedLanguage != null &&
        normalizedLanguage != 'plaintext' &&
        !markdownCodeCanHighlight(widget.source);
    final displaySource = markdownCodeExpandTabs(widget.source);
    final span = markdownHighlightedCodeSpan(
      displaySource,
      language: widget.language,
      baseStyle: baseStyle,
      dark: dark,
    );
    final desktopHoverControls = switch (Theme.of(context).platform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      _ => false,
    };
    final editing =
        widget.presentation == IanvsMarkdownCodeBlockPresentation.editing;
    final showActions = editing || _hovered || !desktopHoverControls || _copied;
    final blankPayload = widget.source.codeUnits.every(
      (unit) => unit == 0x0a || unit == 0x0d,
    );
    // Obsidian Reading view omits the empty `<code>` line box, while Live
    // Preview keeps the opening, content, and closing editor rows. Additional
    // blank payload rows follow each view's measured logical-line step.
    final contentPadding = blankPayload
        ? EdgeInsets.symmetric(horizontal: 16, vertical: editing ? 15 : 3)
        : const EdgeInsets.symmetric(horizontal: 16, vertical: 12);
    final blankCanvasMinHeight = !blankPayload
        ? 0.0
        : editing
        ? 58.0 + (_lineCount - 1) * 20
        : 34.0 + (_lineCount - 1) * 31;

    final codeViewport = LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: constraints.maxWidth,
          child: SelectableText.rich(
            span,
            style: baseStyle,
            textWidthBasis: TextWidthBasis.parent,
            onTap: widget.onTap,
          ),
        );
      },
    );
    Widget body = Container(
      key: const ValueKey('ianvs-markdown-code-canvas'),
      constraints: BoxConstraints(minHeight: blankCanvasMinHeight),
      child: Stack(
        children: [
          Padding(
            key: const ValueKey('ianvs-markdown-code-content-padding'),
            padding: contentPadding,
            child: codeViewport,
          ),
          Positioned(
            top: editing ? 6 : 0,
            right: editing ? 6 : 0,
            child: _CodeBlockToolbar(
              source: widget.source,
              language: widget.language == null
                  ? null
                  : markdownCodeLanguageLabel(widget.language),
              editing: editing,
              highlightSkipped: highlightSkipped,
              copied: _copied,
              isCollapsible: _isCollapsible,
              expanded: _expanded,
              showActions: showActions,
              colors: colors,
              onCopyCode: widget.onCopyCode,
              onToggleExpanded: () => setState(() => _expanded = !_expanded),
              onCopy: _copy,
            ),
          ),
        ],
      ),
    );
    if (_isCollapsible && !_expanded) {
      body = IanvsMarkdownScrollFadeRegion(
        key: const ValueKey('ianvs-markdown-code-scroll-region'),
        controller: _verticalController,
        maxHeight: widget.collapsedHeight,
        backgroundColor: canvasColor,
        showScrollbar: true,
        child: body,
      );
    }

    final surface = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        key: const ValueKey('ianvs-markdown-code-block'),
        width: widget.maxWidth ?? double.infinity,
        constraints: BoxConstraints(
          minHeight: blankPayload && !editing ? 34 : 38,
          maxWidth: widget.maxWidth ?? double.infinity,
        ),
        margin: const EdgeInsets.symmetric(vertical: 8),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: canvasColor,
          borderRadius: BorderRadius.circular(radius),
        ),
        foregroundDecoration: IanvsMarkdownDashedBorderDecoration(
          color: frameColor,
          radius: radius,
        ),
        child: CustomPaint(
          key: const ValueKey('ianvs-markdown-code-pattern'),
          painter: IanvsMarkdownCodePatternPainter(color: patternColor),
          child: body,
        ),
      ),
    );
    final onTap = widget.onTap;
    if (onTap == null) return surface;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onTap,
      child: surface,
    );
  }

  Future<void> _copy() async {
    final handler = widget.onCopyCode;
    if (handler == null) {
      await Clipboard.setData(ClipboardData(text: widget.source));
    } else {
      await handler(widget.source);
    }
    if (!mounted) return;
    _copiedTimer?.cancel();
    setState(() => _copied = true);
    _copiedTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _copied = false);
    });
  }
}

class _CodeBlockToolbar extends StatelessWidget {
  const _CodeBlockToolbar({
    required this.source,
    required this.language,
    required this.editing,
    required this.highlightSkipped,
    required this.copied,
    required this.isCollapsible,
    required this.expanded,
    required this.showActions,
    required this.colors,
    required this.onCopyCode,
    required this.onToggleExpanded,
    required this.onCopy,
  });

  final String source;
  final String? language;
  final bool editing;
  final bool highlightSkipped;
  final bool copied;
  final bool isCollapsible;
  final bool expanded;
  final bool showActions;
  final IanvsMarkdownThemeData colors;
  final IanvsMarkdownCodeCopyHandler? onCopyCode;
  final VoidCallback onToggleExpanded;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    if (!showActions && !highlightSkipped) {
      return const SizedBox.shrink(
        key: ValueKey('ianvs-markdown-code-toolbar'),
      );
    }
    return Row(
      key: const ValueKey('ianvs-markdown-code-toolbar'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (highlightSkipped)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Tooltip(
              message: '代码过大，已回退为纯文本以保持预览流畅',
              child: Icon(
                Icons.speed_rounded,
                size: 14,
                color: colors.textTertiary,
              ),
            ),
          ),
        if (showActions && isCollapsible) ...[
          TextButton.icon(
            onPressed: onToggleExpanded,
            style:
                TextButton.styleFrom(
                  foregroundColor: colors.codeForeground,
                  backgroundColor: Colors.transparent,
                  visualDensity: VisualDensity.compact,
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: 12),
                ).copyWith(
                  overlayColor: WidgetStatePropertyAll(
                    colors.codeForeground.withValues(alpha: .2),
                  ),
                ),
            icon: Icon(
              expanded ? Icons.unfold_less_rounded : Icons.unfold_more_rounded,
              size: 14,
            ),
            label: Text(expanded ? '收起' : '展开'),
          ),
          const SizedBox(width: 2),
        ],
        if (showActions && editing)
          IanvsMarkdownCodeFlair(
            source: source,
            language: language,
            theme: colors,
            onCopyCode: onCopyCode,
          )
        else if (showActions)
          KeyedSubtree(
            key: const ValueKey('ianvs-markdown-code-action-strip'),
            child: _CodeToolbarButton(
              tooltip: copied ? '已复制到剪贴板' : '复制',
              icon: copied ? Icons.check_rounded : Icons.content_copy_rounded,
              selected: copied,
              colors: colors,
              onPressed: onCopy,
            ),
          ),
      ],
    );
  }
}

/// Obsidian Live Preview's persistent code-block flair.
///
/// A labeled fence shows its language; an unlabeled fence shows the copy icon.
/// Both forms copy the exact code payload when pressed.
class IanvsMarkdownCodeFlair extends StatelessWidget {
  const IanvsMarkdownCodeFlair({
    super.key,
    required this.source,
    this.language,
    this.theme,
    this.onCopyCode,
  });

  final String source;
  final String? language;
  final IanvsMarkdownThemeData? theme;
  final IanvsMarkdownCodeCopyHandler? onCopyCode;

  Future<void> _copy() async {
    final handler = onCopyCode;
    if (handler == null) {
      await Clipboard.setData(ClipboardData(text: source));
    } else {
      await handler(source);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context, theme);
    final label = language == null ? null : markdownCodeLanguageLabel(language);
    final hasLabel = label != null && label.isNotEmpty;
    return Tooltip(
      message: '复制',
      child: TextButton(
        key: const ValueKey('ianvs-markdown-code-flair'),
        onPressed: _copy,
        style:
            TextButton.styleFrom(
              foregroundColor: colors.codeForeground,
              backgroundColor: Colors.transparent,
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ).copyWith(
              overlayColor: WidgetStatePropertyAll(
                colors.codeForeground.withValues(alpha: .2),
              ),
            ),
        child: hasLabel
            ? Semantics(
                key: const ValueKey('ianvs-markdown-code-language-badge'),
                label: label,
                excludeSemantics: true,
                child: Text(label),
              )
            : const Icon(Icons.content_copy_rounded, size: 16),
      ),
    );
  }
}

class _CodeToolbarButton extends StatelessWidget {
  const _CodeToolbarButton({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.colors,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final IanvsMarkdownThemeData colors;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      style:
          IconButton.styleFrom(
            foregroundColor: selected
                ? colors.headingAccent(4)
                : colors.codeForeground,
            backgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ).copyWith(
            overlayColor: WidgetStatePropertyAll(
              colors.codeForeground.withValues(alpha: .2),
            ),
          ),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      visualDensity: VisualDensity.compact,
    );
  }
}

String? markdownCodeLanguage(md.Element code) {
  final className = code.attributes['class'] ?? '';
  for (final part in className.split(RegExp(r'\s+'))) {
    final rawPart = part.trim();
    final normalizedPart = rawPart.toLowerCase();
    if (normalizedPart.startsWith('language-')) {
      return rawPart.substring('language-'.length);
    }
    if (normalizedPart.startsWith('lang-')) {
      return rawPart.substring('lang-'.length);
    }
  }
  return null;
}

String? normalizeMarkdownCodeLanguage(String? language) {
  final value = language?.trim().toLowerCase();
  if (value == null || value.isEmpty) return null;
  return _languageAliases[value] ?? value;
}

String markdownCodeLanguageLabel(String? language) {
  final normalized = normalizeMarkdownCodeLanguage(language);
  if (normalized == null) return 'text';
  final conventionalLabel = _languageLabels[normalized];
  if (conventionalLabel != null) return conventionalLabel;
  if (_codeHighlighter.getLanguage(normalized) != null) {
    return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
  }
  return language!.trim();
}

int markdownCodeLineCount(String source) {
  if (source.isEmpty) return 1;
  var lines = 1;
  for (var index = 0; index < source.length; index += 1) {
    if (source.codeUnitAt(index) == 0x0a) lines += 1;
  }
  return lines;
}

/// Expands literal tabs to Obsidian's four-column code-block tab stops while
/// leaving the canonical Markdown source available for editing and copying.
String markdownCodeExpandTabs(
  String source, {
  int tabSize = markdownCodeTabSize,
}) {
  assert(tabSize > 0);
  if (!source.contains('\t')) return source;

  final result = StringBuffer();
  var column = 0;
  for (final rune in source.runes) {
    if (rune == 0x09) {
      final spaces = tabSize - (column % tabSize);
      result.write(''.padLeft(spaces));
      column += spaces;
      continue;
    }
    result.writeCharCode(rune);
    if (rune == 0x0a || rune == 0x0d) {
      column = 0;
    } else {
      column += 1;
    }
  }
  return result.toString();
}

bool markdownCodeCanHighlight(String source) =>
    source.length <= markdownCodeHighlightCharacterLimit &&
    markdownCodeLineCount(source) <= markdownCodeHighlightLineLimit;

TextSpan markdownHighlightedCodeSpan(
  String source, {
  required String? language,
  required TextStyle baseStyle,
  bool dark = false,
}) {
  final normalized = normalizeMarkdownCodeLanguage(language);
  if (normalized == null ||
      normalized == 'plaintext' ||
      !markdownCodeCanHighlight(source) ||
      _codeHighlighter.getLanguage(normalized) == null) {
    return TextSpan(text: source, style: baseStyle);
  }

  final key = _HighlightCacheKey(language: normalized, source: source);
  var result = _highlightCache.get(key);
  if (result == null) {
    try {
      result = _codeHighlighter.highlight(code: source, language: normalized);
      _highlightCache.put(key, result);
    } on Object {
      return TextSpan(text: source, style: baseStyle);
    }
  }
  final renderer = TextSpanRenderer(
    baseStyle,
    dark ? _borderDarkCodeTheme : _borderLightCodeTheme,
  );
  result.render(renderer);
  return renderer.span ?? TextSpan(text: source, style: baseStyle);
}

md.Element? _codeChild(md.Element element) {
  for (final child in element.children ?? const <md.Node>[]) {
    if (child is md.Element && child.tag == 'code') return child;
  }
  return null;
}

String _stripMarkdownTerminalNewline(String source) {
  if (source.endsWith('\r\n')) {
    return source.substring(0, source.length - 2);
  }
  if (source.endsWith('\n')) return source.substring(0, source.length - 1);
  return source;
}

final Highlight _codeHighlighter = _createCodeHighlighter();
final _HighlightCache _highlightCache = _HighlightCache();

const _borderLightCodeTheme = <String, TextStyle>{
  'root': TextStyle(color: Color(0xff545664)),
  'doctag': TextStyle(color: Color(0xff989bae)),
  'keyword': TextStyle(color: Color(0xffdd1399)),
  'meta-keyword': TextStyle(color: Color(0xffdd1399)),
  'template-tag': TextStyle(color: Color(0xffdd2c38)),
  'template-variable': TextStyle(color: Color(0xff16a6ab)),
  'type': TextStyle(color: Color(0xffc09c0c)),
  'variable.language_': TextStyle(color: Color(0xff16a6ab)),
  'title': TextStyle(color: Color(0xffc09c0c)),
  'title.class_': TextStyle(color: Color(0xffc09c0c)),
  'title.class_.inherited__': TextStyle(color: Color(0xffc09c0c)),
  'title.function_': TextStyle(color: Color(0xffc09c0c)),
  'attr': TextStyle(color: Color(0xff1da51d)),
  'attribute': TextStyle(color: Color(0xff1da51d)),
  'literal': TextStyle(color: Color(0xff8f47e1)),
  'meta': TextStyle(color: Color(0xff989bae)),
  'number': TextStyle(color: Color(0xff8f47e1)),
  'operator': TextStyle(color: Color(0xffdd2c38)),
  'variable': TextStyle(color: Color(0xff16a6ab)),
  'selector-attr': TextStyle(color: Color(0xff1da51d)),
  'selector-class': TextStyle(color: Color(0xff1da51d)),
  'selector-id': TextStyle(color: Color(0xff1da51d)),
  'regexp': TextStyle(color: Color(0xffde7417)),
  'string': TextStyle(color: Color(0xff1da51d)),
  'meta-string': TextStyle(color: Color(0xff1da51d)),
  'built_in': TextStyle(color: Color(0xffc09c0c)),
  'symbol': TextStyle(color: Color(0xffdd2c38)),
  'comment': TextStyle(color: Color(0xff989bae)),
  'code': TextStyle(color: Color(0xff989bae)),
  'formula': TextStyle(color: Color(0xff989bae)),
  'name': TextStyle(color: Color(0xffdd2c38)),
  'quote': TextStyle(color: Color(0xff1da51d)),
  'selector-tag': TextStyle(color: Color(0xff1da51d)),
  'selector-pseudo': TextStyle(color: Color(0xff1da51d)),
  'subst': TextStyle(color: Color(0xff545664)),
  'section': TextStyle(color: Color(0xffc09c0c), fontWeight: FontWeight.bold),
  'bullet': TextStyle(color: Color(0xffdd2c38)),
  'emphasis': TextStyle(color: Color(0xff545664), fontStyle: FontStyle.italic),
  'strong': TextStyle(color: Color(0xff545664), fontWeight: FontWeight.bold),
  'addition': TextStyle(color: Color(0xff1da51d)),
  'deletion': TextStyle(color: Color(0xffdd2c38)),
};

const _borderDarkCodeTheme = <String, TextStyle>{
  'root': TextStyle(color: Color(0xffb8bac7)),
  'doctag': TextStyle(color: Color(0xff74778b)),
  'keyword': TextStyle(color: Color(0xfff2b6de)),
  'meta-keyword': TextStyle(color: Color(0xfff2b6de)),
  'template-tag': TextStyle(color: Color(0xffff7881)),
  'template-variable': TextStyle(color: Color(0xff86dfe2)),
  'type': TextStyle(color: Color(0xffffe88b)),
  'variable.language_': TextStyle(color: Color(0xff86dfe2)),
  'title': TextStyle(color: Color(0xffffe88b)),
  'title.class_': TextStyle(color: Color(0xffffe88b)),
  'title.class_.inherited__': TextStyle(color: Color(0xffffe88b)),
  'title.function_': TextStyle(color: Color(0xffffe88b)),
  'attr': TextStyle(color: Color(0xff7cd37c)),
  'attribute': TextStyle(color: Color(0xff7cd37c)),
  'literal': TextStyle(color: Color(0xffcb9eff)),
  'meta': TextStyle(color: Color(0xff74778b)),
  'number': TextStyle(color: Color(0xffcb9eff)),
  'operator': TextStyle(color: Color(0xffff7881)),
  'variable': TextStyle(color: Color(0xff86dfe2)),
  'selector-attr': TextStyle(color: Color(0xff7cd37c)),
  'selector-class': TextStyle(color: Color(0xff7cd37c)),
  'selector-id': TextStyle(color: Color(0xff7cd37c)),
  'regexp': TextStyle(color: Color(0xfffbbb83)),
  'string': TextStyle(color: Color(0xff7cd37c)),
  'meta-string': TextStyle(color: Color(0xff7cd37c)),
  'built_in': TextStyle(color: Color(0xffffe88b)),
  'symbol': TextStyle(color: Color(0xffff7881)),
  'comment': TextStyle(color: Color(0xff74778b)),
  'code': TextStyle(color: Color(0xff74778b)),
  'formula': TextStyle(color: Color(0xff74778b)),
  'name': TextStyle(color: Color(0xffff7881)),
  'quote': TextStyle(color: Color(0xff7cd37c)),
  'selector-tag': TextStyle(color: Color(0xff7cd37c)),
  'selector-pseudo': TextStyle(color: Color(0xff7cd37c)),
  'subst': TextStyle(color: Color(0xffb8bac7)),
  'section': TextStyle(color: Color(0xffffe88b), fontWeight: FontWeight.bold),
  'bullet': TextStyle(color: Color(0xffff7881)),
  'emphasis': TextStyle(color: Color(0xffb8bac7), fontStyle: FontStyle.italic),
  'strong': TextStyle(color: Color(0xffb8bac7), fontWeight: FontWeight.bold),
  'addition': TextStyle(color: Color(0xff7cd37c)),
  'deletion': TextStyle(color: Color(0xffff7881)),
};

Highlight _createCodeHighlighter() {
  return Highlight()..registerLanguages(<String, Mode>{
    'bash': langBash,
    'c': langC,
    'cpp': langCpp,
    'csharp': langCsharp,
    'css': langCss,
    'dart': langDart,
    'diff': langDiff,
    'dockerfile': langDockerfile,
    'go': langGo,
    'graphql': langGraphql,
    'ini': langIni,
    'java': langJava,
    'javascript': langJavascript,
    'json': langJson,
    'kotlin': langKotlin,
    'markdown': langMarkdown,
    'objectivec': langObjectivec,
    'php': langPhp,
    'plaintext': langPlaintext,
    'powershell': langPowershell,
    'python': langPython,
    'ruby': langRuby,
    'rust': langRust,
    'shell': langShell,
    'sql': langSql,
    'swift': langSwift,
    'typescript': langTypescript,
    'xml': langXml,
    'yaml': langYaml,
  });
}

const Map<String, String> _languageAliases = <String, String>{
  'bsh': 'bash',
  'c++': 'cpp',
  'cc': 'cpp',
  'c#': 'csharp',
  'cs': 'csharp',
  'docker': 'dockerfile',
  'golang': 'go',
  'gql': 'graphql',
  'html': 'xml',
  'js': 'javascript',
  'jsx': 'javascript',
  'kt': 'kotlin',
  'md': 'markdown',
  'objc': 'objectivec',
  'ps1': 'powershell',
  'py': 'python',
  'rb': 'ruby',
  'rs': 'rust',
  'sh': 'bash',
  'shellscript': 'bash',
  'text': 'plaintext',
  'txt': 'plaintext',
  'ts': 'typescript',
  'tsx': 'typescript',
  'yml': 'yaml',
};

const Map<String?, String> _languageLabels = <String?, String>{
  'bash': 'Shell',
  'css': 'CSS',
  'dart': 'Dart',
  'cpp': 'C++',
  'csharp': 'C#',
  'dockerfile': 'Dockerfile',
  'graphql': 'GraphQL',
  'javascript': 'JavaScript',
  'json': 'JSON',
  'markdown': 'Markdown',
  'objectivec': 'Objective-C',
  'php': 'PHP',
  'plaintext': 'text',
  'powershell': 'PowerShell',
  'sql': 'SQL',
  'typescript': 'TypeScript',
  'xml': 'HTML / XML',
  'yaml': 'YAML',
};

final class _HighlightCacheKey {
  _HighlightCacheKey({required this.language, required this.source})
    : _hashCode = Object.hash(language, source);

  final String language;
  final String source;
  final int _hashCode;

  @override
  int get hashCode => _hashCode;

  @override
  bool operator ==(Object other) =>
      other is _HighlightCacheKey &&
      language == other.language &&
      source == other.source;
}

final class _HighlightCache {
  static const int _maximumEntries = 64;
  static const int _maximumSourceCharacters = 1024 * 1024;

  final LinkedHashMap<_HighlightCacheKey, HighlightResult> _entries =
      LinkedHashMap<_HighlightCacheKey, HighlightResult>();
  var _sourceCharacters = 0;

  HighlightResult? get(_HighlightCacheKey key) {
    final value = _entries.remove(key);
    if (value != null) _entries[key] = value;
    return value;
  }

  void put(_HighlightCacheKey key, HighlightResult value) {
    final replaced = _entries.remove(key);
    if (replaced != null) _sourceCharacters -= key.source.length;
    _entries[key] = value;
    _sourceCharacters += key.source.length;
    while (_entries.length > _maximumEntries ||
        _sourceCharacters > _maximumSourceCharacters) {
      final oldest = _entries.keys.first;
      _entries.remove(oldest);
      _sourceCharacters -= oldest.source.length;
    }
  }
}
