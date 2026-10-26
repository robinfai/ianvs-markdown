/// Optional native multi-format clipboard input and output. The Markdown renderer itself
/// does not depend on this package or its platform plugins.
library;

export 'src/writer.dart' show writeIanvsMarkdownRichClipboard;

export 'src/reader.dart'
    show IanvsMarkdownClipboardText, readIanvsMarkdownClipboardText;
