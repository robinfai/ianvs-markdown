import 'package:flutter/material.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'models/reading_preferences.dart';

MarkdownStyleSheet readingStyleSheet(
  BuildContext context,
  ReadingPreferences preferences,
) {
  final base = ianvsMarkdownStyleSheet(context);
  final scale = preferences.fontSize / ReadingPreferences.defaults.fontSize;
  TextStyle? heading(TextStyle? style) =>
      style?.copyWith(fontSize: (style.fontSize ?? 14.5) * scale);
  return base.copyWith(
    p: base.p?.copyWith(
      fontSize: preferences.fontSize,
      height: preferences.lineHeight,
    ),
    listBullet: base.listBullet?.copyWith(
      fontSize: preferences.fontSize,
      height: preferences.lineHeight,
    ),
    h1: heading(base.h1),
    h2: heading(base.h2),
    h3: heading(base.h3),
    h4: heading(base.h4),
    h5: heading(base.h5),
    h6: heading(base.h6),
    tableHead: base.tableHead?.copyWith(
      fontSize: preferences.fontSize,
      height: preferences.lineHeight,
    ),
    tableBody: base.tableBody?.copyWith(
      fontSize: preferences.fontSize,
      height: preferences.lineHeight,
    ),
    code: heading(base.code),
  );
}
