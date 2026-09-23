import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  group('scanMarkdownForRendering', () {
    test('charges math delimiters only for the Obsidian preset', () {
      const budget = IanvsMarkdownRenderBudget(maxSyntaxTokens: 0);
      final standard = scanMarkdownForRendering(
        r'currency $$$$ and $x$',
        budget: budget,
        syntaxPreset: IanvsMarkdownSyntaxPreset.standard,
      );
      final obsidian = scanMarkdownForRendering(r'$x$', budget: budget);
      expect(standard.useMarkdown, isTrue);
      expect(standard.syntaxTokens, 0);
      expect(obsidian.useMarkdown, isFalse);
    });

    test('standard exact and plus-one limits preserve UTF-8 fallback', () {
      const source = '**😀**';
      final exact = scanMarkdownForRendering(
        source,
        budget: const IanvsMarkdownRenderBudget(maxSyntaxTokens: 4),
        syntaxPreset: IanvsMarkdownSyntaxPreset.standard,
      );
      final overflow = scanMarkdownForRendering(
        source,
        budget: const IanvsMarkdownRenderBudget(
          maxSyntaxTokens: 3,
          maxFallbackBytes: 6,
        ),
        syntaxPreset: IanvsMarkdownSyntaxPreset.standard,
      );
      expect(exact.useMarkdown, isTrue);
      expect(exact.syntaxTokens, 4);
      expect(overflow.useMarkdown, isFalse);
      expect(overflow.text, '**😀');
      expect(overflow.truncated, isTrue);
    });

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
