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
    this.scrollable = false,
    this.onBuildBlock,
    this.scrollPadding = EdgeInsets.zero,
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

  final bool scrollable;

  // Restores source ordinals when viewport blocks build out of order.
  final void Function(int images, int tasks)? onBuildBlock;
  final EdgeInsetsGeometry scrollPadding;

  final IanvsMarkdownTapLinkTargetCallback? onTapLinkTarget;

  @override
  State<ScopedMarkdownBody> createState() => _ScopedMarkdownBodyState();

  Widget _buildBody(BuildContext context, List<Widget>? children) {
    final viewport = MarkdownViewportLayout.maybeOf(context);
    if (!scrollable) return super.build(context, children);
    final header = viewport?.header;
    return ListView.builder(
      controller: viewport?.controller,
      padding: viewport?.padding ?? scrollPadding,
      itemCount: children!.length + (header == null ? 0 : 1),
      itemBuilder: (context, index) {
        final child = header != null && index == 0
            ? header
            : children[index - (header == null ? 0 : 1)];
        return viewport == null
            ? child
            : Align(
                alignment: viewport.alignment,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: viewport.maxWidth),
                  child: SizedBox(width: double.infinity, child: child),
                ),
              );
      },
    );
  }
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
    ScopedMarkdownBuilder makeBuilder(ScopedMarkdownBuilderDelegate delegate) =>
        ScopedMarkdownBuilder(
          delegate: delegate,
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
                  return range == null
                      ? child
                      : _sourceRegions!.wrap(range, child);
                }
              : null,
        );
    if (widget.scrollable &&
        widget.onBuildBlock != null &&
        _sourceRegions == null) {
      var images = 0;
      var tasks = 0;
      void count(md.Node node) {
        if (node is! md.Element) return;
        if (node.tag == 'img') images++;
        if (node.attributes['type'] == 'checkbox') tasks++;
        for (final child in node.children ?? const <md.Node>[]) {
          count(child);
        }
      }

      _children = <Widget>[];
      for (final node in nodes) {
        final imageStart = images;
        final taskStart = tasks;
        count(node);
        if (_children!.isNotEmpty) {
          _children!.add(SizedBox(height: styleSheet.blockSpacing));
        }
        _children!.add(
          _DeferredMarkdownBlock(
            key: ObjectKey(node),
            buildBlock: (delegate) {
              widget.onBuildBlock!(imageStart, taskStart);
              return makeBuilder(delegate).build([node]);
            },
            onTapLink: widget.onTapLink,
            onTapLinkTarget: widget.onTapLinkTarget,
            syntaxHighlighter: widget.syntaxHighlighter,
          ),
        );
      }
      return;
    }
    final builder = makeBuilder(this);
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

// Offscreen blocks release their Widget/InlineSpan trees and recognizers. The
// document AST stays shared so cross-block link definitions remain intact.
class _DeferredMarkdownBlock extends StatefulWidget {
  const _DeferredMarkdownBlock({
    super.key,
    required this.buildBlock,
    required this.onTapLink,
    required this.onTapLinkTarget,
    required this.syntaxHighlighter,
  });
  final List<Widget> Function(ScopedMarkdownBuilderDelegate) buildBlock;
  final MarkdownTapLinkCallback? onTapLink;
  final IanvsMarkdownTapLinkTargetCallback? onTapLinkTarget;
  final SyntaxHighlighter? syntaxHighlighter;
  @override
  State<_DeferredMarkdownBlock> createState() => _DeferredMarkdownBlockState();
}

class _DeferredMarkdownBlockState extends State<_DeferredMarkdownBlock>
    implements ScopedMarkdownBuilderDelegate {
  final _recognizers = <GestureRecognizer>[];
  late List<Widget> _children;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _clear();
    _children = widget.buildBlock(this);
  }

  @override
  void didUpdateWidget(_DeferredMarkdownBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    _clear();
    _children = widget.buildBlock(this);
  }

  void _clear() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
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
  TextSpan formatText(MarkdownStyleSheet styleSheet, String code) =>
      widget.syntaxHighlighter?.format(code.replaceAll(RegExp(r'\n$'), '')) ??
      TextSpan(
        style: styleSheet.code,
        text: code.replaceAll(RegExp(r'\n$'), ''),
      );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: _children,
  );
}

/// Internal host layout for the read view's viewport. Keeps the public renderer
/// API unchanged and preserves one vertical scroll position for header + body.
class MarkdownViewportLayout extends InheritedWidget {
  const MarkdownViewportLayout({
    super.key,
    required super.child,
    required this.controller,
    required this.padding,
    required this.maxWidth,
    required this.alignment,
    this.header,
  });
  final ScrollController controller;
  final EdgeInsetsGeometry padding;
  final double maxWidth;
  final AlignmentGeometry alignment;
  final Widget? header;
  static MarkdownViewportLayout? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MarkdownViewportLayout>();
  @override
  bool updateShouldNotify(MarkdownViewportLayout oldWidget) =>
      controller != oldWidget.controller ||
      padding != oldWidget.padding ||
      maxWidth != oldWidget.maxWidth ||
      alignment != oldWidget.alignment ||
      header != oldWidget.header;
}
