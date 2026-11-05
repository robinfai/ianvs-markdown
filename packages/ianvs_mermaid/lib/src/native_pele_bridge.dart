import 'dart:convert';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'mermaid_exception.dart';

const _asset = 'package:ianvs_mermaid/src/native_pele_bridge.dart';
@Native<Pointer<Void> Function()>(
  symbol: 'ianvs_pele_allocate',
  assetId: _asset,
)
external Pointer<Void> _allocate();
@Native<Void Function(Pointer<Void>)>(
  symbol: 'ianvs_pele_retain',
  assetId: _asset,
)
external void _retain(Pointer<Void> pointer);
@Native<Void Function(Pointer<Void>)>(
  symbol: 'ianvs_pele_release',
  assetId: _asset,
)
external void _release(Pointer<Void> pointer);
@Native<Void Function(Pointer<Void>, Int64)>(
  symbol: 'ianvs_pele_cancel',
  assetId: _asset,
)
external void _cancel(Pointer<Void> pointer, int through);
@Native<Void Function(Pointer<Void>)>(
  symbol: 'ianvs_pele_close',
  assetId: _asset,
)
external void _close(Pointer<Void> pointer);
@Native<
  Pointer<Utf8> Function(
    Pointer<Void>,
    Pointer<Utf8>,
    Int64,
    Double,
    Pointer<Int32>,
  )
>(symbol: 'ianvs_pele_evaluate', assetId: _asset)
external Pointer<Utf8> _evaluate(
  Pointer<Void> engine,
  Pointer<Utf8> script,
  int request,
  double seconds,
  Pointer<Int32> status,
);
@Native<Void Function(Pointer<Utf8>)>(
  symbol: 'ianvs_pele_free',
  assetId: _asset,
)
external void _free(Pointer<Utf8> result);

/// Atomics may be called by the owner isolate; JSC operations only by its worker.
class NativePeleBridge {
  NativePeleBridge.allocate() : address = _allocate().address {
    if (address == 0) throw StateError('Cannot allocate Pele engine');
  }
  NativePeleBridge.at(this.address);
  final int address;
  bool _loaded = false;
  int _renders = 0;
  Pointer<Void> get _pointer => Pointer.fromAddress(address);
  void retain() => _retain(_pointer);
  void release() => _release(_pointer);
  void cancelThrough(int id) => _cancel(_pointer, id);
  void close() {
    _close(_pointer);
    _loaded = false;
    _renders = 0;
  }

  String evaluate(String script, int request, double seconds) {
    final input = script.toNativeUtf8();
    final status = calloc<Int32>();
    Pointer<Utf8> output = nullptr;
    try {
      output = _evaluate(_pointer, input, request, seconds, status);
      if (output == nullptr) throw StateError('Pele returned no result');
      final value = output.toDartString();
      if (status.value != 0) {
        if (status.value >= 2) _loaded = false;
        throw MermaidRenderFailure(message: value);
      }
      return value;
    } finally {
      if (output != nullptr) _free(output);
      calloc.free(status);
      calloc.free(input);
    }
  }

  Map<String, dynamic> run(
    String runtime,
    String source,
    Map<String, Object?> options,
    int request, {
    bool parseOnly = false,
    double seconds = 5,
  }) {
    // Periodically release JS heap and all engine caches, not just Dart results.
    if (_renders >= 64) close();
    if (!_loaded) {
      evaluate(runtime, request, seconds);
      _loaded = true;
    }
    // Failed parses also allocate; count attempts so repeated invalid input
    // cannot bypass periodic context recycling.
    _renders++;
    final result = evaluate(
      'JSON.stringify(Pele.${parseOnly ? 'parse' : 'render'}(${jsonEncode(source)},${jsonEncode(options)}))',
      request,
      seconds,
    );
    return jsonDecode(result) as Map<String, dynamic>;
  }
}
