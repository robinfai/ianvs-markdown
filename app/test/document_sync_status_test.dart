import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/controllers/document_sync_controller.dart';
import 'package:linefold/src/models/document_sync_status.dart';
import 'package:linefold/src/services/apple_workspace_service.dart';
import 'package:linefold/src/widgets/document_sync_indicator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 22);
  Map<Object?, Object?> sample(Map<Object?, Object?> fields) => {
    'observedAt': now.millisecondsSinceEpoch,
    'isUbiquitous': true,
    ...fields,
  };

  testWidgets('unsupported provider visibly remains unknown without reading', (
    tester,
  ) async {
    var reads = 0;
    final controller = DocumentSyncController(
      canRead: false,
      read: (_) async {
        ++reads;
        return const DocumentSyncMetadata(state: CloudSyncState.uploaded);
      },
    );
    controller.configure(
      path: '/synthetic/unsupported.md',
      identity: 'provider',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DocumentSyncIndicator(controller: controller)),
      ),
    );
    expect(find.text('Cloud status unknown'), findsOneWidget);
    controller.scheduleRefresh();
    await controller.refresh();
    await tester.pump(const Duration(minutes: 1));
    expect(reads, 0);
    expect(controller.checking, isFalse);
    controller.dispose();
  });

  test('nullable provider observations never infer uploaded or offline', () {
    for (final (fields, expected) in <(Map<Object?, Object?>, CloudSyncState)>[
      ({}, CloudSyncState.unknown),
      ({'isUbiquitous': false, 'isUploaded': true}, CloudSyncState.unknown),
      ({'isUploaded': false}, CloudSyncState.uploadPending),
      ({'isUploaded': true}, CloudSyncState.uploaded),
      ({'isUploaded': true, 'isUploading': true}, CloudSyncState.uploading),
      ({'isUploaded': true, 'isDownloading': true}, CloudSyncState.downloading),
      (
        {'isUploaded': true, 'downloadingStatus': 'downloaded'},
        CloudSyncState.downloadPending,
      ),
      ({'downloadingStatus': 'notDownloaded'}, CloudSyncState.downloadPending),
      (
        {'isUploaded': true, 'uploadError': 'Offline (system reported)'},
        CloudSyncState.failure,
      ),
      (
        {'isUploaded': true, 'downloadError': 'Access denied'},
        CloudSyncState.failure,
      ),
      (
        {'isUploaded': true, 'hasUnresolvedConflicts': true},
        CloudSyncState.conflict,
      ),
      ({'observedAt': null, 'isUploaded': true}, CloudSyncState.unknown),
    ]) {
      expect(DocumentSyncMetadata.fromMap(sample(fields)).state, expected);
    }
    expect(
      DocumentSyncMetadata.fromMap(sample({'isUploaded': true})).label,
      'iCloud reports uploaded',
    );
    expect(
      DocumentSyncMetadata.fromMap(sample({})).explanation,
      contains('does not confirm cloud upload'),
    );
    final conflict = DocumentSyncMetadata.fromMap(
      sample({
        'conflictsAvailable': true,
        'conflicts': [
          {'name': 'Version B', 'modified': now.millisecondsSinceEpoch},
          null,
          {'modified': 'invalid'},
        ],
      }),
    );
    expect(conflict.state, CloudSyncState.conflict);
    expect(conflict.conflicts.single.name, 'Version B');
    expect(conflict.conflicts.single.modified, now);
  });

  test('local states explicitly distinguish recovery and original file', () {
    expect(
      const DocumentPersistenceStatus(
        local: LocalDocumentState.saved,
        recovery: RecoveryCopyState.saved,
      ).label,
      'Saved locally',
    );
    expect(
      const DocumentPersistenceStatus(
        local: LocalDocumentState.draft,
        recovery: RecoveryCopyState.pending,
      ).label,
      'Draft · recovery pending',
    );
    expect(
      const DocumentPersistenceStatus(
        local: LocalDocumentState.edited,
        recovery: RecoveryCopyState.saved,
      ).label,
      'Edited · recovery saved',
    );
    expect(
      const DocumentPersistenceStatus(
        local: LocalDocumentState.restoring,
        recovery: RecoveryCopyState.pending,
      ).label,
      startsWith('Restoring draft'),
    );
    expect(
      const DocumentPersistenceStatus(
        local: LocalDocumentState.failed,
        recovery: RecoveryCopyState.failed,
      ).label,
      'Local save failed · recovery failed',
    );
    expect(
      const DocumentPersistenceStatus(
        local: LocalDocumentState.saved,
        recovery: RecoveryCopyState.saved,
        conflict: true,
      ).label,
      contains('disk conflict'),
    );
  });

  test(
    'native metadata read is a single backward compatible optional method',
    () async {
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(AppleWorkspaceService.channel, (
        call,
      ) async {
        calls.add(call);
        return sample({'isUploaded': false});
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          AppleWorkspaceService.channel,
          null,
        ),
      );
      final result = await const AppleWorkspaceService().readSyncMetadata(
        '/active.md',
      );
      expect(result.state, CloudSyncState.uploadPending);
      expect(calls.map((call) => call.method), ['readDocumentSyncMetadata']);
      expect(calls.single.arguments, {'path': '/active.md'});
      messenger.setMockMethodCallHandler(
        AppleWorkspaceService.channel,
        (_) async => throw MissingPluginException(),
      );
      expect(
        (await const AppleWorkspaceService().readSyncMetadata(
          '/active.md',
        )).state,
        CloudSyncState.unknown,
      );
    },
  );

  testWidgets('native metadata busy is unknown, finite and retryable', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var busy = true;
    messenger.setMockMethodCallHandler(AppleWorkspaceService.channel, (
      _,
    ) async {
      if (busy) throw PlatformException(code: 'workspace_busy');
      return sample({'isUploaded': true});
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        AppleWorkspaceService.channel,
        null,
      ),
    );
    final sync = DocumentSyncController(
      now: () => now,
      read: const AppleWorkspaceService().readSyncMetadata,
    );
    sync.configure(path: '/active.md', identity: 'a');
    await sync.refresh();
    expect(sync.metadata.state, CloudSyncState.unknown);
    expect(sync.checking, isFalse);
    busy = false;
    await sync.refresh();
    expect(sync.metadata.state, CloudSyncState.uploaded);
    expect(sync.checking, isFalse);
    sync.dispose();
  });

  test(
    'native read admission captures only strings and scalar options on main',
    () {
      final swift = File('apple/CloudWorkspace.swift').readAsStringSync();
      final routeStart = swift.indexOf(
        'if let readKind = WorkspaceReadScheduler.Kind(method: method)',
      );
      final admission = swift.indexOf(
        'self.readScheduler.execute(kind: readKind, operation:',
        routeStart,
      );
      expect(routeStart, greaterThanOrEqualTo(0));
      expect(admission, greaterThan(routeStart));
      final mainSnapshot = swift.substring(routeStart, admission);
      expect(mainSnapshot, contains('arguments["path"] as? String'));
      expect(mainSnapshot, contains('arguments["recursive"] as? Bool'));
      expect(mainSnapshot, contains('arguments["maximumBytes"] as? Int'));
      for (final forbidden in [
        'URL(fileURLWithPath:',
        'resourceValues(',
        'FileManager.',
        'FileHandle(',
        'NSFileCoordinator(',
        'Data(contentsOf:',
        'startAccessingSecurityScopedResource(',
      ]) {
        expect(mainSnapshot, isNot(contains(forbidden)), reason: forbidden);
      }
      final operation = swift.substring(
        admission,
        swift.indexOf('}, completion:', admission),
      );
      expect(operation, contains('let url = URL(fileURLWithPath: path)'));
    },
  );

  test('native status implementation cannot initiate downloads or writes', () {
    final swift = File('apple/CloudWorkspace.swift').readAsStringSync();
    final method = swift.substring(
      swift.indexOf('static func readSyncMetadata('),
      swift.indexOf('static func list(_ root:'),
    );
    for (final forbidden in [
      'startDownloadingUbiquitousItem(',
      'coordinate(',
      'Data(contentsOf:',
      'contentsOfDirectory(',
      'getNonlocalVersions',
      'isResolved =',
      'removeOtherVersions',
      'setUbiquitous(',
      'startAccessingSecurityScopedResource(',
    ]) {
      expect(method, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(method, contains('removeAllCachedResourceValues()'));
    expect(method, contains('unresolvedConflictVersionsOfItem(at: url)'));
  });

  testWidgets(
    'scope ABA and older reads cannot overwrite the active observation',
    (tester) async {
      final pending = <Completer<DocumentSyncMetadata>>[];
      final paths = <String>[];
      final sync = DocumentSyncController(
        now: () => now,
        read: (path) {
          paths.add(path);
          final value = Completer<DocumentSyncMetadata>();
          pending.add(value);
          return value.future;
        },
      );
      sync.configure(path: '/a.md', identity: ('rootA', 'doc'));
      await tester.pump();
      sync.configure(path: '/a.md', identity: ('rootB', 'doc'));
      await tester.pump();
      sync.configure(path: '/a.md', identity: ('rootA', 'doc'));
      await tester.pump();
      pending[2].complete(
        DocumentSyncMetadata(
          state: CloudSyncState.uploadPending,
          observedAt: now,
        ),
      );
      await tester.pump();
      pending[0].complete(
        DocumentSyncMetadata(state: CloudSyncState.uploaded, observedAt: now),
      );
      pending[1].complete(
        DocumentSyncMetadata(state: CloudSyncState.conflict, observedAt: now),
      );
      await tester.pump();
      expect(paths, ['/a.md', '/a.md', '/a.md']);
      expect(sync.metadata.state, CloudSyncState.uploadPending);
      expect(sync.checking, isFalse);
      sync.dispose();
    },
  );

  testWidgets(
    'throttled bursts query only active path and expiry never polls',
    (tester) async {
      final paths = <String>[];
      final sync = DocumentSyncController(
        now: () => now,
        read: (path) async {
          paths.add(path);
          return DocumentSyncMetadata(
            state: CloudSyncState.uploading,
            observedAt: now,
          );
        },
      );
      sync.configure(path: '/active.md', identity: 'a');
      await tester.pump();
      for (var i = 0; i < 50; i++) {
        sync.scheduleRefresh();
      }
      await tester.pump(const Duration(milliseconds: 499));
      expect(paths, ['/active.md']);
      await tester.pump(const Duration(milliseconds: 1));
      expect(paths, ['/active.md', '/active.md']);
      await tester.pump(const Duration(seconds: 31));
      expect(sync.metadata.state, CloudSyncState.unknown);
      expect(paths, hasLength(2));
      sync.dispose();
    },
  );

  testWidgets(
    'timeout releases checking and ignores late data; retry succeeds',
    (tester) async {
      final delayed = Completer<DocumentSyncMetadata>();
      var calls = 0;
      final sync = DocumentSyncController(
        now: () => now,
        read: (_) => ++calls == 1
            ? delayed.future
            : Future.value(
                DocumentSyncMetadata(
                  state: CloudSyncState.downloadPending,
                  observedAt: now,
                ),
              ),
      );
      sync.configure(path: '/active.md', identity: 'a');
      await tester.pump();
      expect(sync.checking, isTrue);
      await tester.pump(const Duration(seconds: 5));
      expect(sync.checking, isFalse);
      expect(sync.metadata.state, CloudSyncState.unknown);
      await sync.refresh();
      delayed.complete(
        DocumentSyncMetadata(state: CloudSyncState.uploaded, observedAt: now),
      );
      await tester.pump();
      expect(sync.metadata.state, CloudSyncState.downloadPending);
      sync.dispose();
    },
  );

  testWidgets(
    'old and future observations are unknown; synchronous failures recover',
    (tester) async {
      var observation = DocumentSyncMetadata(
        state: CloudSyncState.uploaded,
        observedAt: now.subtract(const Duration(seconds: 31)),
      );
      var fail = false;
      final sync = DocumentSyncController(
        now: () => now,
        read: (_) {
          if (fail) throw StateError('provider offline');
          return Future.value(observation);
        },
      );
      sync.configure(path: '/active.md', identity: 'a');
      await tester.pump();
      expect(sync.metadata.state, CloudSyncState.unknown);
      observation = DocumentSyncMetadata(
        state: CloudSyncState.uploaded,
        observedAt: now.add(const Duration(seconds: 1)),
      );
      await sync.refresh();
      expect(sync.metadata.state, CloudSyncState.unknown);
      fail = true;
      await sync.refresh();
      expect(sync.metadata.state, CloudSyncState.unknown);
      expect(sync.checking, isFalse);
      sync.dispose();
    },
  );

  testWidgets(
    'invalidate and dispose release waits without accepting late metadata',
    (tester) async {
      final delayed = Completer<DocumentSyncMetadata>();
      final sync = DocumentSyncController(
        now: () => now,
        read: (_) => delayed.future,
      );
      sync.configure(path: '/a.md', identity: 'a');
      await tester.pump();
      final waiting = sync.refresh();
      sync.invalidate();
      await waiting;
      expect(sync.checking, isFalse);
      expect(sync.metadata.state, CloudSyncState.unknown);
      final second = sync.refresh();
      sync.dispose();
      await second;
      delayed.complete(
        DocumentSyncMetadata(state: CloudSyncState.uploaded, observedAt: now),
      );
      await tester.pump();
      expect(sync.metadata.state, CloudSyncState.unknown);
    },
  );

  testWidgets(
    'status and conflict details fit 320px at 3x with retry semantics',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      final sync = DocumentSyncController(
        now: () => now,
        read: (_) async => DocumentSyncMetadata(
          state: CloudSyncState.conflict,
          observedAt: now,
          conflictsAvailable: true,
          conflicts: [
            DocumentConflictVersion(name: 'Preserved version B', modified: now),
          ],
        ),
      );
      sync.configure(path: '/active.md', identity: 'a');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DocumentSyncIndicator(controller: sync)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('iCloud conflict'), findsOneWidget);
      await tester.tap(find.text('iCloud conflict'));
      await tester.pumpAndSettle();
      expect(find.text('Check again'), findsOneWidget);
      expect(find.textContaining('Preserved version B'), findsOneWidget);
      expect(
        find.textContaining('No version has been replaced'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Check again'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      sync.dispose();
    },
  );
}
