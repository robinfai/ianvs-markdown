import 'package:ianvs_markdown/ianvs_markdown.dart';

// Shared by the application and isolated Finder client. Byte limits at file
// boundaries remain separate from Dart's UTF-16 source length budget.
const linefoldDocumentRenderBudget = IanvsMarkdownRenderBudget(
  maxSourceCodeUnits: 8 * 1024 * 1024,
  maxLineCodeUnits: 16 * 1024,
  maxSyntaxTokens: 256 * 1024,
  maxSyntaxTokensBetweenBlankLines: 8 * 1024,
  maxDenseSyntaxTokensBetweenBlankLines: 4 * 1024,
  maxCodeUnitsBetweenBlankLines: 256 * 1024,
);
