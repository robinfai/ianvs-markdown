import 'package:flutter/foundation.dart';

/// Internal counters for tests and opt-in profile runs; not a public export.
abstract final class IanvsMarkdownEditorDiagnostics {
  static const enabled =
      kDebugMode || bool.fromEnvironment('IANVS_MARKDOWN_DIAGNOSTICS');
  static const forceDocumentRefresh =
      enabled && bool.fromEnvironment('IANVS_MARKDOWN_FORCE_DOCUMENT_PARSE');
  static const profilePhases =
      enabled && bool.fromEnvironment('IANVS_MARKDOWN_PROFILE_PHASES');

  static final _phaseMicros = <String, int>{};
  static final _phaseCalls = <String, int>{};

  /// Opt-in synchronous attribution, kept out of accepted latency runs.
  /// Nested phases are inclusive; do not add them to infer elapsed time.
  static T measure<T>(String phase, T Function() operation) {
    if (!profilePhases) return operation();
    final watch = Stopwatch()..start();
    try {
      return operation();
    } finally {
      watch.stop();
      _phaseMicros.update(
        phase,
        (value) => value + watch.elapsedMicroseconds,
        ifAbsent: () => watch.elapsedMicroseconds,
      );
      _phaseCalls.update(phase, (value) => value + 1, ifAbsent: () => 1);
    }
  }

  static void resetPhases() {
    _phaseMicros.clear();
    _phaseCalls.clear();
  }

  static Map<String, Object> phaseSnapshot() => {
    for (final entry in _phaseMicros.entries)
      entry.key: {
        'microseconds': entry.value,
        'calls': _phaseCalls[entry.key]!,
      },
  };

  static var _documentParses = 0;
  static int get documentParses => _documentParses;

  static void recordDocumentParse() {
    if (enabled) _documentParses += 1;
  }
}
