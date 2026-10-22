import 'package:flutter/foundation.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// The parsed syntax that produced a link, independent of its destination.
enum IanvsMarkdownLinkKind { markdown, wiki, tag }

/// A rendered link interaction, without host-specific path resolution.
@immutable
final class IanvsMarkdownLinkTarget {
  const IanvsMarkdownLinkTarget({
    required this.text,
    required this.href,
    required this.kind,
    this.title = '',
  });

  /// Display text, including a Wiki link's alias when one is present.
  final String text;

  /// The renderer's destination, before host resolution. Wiki links preserve
  /// their complete parsed target, including any heading or block fragment.
  /// Ordinary Markdown links retain the legacy callback's destination behavior.
  final String? href;

  final String title;
  final IanvsMarkdownLinkKind kind;
}

/// Receives typed link interactions in preference to the legacy callback.
typedef IanvsMarkdownTapLinkTargetCallback =
    void Function(IanvsMarkdownLinkTarget target);

/// Internal single-dispatch bridge; excluded from the package's public export.
void dispatchIanvsMarkdownLinkTap(
  IanvsMarkdownLinkTarget target, {
  IanvsMarkdownTapLinkTargetCallback? onTapLinkTarget,
  MarkdownTapLinkCallback? onTapLink,
}) {
  if (onTapLinkTarget != null) {
    onTapLinkTarget(target);
  } else {
    onTapLink?.call(target.text, target.href, target.title);
  }
}
