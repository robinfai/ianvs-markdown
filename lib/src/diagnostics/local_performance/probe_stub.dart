class ProbeStorage {
  String get path => throw UnsupportedError('macOS diagnostics only');
  static Future<ProbeStorage> create(String entry) async =>
      throw UnsupportedError('macOS diagnostics only');
  Future<String> fixture(int bytes, String source) async => path;
  Future<void> event(Map<String, Object?> event) async {}
  Future<void> result(Map<String, Object?> value) async {}
  Future<void> diagnostic(Map<String, Object?> value) async {}
  Future<String> read(String path) async => '';
}

double get probeRssMiB => 0;
Map<String, Object> get probeSystem => {};
