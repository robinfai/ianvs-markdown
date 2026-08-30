import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

typedef IanvsMarkdownHtmlDefinitionListItemBuilder =
    Widget Function(BuildContext context, String source);

/// Parses Obsidian's line-delimited HTML definition-list form.
///
/// Obsidian hides every `dl`, `dt`, and `dd` tag while retaining ordinary text
/// lines. Definition rows are inset; term rows are not. This syntactic subset
/// deliberately leaves the whole rendered block passive so Live Preview can
/// enter the exact original HTML source on a normal click.
class IanvsMarkdownHtmlDefinitionListSyntax extends md.BlockSyntax {
  const IanvsMarkdownHtmlDefinitionListSyntax();

  static final RegExp _open = RegExp(
    r'^ {0,3}<dl(?:\s[^>\n]*)?>[ \t]*$',
    caseSensitive: false,
  );
  static final RegExp _close = RegExp(
    r'^ {0,3}</dl\s*>[ \t]*$',
    caseSensitive: false,
  );
  static final RegExp _item = RegExp(
    r'^ {0,3}<(dt|dd)(?:\s[^>\n]*)?>(.*?)</\1\s*>[ \t]*$',
    caseSensitive: false,
  );

  @override
  RegExp get pattern => _open;

  @override
  bool canParse(md.BlockParser parser) {
    if (!super.canParse(parser)) return false;
    var foundItem = false;
    for (var offset = 1; ; offset += 1) {
      final line = parser.peek(offset);
      if (line == null) return false;
      foundItem = foundItem || _item.hasMatch(line.content);
      if (_close.hasMatch(line.content)) return foundItem;
    }
  }

  @override
  md.Node parse(md.BlockParser parser) {
    parser.advance();
    final items = <IanvsMarkdownHtmlDefinitionListItem>[];
    while (!parser.isDone && !_close.hasMatch(parser.current.content)) {
      final match = _item.firstMatch(parser.current.content);
      if (match != null) {
        items.add(
          IanvsMarkdownHtmlDefinitionListItem(
            definition: match.group(1)!.toLowerCase() == 'dd',
            source: (match.group(2) ?? '').trim(),
          ),
        );
      }
      parser.advance();
    }
    if (!parser.isDone) parser.advance();
    return md.Element.empty('ianvs-html-definition-list')
      ..attributes['data-items'] = jsonEncode(
        items
            .map(
              (item) => <String, Object>{
                'definition': item.definition,
                'source': item.source,
              },
            )
            .toList(growable: false),
      );
  }
}

class IanvsMarkdownHtmlDefinitionListItem {
  const IanvsMarkdownHtmlDefinitionListItem({
    required this.definition,
    required this.source,
  });

  final bool definition;
  final String source;
}

class IanvsMarkdownHtmlDefinitionListBuilder extends MarkdownElementBuilder {
  IanvsMarkdownHtmlDefinitionListBuilder({required this.itemBuilder});

  final IanvsMarkdownHtmlDefinitionListItemBuilder itemBuilder;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final rawItems = jsonDecode(element.attributes['data-items'] ?? '[]');
    final items = (rawItems as List<Object?>)
        .whereType<Map<Object?, Object?>>()
        .map(
          (item) => IanvsMarkdownHtmlDefinitionListItem(
            definition: item['definition'] == true,
            source: item['source'] as String? ?? '',
          ),
        )
        .toList(growable: false);
    return IanvsMarkdownHtmlDefinitionList(
      items: items,
      itemBuilder: itemBuilder,
    );
  }
}

class IanvsMarkdownHtmlDefinitionList extends StatelessWidget {
  const IanvsMarkdownHtmlDefinitionList({
    super.key,
    required this.items,
    required this.itemBuilder,
  });

  final List<IanvsMarkdownHtmlDefinitionListItem> items;
  final IanvsMarkdownHtmlDefinitionListItemBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('ianvs-markdown-html-definition-list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < items.length; index += 1)
          Padding(
            key: ValueKey(
              'ianvs-markdown-html-definition-list-${items[index].definition ? 'dd' : 'dt'}-$index',
            ),
            padding: EdgeInsets.only(left: items[index].definition ? 28 : 0),
            child: itemBuilder(context, items[index].source),
          ),
      ],
    );
  }
}
