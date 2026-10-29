import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/services/outline_operations.dart';

void main() {
  test('moving parent moves descendants and preserves fenced heading text', () {
    const source = '# A\na\n## Child\n```\n# fake\n```\n# B\nb\n';
    expect(moveChapter(source, 0, 3), '# B\nb\n# A\na\n## Child\n```\n# fake\n```\n');
    expect(moveChapter(source, 0, 1), source);
    expect(moveChapter(source, 2, 0), '# B\nb\n# A\na\n## Child\n```\n# fake\n```\n');
  });

  test('chapter levels include descendants without touching code and YAML', () {
    const source = '---\ntitle: Example\n---\n# A\n## Child\n```\n# fake\n```\n# B\n';
    expect(changeChapterLevel(source, 0, 1), '---\ntitle: Example\n---\n## A\n### Child\n```\n# fake\n```\n# B\n');
    expect(changeChapterLevel(source, 0, -1), source);
  });

  test('moving final chapter without newline keeps headings separate', () {
    expect(moveChapter('# A\na\n# B\nb', 1, 0), '# B\nb\n# A\na\n');
  });
}
