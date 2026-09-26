import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'mermaid_exception.dart';

const _asset = 'package:ianvs_mermaid/src/native_svg_bridge.dart';

@Native<Pointer<Utf8> Function()>(
  symbol: 'ianvs_svg_environment',
  assetId: _asset,
)
external Pointer<Utf8> _environment();

@Native<Pointer<Utf8> Function(Pointer<Utf8>, Size, Size)>(
  symbol: 'ianvs_svg_preprocess',
  assetId: _asset,
)
external Pointer<Utf8> _preprocess(
  Pointer<Utf8> source,
  int length,
  int maxOutputBytes,
);

@Native<Void Function(Pointer<Utf8>)>(symbol: 'ianvs_svg_free', assetId: _asset)
external void _free(Pointer<Utf8> result);

/// Synchronous FFI primitives. Call only from the Mermaid rendering worker.
class NativeSvgBridge {
  late final Map<String, dynamic> environment = _read(_environment());

  String get cacheIdentity =>
      '${environment['version']}:${environment['fontFingerprint']}';

  Map<String, dynamic> preprocess(
    String svg, {
    int maxOutputBytes = 16 * 1024 * 1024,
  }) {
    final bytes = utf8.encode(svg);
    final source = calloc<Uint8>(bytes.length + 1);
    try {
      source.asTypedList(bytes.length).setAll(0, bytes);
      return _read(_preprocess(source.cast(), bytes.length, maxOutputBytes));
    } finally {
      calloc.free(source);
    }
  }

  Map<String, dynamic> _read(Pointer<Utf8> result) {
    if (result == nullptr) {
      throw const MermaidRenderFailure(
        message: 'Native SVG bridge returned no result',
      );
    }
    try {
      final value = jsonDecode(result.toDartString()) as Map<String, dynamic>;
      if (value['error'] case final String error) {
        throw MermaidRenderFailure(message: error);
      }
      return value;
    } finally {
      _free(result);
    }
  }
}
