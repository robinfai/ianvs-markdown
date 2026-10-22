import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/services/attachment_resolver.dart';

String normalize(String value) =>
    value.replaceAll('e\u0301', 'é').toLowerCase();
AttachmentMetadata entry(String path) => AttachmentMetadata(
  relativePath: path,
  comparisonPath: normalize(path),
  size: 10,
  modified: 1,
);
AttachmentMetadata resolve(
  List<String> files,
  String target, {
  AttachmentLinkKind kind = AttachmentLinkKind.wiki,
  String note = 'notes/note.md',
}) {
  final reference = AttachmentReference(target, kind);
  return AttachmentIndex(files.map(entry)).resolve(
    reference: reference,
    documentRelativePath: note,
    normalizedReference: normalize(reference.path),
    normalizedDocument: normalize(note),
  );
}

Matcher failure(AttachmentFailureKind kind) =>
    isA<AttachmentFailure>().having((error) => error.kind, 'kind', kind);

void main() {
  for (final (setting, path, markdown) in [
    ('/', 'pic.png', '../pic.png'),
    ('assets', 'assets/pic.png', '../assets/pic.png'),
    ('./', 'notes/pic.png', './pic.png'),
    ('./assets', 'notes/assets/pic.png', './assets/pic.png'),
  ]) {
    test(
      'folder fixture $setting supports existing Wiki and Markdown images',
      () {
        final settings = ObsidianAttachmentSettings.parse(
          utf8.encode(jsonEncode({'attachmentFolderPath': setting})),
        );
        expect(settings.malformed, isFalse);
        expect(resolve([path], 'pic.png').relativePath, path);
        expect(
          resolve(
            [path],
            markdown,
            kind: AttachmentLinkKind.markdown,
          ).relativePath,
          path,
        );
        // The new-file preference must NOT hide older attachments elsewhere.
        expect(
          resolve([path, 'old/older.png'], 'older.png').relativePath,
          'old/older.png',
        );
      },
    );
  }

  test(
    'settings reads one optional field and fails closed on bad destinations',
    () {
      for (final value in ['', '/', './', './assets', '附件/截图']) {
        final settings = ObsidianAttachmentSettings.parse(
          utf8.encode(
            jsonEncode({'attachmentFolderPath': value, 'secret': 'unused'}),
          ),
        );
        expect(settings.folderPath, value);
        expect(settings.malformed, isFalse);
      }
      for (final value in [
        '../outside',
        '/private',
        'file:assets',
        String.fromCharCode(0xd800),
        String.fromCharCode(0xdc00),
        String.fromCharCode(0x7f),
        '.obsidian',
        r'a\b',
      ]) {
        expect(
          ObsidianAttachmentSettings.parse(
            utf8.encode(jsonEncode({'attachmentFolderPath': value})),
          ).malformed,
          isTrue,
        );
      }
      for (final bytes in [
        utf8.encode('{bad'),
        utf8.encode('[]'),
        [255],
        List.filled(65537, 32),
        utf8.encode('{"attachmentFolderPath":42}'),
        utf8.encode('{"attachmentFolderPath":null}'),
      ]) {
        expect(ObsidianAttachmentSettings.parse(bytes).malformed, isTrue);
      }
      expect(
        ObsidianAttachmentSettings.parse(utf8.encode('{}')).folderPath,
        isNull,
      );
    },
  );

  test(
    'Markdown relative wins, root fallback does not use arbitrary basename',
    () {
      const files = ['notes/pic.png', 'pic.png', 'assets/only.png'];
      expect(
        resolve(
          files,
          'pic.png',
          kind: AttachmentLinkKind.markdown,
        ).relativePath,
        'notes/pic.png',
      );
      expect(
        resolve(
          files,
          '/pic.png',
          kind: AttachmentLinkKind.markdown,
        ).relativePath,
        'pic.png',
      );
      expect(
        resolve(
          files,
          'assets/only.png',
          kind: AttachmentLinkKind.markdown,
        ).relativePath,
        'assets/only.png',
      );
      expect(
        () => resolve(files, 'only.png', kind: AttachmentLinkKind.markdown),
        throwsA(failure(AttachmentFailureKind.missing)),
      );
      expect(
        () => resolve(
          files,
          './assets/only.png',
          kind: AttachmentLinkKind.markdown,
        ),
        throwsA(failure(AttachmentFailureKind.missing)),
      );
    },
  );

  test(
    'Wiki shortest suffix and exact full paths disambiguate without guessing',
    () {
      const files = ['one/pic.png', 'two/pic.png', 'old/two/unique.png'];
      expect(
        () => resolve(files, 'pic.png'),
        throwsA(failure(AttachmentFailureKind.ambiguous)),
      );
      expect(resolve(files, 'one/pic.png').relativePath, 'one/pic.png');
      expect(
        resolve(files, 'two/unique.png').relativePath,
        'old/two/unique.png',
      );
      expect(
        () => resolve(['pic.png', 'else/pic.png'], 'pic.png'),
        throwsA(failure(AttachmentFailureKind.ambiguous)),
      );
    },
  );

  test('root-anchored Wiki paths never fall back to a suffix match', () {
    const files = [
      'archive/assets/chart.png',
      'assets/exact.png',
      'archive/assets/exact.png',
      'Assets/CASE.PNG',
      'archive/assets/case.png',
      'Images/cafe\u0301.png',
    ];
    for (final target in [
      '/assets/chart.png',
      '/chart.png',
      './assets/chart.png',
      '../assets/chart.png',
    ]) {
      expect(
        () => resolve(files, target),
        throwsA(failure(AttachmentFailureKind.missing)),
      );
    }
    expect(
      resolve(files, '/assets/exact.png').relativePath,
      'assets/exact.png',
    );
    expect(resolve(files, '/assets/case.png').relativePath, 'Assets/CASE.PNG');
    expect(resolve(files, '/images/café.png').relativePath, files.last);
    expect(
      () => resolve(['Assets/x.png', 'ASSETS/X.PNG'], '/assets/x.png'),
      throwsA(failure(AttachmentFailureKind.ambiguous)),
    );
    // Only an unanchored Wiki target may use the unique suffix fallback.
    expect(
      resolve(files, 'assets/chart.png').relativePath,
      'archive/assets/chart.png',
    );
  });

  test(
    'Chinese, spaces, URL encoding, case and NFC/NFD preserve actual path',
    () {
      const files = ['附件/中文 图片.PNG', 'notes/cafe\u0301.png', 'literal%20.png'];
      expect(
        resolve(
          files,
          '../附件/中文%20图片.PNG',
          kind: AttachmentLinkKind.markdown,
        ).relativePath,
        files[0],
      );
      expect(resolve(files, 'CAFÉ.PNG').relativePath, files[1]);
      expect(
        resolve(
          files,
          'literal%2520.png',
          kind: AttachmentLinkKind.markdown,
        ).relativePath,
        files[2],
      );
      expect(resolve(files, 'literal%20.png').relativePath, files[2]);
      expect(
        resolve(
          files,
          '../附件/中文%20图片.PNG',
          kind: AttachmentLinkKind.markdown,
        ).relativePath,
        files[0],
      );
      expect(
        () => resolve(['x/café.png', 'y/cafe\u0301.png'], 'café.png'),
        throwsA(failure(AttachmentFailureKind.ambiguous)),
      );
      expect(
        resolve(['x/A.png', 'x/a.png'], 'x/A.png').relativePath,
        'x/A.png',
      );
      expect(
        () => resolve(['x/A.png', 'x/a.png'], 'A.png'),
        throwsA(failure(AttachmentFailureKind.ambiguous)),
      );
    },
  );

  test(
    'plain internal parent paths allowed, traversal and schemes rejected',
    () {
      expect(resolve(['pic.png'], '../pic.png').relativePath, 'pic.png');
      expect(
        resolve(
          ['pic.png'],
          '%2e%2e/pic.png',
          kind: AttachmentLinkKind.markdown,
        ).relativePath,
        'pic.png',
      );
      expect(
        resolve(
          ['a/b.png'],
          'a%2fb.png',
          kind: AttachmentLinkKind.markdown,
        ).relativePath,
        'a/b.png',
      );
      expect(
        resolve(
          ['%2e%2e/pic.png'],
          '%252e%252e/pic.png',
          kind: AttachmentLinkKind.markdown,
        ).relativePath,
        '%2e%2e/pic.png',
      );
      expect(
        () => resolve(
          ['pic.png'],
          '%2e%2e/%2e%2e/outside.png',
          kind: AttachmentLinkKind.markdown,
        ),
        throwsA(failure(AttachmentFailureKind.invalid)),
      );
      for (final target in ['../../outside.png', '../outside.png']) {
        expect(
          () => resolve(['pic.png'], target, note: 'note.md'),
          throwsA(failure(AttachmentFailureKind.invalid)),
        );
      }
      for (final target in [
        r'a\b.png',
        '//server/pic.png',
        'pic.png?secret=1',
        'pic.png#frag',
      ]) {
        expect(
          () => AttachmentReference(target, AttachmentLinkKind.markdown),
          throwsA(failure(AttachmentFailureKind.invalid)),
        );
      }
      for (final target in [
        'file:///pic.png',
        'https://example.com/pic.png',
        'data:image/png;base64,abc',
        'blob:local.png',
        'picture.svg',
        'picture.avif',
      ]) {
        expect(
          () => AttachmentReference(target, AttachmentLinkKind.wiki),
          throwsA(failure(AttachmentFailureKind.unsupported)),
        );
      }
    },
  );

  test(
    'Wiki percent characters select literal names and never URI alternatives',
    () {
      const files = ['literal%20.png', 'literal .png', '%2e%2e/pic.png'];
      expect(resolve(files, 'literal%20.png').relativePath, 'literal%20.png');
      expect(
        resolve(
          files,
          'literal%20.png',
          kind: AttachmentLinkKind.markdown,
        ).relativePath,
        'literal .png',
      );
      expect(resolve(files, '%2e%2e/pic.png').relativePath, '%2e%2e/pic.png');
    },
  );

  test('index rejects unsafe, hidden and unsupported metadata', () {
    for (final path in [
      '../outside.png',
      '/outside.png',
      '.obsidian/pic.png',
      'a/../pic.png',
      'image.svg',
    ]) {
      expect(
        () => AttachmentIndex([entry(path)]),
        throwsA(failure(AttachmentFailureKind.invalid)),
      );
    }
  });
}
