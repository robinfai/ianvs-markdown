import 'package:flutter/material.dart';

/// macOS interface text styles, in logical points.
///
/// Sizes and leading follow Apple's macOS built-in text styles:
/// https://developer.apple.com/design/human-interface-guidelines/typography
/// Document typography is supplied separately by the Markdown renderer.
abstract final class DesktopTypography {
  static const fontFamily = '.AppleSystemUIFont';

  // Avoid inherited Material tracking. System font shaping and platform
  // fallback handle Latin, CJK, and emoji without manual character spacing.
  static const body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    height: 16 / 13,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static final largeTitle = body.copyWith(fontSize: 26, height: 32 / 26);
  static final title1 = body.copyWith(fontSize: 22, height: 26 / 22);
  static final title2 = body.copyWith(fontSize: 17, height: 22 / 17);
  static final title3 = body.copyWith(fontSize: 15, height: 20 / 15);
  static final headline = body.copyWith(fontWeight: FontWeight.w700);
  static final emphasizedBody = body.copyWith(fontWeight: FontWeight.w600);
  static final callout = body.copyWith(fontSize: 12, height: 15 / 12);
  static final subheadline = body.copyWith(fontSize: 11, height: 14 / 11);
  static final sectionLabel = subheadline.copyWith(fontWeight: FontWeight.w600);

  /// Fill every Material slot so mobile sizes and tracking cannot leak into
  /// menus, dialogs, controls, or inherited text in the desktop shell.
  static TextTheme textTheme(Color foreground, Color secondary) => TextTheme(
    displayLarge: largeTitle.copyWith(color: foreground),
    displayMedium: largeTitle.copyWith(color: foreground),
    displaySmall: title1.copyWith(color: foreground),
    headlineLarge: title1.copyWith(color: foreground),
    headlineMedium: title2.copyWith(color: foreground),
    headlineSmall: title3.copyWith(color: foreground),
    titleLarge: title2.copyWith(color: foreground),
    titleMedium: title3.copyWith(color: foreground),
    titleSmall: headline.copyWith(color: foreground),
    bodyLarge: body.copyWith(color: foreground),
    bodyMedium: body.copyWith(color: foreground),
    bodySmall: subheadline.copyWith(color: secondary),
    labelLarge: body.copyWith(color: foreground),
    labelMedium: callout.copyWith(color: foreground),
    labelSmall: subheadline.copyWith(color: secondary),
  );
}
