import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'dart:io';
import 'native_pele_bridge.dart';
import 'pele_svg_normalizer.dart';

import 'mermaid_cache.dart';
import 'mermaid_exception.dart';
import 'mermaid_render_options.dart';
import 'mermaid_render_result.dart';
import 'mermaid_renderer.dart';
import 'native_svg_bridge.dart';

/// Owns one background isolate. Native rendering, font discovery, SVG expansion
/// and the bounded LRU all live there; no native calls run on the UI isolate.
class NativePeleRenderer implements MermaidRenderer {
  NativePeleRenderer({MermaidSvgCache? cache, this.maxPendingRequests = 32})
    : assert(maxPendingRequests > 0),
      _config = _WorkerConfig(
        cache?.maxEntries ?? 64,
        cache?.maxBytes ?? 16 * 1024 * 1024,
      );

  final int maxPendingRequests;
  final _WorkerConfig _config;
  final _pending = <int, Completer<Object>>{};
  final _inFlight = <String, Future<MermaidRenderResult>>{};
  Future<SendPort>? _starting;
  SendPort? _commands;
  var _nextId = 0;
  var _disposed = false;
  NativePeleBridge? _control;
  static const engineVersion = 'pele/1.13.0;checkpoints/1';

  Future<SendPort> _start() => _starting ??= _spawn();

  Future<SendPort> _spawn() async {
    if (!Platform.isMacOS && !Platform.isIOS) {
      throw UnsupportedError(
        'Pele requires system JavaScriptCore on macOS/iOS',
      );
    }
    final runtime = await rootBundle.loadString(
      'packages/ianvs_mermaid/vendor/pele/pele-runtime.js',
    );
    if (_disposed) throw const MermaidRendererDisposedException();
    final control = NativePeleBridge.allocate();
    _control = control;
    control
        .retain(); // worker ownership, released after it destroys its context
    final ready = Completer<SendPort>();
    final responses = ReceivePort();
    responses.listen((message) {
      if (message is SendPort) {
        _commands = message;
        ready.complete(message);
        if (_disposed) {
          message.send(null);
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
        _control?.release();
        _control = null;
      }
    });
    try {
      await Isolate.spawn(
        _runMermaidWorker,
        (_config, responses.sendPort, runtime, control.address),
        onError: responses.sendPort,
        onExit: responses.sendPort,
        debugName: 'Mermaid vector rendering',
      );
    } catch (error, stack) {
      control.release();
      control.release();
      _control = null;
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
    // Polling checkpoints stop active JS execution; the worker then destroys
    // its context and releases its reference. Never free a running JSC context.
    _control?.cancelThrough(_nextId);
    _commands?.send(null);
  }
}

class _WorkerConfig {
  const _WorkerConfig(this.cacheEntries, this.cacheBytes);
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

void _runMermaidWorker((_WorkerConfig, SendPort, String, int) args) {
  final (config, responses, runtime, address) = args;
  final commands = ReceivePort();
  final cache = MermaidSvgCache.memory(
    maxEntries: config.cacheEntries,
    maxBytes: config.cacheBytes,
  );
  final engine = NativePeleBridge.at(address);
  final svgBridge = NativeSvgBridge();
  responses.send(commands.sendPort);
  commands.listen((message) {
    if (message == null) {
      cache.clear();
      engine.close();
      engine.release();
      commands.close();
      Isolate.exit();
    }
    final request = message as _WorkerRequest;
    try {
      final config = jsonDecode(request.options) as Map<String, dynamic>;
      final limits = config['resources']['limits'] as Map<String, dynamic>;
      if (utf8.encode(request.source).length >
          (limits['max_source_bytes'] as int)) {
        throw const MermaidRenderFailure(
          message: 'Diagram source exceeds the byte limit',
        );
      }
      final site = config['site_config'] as Map<String, dynamic>;
      final layout = config['layout'] as Map<String, dynamic>;
      final variables = Map<String, String>.from(site['themeVariables'] as Map);
      final identity = svgBridge.cacheIdentity;
      final key = MermaidSvgCache.keyFor(
        source: request.source,
        optionsJson: request.options,
        engineVersion: NativePeleRenderer.engineVersion,
        preprocessingIdentity: identity,
      );
      final options = <String, Object?>{
        'responsive': false,
        'limit': limits['max_source_bytes'],
        'outputLimit': limits['max_svg_bytes'],
        if (limits['max_model_items'] != null)
          'maxEdges': limits['max_model_items'],
        'idPrefix': 'linefold-${key.substring(0, 20)}',
        'fontFamily':
            variables['fontFamily'] ?? svgBridge.environment['fontFamily'],
        'fontFamilyMono':
            variables['fontFamily'] ?? svgBridge.environment['fontFamily'],
        if (layout['container_width'] != null)
          'maxWidth': layout['container_width'],
        'now': config['fixed_today'] == null
            ? 0
            : DateTime.parse(
                config['fixed_today'] as String,
              ).millisecondsSinceEpoch,
      };
      Object result;
      if (request.method == 'validate') {
        try {
          engine.run(
            runtime,
            request.source,
            options,
            request.id,
            parseOnly: true,
          );
          result = const MermaidValidationResult(valid: true);
        } catch (e) {
          result = MermaidValidationResult(
            valid: false,
            errorMessage: e.toString(),
          );
        }
      } else {
        final cached = cache.get(key);
        Map<String, dynamic>? rendered;
        Map<String, dynamic> render() => rendered ??= engine.run(
          runtime,
          request.source,
          options,
          request.id,
        );
        if (request.method == 'layout') {
          final r = render();
          result = jsonEncode({
            'width': r['width'],
            'height': r['height'],
            'type': r['type'],
            'links': r['links'],
          });
        } else {
          final expanded = cached == null
              ? svgBridge.preprocess(
                  normalizePeleSvg(
                    render()['svg'] as String,
                    dark: (site['theme'] as String).contains('dark'),
                    overrides: {
                      for (final e in variables.entries)
                        if (e.key.startsWith('--pele-')) e.key: e.value,
                    },
                  ),
                )
              : jsonDecode(cached) as Map<String, dynamic>;
          if (cached == null) cache.set(key, jsonEncode(expanded));
          result = MermaidRenderResult(
            source: request.source,
            svg: expanded['svg'] as String,
            optionsJson: request.options,
            engineVersion: NativePeleRenderer.engineVersion,
            preprocessingIdentity: identity,
            width: (expanded['width'] as num).toDouble(),
            height: (expanded['height'] as num).toDouble(),
            fromCache: cached != null,
            layoutJson: request.includeLayout
                ? jsonEncode({
                    'width': expanded['width'],
                    'height': expanded['height'],
                  })
                : null,
          );
        }
      }
      responses.send(_WorkerReply(request.id, value: result));
    } catch (error, stack) {
      responses.send(
        _WorkerReply(
          request.id,
          error: error.toString(),
          stack: stack.toString(),
        ),
      );
    }
  });
}
