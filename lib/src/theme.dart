import 'package:flutter/material.dart';

/// Visual tokens used by all Ianvs Markdown widgets.
///
/// Add an instance to [ThemeData.extensions] to theme every renderer in a
/// subtree, or pass one directly to an individual widget.
@immutable
class IanvsMarkdownThemeData extends ThemeExtension<IanvsMarkdownThemeData> {
  const IanvsMarkdownThemeData({
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceRaised,
    required this.surfaceHover,
    required this.border,
    required this.borderSoft,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentDark,
    required this.accentSoft,
    required this.accentMist,
    required this.error,
    Color? codeForeground,
    Color? inlineCodeForeground,
    Color? strongForeground,
    Color? emphasisForeground,
    Color? taskCheckboxColor,
    Color? taskCheckboxBorderColor,
    Color? taskCheckboxHoverOutlineColor,
    Color? taskDoneColor,
    Color? taskStatusRed,
    Color? taskStatusOrange,
    Color? taskStatusYellow,
    Color? taskStatusCyan,
    Color? taskStatusBlue,
    Color? taskStatusPurple,
    Color? taskStatusPink,
    this.headingAccents = const <Color>[
      Color(0xffc24b57),
      Color(0xffb56b35),
      Color(0xff9a7a16),
      Color(0xff4f8a3f),
      Color(0xff3979b8),
      Color(0xff8e55ad),
    ],
    this.monoFontFamily = 'SF Mono',
    this.monoFontFamilyFallback = const <String>[
      'Menlo',
      'Monaco',
      'monospace',
    ],
    this.smallRadius = 8,
    this.mediumRadius = 10,
    this.largeRadius = 14,
  }) : codeForeground = codeForeground ?? textSecondary,
       inlineCodeForeground = inlineCodeForeground ?? textPrimary,
       strongForeground = strongForeground ?? textPrimary,
       emphasisForeground = emphasisForeground ?? textPrimary,
       taskCheckboxColor = taskCheckboxColor ?? accent,
       taskCheckboxBorderColor = taskCheckboxBorderColor ?? textTertiary,
       taskCheckboxHoverOutlineColor = taskCheckboxHoverOutlineColor ?? border,
       taskDoneColor = taskDoneColor ?? textTertiary,
       taskStatusRed = taskStatusRed ?? error,
       taskStatusOrange = taskStatusOrange ?? emphasisForeground ?? textPrimary,
       taskStatusYellow = taskStatusYellow ?? accent,
       taskStatusCyan = taskStatusCyan ?? accent,
       taskStatusBlue = taskStatusBlue ?? accent,
       taskStatusPurple = taskStatusPurple ?? accent,
       taskStatusPink = taskStatusPink ?? inlineCodeForeground ?? textPrimary;

  static const IanvsMarkdownThemeData light = IanvsMarkdownThemeData(
    surface: Color(0xffffffff),
    surfaceMuted: Color(0xfff5f7f7),
    surfaceRaised: Color(0xfffafbfb),
    surfaceHover: Color(0xffedf3f3),
    border: Color(0xffd8dede),
    borderSoft: Color(0xffe8ecec),
    textPrimary: Color(0xff202526),
    textSecondary: Color(0xff4f595b),
    textTertiary: Color(0xff6f797b),
    accent: Color(0xff167b82),
    accentDark: Color(0xff11656b),
    accentSoft: Color(0xffdceced),
    accentMist: Color(0xffeef7f7),
    error: Color(0xffc33f43),
    codeForeground: Color(0xff545664),
    inlineCodeForeground: Color(0xffdd1399),
    strongForeground: Color(0xffdd2c38),
    emphasisForeground: Color(0xffde7417),
    taskCheckboxColor: Color(0xff1da51d),
    taskCheckboxBorderColor: Color(0xff989bae),
    taskCheckboxHoverOutlineColor: Color(0x408089c6),
    taskDoneColor: Color(0xff989bae),
    taskStatusRed: Color(0xffdd2c38),
    taskStatusOrange: Color(0xffde7417),
    taskStatusYellow: Color(0xffc09c0c),
    taskStatusCyan: Color(0xff16a6ab),
    taskStatusBlue: Color(0xff1775d9),
    taskStatusPurple: Color(0xff8f47e1),
    taskStatusPink: Color(0xffdd1399),
    headingAccents: <Color>[
      Color(0xffc24b57),
      Color(0xffb56b35),
      Color(0xff9a7a16),
      Color(0xff4f8a3f),
      Color(0xff3979b8),
      Color(0xff8e55ad),
    ],
  );

  static const IanvsMarkdownThemeData dark = IanvsMarkdownThemeData(
    surface: Color(0xff1e1e1e),
    surfaceMuted: Color(0xff252525),
    surfaceRaised: Color(0xff292929),
    surfaceHover: Color(0xff333333),
    border: Color(0xff454545),
    borderSoft: Color(0xff353535),
    textPrimary: Color(0xffeeeeee),
    textSecondary: Color(0xffc0c0c0),
    textTertiary: Color(0xffa2a2a2),
    accent: Color(0xff68c5ca),
    accentDark: Color(0xff9cdee1),
    accentSoft: Color(0xff27484a),
    accentMist: Color(0xff24393b),
    error: Color(0xffff8a8e),
    codeForeground: Color(0xffb8bac7),
    inlineCodeForeground: Color(0xfff2b6de),
    strongForeground: Color(0xffff7881),
    emphasisForeground: Color(0xfffbbb83),
    taskCheckboxColor: Color(0xff7cd37c),
    taskCheckboxBorderColor: Color(0xff74778b),
    taskCheckboxHoverOutlineColor: Color(0x406974bc),
    taskDoneColor: Color(0xff74778b),
    taskStatusRed: Color(0xffff7881),
    taskStatusOrange: Color(0xfffbbb83),
    taskStatusYellow: Color(0xffffe88b),
    taskStatusCyan: Color(0xff86dfe2),
    taskStatusBlue: Color(0xff89bdf4),
    taskStatusPurple: Color(0xffcb9eff),
    taskStatusPink: Color(0xfff2b6de),
    headingAccents: <Color>[
      Color(0xffe06c75),
      Color(0xffd19a66),
      Color(0xffe5c07b),
      Color(0xff98c379),
      Color(0xff61afef),
      Color(0xffc678dd),
    ],
  );

  final Color surface;
  final Color surfaceMuted;
  final Color surfaceRaised;
  final Color surfaceHover;
  final Color border;
  final Color borderSoft;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color accent;
  final Color accentDark;
  final Color accentSoft;
  final Color accentMist;
  final Color error;
  final Color codeForeground;
  final Color inlineCodeForeground;
  final Color strongForeground;
  final Color emphasisForeground;
  final Color taskCheckboxColor;
  final Color taskCheckboxBorderColor;
  final Color taskCheckboxHoverOutlineColor;
  final Color taskDoneColor;
  final Color taskStatusRed;
  final Color taskStatusOrange;
  final Color taskStatusYellow;
  final Color taskStatusCyan;
  final Color taskStatusBlue;
  final Color taskStatusPurple;
  final Color taskStatusPink;
  final List<Color> headingAccents;
  final String monoFontFamily;
  final List<String> monoFontFamilyFallback;
  final double smallRadius;
  final double mediumRadius;
  final double largeRadius;

  Color headingAccent(int level) {
    if (headingAccents.isEmpty) return accent;
    final index = (level - 1).clamp(0, headingAccents.length - 1);
    return headingAccents[index];
  }

  static IanvsMarkdownThemeData resolve(
    BuildContext context, [
    IanvsMarkdownThemeData? override,
  ]) {
    return override ??
        Theme.of(context).extension<IanvsMarkdownThemeData>() ??
        (Theme.of(context).brightness == Brightness.dark ? dark : light);
  }

  @override
  IanvsMarkdownThemeData copyWith({
    Color? surface,
    Color? surfaceMuted,
    Color? surfaceRaised,
    Color? surfaceHover,
    Color? border,
    Color? borderSoft,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    Color? accentDark,
    Color? accentSoft,
    Color? accentMist,
    Color? error,
    Color? codeForeground,
    Color? inlineCodeForeground,
    Color? strongForeground,
    Color? emphasisForeground,
    Color? taskCheckboxColor,
    Color? taskCheckboxBorderColor,
    Color? taskCheckboxHoverOutlineColor,
    Color? taskDoneColor,
    Color? taskStatusRed,
    Color? taskStatusOrange,
    Color? taskStatusYellow,
    Color? taskStatusCyan,
    Color? taskStatusBlue,
    Color? taskStatusPurple,
    Color? taskStatusPink,
    List<Color>? headingAccents,
    String? monoFontFamily,
    List<String>? monoFontFamilyFallback,
    double? smallRadius,
    double? mediumRadius,
    double? largeRadius,
  }) {
    return IanvsMarkdownThemeData(
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      border: border ?? this.border,
      borderSoft: borderSoft ?? this.borderSoft,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accent: accent ?? this.accent,
      accentDark: accentDark ?? this.accentDark,
      accentSoft: accentSoft ?? this.accentSoft,
      accentMist: accentMist ?? this.accentMist,
      error: error ?? this.error,
      codeForeground: codeForeground ?? this.codeForeground,
      inlineCodeForeground: inlineCodeForeground ?? this.inlineCodeForeground,
      strongForeground: strongForeground ?? this.strongForeground,
      emphasisForeground: emphasisForeground ?? this.emphasisForeground,
      taskCheckboxColor: taskCheckboxColor ?? this.taskCheckboxColor,
      taskCheckboxBorderColor:
          taskCheckboxBorderColor ?? this.taskCheckboxBorderColor,
      taskCheckboxHoverOutlineColor:
          taskCheckboxHoverOutlineColor ?? this.taskCheckboxHoverOutlineColor,
      taskDoneColor: taskDoneColor ?? this.taskDoneColor,
      taskStatusRed: taskStatusRed ?? this.taskStatusRed,
      taskStatusOrange: taskStatusOrange ?? this.taskStatusOrange,
      taskStatusYellow: taskStatusYellow ?? this.taskStatusYellow,
      taskStatusCyan: taskStatusCyan ?? this.taskStatusCyan,
      taskStatusBlue: taskStatusBlue ?? this.taskStatusBlue,
      taskStatusPurple: taskStatusPurple ?? this.taskStatusPurple,
      taskStatusPink: taskStatusPink ?? this.taskStatusPink,
      headingAccents: headingAccents ?? this.headingAccents,
      monoFontFamily: monoFontFamily ?? this.monoFontFamily,
      monoFontFamilyFallback:
          monoFontFamilyFallback ?? this.monoFontFamilyFallback,
      smallRadius: smallRadius ?? this.smallRadius,
      mediumRadius: mediumRadius ?? this.mediumRadius,
      largeRadius: largeRadius ?? this.largeRadius,
    );
  }

  @override
  IanvsMarkdownThemeData lerp(
    covariant IanvsMarkdownThemeData? other,
    double t,
  ) {
    if (other == null) return this;
    return IanvsMarkdownThemeData(
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceHover: Color.lerp(surfaceHover, other.surfaceHover, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderSoft: Color.lerp(borderSoft, other.borderSoft, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentDark: Color.lerp(accentDark, other.accentDark, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      accentMist: Color.lerp(accentMist, other.accentMist, t)!,
      error: Color.lerp(error, other.error, t)!,
      codeForeground: Color.lerp(codeForeground, other.codeForeground, t)!,
      inlineCodeForeground: Color.lerp(
        inlineCodeForeground,
        other.inlineCodeForeground,
        t,
      )!,
      strongForeground: Color.lerp(
        strongForeground,
        other.strongForeground,
        t,
      )!,
      emphasisForeground: Color.lerp(
        emphasisForeground,
        other.emphasisForeground,
        t,
      )!,
      taskCheckboxColor: Color.lerp(
        taskCheckboxColor,
        other.taskCheckboxColor,
        t,
      )!,
      taskCheckboxBorderColor: Color.lerp(
        taskCheckboxBorderColor,
        other.taskCheckboxBorderColor,
        t,
      )!,
      taskCheckboxHoverOutlineColor: Color.lerp(
        taskCheckboxHoverOutlineColor,
        other.taskCheckboxHoverOutlineColor,
        t,
      )!,
      taskDoneColor: Color.lerp(taskDoneColor, other.taskDoneColor, t)!,
      taskStatusRed: Color.lerp(taskStatusRed, other.taskStatusRed, t)!,
      taskStatusOrange: Color.lerp(
        taskStatusOrange,
        other.taskStatusOrange,
        t,
      )!,
      taskStatusYellow: Color.lerp(
        taskStatusYellow,
        other.taskStatusYellow,
        t,
      )!,
      taskStatusCyan: Color.lerp(taskStatusCyan, other.taskStatusCyan, t)!,
      taskStatusBlue: Color.lerp(taskStatusBlue, other.taskStatusBlue, t)!,
      taskStatusPurple: Color.lerp(
        taskStatusPurple,
        other.taskStatusPurple,
        t,
      )!,
      taskStatusPink: Color.lerp(taskStatusPink, other.taskStatusPink, t)!,
      headingAccents: <Color>[
        for (var level = 1; level <= 6; level += 1)
          Color.lerp(headingAccent(level), other.headingAccent(level), t)!,
      ],
      monoFontFamily: t < .5 ? monoFontFamily : other.monoFontFamily,
      monoFontFamilyFallback: t < .5
          ? monoFontFamilyFallback
          : other.monoFontFamilyFallback,
      smallRadius: _lerpDouble(smallRadius, other.smallRadius, t),
      mediumRadius: _lerpDouble(mediumRadius, other.mediumRadius, t),
      largeRadius: _lerpDouble(largeRadius, other.largeRadius, t),
    );
  }
}

double _lerpDouble(double a, double b, double t) => a + (b - a) * t;
