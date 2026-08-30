import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'theme.dart';

/// Parses the line-delimited HTML `pre` form projected by Obsidian.
///
/// The tags are projection metadata: the literal body keeps its physical
/// newlines and is presented as a small, monospaced preformatted region. The
/// resulting widget intentionally has no local gesture recognizer, allowing a
/// normal Live Preview click to select and edit the complete original block.
class IanvsMarkdownHtmlPreSyntax extends md.BlockSyntax {
  const IanvsMarkdownHtmlPreSyntax();

  static final RegExp _open = RegExp(
    r'^ {0,3}<pre(?:\s[^>\n]*)?>(.*)$',
    caseSensitive: false,
  );
  static final RegExp _close = RegExp(
    r'^(.*)</pre\s*>[ \t]*$',
    caseSensitive: false,
  );

  @override
  RegExp get pattern => _open;

  @override
  bool canParse(md.BlockParser parser) {
    if (!super.canParse(parser)) return false;
    final opening = _open.firstMatch(parser.current.content);
    if (opening == null) return false;
    if (_close.hasMatch(opening.group(1) ?? '')) return true;
    for (var offset = 1; ; offset += 1) {
      final line = parser.peek(offset);
      if (line == null) return false;
      if (_close.hasMatch(line.content)) return true;
    }
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final opening = _open.firstMatch(parser.current.content)!;
    final bodyLines = <String>[];
    var firstBody = opening.group(1) ?? '';
    final inlineClose = _close.firstMatch(firstBody);
    if (inlineClose != null) {
      bodyLines.add(inlineClose.group(1) ?? '');
      parser.advance();
    } else {
      if (firstBody.isNotEmpty) bodyLines.add(firstBody);
      parser.advance();
      while (!parser.isDone) {
        final close = _close.firstMatch(parser.current.content);
        if (close != null) {
          bodyLines.add(close.group(1) ?? '');
          parser.advance();
          break;
        }
        bodyLines.add(parser.current.content);
        parser.advance();
      }
    }
    return md.Element.empty('ianvs-html-pre')
      ..attributes['data-body'] = bodyLines.join('\n');
  }
}

class IanvsMarkdownHtmlPreBuilder extends MarkdownElementBuilder {
  IanvsMarkdownHtmlPreBuilder({this.theme});

  final IanvsMarkdownThemeData? theme;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => IanvsMarkdownHtmlPreformattedBlock(
    source: element.attributes['data-body'] ?? '',
    theme: theme,
  );
}

/// Obsidian-like passive projection for an HTML `pre` block.
class IanvsMarkdownHtmlPreformattedBlock extends StatelessWidget {
  const IanvsMarkdownHtmlPreformattedBlock({
    super.key,
    required this.source,
    this.theme,
  });

  final String source;
  final IanvsMarkdownThemeData? theme;

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context, theme);
    return CustomPaint(
      key: const ValueKey('ianvs-markdown-html-pre'),
      foregroundPainter: _IanvsMarkdownDashedBorderPainter(colors.borderSoft),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          source,
          style: TextStyle(
            color: colors.codeForeground,
            fontFamily: colors.monoFontFamily,
            fontFamilyFallback: colors.monoFontFamilyFallback,
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

class _IanvsMarkdownDashedBorderPainter extends CustomPainter {
  const _IanvsMarkdownDashedBorderPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final rect = Offset(.5, .5) & Size(size.width - 1, size.height - 1);
    _drawDashedLine(canvas, rect.topLeft, rect.topRight, paint);
    _drawDashedLine(canvas, rect.topRight, rect.bottomRight, paint);
    _drawDashedLine(canvas, rect.bottomRight, rect.bottomLeft, paint);
    _drawDashedLine(canvas, rect.bottomLeft, rect.topLeft, paint);
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    final delta = end - start;
    final distance = delta.distance;
    if (distance == 0) return;
    final direction = delta / distance;
    for (var position = 0.0; position < distance; position += 4) {
      canvas.drawLine(
        start + direction * position,
        start + direction * (position + 2).clamp(0.0, distance),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _IanvsMarkdownDashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}
