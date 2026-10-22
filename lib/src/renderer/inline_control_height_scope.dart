import 'package:flutter/widgets.dart';

/// Reference definitions stay rendered while focused, so their multiline
/// controls can determine row height without diverging from an editable-text
/// projection. Ordinary live-preview paragraphs retain their fixed strut.
class MarkdownInlineControlHeightScope extends InheritedWidget {
  const MarkdownInlineControlHeightScope({super.key, required super.child});

  static bool enabledOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<
            MarkdownInlineControlHeightScope
          >() !=
      null;

  @override
  bool updateShouldNotify(MarkdownInlineControlHeightScope oldWidget) => false;
}
