// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_markdown/src/editor/editor_diagnostics.dart';

import 'corpus.dart';

const samples = int.fromEnvironment('BENCHMARK_SAMPLES', defaultValue: 20);
const warmup = int.fromEnvironment('BENCHMARK_WARMUP', defaultValue: 5);
final failures = <String>[];

void main() {
  if (!kProfileMode || !IanvsMarkdownEditorDiagnostics.enabled) {
    throw StateError(
      'Run in profile mode with IANVS_MARKDOWN_DIAGNOSTICS=true',
    );
  }
  FlutterError.onError = (details) {
    failures.add(details.exceptionAsString());
    print('IANVS_BENCHMARK_FAILURE: ${jsonEncode(failures.last)}');
    print(details.stack);
    // Later timings are invalid after a rendering exception.
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

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(frames.addAll);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(run()));
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
                  autofocus: true,
                  showToolbar: false,
                  enableHeadingFolding: true,
                ),
              ),
      ),
    ),
  );

  Future<void> nextFrame() => SchedulerBinding.instance.endOfFrame;

  Future<void> replaceDocument(String source) async {
    final old = controller;
    controller = IanvsMarkdownController(text: source);
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

  Future<Map<String, Object>> measure(
    String name,
    Future<void> Function(int) action,
  ) async {
    for (var i = 0; i < warmup; i += 1) {
      await action(i);
      await nextFrame();
    }
    // Profile FrameTiming delivery is batched. Drain the previous phase first.
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    frames.clear();
    final durations = <double>[];
    final parseCounts = <double>[];
    final rss = <double>[];
    for (var i = 0; i < samples; i += 1) {
      final parses = IanvsMarkdownEditorDiagnostics.documentParses;
      final watch = Stopwatch()..start();
      await action(i + warmup);
      await nextFrame();
      durations.add(watch.elapsedMicroseconds / 1000);
      parseCounts.add(
        (IanvsMarkdownEditorDiagnostics.documentParses - parses).toDouble(),
      );
      rss.add(ProcessInfo.currentRss / (1024 * 1024));
    }
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final result = <String, Object>{
      'operation': name,
      'latencyMs': distribution(durations),
      'documentParses': distribution(parseCounts),
      'buildMs': distribution([
        for (final frame in frames) frame.buildDuration.inMicroseconds / 1000,
      ]),
      'rasterMs': distribution([
        for (final frame in frames) frame.rasterDuration.inMicroseconds / 1000,
      ]),
      'rssMiB': distribution(rss),
    };
    print('IANVS_BENCHMARK_PROGRESS: $name ${durations.length} samples');
    return result;
  }

  Future<void> run() async {
    final results = <Map<String, Object>>[];
    try {
      for (final size in corpusSizes) {
        final source = benchmarkCorpus(size);
        for (final full in [false, true]) {
          budget = full ? null : const IanvsMarkdownRenderBudget();
          final decision = scanMarkdownForRendering(
            source,
            budget: const IanvsMarkdownRenderBudget(),
          );
          print('IANVS_BENCHMARK_PROGRESS: bytes=$size full=$full');
          final operations = <Map<String, Object>>[];
          results.add({
            'utf8Bytes': utf8.encode(source).length,
            'utf16Units': source.length,
            'lines': '\n'.allMatches(source).length + 1,
            'blocks': parseMarkdownBlocks(source, splitListItems: true).length,
            'budget': full ? 'unlimited-controlled-corpus' : 'default',
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

          checkpoint('initialDisplay');
          operations.add(
            await measure('initialDisplay', (_) => replaceDocument(source)),
          );
          checkpoint('selection');
          operations.add(
            await measure('selection', (i) async {
              controller!.selection = TextSelection.collapsed(
                offset: 2 + i % 20,
              );
            }),
          );
          checkpoint('typing');
          operations.add(
            await measure('typing', (i) async {
              final editable = activeEditable();
              final value = editable.widget.controller.value;
              final offset = value.selection.extentOffset;
              editable.updateEditingValue(
                TextEditingValue(
                  text: value.text.replaceRange(offset, offset, 'a'),
                  selection: TextSelection.collapsed(offset: offset + 1),
                ),
              );
            }),
          );
          checkpoint('scroll');
          controller!.text = source;
          controller!.clearHistory();
          await nextFrame();
          operations.add(
            await measure('scroll', (i) async {
              final destination = i.isEven ? 0.0 : 300.0 + (i % 4) * 300;
              scroll.jumpTo(
                destination.clamp(0.0, scroll.position.maxScrollExtent),
              );
            }),
          );
          checkpoint('modeSwitch');
          scroll.jumpTo(0);
          await nextFrame();
          operations.add(
            await measure('modeSwitch', (i) async {
              controller!.mode = [
                IanvsMarkdownEditorMode.source,
                IanvsMarkdownEditorMode.preview,
                IanvsMarkdownEditorMode.livePreview,
              ][i % 3];
            }),
          );
          checkpoint('caseComplete');
        }
      }
      final result = snapshot(results, complete: true);
      print('IANVS_BENCHMARK_RESULT: ${jsonEncode(result)}');
      exit(failures.isEmpty ? 0 : 1);
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
      'corpusVersion': corpusVersion,
      'mode': 'profile',
      'warmupPerOperation': warmup,
      'samplesPerOperation': samples,
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
