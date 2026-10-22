import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/document_sync_status.dart';

/// One active document, one read per burst. No polling, content reads, or index
/// requests. Every target change invalidates completions, including A → B → A.
class DocumentSyncController extends ChangeNotifier {
  DocumentSyncController({
    required this.read,
    this.canRead = true,
    DateTime Function()? now,
    this.freshness = const Duration(seconds: 30),
    this.timeout = const Duration(seconds: 5),
    this.debounce = const Duration(milliseconds: 500),
  }) : _now = now ?? DateTime.now;

  final Future<DocumentSyncMetadata> Function(String path) read;
  // An unsupported provider still has a visible unknown status, without I/O.
  final bool canRead;
  final DateTime Function() _now;
  final Duration freshness;
  final Duration timeout;
  final Duration debounce;
  String? path;
  Object? _identity;
  int _epoch = 0;
  bool _disposed = false;
  bool checking = false;
  DocumentSyncMetadata metadata = const DocumentSyncMetadata();
  Future<void>? _pending;
  Timer? _refreshTimer;
  Timer? _expiry;
  Timer? _deadline;
  Completer<DocumentSyncMetadata>? _readCompletion;
  bool _refreshAgain = false;

  void configure({required String? path, required Object? identity}) {
    if (_disposed || (this.path == path && _identity == identity)) return;
    ++_epoch;
    _cancelRead();
    this.path = path;
    _identity = identity;
    _pending = null;
    _refreshAgain = false;
    checking = false;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _expiry?.cancel();
    metadata = const DocumentSyncMetadata();
    // Configuration happens while the workspace is notifying/building. Defer
    // notification and I/O so listeners never trigger a nested widget build.
    final epoch = _epoch;
    scheduleMicrotask(() {
      if (_disposed || epoch != _epoch) return;
      if (path == null || !canRead) {
        notifyListeners();
      } else {
        unawaited(refresh());
      }
    });
  }

  void invalidate() {
    if (_disposed) return;
    ++_epoch;
    _cancelRead();
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _pending = null;
    checking = false;
    _refreshAgain = false;
    _expiry?.cancel();
    metadata = const DocumentSyncMetadata();
    notifyListeners();
  }

  void scheduleRefresh() {
    if (_disposed || path == null || !canRead) return;
    // Leading-edge window with one trailing read avoids starvation when the
    // query emits a continuous stream of unrelated workspace notifications.
    _refreshTimer ??= Timer(debounce, () {
      _refreshTimer = null;
      if (_pending != null) {
        _refreshAgain = true;
      } else {
        unawaited(refresh());
      }
    });
  }

  Future<void> refresh() {
    if (_disposed || path == null || !canRead) return Future.value();
    if (_pending case final pending?) return pending;
    final currentPath = path!;
    final epoch = _epoch;
    checking = true;
    notifyListeners();
    late final Future<void> task;
    task = () async {
      final completion = Completer<DocumentSyncMetadata>();
      _readCompletion = completion;
      const unavailable = DocumentSyncMetadata(
        detail:
            'Cloud status is unavailable. Your local document has not been changed. Try checking again.',
      );
      _deadline = Timer(timeout, () {
        if (!completion.isCompleted) completion.complete(unavailable);
      });
      unawaited(
        Future.sync(() => read(currentPath)).then<void>(
          (value) {
            if (!completion.isCompleted) completion.complete(value);
          },
          onError: (Object _) {
            if (!completion.isCompleted) completion.complete(unavailable);
          },
        ),
      );
      final observation = await completion.future;
      if (_disposed || epoch != _epoch || path != currentPath) return;
      _deadline?.cancel();
      _readCompletion = null;
      final sampled = observation.observedAt;
      final age = sampled == null ? null : _now().difference(sampled);
      _expiry?.cancel();
      // Future times are not trusted either. A wall-clock change cannot turn an
      // old sample into a permanent "uploaded" or "uploading" indicator.
      if (observation.state != CloudSyncState.localOnly &&
          (age == null || age.isNegative || age >= freshness)) {
        metadata = DocumentSyncMetadata(
          detail:
              observation.detail ??
              'No current cloud observation is available. Check again for an updated status.',
        );
      } else {
        metadata = observation;
        if (age != null && observation.state != CloudSyncState.localOnly) {
          _expiry = Timer(freshness - age, () {
            if (_disposed || epoch != _epoch) return;
            metadata = const DocumentSyncMetadata(
              detail:
                  'The previous cloud observation is out of date. Check again for an updated status.',
            );
            notifyListeners();
          });
        }
      }
      checking = false;
      if (identical(_pending, task)) _pending = null;
      notifyListeners();
      if (_refreshAgain) {
        _refreshAgain = false;
        scheduleRefresh();
      }
    }();
    _pending = task;
    return task;
  }

  void _cancelRead() {
    _deadline?.cancel();
    final completion = _readCompletion;
    _readCompletion = null;
    if (completion != null && !completion.isCompleted) {
      completion.complete(const DocumentSyncMetadata());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_epoch;
    _cancelRead();
    _refreshTimer?.cancel();
    _expiry?.cancel();
    super.dispose();
  }
}
