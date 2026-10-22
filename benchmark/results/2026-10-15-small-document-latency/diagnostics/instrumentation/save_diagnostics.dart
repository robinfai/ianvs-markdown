// Temporary R4-03 attribution; removed before formal acceptance builds.
abstract final class SaveDiagnostics {
  static const enabled = bool.fromEnvironment('IANVS_PERF_ATTRIBUTION');
  static final phases = <String, double>{};
  static Stopwatch? begin() => enabled ? (Stopwatch()..start()) : null;
  static void mark(String phase, Stopwatch? watch) {
    if (watch == null) return;
    phases[phase] = watch.elapsedMicroseconds / 1000;
    watch.reset();
  }
}
