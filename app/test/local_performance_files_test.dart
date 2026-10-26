import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/local_performance.dart';
import 'package:linefold/src/services/apple_workspace_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final fails in [false, true]) {
    test(
      'guarded save timing includes native completion (fails=$fails)',
      () async {
        final files = LocalPerformanceFiles();
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(AppleWorkspaceService.channel, (
          call,
        ) async {
          expect(call.method, 'writeDocumentGuarded');
          final args = call.arguments as Map;
          expect(args['path'], '/tmp/performance-fixture.md');
          expect(utf8.decode(args['contentsBytes'] as Uint8List), 'new 中文');
          expect(
            utf8.decode(args['expectedContentsBytes'] as Uint8List),
            'old 中文',
          );
          await Future<void>.delayed(const Duration(milliseconds: 20));
          if (fails) throw PlatformException(code: 'write_failed');
          return true;
        });
        addTearDown(
          () => messenger.setMockMethodCallHandler(
            AppleWorkspaceService.channel,
            null,
          ),
        );
        final saving = files.writeMarkdownFileGuarded(
          '/tmp/performance-fixture.md',
          'new 中文',
          expectedContents: 'old 中文',
        );
        if (fails) {
          await expectLater(saving, throwsA(isA<PlatformException>()));
        } else {
          await saving;
        }
        expect(files.writeMs, greaterThanOrEqualTo(10));
      },
    );
  }
}
