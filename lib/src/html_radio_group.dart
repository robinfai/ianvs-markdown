import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'theme.dart';

enum IanvsMarkdownHtmlRadioGroupPresentation { reading, editing }

/// Parses a contiguous HTML radio group into one source-preserving view model.
///
/// Obsidian projects these controls in both Reading and Live Preview. The
/// sampled Live Preview starts with no local selection, while Reading honors
/// the source `checked` attribute. Interactions never rewrite the Markdown.
class IanvsMarkdownHtmlRadioGroupSyntax extends md.BlockSyntax {
  const IanvsMarkdownHtmlRadioGroupSyntax();

  static final RegExp _line = RegExp(
    r'^ {0,3}<input\b([^>\n]*)/?>[ \t]*(.*)$',
    caseSensitive: false,
  );
  static final RegExp _typeRadio = RegExp(
    r'''\btype\s*=\s*(?:"radio"|'radio'|radio)(?:\s|/|$)''',
    caseSensitive: false,
  );
  static final RegExp _checked = RegExp(
    r'(?:^|\s)checked(?:\s|=|$)',
    caseSensitive: false,
  );

  @override
  RegExp get pattern => _line;

  @override
  bool canParse(md.BlockParser parser) =>
      super.canParse(parser) && _parseLine(parser.current.content) != null;

  @override
  md.Node parse(md.BlockParser parser) {
    final first = _parseLine(parser.current.content)!;
    final groupName = first.name;
    final items = <_ParsedRadioLine>[first];
    parser.advance();

    // Unnamed radios are independent HTML controls. Named, physically
    // adjacent radios form the sampled mutual-exclusion group.
    if (groupName.isNotEmpty) {
      while (!parser.isDone) {
        final next = _parseLine(parser.current.content);
        if (next == null || next.name != groupName) break;
        items.add(next);
        parser.advance();
      }
    }

    return md.Element.empty('ianvs-html-radio-group')
      ..attributes['data-items'] = jsonEncode(<Map<String, Object>>[
        for (final item in items)
          <String, Object>{
            'name': item.name,
            'label': item.label,
            'checked': item.checked,
          },
      ]);
  }

  static _ParsedRadioLine? _parseLine(String source) {
    final match = _line.firstMatch(source);
    if (match == null) return null;
    final attributes = match.group(1) ?? '';
    if (!_typeRadio.hasMatch(attributes)) return null;
    return _ParsedRadioLine(
      name: _attribute(attributes, 'name') ?? '',
      label: match.group(2) ?? '',
      checked: _checked.hasMatch(attributes),
    );
  }

  static String? _attribute(String source, String name) {
    final match = RegExp(
      '''\\b${RegExp.escape(name)}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s"'=<>`]+))''',
      caseSensitive: false,
    ).firstMatch(source);
    return match?.group(1) ?? match?.group(2) ?? match?.group(3);
  }
}

class _ParsedRadioLine {
  const _ParsedRadioLine({
    required this.name,
    required this.label,
    required this.checked,
  });

  final String name;
  final String label;
  final bool checked;
}

class IanvsMarkdownHtmlRadioGroupBuilder extends MarkdownElementBuilder {
  IanvsMarkdownHtmlRadioGroupBuilder({required this.presentation, this.theme});

  final IanvsMarkdownHtmlRadioGroupPresentation presentation;
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
    final decoded =
        jsonDecode(element.attributes['data-items'] ?? '[]') as List<Object?>;
    return IanvsMarkdownHtmlRadioGroup(
      items: decoded
          .whereType<Map<Object?, Object?>>()
          .map(
            (item) => IanvsMarkdownHtmlRadioItem(
              name: item['name'] as String? ?? '',
              label: item['label'] as String? ?? '',
              checked: item['checked'] == true,
            ),
          )
          .toList(growable: false),
      honorSourceSelection:
          presentation == IanvsMarkdownHtmlRadioGroupPresentation.reading,
      theme: theme,
    );
  }
}

@immutable
class IanvsMarkdownHtmlRadioItem {
  const IanvsMarkdownHtmlRadioItem({
    required this.name,
    required this.label,
    required this.checked,
  });

  final String name;
  final String label;
  final bool checked;

  @override
  bool operator ==(Object other) =>
      other is IanvsMarkdownHtmlRadioItem &&
      other.name == name &&
      other.label == label &&
      other.checked == checked;

  @override
  int get hashCode => Object.hash(name, label, checked);
}

/// A compact, view-local HTML radio group matching Obsidian's projection.
class IanvsMarkdownHtmlRadioGroup extends StatefulWidget {
  const IanvsMarkdownHtmlRadioGroup({
    super.key,
    required this.items,
    required this.honorSourceSelection,
    this.theme,
  });

  final List<IanvsMarkdownHtmlRadioItem> items;
  final bool honorSourceSelection;
  final IanvsMarkdownThemeData? theme;

  @override
  State<IanvsMarkdownHtmlRadioGroup> createState() =>
      _IanvsMarkdownHtmlRadioGroupState();
}

class _IanvsMarkdownHtmlRadioGroupState
    extends State<IanvsMarkdownHtmlRadioGroup> {
  late int? _selected = _initialSelection();
  late List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _focusNodes = _createFocusNodes();
  }

  List<FocusNode> _createFocusNodes() => List<FocusNode>.generate(
    widget.items.length,
    (index) => FocusNode(debugLabel: 'Ianvs Markdown HTML radio ${index + 1}'),
    growable: false,
  );

  @override
  void dispose() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  int? _initialSelection() {
    if (!widget.honorSourceSelection) return null;
    final selected = widget.items.indexWhere((item) => item.checked);
    return selected < 0 ? null : selected;
  }

  @override
  void didUpdateWidget(covariant IanvsMarkdownHtmlRadioGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.honorSourceSelection != widget.honorSourceSelection ||
        !listEquals(oldWidget.items, widget.items)) {
      _selected = _initialSelection();
      if (oldWidget.items.length != widget.items.length) {
        for (final node in _focusNodes) {
          node.dispose();
        }
        _focusNodes = _createFocusNodes();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context, widget.theme);
    return RadioGroup<int>(
      key: const ValueKey('ianvs-markdown-html-radio-group'),
      groupValue: _selected,
      onChanged: (value) => setState(() => _selected = value),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (var index = 0; index < widget.items.length; index += 1)
            _RadioRow(
              index: index,
              label: widget.items[index].label,
              colors: colors,
              focusNode: _focusNodes[index],
            ),
        ],
      ),
    );
  }
}

class _RadioRow extends StatelessWidget {
  const _RadioRow({
    required this.index,
    required this.label,
    required this.colors,
    required this.focusNode,
  });

  final int index;
  final String label;
  final IanvsMarkdownThemeData colors;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 22,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (focusNode.canRequestFocus) focusNode.requestFocus();
            });
          },
          child: SizedBox(
            width: 13,
            height: 13,
            child: Radio<int>(
              key: ValueKey('ianvs-markdown-html-radio-$index'),
              value: index,
              focusNode: focusNode,
              activeColor: colors.accent,
              fillColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? colors.accent
                    : colors.taskCheckboxBorderColor,
              ),
              side: BorderSide(color: colors.taskCheckboxBorderColor, width: 1),
              innerRadius: const WidgetStatePropertyAll<double>(3),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              splashRadius: 8,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            height: 1.55,
          ),
        ),
      ],
    ),
  );
}
