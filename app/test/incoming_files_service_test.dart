import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/services/incoming_files_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MacOSIncomingFilesService.channel;
  const codec = StandardMethodCodec();

  Future<void> notifyFilesAvailable() async {
    final reply = Completer<void>();
    ServicesBinding.instance.channelBuffers.push(
      channel.name,
      codec.encodeMethodCall(const MethodCall('filesAvailable')),
      (_) => reply.complete(),
    );
    await reply.future;
  }

  test(
    'native startup and live queues drain serially without reopening batches',
    () async {
      final pending = <String>['/notes/startup.md'];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        expect(call.method, 'takePendingFiles');
        final files = pending.toList();
        pending.clear();
        return files;
      });
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final service = MacOSIncomingFilesService();
      addTearDown(service.dispose);
      final batches = <List<String>>[];
      final openingFirst = Completer<void>();
      final started = Completer<void>();
      final startup = service.start((paths) async {
        batches.add(paths);
        if (batches.length == 1) {
          started.complete();
          await openingFirst.future;
        }
      });
      await started.future;
      pending.add('/notes/live.md');
      final live = notifyFilesAvailable();
      expect(batches, [
        ['/notes/startup.md'],
      ]);
      openingFirst.complete();
      await Future.wait([startup, live]);
      await notifyFilesAvailable();
      expect(batches, [
        ['/notes/startup.md'],
        ['/notes/live.md'],
      ]);
    },
    skip: !Platform.isMacOS,
  );

  test(
    'one failed open does not block later native requests',
    () async {
      final pending = <String>['/notes/broken.md'];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        _,
      ) async {
        final files = pending.toList();
        pending.clear();
        return files;
      });
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final service = MacOSIncomingFilesService();
      addTearDown(service.dispose);
      final opened = <String>[];
      await expectLater(
        service.start((paths) async {
          if (paths.single.endsWith('broken.md')) {
            throw StateError('Unreadable file');
          }
          opened.addAll(paths);
        }),
        throwsStateError,
      );
      pending.add('/notes/recovered.md');
      await notifyFilesAvailable();
      expect(opened, ['/notes/recovered.md']);
    },
    skip: !Platform.isMacOS,
  );
}
