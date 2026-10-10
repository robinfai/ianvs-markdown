import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:markdown/markdown.dart' as md;

import 'render_budget.dart';
import 'syntax_preset.dart';

/// Complete text and optional HTML provided to Reading-mode clipboard writers.
final class IanvsMarkdownClipboardData {
  const IanvsMarkdownClipboardData({
    required this.markdown,
    required this.html,
    this.budgetExceeded,
  });

  /// Markdown-compatible plain text.
  ///
  /// A whole-document selection preserves the exact original Markdown source;
  /// a partial visual selection is re-serialized from the selected semantic
  /// Markdown fragment so inline and block formatting remain available.
  final String markdown;

  /// Safe semantic HTML, or an empty string when conversion was skipped.
  /// Writers must omit the HTML format when [hasHtml] is false.
  final String html;

  bool get hasHtml => html.isNotEmpty;

  /// When non-null, Markdown parsing was skipped. Whole-document Markdown is
  /// exact source; partial selections contain the complete selected plain text.
  final IanvsMarkdownBudgetExceeded? budgetExceeded;
}

/// Receives Markdown and rich HTML representations for host-controlled output.
typedef IanvsMarkdownClipboardWriter =
    Future<void> Function(IanvsMarkdownClipboardData data);

/// Default pure-Flutter clipboard writer used by Reading mode.
///
/// Writes the complete Markdown representation as plain text. To also write
/// HTML, inject a writer such as the optional ianvs_markdown_clipboard adapter.
Future<void> writeIanvsMarkdownClipboard(IanvsMarkdownClipboardData data) =>
    Clipboard.setData(ClipboardData(text: data.markdown));

/// Converts Markdown to safe HTML, or returns an empty string on overflow.
/// [onBudgetExceeded] observes why no HTML was generated. No truncated HTML
/// is returned. Set [budget] to null only for trusted input.
String ianvsMarkdownClipboardHtml(
  String markdown, {
  IanvsMarkdownRenderBudget? budget = const IanvsMarkdownRenderBudget(),
  void Function(IanvsMarkdownBudgetExceeded reason)? onBudgetExceeded,
}) {
  final decision = _clipboardDecision(markdown, budget);
  if (!decision.useMarkdown) {
    onBudgetExceeded?.call(decision.budgetExceeded!);
    return '';
  }
  return _markdownClipboardHtml(markdown);
}

IanvsMarkdownRenderDecision _clipboardDecision(
  String source,
  IanvsMarkdownRenderBudget? budget,
) => scanMarkdownForRendering(
  source,
  budget: budget,
  syntaxPreset: IanvsMarkdownSyntaxPreset.standard,
);

/// Builds a whole-document payload without truncating [markdown].
/// [richMarkdown] may omit front matter or include a host's reading projection;
/// both inputs must pass the budget before any HTML conversion is attempted.
IanvsMarkdownClipboardData ianvsMarkdownDocumentClipboardData(
  String markdown, {
  String? richMarkdown,
  IanvsMarkdownRenderBudget? budget = const IanvsMarkdownRenderBudget(),
}) {
  final sourceDecision = _clipboardDecision(markdown, budget);
  final richSource = richMarkdown ?? markdown;
  final decision = sourceDecision.useMarkdown && richSource != markdown
      ? _clipboardDecision(richSource, budget)
      : sourceDecision;
  return IanvsMarkdownClipboardData(
    markdown: markdown,
    html: decision.useMarkdown ? _markdownClipboardHtml(richSource) : '',
    budgetExceeded: decision.budgetExceeded,
  );
}

String _markdownClipboardHtml(String markdown) {
  final rendered = md.markdownToHtml(
    markdown,
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: true,
    enableTagfilter: true,
  );
  final fragment = html_parser.parseFragment(rendered);
  _sanitizeClipboardFragment(fragment);
  return fragment.nodes.map(_clipboardNodeHtml).join();
}

String _clipboardNodeHtml(dom.Node node) => switch (node) {
  dom.Element() => node.outerHtml,
  dom.Text() => const HtmlEscape().convert(node.data),
  _ => '',
};

String ianvsPlainTextClipboardHtml(String text) {
  final container = dom.Element.tag('div');
  final lines = text.split('\n');
  for (var index = 0; index < lines.length; index += 1) {
    if (index > 0) container.append(dom.Element.tag('br'));
    container.append(dom.Text(lines[index]));
  }
  return container.outerHtml;
}

/// Builds both clipboard representations for a visual Markdown selection.
///
/// Flutter currently exposes only the flattened visible text for a selection.
/// This function locates that text in the rendered Markdown DOM, slices the
/// matching semantic fragment, and serializes the fragment back to Markdown.
/// [preferredStart] disambiguates repeated text when the selection system can
/// also provide its flattened document offset.
IanvsMarkdownClipboardData ianvsMarkdownSelectionClipboardData(
  String markdown,
  String selectedText, {
  int? preferredStart,
  IanvsMarkdownRenderBudget? budget = const IanvsMarkdownRenderBudget(),
}) {
  if (selectedText.isEmpty) {
    return const IanvsMarkdownClipboardData(markdown: '', html: '');
  }
  final sourceDecision = _clipboardDecision(markdown, budget);
  final decision = sourceDecision.useMarkdown
      ? _clipboardDecision(selectedText, budget)
      : sourceDecision;
  if (!decision.useMarkdown) {
    return IanvsMarkdownClipboardData(
      markdown: selectedText,
      html: '',
      budgetExceeded: decision.budgetExceeded,
    );
  }
  final rendered = md.markdownToHtml(
    markdown,
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: true,
    enableTagfilter: true,
  );
  final fragment = html_parser.parseFragment(rendered);
  _markClipboardTaskItems(fragment);
  _sanitizeClipboardFragment(fragment);
  _removeClipboardInterBlockWhitespace(fragment);
  final visibleText = fragment.text ?? '';
  final start = _closestTextOccurrence(
    visibleText,
    selectedText,
    preferredStart: preferredStart,
  );
  if (start == null) {
    return IanvsMarkdownClipboardData(
      markdown: selectedText,
      html: ianvsPlainTextClipboardHtml(selectedText),
    );
  }

  final end = start + selectedText.length;
  final cursor = _ClipboardTextCursor();
  final selectedFragment = dom.DocumentFragment();
  for (final node in fragment.nodes) {
    final selected = _sliceClipboardNode(node, start, end, cursor);
    if (selected != null) selectedFragment.append(selected);
  }
  final selectedMarkdown = _clipboardNodesMarkdown(
    selectedFragment.nodes,
    blockSeparator: true,
  );
  _removeClipboardTaskMetadata(selectedFragment);
  final html = selectedFragment.nodes.map(_clipboardNodeHtml).join();
  return IanvsMarkdownClipboardData(
    markdown: selectedMarkdown.isEmpty ? selectedText : selectedMarkdown,
    html: html.isEmpty ? ianvsPlainTextClipboardHtml(selectedText) : html,
  );
}

const _clipboardTaskAttribute = 'data-ianvs-task';

void _markClipboardTaskItems(dom.DocumentFragment fragment) {
  for (final item in fragment.querySelectorAll('li.task-list-item')) {
    final checkbox = item.querySelector('input[type="checkbox"]');
    if (checkbox == null) continue;
    item.attributes[_clipboardTaskAttribute] =
        checkbox.attributes.containsKey('checked') ? 'x' : ' ';
  }
}

void _removeClipboardTaskMetadata(dom.DocumentFragment fragment) {
  for (final item in fragment.querySelectorAll('[$_clipboardTaskAttribute]')) {
    item.attributes.remove(_clipboardTaskAttribute);
  }
}

void _removeClipboardInterBlockWhitespace(dom.Node parent) {
  final structuralWhitespace =
      parent is dom.DocumentFragment ||
      parent is dom.Element &&
          const <String>{
            'blockquote',
            'ol',
            'table',
            'tbody',
            'tfoot',
            'thead',
            'tr',
            'ul',
          }.contains(parent.localName);
  for (final child in parent.nodes.toList(growable: false)) {
    if (structuralWhitespace &&
        child is dom.Text &&
        child.data.trim().isEmpty) {
      child.remove();
      continue;
    }
    _removeClipboardInterBlockWhitespace(child);
  }
}

int? _closestTextOccurrence(
  String text,
  String selection, {
  int? preferredStart,
}) {
  var match = text.indexOf(selection);
  if (match < 0) return null;
  if (preferredStart == null) return match;
  var closest = match;
  var closestDistance = (match - preferredStart).abs();
  while (match >= 0) {
    final distance = (match - preferredStart).abs();
    if (distance < closestDistance) {
      closest = match;
      closestDistance = distance;
    }
    match = text.indexOf(selection, match + 1);
  }
  return closest;
}

final class _ClipboardTextCursor {
  int offset = 0;
}

dom.Node? _sliceClipboardNode(
  dom.Node node,
  int selectionStart,
  int selectionEnd,
  _ClipboardTextCursor cursor,
) {
  if (node is dom.Text) {
    final nodeStart = cursor.offset;
    final nodeEnd = nodeStart + node.data.length;
    cursor.offset = nodeEnd;
    final start = selectionStart.clamp(nodeStart, nodeEnd) - nodeStart;
    final end = selectionEnd.clamp(nodeStart, nodeEnd) - nodeStart;
    if (start >= end) return null;
    return dom.Text(node.data.substring(start, end));
  }
  if (node is! dom.Element) return null;

  final nodeStart = cursor.offset;
  final clone = dom.Element.tag(node.localName);
  clone.attributes.addAll(node.attributes);
  for (final child in node.nodes) {
    final selected = _sliceClipboardNode(
      child,
      selectionStart,
      selectionEnd,
      cursor,
    );
    if (selected != null) clone.append(selected);
  }
  if (clone.nodes.isNotEmpty) return clone;

  // Preserve zero-width semantic nodes, such as line breaks and horizontal
  // rules, only when they lie inside a non-empty selected range.
  final liesInsideSelection =
      selectionStart < selectionEnd &&
      nodeStart > selectionStart &&
      nodeStart < selectionEnd;
  if (liesInsideSelection &&
      const <String>{'br', 'hr'}.contains(node.localName)) {
    return clone;
  }
  return null;
}

String _clipboardNodesMarkdown(
  Iterable<dom.Node> nodes, {
  required bool blockSeparator,
}) {
  final converted = nodes
      .map(_clipboardNodeMarkdown)
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  return converted.join(blockSeparator ? '\n\n' : '');
}

String _clipboardNodeMarkdown(dom.Node node) {
  if (node is dom.Text) return _escapeClipboardMarkdownText(node.data);
  if (node is! dom.Element) return '';
  final tag = node.localName;
  final inline = _clipboardNodesMarkdown(node.nodes, blockSeparator: false);
  return switch (tag) {
    'h1' => '# $inline',
    'h2' => '## $inline',
    'h3' => '### $inline',
    'h4' => '#### $inline',
    'h5' => '##### $inline',
    'h6' => '###### $inline',
    'p' => inline,
    'strong' || 'b' => inline.isEmpty ? '' : '**$inline**',
    'em' || 'i' => inline.isEmpty ? '' : '*$inline*',
    'del' || 's' || 'strike' => inline.isEmpty ? '' : '~~$inline~~',
    'code' => _clipboardInlineCode(node.text),
    'pre' => _clipboardFencedCode(node.text),
    'a' => _clipboardMarkdownLink(node, inline),
    'blockquote' => _clipboardMarkdownBlockquote(node),
    'ul' => _clipboardMarkdownList(node, ordered: false),
    'ol' => _clipboardMarkdownList(node, ordered: true),
    'li' => inline,
    'br' => '\n',
    'hr' => '---',
    'table' => node.outerHtml,
    'thead' || 'tbody' || 'tfoot' || 'tr' || 'th' || 'td' => inline,
    'div' ||
    'section' ||
    'article' ||
    'header' ||
    'footer' ||
    'main' ||
    'details' ||
    'summary' => _clipboardNodesMarkdown(node.nodes, blockSeparator: true),
    'u' ||
    'mark' ||
    'kbd' ||
    'small' ||
    'sup' ||
    'sub' ||
    'q' ||
    'abbr' => node.outerHtml,
    _ => inline,
  };
}

String _clipboardMarkdownLink(dom.Element element, String label) {
  final href = element.attributes['href'];
  if (href == null || href.isEmpty) return label;
  final title = element.attributes['title'];
  final escapedHref = href.replaceAll(')', r'\)');
  final suffix = title == null || title.isEmpty
      ? ''
      : ' "${title.replaceAll('"', r'\"')}"';
  return '[$label]($escapedHref$suffix)';
}

String _clipboardMarkdownBlockquote(dom.Element element) {
  final content = _clipboardNodesMarkdown(element.nodes, blockSeparator: true);
  if (content.isEmpty) return '';
  return content.split('\n').map((line) => '> $line').join('\n');
}

String _clipboardMarkdownList(dom.Element element, {required bool ordered}) {
  final items = element.children.where((child) => child.localName == 'li');
  var index = int.tryParse(element.attributes['start'] ?? '') ?? 1;
  final lines = <String>[];
  for (final item in items) {
    final content = _clipboardMarkdownListItem(item);
    if (content.isEmpty) continue;
    final prefix = ordered ? '${index++}. ' : '- ';
    final task = item.attributes[_clipboardTaskAttribute];
    final taskPrefix = task == null ? '' : '[$task] ';
    final continuation = ' ' * prefix.length;
    final indented = content.split('\n').join('\n$continuation');
    lines.add('$prefix$taskPrefix$indented');
  }
  return lines.join('\n');
}

String _clipboardMarkdownListItem(dom.Element item) {
  const blockTags = <String>{
    'blockquote',
    'div',
    'ol',
    'p',
    'pre',
    'table',
    'ul',
  };
  final chunks = <String>[];
  final inline = StringBuffer();
  void flushInline() {
    if (inline.isEmpty) return;
    chunks.add(inline.toString());
    inline.clear();
  }

  for (final node in item.nodes) {
    final converted = _clipboardNodeMarkdown(node);
    if (converted.isEmpty) continue;
    if (node is dom.Element && blockTags.contains(node.localName)) {
      flushInline();
      chunks.add(converted);
    } else {
      inline.write(converted);
    }
  }
  flushInline();
  return chunks.join('\n\n');
}

String _clipboardInlineCode(String text) {
  var fence = '`';
  while (text.contains(fence)) {
    fence += '`';
  }
  return '$fence$text$fence';
}

String _clipboardFencedCode(String text) {
  var fence = '```';
  while (text.contains(fence)) {
    fence += '`';
  }
  final content = text.endsWith('\n')
      ? text.substring(0, text.length - 1)
      : text;
  return '$fence\n$content\n$fence';
}

String _escapeClipboardMarkdownText(String text) =>
    text.replaceAllMapped(RegExp(r'[\\`*_\[\]<>]'), (match) => '\\${match[0]}');

void _sanitizeClipboardFragment(dom.DocumentFragment fragment) {
  const forbiddenElements = <String>{
    'base',
    'button',
    'embed',
    'form',
    'iframe',
    'input',
    'link',
    'meta',
    'object',
    'script',
    'select',
    'style',
    'textarea',
  };
  const allowedAttributes = <String>{
    'align',
    'checked',
    'class',
    'colspan',
    'height',
    'href',
    'rowspan',
    'start',
    'title',
    'type',
    'width',
    _clipboardTaskAttribute,
  };

  for (final element in fragment.querySelectorAll('*').toList()) {
    final name = element.localName;
    if (name == 'img') {
      element.replaceWith(dom.Text(element.attributes['alt'] ?? ''));
      continue;
    }
    if (forbiddenElements.contains(name)) {
      element.remove();
      continue;
    }
    element.attributes.removeWhere(
      (attribute, _) => !allowedAttributes.contains(attribute),
    );
    final href = element.attributes['href'];
    if (href != null && !_isSafeClipboardLink(href)) {
      element.attributes.remove('href');
    }
  }
}

bool _isSafeClipboardLink(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || !uri.hasScheme) return uri != null;
  return const <String>{
    'ftp',
    'http',
    'https',
    'mailto',
    'obsidian',
  }.contains(uri.scheme.toLowerCase());
}
