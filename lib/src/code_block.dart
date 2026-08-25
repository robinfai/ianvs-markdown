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
import 'package:re_highlight/styles/github.dart';
import 'package:re_highlight/styles/github-dark.dart';

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
  });

  final String source;
  final IanvsMarkdownThemeData? theme;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context, theme);
    return Container(
      key: const ValueKey('ianvs-markdown-indented-code-block'),
      width: maxWidth ?? double.infinity,
      constraints: BoxConstraints(
        minHeight: 24,
        maxWidth: maxWidth ?? double.infinity,
      ),
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(10, 2, 0, 2),
      child: SelectableText(
        markdownCodeExpandTabs(source),
        style: TextStyle(
          color: colors.accentDark,
          fontFamily: colors.monoFontFamily,
          fontFamilyFallback: colors.monoFontFamilyFallback,
          fontSize: 13,
          height: 1.55,
          letterSpacing: 0,
        ),
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
    final canvasColor = dark ? colors.surfaceMuted : colors.surfaceRaised;
    final frameColor = _hovered
        ? colors.border.withValues(alpha: dark ? .72 : .62)
        : colors.borderSoft.withValues(alpha: dark ? .72 : .82);
    final baseStyle = TextStyle(
      color: colors.textPrimary,
      fontFamily: colors.monoFontFamily,
      fontFamilyFallback: colors.monoFontFamilyFallback,
      fontSize: 13.25,
      height: 1.55,
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
    final showActions =
        _hovered ||
        !desktopHoverControls ||
        (editing && widget.language == null);
    final showLanguage =
        editing &&
        (!_hovered || !desktopHoverControls) &&
        widget.language != null;

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
      color: canvasColor,
      child: Stack(
        children: [
          Padding(
            key: const ValueKey('ianvs-markdown-code-content-padding'),
            padding: const EdgeInsets.all(12),
            child: codeViewport,
          ),
          Positioned(
            top: 4,
            right: 5,
            child: _CodeBlockToolbar(
              language: widget.language == null
                  ? null
                  : markdownCodeLanguageLabel(widget.language),
              highlightSkipped: highlightSkipped,
              copied: _copied,
              isCollapsible: _isCollapsible,
              expanded: _expanded,
              showActions: showActions,
              showLanguage: showLanguage,
              colors: colors,
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
        child: body,
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
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }
}

class _CodeBlockToolbar extends StatelessWidget {
  const _CodeBlockToolbar({
    required this.language,
    required this.highlightSkipped,
    required this.copied,
    required this.isCollapsible,
    required this.expanded,
    required this.showActions,
    required this.showLanguage,
    required this.colors,
    required this.onToggleExpanded,
    required this.onCopy,
  });

  final String? language;
  final bool highlightSkipped;
  final bool copied;
  final bool isCollapsible;
  final bool expanded;
  final bool showActions;
  final bool showLanguage;
  final IanvsMarkdownThemeData colors;
  final VoidCallback onToggleExpanded;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      key: const ValueKey('ianvs-markdown-code-toolbar'),
      duration: const Duration(milliseconds: 120),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: Row(
        key: ValueKey((showActions, showLanguage)),
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showLanguage && language != null)
            Semantics(
              key: const ValueKey('ianvs-markdown-code-language-badge'),
              label: language,
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(5, 2, 5, 3),
                child: Text(
                  language!,
                  style: TextStyle(
                    color: colors.textTertiary.withValues(alpha: .88),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    letterSpacing: .1,
                  ),
                ),
              ),
            ),
          if (highlightSkipped) ...[
            if (showLanguage) const SizedBox(width: 8),
            Tooltip(
              message: '代码过大，已回退为纯文本以保持预览流畅',
              child: Icon(
                Icons.speed_rounded,
                size: 14,
                color: colors.textTertiary,
              ),
            ),
          ],
          if (showActions) ...[
            if (showLanguage || highlightSkipped)
              const SizedBox(
                key: ValueKey('ianvs-markdown-code-action-strip'),
                width: 3,
              )
            else
              const SizedBox(key: ValueKey('ianvs-markdown-code-action-strip')),
            if (isCollapsible)
              TextButton.icon(
                onPressed: onToggleExpanded,
                style: TextButton.styleFrom(
                  foregroundColor: colors.textSecondary,
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(0, 24),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(3),
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                icon: Icon(
                  expanded
                      ? Icons.unfold_less_rounded
                      : Icons.unfold_more_rounded,
                  size: 13,
                ),
                label: Text(expanded ? '收起' : '展开'),
              ),
            if (isCollapsible) const SizedBox(width: 2),
            _CodeToolbarButton(
              tooltip: copied ? '已复制到剪贴板' : '复制',
              icon: copied ? Icons.check_rounded : Icons.content_copy_rounded,
              selected: copied,
              colors: colors,
              onPressed: onCopy,
            ),
          ],
        ],
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
      icon: Icon(icon, size: 14),
      style: IconButton.styleFrom(
        foregroundColor: selected ? colors.accentDark : colors.textSecondary,
        backgroundColor: selected
            ? colors.accentMist
            : colors.surface.withValues(alpha: .82),
        overlayColor: colors.surfaceHover,
        side: BorderSide(
          color: selected
              ? colors.accent.withValues(alpha: .34)
              : colors.borderSoft.withValues(alpha: .78),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      ),
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      padding: EdgeInsets.zero,
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
    dark ? githubDarkTheme : githubTheme,
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
