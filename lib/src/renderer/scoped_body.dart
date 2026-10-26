// Copyright 2013 The Flutter Authors. All rights reserved.
// BSD license: LICENSE.flutter_markdown_plus in this directory.
// State bridge derived from flutter_markdown_plus 1.0.12's widget.dart.

import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../editor/editor_diagnostics.dart';
import '../link_target.dart';
import 'fallback_style_io.dart'
    if (dart.library.js_interop) 'fallback_style_web.dart';
import 'scoped_builder.dart';
import 'source_mapped_document.dart';
import 'source_regions.dart';

/// Internal body using the same public builder/style contracts with per-build
/// block registration. Not part of the component's public exports.
class ScopedMarkdownBody extends MarkdownBody {
  const ScopedMarkdownBody({
    super.key,
    required super.data,
    required MarkdownImageBuilder imageBuilder,
    super.selectable,
    super.styleSheet,
    super.styleSheetTheme,
    super.syntaxHighlighter,
    super.onSelectionChanged,
    super.onTapLink,
    this.onTapLinkTarget,
    super.onTapText,
    super.contextMenuBuilder,
    super.imageDirectory,
    super.blockSyntaxes,
    super.inlineSyntaxes,
    super.extensionSet,
    super.checkboxBuilder,
    super.bulletBuilder,
    super.builders,
    super.paddingBuilders,
    super.listItemCrossAxisAlignment,
    super.shrinkWrap,
    super.fitContent,
    super.softLineBreak,
  }) : super(imageBuilder: imageBuilder);

  final IanvsMarkdownTapLinkTargetCallback? onTapLinkTarget;

  @override
  State<ScopedMarkdownBody> createState() => _ScopedMarkdownBodyState();

  Widget _buildBody(BuildContext context, List<Widget>? children) =>
      super.build(context, children);
}

class _ScopedMarkdownBodyState extends State<ScopedMarkdownBody>
    implements ScopedMarkdownBuilderDelegate {
  List<Widget>? _children;
  final _recognizers = <GestureRecognizer>[];
  MarkdownSourceRegions? _sourceRegions;

  @override
  void didChangeDependencies() {
    _sourceRegions = MarkdownSourceRegionScope.of(context);
    _parseMarkdown();
    super.didChangeDependencies();
  }

  @override
  void didUpdateWidget(ScopedMarkdownBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.data != oldWidget.data ||
        widget.styleSheet != oldWidget.styleSheet ||
        widget.onTapLinkTarget != oldWidget.onTapLinkTarget ||
        widget.onTapLink != oldWidget.onTapLink) {
      _parseMarkdown();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _parseMarkdown() {
    final fallback = kFallbackStyle(context, widget.styleSheetTheme);
    final styleSheet = fallback.merge(widget.styleSheet);
    _disposeRecognizers();
    final md.Document document = _sourceRegions == null
        ? md.Document(
            blockSyntaxes: widget.blockSyntaxes,
            inlineSyntaxes: widget.inlineSyntaxes,
            extensionSet: widget.extensionSet ?? md.ExtensionSet.gitHubFlavored,
            encodeHtml: false,
          )
        : SourceMappedMarkdownDocument(
            blockSyntaxes: widget.blockSyntaxes,
            inlineSyntaxes: widget.inlineSyntaxes,
            extensionSet: widget.extensionSet ?? md.ExtensionSet.gitHubFlavored,
            encodeHtml: false,
          );
    final nodes = IanvsMarkdownEditorDiagnostics.measure(
      'body.parse',
      () => document.parseLines(const LineSplitter().convert(widget.data)),
    );
    final builder = ScopedMarkdownBuilder(
      delegate: this,
      selectable: widget.selectable,
      styleSheet: styleSheet,
      imageDirectory: widget.imageDirectory,
      imageBuilder: widget.imageBuilder!,
      checkboxBuilder: widget.checkboxBuilder,
      bulletBuilder: widget.bulletBuilder,
      builders: widget.builders,
      paddingBuilders: widget.paddingBuilders,
      fitContent: widget.fitContent,
      listItemCrossAxisAlignment: widget.listItemCrossAxisAlignment,
      onSelectionChanged: widget.onSelectionChanged,
      onTapText: widget.onTapText,
      contextMenuBuilder: widget.contextMenuBuilder,
      softLineBreak: widget.softLineBreak,
      wrapSourceNode: document is SourceMappedMarkdownDocument
          ? (node, child) {
              if (node is md.Element && node.tag == 'li') {
                final id = node.attributes['id'];
                if (id != null && id.startsWith('fn-')) {
                  child = _sourceRegions!.wrapTarget(
                    Uri.decodeComponent(id),
                    child,
                  );
                }
              }
              final range = document.ranges[node];
              return range == null ? child : _sourceRegions!.wrap(range, child);
            }
          : null,
    );
    _children = IanvsMarkdownEditorDiagnostics.measure(
      'body.buildWidgets',
      () => builder.build(nodes),
    );
  }

  void _disposeRecognizers() {
    final previous = List<GestureRecognizer>.of(_recognizers);
    _recognizers.clear();
    for (final recognizer in previous) {
      recognizer.dispose();
    }
  }

  @override
  GestureRecognizer createLink(IanvsMarkdownLinkTarget target) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () => dispatchIanvsMarkdownLinkTap(
        target,
        onTapLinkTarget: widget.onTapLinkTarget,
        onTapLink: widget.onTapLink,
      );
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  TextSpan formatText(MarkdownStyleSheet styleSheet, String code) {
    code = code.replaceAll(RegExp(r'\n$'), '');
    return widget.syntaxHighlighter?.format(code) ??
        TextSpan(style: styleSheet.code, text: code);
  }

  @override
  Widget build(BuildContext context) => MarkdownSourceRegionScope(
    regions: null, // Nested callout/HTML renderers own a different source.
    child: widget._buildBody(context, _children),
  );
}
