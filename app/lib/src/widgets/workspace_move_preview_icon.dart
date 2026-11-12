import 'package:flutter/material.dart';

/// The eight outline glyphs generated from the approved rename-dialog design.
/// Keep this order aligned with the atlas's four columns and two rows.
enum MovePreviewGlyph {
  folder,
  note,
  link,
  warning,
  location,
  close,
  chevronRight,
  chevronDown,
}

class MovePreviewIcon extends StatelessWidget {
  const MovePreviewIcon(this.glyph, {super.key, this.size = 24, this.color});

  final MovePreviewGlyph glyph;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    // The original PNG has transparent padding around each glyph. Zoom each
    // cell together with that padding; retain one shared cached image and tint
    // its alpha mask so the same assets work in dark and disabled states.
    final cell = size * 1.35;
    final foreground =
        color ?? theme.color ?? Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: size,
      height: size,
      child: ExcludeSemantics(
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: size / 2 - (glyph.index % 4 + .5) * cell,
              top: size / 2 - (glyph.index ~/ 4 + .5) * cell,
              width: cell * 4,
              height: cell * 2,
              child: Image.asset(
                'assets/icons/move-preview-atlas.png',
                fit: BoxFit.fill,
                color: foreground.withValues(
                  alpha: foreground.a * (theme.opacity ?? 1),
                ),
                colorBlendMode: BlendMode.srcIn,
                filterQuality: FilterQuality.high,
                excludeFromSemantics: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
