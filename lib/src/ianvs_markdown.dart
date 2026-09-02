import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'blocked_image.dart';
import 'callout.dart';
import 'code_block.dart';
import 'code_surface.dart';
import 'editor/editor_models.dart';
import 'editor/markdown_code_ranges.dart';
import 'emphasis.dart';
import 'front_matter_card.dart';
import 'heading_folding.dart';
import 'highlight.dart';
import 'html_blockquote.dart';
import 'html_button.dart';
import 'html_center.dart';
import 'html_checkbox.dart';
import 'html_details.dart';
import 'html_definition_list.dart';
import 'html_fieldset.dart';
import 'html_figure.dart';
import 'html_hr.dart';
import 'html_meter.dart';
import 'html_ordered_list.dart';
import 'html_pre.dart';
import 'html_progress.dart';
import 'html_ruby.dart';
import 'html_select.dart';
import 'html_table.dart';
import 'html_textarea.dart';
import 'html_unordered_list.dart';
import 'inline_code.dart';
import 'inline_link.dart';
import 'list_guide.dart';
import 'markdown_table_syntax.dart';
import 'math.dart';
import 'markdown_document.dart';
import 'obsidian_autolink.dart';
import 'obsidian_html.dart';
import 'obsidian_inline.dart';
import 'obsidian_metadata.dart';
import 'obsidian_image.dart';
import 'render_budget.dart';
import 'rich_clipboard.dart';
import 'strikethrough.dart';
import 'task_checkbox.dart';
import 'task_syntax.dart';
import 'theme.dart';
import 'wiki_embed.dart';

typedef IanvsMarkdownFallbackBuilder =
    Widget Function(BuildContext context, IanvsMarkdownRenderDecision decision);

Set<String> _markdownReferenceLabels(String source) {
  if (source.isEmpty) return const <String>{};
  final document = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
  document.parseLines(source.split('\n'));
  return document.linkReferences.keys.toSet();
}

/// A content-sized, reusable Markdown renderer.
///
/// Images are represented by a safe placeholder unless [imageBuilder] is
/// supplied. No network or file I/O is performed by this widget.
class IanvsMarkdown extends StatelessWidget {
  const IanvsMarkdown({
    super.key,
    required this.data,
    this.selectable = true,
    this.documentSelection = true,
    this.clipboardWriter = writeIanvsMarkdownClipboard,
    this.styleSheet,
    this.styleSheetTheme = MarkdownStyleSheetBaseTheme.material,
    this.onSelectionChanged,
    this.onTapLink,
    this.onTapText,
    this.onCalloutToggle,
    this.blockSyntaxes,
    this.inlineSyntaxes,
    this.extensionSet,
    this.imageBuilder,
    this.onImageResize,
    this.onEditImage,
    this.checkboxBuilder,
    this.bulletBuilder,
    this.builders = const <String, MarkdownElementBuilder>{},
    this.paddingBuilders = const <String, MarkdownPaddingBuilder>{},
    this.fitContent = false,
    this.listItemCrossAxisAlignment =
        MarkdownListItemCrossAxisAlignment.baseline,
    this.showListIndentationGuides = true,
    this.listNestingOffset = 0,
    this.softLineBreak = true,
    this.enableFileLinkChips = false,
    this.obsidianMetadataMode = IanvsMarkdownObsidianMetadataMode.reading,
    this.renderBudget = const IanvsMarkdownRenderBudget(),
    this.fallbackBuilder,
    this.diagramBuilder,
    this.mathBuilder,
    this.onCopyCode,
    this.wikiEmbedBuilder,
    this.wikiLinkExists,
    this.theme,
  }) : assert(listNestingOffset >= 0);

  final String data;
  final bool selectable;

  /// Whether [selectable] uses one selection surface for the complete widget.
  ///
  /// This enables cross-block mouse selection and document-level Select All.
  /// Source-aware hosts such as Live Preview set this to false and provide
  /// their own selection coordination.
  final bool documentSelection;

  /// Writes the Markdown and rich HTML produced by a document-level Copy.
  final IanvsMarkdownClipboardWriter clipboardWriter;
  final MarkdownStyleSheet? styleSheet;
  final MarkdownStyleSheetBaseTheme styleSheetTheme;
  final MarkdownOnSelectionChangedCallback? onSelectionChanged;
  final MarkdownTapLinkCallback? onTapLink;
  final VoidCallback? onTapText;

  /// Called when a foldable callout's arrow is pressed.
  ///
  /// Live Preview hosts can use this to enter the exact source surface after
  /// the same arrow gesture that changes the callout's expansion state.
  final VoidCallback? onCalloutToggle;
  final List<md.BlockSyntax>? blockSyntaxes;
  final List<md.InlineSyntax>? inlineSyntaxes;
  final md.ExtensionSet? extensionSet;
  final MarkdownImageBuilder? imageBuilder;

  /// Receives completed desktop resize and reset gestures for host-resolved
  /// images. [IanvsMarkdownLiveEditor] uses this internally for exact source
  /// updates; renderer hosts can use it with the public rewrite helpers.
  final IanvsMarkdownImageResizeHandler? onImageResize;

  /// Adds Obsidian-style image controls in editing mode and reports which
  /// rendered standard image requested source editing.
  final IanvsMarkdownImageEditHandler? onEditImage;
  final MarkdownCheckboxBuilder? checkboxBuilder;
  final MarkdownBulletBuilder? bulletBuilder;
  final Map<String, MarkdownElementBuilder> builders;
  final Map<String, MarkdownPaddingBuilder> paddingBuilders;
  final bool fitContent;
  final MarkdownListItemCrossAxisAlignment listItemCrossAxisAlignment;

  /// Whether nested lists paint Border/Obsidian-style indentation guides.
  final bool showListIndentationGuides;

  /// Additional structural depth supplied by a host that renders list items
  /// as separate Markdown blocks, such as Live Preview.
  final int listNestingOffset;
  final bool softLineBreak;
  final bool enableFileLinkChips;
  final IanvsMarkdownObsidianMetadataMode obsidianMetadataMode;

  /// Set to null to disable the syntax rendering budget.
  final IanvsMarkdownRenderBudget? renderBudget;
  final IanvsMarkdownFallbackBuilder? fallbackBuilder;
  final IanvsMarkdownDiagramBuilder? diagramBuilder;
  final IanvsMarkdownMathBuilder? mathBuilder;
  final IanvsMarkdownCodeCopyHandler? onCopyCode;
  final IanvsMarkdownWikiEmbedContentBuilder? wikiEmbedBuilder;
  final IanvsMarkdownWikiLinkExists? wikiLinkExists;
  final IanvsMarkdownThemeData? theme;

  @override
  Widget build(BuildContext context) {
    final insideDocumentSelection =
        _IanvsMarkdownDocumentSelectionScope.maybeOf(context);
    final useDocumentSelection =
        selectable && documentSelection && !insideDocumentSelection;
    final useBlockSelection =
        selectable && !documentSelection && !insideDocumentSelection;
    final content = LayoutBuilder(
      builder: (context, constraints) => _buildConstrained(
        context,
        constraints,
        blockSelectable: useBlockSelection,
      ),
    );
    if (!useDocumentSelection) return content;
    return _IanvsMarkdownReadingSelection(
      enabled: true,
      markdown: data,
      richMarkdown: data,
      clipboardWriter: clipboardWriter,
      onSelectionChanged: onSelectionChanged,
      child: content,
    );
  }

  Widget _buildConstrained(
    BuildContext context,
    BoxConstraints constraints, {
    required bool blockSelectable,
  }) {
    final colors = IanvsMarkdownThemeData.resolve(context, theme);
    final budget = renderBudget;
    final decision = budget == null
        ? IanvsMarkdownRenderDecision(
            text: data,
            useMarkdown: true,
            syntaxTokens: 0,
            truncated: false,
          )
        : scanMarkdownForRendering(data, budget: budget);
    if (!decision.useMarkdown) {
      final style = TextStyle(
        color: colors.textPrimary,
        fontSize: 14,
        height: 1.55,
      );
      return fallbackBuilder?.call(context, decision) ??
          (blockSelectable
              ? SelectableText(
                  decision.text,
                  key: const ValueKey('ianvs-markdown-plain-fallback'),
                  style: style,
                )
              : Text(
                  decision.text,
                  key: const ValueKey('ianvs-markdown-plain-fallback'),
                  style: style,
                ));
    }

    final effectiveStyleSheet =
        (styleSheet ?? ianvsMarkdownStyleSheet(context, colors)).copyWith();
    final effectiveBuilders = <String, MarkdownElementBuilder>{
      if (obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.reading)
        for (var level = 1; level <= 6; level += 1)
          'h$level': _IanvsMarkdownStandaloneHeadingBuilder(
            level: level,
            colors: colors,
            selectable: blockSelectable,
          ),
      'pre': IanvsMarkdownCodeBlockBuilder(
        theme: colors,
        maxWidth: constraints.hasBoundedWidth ? constraints.maxWidth : null,
        diagramBuilder: diagramBuilder,
        onCopyCode: onCopyCode,
        onTap: onTapText,
        presentation:
            obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing
            ? IanvsMarkdownCodeBlockPresentation.editing
            : IanvsMarkdownCodeBlockPresentation.reading,
      ),
      'ianvs-inline-code': IanvsMarkdownInlineCodeBuilder(theme: colors),
      'ianvs-html-code': IanvsMarkdownInlineCodeBuilder(
        consumeTap:
            obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing,
        theme: colors,
      ),
      'ianvs-html-strong': IanvsMarkdownHtmlInlineBuilder(
        kind: IanvsMarkdownHtmlInlineKind.strong,
        consumeTap:
            obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing,
        theme: colors,
      ),
      'ianvs-html-em': IanvsMarkdownHtmlInlineBuilder(
        kind: IanvsMarkdownHtmlInlineKind.emphasis,
        consumeTap:
            obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing,
        theme: colors,
      ),
      'sup': IanvsMarkdownFootnoteSuperscriptBuilder(
        onTapLink: onTapLink,
        superscriptFontFeatureTag:
            effectiveStyleSheet.superscriptFontFeatureTag,
        theme: colors,
      ),
      'a': IanvsMarkdownInlineLinkBuilder(
        onTapLink: onTapLink,
        enableFileLinkChips: enableFileLinkChips,
        editing:
            obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing,
        wikiLinkExists: wikiLinkExists,
        theme: colors,
      ),
      'mark': IanvsMarkdownHighlightBuilder(theme: colors),
      'ianvs-inline-math': IanvsMarkdownMathElementBuilder(
        displayMode: false,
        inline: true,
        mathBuilder: mathBuilder,
        theme: colors,
      ),
      'ianvs-inline-display-math': IanvsMarkdownMathElementBuilder(
        displayMode: true,
        inline: true,
        mathBuilder: mathBuilder,
        theme: colors,
      ),
      'ianvs-display-math': IanvsMarkdownMathElementBuilder(
        displayMode: true,
        mathBuilder: mathBuilder,
        theme: colors,
      ),
      'ianvs-html-u': IanvsMarkdownHtmlInlineBuilder(
        kind: IanvsMarkdownHtmlInlineKind.underline,
        theme: colors,
      ),
      'ianvs-html-s': IanvsMarkdownHtmlInlineBuilder(
        kind: IanvsMarkdownHtmlInlineKind.strikethrough,
        consumeTap:
            obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing,
        theme: colors,
      ),
      'ianvs-html-sup': IanvsMarkdownHtmlInlineBuilder(
        kind: IanvsMarkdownHtmlInlineKind.superscript,
        consumeTap:
            obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing,
        theme: colors,
      ),
      'ianvs-html-sub': IanvsMarkdownHtmlInlineBuilder(
        kind: IanvsMarkdownHtmlInlineKind.subscript,
        consumeTap:
            obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing,
        theme: colors,
      ),
      'ianvs-html-kbd': IanvsMarkdownHtmlInlineBuilder(
        kind: IanvsMarkdownHtmlInlineKind.keyboard,
        consumeTap:
            obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing,
        theme: colors,
      ),
      'ianvs-html-small': IanvsMarkdownHtmlInlineBuilder(
        kind: IanvsMarkdownHtmlInlineKind.small,
        consumeTap:
            obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing,
        theme: colors,
      ),
      'ianvs-html-q': IanvsMarkdownHtmlInlineBuilder(
        kind: IanvsMarkdownHtmlInlineKind.quotation,
        consumeTap:
            obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing,
        theme: colors,
      ),
      'ianvs-html-abbr': IanvsMarkdownHtmlInlineBuilder(
        kind: IanvsMarkdownHtmlInlineKind.abbreviation,
        consumeTap:
            obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing,
        theme: colors,
      ),
      'ianvs-html-mark': IanvsMarkdownHtmlInlineBuilder(
        kind: IanvsMarkdownHtmlInlineKind.mark,
        consumeTap:
            obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing,
        theme: colors,
      ),
      'ianvs-html-span': IanvsMarkdownHtmlInlineBuilder(
        kind: IanvsMarkdownHtmlInlineKind.span,
        consumeTap:
            obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing,
        theme: colors,
      ),
      'ianvs-html-details': IanvsMarkdownHtmlDetailsBuilder(
        theme: colors,
        bodyBuilder: (context, source) =>
            _buildHtmlDetailsBody(context, source, effectiveStyleSheet, colors),
      ),
      'ianvs-html-fieldset': IanvsMarkdownHtmlFieldsetBuilder(
        presentation:
            obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing
            ? IanvsMarkdownHtmlFieldsetPresentation.editing
            : IanvsMarkdownHtmlFieldsetPresentation.reading,
        contentBuilder: (context, source) =>
            _buildHtmlFigureBody(context, source, effectiveStyleSheet, colors),
        onTap: onTapText,
        theme: colors,
      ),
      'ianvs-html-blockquote': IanvsMarkdownHtmlBlockquoteBuilder(
        theme: colors,
        bodyBuilder: (context, source) => _buildHtmlBlockquoteBody(
          context,
          source,
          effectiveStyleSheet,
          colors,
        ),
      ),
      'ianvs-html-button': IanvsMarkdownHtmlButtonBuilder(theme: colors),
      'ianvs-html-center': IanvsMarkdownHtmlCenterBuilder(
        bodyBuilder: (context, source) =>
            _buildHtmlFigureBody(context, source, effectiveStyleSheet, colors),
      ),
      'ianvs-html-checkbox': IanvsMarkdownHtmlCheckboxBuilder(theme: colors),
      'ianvs-html-hr': IanvsMarkdownHtmlHorizontalRuleBuilder(
        decoration: effectiveStyleSheet.horizontalRuleDecoration,
      ),
      if (obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.reading)
        'ianvs-html-meter': IanvsMarkdownHtmlMeterBuilder(theme: colors),
      'ianvs-html-pre': IanvsMarkdownHtmlPreBuilder(theme: colors),
      'ianvs-html-progress': IanvsMarkdownHtmlProgressBuilder(theme: colors),
      'ianvs-html-ruby': IanvsMarkdownHtmlRubyBuilder(theme: colors),
      'ianvs-html-select': IanvsMarkdownHtmlSelectBuilder(theme: colors),
      'ianvs-html-figure': IanvsMarkdownHtmlFigureBuilder(
        bodyBuilder: (context, source) =>
            _buildHtmlFigureBody(context, source, effectiveStyleSheet, colors),
      ),
      'ianvs-html-table': IanvsMarkdownHtmlTableBuilder(
        bodyBuilder: (context, source) =>
            _buildHtmlTableBody(context, source, effectiveStyleSheet, colors),
      ),
      'ianvs-html-textarea': IanvsMarkdownHtmlTextareaBuilder(theme: colors),
      'ianvs-html-unordered-list': IanvsMarkdownHtmlUnorderedListBuilder(
        bodyBuilder: (context, source) =>
            _buildHtmlTableBody(context, source, effectiveStyleSheet, colors),
      ),
      'ianvs-html-ordered-list': IanvsMarkdownHtmlOrderedListBuilder(
        bodyBuilder: (context, source) =>
            _buildHtmlTableBody(context, source, effectiveStyleSheet, colors),
      ),
      'ianvs-html-definition-list': IanvsMarkdownHtmlDefinitionListBuilder(
        itemBuilder: (context, source) => _buildHtmlDefinitionListItem(
          context,
          source,
          effectiveStyleSheet,
          colors,
        ),
      ),
      'ianvs-callout': IanvsMarkdownCalloutBuilder(
        theme: colors,
        onToggle: onCalloutToggle,
        titleBuilder: (context, source, accent) => _buildCalloutTitle(
          context,
          source,
          accent,
          effectiveStyleSheet,
          colors,
        ),
        bodyBuilder: (context, source) =>
            _buildCalloutBody(context, source, effectiveStyleSheet, colors),
      ),
      'ianvs-wiki-embed': IanvsMarkdownWikiEmbedElementBuilder(
        onTapLink: onTapLink,
        onTapText: onTapText,
        contentBuilder: wikiEmbedBuilder,
        onResizeImage: onImageResize == null
            ? null
            : (source, width) => onImageResize!(
                IanvsMarkdownImageResizeRequest(
                  syntax: IanvsMarkdownImageSourceSyntax.wiki,
                  source: source,
                  width: width,
                ),
              ),
        theme: colors,
      ),
      if (obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing)
        'ianvs-editing-metadata': IanvsMarkdownEditingMetadataBuilder(
          theme: colors,
        ),
      if (obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing)
        'ianvs-editing-metadata-block': IanvsMarkdownEditingMetadataBuilder(
          theme: colors,
          block: true,
        ),
      ...builders,
    };
    final effectiveBlockSyntaxes = <md.BlockSyntax>[
      ...?blockSyntaxes,
      const IanvsMarkdownIndentedCodeBlockSyntax(),
      const IanvsMarkdownHtmlHorizontalRuleSyntax(),
      const IanvsMarkdownHtmlButtonSyntax(),
      const IanvsMarkdownHtmlCheckboxSyntax(),
      if (obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.reading)
        const IanvsMarkdownHtmlMeterSyntax(),
      const IanvsMarkdownHtmlPreSyntax(),
      const IanvsMarkdownHtmlProgressSyntax(),
      const IanvsMarkdownHtmlSelectSyntax(),
      const IanvsMarkdownHtmlTextareaSyntax(),
      const IanvsMarkdownHtmlFieldsetSyntax(),
      const IanvsMarkdownHtmlBlockquoteSyntax(),
      const IanvsMarkdownHtmlCenterSyntax(),
      const IanvsMarkdownHtmlDefinitionListSyntax(),
      const IanvsMarkdownHtmlFigureSyntax(),
      const IanvsMarkdownHtmlTableSyntax(),
      const IanvsMarkdownHtmlUnorderedListSyntax(),
      const IanvsMarkdownHtmlOrderedListSyntax(),
      const IanvsMarkdownHtmlDetailsSyntax(),
      if (obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing)
        const IanvsMarkdownEditingCommentBlockSyntax(),
      if (obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing)
        const IanvsMarkdownEditingFootnoteDefinitionSyntax(),
      const IanvsMarkdownDisplayMathSyntax(),
      const IanvsMarkdownWikiEmbedSyntax(),
      const IanvsMarkdownCalloutSyntax(),
    ];
    final effectiveInlineSyntaxes = <md.InlineSyntax>[
      ...?inlineSyntaxes,
      IanvsMarkdownCodeSpanSyntax(
        presentation:
            obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing
            ? IanvsMarkdownCodeSpanPresentation.editing
            : IanvsMarkdownCodeSpanPresentation.reading,
      ),
      IanvsMarkdownInlineDisplayMathSyntax(),
      IanvsMarkdownInlineMathSyntax(),
      IanvsMarkdownEntitySyntax(
        presentation:
            obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing
            ? IanvsMarkdownEntityPresentation.editing
            : IanvsMarkdownEntityPresentation.reading,
      ),
      // Angle autolinks are syntactically more specific than raw HTML.
      // Giving them first refusal keeps `<https:…>`, `<user@example.com>`,
      // and custom schemes from being consumed by the safe HTML fallback.
      IanvsMarkdownAutolinkSyntax(),
      ...ianvsMarkdownInlineHtmlSyntaxes(obsidianMetadataMode),
      if (obsidianMetadataMode ==
          IanvsMarkdownObsidianMetadataMode.editing) ...[
        IanvsMarkdownEditingMetadataInlineSyntax.comment(),
        IanvsMarkdownEditingMetadataInlineSyntax.blockId(),
        IanvsMarkdownEditingMetadataInlineSyntax.standardFootnote(),
        IanvsMarkdownEditingMetadataInlineSyntax.inlineFootnote(),
      ],
      IanvsMarkdownLiteralReferenceWhitespaceSyntax(),
      // Metadata syntaxes such as block IDs include their leading space, so
      // they must get first refusal before rendered whitespace is collapsed.
      IanvsMarkdownRenderedWhitespaceSyntax(),
      IanvsMarkdownEmphasisSyntax(
        presentation:
            obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing
            ? IanvsMarkdownEmphasisPresentation.editing
            : IanvsMarkdownEmphasisPresentation.reading,
      ),
      IanvsMarkdownHighlightSyntax(
        presentation:
            obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing
            ? IanvsMarkdownHighlightPresentation.editing
            : IanvsMarkdownHighlightPresentation.reading,
      ),
      IanvsMarkdownStrikethroughSyntax(
        presentation:
            obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing
            ? IanvsMarkdownStrikethroughPresentation.editing
            : IanvsMarkdownStrikethroughPresentation.reading,
      ),
      IanvsMarkdownWikiLinkSyntax(
        presentation:
            obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing
            ? IanvsMarkdownWikiLinkPresentation.editing
            : IanvsMarkdownWikiLinkPresentation.reading,
      ),
      IanvsMarkdownTagSyntax(),
    ];
    final preparedData = _projectIrregularObsidianTables(
      prepareObsidianMarkdownForRendering(
        decision.text,
        mode: obsidianMetadataMode,
      ),
    );
    final imageProjectedData =
        obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing
        ? projectObsidianReferenceImagesForLivePreview(preparedData)
        : preparedData;
    final renderedData =
        projectObsidianInlineLinkDestinationBackslashesForRendering(
          projectObsidianCrossParagraphHighlightsForRendering(
            imageProjectedData,
          ),
        );
    final taskProjection = projectObsidianTaskMarkers(renderedData);
    final listIndentStep =
        (effectiveStyleSheet.listIndent ?? 24) +
        (effectiveStyleSheet.listBulletPadding?.horizontal ?? 4);
    var imageIndex = 0;
    var taskIndex = 0;
    Set<String>? imageReferenceLabels;
    final body = MarkdownBody(
      key: ValueKey<bool>(softLineBreak),
      // flutter_markdown_plus only reparses when data or styles change, so
      // changing this option must remount its state to rebuild line spans.
      data: taskProjection.data,
      selectable: blockSelectable,
      styleSheet: effectiveStyleSheet,
      styleSheetTheme: styleSheetTheme,
      onSelectionChanged: blockSelectable ? onSelectionChanged : null,
      onTapLink: onTapLink,
      onTapText: onTapText,
      blockSyntaxes: effectiveBlockSyntaxes,
      inlineSyntaxes: effectiveInlineSyntaxes,
      extensionSet: extensionSet ?? md.ExtensionSet.gitHubFlavored,
      imageBuilder: (uri, title, alt) {
        final currentImageIndex = imageIndex;
        imageIndex += 1;
        final dimensions = parseIanvsMarkdownImageDimensions(alt);
        imageReferenceLabels ??= _markdownReferenceLabels(renderedData);
        final sourceImage = findIanvsMarkdownStandardImageSource(
          renderedData,
          imageIndex: currentImageIndex,
          linkReferenceLabels: imageReferenceLabels!,
        );
        final builder = imageBuilder;
        if (builder == null) {
          return IanvsMarkdownBlockedImage(
            uri: uri,
            title: title,
            alt: dimensions.alt,
            theme: colors,
          );
        }
        Widget image = builder(uri, title, dimensions.alt);
        final resize = onImageResize;
        if (dimensions.hasDimensions || resize != null) {
          image = IanvsMarkdownSizedImage(
            dimensions: dimensions,
            resizeColor: colors.accent,
            onResize: resize == null
                ? null
                : (width) => resize(
                    IanvsMarkdownImageResizeRequest(
                      syntax: IanvsMarkdownImageSourceSyntax.standard,
                      imageIndex: currentImageIndex,
                      width: width,
                    ),
                  ),
            child: image,
          );
        }
        final editing =
            obsidianMetadataMode == IanvsMarkdownObsidianMetadataMode.editing;
        final edit = onEditImage;
        final referenceTitle =
            sourceImage?.syntax == IanvsMarkdownStandardImageSourceSyntax.inline
            ? null
            : title?.trim();
        image = IanvsMarkdownInteractiveImage(
          alt: dimensions.alt,
          title: title,
          viewerLabel: referenceTitle == null || referenceTitle.isEmpty
              ? dimensions.alt
              : referenceTitle,
          openViewerOnTap: !editing,
          theme: colors,
          onEdit: !editing || edit == null
              ? null
              : () => edit(currentImageIndex),
          expandedImageBuilder: (_) => builder(uri, title, dimensions.alt),
          child: image,
        );
        return image;
      },
      checkboxBuilder: (checked) {
        final task = taskIndex < taskProjection.tasks.length
            ? taskProjection.tasks[taskIndex]
            : IanvsMarkdownTaskSourceMarker(
                marker: checked ? 'x' : ' ',
                offset: -1,
                nestLevel: 0,
              );
        taskIndex += 1;
        return IanvsMarkdownListGuideAnchor(
          nestLevel: listNestingOffset + task.nestLevel,
          child:
              checkboxBuilder?.call(checked) ??
              IanvsMarkdownTaskCheckbox(
                value: task.marker != ' ',
                marker: task.marker,
                theme: colors,
              ),
        );
      },
      bulletBuilder: (parameters) => IanvsMarkdownListGuideAnchor(
        nestLevel: listNestingOffset + parameters.nestLevel,
        child:
            bulletBuilder?.call(parameters) ??
            _IanvsMarkdownListMarker(
              parameters: parameters,
              nestLevel: listNestingOffset + parameters.nestLevel,
              theme: colors,
            ),
      ),
      builders: effectiveBuilders,
      paddingBuilders: paddingBuilders,
      fitContent: fitContent,
      listItemCrossAxisAlignment: listItemCrossAxisAlignment,
      softLineBreak: softLineBreak,
    );
    return KeyedSubtree(
      key: const ValueKey('ianvs-markdown-body'),
      child: showListIndentationGuides
          ? IanvsMarkdownListGuideSurface(
              color: colors.listGuideColor,
              indent: listIndentStep,
              textDirection: Directionality.of(context),
              child: body,
            )
          : body,
    );
  }

  Widget _buildCalloutBody(
    BuildContext context,
    String source,
    MarkdownStyleSheet effectiveStyleSheet,
    IanvsMarkdownThemeData colors,
  ) {
    return IanvsMarkdown(
      data: source,
      selectable: selectable,
      documentSelection: documentSelection,
      styleSheet: effectiveStyleSheet.copyWith(
        blockSpacing: 12,
        pPadding: EdgeInsets.zero,
      ),
      styleSheetTheme: styleSheetTheme,
      onSelectionChanged: onSelectionChanged,
      onTapLink: onTapLink,
      onTapText: onTapText,
      blockSyntaxes: blockSyntaxes,
      inlineSyntaxes: inlineSyntaxes,
      extensionSet: extensionSet,
      imageBuilder: imageBuilder,
      onImageResize: onImageResize,
      onEditImage: onEditImage,
      checkboxBuilder: checkboxBuilder,
      bulletBuilder: bulletBuilder,
      builders: builders,
      paddingBuilders: paddingBuilders,
      fitContent: true,
      listItemCrossAxisAlignment: listItemCrossAxisAlignment,
      showListIndentationGuides: false,
      listNestingOffset: listNestingOffset,
      softLineBreak: softLineBreak,
      enableFileLinkChips: enableFileLinkChips,
      obsidianMetadataMode: obsidianMetadataMode,
      renderBudget: renderBudget,
      fallbackBuilder: fallbackBuilder,
      diagramBuilder: diagramBuilder,
      mathBuilder: mathBuilder,
      onCopyCode: onCopyCode,
      wikiEmbedBuilder: wikiEmbedBuilder,
      wikiLinkExists: wikiLinkExists,
      theme: colors,
    );
  }

  Widget _buildHtmlDetailsBody(
    BuildContext context,
    String source,
    MarkdownStyleSheet effectiveStyleSheet,
    IanvsMarkdownThemeData colors,
  ) {
    return IanvsMarkdown(
      data: source,
      selectable: selectable,
      documentSelection: documentSelection,
      styleSheet: effectiveStyleSheet.copyWith(
        blockSpacing: 8,
        pPadding: EdgeInsets.zero,
      ),
      styleSheetTheme: styleSheetTheme,
      onSelectionChanged: onSelectionChanged,
      onTapLink: onTapLink,
      onTapText: onTapText,
      blockSyntaxes: blockSyntaxes,
      inlineSyntaxes: inlineSyntaxes,
      extensionSet: extensionSet,
      imageBuilder: imageBuilder,
      onImageResize: onImageResize,
      onEditImage: onEditImage,
      checkboxBuilder: checkboxBuilder,
      bulletBuilder: bulletBuilder,
      builders: builders,
      paddingBuilders: paddingBuilders,
      fitContent: true,
      listItemCrossAxisAlignment: listItemCrossAxisAlignment,
      showListIndentationGuides: false,
      listNestingOffset: listNestingOffset,
      softLineBreak: softLineBreak,
      enableFileLinkChips: enableFileLinkChips,
      obsidianMetadataMode: IanvsMarkdownObsidianMetadataMode.reading,
      renderBudget: renderBudget,
      fallbackBuilder: fallbackBuilder,
      diagramBuilder: diagramBuilder,
      mathBuilder: mathBuilder,
      onCopyCode: onCopyCode,
      wikiEmbedBuilder: wikiEmbedBuilder,
      wikiLinkExists: wikiLinkExists,
      theme: colors,
    );
  }

  Widget _buildHtmlBlockquoteBody(
    BuildContext context,
    String source,
    MarkdownStyleSheet effectiveStyleSheet,
    IanvsMarkdownThemeData colors,
  ) {
    return IanvsMarkdown(
      data: source,
      selectable: selectable,
      documentSelection: documentSelection,
      styleSheet: effectiveStyleSheet.copyWith(
        blockSpacing: 0,
        pPadding: EdgeInsets.zero,
      ),
      styleSheetTheme: styleSheetTheme,
      onSelectionChanged: onSelectionChanged,
      onTapLink: onTapLink,
      onTapText: onTapText,
      blockSyntaxes: blockSyntaxes,
      inlineSyntaxes: inlineSyntaxes,
      extensionSet: extensionSet,
      imageBuilder: imageBuilder,
      onImageResize: onImageResize,
      onEditImage: onEditImage,
      checkboxBuilder: checkboxBuilder,
      bulletBuilder: bulletBuilder,
      builders: builders,
      paddingBuilders: paddingBuilders,
      fitContent: true,
      listItemCrossAxisAlignment: listItemCrossAxisAlignment,
      showListIndentationGuides: false,
      listNestingOffset: listNestingOffset,
      softLineBreak: false,
      enableFileLinkChips: enableFileLinkChips,
      obsidianMetadataMode: IanvsMarkdownObsidianMetadataMode.reading,
      renderBudget: renderBudget,
      fallbackBuilder: fallbackBuilder,
      diagramBuilder: diagramBuilder,
      mathBuilder: mathBuilder,
      onCopyCode: onCopyCode,
      wikiEmbedBuilder: wikiEmbedBuilder,
      wikiLinkExists: wikiLinkExists,
      theme: colors,
    );
  }

  Widget _buildHtmlFigureBody(
    BuildContext context,
    String source,
    MarkdownStyleSheet effectiveStyleSheet,
    IanvsMarkdownThemeData colors,
  ) {
    return IanvsMarkdown(
      data: source,
      selectable: selectable,
      documentSelection: documentSelection,
      styleSheet: effectiveStyleSheet.copyWith(
        blockSpacing: 0,
        pPadding: EdgeInsets.zero,
      ),
      styleSheetTheme: styleSheetTheme,
      onSelectionChanged: onSelectionChanged,
      onTapLink: onTapLink,
      onTapText: onTapText,
      blockSyntaxes: blockSyntaxes,
      inlineSyntaxes: inlineSyntaxes,
      extensionSet: extensionSet,
      imageBuilder: imageBuilder,
      onImageResize: onImageResize,
      onEditImage: onEditImage,
      checkboxBuilder: checkboxBuilder,
      bulletBuilder: bulletBuilder,
      builders: builders,
      paddingBuilders: paddingBuilders,
      fitContent: true,
      listItemCrossAxisAlignment: listItemCrossAxisAlignment,
      showListIndentationGuides: false,
      listNestingOffset: listNestingOffset,
      softLineBreak: true,
      enableFileLinkChips: enableFileLinkChips,
      obsidianMetadataMode: IanvsMarkdownObsidianMetadataMode.reading,
      renderBudget: renderBudget,
      fallbackBuilder: fallbackBuilder,
      diagramBuilder: diagramBuilder,
      mathBuilder: mathBuilder,
      onCopyCode: onCopyCode,
      wikiEmbedBuilder: wikiEmbedBuilder,
      wikiLinkExists: wikiLinkExists,
      theme: colors,
    );
  }

  Widget _buildHtmlTableBody(
    BuildContext context,
    String source,
    MarkdownStyleSheet effectiveStyleSheet,
    IanvsMarkdownThemeData colors,
  ) {
    return IanvsMarkdown(
      data: source,
      selectable: selectable,
      documentSelection: documentSelection,
      styleSheet: effectiveStyleSheet.copyWith(
        blockSpacing: 0,
        pPadding: EdgeInsets.zero,
      ),
      styleSheetTheme: styleSheetTheme,
      onSelectionChanged: onSelectionChanged,
      onTapLink: onTapLink,
      onTapText: onTapText,
      blockSyntaxes: blockSyntaxes,
      inlineSyntaxes: inlineSyntaxes,
      extensionSet: extensionSet,
      imageBuilder: imageBuilder,
      onImageResize: onImageResize,
      onEditImage: onEditImage,
      checkboxBuilder: checkboxBuilder,
      bulletBuilder: bulletBuilder,
      builders: builders,
      paddingBuilders: paddingBuilders,
      fitContent: true,
      listItemCrossAxisAlignment: listItemCrossAxisAlignment,
      showListIndentationGuides: false,
      listNestingOffset: listNestingOffset,
      softLineBreak: softLineBreak,
      enableFileLinkChips: enableFileLinkChips,
      obsidianMetadataMode: IanvsMarkdownObsidianMetadataMode.reading,
      renderBudget: renderBudget,
      fallbackBuilder: fallbackBuilder,
      diagramBuilder: diagramBuilder,
      mathBuilder: mathBuilder,
      onCopyCode: onCopyCode,
      wikiEmbedBuilder: wikiEmbedBuilder,
      wikiLinkExists: wikiLinkExists,
      theme: colors,
    );
  }

  Widget _buildHtmlDefinitionListItem(
    BuildContext context,
    String source,
    MarkdownStyleSheet effectiveStyleSheet,
    IanvsMarkdownThemeData colors,
  ) {
    return IanvsMarkdown(
      data: source,
      selectable: selectable,
      documentSelection: documentSelection,
      styleSheet: effectiveStyleSheet.copyWith(
        blockSpacing: 0,
        pPadding: EdgeInsets.zero,
      ),
      styleSheetTheme: styleSheetTheme,
      onSelectionChanged: onSelectionChanged,
      onTapLink: onTapLink,
      onTapText: onTapText,
      blockSyntaxes: blockSyntaxes,
      inlineSyntaxes: inlineSyntaxes,
      extensionSet: extensionSet,
      imageBuilder: imageBuilder,
      onImageResize: onImageResize,
      onEditImage: onEditImage,
      checkboxBuilder: checkboxBuilder,
      bulletBuilder: bulletBuilder,
      builders: builders,
      paddingBuilders: paddingBuilders,
      fitContent: true,
      listItemCrossAxisAlignment: listItemCrossAxisAlignment,
      showListIndentationGuides: false,
      listNestingOffset: listNestingOffset,
      softLineBreak: softLineBreak,
      enableFileLinkChips: enableFileLinkChips,
      obsidianMetadataMode: IanvsMarkdownObsidianMetadataMode.reading,
      renderBudget: renderBudget,
      fallbackBuilder: fallbackBuilder,
      diagramBuilder: diagramBuilder,
      mathBuilder: mathBuilder,
      onCopyCode: onCopyCode,
      wikiEmbedBuilder: wikiEmbedBuilder,
      wikiLinkExists: wikiLinkExists,
      theme: colors,
    );
  }

  Widget _buildCalloutTitle(
    BuildContext context,
    String source,
    Color accent,
    MarkdownStyleSheet effectiveStyleSheet,
    IanvsMarkdownThemeData colors,
  ) {
    final titleStyle = (effectiveStyleSheet.p ?? const TextStyle()).copyWith(
      color: accent,
      fontSize: 14.5,
      height: 1.4,
      fontWeight: FontWeight.w700,
    );
    return IanvsMarkdown(
      data: source,
      selectable: false,
      styleSheet: effectiveStyleSheet.copyWith(
        p: titleStyle,
        strong: titleStyle.copyWith(fontWeight: FontWeight.w800),
        a: titleStyle.copyWith(
          decoration: TextDecoration.underline,
          decorationColor: accent,
        ),
        blockSpacing: 0,
        pPadding: EdgeInsets.zero,
      ),
      styleSheetTheme: styleSheetTheme,
      onTapLink: onTapLink,
      blockSyntaxes: blockSyntaxes,
      inlineSyntaxes: inlineSyntaxes,
      extensionSet: extensionSet,
      imageBuilder: imageBuilder,
      onImageResize: onImageResize,
      onEditImage: onEditImage,
      builders: builders,
      paddingBuilders: paddingBuilders,
      fitContent: true,
      showListIndentationGuides: false,
      listNestingOffset: listNestingOffset,
      softLineBreak: softLineBreak,
      enableFileLinkChips: enableFileLinkChips,
      obsidianMetadataMode: obsidianMetadataMode,
      renderBudget: renderBudget,
      fallbackBuilder: fallbackBuilder,
      mathBuilder: mathBuilder,
      wikiLinkExists: wikiLinkExists,
      theme: colors,
    );
  }
}

String _projectIrregularObsidianTables(String source) {
  final lines = source.split('\n');
  final codeLines = _projectedCodeLines(source, lines);
  for (var index = 0; index + 1 < lines.length; index += 1) {
    final headerCellCount = countMarkdownTableCells(lines[index]);
    if (codeLines[index] ||
        codeLines[index + 1] ||
        !isMarkdownTableDelimiterRow(lines[index + 1]) ||
        countMarkdownTableCells(lines[index + 1]) != headerCellCount) {
      continue;
    }

    var end = index + 1;
    while (end + 1 < lines.length &&
        !codeLines[end + 1] &&
        ianvsMarkdownTableBodyContinues(
          lines[end + 1],
          nextLine: end + 2 < lines.length ? lines[end + 2] : null,
        )) {
      end += 1;
    }
    var columnCount = 0;
    for (var row = index; row <= end; row += 1) {
      final count = countMarkdownTableCells(lines[row]);
      if (count > columnCount) columnCount = count;
    }
    for (var row = index; row <= end; row += 1) {
      final separator = row == index + 1;
      while (countMarkdownTableCells(lines[row]) < columnCount) {
        lines[row] = _appendProjectedTableCell(
          lines[row],
          separator: separator,
        );
      }
    }
    index = end;
  }
  return lines.join('\n');
}

List<bool> _projectedCodeLines(String source, List<String> lines) {
  final codeRanges = ianvsMarkdownBlockCodeRanges(source);
  final result = List<bool>.filled(lines.length, false);
  var lineStart = 0;
  var rangeIndex = 0;
  for (var lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
    final lineEnd = lineStart + lines[lineIndex].length;
    while (rangeIndex < codeRanges.length &&
        codeRanges[rangeIndex].end <= lineStart) {
      rangeIndex += 1;
    }
    if (rangeIndex < codeRanges.length) {
      final range = codeRanges[rangeIndex];
      result[lineIndex] = range.start < lineEnd && range.end > lineStart;
    }
    lineStart = lineEnd + 1;
  }
  return result;
}

String _appendProjectedTableCell(String source, {required bool separator}) {
  final trimmedLength = source.trimRight().length;
  final trailingWhitespace = source.substring(trimmedLength);
  final cell = separator ? '---' : '';
  if (trimmedLength > 0 && source[trimmedLength - 1] == '|') {
    return '${source.substring(0, trimmedLength)} $cell |$trailingWhitespace';
  }
  if (cell.isEmpty) return '$source |  |';
  return '$source | $cell';
}

class _IanvsMarkdownListMarker extends StatelessWidget {
  const _IanvsMarkdownListMarker({
    required this.parameters,
    required this.nestLevel,
    required this.theme,
  });

  final MarkdownBulletParameters parameters;
  final int nestLevel;
  final IanvsMarkdownThemeData theme;

  @override
  Widget build(BuildContext context) {
    final ordered = parameters.style == BulletStyle.orderedList;
    if (!ordered) {
      return IanvsMarkdownUnorderedListMarker(
        key: ValueKey('ianvs-markdown-unordered-marker-$nestLevel'),
        nestLevel: nestLevel,
        color: theme.textSecondary,
      );
    }
    return Text(
      '${parameters.index + 1}.',
      key: ValueKey('ianvs-markdown-ordered-marker-$nestLevel'),
      textAlign: TextAlign.right,
      style: TextStyle(color: theme.textPrimary, fontSize: 14.5, height: 1.58),
    );
  }
}

/// A full document renderer with scrolling, YAML front matter, and an outline.
///
/// Place this widget in a height-bounded parent such as [Expanded] or a
/// [Scaffold] body.
class IanvsMarkdownView extends StatefulWidget {
  const IanvsMarkdownView({
    super.key,
    required this.data,
    this.controller,
    this.padding = const EdgeInsets.fromLTRB(28, 24, 32, 44),
    this.showFrontMatter = false,
    this.compactFrontMatter = true,
    this.showDocumentTitle = false,
    this.showOutline = true,
    this.enableHeadingFolding = false,
    this.headingFoldController,
    this.outlineBreakpoint = 560,
    this.outlineWidth = 180,
    this.contentMaxWidth = 840,
    this.contentAlignment = Alignment.topCenter,
    this.maximumOutlineItems = 18,
    this.selectable = true,
    this.softLineBreak = true,
    this.styleSheet,
    this.onSelectionChanged,
    this.onTapLink,
    this.imageBuilder,
    this.builders = const <String, MarkdownElementBuilder>{},
    this.renderBudget = const IanvsMarkdownRenderBudget(),
    this.fallbackBuilder,
    this.diagramBuilder,
    this.mathBuilder,
    this.onCopyCode,
    this.wikiEmbedBuilder,
    this.wikiLinkExists,
    this.enableFileLinkChips = false,
    this.onHeadingSelected,
    this.clipboardWriter = writeIanvsMarkdownClipboard,
    this.theme,
  });

  final String data;
  final ScrollController? controller;
  final EdgeInsetsGeometry padding;
  final bool showFrontMatter;
  final bool compactFrontMatter;
  final bool showDocumentTitle;
  final bool showOutline;

  /// Whether Reading view exposes fold controls beside headings.
  ///
  /// Defaults to the Obsidian configuration where heading fold controls are
  /// not shown.
  final bool enableHeadingFolding;
  final IanvsMarkdownHeadingFoldController? headingFoldController;
  final double outlineBreakpoint;
  final double outlineWidth;
  final double contentMaxWidth;
  final AlignmentGeometry contentAlignment;
  final int maximumOutlineItems;
  final bool selectable;
  final bool softLineBreak;
  final MarkdownStyleSheet? styleSheet;
  final MarkdownOnSelectionChangedCallback? onSelectionChanged;
  final MarkdownTapLinkCallback? onTapLink;
  final MarkdownImageBuilder? imageBuilder;
  final Map<String, MarkdownElementBuilder> builders;
  final IanvsMarkdownRenderBudget? renderBudget;
  final IanvsMarkdownFallbackBuilder? fallbackBuilder;
  final IanvsMarkdownDiagramBuilder? diagramBuilder;
  final IanvsMarkdownMathBuilder? mathBuilder;
  final IanvsMarkdownCodeCopyHandler? onCopyCode;
  final IanvsMarkdownWikiEmbedContentBuilder? wikiEmbedBuilder;
  final IanvsMarkdownWikiLinkExists? wikiLinkExists;
  final bool enableFileLinkChips;
  final ValueChanged<IanvsMarkdownHeading>? onHeadingSelected;

  /// Writes the plain Markdown and rich HTML representations created by Copy.
  ///
  /// The default publishes both formats to the system clipboard. Override this
  /// only when the host owns clipboard policy or needs to observe copy events.
  final IanvsMarkdownClipboardWriter clipboardWriter;
  final IanvsMarkdownThemeData? theme;

  @override
  State<IanvsMarkdownView> createState() => _IanvsMarkdownViewState();
}

class _IanvsMarkdownViewState extends State<IanvsMarkdownView> {
  late ScrollController _scrollController;
  late IanvsMarkdownHeadingFoldController _headingFoldController;
  late IanvsMarkdownDocument _document;
  late List<IanvsMarkdownHeading> _headings;
  late IanvsMarkdownHeadingFoldModel _headingFoldModel;
  var _outlineCollapsed = false;
  int? _activeHeadingIndex;

  bool get _ownsController => widget.controller == null;
  bool get _ownsHeadingFoldController => widget.headingFoldController == null;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.controller ?? ScrollController();
    _headingFoldController =
        widget.headingFoldController ?? IanvsMarkdownHeadingFoldController();
    _parseDocument();
    _headingFoldController.addListener(_handleHeadingFoldsChanged);
  }

  @override
  void didUpdateWidget(covariant IanvsMarkdownView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      if (oldWidget.controller == null) _scrollController.dispose();
      _scrollController = widget.controller ?? ScrollController();
    }
    if (!identical(
      oldWidget.headingFoldController,
      widget.headingFoldController,
    )) {
      _headingFoldController.removeListener(_handleHeadingFoldsChanged);
      if (oldWidget.headingFoldController == null) {
        _headingFoldController.dispose();
      }
      _headingFoldController =
          widget.headingFoldController ?? IanvsMarkdownHeadingFoldController();
      _headingFoldController.addListener(_handleHeadingFoldsChanged);
      _headingFoldController.retainIdentities(_headingFoldModel.identities);
    }
    if (oldWidget.data != widget.data ||
        oldWidget.showFrontMatter != widget.showFrontMatter ||
        oldWidget.renderBudget != widget.renderBudget) {
      _parseDocument();
      _activeHeadingIndex = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    }
  }

  void _parseDocument() {
    // YAML is always removed from the Markdown body. [showFrontMatter]
    // controls only the optional properties card, matching Obsidian's
    // document-surface setting rather than leaking raw YAML into Reading view.
    _document = IanvsMarkdownDocument.parse(widget.data);
    final budget = widget.renderBudget;
    final canRenderHeadings =
        budget == null ||
        scanMarkdownForRendering(_document.body, budget: budget).useMarkdown;
    _headings = canRenderHeadings
        ? _document.headings
        : const <IanvsMarkdownHeading>[];
    _headingFoldModel = IanvsMarkdownHeadingFoldModel.parse(_document.body);
    _headingFoldController.retainIdentities(_headingFoldModel.identities);
  }

  void _handleHeadingFoldsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _headingFoldController.removeListener(_handleHeadingFoldsChanged);
    if (_ownsHeadingFoldController) _headingFoldController.dispose();
    if (_ownsController) _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context, widget.theme);
    final foldProjection = widget.enableHeadingFolding
        ? _headingFoldModel.project(_headingFoldController)
        : IanvsMarkdownHeadingFoldProjection(
            source: _document.body,
            visibleHeadingIdentities: _headingFoldModel.identities,
          );
    final headingPresentations = <_MarkdownHeadingPresentation>[];
    for (
      var index = 0;
      index < _headingFoldModel.sections.length && index < _headings.length;
      index += 1
    ) {
      final section = _headingFoldModel.sections[index];
      if (!foldProjection.visibleHeadingIdentities.contains(section.identity)) {
        continue;
      }
      headingPresentations.add(
        _MarkdownHeadingPresentation(
          heading: _headings[index],
          section: section,
        ),
      );
    }
    final headingBuilder = _MarkdownHeadingBuilder(
      headingPresentations,
      colors,
      foldingEnabled: widget.enableHeadingFolding,
      foldController: _headingFoldController,
      selectable: false,
    );
    final headingBuilders = <String, MarkdownElementBuilder>{
      ...widget.builders,
      if (_headings.isNotEmpty) ...<String, MarkdownElementBuilder>{
        'h1': headingBuilder,
        'h2': headingBuilder,
        'h3': headingBuilder,
        'h4': headingBuilder,
        'h5': headingBuilder,
        'h6': headingBuilder,
      },
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final showOutline =
            widget.showOutline &&
            constraints.maxWidth >= widget.outlineBreakpoint &&
            _headings.isNotEmpty;
        return Row(
          key: const ValueKey('ianvs-markdown-view'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showOutline) ...[
              SizedBox(
                width: _outlineCollapsed ? 44 : widget.outlineWidth,
                child: _MarkdownOutline(
                  headings: _headings,
                  collapsed: _outlineCollapsed,
                  activeHeadingIndex: _activeHeadingIndex,
                  maximumItems: widget.maximumOutlineItems,
                  colors: colors,
                  onToggle: () =>
                      setState(() => _outlineCollapsed = !_outlineCollapsed),
                  onSelect: _scrollToHeading,
                ),
              ),
              VerticalDivider(width: 1, color: colors.border),
            ],
            Expanded(
              child: _IanvsMarkdownReadingSelection(
                enabled: widget.selectable,
                markdown: widget.data,
                richMarkdown: _document.body,
                clipboardWriter: widget.clipboardWriter,
                onSelectionChanged: widget.onSelectionChanged,
                child: SingleChildScrollView(
                  key: const ValueKey('ianvs-markdown-scroll-view'),
                  controller: _scrollController,
                  padding: widget.padding,
                  child: Align(
                    alignment: widget.contentAlignment,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: widget.contentMaxWidth,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.showFrontMatter &&
                              _document.metadata.isNotEmpty) ...[
                            IanvsMarkdownFrontMatterCard(
                              entries: _document.metadata,
                              theme: colors,
                              compact: widget.compactFrontMatter,
                              initiallyExpanded: true,
                              showDocumentTitle: widget.showDocumentTitle,
                              onTapLink: widget.onTapLink,
                            ),
                            const SizedBox(height: 18),
                          ],
                          IanvsMarkdown(
                            data: foldProjection.source,
                            selectable: false,
                            softLineBreak: widget.softLineBreak,
                            styleSheet: widget.styleSheet,
                            onTapLink: widget.onTapLink,
                            imageBuilder: widget.imageBuilder,
                            builders: headingBuilders,
                            renderBudget: widget.renderBudget,
                            fallbackBuilder: widget.fallbackBuilder,
                            diagramBuilder: widget.diagramBuilder,
                            mathBuilder: widget.mathBuilder,
                            onCopyCode: widget.onCopyCode,
                            wikiEmbedBuilder: widget.wikiEmbedBuilder,
                            wikiLinkExists: widget.wikiLinkExists,
                            enableFileLinkChips: widget.enableFileLinkChips,
                            theme: colors,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _scrollToHeading(int index) async {
    if (index < 0 || index >= _headings.length) return;
    final heading = _headings[index];
    setState(() => _activeHeadingIndex = index);
    widget.onHeadingSelected?.call(heading);
    if (widget.enableHeadingFolding &&
        index < _headingFoldModel.sections.length) {
      final target = _headingFoldModel.sections[index];
      final ancestors = _headingFoldModel
          .collapsedAncestorIdentities(
            target.headingBlockIndex,
            _headingFoldController,
          )
          .toList(growable: false);
      if (ancestors.isNotEmpty) {
        _headingFoldController.expandIdentities(ancestors);
        await WidgetsBinding.instance.endOfFrame;
      }
    }
    if (!mounted) return;
    final headingContext = heading.anchorKey.currentContext;
    if (headingContext == null || !headingContext.mounted) return;
    await Scrollable.ensureVisible(
      headingContext,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: .04,
    );
  }
}

class _IanvsMarkdownReadingSelection extends StatefulWidget {
  const _IanvsMarkdownReadingSelection({
    required this.enabled,
    required this.markdown,
    required this.richMarkdown,
    required this.clipboardWriter,
    required this.onSelectionChanged,
    required this.child,
  });

  final bool enabled;
  final String markdown;
  final String richMarkdown;
  final IanvsMarkdownClipboardWriter clipboardWriter;
  final MarkdownOnSelectionChangedCallback? onSelectionChanged;
  final Widget child;

  @override
  State<_IanvsMarkdownReadingSelection> createState() =>
      _IanvsMarkdownReadingSelectionState();
}

class _IanvsMarkdownReadingSelectionState
    extends State<_IanvsMarkdownReadingSelection> {
  final GlobalKey<SelectionAreaState> _selectionAreaKey =
      GlobalKey<SelectionAreaState>();
  final FocusNode _focusNode = FocusNode(
    debugLabel: 'Ianvs Markdown document selection',
  );
  final SelectionListenerNotifier _selectionNotifier =
      SelectionListenerNotifier();
  SelectedContent? _selectedContent;
  SelectionChangedCause? _selectionCause;
  var _wholeDocumentSelected = false;
  var _hardwareCopyHandled = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _selectionNotifier.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (!widget.enabled || !_focusNode.hasFocus || event is! KeyDownEvent) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    final commandOrControl =
        keyboard.isMetaPressed || keyboard.isControlPressed;
    if (!commandOrControl || keyboard.isAltPressed || keyboard.isShiftPressed) {
      return false;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyA) {
      _selectAll(SelectionChangedCause.keyboard);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyC &&
        _selectedContent?.plainText.isNotEmpty == true) {
      _hardwareCopyHandled = true;
      unawaited(_copySelection());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _hardwareCopyHandled = false;
      });
      return true;
    }
    return false;
  }

  @override
  void didUpdateWidget(covariant _IanvsMarkdownReadingSelection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.markdown != widget.markdown ||
        oldWidget.enabled != widget.enabled) {
      _selectedContent = null;
      _wholeDocumentSelected = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyA, meta: true):
            SelectAllTextIntent(SelectionChangedCause.keyboard),
        SingleActivator(LogicalKeyboardKey.keyA, control: true):
            SelectAllTextIntent(SelectionChangedCause.keyboard),
        SingleActivator(LogicalKeyboardKey.keyC, meta: true):
            CopySelectionTextIntent.copy,
        SingleActivator(LogicalKeyboardKey.keyC, control: true):
            CopySelectionTextIntent.copy,
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          SelectAllTextIntent: CallbackAction<SelectAllTextIntent>(
            onInvoke: (intent) {
              _selectAll(intent.cause);
              return null;
            },
          ),
          CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
            onInvoke: (_) {
              if (_hardwareCopyHandled) {
                _hardwareCopyHandled = false;
                return null;
              }
              unawaited(_copySelection());
              return null;
            },
          ),
        },
        child: SelectionArea(
          key: _selectionAreaKey,
          focusNode: _focusNode,
          onSelectionChanged: _handleSelectionChanged,
          contextMenuBuilder: _buildContextMenu,
          child: SelectionListener(
            selectionNotifier: _selectionNotifier,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) {
                _wholeDocumentSelected = false;
                _focusNode.requestFocus();
              },
              child: _IanvsMarkdownDocumentSelectionScope(child: widget.child),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContextMenu(BuildContext context, SelectableRegionState region) {
    final items = region.contextMenuButtonItems
        .map((item) {
          return switch (item.type) {
            ContextMenuButtonType.copy => item.copyWith(
              onPressed: () {
                unawaited(_copySelection());
                region.hideToolbar();
              },
            ),
            ContextMenuButtonType.selectAll => item.copyWith(
              onPressed: () => _selectAll(SelectionChangedCause.toolbar),
            ),
            _ => item,
          };
        })
        .toList(growable: false);
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: region.contextMenuAnchors,
      buttonItems: items,
    );
  }

  void _selectAll(SelectionChangedCause cause) {
    final region = _selectionAreaKey.currentState?.selectableRegion;
    if (region == null) return;
    _selectionCause = cause;
    _wholeDocumentSelected = true;
    region.selectAll(cause);
    _selectionCause = null;
  }

  void _handleSelectionChanged(SelectedContent? content) {
    _selectedContent = content;
    final callback = widget.onSelectionChanged;
    if (callback == null) return;
    final length = content?.plainText.length ?? 0;
    callback(
      content?.plainText,
      content == null
          ? const TextSelection.collapsed(offset: -1)
          : TextSelection(baseOffset: 0, extentOffset: length),
      _selectionCause,
    );
  }

  Future<void> _copySelection() async {
    final selectedText = _selectedContent?.plainText;
    if (selectedText == null || selectedText.isEmpty) return;
    final wholeDocument = _wholeDocumentSelected;
    final range = _selectionNotifier.registered
        ? _selectionNotifier.selection.range
        : null;
    final preferredStart = range == null
        ? null
        : range.startOffset < range.endOffset
        ? range.startOffset
        : range.endOffset;
    final partial = wholeDocument
        ? null
        : ianvsMarkdownSelectionClipboardData(
            widget.richMarkdown,
            selectedText,
            preferredStart: preferredStart,
          );
    await widget.clipboardWriter(
      IanvsMarkdownClipboardData(
        markdown: wholeDocument ? widget.markdown : partial!.markdown,
        html: wholeDocument
            ? ianvsMarkdownClipboardHtml(widget.richMarkdown)
            : partial!.html,
      ),
    );
  }
}

class _IanvsMarkdownDocumentSelectionScope extends InheritedWidget {
  const _IanvsMarkdownDocumentSelectionScope({required super.child});

  static bool maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<
            _IanvsMarkdownDocumentSelectionScope
          >() !=
      null;

  @override
  bool updateShouldNotify(_IanvsMarkdownDocumentSelectionScope oldWidget) =>
      false;
}

class _MarkdownOutline extends StatelessWidget {
  const _MarkdownOutline({
    required this.headings,
    required this.collapsed,
    required this.activeHeadingIndex,
    required this.maximumItems,
    required this.colors,
    required this.onToggle,
    required this.onSelect,
  });

  final List<IanvsMarkdownHeading> headings;
  final bool collapsed;
  final int? activeHeadingIndex;
  final int maximumItems;
  final IanvsMarkdownThemeData colors;
  final VoidCallback onToggle;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.surfaceRaised,
      child: collapsed
          ? Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: IconButton(
                  tooltip: '展开文档大纲',
                  onPressed: onToggle,
                  icon: const Icon(Icons.toc_rounded, size: 19),
                  color: colors.textSecondary,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            )
          : ListView(
              key: const ValueKey('ianvs-markdown-outline'),
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 18),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          '文档大纲',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '收起文档大纲',
                      onPressed: onToggle,
                      icon: const Icon(
                        Icons.keyboard_double_arrow_left_rounded,
                        size: 17,
                      ),
                      color: colors.textSecondary,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                for (
                  var index = 0;
                  index < headings.length && index < maximumItems;
                  index += 1
                )
                  _MarkdownOutlineItem(
                    key: ValueKey('ianvs-markdown-outline-heading-$index'),
                    heading: headings[index],
                    selected: activeHeadingIndex == index,
                    colors: colors,
                    onTap: () => onSelect(index),
                  ),
              ],
            ),
    );
  }
}

class _MarkdownOutlineItem extends StatelessWidget {
  const _MarkdownOutlineItem({
    super.key,
    required this.heading,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final IanvsMarkdownHeading heading;
  final bool selected;
  final IanvsMarkdownThemeData colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: (heading.level - 1) * 9, bottom: 3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(colors.smallRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? colors.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(colors.smallRadius),
          ),
          child: Text(
            heading.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected || heading.level == 1
                  ? colors.accentDark
                  : colors.textSecondary,
              fontSize: 11,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

final class _MarkdownHeadingPresentation {
  const _MarkdownHeadingPresentation({
    required this.heading,
    required this.section,
  });

  final IanvsMarkdownHeading heading;
  final IanvsMarkdownHeadingSection section;
}

class _MarkdownHeadingBuilder extends MarkdownElementBuilder {
  _MarkdownHeadingBuilder(
    this.headings,
    this.colors, {
    required this.foldingEnabled,
    required this.foldController,
    required this.selectable,
  });

  final List<_MarkdownHeadingPresentation> headings;
  final IanvsMarkdownThemeData colors;
  final bool foldingEnabled;
  final IanvsMarkdownHeadingFoldController foldController;
  final bool selectable;
  var _index = 0;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    if (_index >= headings.length) return null;
    final presentation = headings[_index];
    final heading = presentation.heading;
    final level = int.tryParse(element.tag.substring(1));
    final text = element.textContent.trim();
    if (heading.level != level || heading.text != text) return null;
    _index += 1;
    final section = presentation.section;
    return _FoldableViewHeading(
      key: heading.anchorKey,
      identity: section.identity,
      level: level ?? section.level,
      text: text,
      style: preferredStyle ?? parentStyle,
      colors: colors,
      foldable: foldingEnabled && section.canFold,
      collapsed: foldController.isCollapsed(section.identity),
      onToggle: () => foldController.toggleIdentity(section.identity),
      selectable: selectable,
    );
  }
}

class _FoldableViewHeading extends StatefulWidget {
  const _FoldableViewHeading({
    super.key,
    required this.identity,
    required this.level,
    required this.text,
    required this.style,
    required this.colors,
    required this.foldable,
    required this.collapsed,
    required this.onToggle,
    required this.selectable,
  });

  final String identity;
  final int level;
  final String text;
  final TextStyle? style;
  final IanvsMarkdownThemeData colors;
  final bool foldable;
  final bool collapsed;
  final VoidCallback onToggle;
  final bool selectable;

  @override
  State<_FoldableViewHeading> createState() => _FoldableViewHeadingState();
}

class _FoldableViewHeadingState extends State<_FoldableViewHeading> {
  var _hovering = false;

  @override
  Widget build(BuildContext context) {
    final showToggle = widget.foldable && (_hovering || widget.collapsed);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Semantics(
        header: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (widget.foldable)
              SizedBox(
                width: 22,
                child: AnimatedOpacity(
                  opacity: showToggle ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  alwaysIncludeSemantics: true,
                  child: IconButton(
                    key: ValueKey(
                      'ianvs-markdown-heading-fold-${widget.identity}',
                    ),
                    tooltip: widget.collapsed ? '展开标题内容' : '折叠标题内容',
                    onPressed: widget.onToggle,
                    icon: Icon(
                      widget.collapsed
                          ? Icons.keyboard_arrow_right_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 17,
                    ),
                    color: widget.colors.textTertiary,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 22,
                      height: 24,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            Expanded(
              child: Container(
                key: ValueKey('ianvs-markdown-heading-rail-${widget.level}'),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: widget.colors.headingAccent(widget.level),
                      width: 2,
                    ),
                  ),
                ),
                padding: const EdgeInsets.only(left: 8),
                child: Row(
                  children: [
                    Flexible(
                      fit: FlexFit.loose,
                      child: widget.selectable
                          ? SelectableText(widget.text, style: widget.style)
                          : Text(widget.text, style: widget.style),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IanvsMarkdownStandaloneHeadingBuilder extends MarkdownElementBuilder {
  _IanvsMarkdownStandaloneHeadingBuilder({
    required this.level,
    required this.colors,
    required this.selectable,
  });

  final int level;
  final IanvsMarkdownThemeData colors;
  final bool selectable;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final text = element.textContent.trim();
    if (text.isEmpty) return null;
    return Semantics(
      header: true,
      child: Container(
        key: ValueKey('ianvs-markdown-standalone-heading-rail-$level'),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: colors.headingAccent(level), width: 2),
          ),
        ),
        padding: const EdgeInsets.only(left: 8),
        child: selectable
            ? SelectableText(text, style: preferredStyle ?? parentStyle)
            : Text(text, style: preferredStyle ?? parentStyle),
      ),
    );
  }
}

MarkdownStyleSheet ianvsMarkdownStyleSheet(
  BuildContext context, [
  IanvsMarkdownThemeData? theme,
]) {
  final colors = IanvsMarkdownThemeData.resolve(context, theme);
  final dark = Theme.of(context).brightness == Brightness.dark;
  final quotePatternColor = (dark ? Colors.white : Colors.black).withValues(
    alpha: .12,
  );
  final base = MarkdownStyleSheet.fromTheme(Theme.of(context));
  return base.copyWith(
    h1: TextStyle(
      color: colors.textPrimary,
      fontSize: 26,
      height: 1.22,
      fontWeight: FontWeight.w600,
    ),
    h2: TextStyle(
      color: colors.textPrimary,
      fontSize: 21,
      height: 1.3,
      fontWeight: FontWeight.w600,
    ),
    h3: TextStyle(
      color: colors.textPrimary,
      fontSize: 18,
      height: 1.35,
      fontWeight: FontWeight.w600,
    ),
    h4: TextStyle(
      color: colors.textPrimary,
      fontSize: 16,
      height: 1.35,
      fontWeight: FontWeight.w600,
    ),
    h5: TextStyle(
      color: colors.textPrimary,
      fontSize: 14.5,
      height: 1.4,
      fontWeight: FontWeight.w600,
    ),
    h6: TextStyle(
      color: colors.textPrimary,
      fontSize: 13.5,
      height: 1.45,
      fontWeight: FontWeight.w600,
    ),
    p: TextStyle(color: colors.textPrimary, fontSize: 14.5, height: 1.58),
    a: TextStyle(
      color: colors.accentDark,
      decoration: TextDecoration.underline,
      decorationColor: colors.accent,
      fontWeight: FontWeight.w600,
    ),
    em: TextStyle(
      color: colors.emphasisForeground,
      fontStyle: FontStyle.italic,
    ),
    strong: TextStyle(
      color: colors.strongForeground,
      fontWeight: FontWeight.w600,
    ),
    code: ianvsMarkdownInlineCodeStyle(colors),
    listBullet: TextStyle(
      color: colors.textPrimary,
      fontSize: 14.5,
      height: 1.58,
    ),
    tableBorder: TableBorder.all(color: colors.borderSoft),
    tableHead: TextStyle(
      color: colors.textPrimary,
      fontWeight: FontWeight.w600,
    ),
    tableBody: TextStyle(color: colors.textPrimary),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    blockquoteDecoration: IanvsMarkdownQuoteDecoration(
      backgroundColor: colors.surface,
      patternColor: quotePatternColor,
      railColor: colors.accent,
      radius: colors.smallRadius / 2,
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(27, 8, 8, 8),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: colors.borderSoft, width: 2)),
    ),
    blockSpacing: 14,
    listIndent: 24,
    codeblockPadding: EdgeInsets.zero,
    codeblockDecoration: const BoxDecoration(),
  );
}
