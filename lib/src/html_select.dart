import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'theme.dart';

class IanvsMarkdownHtmlSelectSyntax extends md.BlockSyntax {
  const IanvsMarkdownHtmlSelectSyntax();

  static final RegExp _line = RegExp(
    r'^ {0,3}<select(?:\s[^>\n]*)?>(.*?)</select\s*>[ \t]*$',
    caseSensitive: false,
  );
  static final RegExp _option = RegExp(
    r'<option([^>]*)>(.*?)</option\s*>',
    caseSensitive: false,
  );

  @override
  RegExp get pattern => _line;

  @override
  md.Node parse(md.BlockParser parser) {
    final match = _line.firstMatch(parser.current.content)!;
    parser.advance();
    final options = <Map<String, Object>>[];
    for (final option in _option.allMatches(match.group(1) ?? '')) {
      options.add(<String, Object>{
        'label': option.group(2) ?? '',
        'selected': RegExp(
          r'(?:^|\s)selected(?:\s|=|$)',
          caseSensitive: false,
        ).hasMatch(option.group(1) ?? ''),
      });
    }
    return md.Element.empty('ianvs-html-select')
      ..attributes['data-options'] = jsonEncode(options);
  }
}

class IanvsMarkdownHtmlSelectBuilder extends MarkdownElementBuilder {
  IanvsMarkdownHtmlSelectBuilder({this.theme});
  final IanvsMarkdownThemeData? theme;
  @override
  bool isBlockElement() => true;
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final parsed =
        jsonDecode(element.attributes['data-options'] ?? '[]') as List<Object?>;
    return IanvsMarkdownHtmlSelect(
      options: parsed
          .whereType<Map<Object?, Object?>>()
          .map(
            (item) => IanvsMarkdownHtmlSelectOption(
              label: item['label'] as String? ?? '',
              selected: item['selected'] == true,
            ),
          )
          .toList(growable: false),
      theme: theme,
    );
  }
}

class IanvsMarkdownHtmlSelectOption {
  const IanvsMarkdownHtmlSelectOption({
    required this.label,
    required this.selected,
  });
  final String label;
  final bool selected;
}

class IanvsMarkdownHtmlSelect extends StatefulWidget {
  const IanvsMarkdownHtmlSelect({super.key, required this.options, this.theme});
  final List<IanvsMarkdownHtmlSelectOption> options;
  final IanvsMarkdownThemeData? theme;
  @override
  State<IanvsMarkdownHtmlSelect> createState() =>
      _IanvsMarkdownHtmlSelectState();
}

class _IanvsMarkdownHtmlSelectState extends State<IanvsMarkdownHtmlSelect> {
  late int _selected = _initialIndex();
  int _initialIndex() {
    final selected = widget.options.indexWhere((option) => option.selected);
    return selected < 0 ? 0 : selected;
  }

  @override
  void didUpdateWidget(covariant IanvsMarkdownHtmlSelect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options != widget.options) _selected = _initialIndex();
  }

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context, widget.theme);
    if (widget.options.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('ianvs-markdown-html-select'),
      height: 22,
      padding: const EdgeInsets.only(left: 6, right: 3),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        border: Border.all(color: colors.taskCheckboxBorderColor),
        borderRadius: BorderRadius.circular(2),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _selected,
          isDense: true,
          dropdownColor: colors.surfaceMuted,
          style: TextStyle(color: colors.textPrimary, fontSize: 12),
          items: [
            for (var i = 0; i < widget.options.length; i += 1)
              DropdownMenuItem(value: i, child: Text(widget.options[i].label)),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _selected = value);
          },
        ),
      ),
    );
  }
}
