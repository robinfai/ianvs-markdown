import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/services/workspace_index.dart';
import 'package:linefold/src/services/workspace_index_source.dart';
import 'package:linefold/src/services/workspace_reference_index.dart';
import 'workspace_index_test.dart' show FakeIndexSource;

class _IdentitySource extends FakeIndexSource
    implements WorkspacePathIdentitySource {
  Completer<void>? identityGate;
  final entered = Completer<void>();
  @override
  Future<WorkspacePathIdentity> resolveWorkspacePath(
    String root,
    String path,
  ) async {
    if (!entered.isCompleted) entered.complete();
    final gate = identityGate;
    identityGate = null;
    if (gate != null) await gate.future;
    return WorkspacePathIdentity(
      relativePath: path == 'ORIGIN.MD' ? 'Origin.md' : path,
      identity: 'origin-inode',
    );
  }
}

void main() {
  test('dirty revision during identity resolution wins atomically', () async {
    final source = _IdentitySource()
      ..note('Origin.md', '[[Old]] #disk')
      ..note('Old.md', 'old')
      ..note('New.md', 'new');
    final index = WorkspaceIndex(source: source)..configure('/vault');
    final refs = WorkspaceReferenceIndex(index);
    addTearDown(refs.dispose);
    addTearDown(index.dispose);
    void edit(String text) => index.updateBuffer(
      sessionId: 'dirty',
      path: '/vault/ORIGIN.MD',
      name: 'ORIGIN.MD',
      text: text,
      externalConflict: true,
    );
    edit('[[Old]] #oldbuffer');
    final gate = Completer<void>();
    source.identityGate = gate;
    final pending = refs.refresh();
    await source.entered.future;
    edit('😀 [[New]] #newbuffer');
    gate.complete();
    final snapshot = await pending;
    expect(snapshot.backlinks('Old.md'), isEmpty);
    expect(snapshot.backlinks('New.md'), hasLength(1));
    expect(snapshot.notes.containsKey('/vault/ORIGIN.MD'), isFalse);
    expect(
      snapshot.notes['/vault/Origin.md']!.source.text,
      '😀 [[New]] #newbuffer',
    );
    expect(snapshot.notes['/vault/Origin.md']!.source.externalConflict, isTrue);
    expect(snapshot.tags.containsKey('disk'), isFalse);
    expect(snapshot.tags.containsKey('oldbuffer'), isFalse);
    expect(snapshot.tags['newbuffer'], hasLength(1));
    expect(refs.previewImpact('New.md').complete, isTrue);
  });
  test(
    'conflicting physical-identity buffers cannot yield a safe impact',
    () async {
      final source = _IdentitySource()
        ..note('Origin.md', 'disk')
        ..note('Target.md', 'target');
      final index = WorkspaceIndex(source: source)..configure('/vault');
      final refs = WorkspaceReferenceIndex(index);
      addTearDown(refs.dispose);
      addTearDown(index.dispose);
      index.updateBuffer(
        sessionId: 'one',
        path: '/vault/Origin.md',
        name: 'Origin.md',
        text: '[[Target]]',
      );
      index.updateBuffer(
        sessionId: 'two',
        path: '/vault/ORIGIN.MD',
        name: 'ORIGIN.MD',
        text: 'conflicting dirty text',
        externalConflict: true,
      );
      final snapshot = await refs.refresh();
      expect(snapshot.complete, isFalse);
      expect(snapshot.issues.containsKey('identities'), isTrue);
      expect(refs.previewImpact('Target.md').complete, isFalse);
    },
  );
}
