import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:markdown/markdown.dart' as md;
import 'package:super_clipboard/super_clipboard.dart';

/// The two representations written by every Reading-mode copy operation.
final class IanvsMarkdownClipboardData {
  const IanvsMarkdownClipboardData({
    required this.markdown,
    required this.html,
  });

  /// Markdown-compatible plain text.
  ///
  /// A whole-document selection preserves the exact original Markdown source;
  /// a partial visual selection is re-serialized from the selected semantic
  /// Markdown fragment so inline and block formatting remain available.
  final String markdown;

  /// A safe semantic HTML representation for rich-text paste targets.
  final String html;
}

/// Writes Markdown and rich HTML representations to the system clipboard.
typedef IanvsMarkdownClipboardWriter =
    Future<void> Function(IanvsMarkdownClipboardData data);

/// Default clipboard writer used by Reading mode.
///
/// Platforms without multi-format clipboard support fall back to Flutter's
/// plain-text clipboard API, so copying remains functional.
Future<void> writeIanvsMarkdownClipboard(
  IanvsMarkdownClipboardData data,
) async {
  try {
    final clipboard = SystemClipboard.instance;
    if (clipboard != null) {
      // Keep both representations on the same pasteboard item so the paste
      // target can choose semantic HTML or Markdown-compatible plain text.
      final item = DataWriterItem()
        ..add(Formats.plainText(data.markdown))
        ..add(Formats.htmlText(data.html));
      await clipboard.write(<DataWriterItem>[item]);
      return;
    }
  } on Object {
    // Missing or unavailable native clipboard plugins must not make Copy fail.
  }
  await Clipboard.setData(ClipboardData(text: data.markdown));
}

/// Converts Markdown to a safe HTML clipboard fragment.
String ianvsMarkdownClipboardHtml(String markdown) {
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
}) {
  if (selectedText.isEmpty) {
    return const IanvsMarkdownClipboardData(markdown: '', html: '');
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
