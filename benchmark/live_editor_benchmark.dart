// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' show FramePhase;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_markdown/src/editor/editor_diagnostics.dart';

import 'corpus.dart';

const samples = int.fromEnvironment('BENCHMARK_SAMPLES', defaultValue: 20);
const warmup = int.fromEnvironment('BENCHMARK_WARMUP', defaultValue: 5);
const allOperations = [
  'initialDisplay',
  'selection',
  'typing',
  'scroll',
  'liveToSource',
  'sourceToReading',
  'readingToLive',
];
final selectedSizes = const String.fromEnvironment(
  'BENCHMARK_SIZES',
  defaultValue: '10240,102400,1048576',
).split(',').map(int.parse).toList();
final selectedBudgets = const String.fromEnvironment(
  'BENCHMARK_BUDGETS',
  defaultValue: 'default,unlimited',
).split(',');
final selectedOperations = const String.fromEnvironment(
  'BENCHMARK_OPERATIONS',
  defaultValue:
      'initialDisplay,selection,typing,scroll,liveToSource,sourceToReading,readingToLive',
).split(',');
final failures = <String>[];

void main() {
  if (!kProfileMode || !IanvsMarkdownEditorDiagnostics.enabled) {
    throw StateError(
      'Run in profile mode with IANVS_MARKDOWN_DIAGNOSTICS=true',
    );
  }
  if (samples < 1 ||
      warmup < 0 ||
      selectedSizes.any((size) => !corpusSizes.contains(size)) ||
      selectedBudgets.any(
        (value) => !['default', 'unlimited'].contains(value),
      ) ||
      selectedOperations.any((value) => !allOperations.contains(value))) {
    throw ArgumentError('Invalid benchmark configuration');
  }
  FlutterError.onError = (details) {
    failures.add(details.exceptionAsString());
    print('IANVS_BENCHMARK_FAILURE: ${jsonEncode(failures.last)}');
    print(details.stack);
    exit(1);
  };
  runApp(const _BenchmarkApp());
}

class _BenchmarkApp extends StatefulWidget {
  const _BenchmarkApp();

  @override
  State<_BenchmarkApp> createState() => _BenchmarkAppState();
}

class _BenchmarkAppState extends State<_BenchmarkApp> {
  final scroll = ScrollController();
  var editorKey = GlobalKey();
  final frames = <FrameTiming>[];
  IanvsMarkdownController? controller;
  IanvsMarkdownRenderBudget? budget;
  var generation = 0;
  var currentSize = 0;
  var currentBudget = '';
  final environment = _BenchmarkEnvironment();

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(frames.addAll);
    // Query native state even if an occluded window never produces a frame.
    unawaited(run());
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 1000,
        height: 720,
        child: controller == null
            ? const SizedBox.shrink()
            : KeyedSubtree(
                key: ValueKey(generation),
                child: IanvsMarkdownLiveEditor(
                  key: editorKey,
                  controller: controller!,
                  scrollController: scroll,
                  renderBudget: budget,
                  clipboardBudget: budget,
                  autofocus: true,
                  showToolbar: false,
                  enableHeadingFolding: true,
                ),
              ),
      ),
    ),
  );

  Future<void> nextFrame() => SchedulerBinding.instance.endOfFrame;
  int get frameStamp =>
      SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds;

  Future<void> replaceDocument(String source) async {
    final old = controller;
    controller = IanvsMarkdownController(text: source, parseBudget: budget);
    editorKey = GlobalKey();
    setState(() => generation += 1);
    await nextFrame();
    await nextFrame(); // Includes the post-frame autofocus projection.
    old?.dispose();
  }

  EditableTextState activeEditable() {
    EditableTextState? result;
    void visit(Element element) {
      if (element is StatefulElement &&
          element.state is EditableTextState &&
          !(element.widget as EditableText).readOnly &&
          (element.widget as EditableText).focusNode.hasFocus) {
        result = element.state as EditableTextState;
      }
      element.visitChildren(visit);
    }

    visit(editorKey.currentContext! as Element);
    return result ?? (throw StateError('No active editable'));
  }

  void trace(Map<String, Object> event) {
    print(
      'IANVS_BENCHMARK_SAMPLE: ${jsonEncode({'utf8Bytes': currentSize, 'budget': currentBudget, ...event})}',
    );
  }

  Future<void> action(
    _Operation operation,
    String stage,
    int index,
    Future<void> Function() callback,
  ) async {
    final identity = {
      'operation': operation.name,
      'stage': stage,
      'index': index,
    };
    final before = await environment.check();
    trace({
      ...identity,
      'event': 'start',
      'timelineMicros': developer.Timeline.now,
      'windowEnvironment': before,
    });
    final firstFrame = frameStamp;
    IanvsMarkdownEditorDiagnostics.resetPhases();
    final parses = IanvsMarkdownEditorDiagnostics.documentParses;
    final watch = Stopwatch()..start();
    await callback();
    final callbackMs = watch.elapsedMicroseconds / 1000;
    await nextFrame();
    watch.stop();
    final latency = watch.elapsedMicroseconds / 1000;
    final parseCount = (IanvsMarkdownEditorDiagnostics.documentParses - parses)
        .toDouble();
    final rss = ProcessInfo.currentRss / (1024 * 1024);
    final lastFrame = frameStamp;
    final phaseSnapshot = IanvsMarkdownEditorDiagnostics.phaseSnapshot();
    // Keep method-channel overhead outside the latency and frame intervals.
    final after = await environment.check();
    if (stage == 'sample') {
      operation.durations.add(latency);
      operation.parses.add(parseCount);
      operation.rss.add(rss);
      operation.callbackMs.add(callbackMs);
      operation.frameWaitMs.add(latency - callbackMs);
      operation.frameIntervals.add((firstFrame, lastFrame));
      if (IanvsMarkdownEditorDiagnostics.profilePhases) {
        operation.phases.add(phaseSnapshot);
      }
    }
    trace({
      ...identity,
      'event': 'end',
      'timelineMicros': developer.Timeline.now,
      'latencyMs': latency,
      'callbackMs': callbackMs,
      'completionFrameWaitMs': latency - callbackMs,
      'lifecycle': SchedulerBinding.instance.lifecycleState?.name ?? 'unknown',
      'documentParses': parseCount,
      'rssMiB': rss,
      'firstFrameMicros': firstFrame,
      'lastFrameMicros': lastFrame,
      'windowEnvironment': after,
      if (IanvsMarkdownEditorDiagnostics.profilePhases) 'phases': phaseSnapshot,
    });
  }

  Future<Map<String, Object>> measure(
    String name,
    Future<void> Function(int) callback,
  ) async {
    final operation = _Operation(name);
    for (var i = 0; i < warmup; i += 1) {
      await action(operation, 'warmup', i, () => callback(i));
    }
    // Profile FrameTiming delivery is batched. Drain warmup frames first.
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    frames.clear();
    for (var i = 0; i < samples; i += 1) {
      await action(operation, 'sample', i, () => callback(i + warmup));
    }
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    print('IANVS_BENCHMARK_PROGRESS: $name $samples samples');
    return operation.result(frames);
  }

  Future<List<Map<String, Object>>> measureModes() async {
    final transitions = [
      (_Operation('liveToSource'), IanvsMarkdownEditorMode.source),
      (_Operation('sourceToReading'), IanvsMarkdownEditorMode.preview),
      (_Operation('readingToLive'), IanvsMarkdownEditorMode.livePreview),
    ];
    Future<void> cycle(String stage, int index) async {
      for (final (operation, mode) in transitions) {
        final selected = selectedOperations.contains(operation.name);
        await action(
          operation,
          selected ? stage : 'preparation',
          index,
          () async => controller!.mode = mode,
        );
      }
    }

    for (var i = 0; i < warmup; i += 1) {
      await cycle('warmup', i);
    }
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    frames.clear();
    for (var i = 0; i < samples; i += 1) {
      await cycle('sample', i);
    }
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    return [
      for (final (operation, _) in transitions)
        if (selectedOperations.contains(operation.name))
          operation.result(frames),
    ];
  }

  Future<void> run() async {
    final results = <Map<String, Object>>[];
    try {
      await environment.initialize();
      await nextFrame();
      for (final size in selectedSizes) {
        final source = benchmarkCorpus(size);
        currentSize = size;
        for (final selectedBudget in selectedBudgets) {
          final full = selectedBudget == 'unlimited';
          currentBudget = selectedBudget;
          budget = full ? null : const IanvsMarkdownRenderBudget();
          final decision = scanMarkdownForRendering(
            source,
            budget: const IanvsMarkdownRenderBudget(),
          );
          print('IANVS_BENCHMARK_PROGRESS: bytes=$size budget=$selectedBudget');
          final operations = <Map<String, Object>>[];
          results.add({
            'utf8Bytes': utf8.encode(source).length,
            'utf16Units': source.length,
            'lines': '\n'.allMatches(source).length + 1,
            'blocks': parseMarkdownBlocks(source, splitListItems: true).length,
            'budget': full ? 'unlimited-controlled-corpus' : 'default',
            'controllerUsesMarkdown': full || decision.useMarkdown,
            'liveUsesMarkdown': full || decision.useMarkdown,
            'readingUsesMarkdown': full || decision.useMarkdown,
            'readingFallbackBytes': full || decision.useMarkdown
                ? 0
                : utf8.encode(decision.text).length,
            'operations': operations,
          });
          void checkpoint(String operation) {
            print(
              'IANVS_BENCHMARK_CHECKPOINT: ${jsonEncode(snapshot(results, activeOperation: operation))}',
            );
          }

          checkpoint('setup');
          await action(_Operation('setup'), 'preparation', 0, () async {
            await replaceDocument(source);
          });
          final callbacks = <String, Future<void> Function(int)>{
            'initialDisplay': (_) => replaceDocument(source),
            'selection': (i) async {
              controller!.selection = TextSelection.collapsed(
                offset: 2 + i % 20,
              );
            },
            'typing': (i) async {
              final original = controller!.value;
              if (!original.selection.isValid ||
                  !original.selection.isCollapsed) {
                throw StateError(
                  'Typing requires a collapsed source selection',
                );
              }
              final expected = original.text.replaceRange(
                original.selection.extentOffset,
                original.selection.extentOffset,
                'a',
              );
              final editable = activeEditable();
              final value = editable.widget.controller.value;
              final offset = value.selection.extentOffset;
              editable.updateEditingValue(
                TextEditingValue(
                  text: value.text.replaceRange(offset, offset, 'a'),
                  selection: TextSelection.collapsed(offset: offset + 1),
                ),
              );
              if (controller!.text != expected) {
                throw StateError('Typing did not preserve the source mapping');
              }
            },
            'scroll': (i) async {
              final destination = i.isEven ? 0.0 : 300.0 + (i % 4) * 300;
              scroll.jumpTo(
                destination.clamp(0.0, scroll.position.maxScrollExtent),
              );
            },
          };
          for (final entry in callbacks.entries) {
            if (!selectedOperations.contains(entry.key)) continue;
            checkpoint(entry.key);
            if (entry.key == 'scroll') {
              await action(_Operation('resetText'), 'preparation', 0, () async {
                controller!.text = source;
                controller!.clearHistory();
              });
            }
            operations.add(await measure(entry.key, entry.value));
          }
          if (selectedOperations.any((name) => !callbacks.containsKey(name))) {
            checkpoint('modeSwitch');
            await action(_Operation('resetModes'), 'preparation', 0, () async {
              controller!.text = source;
              controller!.clearHistory();
              scroll.jumpTo(0);
              controller!.mode = IanvsMarkdownEditorMode.livePreview;
            });
            operations.addAll(await measureModes());
            if (controller!.text != source) {
              throw StateError('Mode switching changed document source');
            }
          }
          checkpoint('caseComplete');
        }
      }
      await environment.check();
      print(
        'IANVS_BENCHMARK_RESULT: ${jsonEncode(snapshot(results, complete: true))}',
      );
      exit(0);
    } catch (error, stack) {
      print('IANVS_BENCHMARK_ERROR: $error\n$stack');
      exit(1);
    }
  }

  Map<String, Object?> snapshot(
    List<Map<String, Object>> results, {
    bool complete = false,
    String? activeOperation,
  }) {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    return {
      'schemaVersion': 2,
      'processingBudgetPolicy': 'full-document-preflight-v1',
      'phaseTimingsEnabled': IanvsMarkdownEditorDiagnostics.profilePhases,
      'environmentPolicy': 'native-window-stable-v1',
      'initialWindowEnvironment': environment.initial,
      'corpusVersion': corpusVersion,
      'mode': 'profile',
      'warmupPerOperation': warmup,
      'samplesPerOperation': samples,
      'requestedSizes': selectedSizes,
      'requestedBudgets': selectedBudgets,
      'requestedOperations': selectedOperations,
      'fullBaseline':
          complete &&
          setEquals(selectedSizes.toSet(), corpusSizes.toSet()) &&
          setEquals(selectedBudgets.toSet(), {'default', 'unlimited'}) &&
          setEquals(selectedOperations.toSet(), allOperations.toSet()),
      'dart': Platform.version,
      'os': Platform.operatingSystemVersion,
      'viewPhysicalWidth': view.physicalSize.width,
      'viewPhysicalHeight': view.physicalSize.height,
      'devicePixelRatio': view.devicePixelRatio,
      'forceDocumentRefresh':
          IanvsMarkdownEditorDiagnostics.forceDocumentRefresh,
      'complete': complete,
      'activeOperation': activeOperation,
      'results': results,
      'errors': failures,
    };
  }
}

class _BenchmarkEnvironment {
  static const channel = MethodChannel('ianvs_markdown/benchmark_environment');
  Map<String, Object?>? initial;

  Future<Map<String, Object?>> read() async =>
      (await channel.invokeMapMethod<String, Object?>('snapshot')) ??
      (throw StateError('Missing native benchmark environment'));

  bool valid(Map<String, Object?> state) =>
      state['active'] == true &&
      state['visible'] == true &&
      state['occlusionVisible'] == true &&
      state['onActiveSpace'] == true &&
      state['miniaturized'] == false &&
      state['appHidden'] == false;

  Future<void> initialize() async {
    channel.setMethodCallHandler((call) async {
      if (call.method != 'changed' || initial == null) return;
      final state = Map<String, Object?>.from(call.arguments as Map);
      if (!valid(state) || !mapEquals(initial, state)) {
        // A hidden/locked window may stop frames. Fail from the native event
        // rather than waiting for the action's next frame or outer watchdog.
        print('IANVS_BENCHMARK_ERROR: Benchmark window changed: $state');
        exit(1);
      }
    });
    final watch = Stopwatch()..start();
    Map<String, Object?>? previous;
    while (watch.elapsed < const Duration(seconds: 10)) {
      final state = await read();
      if (valid(state) && previous != null && mapEquals(previous, state)) {
        initial = state;
        return;
      }
      previous = state;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw StateError('Benchmark window unavailable at startup: $previous');
  }

  Future<Map<String, Object?>> check() async {
    final state = await read();
    // The native generation detects a loss/regain between these snapshots.
    if (!valid(state) || !mapEquals(initial, state)) {
      throw StateError('Benchmark window changed during run: $state');
    }
    return state;
  }
}

class _Operation {
  _Operation(this.name);

  final String name;
  final durations = <double>[];
  final parses = <double>[];
  final rss = <double>[];
  final callbackMs = <double>[];
  final frameWaitMs = <double>[];
  final frameIntervals = <(int, int)>[];
  final phases = <Map<String, Object>>[];

  Map<String, Object> result(List<FrameTiming> allFrames) {
    // Both timestamps originate from the engine's raw frame clock. Assign
    // batched reports to the action's completed frames, excluding unmeasured
    // preparation and caret/settling frames between actions.
    final frames = allFrames.where((frame) {
      final stamp = frame.timestampInMicroseconds(FramePhase.vsyncStart);
      return frameIntervals.any(
        (range) => stamp > range.$1 && stamp <= range.$2,
      );
    }).toList();
    if (durations.length != samples || frames.isEmpty) {
      throw StateError(
        'Incomplete samples or missing frame evidence for $name',
      );
    }
    return {
      'operation': name,
      'latencyMs': distribution(durations),
      'documentParses': distribution(parses),
      'buildMs': distribution([
        for (final frame in frames) frame.buildDuration.inMicroseconds / 1000,
      ]),
      'rasterMs': distribution([
        for (final frame in frames) frame.rasterDuration.inMicroseconds / 1000,
      ]),
      'frameAttribution': 'engine-vsync-intervals',
      'rssMiB': distribution(rss),
      'callbackMs': distribution(callbackMs),
      'completionFrameWaitMs': distribution(frameWaitMs),
      if (IanvsMarkdownEditorDiagnostics.profilePhases) 'phases': phases,
    };
  }
}

Map<String, Object> distribution(List<double> values) {
  if (values.isEmpty) return {'count': 0};
  final sorted = [...values]..sort();
  double at(double p) =>
      sorted[(p * sorted.length).ceil().clamp(1, sorted.length) - 1];
  return {
    'count': sorted.length,
    'p50': at(.5),
    'p95': at(.95),
    'max': sorted.last,
    'raw': values,
  };
}
