import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

/// Markdown source form associated with a resizable image.
enum IanvsMarkdownImageSourceSyntax { standard, wiki }

/// A completed image resize or reset gesture.
@immutable
class IanvsMarkdownImageResizeRequest {
  const IanvsMarkdownImageResizeRequest({
    required this.syntax,
    required this.width,
    this.imageIndex = 0,
    this.source,
  });

  final IanvsMarkdownImageSourceSyntax syntax;

  /// Zero-based rendered standard-image index inside the current source unit.
  final int imageIndex;

  /// Exact Wiki embed source when [syntax] is
  /// [IanvsMarkdownImageSourceSyntax.wiki].
  final String? source;

  /// New integer width, or null when the user resets the image size.
  final int? width;
}

typedef IanvsMarkdownImageResizeHandler =
    void Function(IanvsMarkdownImageResizeRequest request);

typedef IanvsMarkdownImageEditHandler = void Function(int imageIndex);

/// Exact source ranges for one rendered standard Markdown image.
@immutable
class IanvsMarkdownStandardImageSource {
  const IanvsMarkdownStandardImageSource({
    required this.sourceRange,
    required this.altRange,
    required this.editableRange,
  });

  /// Complete image source, including `![` and its closing delimiter.
  final TextRange sourceRange;

  /// Alternative text without its surrounding brackets.
  final TextRange altRange;

  /// Destination and title content selected by Obsidian's image edit control.
  ///
  /// For inline images this excludes the surrounding parentheses. Reference
  /// images use the reference label, and shortcut references use their alt.
  final TextRange editableRange;
}

/// Image alternative text and optional pixel dimensions parsed from Obsidian
/// Markdown.
///
/// Obsidian accepts a trailing `|width` or `|widthxheight` segment in image
/// alternative text. A dimension-only alternative such as `![250](image.png)`
/// is also supported.
@immutable
class IanvsMarkdownImageDimensions {
  const IanvsMarkdownImageDimensions({
    required this.alt,
    this.width,
    this.height,
  });

  /// Alternative text with a valid trailing dimension segment removed.
  final String? alt;

  /// Requested image width in logical pixels.
  final int? width;

  /// Requested image height in logical pixels, or null for proportional
  /// width-only sizing.
  final int? height;

  bool get hasDimensions => width != null;
}

/// Parses Obsidian's image-size suffix from [alt].
///
/// The accepted grammar intentionally matches Obsidian: integer width, an
/// optional lowercase `x` followed by integer height, and optional surrounding
/// whitespace. Invalid suffixes remain part of the alternative text.
IanvsMarkdownImageDimensions parseIanvsMarkdownImageDimensions(String? alt) {
  if (alt == null) {
    return const IanvsMarkdownImageDimensions(alt: null);
  }

  final separator = alt.lastIndexOf('|');
  final candidate = separator < 0 ? alt : alt.substring(separator + 1);
  final dimensions = _imageDimensions.firstMatch(candidate);
  if (dimensions == null) {
    return IanvsMarkdownImageDimensions(alt: alt);
  }

  final cleanedAlt = separator < 0 ? '' : alt.substring(0, separator);
  return IanvsMarkdownImageDimensions(
    alt: cleanedAlt.isEmpty ? null : cleanedAlt,
    width: int.parse(dimensions.group(1)!),
    height: dimensions.group(2) == null
        ? null
        : int.parse(dimensions.group(2)!),
  );
}

final RegExp _imageDimensions = RegExp(r'^\s*([0-9]+)\s*(?:x\s*([0-9]+)\s*)?$');

/// Rewrites the size segment of the rendered standard image at [imageIndex].
///
/// Code spans, Obsidian comments, escaped image markers, and unresolved
/// reference images do not participate in the rendered-image index.
String rewriteIanvsMarkdownImageWidth(
  String source, {
  required int imageIndex,
  required int? width,
  Set<String> linkReferenceLabels = const <String>{},
}) {
  final image = findIanvsMarkdownStandardImageSource(
    source,
    imageIndex: imageIndex,
    linkReferenceLabels: linkReferenceLabels,
  );
  if (image == null) return source;
  final alt = source.substring(image.altRange.start, image.altRange.end);
  final replacement = _imageAltWithWidth(alt, width);
  return source.replaceRange(
    image.altRange.start,
    image.altRange.end,
    replacement,
  );
}

/// Finds the rendered standard image at [imageIndex] without counting images
/// hidden in code, comments, escapes, or unresolved reference syntax.
IanvsMarkdownStandardImageSource? findIanvsMarkdownStandardImageSource(
  String source, {
  required int imageIndex,
  Set<String> linkReferenceLabels = const <String>{},
}) {
  if (imageIndex < 0 || source.isEmpty) return null;
  var renderedImageIndex = 0;
  var index = 0;
  while (index + 1 < source.length) {
    if (_startsUnescaped(source, index, '%%')) {
      final commentEnd = _findUnescaped(source, '%%', index + 2);
      index = commentEnd < 0 ? source.length : commentEnd + 2;
      continue;
    }
    if (source.codeUnitAt(index) == 0x60 && !_isEscaped(source, index)) {
      final codeEnd = _codeSpanEnd(source, index);
      if (codeEnd != null) {
        index = codeEnd;
        continue;
      }
    }
    if (!_startsUnescaped(source, index, '![') ||
        source.startsWith('![[', index)) {
      index += 1;
      continue;
    }

    final labelEnd = _balancedDelimiterEnd(
      source,
      index + 1,
      opening: 0x5b,
      closing: 0x5d,
    );
    if (labelEnd == null) {
      index += 2;
      continue;
    }
    final alt = source.substring(index + 2, labelEnd);
    final following = labelEnd + 1;
    late final int syntaxEnd;
    late final TextRange editableRange;
    if (following < source.length && source.codeUnitAt(following) == 0x28) {
      final destinationEnd = _balancedDelimiterEnd(
        source,
        following,
        opening: 0x28,
        closing: 0x29,
      );
      if (destinationEnd == null) {
        index = labelEnd + 1;
        continue;
      }
      syntaxEnd = destinationEnd + 1;
      editableRange = TextRange(start: following + 1, end: destinationEnd);
    } else if (following < source.length &&
        source.codeUnitAt(following) == 0x5b) {
      final referenceEnd = _balancedDelimiterEnd(
        source,
        following,
        opening: 0x5b,
        closing: 0x5d,
      );
      if (referenceEnd == null) {
        index = labelEnd + 1;
        continue;
      }
      final explicit = source.substring(following + 1, referenceEnd);
      final label = explicit.isEmpty ? alt : explicit;
      if (!linkReferenceLabels.contains(_normalizeReferenceLabel(label))) {
        index = referenceEnd + 1;
        continue;
      }
      syntaxEnd = referenceEnd + 1;
      editableRange = explicit.isEmpty
          ? TextRange(start: index + 2, end: labelEnd)
          : TextRange(start: following + 1, end: referenceEnd);
    } else {
      if (!linkReferenceLabels.contains(_normalizeReferenceLabel(alt))) {
        index = labelEnd + 1;
        continue;
      }
      syntaxEnd = following;
      editableRange = TextRange(start: index + 2, end: labelEnd);
    }

    if (renderedImageIndex == imageIndex) {
      return IanvsMarkdownStandardImageSource(
        sourceRange: TextRange(start: index, end: syntaxEnd),
        altRange: TextRange(start: index + 2, end: labelEnd),
        editableRange: editableRange,
      );
    }
    renderedImageIndex += 1;
    index = syntaxEnd;
  }
  return null;
}

/// Rewrites or removes the size segment of a standalone Wiki image embed.
String rewriteIanvsMarkdownWikiImageWidth(
  String source, {
  required int? width,
}) {
  final match = RegExp(r'^(\s*)!\[\[([^\]\n]+)\]\](\s*)$').firstMatch(source);
  if (match == null) return source;
  final inner = match.group(2)!;
  final separator = inner.indexOf('|');
  final target = separator < 0 ? inner : inner.substring(0, separator);
  final alias = separator < 0 ? '' : inner.substring(separator + 1);
  final rewrittenAlias = _imageAltWithWidth(alias, width);
  if (width == null && rewrittenAlias == alias) return source;
  final rewrittenInner = rewrittenAlias.isEmpty
      ? target
      : '$target|$rewrittenAlias';
  return '${match.group(1)}![[$rewrittenInner]]${match.group(3)}';
}

String _imageAltWithWidth(String alt, int? width) {
  final dimensions = parseIanvsMarkdownImageDimensions(alt);
  if (width == null) {
    if (!dimensions.hasDimensions) return alt;
    return dimensions.alt ?? '';
  }
  final base = dimensions.hasDimensions ? dimensions.alt : alt;
  return base == null || base.isEmpty ? '$width' : '$base|$width';
}

String _normalizeReferenceLabel(String label) =>
    label.trim().replaceAll(RegExp(r'[ \n\r\t]+'), ' ').toLowerCase();

int? _balancedDelimiterEnd(
  String source,
  int start, {
  required int opening,
  required int closing,
}) {
  if (start < 0 ||
      start >= source.length ||
      source.codeUnitAt(start) != opening) {
    return null;
  }
  var depth = 1;
  for (var index = start + 1; index < source.length; index += 1) {
    final character = source.codeUnitAt(index);
    if (character == 0x0a || character == 0x0d) return null;
    if (character == 0x5c && index + 1 < source.length) {
      index += 1;
      continue;
    }
    if (character == opening) {
      depth += 1;
    } else if (character == closing) {
      depth -= 1;
      if (depth == 0) return index;
    }
  }
  return null;
}

int? _codeSpanEnd(String source, int openingStart) {
  var runLength = 0;
  while (openingStart + runLength < source.length &&
      source.codeUnitAt(openingStart + runLength) == 0x60) {
    runLength += 1;
  }
  var index = openingStart + runLength;
  while (index < source.length) {
    if (source.codeUnitAt(index) != 0x60) {
      index += 1;
      continue;
    }
    var closingLength = 0;
    while (index + closingLength < source.length &&
        source.codeUnitAt(index + closingLength) == 0x60) {
      closingLength += 1;
    }
    if (closingLength == runLength) return index + closingLength;
    index += closingLength;
  }
  return null;
}

bool _startsUnescaped(String source, int index, String value) =>
    source.startsWith(value, index) && !_isEscaped(source, index);

int _findUnescaped(String source, String value, int start) {
  var index = source.indexOf(value, start);
  while (index >= 0 && _isEscaped(source, index)) {
    index = source.indexOf(value, index + value.length);
  }
  return index;
}

bool _isEscaped(String source, int index) {
  var slashes = 0;
  for (var cursor = index - 1; cursor >= 0; cursor -= 1) {
    if (source.codeUnitAt(cursor) != 0x5c) break;
    slashes += 1;
  }
  return slashes.isOdd;
}

/// Obsidian-style Live Preview controls for a resolved Markdown image.
class IanvsMarkdownInteractiveImage extends StatefulWidget {
  const IanvsMarkdownInteractiveImage({
    super.key,
    required this.child,
    required this.expandedImageBuilder,
    this.alt,
    this.title,
    this.onEdit,
    this.theme,
  });

  final Widget child;
  final WidgetBuilder expandedImageBuilder;
  final String? alt;
  final String? title;
  final VoidCallback? onEdit;
  final IanvsMarkdownThemeData? theme;

  @override
  State<IanvsMarkdownInteractiveImage> createState() =>
      _IanvsMarkdownInteractiveImageState();
}

class _IanvsMarkdownInteractiveImageState
    extends State<IanvsMarkdownInteractiveImage> {
  var _controlsVisible = false;

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context, widget.theme);
    final alt = widget.alt?.trim();
    final title = widget.title?.trim();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onExit: (_) {
        if (_controlsVisible && mounted) {
          setState(() => _controlsVisible = false);
        }
      },
      child: GestureDetector(
        key: const ValueKey('ianvs-markdown-image-interaction'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!_controlsVisible) setState(() => _controlsVisible = true);
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Semantics(
              image: true,
              label: alt == null || alt.isEmpty ? null : alt,
              hint: title == null || title.isEmpty ? null : title,
              excludeSemantics: true,
              child: widget.child,
            ),
            if (_controlsVisible)
              PositionedDirectional(
                top: 8,
                end: 8,
                child: Material(
                  key: const ValueKey('ianvs-markdown-image-controls'),
                  color: colors.surfaceRaised.withValues(alpha: .96),
                  elevation: 4,
                  shadowColor: Colors.black.withValues(alpha: .3),
                  borderRadius: BorderRadius.circular(colors.smallRadius),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _imageAction(
                        key: const ValueKey('ianvs-markdown-image-zoom'),
                        label: 'Zoom image',
                        icon: Icons.zoom_out_map_rounded,
                        colors: colors,
                        onPressed: _showExpanded,
                      ),
                      if (widget.onEdit != null)
                        _imageAction(
                          key: const ValueKey('ianvs-markdown-image-edit'),
                          label: 'Edit image block',
                          icon: Icons.edit_outlined,
                          colors: colors,
                          onPressed: widget.onEdit!,
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

  Widget _imageAction({
    required Key key,
    required String label,
    required IconData icon,
    required IanvsMarkdownThemeData colors,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      key: key,
      tooltip: label,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      padding: EdgeInsets.zero,
      color: colors.textSecondary,
      iconSize: 18,
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }

  Future<void> _showExpanded() async {
    final alt = widget.alt?.trim();
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .88),
      builder: (dialogContext) => Material(
        key: const ValueKey('ianvs-markdown-image-viewer'),
        color: Colors.black.withValues(alpha: .92),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 52,
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        alt == null || alt.isEmpty ? 'Image' : alt,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('ianvs-markdown-image-viewer-close'),
                      tooltip: 'Close image viewer',
                      color: Colors.white,
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
              Expanded(
                child: InteractiveViewer(
                  minScale: .5,
                  maxScale: 6,
                  child: Center(
                    child: widget.expandedImageBuilder(dialogContext),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Applies Obsidian image dimensions and optional desktop resize affordances
/// to a host-supplied image widget.
class IanvsMarkdownSizedImage extends StatefulWidget {
  const IanvsMarkdownSizedImage({
    super.key,
    required this.dimensions,
    required this.child,
    this.onResize,
    this.resizeColor,
  });

  final IanvsMarkdownImageDimensions dimensions;
  final Widget child;
  final ValueChanged<int?>? onResize;
  final Color? resizeColor;

  @override
  State<IanvsMarkdownSizedImage> createState() =>
      _IanvsMarkdownSizedImageState();
}

class _IanvsMarkdownSizedImageState extends State<IanvsMarkdownSizedImage> {
  final GlobalKey _surfaceKey = GlobalKey();
  var _hovered = false;
  var _resizing = false;
  double? _previewWidth;
  double? _dragAspectRatio;
  Offset? _dragOrigin;
  double? _dragHorizontalOrigin;
  TextDirection? _dragDirection;
  int? _resizePointer;
  Offset? _resizeStartPosition;
  var _resizeMoved = false;
  var _maximumWidth = double.infinity;

  @override
  void didUpdateWidget(covariant IanvsMarkdownSizedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dimensions.width != widget.dimensions.width ||
        oldWidget.dimensions.height != widget.dimensions.height) {
      _previewWidth = null;
      _dragAspectRatio = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final resize = switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => null,
      _ => widget.onResize,
    };
    final color = widget.resizeColor ?? Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        _maximumWidth = constraints.hasBoundedWidth
            ? math.max(20, constraints.maxWidth)
            : double.infinity;
        final previewWidth = _previewWidth;
        final previewHeight = previewWidth != null && _dragAspectRatio != null
            ? previewWidth / _dragAspectRatio!
            : widget.dimensions.height?.toDouble();
        Widget image = SizedBox(
          key: const ValueKey('ianvs-markdown-image-size'),
          width: previewWidth ?? widget.dimensions.width?.toDouble(),
          height: previewHeight,
          child: widget.child,
        );
        if (_resizing) {
          image = DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(border: Border.all(color: color)),
            child: image,
          );
        }
        return MouseRegion(
          onEnter: resize == null
              ? null
              : (_) => setState(() => _hovered = true),
          onExit: resize == null
              ? null
              : (_) {
                  if (!_resizing) setState(() => _hovered = false);
                },
          child: Stack(
            key: _surfaceKey,
            clipBehavior: Clip.none,
            children: [
              image,
              if (resize != null)
                PositionedDirectional(
                  end: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    ignoring: !_hovered && !_resizing,
                    child: AnimatedOpacity(
                      key: const ValueKey(
                        'ianvs-markdown-image-resize-handle-opacity',
                      ),
                      opacity: _hovered || _resizing ? 1 : 0,
                      duration: const Duration(milliseconds: 120),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeUpLeftDownRight,
                        child: GestureDetector(
                          key: const ValueKey(
                            'ianvs-markdown-image-resize-handle',
                          ),
                          behavior: HitTestBehavior.opaque,
                          onTap: () {},
                          onDoubleTap: _resetResize,
                          child: Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: _startResize,
                            onPointerMove: _updateResize,
                            onPointerUp: _finishResize,
                            onPointerCancel: (_) => _cancelResize(),
                            child: SizedBox(
                              width: 30,
                              height: 30,
                              child: Align(
                                alignment: AlignmentDirectional.bottomEnd,
                                child: Container(
                                  key: const ValueKey(
                                    'ianvs-markdown-image-resize-corner',
                                  ),
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    border: BorderDirectional(
                                      end: BorderSide(color: color, width: 2),
                                      bottom: BorderSide(
                                        color: color,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _startResize(PointerDownEvent event) {
    if (_resizePointer != null || !event.down) return;
    final renderObject = _surfaceKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || renderObject.size.isEmpty) return;
    final size = renderObject.size;
    _resizePointer = event.pointer;
    _resizeStartPosition = event.position;
    _resizeMoved = false;
    _dragOrigin = renderObject.localToGlobal(Offset.zero);
    _dragDirection = Directionality.of(context);
    _dragHorizontalOrigin = _dragDirection == TextDirection.rtl
        ? _dragOrigin!.dx + size.width
        : _dragOrigin!.dx;
    _dragAspectRatio = size.height > 0 ? size.width / size.height : 1;
    setState(() {
      _resizing = true;
      _previewWidth = size.width;
    });
  }

  void _updateResize(PointerMoveEvent event) {
    if (!_resizing ||
        event.pointer != _resizePointer ||
        _dragOrigin == null ||
        _dragHorizontalOrigin == null ||
        _dragAspectRatio == null) {
      return;
    }
    final origin = _dragOrigin!;
    if ((event.position - (_resizeStartPosition ?? event.position)).distance >
        kTouchSlop) {
      _resizeMoved = true;
    }
    if (!_resizeMoved) return;
    final horizontal = _dragDirection == TextDirection.rtl
        ? _dragHorizontalOrigin! - event.position.dx
        : event.position.dx - _dragHorizontalOrigin!;
    final vertical = event.position.dy - origin.dy;
    final requested = math.max(
      horizontal.abs(),
      vertical.abs() * _dragAspectRatio!,
    );
    setState(() {
      _previewWidth = requested.clamp(20, _maximumWidth).toDouble();
    });
  }

  void _finishResize(PointerUpEvent event) {
    if (!_resizing || event.pointer != _resizePointer) return;
    final moved = _resizeMoved;
    final width = (_previewWidth ?? 20).round();
    setState(() {
      _resizing = false;
      _hovered = true;
      if (!moved) {
        _previewWidth = null;
        _dragAspectRatio = null;
      }
    });
    _resizePointer = null;
    _resizeStartPosition = null;
    _resizeMoved = false;
    if (moved) widget.onResize?.call(width);
  }

  void _cancelResize() {
    if (!_resizing) return;
    setState(() {
      _resizing = false;
      _previewWidth = null;
      _dragAspectRatio = null;
    });
    _resizePointer = null;
    _resizeStartPosition = null;
    _resizeMoved = false;
  }

  void _resetResize() {
    setState(() {
      _resizing = false;
      _previewWidth = null;
      _dragAspectRatio = null;
      _hovered = true;
    });
    widget.onResize?.call(null);
  }
}
