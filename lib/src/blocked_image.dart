import 'package:flutter/material.dart';

import 'theme.dart';

/// Safe default for Markdown images. It performs no network or file I/O.
class IanvsMarkdownBlockedImage extends StatelessWidget {
  const IanvsMarkdownBlockedImage({
    super.key,
    required this.uri,
    this.title,
    this.alt,
    this.theme,
  });

  final Uri uri;
  final String? title;
  final String? alt;
  final IanvsMarkdownThemeData? theme;

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context, theme);
    final scheme = uri.scheme.trim().toLowerCase();
    final source = switch (scheme) {
      'http' ||
      'https' when uri.host.trim().isNotEmpty => uri.host.toLowerCase(),
      '' => 'local',
      _ => scheme,
    };
    final altText = alt?.trim();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Container(
        key: const ValueKey('ianvs-markdown-image-blocked'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(colors.smallRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_not_supported_outlined,
              size: 15,
              color: colors.textTertiary,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                [
                  'Image blocked · $source',
                  if (altText != null && altText.isNotEmpty) altText,
                ].join('\n'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 11,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
