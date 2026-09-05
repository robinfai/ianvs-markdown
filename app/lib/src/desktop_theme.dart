import 'package:flutter/material.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

/// App chrome tokens. Document rendering inherits the same neutral palette.
abstract final class DesktopMetrics {
  static const toolbarHeight = 44.0;
  static const tabsHeight = 32.0;
  static const sidebarWidth = 248.0;
  static const inspectorWidth = 224.0;
  static const controlRadius = 6.0;
}

ThemeData desktopTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final foreground = dark ? const Color(0xffeeeeee) : const Color(0xff262626);
  final secondary = dark ? const Color(0xffb8b8bc) : const Color(0xff626268);
  final muted = dark ? const Color(0xff97979d) : const Color(0xff737379);
  final surface = dark ? const Color(0xff202122) : Colors.white;
  final chrome = dark ? const Color(0xff28292b) : const Color(0xfff4f4f5);
  final border = dark ? const Color(0xff434447) : const Color(0xffd8d8dc);
  final accent = dark ? const Color(0xff64aaff) : const Color(0xff0066cc);
  final colors =
      (dark ? IanvsMarkdownThemeData.dark : IanvsMarkdownThemeData.light)
          .copyWith(
            surface: surface,
            surfaceMuted: chrome,
            surfaceRaised: dark ? const Color(0xff303134) : Colors.white,
            surfaceHover: dark
                ? const Color(0xff3a3b3e)
                : const Color(0xffe7e7ea),
            border: border,
            borderSoft: dark
                ? const Color(0xff353639)
                : const Color(0xffe4e4e7),
            textPrimary: foreground,
            textSecondary: secondary,
            textTertiary: muted,
            accent: accent,
            accentDark: accent,
            accentSoft: accent.withValues(alpha: .18),
            accentMist: accent.withValues(alpha: .08),
            strongForeground: foreground,
            emphasisForeground: foreground,
            inlineCodeForeground: secondary,
            taskCheckboxColor: accent,
            smallRadius: 5,
            mediumRadius: 8,
            largeRadius: 10,
          );
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness)
      .copyWith(
        primary: accent,
        onPrimary: dark ? const Color(0xff101820) : Colors.white,
        surface: surface,
        onSurface: foreground,
        onSurfaceVariant: secondary,
        surfaceContainer: chrome,
        surfaceContainerLow: chrome,
        surfaceContainerHigh: chrome,
        outline: border,
        outlineVariant: colors.borderSoft,
        surfaceTint: Colors.transparent,
      );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(6));
  final buttonStyle = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(64, 28)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
    shape: WidgetStatePropertyAll(shape),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    ),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
  return ThemeData(
    useMaterial3: true,
    platform: TargetPlatform.macOS,
    brightness: brightness,
    fontFamily: '.AppleSystemUIFont',
    colorScheme: scheme,
    scaffoldBackgroundColor: surface,
    splashFactory: NoSplash.splashFactory,
    hoverColor: foreground.withValues(alpha: .06),
    focusColor: accent.withValues(alpha: .18),
    visualDensity: VisualDensity.compact,
    textTheme: TextTheme(
      bodyLarge: TextStyle(fontSize: 13, color: foreground),
      bodyMedium: TextStyle(fontSize: 13, color: foreground),
      bodySmall: TextStyle(fontSize: 11, color: secondary),
      titleMedium: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: foreground,
      ),
      titleLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: foreground,
      ),
      labelLarge: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: foreground,
      ),
    ),
    iconTheme: IconThemeData(size: 16, color: secondary),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(shape),
        minimumSize: const WidgetStatePropertyAll(Size(28, 28)),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(5)),
        foregroundColor: WidgetStatePropertyAll(secondary),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: buttonStyle.copyWith(
        foregroundColor: WidgetStatePropertyAll(secondary),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: buttonStyle.copyWith(
        foregroundColor: WidgetStatePropertyAll(foreground),
        side: WidgetStatePropertyAll(BorderSide(color: border)),
        backgroundColor: WidgetStatePropertyAll(colors.surfaceRaised),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: border),
      ),
      textStyle: TextStyle(fontSize: 13, color: foreground),
      menuPadding: const EdgeInsets.symmetric(vertical: 5),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: chrome,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: border),
      ),
      titleTextStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: foreground,
      ),
      contentTextStyle: TextStyle(fontSize: 13, height: 1.45, color: secondary),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 600),
      textStyle: TextStyle(fontSize: 11, color: foreground),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border),
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(5),
      radius: const Radius.circular(3),
      thumbColor: WidgetStatePropertyAll(muted.withValues(alpha: .45)),
      crossAxisMargin: 3,
    ),
    dividerTheme: DividerThemeData(
      color: colors.borderSoft,
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xffe8e8eb) : const Color(0xff303134),
      shape: shape,
      contentTextStyle: TextStyle(
        fontSize: 13,
        color: dark ? Colors.black87 : Colors.white,
      ),
    ),
    extensions: <ThemeExtension<dynamic>>[colors],
  );
}
