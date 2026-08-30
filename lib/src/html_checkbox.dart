import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'task_checkbox.dart';
import 'theme.dart';

/// Parses Obsidian's standalone HTML checkbox-input lines.
///
/// The sampled `input type="checkbox"` controls are stateful view widgets:
/// toggling one changes only the current rendered control and never rewrites
/// the `checked` attribute in source. This intentionally accepts only a whole
/// physical line beginning with the safe checkbox form.
class IanvsMarkdownHtmlCheckboxSyntax extends md.BlockSyntax {
  const IanvsMarkdownHtmlCheckboxSyntax();

  static final RegExp _line = RegExp(
    r'^ {0,3}<input\b([^>\n]*)>[ \t]*(.*)$',
    caseSensitive: false,
  );
  static final RegExp _typeCheckbox = RegExp(
    r'''\btype\s*=\s*(["'])checkbox\1''',
    caseSensitive: false,
  );
  static final RegExp _checked = RegExp(
    r'(?:^|\s)checked(?:\s|=|$)',
    caseSensitive: false,
  );

  @override
  RegExp get pattern => _line;

  @override
  bool canParse(md.BlockParser parser) {
    if (!super.canParse(parser)) return false;
    final match = _line.firstMatch(parser.current.content);
    return match != null && _typeCheckbox.hasMatch(match.group(1) ?? '');
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final match = _line.firstMatch(parser.current.content)!;
    parser.advance();
    final attributes = match.group(1) ?? '';
    return md.Element.empty('ianvs-html-checkbox')
      ..attributes['data-checked'] = _checked.hasMatch(attributes)
          ? 'true'
          : 'false'
      ..attributes['data-label'] = match.group(2) ?? '';
  }
}

class IanvsMarkdownHtmlCheckboxBuilder extends MarkdownElementBuilder {
  IanvsMarkdownHtmlCheckboxBuilder({this.theme});

  final IanvsMarkdownThemeData? theme;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => IanvsMarkdownHtmlCheckbox(
    checked: element.attributes['data-checked'] == 'true',
    label: element.attributes['data-label'] ?? '',
    theme: theme,
  );
}

/// A source-preserving HTML checkbox whose checked state is view-local.
class IanvsMarkdownHtmlCheckbox extends StatefulWidget {
  const IanvsMarkdownHtmlCheckbox({
    super.key,
    required this.checked,
    required this.label,
    this.theme,
  });

  final bool checked;
  final String label;
  final IanvsMarkdownThemeData? theme;

  @override
  State<IanvsMarkdownHtmlCheckbox> createState() =>
      _IanvsMarkdownHtmlCheckboxState();
}

class _IanvsMarkdownHtmlCheckboxState extends State<IanvsMarkdownHtmlCheckbox> {
  late bool _checked = widget.checked;

  @override
  void didUpdateWidget(covariant IanvsMarkdownHtmlCheckbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.checked != widget.checked) _checked = widget.checked;
  }

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context, widget.theme);
    return Row(
      key: const ValueKey('ianvs-markdown-html-checkbox'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SizedBox(
          width: IanvsMarkdownTaskCheckbox.size,
          height: IanvsMarkdownTaskCheckbox.layoutSize,
          child: Transform.translate(
            offset: const Offset(-4, 0),
            child: IanvsMarkdownTaskCheckbox(
              value: _checked,
              onChanged: (value) => setState(() => _checked = value),
              theme: colors,
            ),
          ),
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: Text(
              widget.label,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14,
                height: 1.55,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
