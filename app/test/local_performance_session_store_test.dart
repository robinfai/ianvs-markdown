import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/local_performance.dart';
import 'package:linefold/src/services/workspace_session_store.dart';

const snapshot = WorkspaceSnapshot(
  documents: [],
  activeDocumentId: null,
  workspaceRoot: null,
  workspaceAccessToken: null,
  sidebarVisible: true,
  outlineVisible: true,
);

class PendingStore implements WorkspaceSessionStore {
  final writes = <Completer<void>>[];
  @override
  Future<WorkspaceSnapshot?> load() async => snapshot;
  @override
  Future<void> save(WorkspaceSnapshot value) {
    expect(identical(value, snapshot), isTrue);
    final pending = Completer<void>();
    writes.add(pending);
    return pending.future;
  }
}

void main() {
  test(
    'capture excludes preparation and late writes from an older action',
    () async {
      final delegate = PendingStore();
      final store = LocalPerformanceSessionStore(delegate);
      expect(await store.load(), same(snapshot));
      final preparation = store.save(snapshot);
      store.beginSaveCapture();
      delegate.writes[0].complete();
      await preparation;
      expect(store.saveCount, 0);
      final old = store.save(snapshot);
      store.endSaveCapture();
      store.beginSaveCapture();
      delegate.writes[1].complete();
      await old;
      expect(store.saveCount, 0);
      final current = store.save(snapshot);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      delegate.writes[2].complete();
      await current;
      expect(store.saveCount, 1);
      expect(store.saveMs, greaterThanOrEqualTo(10));
      store.endSaveCapture();
      final after = store.save(snapshot);
      delegate.writes[3].complete();
      await after;
      expect(store.saveCount, 1);
    },
  );

  test(
    'failed recovery writes retain timing and propagate the error',
    () async {
      final delegate = PendingStore();
      final store = LocalPerformanceSessionStore(delegate)..beginSaveCapture();
      final saving = store.save(snapshot);
      final error = StateError('recovery failed');
      final expectation = expectLater(saving, throwsA(same(error)));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      delegate.writes.single.completeError(error);
      await expectation;
      expect(store.saveCount, 1);
      expect(store.saveMs, greaterThanOrEqualTo(10));
      store.endSaveCapture();
    },
  );
}
