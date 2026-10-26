import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'apple_workspace_service.dart';
import 'attachment_resolver.dart';

abstract class AttachmentSource {
  Future<List<AttachmentMetadata>> list(String root);
  Future<List<String>> normalize(List<String> paths);
  Future<Uint8List> read(String root, String relativePath, int maximumBytes);

  /// Import must never request provider downloads or materialize settings.
  Future<Uint8List> readImportSettings(String root);
}

/// Only the native adapter touches the filesystem. In particular, there is no
/// Dart File fallback which could follow a swapped symlink after validation.
class AppleAttachmentSource implements AttachmentSource {
  const AppleAttachmentSource({this.forBundle = false});
  final bool forBundle;

  @override
  Future<List<AttachmentMetadata>> list(String root) async {
    final result = await AppleWorkspaceService.channel
        .invokeListMethod<dynamic>(
          forBundle ? 'listBundleAssets' : 'listAttachments',
          {'path': root},
        );
    if (result == null) {
      throw const AttachmentFailure(AttachmentFailureKind.unavailable);
    }
    return [
      for (final value in result)
        AttachmentMetadata(
          relativePath: (value as Map)['relativePath'] as String,
          comparisonPath: value['comparisonPath'] as String,
          size: (value['size'] as num).toInt(),
          modified: (value['modified'] as num).toInt(),
          revision: value['revision'] as String?,
        ),
    ];
  }

  @override
  Future<List<String>> normalize(List<String> paths) async {
    final result = await AppleWorkspaceService.channel.invokeListMethod<String>(
      'normalizeAttachmentPaths',
      {'values': paths},
    );
    if (result == null || result.length != paths.length) {
      throw const AttachmentFailure(AttachmentFailureKind.unavailable);
    }
    return result;
  }

  @override
  Future<Uint8List> readImportSettings(String root) async {
    final result = await AppleWorkspaceService.channel.invokeMethod<Uint8List>(
      'readAttachmentImportSettings',
      {'path': root},
    );
    if (result == null) {
      throw const AttachmentFailure(AttachmentFailureKind.unavailable);
    }
    if (result.length > attachmentSettingsMaximumBytes) {
      throw const AttachmentFailure(AttachmentFailureKind.tooLarge);
    }
    return result;
  }

  @override
  Future<Uint8List> read(
    String root,
    String relativePath,
    int maximumBytes,
  ) async {
    final result = await AppleWorkspaceService.channel.invokeMethod<Uint8List>(
      forBundle ? 'readBundleAssetBytes' : 'readAttachmentBytes',
      {
        'path': root,
        'relativePath': relativePath,
        'maximumBytes': maximumBytes,
      },
    );
    if (result == null) {
      throw const AttachmentFailure(AttachmentFailureKind.unavailable);
    }
    if (result.length > maximumBytes) {
      throw const AttachmentFailure(AttachmentFailureKind.tooLarge);
    }
    return result;
  }
}

AttachmentFailure attachmentFailure(Object error) {
  if (error is AttachmentFailure) return error;
  if (error is PlatformException) {
    return AttachmentFailure(switch (error.code) {
      'attachment_missing' => AttachmentFailureKind.missing,
      'attachment_offline' => AttachmentFailureKind.offline,
      'attachment_denied' => AttachmentFailureKind.denied,
      'attachment_invalid' => AttachmentFailureKind.invalid,
      'attachment_too_large' => AttachmentFailureKind.tooLarge,
      'attachment_unsupported' => AttachmentFailureKind.unsupported,
      'attachment_index_limit' => AttachmentFailureKind.indexLimit,
      _ => AttachmentFailureKind.unavailable,
    });
  }
  return const AttachmentFailure(AttachmentFailureKind.unavailable);
}

class AttachmentImageLease {
  AttachmentImageLease._(this.image, this._release);
  final ui.Image image;
  VoidCallback? _release;
  void dispose() {
    _release?.call();
    _release = null;
  }
}

class _CachedImage {
  _CachedImage(this.image);
  final ui.Image image;
  int users = 0;
  bool retired = false;
  int get bytes => image.width * image.height * 4;
}

/// A single visible document's bounded cache. Encoded reads/decode are
/// serialized, decoded images have explicit leases, and old scope results are
/// discarded. We do not put private attachments into Flutter's global cache.
class AttachmentRepository extends ChangeNotifier {
  AttachmentRepository({
    required this.root,
    this.source = const AppleAttachmentSource(),
    this.maximumCacheBytes = 64 * 1024 * 1024,
    this.maximumDecodeWorkingBytes = 256 * 1024 * 1024,
  });

  final String? root;
  final AttachmentSource source;
  final int maximumCacheBytes;
  final int maximumDecodeWorkingBytes;
  static const maximumPixels = 32 * 1024 * 1024;
  static const maximumDecodedSide = 2048;
  final _cache = <String, _CachedImage>{};
  Future<AttachmentIndex>? _index;
  bool _indexPending = false;
  Future<void> _readTail = Future.value();
  ObsidianAttachmentSettings? settings;
  bool _disposed = false;
  int _generation = 0;
  int _cachedBytes = 0;

  int get generation => _generation;

  void refresh() {
    // Avoid overlapping native enumerations when a provider is slow. Scope
    // replacement still disposes immediately; a later timer/retry refreshes.
    if (_disposed || _indexPending) return;
    ++_generation;
    _index = null;
    notifyListeners();
  }

  void _check(int generation) {
    if (_disposed || generation != _generation) {
      throw const AttachmentFailure(AttachmentFailureKind.cancelled);
    }
  }

  Future<AttachmentIndex> _getIndex(int generation) {
    if (_index case final index?) return index;
    _indexPending = true;
    return _index = () async {
      try {
        final entries = await source.list(root!);
        _check(generation);
        // A broken/missing settings file never hides existing images. Read ONLY
        // app.json and retain ONLY attachmentFolderPath, never other preferences.
        try {
          final bytes = await source.read(
            root!,
            '.obsidian/app.json',
            attachmentSettingsMaximumBytes,
          );
          _check(generation);
          settings = ObsidianAttachmentSettings.parse(bytes);
        } on Object catch (error) {
          _check(generation);
          settings = ObsidianAttachmentSettings(
            malformed:
                attachmentFailure(error).kind != AttachmentFailureKind.missing,
          );
        }
        return AttachmentIndex(entries);
      } finally {
        _indexPending = false;
      }
    }();
  }

  Future<AttachmentImageLease> load({
    required String? documentPath,
    required String target,
    required AttachmentLinkKind kind,
  }) async {
    final generation = _generation;
    _check(generation);
    final reference = AttachmentReference(target, kind);
    final vault = root;
    if (vault == null ||
        documentPath == null ||
        !p.posix.isAbsolute(vault) ||
        !p.posix.isWithin(vault, documentPath)) {
      throw const AttachmentFailure(AttachmentFailureKind.needsFolder);
    }
    final document = p.posix.relative(documentPath, from: vault);
    final rawPath = reference.path;
    final candidate = rawPath.startsWith('/')
        ? rawPath.substring(1)
        : kind == AttachmentLinkKind.markdown ||
              rawPath.startsWith('./') ||
              rawPath.startsWith('../')
        ? p.posix.join(p.posix.dirname(document), rawPath)
        : rawPath;
    if (!isSafeAttachmentRelativePath(p.posix.normalize(candidate))) {
      throw const AttachmentFailure(AttachmentFailureKind.invalid);
    }
    try {
      final index = await _getIndex(generation);
      final normalized = await source.normalize([reference.path, document]);
      _check(generation);
      final metadata = index.resolve(
        reference: reference,
        documentRelativePath: document,
        normalizedReference: normalized[0],
        normalizedDocument: normalized[1],
      );
      if (metadata.size > attachmentMaximumBytes) {
        throw const AttachmentFailure(AttachmentFailureKind.tooLarge);
      }
      final done = Completer<AttachmentImageLease>();
      _readTail = _readTail.then((_) async {
        try {
          _check(generation);
          final key = metadata.version;
          var cached = _cache.remove(key);
          if (cached == null) {
            final bytes = await source.read(
              vault,
              metadata.relativePath,
              attachmentMaximumBytes,
            );
            _check(generation);
            if (bytes.length > attachmentMaximumBytes) {
              throw const AttachmentFailure(AttachmentFailureKind.tooLarge);
            }
            cached = _CachedImage(await _decode(bytes, generation));
            _cachedBytes += cached.bytes;
          }
          _cache[key] = cached;
          ++cached.users;
          final leased = cached;
          done.complete(
            AttachmentImageLease._(leased.image, () {
              --leased.users;
              if (leased.retired && leased.users == 0) leased.image.dispose();
            }),
          );
        } on Object catch (error) {
          done.completeError(attachmentFailure(error));
        }
      });
      return await done.future;
    } on Object catch (error) {
      throw attachmentFailure(error);
    }
  }

  /// Validates imported bytes with exactly the same format, actual codec and
  /// admission limits as preview. No filesystem or clipboard is accessed.
  Future<String> validateImport(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > attachmentMaximumBytes) {
      throw const AttachmentFailure(AttachmentFailureKind.tooLarge);
    }
    final extension = attachmentRasterExtension(bytes);
    if (extension == null) {
      throw const AttachmentFailure(AttachmentFailureKind.unsupported);
    }
    final image = await _decode(bytes, _generation);
    image.dispose();
    return extension;
  }

  Future<ui.Image> _decode(Uint8List bytes, int generation) async {
    // The engine can decode other formats (for example WBMP) despite an allowed
    // suffix. Require an allowed content signature before invoking any codec.
    if (attachmentRasterExtension(bytes) == null) {
      throw const AttachmentFailure(AttachmentFailureKind.unsupported);
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      _check(generation);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      _check(generation);
      if (descriptor.width <= 0 ||
          descriptor.height <= 0 ||
          descriptor.width * descriptor.height > maximumPixels) {
        throw const AttachmentFailure(AttachmentFailureKind.tooLarge);
      }
      final scale = math.min(
        1.0,
        maximumDecodedSide / math.max(descriptor.width, descriptor.height),
      );
      final width = math.max(1, (descriptor.width * scale).round());
      final height = math.max(1, (descriptor.height * scale).round());
      final targetBytes = width * height * 4;
      _makeRoom(targetBytes);
      // Reserve the input plus ImmutableBuffer copy, three source-sized decode/
      // staging copies, and output, not just a thumbnail. This is a conservative
      // admission budget, not a promise about total process RSS.
      final workingBytes =
          bytes.length * 2 +
          descriptor.width * descriptor.height * 4 * 3 +
          targetBytes;
      _makeRoom(workingBytes, budget: maximumDecodeWorkingBytes);
      codec = await descriptor.instantiateCodec(
        targetWidth: width,
        targetHeight: height,
      );
      // Flutter's multi-frame codec ignores targetWidth/targetHeight. Refuse
      // oversized animations BEFORE allocating their first full-size frame.
      if (codec.frameCount > 1 &&
          (descriptor.width > maximumDecodedSide ||
              descriptor.height > maximumDecodedSide)) {
        throw const AttachmentFailure(AttachmentFailureKind.tooLarge);
      }
      final frame = await codec.getNextFrame();
      try {
        _check(generation);
        final image = frame.image;
        if (image.width > maximumDecodedSide ||
            image.height > maximumDecodedSide) {
          throw const AttachmentFailure(AttachmentFailureKind.tooLarge);
        }
        // Reconcile using the real allocation even if a platform codec returns
        // a different size. A failed reconciliation must dispose the frame.
        _makeRoom(image.width * image.height * 4);
        return image;
      } on Object {
        frame.image.dispose();
        rethrow;
      }
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  void _makeRoom(int needed, {int? budget}) {
    final limit = budget ?? maximumCacheBytes;
    for (final key in _cache.keys.toList()) {
      if (_cachedBytes + needed <= limit) break;
      final cached = _cache[key]!;
      if (cached.users != 0) continue;
      _cache.remove(key);
      _cachedBytes -= cached.bytes;
      cached.image.dispose();
    }
    if (_cachedBytes + needed > limit) {
      throw const AttachmentFailure(AttachmentFailureKind.tooLarge);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    for (final cached in _cache.values) {
      cached.retired = true;
      if (cached.users == 0) cached.image.dispose();
    }
    _cache.clear();
    _cachedBytes = 0;
    super.dispose();
  }
}

// Signatures only admit a codec family. A successful real decode is still
// required, so a forged/truncated header does not count as a valid image.
String? attachmentRasterExtension(Uint8List bytes) {
  bool at(int offset, List<int> signature) {
    if (bytes.length < offset + signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) return false;
    }
    return true;
  }

  if (at(0, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return 'png';
  if (at(0, [0xff, 0xd8, 0xff])) return 'jpg';
  if (at(0, [0x47, 0x49, 0x46, 0x38, 0x37, 0x61]) ||
      at(0, [0x47, 0x49, 0x46, 0x38, 0x39, 0x61])) {
    return 'gif';
  }
  if (at(0, [0x52, 0x49, 0x46, 0x46]) && at(8, [0x57, 0x45, 0x42, 0x50])) {
    return 'webp';
  }
  if (at(0, [0x42, 0x4d])) return 'bmp';
  return null;
}
