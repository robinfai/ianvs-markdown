import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/services/workspace_move_tree_inspector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('readonly-directory-tree-tests');
  const service = AppleWorkspaceMoveTreeInspector(channel: channel);
  const id = '12345678-1234-4234-8234-123456789abc';
  late List<MethodCall> calls;
  Map<String, Object?> reply() => {
    'root': '/vault',
    'sourcePath': 'Old',
    'requestId': id,
    'sourceState': 'unavailable',
    'complete': false,
    'members': <Object>[],
    'issues': [
      {'code': 'source_unavailable', 'path': 'Old'},
    ],
    'observedEntryCount': 0,
  };

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'inspectWorkspaceDirectoryMoveTree'
              ? reply()
              : false;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'inspection and cancellation only use their read-only control routes',
    () async {
      final result = await service.inspect('/vault', 'Old', id);
      expect(result.complete, isFalse);
      expect(result.issues.single.code, 'source_unavailable');
      await service.cancel(id);
      expect(calls.map((c) => c.method), [
        'inspectWorkspaceDirectoryMoveTree',
        'cancelWorkspaceDirectoryMoveInspection',
      ]);
      expect(calls.first.arguments, {
        'path': '/vault',
        'relativePath': 'Old',
        'requestId': id,
      });
    },
  );

  test('invalid scope and IDs never reach the platform channel', () async {
    for (final path in [
      '',
      '../Old',
      '/Old',
      'Old/../Other',
      'x' * 4097,
      '界' * 2000,
    ]) {
      await expectLater(
        service.inspect('/vault', path, id),
        throwsFormatException,
      );
    }
    await expectLater(
      service.inspect('vault', 'Old', id),
      throwsFormatException,
    );
    await expectLater(
      service.inspect('/${'x' * 4096}', 'Old', id),
      throwsFormatException,
    );
    await expectLater(service.cancel('not-an-id'), throwsFormatException);
    expect(calls, isEmpty);
  });

  for (final field in ['root', 'sourcePath', 'requestId']) {
    test(
      'a mismatched $field response is not accepted as current evidence',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async {
              final value = reply();
              value[field] = switch (field) {
                'root' => '/other',
                'sourcePath' => 'Other',
                _ => '87654321-1234-4234-8234-123456789abc',
              };
              if (field == 'sourcePath') {
                value['issues'] = [
                  {'code': 'source_unavailable', 'path': 'Other'},
                ];
              }
              return value;
            });
        await expectLater(
          service.inspect('/vault', 'Old', id),
          throwsFormatException,
        );
      },
    );
  }

  test(
    'cancellation notification is one-shot, detachable and supports late listeners',
    () {
      final cancellation = WorkspaceMovePreviewCancellation();
      var first = 0;
      var detached = 0;
      var late = 0;
      cancellation.listen(() => first++);
      cancellation.listen(() => detached++)();
      cancellation.cancel();
      cancellation.cancel();
      cancellation.listen(() => late++);
      expect(first, 1);
      expect(detached, 0);
      expect(late, 1);
      expect(cancellation.isCancelled, isTrue);
      expect(
        cancellation.throwIfCancelled,
        throwsA(isA<WorkspaceMovePreviewCancelled>()),
      );
    },
  );
}
