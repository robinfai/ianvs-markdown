import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/preview/preview_platform.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'cold and running deliveries are serialized; native errors do not discard files',
    () async {
      final pending = <String>['/cold.md'];
      var nativeErrors = <String>[];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        PreviewPlatform.channel,
        (call) async {
          expect(call.method, 'takePendingFiles');
          final result = {'paths': pending.toList(), 'errors': nativeErrors};
          pending.clear();
          nativeErrors = [];
          return result;
        },
      );
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          PreviewPlatform.channel,
          null,
        ),
      );
      final platform = PreviewPlatform();
      addTearDown(platform.dispose);
      final received = <List<String>>[];
      final errors = <String>[];
      final started = Completer<void>();
      final release = Completer<void>();
      final start = platform.start((paths) async {
        received.add(paths);
        if (received.length == 1) {
          started.complete();
          await release.future;
        }
      }, errors.add);
      await started.future;
      pending.add('/running.md');
      nativeErrors = ['Unsupported file'];
      final reply = Completer<void>();
      ServicesBinding.instance.channelBuffers.push(
        PreviewPlatform.channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('filesAvailable'),
        ),
        (_) => reply.complete(),
      );
      release.complete();
      await Future.wait([start, reply.future]);
      await platform.refresh();
      expect(received, [
        ['/cold.md'],
        ['/running.md'],
      ]);
      expect(errors, ['Unsupported file']);
    },
  );

  test(
    'channel failure is surfaced and later notifications can recover',
    () async {
      var fail = true;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        PreviewPlatform.channel,
        (_) async {
          if (fail) throw PlatformException(code: 'unavailable');
          return {
            'paths': ['/recovered.md'],
            'errors': <String>[],
          };
        },
      );
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          PreviewPlatform.channel,
          null,
        ),
      );
      final platform = PreviewPlatform();
      addTearDown(platform.dispose);
      final received = <String>[];
      final errors = <String>[];
      await platform.start((paths) async => received.addAll(paths), errors.add);
      expect(errors, hasLength(1));
      fail = false;
      await platform.refresh();
      expect(received, ['/recovered.md']);
    },
  );
}
