import 'package:flutter/widgets.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

typedef IanvsMarkdownHtmlTableBodyBuilder =
    Widget Function(BuildContext context, String markdown);

/// Parses the simple line-delimited HTML table form rendered by Obsidian.
///
/// The safe projection accepts table rows with `th`/`td` cells on a single
/// source line. It converts only the presentation copy to GFM so the existing
/// table renderer handles grids, header emphasis, equal columns, and padding;
/// the original HTML source remains untouched by the live editor.
class IanvsMarkdownHtmlTableSyntax extends md.BlockSyntax {
  const IanvsMarkdownHtmlTableSyntax();

  static final RegExp _open = RegExp(
    r'^ {0,3}<table(?:\s[^>\n]*)?>[ \t]*$',
    caseSensitive: false,
  );
  static final RegExp _close = RegExp(
    r'^ {0,3}</table\s*>[ \t]*$',
    caseSensitive: false,
  );
  static final RegExp _row = RegExp(
    r'^ {0,3}<tr(?:\s[^>\n]*)?>(.*?)</tr\s*>[ \t]*$',
    caseSensitive: false,
  );
  static final RegExp _cell = RegExp(
    r'<t([hd])(?:\s[^>\n]*)?>(.*?)</t\1\s*>',
    caseSensitive: false,
  );

  @override
  RegExp get pattern => _open;

  @override
  bool canParse(md.BlockParser parser) {
    if (!super.canParse(parser)) return false;
    var foundRow = false;
    for (var offset = 1; ; offset += 1) {
      final line = parser.peek(offset);
      if (line == null) return false;
      foundRow = foundRow || _row.hasMatch(line.content);
      if (_close.hasMatch(line.content)) return foundRow;
    }
  }

  @override
  md.Node parse(md.BlockParser parser) {
    parser.advance();
    final rows = <_IanvsMarkdownHtmlTableRow>[];
    while (!parser.isDone && !_close.hasMatch(parser.current.content)) {
      final row = _parseRow(parser.current.content);
      if (row != null) rows.add(row);
      parser.advance();
    }
    if (!parser.isDone) parser.advance();
    return md.Element.empty('ianvs-html-table')
      ..attributes['data-markdown'] = _toMarkdown(rows);
  }

  _IanvsMarkdownHtmlTableRow? _parseRow(String line) {
    final rowMatch = _row.firstMatch(line);
    if (rowMatch == null) return null;
    final cells = <String>[];
    var firstCellHeader = false;
    for (final match in _cell.allMatches(rowMatch.group(1)!)) {
      if (cells.isEmpty) firstCellHeader = match.group(1)!.toLowerCase() == 'h';
      cells.add((match.group(2) ?? '').trim().replaceAll('|', r'\|'));
    }
    return cells.isEmpty
        ? null
        : _IanvsMarkdownHtmlTableRow(cells: cells, header: firstCellHeader);
  }

  String _toMarkdown(List<_IanvsMarkdownHtmlTableRow> rows) {
    if (rows.isEmpty) return '';
    final columnCount = rows.fold<int>(
      0,
      (maximum, row) => row.cells.length > maximum ? row.cells.length : maximum,
    );
    if (columnCount == 0) return '';
    final normalized = rows
        .map(
          (row) => <String>[
            ...row.cells,
            ...List<String>.filled(columnCount - row.cells.length, ''),
          ],
        )
        .toList();
    final headerIndex = rows.indexWhere((row) => row.header);
    final header = headerIndex < 0
        ? normalized.first
        : normalized.removeAt(headerIndex);
    final body = normalized;
    final lines = <String>[
      '| ${header.join(' | ')} |',
      '| ${List<String>.filled(columnCount, '---').join(' | ')} |',
      ...body.map((cells) => '| ${cells.join(' | ')} |'),
    ];
    return lines.join('\n');
  }
}

class _IanvsMarkdownHtmlTableRow {
  const _IanvsMarkdownHtmlTableRow({required this.cells, required this.header});

  final List<String> cells;
  final bool header;
}

class IanvsMarkdownHtmlTableBuilder extends MarkdownElementBuilder {
  IanvsMarkdownHtmlTableBuilder({required this.bodyBuilder});

  final IanvsMarkdownHtmlTableBodyBuilder bodyBuilder;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => bodyBuilder(context, element.attributes['data-markdown'] ?? '');
}
