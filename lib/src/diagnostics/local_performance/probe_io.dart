import 'dart:convert';
import 'dart:io';

class ProbeStorage {
  ProbeStorage._(this.directory);
  final Directory directory;
  String get path => directory.path;
  static Future<ProbeStorage> create(String entry) async => ProbeStorage._(
    await Directory.systemTemp.createTemp('ianvs-r402-$entry-'),
  );
  Future<String> fixture(int bytes, String source) async {
    await File('$path/corpus-$bytes.md').writeAsString(source, flush: true);
    final file = File('$path/$bytes.md');
    await file.writeAsString(source, flush: true);
    return file.path;
  }

  Future<void> event(Map<String, Object?> event) => File(
    '$path/trace.jsonl',
  ).writeAsString('${jsonEncode(event)}\n', mode: FileMode.append);
  Future<void> result(Map<String, Object?> value) =>
      File('$path/result.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(value)}\n',
        flush: true,
      );
  Future<String> read(String path) => File(path).readAsString();
}

double get probeRssMiB => ProcessInfo.currentRss / (1024 * 1024);
Map<String, Object> get probeSystem => {
  'dart': Platform.version,
  'os': Platform.operatingSystemVersion,
  'pid': pid,
  'executable': Platform.resolvedExecutable,
};
