import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:path/path.dart' as p;

import '../models/document_session.dart';
import '../services/markdown_file_service.dart';
import '../services/workspace_session_store.dart';

class WorkspaceController extends ChangeNotifier {
  WorkspaceController({required this.fileService, required this.sessionStore});

  final MarkdownFileService fileService;
  final WorkspaceSessionStore sessionStore;
  final List<DocumentSession> _documents = <DocumentSession>[];
  final Map<String, StreamSubscription<FileSystemEvent>> _watchers =
      <String, StreamSubscription<FileSystemEvent>>{};
  final Set<String> _savingPaths = <String>{};
  Timer? _persistTimer;
  var _activeIndex = 0;
  var _nextDocumentId = 1;
  var _initialized = false;
  String? _workspaceRoot;
  String? _workspaceAccessToken;
  bool _sidebarVisible = true;
  bool _outlineVisible = true;

  List<DocumentSession> get documents => List.unmodifiable(_documents);
  DocumentSession? get activeDocument =>
      _documents.isEmpty ? null : _documents[_activeIndex];
  int get activeIndex => _activeIndex;
  String? get workspaceRoot => _workspaceRoot;
  bool get sidebarVisible => _sidebarVisible;
  bool get outlineVisible => _outlineVisible;
  bool get initialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final snapshot = await sessionStore.load();
      if (snapshot != null) {
        _workspaceRoot = snapshot.workspaceRoot;
        _workspaceAccessToken = snapshot.workspaceAccessToken;
        if (_workspaceAccessToken case final token?) {
          _workspaceRoot =
              await fileService.restorePersistentAccess(token) ??
              _workspaceRoot;
        }
        _sidebarVisible = snapshot.sidebarVisible;
        _outlineVisible = snapshot.outlineVisible;
        for (final documentJson in snapshot.documents) {
          final restored = DocumentSession.fromJson(documentJson);
          var path = restored.path;
          if (restored.accessToken case final token?) {
            path = await fileService.restorePersistentAccess(token) ?? path;
            restored.path = path;
          }
          if (restored.id.isEmpty) {
            restored.dispose();
            continue;
          }
          final fileAvailable = path == null || fileService.fileExists(path);
          if (!fileAvailable) {
            if (!restored.controller.isDirty) {
              restored.dispose();
              continue;
            }
            restored.hasExternalChanges = true;
          }
          if (path != null && fileAvailable) {
            try {
              final disk = await fileService.readMarkdownFile(path);
              if (restored.controller.isDirty) {
                restored.hasExternalChanges =
                    disk.contents != restored.persistedText;
              } else {
                restored
                  ..encoding = disk.encoding
                  ..lineEnding = disk.lineEnding
                  ..replaceFromDisk(disk.contents);
              }
            } on Object catch (error) {
              debugPrint('Unable to refresh $path while restoring: $error');
              restored.hasExternalChanges = true;
            }
          }
          _nextDocumentId = _nextIdAfter(restored.id, _nextDocumentId);
          _attach(restored);
          _documents.add(restored);
          if (restored.id == snapshot.activeDocumentId) {
            _activeIndex = _documents.length - 1;
          }
        }
      }
    } on Object catch (error, stackTrace) {
      debugPrint('Unable to restore workspace: $error\n$stackTrace');
    }
    if (_documents.isEmpty) {
      _documents.add(
        _createDocument(
          name: 'Welcome.md',
          text: welcomeMarkdown,
          persistedText: welcomeMarkdown,
        ),
      );
    }
    _initialized = true;
    notifyListeners();
    _schedulePersist();
  }

  DocumentSession newDocument() {
    final document = _createDocument(
      name: 'Untitled-$_nextDocumentId.md',
      text: '',
    );
    _documents.add(document);
    _activeIndex = _documents.length - 1;
    notifyListeners();
    _schedulePersist();
    return document;
  }

  Future<void> chooseAndOpenFiles() async {
    final paths = await fileService.chooseMarkdownFiles();
    await openPaths(paths);
  }

  Future<void> openPaths(Iterable<String> paths) async {
    for (final path in paths) {
      if (isMarkdownFileName(path)) await openPath(path);
    }
  }

  Future<DocumentSession?> openPath(String path) async {
    final normalized = p.normalize(p.absolute(path));
    final existingIndex = _documents.indexWhere(
      (document) =>
          document.path != null && p.equals(document.path!, normalized),
    );
    if (existingIndex >= 0) {
      selectDocument(existingIndex);
      return _documents[existingIndex];
    }
    final file = await fileService.readMarkdownFile(normalized);
    final document = _createDocument(
      name: file.name,
      path: normalized,
      accessToken: await fileService.createPersistentAccessToken(normalized),
      text: file.contents,
      persistedText: file.contents,
      encoding: file.encoding,
      lineEnding: file.lineEnding,
    );
    _documents.add(document);
    _activeIndex = _documents.length - 1;
    _watch(document);
    notifyListeners();
    _schedulePersist();
    return document;
  }

  Future<void> chooseWorkspaceFolder() async {
    final root = await fileService.chooseWorkspaceFolder();
    if (root == null) return;
    _workspaceRoot = p.normalize(p.absolute(root));
    _workspaceAccessToken = await fileService.createPersistentAccessToken(
      _workspaceRoot!,
    );
    _sidebarVisible = true;
    notifyListeners();
    _schedulePersist();
  }

  void selectDocument(int index) {
    if (index < 0 || index >= _documents.length || index == _activeIndex) {
      return;
    }
    _activeIndex = index;
    notifyListeners();
    _schedulePersist();
  }

  void reorderDocument(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _documents.length) return;
    newIndex = newIndex.clamp(0, _documents.length - 1);
    if (newIndex == oldIndex) return;
    final active = activeDocument;
    final document = _documents.removeAt(oldIndex);
    _documents.insert(newIndex, document);
    _activeIndex = active == null ? 0 : _documents.indexOf(active);
    notifyListeners();
    _schedulePersist();
  }

  Future<bool> saveActive({bool saveAs = false}) async {
    final document = activeDocument;
    if (document == null) return false;
    return saveDocument(document, saveAs: saveAs);
  }

  Future<bool> saveDocument(
    DocumentSession document, {
    bool saveAs = false,
  }) async {
    var path = saveAs ? null : document.path;
    path ??= await fileService.chooseSavePath(document.name);
    if (path == null) return false;
    final normalized = p.normalize(p.absolute(path));
    _savingPaths.add(normalized);
    try {
      await fileService.writeMarkdownFileAtomic(
        normalized,
        document.controller.text,
      );
      final previousPath = document.path;
      final needsAccessToken =
          document.accessToken == null ||
          previousPath == null ||
          !p.equals(previousPath, normalized);
      final accessToken = needsAccessToken
          ? await fileService.createPersistentAccessToken(normalized)
          : document.accessToken;
      document
        ..path = normalized
        ..accessToken = accessToken ?? document.accessToken
        ..name = p.basename(normalized)
        ..encoding = 'UTF-8'
        ..lineEnding = _lineEndingOf(document.controller.text)
        ..markSaved();
      if (previousPath == null || !p.equals(previousPath, normalized)) {
        await _unwatch(document.id);
        _watch(document);
      }
      notifyListeners();
      await _persistNow();
      return true;
    } finally {
      Timer(const Duration(milliseconds: 600), () {
        _savingPaths.remove(normalized);
      });
    }
  }

  Future<void> reloadFromDisk(DocumentSession document) async {
    final path = document.path;
    if (path == null) return;
    final file = await fileService.readMarkdownFile(path);
    document
      ..encoding = file.encoding
      ..lineEnding = file.lineEnding
      ..replaceFromDisk(file.contents);
    notifyListeners();
    _schedulePersist();
  }

  void keepLocalVersion(DocumentSession document) {
    document.hasExternalChanges = false;
    notifyListeners();
  }

  void removeDocument(DocumentSession document) {
    final index = _documents.indexOf(document);
    if (index < 0) return;
    _documents.removeAt(index);
    _unwatch(document.id);
    document.controller.removeListener(_handleDocumentChanged);
    document.dispose();
    if (_documents.isEmpty) {
      _documents.add(
        _createDocument(name: 'Untitled-$_nextDocumentId.md', text: ''),
      );
      _activeIndex = 0;
    } else if (_activeIndex > index) {
      _activeIndex -= 1;
    } else if (_activeIndex >= _documents.length) {
      _activeIndex = _documents.length - 1;
    }
    notifyListeners();
    _schedulePersist();
  }

  void toggleSidebar() {
    _sidebarVisible = !_sidebarVisible;
    notifyListeners();
    _schedulePersist();
  }

  void toggleOutline() {
    _outlineVisible = !_outlineVisible;
    notifyListeners();
    _schedulePersist();
  }

  void setMode(IanvsMarkdownEditorMode mode) {
    final document = activeDocument;
    if (document == null) return;
    document.controller.mode = mode;
    _schedulePersist();
  }

  DocumentSession _createDocument({
    required String name,
    required String text,
    String? path,
    String? accessToken,
    String? persistedText,
    String encoding = 'UTF-8',
    String lineEnding = 'LF',
  }) {
    final document = DocumentSession(
      id: 'document-${_nextDocumentId++}',
      name: name,
      path: path,
      accessToken: accessToken,
      text: text,
      persistedText: persistedText,
      encoding: encoding,
      lineEnding: lineEnding,
    );
    _attach(document);
    return document;
  }

  void _attach(DocumentSession document) {
    document.controller.addListener(_handleDocumentChanged);
    if (document.path != null) _watch(document);
  }

  void _handleDocumentChanged() {
    _schedulePersist();
  }

  void _watch(DocumentSession document) {
    final path = document.path;
    if (path == null || _watchers.containsKey(document.id)) return;
    try {
      final directory = p.dirname(path);
      _watchers[document.id] = fileService
          .watchDirectory(directory)
          .listen(
            (event) {
              if (_savingPaths.contains(path) || !p.equals(event.path, path)) {
                return;
              }
              document.hasExternalChanges = true;
              notifyListeners();
            },
            onError: (Object error, StackTrace stackTrace) {
              debugPrint('File watcher failed for $path: $error');
            },
          );
    } on Object catch (error) {
      debugPrint('Unable to watch $path: $error');
    }
  }

  Future<void> _unwatch(String documentId) async {
    await _watchers.remove(documentId)?.cancel();
  }

  void _schedulePersist() {
    if (!_initialized) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_persistNow()),
    );
  }

  Future<void> _persistNow() async {
    if (!_initialized) return;
    final active = activeDocument;
    final snapshot = WorkspaceSnapshot(
      documents: _documents
          .map((document) => document.toJson())
          .toList(growable: false),
      activeDocumentId: active?.id,
      workspaceRoot: _workspaceRoot,
      workspaceAccessToken: _workspaceAccessToken,
      sidebarVisible: _sidebarVisible,
      outlineVisible: _outlineVisible,
    );
    try {
      await sessionStore.save(snapshot);
    } on Object catch (error, stackTrace) {
      debugPrint('Unable to persist workspace: $error\n$stackTrace');
    }
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    for (final watcher in _watchers.values) {
      unawaited(watcher.cancel());
    }
    for (final document in _documents) {
      document.controller.removeListener(_handleDocumentChanged);
      document.dispose();
    }
    super.dispose();
  }
}

int _nextIdAfter(String id, int fallback) {
  final value = int.tryParse(id.split('-').last);
  if (value == null) return fallback;
  return value >= fallback ? value + 1 : fallback;
}

String _lineEndingOf(String text) => text.contains('\r\n') ? 'CRLF' : 'LF';

const welcomeMarkdown = '''
# Welcome to Ianvs Markdown

This is the full desktop app. It keeps your Markdown files at the center while
adding a workspace, tabs, outline navigation, crash recovery, and file watching.

## Open a workspace

Use the sidebar folder button or **⌘⇧O** to open a folder. Markdown files appear
in a lazy file tree and open in tabs.

## Edit without losing source

Click any rendered block to edit its exact Markdown. Switch between Live
Preview, Source, and Read from the centered toolbar control or the **View** menu.

## Navigate documents

Use **⌘1–9** to select the first nine tabs from left to right. Shortcuts follow
the current tab order after dragging. Create a document with the tab-strip **+**
or **⌘N**; use the **File** menu to open or save files. Filter the workspace
tree with **Search Files**, and change appearance from the **View** menu.

- [ ] Open a folder
- [ ] Edit a document
- [ ] Save with ⌘S
''';
