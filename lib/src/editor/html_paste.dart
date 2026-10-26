import 'package:flutter/services.dart';
import 'markdown_paste.dart';
import 'package:html/dom.dart' as html;
import 'package:html/parser.dart' as parser;

/// Converts a bounded clipboard HTML fragment into editable Markdown.
/// Returns null when faithful conversion is unsupported, allowing plain text
/// fallback. Never fetches resources or preserves executable HTML.
String? markdownFromClipboardHtml(String source) {
  if (source.isEmpty || source.length > 1024 * 1024) return null;
  final converter = _ClipboardHtmlConverter();
  final fragment = parser.parseFragment(source);
  final result = converter.nodes(fragment.nodes, 0).trim();
  return converter.unsupported || !converter.structured || result.isEmpty
      ? null
      : result;
}

class _ClipboardHtmlConverter {
  bool unsupported = false;
  bool structured = false;

  String escape(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAllMapped(RegExp(r'[\\`*_{}\[\]()#+.!|~\-]'), (m) => '\\${m[0]}');

  String nodes(List<html.Node> children, int depth) =>
      children.map((child) => node(child, depth)).join();

  String block(String value) => '\n\n${value.trim()}\n\n';

  String node(html.Node node, int depth) {
    if (depth > 100) {
      unsupported = true;
      return '';
    }
    if (node is html.Text) {
      return escape(node.data.replaceAll(RegExp(r'\s+'), ' '));
    }
    if (node is! html.Element) return '';
    final tag = node.localName;
    if (const {
      'script',
      'style',
      'head',
      'noscript',
      'template',
      'iframe',
      'object',
    }.contains(tag)) {
      return '';
    }
    if (node.attributes.containsKey('hidden')) return '';
    if (tag == 'pre') {
      structured = true;
      final text = node.text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      var fenceLength = 3;
      for (final run in RegExp(r'`+').allMatches(text)) {
        if (run.end - run.start >= fenceLength) {
          fenceLength = run.end - run.start + 1;
        }
      }
      final fence = List.filled(fenceLength, '`').join();
      final code = node.querySelector('code');
      final language =
          RegExp(
            r'(?:^|\s)language-([A-Za-z0-9_+\-]+)(?:\s|$)',
          ).firstMatch(code?.attributes['class'] ?? '')?.group(1) ??
          '';
      return block(
        '$fence$language\n$text${text.endsWith('\n') ? '' : '\n'}$fence',
      );
    }
    if (tag == 'table') return table(node, depth + 1);
    if (tag == 'ul' || tag == 'ol') {
      structured = true;
      var number = int.tryParse(node.attributes['start'] ?? '') ?? 1;
      final items = <String>[];
      for (final item in node.children.where((e) => e.localName == 'li')) {
        final marker = tag == 'ol' ? '${number++}. ' : '- ';
        final content = nodes(item.nodes, depth + 1).trim();
        final lines = content.split('\n');
        items.add(
          '$marker${lines.first}${lines.skip(1).map((line) => '\n${' ' * marker.length}$line').join()}',
        );
      }
      return block(items.join('\n'));
    }
    final content = nodes(node.nodes, depth + 1);
    switch (tag) {
      case 'p':
      case 'div':
      case 'section':
      case 'article':
        structured = true;
        return block(content);
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        structured = true;
        return block('${'#' * int.parse(tag![1])} ${content.trim()}');
      case 'br':
        return '<br>';
      case 'hr':
        structured = true;
        return block('---');
      case 'blockquote':
        structured = true;
        return block(
          content.trim().split('\n').map((line) => '> $line').join('\n'),
        );
      case 'strong':
      case 'b':
        structured = true;
        return wrapInline(content, '**');
      case 'em':
      case 'i':
        structured = true;
        return wrapInline(content, '*');
      case 's':
      case 'del':
        structured = true;
        return wrapInline(content, '~~');
      case 'code':
        structured = true;
        final text = node.text.replaceAll(RegExp(r'\r\n|\r|\n'), ' ');
        if (text.isEmpty) return '';
        var longest = 0;
        for (final run in RegExp(r'`+').allMatches(text)) {
          if (run.end - run.start > longest) longest = run.end - run.start;
        }
        final fence = '`' * (longest + 1);
        // CommonMark removes one padding space only for non-blank code.
        final padding = text.trim().isEmpty ? '' : ' ';
        return '$fence$padding$text$padding$fence';
      case 'a':
        structured = true;
        final href = node.attributes['href']?.trim();
        final uri = href == null ? null : Uri.tryParse(href);
        if (uri == null ||
            !const {
              'http',
              'https',
              'mailto',
            }.contains(uri.scheme.toLowerCase())) {
          return content;
        }
        final target = uri
            .toString()
            .replaceAll('<', '%3C')
            .replaceAll('>', '%3E');
        final label = content.trim();
        if (label.isEmpty) return content;
        final start = content.indexOf(label);
        return '${content.substring(0, start)}[$label](<$target>)${content.substring(start + label.length)}';
      case 'img':
        // Clipboard images require the host's attachment import pipeline.
        unsupported = true;
        return '';
      default:
        return content;
    }
  }

  String wrapInline(String content, String marker) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return content;
    final start = content.indexOf(trimmed);
    return '${content.substring(0, start)}$marker$trimmed$marker${content.substring(start + trimmed.length)}';
  }

  String table(html.Element element, int depth) {
    structured = true;
    if (element.querySelector('pre') != null ||
        element.querySelector('table') != null) {
      unsupported = true;
      return '';
    }
    final rows = <List<String>>[];
    for (final row in element.querySelectorAll('tr')) {
      final cells = row.children
          .where((e) => e.localName == 'td' || e.localName == 'th')
          .toList();
      if (cells.isEmpty) continue;
      if (cells.any(
        (cell) =>
            (cell.attributes['colspan'] ?? '1') != '1' ||
            (cell.attributes['rowspan'] ?? '1') != '1',
      )) {
        unsupported = true;
        return '';
      }
      rows.add(
        cells
            .map(
              (cell) => nodes(cell.nodes, depth + 1)
                  .trim()
                  .replaceAll(RegExp(r'\n+'), '<br>')
                  .replaceAllMapped(RegExp(r'(?<!\\)\|'), (_) => r'\|'),
            )
            .toList(),
      );
    }
    if (rows.isEmpty ||
        rows.any((row) => row.length != rows.first.length) ||
        element.querySelector('table') != null) {
      unsupported = true;
      return '';
    }
    String line(List<String> row) => '| ${row.join(' | ')} |';
    return block(
      [
        line(rows.first),
        '| ${List.filled(rows.first.length, '---').join(' | ')} |',
        ...rows.skip(1).map(line),
      ].join('\n'),
    );
  }
}

/// Prepares one HTML clipboard insertion without mutating editor state.
/// Returns null for unsupported HTML or a code/structured editing context;
/// the host should retain the same clipboard item's plain-text representation.
TextEditingValue? ianvsMarkdownHtmlPasteValue(
  TextEditingValue value,
  String html,
) {
  final markdown = markdownFromClipboardHtml(html);
  return markdown == null ? null : markdownBlockPasteValue(value, markdown);
}
