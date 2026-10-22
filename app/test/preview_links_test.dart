import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:linefold/src/preview/preview_library.dart';
import 'package:linefold/src/preview/preview_links.dart';

void main() {
  final docs = [
    for (final path in [
      '/vault/a/note.md',
      '/vault/b/note.md',
      '/vault/space note.md',
      '/vault/字%20面.md',
    ])
      PreviewDocument(path: path, name: path, openedAt: DateTime(2026)),
  ];
  PreviewLinkDestination resolve(String href, {bool wiki = false}) =>
      resolvePreviewLink(
        link: IanvsMarkdownLinkTarget(
          text: '',
          href: href,
          kind: wiki
              ? IanvsMarkdownLinkKind.wiki
              : IanvsMarkdownLinkKind.markdown,
        ),
        root: '/vault',
        origin: '/vault/a/note.md',
        documents: docs,
      );
  test(
    'ordinary relative and percent encoded links resolve only catalogued scoped Markdown',
    () {
      expect(resolve('../space%20note.md#标题').paths, ['/vault/space note.md']);
      expect(resolve('../space%20note.md#标题').fragment, '标题');
      expect(resolve('../字%2520面.md').paths, ['/vault/字%20面.md']);
      expect(resolve('#Heading').paths, ['/vault/a/note.md']);
      for (final target in [
        '../../outside.md',
        'file:///vault/b/note.md',
        '//host/a.md',
        '../missing.md',
        '../a.png',
        'javascript:foo',
        '../.hidden/note.md',
      ]) {
        expect(() => resolve(target), throwsFormatException, reason: target);
      }
    },
  );
  test(
    'Wiki basename collisions stay ambiguous, paths are root based and percent literals stay literal',
    () {
      expect(resolve('note', wiki: true).paths, [
        '/vault/a/note.md',
        '/vault/b/note.md',
      ]);
      expect(resolve('b/note#标题', wiki: true).paths, ['/vault/b/note.md']);
      expect(resolve('字%20面', wiki: true).paths, ['/vault/字%20面.md']);
      expect(() => resolve('note#^block', wiki: true), throwsFormatException);
    },
  );
}
