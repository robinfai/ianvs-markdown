import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  group('scanMarkdownForRendering', () {
    test('keeps Markdown at the exact syntax limit', () {
      const source = '# Title\n\n**strong** and [link](target.md)';
      final measured = scanMarkdownForRendering(
        source,
        budget: const IanvsMarkdownRenderBudget(
          maxSyntaxTokens: 1000,
          maxFallbackBytes: 1000,
        ),
      );
      final exact = scanMarkdownForRendering(
        source,
        budget: IanvsMarkdownRenderBudget(
          maxSyntaxTokens: measured.syntaxTokens,
          maxFallbackBytes: 1000,
        ),
      );
      final overflow = scanMarkdownForRendering(
        source,
        budget: IanvsMarkdownRenderBudget(
          maxSyntaxTokens: measured.syntaxTokens - 1,
          maxFallbackBytes: 1000,
        ),
      );

      expect(exact.useMarkdown, isTrue);
      expect(overflow.useMarkdown, isFalse);
    });

    test('bounds fallback by UTF-8 scalars', () {
      final decision = scanMarkdownForRendering(
        '**😀😀😀**',
        budget: const IanvsMarkdownRenderBudget(
          maxSyntaxTokens: 0,
          maxFallbackBytes: 6,
        ),
      );

      expect(decision.useMarkdown, isFalse);
      expect(decision.text, '**😀');
      expect(decision.truncated, isTrue);
    });
  });
}
