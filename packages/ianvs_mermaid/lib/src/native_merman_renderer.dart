import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:merman/merman.dart' as merman;

import 'mermaid_cache.dart';
import 'mermaid_exception.dart';
import 'mermaid_render_options.dart';
import 'mermaid_render_result.dart';
import 'mermaid_renderer.dart';
import 'mermaid_svg_normalizer.dart';
import 'native_svg_bridge.dart';

abstract interface class MermanEngine {
  String get packageVersion;

  String renderSvg(String source, {String? optionsJson});

  String layoutJsonRaw(String source, {String? optionsJson});

  merman.MermanValidationResult validate(String source, {String? optionsJson});
}

class BundledMermanEngine implements MermanEngine {
  BundledMermanEngine(this._engine);

  factory BundledMermanEngine.open() {
    return BundledMermanEngine(merman.Merman.open());
  }

  factory BundledMermanEngine.openPath(String path) {
    return BundledMermanEngine(merman.Merman.openPath(path));
  }

  final merman.Merman _engine;

  @override
  String get packageVersion => _engine.packageVersion;

  @override
  String renderSvg(String source, {String? optionsJson}) {
    return _engine.renderSvg(source, optionsJson: optionsJson);
  }

  @override
  String layoutJsonRaw(String source, {String? optionsJson}) {
    return _engine.layoutJsonRaw(source, optionsJson: optionsJson);
  }

  @override
  merman.MermanValidationResult validate(String source, {String? optionsJson}) {
    return _engine.validate(source, optionsJson: optionsJson);
  }
}

typedef MermanEngineOpener = MermanEngine Function();

/// Owns one background isolate. Native rendering, font discovery, SVG expansion
/// and the bounded LRU all live there; no native calls run on the UI isolate.
class NativeMermanRenderer implements MermaidRenderer {
  NativeMermanRenderer({
    MermaidSvgCache? cache,
    MermanEngineOpener? openEngine,
    String? libraryPath,
    this.maxPendingRequests = 32,
  }) : assert(maxPendingRequests > 0),
       _config = _WorkerConfig(
         openEngine,
         libraryPath,
         cache?.maxEntries ?? 64,
         cache?.maxBytes ?? 16 * 1024 * 1024,
       );

  final int maxPendingRequests;
  final _WorkerConfig _config;
  final _pending = <int, Completer<Object>>{};
  final _inFlight = <String, Future<MermaidRenderResult>>{};
  Future<SendPort>? _starting;
  ReceivePort? _responses;
  SendPort? _commands;
  var _nextId = 0;
  var _disposed = false;

  Future<SendPort> _start() => _starting ??= _spawn();

  Future<SendPort> _spawn() async {
    final ready = Completer<SendPort>();
    final responses = ReceivePort();
    _responses = responses;
    responses.listen((message) {
      if (message is SendPort) {
        _commands = message;
        ready.complete(message);
        if (_disposed) {
          message.send(null);
          responses.close();
        }
      } else if (message is _WorkerReply) {
        final request = _pending.remove(message.id);
        if (request == null) return;
        if (message.error != null) {
          request.completeError(
            MermaidRenderFailure(message: message.error!),
            StackTrace.fromString(message.stack ?? ''),
          );
        } else {
          request.complete(message.value!);
        }
      } else {
        final error = MermaidRenderFailure(
          message: 'Mermaid worker stopped: $message',
        );
        if (!ready.isCompleted) ready.completeError(error);
        _failPending(error);
        responses.close();
        _starting = null;
        _commands = null;
      }
    });
    try {
      await Isolate.spawn(
        _runMermaidWorker,
        (_config, responses.sendPort),
        onError: responses.sendPort,
        onExit: responses.sendPort,
        debugName: 'Mermaid vector rendering',
      );
    } catch (error, stack) {
      responses.close();
      _starting = null;
      if (!ready.isCompleted) ready.completeError(error, stack);
    }
    return ready.future;
  }

  Future<T> _request<T extends Object>(
    String method,
    String source,
    String optionsJson, {
    bool includeLayout = false,
  }) async {
    if (_disposed) throw const MermaidRendererDisposedException();
    final commands = await _start();
    if (_disposed) throw const MermaidRendererDisposedException();
    if (_pending.length >= maxPendingRequests) {
      throw const MermaidRenderFailure(
        message:
            'Too many pending diagram requests; retry after editing stops.',
      );
    }
    final id = _nextId++;
    final completer = Completer<Object>();
    _pending[id] = completer;
    commands.send(
      _WorkerRequest(id, method, source, optionsJson, includeLayout),
    );
    return (await completer.future) as T;
  }

  @override
  Future<MermaidRenderResult> render(
    String source, {
    MermaidRenderOptions options = MermaidRenderOptions.flutterSvgDefault,
    bool includeLayout = false,
  }) {
    if (_disposed) {
      return Future.error(const MermaidRendererDisposedException());
    }
    if (options.pipeline != MermaidSvgPipeline.resvgSafe) {
      return Future.error(
        const MermaidRenderFailure(
          message:
              'Flutter vector rendering requires the resvg-safe Mermaid pipeline.',
        ),
      );
    }
    final optionsJson = options.toOptionsJson();
    final key = jsonEncode([source, optionsJson, includeLayout]);
    if (!_inFlight.containsKey(key) && _inFlight.length >= maxPendingRequests) {
      return Future.error(
        const MermaidRenderFailure(
          message:
              'Too many pending diagram requests; retry after editing stops.',
        ),
      );
    }
    return _inFlight.putIfAbsent(
      key,
      () =>
          _request<MermaidRenderResult>(
            'render',
            source,
            optionsJson,
            includeLayout: includeLayout,
          ).whenComplete(() {
            _inFlight.remove(key);
          }),
    );
  }

  @override
  Future<MermaidValidationResult> validate(
    String source, {
    MermaidRenderOptions options = MermaidRenderOptions.flutterSvgDefault,
  }) => _request('validate', source, options.toOptionsJson());

  @override
  Future<String> layoutJson(
    String source, {
    MermaidRenderOptions options = MermaidRenderOptions.flutterSvgDefault,
  }) => _request('layout', source, options.toOptionsJson());

  void _failPending(Object error) {
    for (final request in _pending.values) {
      request.completeError(error);
    }
    _pending.clear();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _failPending(const MermaidRendererDisposedException());
    _inFlight.clear();
    // Let an in-progress FFI call return and release its buffers before exit.
    // If startup is pending, the ready handler sends this shutdown instead.
    _commands?.send(null);
    if (_commands != null) _responses?.close();
  }
}

class _WorkerConfig {
  const _WorkerConfig(
    this.openEngine,
    this.libraryPath,
    this.cacheEntries,
    this.cacheBytes,
  );
  final MermanEngineOpener? openEngine;
  final String? libraryPath;
  final int cacheEntries;
  final int cacheBytes;
}

class _WorkerRequest {
  const _WorkerRequest(
    this.id,
    this.method,
    this.source,
    this.options,
    this.includeLayout,
  );
  final int id;
  final String method;
  final String source;
  final String options;
  final bool includeLayout;
}

class _WorkerReply {
  const _WorkerReply(this.id, {this.value, this.error, this.stack});
  final int id;
  final Object? value;
  final String? error;
  final String? stack;
}

void _runMermaidWorker((_WorkerConfig, SendPort) args) {
  final (config, responses) = args;
  final commands = ReceivePort();
  final cache = MermaidSvgCache.memory(
    maxEntries: config.cacheEntries,
    maxBytes: config.cacheBytes,
  );
  MermanEngine? engine;
  final svgBridge = NativeSvgBridge();
  responses.send(commands.sendPort);
  commands.listen((message) {
    if (message == null) {
      cache.clear();
      commands.close();
      Isolate.exit();
    }
    final request = message as _WorkerRequest;
    try {
      final current = engine ??=
          config.openEngine?.call() ??
          (config.libraryPath == null
              ? BundledMermanEngine.open()
              : BundledMermanEngine.openPath(config.libraryPath!));
      Object result;
      switch (request.method) {
        case 'render':
          final identity = svgBridge.cacheIdentity;
          final key = MermaidSvgCache.keyFor(
            source: request.source,
            optionsJson: request.options,
            engineVersion: current.packageVersion,
            preprocessingIdentity: identity,
          );
          final cached = cache.get(key);
          // Cache the expanded SVG with its dimensions as one bounded payload.
          final expanded = cached == null
              ? svgBridge.preprocess(
                  normalizeMermaidSvgForFlutter(
                    current.renderSvg(
                      request.source,
                      optionsJson: request.options,
                    ),
                  ),
                )
              : jsonDecode(cached) as Map<String, dynamic>;
          if (cached == null) cache.set(key, jsonEncode(expanded));
          result = MermaidRenderResult(
            source: request.source,
            svg: expanded['svg'] as String,
            optionsJson: request.options,
            engineVersion: current.packageVersion,
            preprocessingIdentity: identity,
            width: (expanded['width'] as num).toDouble(),
            height: (expanded['height'] as num).toDouble(),
            fromCache: cached != null,
            layoutJson: request.includeLayout
                ? current.layoutJsonRaw(
                    request.source,
                    optionsJson: request.options,
                  )
                : null,
          );
        case 'validate':
          try {
            final validation = current.validate(
              request.source,
              optionsJson: request.options,
            );
            result = MermaidValidationResult(
              valid: validation.valid,
              raw: validation,
              errorMessage: validation.error,
              code: validation.code,
              codeName: validation.codeName,
            );
          } on merman.MermanException catch (error) {
            result = MermaidValidationResult(
              valid: false,
              raw: error,
              errorMessage: error.message,
              code: error.code,
              codeName: error.codeName,
            );
          }
        case 'layout':
          result = current.layoutJsonRaw(
            request.source,
            optionsJson: request.options,
          );
        default:
          throw StateError('Unknown Mermaid worker request: ${request.method}');
      }
      responses.send(_WorkerReply(request.id, value: result));
    } catch (error, stack) {
      responses.send(
        _WorkerReply(
          request.id,
          error: error is MermaidRenderFailure
              ? error.message
              : error.toString(),
          stack: stack.toString(),
        ),
      );
    }
  });
}
