import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/services/apple_workspace_service.dart';
import 'package:linefold/src/services/workspace_index_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const source = AppleWorkspaceIndexSource();
  final calls = <MethodCall>[];
  dynamic response;
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppleWorkspaceService.channel, (call) async {
          calls.add(call);
          return response;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppleWorkspaceService.channel, null);
  });
  test(
    'text channel uses scoped local-only method and preserves BOM/CRLF/Unicode',
    () async {
      response = {
        'bytes': Uint8List.fromList(utf8.encode('\ufefffirst\r\n😀')),
        'revision': 'inode:1',
      };
      final result = await source.readWorkspaceText(
        '/vault',
        'folder/a.md',
        workspaceTextMaximumBytes,
      );
      expect(result.text, '\ufefffirst\r\n😀');
      expect(result.revision, 'inode:1');
      expect(calls.single.method, 'readWorkspaceTextBytes');
      expect(calls.single.arguments, {
        'path': '/vault',
        'relativePath': 'folder/a.md',
        'maximumBytes': workspaceTextMaximumBytes,
      });
    },
  );
  test('malformed UTF8 and oversized native output fail closed', () async {
    response = {
      'bytes': Uint8List.fromList([0xff]),
      'revision': '1',
    };
    await expectLater(
      source.readWorkspaceText('/vault', 'a.md', 10),
      throwsFormatException,
    );
    response = {'bytes': Uint8List(11), 'revision': '1'};
    await expectLater(
      source.readWorkspaceText('/vault', 'a.md', 10),
      throwsA(isA<WorkspaceIndexFailure>()),
    );
  });
  test('incomplete catalog and local-only state are retained', () async {
    response = {
      'entries': [
        {
          'relativePath': 'a.md',
          'isDirectory': false,
          'revision': '1',
          'size': 100,
          'modified': 1,
          'local': false,
        },
      ],
      'complete': false,
      'reason': 'deadline',
    };
    final result = await source.listWorkspaceDirectory('/vault', '');
    expect(result.complete, isFalse);
    expect(result.reason, 'deadline');
    expect(result.entries.single.local, isFalse);
    expect(calls.single.method, 'listWorkspaceDirectory');
  });
}
