import 'package:ianvs_markdown/ianvs_markdown.dart';

/// Host-owned identity, editor state and ordered persistence for one document.
///
/// Unmount widgets using this session before calling [dispose]. A write already
/// in progress may finish after closing; queued writes are cancelled. Storage
/// receives the captured source and stable ID, never a later controller value.
class ExampleDocumentSession {
  ExampleDocumentSession({
    required this.id,
    required String source,
    required this.write,
  }) : controller = IanvsMarkdownController(text: source);

  final String id;
  final IanvsMarkdownController controller;
  final Future<void> Function(String documentId, String source) write;
  Future<void> _writes = Future<void>.value();
  var _closed = false;

  /// Use as onSaveRequested; the component acknowledges the captured source.
  Future<void> persist(String capturedText) {
    final operation = _writes.then<void>((_) async {
      if (_closed) throw const IanvsMarkdownSaveCancelledException();
      await write(id, capturedText);
    });
    // A failed write is still reported to its caller; subsequent retries get a
    // clean queue rather than inheriting the previous operation's exception.
    _writes = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return operation;
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    controller.dispose();
  }
}
