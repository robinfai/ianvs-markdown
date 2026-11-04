// Opt-in local measurements; no document content or network telemetry.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FramePhase;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

const scrollFrameProbeEnabled = bool.fromEnvironment('LINEFOLD_SCROLL_PROBE');

class ScrollFrameProbe extends StatefulWidget {
  const ScrollFrameProbe({super.key, required this.host, required this.child});
  final String host;
  final Widget child;
  @override
  State<ScrollFrameProbe> createState() => _ScrollFrameProbeState();
}

class _ScrollFrameProbeState extends State<ScrollFrameProbe> {
  final frames = <List<int>>[];
  Timer? timer;
  int? start;
  int? end;
  int run = 0;
  bool running = false;
  final content = GlobalKey();
  Map<String, Object?> metrics = {};
  Future<void> measure() async {
    ScrollPosition? target;
    void visit(Element element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        final position = (element.state as ScrollableState).position;
        if (position.axis == Axis.vertical &&
            position.viewportDimension > 300 &&
            position.maxScrollExtent > 5000 &&
            (target == null ||
                position.viewportDimension > target!.viewportDimension)) {
          target = position;
        }
      }
      element.visitChildren(visit);
    }

    visit(content.currentContext! as Element);
    if (target == null) return;
    setState(() => running = true);
    target!.jumpTo(0);
    await Future<void>.delayed(const Duration(seconds: 2));
    await flush();
    for (final offset in [2400.0, 0.0]) {
      if (!mounted) return;
      await target!.animateTo(
        offset,
        duration: const Duration(seconds: 6),
        curve: Curves.linear,
      );
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    if (mounted) setState(() => running = false);
  }

  void timings(List<FrameTiming> batch) {
    final since = start;
    if (since == null) return;
    for (final frame in batch) {
      final vsync = frame.timestampInMicroseconds(FramePhase.vsyncStart);
      if (vsync >= since && (end == null || vsync <= end!)) {
        frames.add([
          vsync,
          frame.buildDuration.inMicroseconds,
          frame.rasterDuration.inMicroseconds,
          frame.totalSpan.inMicroseconds,
        ]);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(timings);
  }

  Future<void> flush() async {
    if (!mounted || frames.isEmpty) return;
    final record = {
      'rssBytes': ProcessInfo.currentRss,
      'peakRssBytes': ProcessInfo.maxRss,
      'host': widget.host,
      'run': run++,
      'controlled': running,
      ...metrics,
      'columns': ['vsync_us', 'build_us', 'raster_us', 'total_us'],
      'frames': List<List<int>>.of(frames),
    };
    start = null;
    frames.clear();
    final file = File(
      '${Directory.systemTemp.path}/linefold-scroll-${widget.host}.jsonl',
    );
    await file.writeAsString('${jsonEncode(record)}\n', mode: FileMode.append);
  }

  bool notification(ScrollNotification event) {
    if (event.metrics.axis != Axis.vertical) return false;
    metrics = {
      'viewport': event.metrics.viewportDimension,
      'extent': event.metrics.maxScrollExtent,
      'refreshHz': WidgetsBinding
          .instance
          .platformDispatcher
          .views
          .first
          .display
          .refreshRate,
    };
    if (event is ScrollStartNotification || event is ScrollUpdateNotification) {
      timer?.cancel();
      start ??=
          SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds;
      end = null;
    }
    if (event is ScrollEndNotification) {
      end =
          SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds;
      timer?.cancel();
      timer = Timer(const Duration(seconds: 2), flush);
    }
    return false;
  }

  @override
  void dispose() {
    timer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(timings);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: notification,
        child: Stack(
          textDirection: TextDirection.ltr,
          children: [
            KeyedSubtree(key: content, child: widget.child),
            Positioned(
              right: 24,
              bottom: 40,
              child: GestureDetector(
                onTap: running ? null : measure,
                child: DecoratedBox(
                  decoration: const BoxDecoration(color: Color(0xffcceeff)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      running ? 'Measuring…' : 'Measure scroll',
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xff000000),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}
