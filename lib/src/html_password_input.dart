import 'package:markdown/markdown.dart' as md;

/// Preserves Obsidian's literal projection for unsupported password inputs.
///
/// Obsidian does not create a password control for this HTML. It hides only
/// the tag's outer angle brackets and leaves the tag name, attributes, and any
/// trailing text visible as ordinary document text.
class IanvsMarkdownHtmlPasswordInputSyntax extends md.BlockSyntax {
  const IanvsMarkdownHtmlPasswordInputSyntax();

  static final RegExp _line = RegExp(
    r'^ {0,3}<input\b([^>\n]*)/?>[ \t]*(.*)$',
    caseSensitive: false,
  );
  static final RegExp _typePassword = RegExp(
    r'''\btype\s*=\s*(?:"password"|'password'|password)(?:\s|/|$)''',
    caseSensitive: false,
  );

  @override
  RegExp get pattern => _line;

  @override
  bool canParse(md.BlockParser parser) {
    if (!super.canParse(parser)) return false;
    final match = _line.firstMatch(parser.current.content);
    return match != null && _typePassword.hasMatch(match.group(1) ?? '');
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final source = parser.current.content.trimLeft();
    final closingAngle = source.indexOf('>');
    final projected = closingAngle < 0
        ? source
        : '${source.substring(1, closingAngle)}${source.substring(closingAngle + 1)}';
    parser.advance();
    return md.Element('p', <md.Node>[md.Text(projected)]);
  }
}
