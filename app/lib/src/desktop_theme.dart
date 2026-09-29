import 'package:ianvs_design/ianvs_design.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

import 'desktop_typography.dart';
import 'models/workspace_layout.dart';

/// Host layout metrics; shared control styling comes from Ianvs Design.
abstract final class DesktopMetrics {
  static const toolbarHeight = 52.0;
  static const tabsHeight = 32.0;
  static const sidebarWidth = WorkspaceLayout.defaultSidebarWidth;
  static const inspectorWidth = 224.0;
  static const controlRadius = 6.0;
}

ThemeData desktopTheme(Brightness brightness) {
  final theme = IanvsTheme.build(
    brightness: brightness,
    density: IanvsDensity.compact,
    platform: TargetPlatform.macOS,
    fontFamily: DesktopTypography.fontFamily,
  );
  final tokens = theme.extension<IanvsTokens>()!;
  final markdown =
      (brightness == Brightness.dark
              ? IanvsMarkdownThemeData.dark
              : IanvsMarkdownThemeData.light)
          .copyWith(
            surface: tokens.canvas,
            surfaceMuted: tokens.chrome,
            surfaceRaised: tokens.raised,
            surfaceHover: Color.alphaBlend(
              tokens.text.withValues(alpha: .06),
              tokens.chrome,
            ),
            border: tokens.border,
            borderSoft: tokens.separator,
            textPrimary: tokens.text,
            textSecondary: tokens.muted,
            textTertiary: tokens.subtle,
            accent: tokens.focus,
            accentDark: tokens.accent,
            accentSoft: tokens.selected,
            accentMist: tokens.focus.withValues(alpha: .08),
            strongForeground: tokens.text,
            emphasisForeground: tokens.text,
            inlineCodeForeground: tokens.muted,
            taskCheckboxColor: tokens.accent,
            smallRadius: tokens.controlRadius,
            mediumRadius: tokens.panelRadius,
            largeRadius: tokens.dialogRadius,
          );
  return theme.copyWith(
    // Preserve Ianvs tokens and code typography alongside document semantics.
    extensions: [...theme.extensions.values, markdown],
    tooltipTheme: theme.tooltipTheme.copyWith(
      waitDuration: const Duration(milliseconds: 600),
    ),
    // A document app's compact modal title uses the macOS title hierarchy.
    dialogTheme: theme.dialogTheme.copyWith(
      titleTextStyle: DesktopTypography.title2.copyWith(
        color: tokens.text,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: theme.textTheme.bodyMedium,
    ),
  );
}
