import 'package:flutter/material.dart';

/// One monochrome icon vocabulary. Toolbar glyphs are 16 pt, tree glyphs
/// 14 pt, and disclosure/close glyphs 12 pt. Action buttons have 28 pt targets;
/// tree disclosures use their row gutter, independently of the glyph size.
abstract final class AppIcons {
  static const sidebar = Icons.view_sidebar_outlined;
  static const outline = Icons.format_list_bulleted;
  static const folder = Icons.folder_outlined;
  static const openFolder = Icons.folder_open_outlined;
  static const document = Icons.description_outlined;
  static const search = Icons.search;
  static const add = Icons.add;
  static const close = Icons.close;
  static const disclosure = Icons.chevron_right;
  static const tabs = Icons.keyboard_arrow_down;
  static const check = Icons.check;
  static const info = Icons.info_outline;
}
