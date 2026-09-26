import 'dart:convert';

import 'package:crypto/crypto.dart';

class MermaidSvgCache {
  MermaidSvgCache.memory({
    this.maxEntries = 64,
    this.maxBytes = 16 * 1024 * 1024,
  }) : assert(maxEntries > 0),
       assert(maxBytes > 0);

  final int maxEntries;

  /// Bounds retained Dart string payloads (UTF-16 code units), not GPU memory.
  final int maxBytes;
  int _sizeBytes = 0;
  int get sizeBytes => _sizeBytes;
  int get length => _map.length;
  final Map<String, String> _map = <String, String>{};

  static String keyFor({
    required String source,
    required String optionsJson,
    required String engineVersion,
    String preprocessingIdentity = '',
  }) {
    final bytes = utf8.encode(
      jsonEncode([engineVersion, preprocessingIdentity, optionsJson, source]),
    );
    return sha256.convert(bytes).toString();
  }

  String? get(String key) {
    final value = _map.remove(key);
    if (value == null) return null;
    _map[key] = value;
    return value;
  }

  void set(String key, String svg) {
    final previous = _map.remove(key);
    if (previous != null) _sizeBytes -= previous.length * 2;
    final size = svg.length * 2;
    if (size > maxBytes) return;
    while (_map.length >= maxEntries || _sizeBytes + size > maxBytes) {
      _sizeBytes -= _map.remove(_map.keys.first)!.length * 2;
    }
    _map[key] = svg;
    _sizeBytes += size;
  }

  void clear() {
    _map.clear();
    _sizeBytes = 0;
  }
}
