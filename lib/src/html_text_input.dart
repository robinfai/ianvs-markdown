import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'theme.dart';

/// Parses a standalone HTML text input and its trailing visual label.
class IanvsMarkdownHtmlTextInputSyntax extends md.BlockSyntax {
  const IanvsMarkdownHtmlTextInputSyntax();

  static final RegExp _line = RegExp(
    r'^ {0,3}<input\b([^>\n]*)/?>[ \t]*(.*)$',
    caseSensitive: false,
  );
  static final RegExp _typeText = RegExp(
    r'''\btype\s*=\s*(?:"text"|'text'|text)(?:\s|/|$)''',
    caseSensitive: false,
  );

  @override
  RegExp get pattern => _line;

  @override
  bool canParse(md.BlockParser parser) {
    if (!super.canParse(parser)) return false;
    final match = _line.firstMatch(parser.current.content);
    return match != null && _typeText.hasMatch(match.group(1) ?? '');
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final match = _line.firstMatch(parser.current.content)!;
    parser.advance();
    final attributes = match.group(1) ?? '';
    return md.Element.empty('ianvs-html-text-input')
      ..attributes.addAll({
        'data-label': match.group(2) ?? '',
        'value': _attribute(attributes, 'value') ?? '',
        'placeholder': _attribute(attributes, 'placeholder') ?? '',
      });
  }

  static String? _attribute(String source, String name) {
    final match = RegExp(
      '''\\b${RegExp.escape(name)}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s"'=<>`]+))''',
      caseSensitive: false,
    ).firstMatch(source);
    return match?.group(1) ?? match?.group(2) ?? match?.group(3);
  }
}

class IanvsMarkdownHtmlTextInputBuilder extends MarkdownElementBuilder {
  IanvsMarkdownHtmlTextInputBuilder({this.theme});

  final IanvsMarkdownThemeData? theme;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => IanvsMarkdownHtmlTextInput(
    value: element.attributes['value'] ?? '',
    placeholder: element.attributes['placeholder'] ?? '',
    label: element.attributes['data-label'] ?? '',
    theme: theme,
  );
}

/// Obsidian-style compact single-line input whose edits are view-local state.
class IanvsMarkdownHtmlTextInput extends StatefulWidget {
  const IanvsMarkdownHtmlTextInput({
    super.key,
    required this.value,
    required this.placeholder,
    required this.label,
    this.theme,
  });

  final String value;
  final String placeholder;
  final String label;
  final IanvsMarkdownThemeData? theme;

  @override
  State<IanvsMarkdownHtmlTextInput> createState() =>
      _IanvsMarkdownHtmlTextInputState();
}

class _IanvsMarkdownHtmlTextInputState
    extends State<IanvsMarkdownHtmlTextInput> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focusNode = FocusNode(
    debugLabel: 'Ianvs Markdown HTML text input',
  );

  @override
  void didUpdateWidget(covariant IanvsMarkdownHtmlTextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A presentation-only rebuild keeps the same source value and therefore
    // preserves the local edit, matching Obsidian's Reading/Live Preview swap.
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context, widget.theme);
    return Row(
      key: const ValueKey('ianvs-markdown-html-text-input-row'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SizedBox(
          key: const ValueKey('ianvs-markdown-html-text-input'),
          width: 128,
          height: 20,
          child: CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.keyA, meta: true):
                  _selectAll,
            },
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              textAlignVertical: TextAlignVertical.center,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 12,
                height: 1,
              ),
              decoration: InputDecoration(
                isDense: true,
                isCollapsed: true,
                hintText: widget.placeholder,
                hintStyle: TextStyle(color: colors.textTertiary, fontSize: 12),
                contentPadding: const EdgeInsets.fromLTRB(4, 4, 3, 3),
                filled: true,
                fillColor: colors.surfaceMuted,
                border: _border(colors.taskCheckboxBorderColor),
                enabledBorder: _border(colors.taskCheckboxBorderColor),
                focusedBorder: _border(colors.accent),
              ),
            ),
          ),
        ),
        if (widget.label.isNotEmpty) ...<Widget>[
          const SizedBox(width: 4),
          Text(
            widget.label,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              height: 1.55,
            ),
          ),
        ],
      ],
    );
  }

  OutlineInputBorder _border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(2),
    borderSide: BorderSide(color: color, width: 1),
  );

  void _selectAll() {
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }
}
