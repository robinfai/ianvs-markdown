import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../services/markdown_file_service.dart';
import '../services/workspace_index_source.dart';
import 'preview_draft_store.dart';
import 'preview_library.dart';

enum PreviewConflictChoice { cancel, keepBoth, overwrite }

typedef PreviewConflictResolver =
    Future<PreviewConflictChoice> Function(MarkdownSaveConflict conflict);

/// Mobile editing is explicit and separate from preview refresh and desktop
/// sessions. A native write has no Dart timeout or cancel button: its outcome
/// must settle before another write, navigation or scope switch is allowed.
class PreviewEditorController extends ChangeNotifier {
  PreviewEditorController({required this.library, required this.store}) {
    source.addListener(_changed);
  }
  final PreviewLibrary library;
  final PreviewDraftStore store;
  final source = TextEditingController();
  String? path;
  String? root;
  int? generation;
  String _baseline = '';
  bool editing = false;
  bool busy = false;
  bool awaitingDecision = false;
  bool ready = false;
  bool _disposed = false;
  bool _settingSource = false;
  bool _storeHealthy = true;
  String? error;
  PreviewDraft? recovery;
  Future<void> _persistTail = Future.value();
  Timer? _persistTimer;

  bool get dirty => editing && source.text != _baseline;
  bool get canBegin => ready && !busy && !editing && library.canWrite;
  bool get current =>
      generation == library.workspaceGeneration &&
      root == library.workspace?.path;
  bool get canRecover =>
      ready &&
      !busy &&
      !editing &&
      recovery != null &&
      recovery!.root == library.workspace?.path &&
      library.canWrite;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    try {
      recovery = await store.load();
    } on Object {
      _storeHealthy = false;
      error = '无法读取恢复草稿；原恢复文件未改动。';
    } finally {
      ready = true;
      _notify();
    }
  }

  Future<bool> begin(String target, {bool restore = false}) async {
    if (!canBegin || (recovery != null && !restore)) {
      error = recovery == null ? '当前文件夹尚不可编辑。' : '请先恢复或丢弃已有草稿。';
      _notify();
      return false;
    }
    final selectedRoot = library.workspace!.path;
    final selectedGeneration = library.workspaceGeneration;
    if (!p.isWithin(selectedRoot, target)) return false;
    busy = true;
    error = null;
    _notify();
    try {
      final draft = restore ? recovery : null;
      if (restore &&
          (draft == null ||
              draft.path != target ||
              draft.root != selectedRoot)) {
        return false;
      }
      final baseline = draft?.baseline ?? await library.readSource(target);
      if (_disposed || selectedGeneration != library.workspaceGeneration) {
        return false;
      }
      path = target;
      root = selectedRoot;
      generation = selectedGeneration;
      _baseline = baseline;
      _settingSource = true;
      source.value = TextEditingValue(
        text: draft?.text ?? baseline,
        selection: const TextSelection.collapsed(offset: 0),
      );
      _settingSource = false;
      editing = true;
      if (draft?.notice != null) error = '已从备用草稿恢复，最近的修改可能缺失；保存前请检查。';
      return true;
    } on Object {
      error = '无法开始编辑，请检查文件权限或网络。';
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  void _changed() {
    if (_settingSource || !editing || _disposed) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(flushDraft()),
    );
    _notify();
  }

  PreviewDraft? get _draft => !editing
      ? recovery
      : dirty
      ? PreviewDraft(
          root: root!,
          path: path!,
          text: source.text,
          baseline: _baseline,
        )
      : null;

  /// The immutable snapshot is captured now, not when the queued write begins.
  Future<bool> _persist(PreviewDraft? draft) async {
    var ok = false;
    final next = _persistTail.then((_) async {
      try {
        if (!_storeHealthy) throw StateError('Recovery was not loaded safely');
        await store.save(draft);
        recovery = draft;
        ok = true;
      } on Object {
        error = '草稿尚未安全保存到本机，请保持此页打开。原文件未因此改动。';
        _notify();
      }
    });
    _persistTail = next;
    await next;
    return ok;
  }

  Future<bool> flushDraft() {
    // A lifecycle event can arrive before asynchronous recovery loading. It must
    // never clear a draft that has not been read yet.
    if (!ready) return Future.value(false);
    _persistTimer?.cancel();
    return _persist(_draft);
  }

  Future<bool> discard() async {
    if (busy) return false;
    busy = true;
    _notify();
    _persistTimer?.cancel();
    try {
      if (!await _persist(null)) return false;
      editing = false;
      path = null;
      root = null;
      generation = null;
      error = null;
      return true;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<String?> create(String name) async {
    if (!canBegin || recovery != null) return null;
    var relative = name.trim();
    if (!relative.toLowerCase().endsWith('.md')) relative += '.md';
    if (!safeWorkspaceRelativePath(relative) ||
        relative.contains('/') ||
        relative == '.md' ||
        relative.length > 200) {
      error = '请输入不含路径分隔符的文件名。';
      _notify();
      return null;
    }
    final selectedGeneration = library.workspaceGeneration;
    busy = true;
    error = null;
    _notify();
    try {
      final target = await library.createNote(
        relative,
        generation: selectedGeneration,
      );
      if (_disposed || selectedGeneration != library.workspaceGeneration) {
        return null;
      }
      return target;
    } on Object {
      error = '未能确认新建成功，文件可能已存在或已创建；请刷新检查，不会覆盖。';
      return null;
    } finally {
      busy = false;
      _notify();
    }
  }

  /// Explicitly recover text into a new note when the old scope is unavailable
  /// (including a changed app container path). This does not restore that grant,
  /// move attachments, or touch the original file.
  Future<bool> recoverToNewNote() async {
    final draft = recovery;
    if (!canBegin || draft == null) return false;
    final selectedRoot = library.workspace!.path;
    final selectedGeneration = library.workspaceGeneration;
    busy = true;
    error = null;
    _notify();
    try {
      final target = await library.createNote(
        'Recovered ${DateTime.now().microsecondsSinceEpoch}.md',
        generation: selectedGeneration,
      );
      if (_disposed || selectedGeneration != library.workspaceGeneration) {
        return false;
      }
      path = target;
      root = selectedRoot;
      generation = selectedGeneration;
      _baseline = '';
      _settingSource = true;
      source.value = TextEditingValue(
        text: draft.text,
        selection: const TextSelection.collapsed(offset: 0),
      );
      _settingSource = false;
      editing = true;
      await flushDraft();
      return true;
    } on Object {
      error = '恢复副本未确认创建成功。原草稿仍保留，请刷新检查；不会改动原文件。';
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<bool> save(PreviewConflictResolver resolve) async {
    if (!editing || busy || !current) {
      error = '文件夹权限已改变；草稿仍保留，请重新选择原文件夹。';
      _notify();
      return false;
    }
    busy = true;
    error = null;
    _persistTimer?.cancel();
    _notify();
    final text = source.text;
    var target = path!;
    String? expected = _baseline;
    try {
      // Recovery is separate from the original file save. Failure keeps the
      // visible buffer and never changes the expected source version.
      await flushDraft();
      while (true) {
        if (_disposed || !current) return false;
        try {
          await library.writeSource(
            target,
            text,
            expectedContents: expected,
            generation: generation!,
          );
          break;
        } on MarkdownSaveConflict catch (conflict) {
          if (_disposed || !current) return false;
          awaitingDecision = true;
          _notify();
          final PreviewConflictChoice choice;
          try {
            choice = await resolve(conflict);
          } finally {
            awaitingDecision = false;
            _notify();
          }
          if (_disposed || !current || choice == PreviewConflictChoice.cancel) {
            return false;
          }
          if (choice == PreviewConflictChoice.overwrite) {
            // Approval is for the exact observed bytes. A third version causes
            // another conflict prompt; there is no unconditional overwrite API.
            expected = conflict.currentContents;
          } else {
            final relative = p.relative(target, from: root!);
            final suffix = DateTime.now().microsecondsSinceEpoch;
            final copy = '${p.withoutExtension(relative)} local $suffix.md';
            target = await library.createNote(copy, generation: generation!);
            expected = '';
          }
        }
      }
      if (_disposed || !current) return false;
      path = target;
      _baseline = text;
      // If recovery cleanup fails, still report original-file success accurately
      // but keep this editor open so a stale recovery copy is not hidden.
      if (source.text != text) {
        await flushDraft();
        return true;
      }
      if (!await _persist(null)) {
        error = '笔记已保存，但本机恢复草稿清理失败；请保持此页打开并重试。';
        return true;
      }
      // Clearing recovery is asynchronous too. A late IME update may arrive
      // after the first comparison but before cleanup settles. Never hide it or
      // leave the just-cleared store as the final snapshot.
      if (_disposed) return true;
      if (source.text != text) {
        await flushDraft();
        return true;
      }
      editing = false;
      return true;
    } on Object {
      error =
          '保存 ${p.basename(target)} 未确认成功。草稿仍保留；请检查权限或网络。若创建过副本，请刷新检查，不会自动覆盖。';
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    // Capture the buffer while its controller is alive. Awaited lifecycle
    // flushes remain the normal durability boundary; disposal is best effort.
    if (ready && editing) unawaited(flushDraft());
    _disposed = true;
    _persistTimer?.cancel();
    source.removeListener(_changed);
    source.dispose();
    super.dispose();
  }
}
