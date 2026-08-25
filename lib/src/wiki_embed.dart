import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'obsidian_image.dart';
import 'theme.dart';

/// The parsed destination of an Obsidian `![[...]]` embed.
@immutable
class IanvsMarkdownWikiEmbedReference {
  const IanvsMarkdownWikiEmbedReference({
    required this.source,
    required this.target,
    required this.note,
    this.subpath,
    this.alias,
    this.width,
    this.height,
  });

  /// Exact embed source, including `![[` and `]]`.
  final String source;

  /// Exact link destination inside the brackets, excluding an alias.
  final String target;

  /// Note path before the first `#`. Empty for a local heading or block.
  final String note;

  /// Heading or block destination after the first `#`, without the `#`.
  final String? subpath;

  /// Optional label after `|`.
  final String? alias;

  /// Requested image width in logical pixels.
  ///
  /// This remains null for non-image embeds, including numeric note aliases.
  final int? width;

  /// Requested image height in logical pixels, or null for proportional
  /// width-only sizing.
  final int? height;

  bool get isImageEmbed {
    final separator = note.lastIndexOf('.');
    if (separator < 0 || separator == note.length - 1) return false;
    return _imageExtensions.contains(
      note.substring(separator + 1).toLowerCase(),
    );
  }

  bool get hasImageDimensions => isImageEmbed && width != null;

  bool get isBlockReference => subpath?.startsWith('^') ?? false;

  bool get isHeadingReference => subpath != null && !isBlockReference;

  String get displayLabel => alias ?? target;
}

/// Resolves an embed reference into content supplied by the host app.
///
/// Ianvs Markdown deliberately performs no file or network I/O. A host can
/// use this callback to resolve the note, heading, or block and return a
/// nested [IanvsMarkdown] widget or any other representation.
typedef IanvsMarkdownWikiEmbedContentBuilder =
    Widget Function(
      BuildContext context,
      IanvsMarkdownWikiEmbedReference reference,
    );

/// Parses standalone Obsidian embeds such as `![[Note#Heading|Label]]`.
class IanvsMarkdownWikiEmbedSyntax extends md.BlockSyntax {
  const IanvsMarkdownWikiEmbedSyntax();

  static final RegExp _embed = RegExp(r'^ {0,3}!\[\[([^\]\n]+)\]\][ \t]*$');

  @override
  RegExp get pattern => _embed;

  @override
  md.Node parse(md.BlockParser parser) {
    final source = parser.current.content.trim();
    final match = _embed.firstMatch(parser.current.content)!;
    final inner = match.group(1)!.trim();
    parser.advance();

    final separator = inner.indexOf('|');
    final target = (separator < 0 ? inner : inner.substring(0, separator))
        .trim();
    final rawAlias = separator < 0 ? '' : inner.substring(separator + 1).trim();
    if (target.isEmpty) {
      return md.Element('p', <md.Node>[md.Text(source)]);
    }

    final hash = target.indexOf('#');
    final note = (hash < 0 ? target : target.substring(0, hash)).trim();
    final rawSubpath = hash < 0 ? '' : target.substring(hash + 1).trim();
    final imageEmbed = _isImageTarget(note);
    final dimensions = imageEmbed
        ? parseIanvsMarkdownImageDimensions(rawAlias.isEmpty ? null : rawAlias)
        : IanvsMarkdownImageDimensions(alt: rawAlias.isEmpty ? null : rawAlias);
    return md.Element('ianvs-wiki-embed', const <md.Node>[])
      ..attributes['data-source'] = source
      ..attributes['data-target'] = target
      ..attributes['data-note'] = note
      ..attributes['data-subpath'] = rawSubpath
      ..attributes['data-alias'] = dimensions.alt ?? ''
      ..attributes['data-width'] = dimensions.width?.toString() ?? ''
      ..attributes['data-height'] = dimensions.height?.toString() ?? '';
  }
}

class IanvsMarkdownWikiEmbedElementBuilder extends MarkdownElementBuilder {
  IanvsMarkdownWikiEmbedElementBuilder({
    required this.onTapLink,
    required this.onTapText,
    this.contentBuilder,
    this.onResizeImage,
    this.theme,
  });

  final MarkdownTapLinkCallback? onTapLink;
  final VoidCallback? onTapText;
  final IanvsMarkdownWikiEmbedContentBuilder? contentBuilder;
  final void Function(String source, int? width)? onResizeImage;
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
    final rawSubpath = element.attributes['data-subpath'] ?? '';
    final rawAlias = element.attributes['data-alias'] ?? '';
    final rawWidth = element.attributes['data-width'] ?? '';
    final rawHeight = element.attributes['data-height'] ?? '';
    return IanvsMarkdownWikiEmbed(
      reference: IanvsMarkdownWikiEmbedReference(
        source: element.attributes['data-source'] ?? '',
        target: element.attributes['data-target'] ?? '',
        note: element.attributes['data-note'] ?? '',
        subpath: rawSubpath.isEmpty ? null : rawSubpath,
        alias: rawAlias.isEmpty ? null : rawAlias,
        width: int.tryParse(rawWidth),
        height: int.tryParse(rawHeight),
      ),
      contentBuilder: contentBuilder,
      onResizeImage: onResizeImage,
      onTapLink: onTapLink,
      onTapText: onTapText,
      theme: theme,
    );
  }
}

/// An Obsidian-style embedded note, heading, or block card.
class IanvsMarkdownWikiEmbed extends StatelessWidget {
  const IanvsMarkdownWikiEmbed({
    super.key,
    required this.reference,
    this.contentBuilder,
    this.onResizeImage,
    this.onTapLink,
    this.onTapText,
    this.theme,
  });

  final IanvsMarkdownWikiEmbedReference reference;
  final IanvsMarkdownWikiEmbedContentBuilder? contentBuilder;
  final void Function(String source, int? width)? onResizeImage;
  final MarkdownTapLinkCallback? onTapLink;
  final VoidCallback? onTapText;
  final IanvsMarkdownThemeData? theme;

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context, theme);
    final resolved = contentBuilder?.call(context, reference);
    if (resolved != null && reference.isImageEmbed) {
      final dimensions = IanvsMarkdownImageDimensions(
        alt: reference.alias,
        width: reference.width,
        height: reference.height,
      );
      final resize = onResizeImage;
      final image = dimensions.hasDimensions || resize != null
          ? IanvsMarkdownSizedImage(
              dimensions: dimensions,
              resizeColor: colors.accent,
              onResize: resize == null
                  ? null
                  : (width) => resize(reference.source, width),
              child: resolved,
            )
          : resolved;
      return GestureDetector(
        key: const ValueKey('ianvs-markdown-wiki-embed-tap-target'),
        behavior: HitTestBehavior.translucent,
        onTap: onTapText,
        child: Container(
          key: const ValueKey('ianvs-markdown-wiki-embed'),
          margin: const EdgeInsets.symmetric(vertical: 5),
          alignment: Alignment.centerLeft,
          child: IgnorePointer(
            ignoring: onTapText != null && resize == null,
            child: image,
          ),
        ),
      );
    }
    return GestureDetector(
      key: const ValueKey('ianvs-markdown-wiki-embed-tap-target'),
      behavior: HitTestBehavior.translucent,
      onTap: onTapText,
      child: Container(
        key: const ValueKey('ianvs-markdown-wiki-embed'),
        margin: const EdgeInsets.symmetric(vertical: 5),
        constraints: const BoxConstraints(minHeight: 42),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: colors.accent.withValues(alpha: .88),
              width: 2,
            ),
          ),
        ),
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(12, resolved == null ? 9 : 6, 42, 8),
              child: resolved == null
                  ? _fallback(colors)
                  : IgnorePointer(ignoring: onTapText != null, child: resolved),
            ),
            Positioned(
              right: 3,
              top: 3,
              child: Tooltip(
                message: '打开 ${reference.displayLabel}',
                child: IconButton(
                  key: const ValueKey('ianvs-markdown-wiki-embed-open'),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: onTapLink == null
                      ? null
                      : () => onTapLink!(
                          reference.displayLabel,
                          reference.target,
                          '',
                        ),
                  icon: Icon(
                    Icons.open_in_new_rounded,
                    size: 15,
                    color: onTapLink == null
                        ? colors.textTertiary
                        : colors.accentDark,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallback(IanvsMarkdownThemeData colors) {
    return Row(
      children: [
        Icon(Icons.note_outlined, size: 16, color: colors.textTertiary),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            reference.displayLabel,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.accentDark,
              fontSize: 13.5,
              height: 1.35,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
              decorationColor: colors.accentDark,
            ),
          ),
        ),
      ],
    );
  }
}

const Set<String> _imageExtensions = <String>{
  'bmp',
  'png',
  'jpg',
  'jpeg',
  'gif',
  'svg',
  'webp',
  'avif',
};

bool _isImageTarget(String target) {
  final separator = target.lastIndexOf('.');
  if (separator < 0 || separator == target.length - 1) return false;
  return _imageExtensions.contains(
    target.substring(separator + 1).toLowerCase(),
  );
}
