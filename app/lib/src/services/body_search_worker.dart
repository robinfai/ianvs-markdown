import 'dart:async';
import 'dart:isolate';

import 'package:ianvs_markdown/ianvs_markdown.dart';

class BodySearchResult {
  const BodySearchResult({required this.available, required this.matches});
  final bool available;
  final List<IanvsMarkdownReadingMatch> matches;
}

/// One background parser per open search. At most one request runs and one
/// latest request waits; intermediate keystrokes do not build an unbounded queue.
class BodySearchWorker {
  final _responses = ReceivePort();
  Isolate? _isolate;
  SendPort? _commands;
  bool _started = false;
  bool _disposed = false;
  _SearchJob? _running;
  _SearchJob? _pending;

  Future<BodySearchResult?> search({
    required String source,
    required String query,
    required bool matchCase,
  }) {
    if (_disposed) return Future.value(null);
    final job = _SearchJob(source, query, matchCase);
    _pending?.completion.complete(null);
    _pending = job;
    if (!_started) {
      _started = true;
      _responses.listen(_received);
      unawaited(_start());
    }
    _dispatch();
    return job.completion.future;
  }

  Future<void> _start() async {
    try {
      final isolate = await Isolate.spawn(
        _runSearch,
        _responses.sendPort,
        onError: _responses.sendPort,
        errorsAreFatal: true,
        onExit: _responses.sendPort,
      );
      if (_disposed) {
        isolate.kill(priority: Isolate.immediate);
      } else {
        _isolate = isolate;
      }
    } catch (error, stack) {
      _fail(error, stack);
    }
  }

  void _received(dynamic message) {
    if (_disposed) return;
    if (message is SendPort) {
      _commands = message;
      _dispatch();
    } else if (message is BodySearchResult) {
      _running?.completion.complete(message);
      _running = null;
      _dispatch();
    } else {
      _fail(
        StateError('Body search worker stopped: $message'),
        StackTrace.current,
      );
    }
  }

  void _dispatch() {
    if (_disposed ||
        _commands == null ||
        _running != null ||
        _pending == null) {
      return;
    }
    final job = _pending!;
    _pending = null;
    _running = job;
    _commands!.send((job.source, job.query, job.matchCase));
  }

  void _fail(Object error, StackTrace stack) {
    _running?.completion.completeError(error, stack);
    _pending?.completion.completeError(error, stack);
    _running = null;
    _pending = null;
    dispose();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _responses.close();
    _running?.completion.complete(null);
    _pending?.completion.complete(null);
    _running = null;
    _pending = null;
  }
}

class _SearchJob {
  _SearchJob(this.source, this.query, this.matchCase);
  final String source;
  final String query;
  final bool matchCase;
  final completion = Completer<BodySearchResult?>();
}

void _runSearch(SendPort results) {
  final commands = ReceivePort();
  results.send(commands.sendPort);
  String? source;
  IanvsMarkdownReadingSearch? index;
  commands.listen((dynamic message) {
    final (String nextSource, String query, bool matchCase) =
        message as (String, String, bool);
    if (source != nextSource) {
      index = IanvsMarkdownReadingSearch.parse(nextSource);
      source = nextSource;
    }
    results.send(
      BodySearchResult(
        available: index != null,
        matches: index?.find(query, matchCase: matchCase) ?? const [],
      ),
    );
  });
}
