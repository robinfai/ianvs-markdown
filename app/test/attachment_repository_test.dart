import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/services/apple_workspace_service.dart';
import 'package:linefold/src/services/attachment_repository.dart';
import 'package:linefold/src/services/attachment_resolver.dart';

import 'attachment_test_support.dart';

Matcher failure(AttachmentFailureKind kind) =>
    isA<AttachmentFailure>().having((e) => e.kind, 'kind', kind);
Future<AttachmentImageLease> load(
  AttachmentRepository repository, {
  String? documentPath = '/vault/note.md',
  String target = 'image.png',
  AttachmentLinkKind kind = AttachmentLinkKind.wiki,
}) => repository.load(documentPath: documentPath, target: target, kind: kind);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final extension in ['png', 'jpg', 'gif', 'webp', 'bmp']) {
    test(
      'real $extension fixture decodes to a bounded still preview',
      () async {
        final source = FakeAttachmentSource()
          ..files['fixture.$extension'] = await File(
            'test/fixtures/attachments/raster.$extension',
          ).readAsBytes();
        final repository = AttachmentRepository(root: '/vault', source: source);
        addTearDown(repository.dispose);
        final lease = await load(repository, target: 'fixture.$extension');
        expect(lease.image.width, 2);
        expect(lease.image.height, 1);
        lease.dispose();
      },
    );
  }

  test(
    'pixel bombs and corrupt raster bytes fail recoverably before display',
    () async {
      final source = FakeAttachmentSource()
        ..files['huge.png'] = await File(
          'test/fixtures/attachments/oversized-header.png',
        ).readAsBytes()
        ..files['bad.png'] = Uint8List.fromList([1, 2, 3])
        ..files['forged.png'] = tinyPng.sublist(0, 8);
      final repository = AttachmentRepository(root: '/vault', source: source);
      addTearDown(repository.dispose);
      await expectLater(
        load(repository, target: 'huge.png'),
        throwsA(failure(AttachmentFailureKind.tooLarge)),
      );
      await expectLater(
        load(repository, target: 'bad.png'),
        throwsA(failure(AttachmentFailureKind.unsupported)),
      );
      await expectLater(
        load(repository, target: 'forged.png'),
        throwsA(failure(AttachmentFailureKind.unavailable)),
      );
      final lease = await load(repository);
      expect(lease.image.width, 1);
      lease.dispose();
    },
  );

  for (final extension in ['gif', 'webp']) {
    test(
      'oversized animated $extension is refused before first-frame decoding',
      () async {
        final source = FakeAttachmentSource()
          ..files['large.$extension'] = await File(
            'test/fixtures/attachments/oversized-animation.$extension',
          ).readAsBytes();
        final repository = AttachmentRepository(
          root: '/vault',
          source: source,
          maximumCacheBytes: 16 * 1024 * 1024,
        );
        addTearDown(repository.dispose);
        await expectLater(
          load(repository, target: 'large.$extension'),
          throwsA(failure(AttachmentFailureKind.tooLarge)),
        );
        final healthy = await load(repository);
        expect(healthy.image.width, 1);
        healthy.dispose();
      },
    );
  }

  test(
    'small animated WebP succeeds and its real frame fits the cache budget',
    () async {
      final bytes = await File(
        'test/fixtures/attachments/small-animation.webp',
      ).readAsBytes();
      final source = FakeAttachmentSource()..files['small.webp'] = bytes;
      for (final budget in [4, 8]) {
        final repository = AttachmentRepository(
          root: '/vault',
          source: source,
          maximumCacheBytes: budget,
        );
        if (budget == 4) {
          await expectLater(
            load(repository, target: 'small.webp'),
            throwsA(failure(AttachmentFailureKind.tooLarge)),
          );
        } else {
          final image = await load(repository, target: 'small.webp');
          expect(image.image.width * image.image.height * 4, budget);
          image.dispose();
        }
        repository.dispose();
      }
    },
  );

  test(
    'single-frame wide image is still downsampled to the output cap',
    () async {
      final source = FakeAttachmentSource()
        ..files['wide.png'] = await File(
          'test/fixtures/attachments/wide-static.png',
        ).readAsBytes();
      final repository = AttachmentRepository(root: '/vault', source: source);
      addTearDown(repository.dispose);
      final image = await load(repository, target: 'wide.png');
      expect(image.image.width, AttachmentRepository.maximumDecodedSide);
      expect(image.image.height, 1);
      image.dispose();
    },
  );

  test(
    'actual format allowlist rejects a WBMP disguised with PNG suffix',
    () async {
      final source = FakeAttachmentSource()
        ..files['disguised.png'] = Uint8List.fromList([0, 0, 1, 1, 0]);
      final repository = AttachmentRepository(root: '/vault', source: source);
      addTearDown(repository.dispose);
      await expectLater(
        load(repository, target: 'disguised.png'),
        throwsA(failure(AttachmentFailureKind.unsupported)),
      );
    },
  );

  test(
    'decode working budget includes source copies, input and pinned cache',
    () async {
      final bytes = await File(
        'test/fixtures/attachments/raster.png',
      ).readAsBytes();
      final source = FakeAttachmentSource()..files['other.png'] = bytes;
      final repository = AttachmentRepository(
        root: '/vault',
        source: source,
        maximumDecodeWorkingBytes: bytes.length * 2 + 2 * 1 * 4 * 3 + 2 * 1 * 4,
      );
      addTearDown(repository.dispose);
      final pinned = await load(repository);
      await expectLater(
        load(repository, target: 'other.png'),
        throwsA(failure(AttachmentFailureKind.tooLarge)),
      );
      pinned.dispose();
      final other = await load(repository, target: 'other.png');
      expect(other.image.width, 2);
      other.dispose();
    },
  );

  test(
    'slow metadata enumeration does not start overlapping refreshes',
    () async {
      final source = FakeAttachmentSource();
      final gate = Completer<void>();
      source.beforeList = gate.future;
      final repository = AttachmentRepository(root: '/vault', source: source);
      final pending = load(repository);
      repository.refresh();
      repository.refresh();
      expect(source.listCalls, 1);
      gate.complete();
      final image = await pending;
      image.dispose();
      repository.dispose();
    },
  );

  test(
    'encoded traversal never sends an unbounded path to the byte reader',
    () async {
      final source = FakeAttachmentSource()
        ..files['%2e%2e/literal.png'] = tinyPng;
      final repository = AttachmentRepository(root: '/vault', source: source);
      addTearDown(repository.dispose);
      for (final target in [
        '../outside.png',
        '%2e%2e/outside.png',
        'a/%2e%2e/%2e%2e/outside.png',
      ]) {
        await expectLater(
          load(repository, target: target, kind: AttachmentLinkKind.markdown),
          throwsA(failure(AttachmentFailureKind.invalid)),
        );
      }
      expect(source.reads.where((p) => p.endsWith('.png')), isEmpty);
      final literal = await load(
        repository,
        target: '%252e%252e/literal.png',
        kind: AttachmentLinkKind.markdown,
      );
      expect(source.reads.last, '%2e%2e/literal.png');
      literal.dispose();
    },
  );

  test(
    'no root or outside document never enumerates or reads the filesystem',
    () async {
      for (final (root, document) in [
        (null, '/vault/note.md'),
        ('/vault', '/other/note.md'),
        ('/vault', '/vault/../other/note.md'),
        ('/vault', null),
      ]) {
        final source = FakeAttachmentSource();
        final repository = AttachmentRepository(root: root, source: source);
        await expectLater(
          load(repository, documentPath: document),
          throwsA(failure(AttachmentFailureKind.needsFolder)),
        );
        expect(source.listCalls, 0);
        expect(source.reads, isEmpty);
        repository.dispose();
      }
    },
  );

  test('remote and unsupported images never cause file reads', () async {
    final source = FakeAttachmentSource();
    final repository = AttachmentRepository(root: '/vault', source: source);
    addTearDown(repository.dispose);
    for (final target in [
      'https://example.com/image.png',
      'file:///tmp/image.png',
      'image.svg',
      'image.avif',
    ]) {
      await expectLater(
        load(repository, target: target),
        throwsA(failure(AttachmentFailureKind.unsupported)),
      );
    }
    expect(source.listCalls, 0);
    expect(source.reads, isEmpty);
  });

  test(
    'read/decode is shared, settings do not restrict old image directories',
    () async {
      final source = FakeAttachmentSource();
      final repository = AttachmentRepository(root: '/vault', source: source);
      final first = await load(repository);
      final second = await load(repository);
      expect(first.image.width, 1);
      expect(identical(first.image, second.image), isTrue);
      expect(source.reads, ['.obsidian/app.json', 'assets/image.png']);
      expect(repository.settings!.folderPath, 'elsewhere');
      repository.dispose();
      // Active image leases remain valid after their old scope is retired.
      expect(first.image.width, 1);
      first.dispose();
      second.dispose();
      second.dispose();
    },
  );

  test(
    'refresh re-indexes and loads replaced bytes, without rewriting settings',
    () async {
      final source = FakeAttachmentSource();
      final repository = AttachmentRepository(root: '/vault', source: source);
      addTearDown(repository.dispose);
      final first = await load(repository);
      source.revision++;
      repository.refresh();
      final second = await load(repository);
      expect(identical(first.image, second.image), isFalse);
      expect(source.reads.where((p) => p.endsWith('.png')).length, 2);
      first.dispose();
      second.dispose();
    },
  );

  test('malformed settings do not block image loading', () async {
    final source = FakeAttachmentSource()..settings = Uint8List.fromList([255]);
    final repository = AttachmentRepository(root: '/vault', source: source);
    addTearDown(repository.dispose);
    final image = await load(repository);
    expect(repository.settings!.malformed, isTrue);
    image.dispose();
  });

  test(
    'refresh and disposal cancel pending old results before decode',
    () async {
      for (final dispose in [false, true]) {
        final source = FakeAttachmentSource();
        final gate = Completer<void>();
        source.beforeRead = gate.future;
        final repository = AttachmentRepository(root: '/vault', source: source);
        final pending = load(repository);
        final assertion = expectLater(
          pending,
          throwsA(failure(AttachmentFailureKind.cancelled)),
        );
        while (!source.reads.contains('assets/image.png')) {
          await Future<void>.delayed(Duration.zero);
        }
        if (dispose) {
          repository.dispose();
        } else {
          repository.refresh();
        }
        gate.complete();
        await assertion;
        if (!dispose) repository.dispose();
      }
    },
  );

  test(
    'cache budget rejects additional pinned images, releases allow eviction',
    () async {
      final source = FakeAttachmentSource()..files['other.png'] = tinyPng;
      final repository = AttachmentRepository(
        root: '/vault',
        source: source,
        maximumCacheBytes: 4,
      );
      addTearDown(repository.dispose);
      final first = await load(repository);
      await expectLater(
        load(repository, target: 'other.png'),
        throwsA(failure(AttachmentFailureKind.tooLarge)),
      );
      first.dispose();
      final next = await load(repository, target: 'other.png');
      expect(next.image.width, 1);
      next.dispose();
    },
  );

  test(
    'missing, offline, permission and index bounds remain distinct',
    () async {
      for (final (code, kind) in [
        ('attachment_offline', AttachmentFailureKind.offline),
        ('attachment_denied', AttachmentFailureKind.denied),
        ('attachment_missing', AttachmentFailureKind.missing),
        ('attachment_index_limit', AttachmentFailureKind.indexLimit),
      ]) {
        final source = FakeAttachmentSource()
          ..listError = PlatformException(code: code);
        final repository = AttachmentRepository(root: '/vault', source: source);
        await expectLater(load(repository), throwsA(failure(kind)));
        expect(source.reads, isEmpty);
        repository.dispose();
      }
    },
  );

  test(
    'native adapter only requests scoped metadata, strings and bounded bytes',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppleWorkspaceService.channel, (
            call,
          ) async {
            calls.add(call);
            return switch (call.method) {
              'listAttachments' => [
                {
                  'relativePath': 'assets/image.png',
                  'comparisonPath': 'assets/image.png',
                  'size': 1,
                  'modified': 1,
                },
              ],
              'normalizeAttachmentPaths' => ['café.png'],
              'readAttachmentBytes' => Uint8List.fromList([1]),
              _ => throw StateError('Unexpected call'),
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(AppleWorkspaceService.channel, null),
      );
      const source = AppleAttachmentSource();
      expect(
        (await source.list('/vault')).single.relativePath,
        'assets/image.png',
      );
      expect(await source.normalize(['cafe\u0301.png']), ['café.png']);
      expect(await source.read('/vault', 'assets/image.png', 16), [1]);
      expect(calls.last.arguments, {
        'path': '/vault',
        'relativePath': 'assets/image.png',
        'maximumBytes': 16,
      });
    },
  );
}
