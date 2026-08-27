import 'package:markdown/markdown.dart' as md;

import 'footnote_syntax.dart';
import 'markdown_link_source.dart';

/// Keeps full-reference labels with Obsidian-non-normalizing whitespace
/// literal, instead of letting CommonMark collapse them onto a definition.
final class IanvsMarkdownLiteralReferenceWhitespaceSyntax
    extends md.InlineSyntax {
  IanvsMarkdownLiteralReferenceWhitespaceSyntax()
    : super(r'\[', startCharacter: 0x5b);

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    final start = startMatchPos ?? parser.pos;
    final source = parser.source;
    if (start != parser.pos ||
        start >= source.length ||
        source.codeUnitAt(start) != 0x5b ||
        isIanvsMarkdownEscapedAt(source, start)) {
      return false;
    }
    final primaryEnd = findIanvsMarkdownLinkLabelEnd(source, start);
    if (primaryEnd == null ||
        primaryEnd + 1 >= source.length ||
        source.codeUnitAt(primaryEnd + 1) != 0x5b) {
      return false;
    }
    final secondaryStart = primaryEnd + 1;
    final secondary = findIanvsMarkdownReferenceLabel(source, secondaryStart);
    if (secondary == null) return false;
    final rawSecondary = source.substring(
      secondaryStart + 1,
      secondary.end - 1,
    );
    if (!hasIanvsMarkdownLiteralReferenceWhitespace(rawSecondary)) {
      return false;
    }

    parser.writeText();
    parser
      ..addNode(md.Text(source.substring(start, secondary.end)))
      ..consume(secondary.end - start);
    return true;
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) => false;
}

/// A source-preserving autolink match shared by rendering and live editing.
final class IanvsMarkdownAutolinkMatch {
  const IanvsMarkdownAutolinkMatch({
    required this.start,
    required this.end,
    required this.labelStart,
    required this.labelEnd,
    required this.destination,
    required this.angleWrapped,
    required this.escapedAngle,
  });

  final int start;
  final int end;
  final int labelStart;
  final int labelEnd;
  final String destination;
  final bool angleWrapped;
  final bool escapedAngle;
}

final _obsidianExtendedUrlPattern = RegExp(
  r'(?:(?:https?|ftp):\/\/|www\.)'
  r'(?:[-_a-z0-9]+\.)*(?:[-a-z0-9]+\.[-a-z0-9]+)'
  r'[^\s<>]*'
  r'[^\s<>?!.,:*_~]',
  caseSensitive: false,
);

final _obsidianExtendedEmailPattern = RegExp(
  r'[-_.+a-z0-9]+@(?:[-_a-z0-9]+\.)+[-_a-z0-9]*[a-z0-9]',
  caseSensitive: false,
);

final _obsidianAngleSchemePattern = RegExp(
  r'^[a-z][a-z0-9+.-]{1,31}:[^\s<>]*$',
  caseSensitive: false,
);

final _obsidianAngleEmailPattern = RegExp(
  r'''^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@'''
  r'''[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?'''
  r'''(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*$''',
  caseSensitive: false,
);

IanvsMarkdownAutolinkMatch? matchIanvsMarkdownAutolinkAt(
  String source,
  int offset,
) {
  if (offset < 0 || offset >= source.length) return null;

  final angle = _matchObsidianAngleAutolink(source, offset);
  if (angle != null) return angle;

  final url = _obsidianExtendedUrlPattern.matchAsPrefix(source, offset);
  if (url != null) {
    var end = _obsidianUrlEnd(source, offset, url.end);
    if (end <= offset) return null;
    final angleWwwFallback =
        offset > 0 &&
        source.codeUnitAt(offset - 1) == 0x3c &&
        !isIanvsMarkdownEscapedAt(source, offset - 1) &&
        source.substring(offset, end).toLowerCase().startsWith('www.') &&
        end < source.length &&
        source.codeUnitAt(end) == 0x3e;
    if (angleWwwFallback) end += 1;
    final label = source.substring(offset, end);
    final destination = label.toLowerCase().startsWith('www.')
        ? 'http://$label'
        : label;
    return IanvsMarkdownAutolinkMatch(
      start: offset,
      end: end,
      labelStart: offset,
      labelEnd: end,
      destination: destination,
      angleWrapped: false,
      escapedAngle: false,
    );
  }

  final email = _obsidianExtendedEmailPattern.matchAsPrefix(source, offset);
  if (email == null) return null;
  if (email.end < source.length) {
    final following = source.codeUnitAt(email.end);
    if (following == 0x5f || following == 0x2d) return null;
  }
  final label = source.substring(offset, email.end);
  return IanvsMarkdownAutolinkMatch(
    start: offset,
    end: email.end,
    labelStart: offset,
    labelEnd: email.end,
    destination: 'mailto:$label',
    angleWrapped: false,
    escapedAngle: false,
  );
}

IanvsMarkdownAutolinkMatch? _matchObsidianAngleAutolink(
  String source,
  int offset,
) {
  final escaped =
      source.codeUnitAt(offset) == 0x5c &&
      offset + 1 < source.length &&
      source.codeUnitAt(offset + 1) == 0x3c;
  final angleStart = escaped ? offset + 1 : offset;
  if (source.codeUnitAt(angleStart) != 0x3c) return null;

  final close = source.indexOf('>', angleStart + 1);
  if (close < 0) return null;
  final lineBreak = source.indexOf('\n', angleStart + 1);
  if (lineBreak >= 0 && lineBreak < close) return null;
  final labelStart = angleStart + 1;
  final label = source.substring(labelStart, close);
  final isEmail = _obsidianAngleEmailPattern.hasMatch(label);
  if (!isEmail && !_obsidianAngleSchemePattern.hasMatch(label)) return null;

  return IanvsMarkdownAutolinkMatch(
    start: offset,
    end: close + 1,
    labelStart: labelStart,
    labelEnd: close,
    destination: isEmail ? 'mailto:$label' : label,
    angleWrapped: true,
    escapedAngle: escaped,
  );
}

int _obsidianUrlEnd(String source, int start, int candidateEnd) {
  var end = candidateEnd;
  // Obsidian leaves ordinary ASCII sentence punctuation outside a bare URL,
  // while non-ASCII punctuation (for example Chinese `。` and `，`) remains
  // part of the destination and is percent-encoded by the renderer.
  while (end > start) {
    final trailing = source.codeUnitAt(end - 1);
    if (trailing != 0x2e && trailing != 0x2c && trailing != 0x3b) break;
    end -= 1;
  }
  if (end > start && source.codeUnitAt(end - 1) == 0x29) {
    var balance = 0;
    for (var index = start; index < end; index += 1) {
      final character = source.codeUnitAt(index);
      if (character == 0x28) {
        balance += 1;
      } else if (character == 0x29) {
        balance -= 1;
      }
    }
    while (balance < 0 && end > start && source.codeUnitAt(end - 1) == 0x29) {
      end -= 1;
      balance += 1;
    }
  }
  return end;
}

/// Parses Obsidian-compatible bare, email, and angle-bracket autolinks.
class IanvsMarkdownAutolinkSyntax extends md.InlineSyntax {
  IanvsMarkdownAutolinkSyntax() : super(r'(?!)');

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    final start = startMatchPos ?? parser.pos;
    final match = matchIanvsMarkdownAutolinkAt(parser.source, start);
    if (match == null || match.start != parser.pos) return false;

    parser.writeText();
    if (match.escapedAngle) parser.addNode(md.Text(r'\'));
    final label = parser.source.substring(match.labelStart, match.labelEnd);
    final anchor = md.Element.text('a', label)
      ..attributes['href'] = Uri.encodeFull(match.destination)
      ..attributes['data-ianvs-autolink'] = 'true';
    parser
      ..addNode(anchor)
      ..consume(match.end - match.start);
    return true;
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) => false;
}
