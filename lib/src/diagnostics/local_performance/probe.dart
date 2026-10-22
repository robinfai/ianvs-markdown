import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' show FramePhase, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

import 'corpus.dart';
import 'probe_stub.dart' if (dart.library.io) 'probe_io.dart';

const localPerformanceEnabled = bool.fromEnvironment('IANVS_LOCAL_PERFORMANCE');
const _attribution = bool.fromEnvironment('IANVS_PERF_ATTRIBUTION');
const _attributionBytes = int.fromEnvironment(
  'IANVS_PERF_ATTRIBUTION_BYTES',
  defaultValue: 1048576,
);

/// Host wiring only. The existing main, editor tree and file services remain.
class LocalPerformanceHost {
  const LocalPerformanceHost({
    required this.entry,
    required this.controller,
    required this.scroll,
    required this.prepare,
    required this.mode,
    this.beforeOpen,
    this.open,
    this.save,
    this.flush,
    this.ioMetrics,
  });
  final String entry;
  final IanvsMarkdownController Function() controller;
  final ScrollController Function() scroll;
  final Future<void> Function(String path, String source) prepare;
  final void Function(IanvsMarkdownEditorMode mode) mode;
  final Future<void> Function()? beforeOpen;
  final Future<void> Function(String path)? open;
  final Future<void> Function()? save;
  final Future<void> Function()? flush;
  final Map<String, double> Function()? ioMetrics;
}

class LocalPerformancePanel extends StatefulWidget {
  const LocalPerformancePanel({
    super.key,
    required this.host,
    required this.child,
  });
  final LocalPerformanceHost host;
  final Widget child;
  @override
  State<LocalPerformancePanel> createState() => _LocalPerformancePanelState();
}

class _LocalPerformancePanelState extends State<LocalPerformancePanel> {
  final content = GlobalKey();
  final status = ValueNotifier('Ready: fixed R4-02 baseline');
  bool started = false;
  LocalPerformanceRun? runner;
  @override
  void dispose() {
    runner?.cancel();
    status.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      KeyedSubtree(key: content, child: widget.child),
      Positioned(
        right: 12,
        bottom: 8,
        child: Material(
          elevation: 4,
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: ValueListenableBuilder(
              valueListenable: status,
              builder: (context, value, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 340,
                    child: Text(
                      value,
                      maxLines: 4,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('local-performance-start'),
                    onPressed: started
                        ? null
                        : () {
                            setState(() => started = true);
                            runner = LocalPerformanceRun(
                              widget.host,
                              () => content.currentContext!,
                              status,
                            );
                            unawaited(runner!.run());
                          },
                    child: const Text('Run R4-02'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class LocalPerformanceRun {
  LocalPerformanceRun(this.host, this.root, this.status);
  final LocalPerformanceHost host;
  final BuildContext Function() root;
  final ValueNotifier<String> status;
  final environment = LocalWindowEnvironment();
  final frames = <FrameTiming>[];
  final records = <Map<String, Object?>>[];
  final cases = <Map<String, Object?>>[];
  final errors = <String>[];
  ProbeStorage? storage;
  bool cancelled = false;
  void cancel() {
    cancelled = true;
    environment.invalidate('Host disposed');
  }

  void updateStatus(String value) {
    if (!cancelled) status.value = value;
  }

  int eventSequence = 0;
  int size = 0;
  late String source;
  late String filePath;
  late String startedAt;
  Map<String, Object?>? display;
  IanvsMarkdownController get controller => host.controller();
  int get stamp =>
      SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds;
  Future<void> frame() async {
    environment.throwIfInvalid();
    await SchedulerBinding.instance.endOfFrame.timeout(
      const Duration(seconds: 30),
    );
    environment.throwIfInvalid();
  }

  Future<void> settle() async {
    await frame();
    await frame();
  }

  void recordFrames(List<FrameTiming> value) => frames.addAll(value);
  Future<void> event(Map<String, Object?> value) async {
    await storage!.event({
      'sequence': eventSequence++,
      'atUtc': DateTime.now().toUtc().toIso8601String(),
      ...value,
    });
  }

  List<EditableTextState> editables() {
    final found = <EditableTextState>[];
    void visit(Element element) {
      if (element is StatefulElement && element.state is EditableTextState) {
        final state = element.state as EditableTextState;
        if (!state.widget.readOnly &&
            element.findAncestorWidgetOfExactType<IanvsMarkdownLiveEditor>() !=
                null) {
          found.add(state);
        }
      }
      element.visitChildren(visit);
    }

    visit(root() as Element);
    return found;
  }

  EditableTextState active() =>
      editables().singleWhere((e) => e.widget.focusNode.hasFocus);

  Future<void> prepare(IanvsMarkdownEditorMode mode) async {
    host.mode(IanvsMarkdownEditorMode.source);
    await settle();
    controller.value = TextEditingValue(
      text: source,
      selection: const TextSelection.collapsed(offset: 2),
    );
    controller.clearHistory();
    final field = editables().single;
    field.widget.focusNode.requestFocus();
    await settle();
    host.scroll().jumpTo(0);
    if (mode != IanvsMarkdownEditorMode.source) {
      host.mode(mode);
      await settle();
    }
    if (controller.text != source) {
      throw StateError('Preparation changed source');
    }
    await host.flush?.call();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await environment.check();
  }

  Future<void> sample(String operation, String stage, int index) async {
    final mode = operation.startsWith('live')
        ? IanvsMarkdownEditorMode.livePreview
        : operation == 'readToLive'
        ? IanvsMarkdownEditorMode.preview
        : IanvsMarkdownEditorMode.source;
    await prepare(mode);
    if (operation == 'open') {
      await host.beforeOpen!();
      await settle();
      await host.flush?.call();
    }
    final savedText = '${source}saved-$stage-$index';
    if (operation == 'save') {
      controller.value = TextEditingValue(
        text: savedText,
        selection: const TextSelection.collapsed(offset: 2),
      );
      await settle();
      await host.flush?.call();
    }
    final before = await environment.check();
    final identity = {
      'bytes': size,
      'operation': operation,
      'stage': stage,
      'index': index,
    };
    await event({...identity, 'event': 'start', 'window': before});
    String expected = operation == 'save' ? savedText : source;
    EditableTextState? inputField;
    TextEditingValue? nextInput;
    if (operation.endsWith('Type') || operation.endsWith('Paste')) {
      final input = operation.endsWith('Type') ? 'a' : localPaste;
      inputField = active();
      final local = inputField.widget.controller.value;
      final offset = controller.selection.extentOffset;
      if (offset != 2) throw StateError('Input position changed');
      expected = source.replaceRange(offset, offset, input);
      nextInput = local.replaced(local.selection, input);
    }
    final nativeBefore = _attribution
        ? await LocalWindowEnvironment.channel.invokeMapMethod<String, Object?>(
            'inputSnapshot',
          )
        : null;
    final first = stamp;
    final firstNumber = PlatformDispatcher.instance.frameData.frameNumber;
    final timelineStart = _attribution ? developer.Timeline.now : null;
    final watch = Stopwatch()..start();
    int? tailPasses;
    switch (operation) {
      case 'sourceType' || 'liveType' || 'sourcePaste' || 'livePaste':
        if (operation.endsWith('Type')) {
          inputField!.updateEditingValue(nextInput!);
        } else {
          // Same insertion boundary as EditableText._pasteText after Clipboard.getData.
          inputField!.userUpdateTextEditingValue(
            nextInput!,
            SelectionChangedCause.keyboard,
          );
        }
      case 'liveToSource':
        host.mode(IanvsMarkdownEditorMode.source);
      case 'sourceToRead':
        host.mode(IanvsMarkdownEditorMode.preview);
      case 'readToLive':
        host.mode(IanvsMarkdownEditorMode.livePreview);
      case 'sourceTail' || 'liveTail':
        // Lazy slivers refine their estimated extent after the first jump.
        // Measure the complete bounded arrival, including those layout frames.
        var stable = 0;
        for (var pass = 1; pass <= 100; pass++) {
          final scroll = host.scroll();
          final target = scroll.position.maxScrollExtent;
          scroll.jumpTo(target);
          await frame();
          final current = scroll.position;
          final arrived =
              (current.pixels - current.maxScrollExtent).abs() <= 1 &&
              (target - current.maxScrollExtent).abs() <= 1;
          stable = arrived ? stable + 1 : 0;
          if (stable == 2) {
            tailPasses = pass;
            break;
          }
        }
        if (tailPasses == null) {
          throw StateError('Tail did not converge within 100 frames');
        }
      case 'open':
        await host.open!(filePath);
      case 'save':
        await host.save!();
      default:
        throw StateError('Unknown operation $operation');
    }
    final callbackMs = watch.elapsedMicroseconds / 1000;
    await frame();
    final latencyMs = watch.elapsedMicroseconds / 1000;
    watch.stop();
    final timelineEnd = _attribution ? developer.Timeline.now : null;
    final last = stamp;
    final lastNumber = PlatformDispatcher.instance.frameData.frameNumber;
    final rss = probeRssMiB;
    if (controller.text != expected) {
      throw StateError('$operation changed source unexpectedly');
    }
    if (operation.endsWith('Tail') &&
        (host.scroll().offset - host.scroll().position.maxScrollExtent).abs() >
            1) {
      throw StateError('Tail was not reached');
    }
    if (operation == 'save' &&
        (controller.isDirty || await storage!.read(filePath) != expected)) {
      throw StateError('Save bytes/dirty mismatch');
    }
    final after = await environment.check();
    final nativeAfter = _attribution
        ? await LocalWindowEnvironment.channel.invokeMapMethod<String, Object?>(
            'inputSnapshot',
          )
        : null;
    final record = <String, Object?>{
      ...identity,
      if (_attribution) ...{
        'nativeBefore': nativeBefore,
        'nativeAfter': nativeAfter,
        'timelineStartMicros': timelineStart,
        'timelineEndMicros': timelineEnd,
      },
      'callbackMs': callbackMs,
      'nextFrameMs': latencyMs,
      'frameWaitMs': latencyMs - callbackMs,
      'rssMiB': rss,
      'firstFrameNumber': firstNumber,
      'lastFrameNumber': lastNumber,
      'firstFrameMicros': first,
      'lastFrameMicros': last,
      'sourcePreserved': true,
      'tailPasses': ?tailPasses,
      if (inputField != null)
        'inputStyle': {
          'fontFamily': inputField.widget.style.fontFamily,
          'fontFamilyFallback': inputField.widget.style.fontFamilyFallback,
          'fontSize': inputField.widget.style.fontSize,
          'height': inputField.widget.style.height,
          'letterSpacing': inputField.widget.style.letterSpacing,
        },
      'mode': controller.mode.name,
      'window': after,
      if (operation == 'open' || operation == 'save') 'ioMs': host.ioMetrics!(),
    };
    records.add(record);
    await event({...record, 'event': 'end'});
    // Finish host persistence outside the editor latency before the next sample.
    await host.flush?.call();
  }

  Future<void> run() async {
    final oldError = FlutterError.onError;
    final oldPlatformError = PlatformDispatcher.instance.onError;
    startedAt = DateTime.now().toUtc().toIso8601String();
    var complete = false;
    try {
      if (!localPerformanceEnabled || kDebugMode || kIsWeb) {
        throw StateError('Opt-in Profile/Release main required');
      }
      storage = await ProbeStorage.create(host.entry);
      if (_attribution) {
        final info = await developer.Service.getInfo();
        await storage!.diagnostic({
          'vmService': info.serverUri?.toString(),
          'entry': host.entry,
          'purpose': 'CPU attribution only; never acceptance',
        });
      }
      updateStatus('Running ${host.entry}; keep this window in front');
      FlutterError.onError = (details) {
        errors.add(details.exceptionAsString());
        environment.invalidate(details.exceptionAsString());
        oldError?.call(details);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        errors.add('$error');
        environment.invalidate('$error');
        return true;
      };
      SchedulerBinding.instance.addTimingsCallback(recordFrames);
      await settle();
      await environment.initialize();
      final context = root();
      if (!context.mounted) throw StateError('Host unmounted');
      final view = View.of(context);
      final theme = IanvsMarkdownThemeData.resolve(context);
      display = {
        'physicalWidth': view.physicalSize.width,
        'physicalHeight': view.physicalSize.height,
        'devicePixelRatio': view.devicePixelRatio,
        'brightness': Theme.of(context).brightness.name,
        'textScale14': MediaQuery.textScalerOf(context).scale(14),
        'monoFontFamily': theme.monoFontFamily,
        'monoFontFamilyFallback': theme.monoFontFamilyFallback,
      };
      for (final bytes in localCorpusSizes) {
        if (_attribution && bytes != _attributionBytes) continue;
        size = bytes;
        source = localCorpus(bytes);
        filePath = await storage!.fixture(bytes, source);
        await host.prepare(filePath, source);
        await settle();
        final decision = controller.parseDecision;
        cases.add({
          'bytes': bytes,
          'utf16Units': source.length,
          'useMarkdown': decision.useMarkdown,
          'exceeded': decision.budgetExceeded?.name,
          'readingBytes': utf8.encode(decision.text).length,
          'truncated': decision.truncated,
        });
        for (final operation in [
          ...localOperations,
          if (host.open != null) 'open',
          if (host.save != null) 'save',
        ]) {
          if (_attribution &&
              !const {
                'readToLive',
                'sourceToRead',
                'save',
                'sourceType',
                'liveType',
                'sourcePaste',
                'livePaste',
              }.contains(operation)) {
            continue;
          }
          updateStatus(
            '${host.entry}: $bytes / $operation\nEvidence: ${storage!.path}',
          );
          await settle();
          await event({
            'event': 'group',
            'bytes': bytes,
            'operation': operation,
          });
          for (var i = 0; i < localWarmup; i++) {
            await sample(operation, 'warmup', i);
          }
          for (var i = 0; i < localSamples; i++) {
            await sample(operation, 'sample', i);
          }
          // Engine timing batches arrive later than endOfFrame, also in Release.
          await Future<void>.delayed(const Duration(milliseconds: 1100));
          for (final record in records.where(
            (r) => r['bytes'] == bytes && r['operation'] == operation,
          )) {
            final selected = frames.where((f) {
              // Raw begin-frame and vsync clocks can differ by microseconds.
              // Use the engine's shared frame identity, not timestamp equality.
              return f.frameNumber > (record['firstFrameNumber'] as int) &&
                  f.frameNumber <= (record['lastFrameNumber'] as int);
            }).toList();
            if (selected.isEmpty) {
              throw StateError('Missing frame evidence: $operation');
            }
            record['frames'] = [
              for (final f in selected)
                {
                  'frameNumber': f.frameNumber,
                  'vsyncMicros': f.timestampInMicroseconds(
                    FramePhase.vsyncStart,
                  ),
                  'buildMs': f.buildDuration.inMicroseconds / 1000,
                  'rasterMs': f.rasterDuration.inMicroseconds / 1000,
                  'totalMs': f.totalSpan.inMicroseconds / 1000,
                },
            ];
          }
          frames.clear();
          await storage!.result(result(false));
        }
      }
      await environment.check();
      complete = errors.isEmpty;
    } catch (error, stack) {
      errors.add('$error');
      if (storage != null) {
        await event({'event': 'error', 'error': '$error', 'stack': '$stack'});
      }
    } finally {
      environment.dispose();
      SchedulerBinding.instance.removeTimingsCallback(recordFrames);
      FlutterError.onError = oldError;
      PlatformDispatcher.instance.onError = oldPlatformError;
      if (storage != null) await storage!.result(result(complete));
      updateStatus(
        '${complete ? 'COMPLETE' : 'INVALID'} ${host.entry}\n${storage?.path ?? errors.join('; ')}',
      );
    }
  }

  Map<String, Object?> result(bool complete) => {
    'schemaVersion': 1,
    'protocol': _attribution ? 'r4-attribution-only-v1' : 'r4-main-entry-v1',
    'sourceRevision': const String.fromEnvironment('IANVS_PERF_REVISION'),
    'inputsDigest': const String.fromEnvironment('IANVS_PERF_INPUTS'),
    'entry': host.entry,
    'main': '${host.entry}/lib/main.dart',
    'buildMode': kProfileMode
        ? 'profile'
        : kReleaseMode
        ? 'release'
        : 'debug',
    'inputKind':
        'synthetic-framework; paste excludes OS clipboard; no physical IME/CUA latency',
    'corpusVersion': localCorpusVersion,
    'warmup': localWarmup,
    'samples': localSamples,
    'budget': 'default',
    'startedAtUtc': startedAt,
    'finishedAtUtc': DateTime.now().toUtc().toIso8601String(),
    'initialWindow': environment.initial,
    'display': display,
    'system': probeSystem,
    'complete': complete,
    'errors': errors,
    'cases': cases,
    'records': records,
  };
}

class LocalWindowEnvironment {
  static const channel = MethodChannel('ianvs_markdown/benchmark_environment');
  Map<String, Object?>? initial;
  String? failure;
  void invalidate(String message) => failure ??= message;
  void throwIfInvalid() {
    if (failure != null) throw StateError(failure!);
  }

  Future<Map<String, Object?>> read() async =>
      await channel.invokeMapMethod<String, Object?>('snapshot') ??
      (throw StateError('Missing native window state'));
  static bool visible(Map<String, Object?> s) =>
      s['active'] == true &&
      s['visible'] == true &&
      s['occlusionVisible'] == true &&
      s['onActiveSpace'] == true &&
      s['miniaturized'] == false &&
      s['appHidden'] == false;
  Future<void> initialize() async {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'changed' && initial != null) {
        final s = Map<String, Object?>.from(call.arguments as Map);
        if (!visible(s) || !mapEquals(initial, s)) {
          invalidate('Window changed: $s');
        }
      }
    });
    Map<String, Object?>? previous;
    for (var i = 0; i < 20; i++) {
      final s = await read();
      if (visible(s) && previous != null && mapEquals(s, previous)) {
        initial = s;
        return;
      }
      previous = s;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw StateError('Window not ready: $previous');
  }

  Future<Map<String, Object?>> check() async {
    throwIfInvalid();
    final s = await read();
    if (!visible(s) || !mapEquals(initial, s)) {
      throw StateError('Window changed: $s');
    }
    return s;
  }

  void dispose() => channel.setMethodCallHandler(null);
}
