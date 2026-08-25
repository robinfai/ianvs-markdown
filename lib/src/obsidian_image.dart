import 'package:flutter/material.dart';

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

/// Applies Obsidian image dimensions to a host-supplied image widget.
class IanvsMarkdownSizedImage extends StatelessWidget {
  const IanvsMarkdownSizedImage({
    super.key,
    required this.dimensions,
    required this.child,
  });

  final IanvsMarkdownImageDimensions dimensions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('ianvs-markdown-image-size'),
      width: dimensions.width?.toDouble(),
      height: dimensions.height?.toDouble(),
      child: child,
    );
  }
}
