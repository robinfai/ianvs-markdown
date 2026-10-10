import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:path/path.dart' as p;

import '../models/document_session.dart';
import 'file_browser_controller.dart';
import '../models/workspace_layout.dart';
import '../services/markdown_file_service.dart';
import '../services/workspace_session_store.dart';

class WorkspaceController extends ChangeNotifier {
  WorkspaceController({
    required this.fileService,
    required this.sessionStore,
    this.defaultWorkspaceDirectory,
  }) {
    browser = FileBrowserController(fileService)..addListener(_schedulePersist);
  }
  late final FileBrowserController browser;
  final _operationGrants = <String, String>{};
  final _favoriteAccessTokens = <String, String>{};
  final _dirtyStates = <String, bool>{};
  Future<void>? _fileOperationTail;

  @override
  void notifyListeners() {
    browser.configure(
      _workspaceRoot,
      _documents
          .map((d) => d.path)
          .whereType<String>()
          .where(
            (path) =>
                _workspaceRoot == null || !p.isWithin(_workspaceRoot!, path),
          )
          .toSet()
          .toList()
        ..sort(),
      activeDocument?.path,
    );
    super.notifyListeners();
  }

  final MarkdownFileService fileService;
  final WorkspaceSessionStore sessionStore;
  final Future<String> Function()? defaultWorkspaceDirectory;
  String? _cloudRoot;
  String? workspaceNotice;
  bool get isCloudWorkspace =>
      _workspaceRoot != null && _workspaceRoot == _cloudRoot;
  final List<DocumentSession> _documents = <DocumentSession>[];
  final Map<String, StreamSubscription<FileSystemEvent>> _watchers =
      <String, StreamSubscription<FileSystemEvent>>{};
  final Map<String, Future<bool>> _pendingSaves = <String, Future<bool>>{};
  Timer? _persistTimer;
  var _activeIndex = 0;
  var _nextDocumentId = 1;
  var _workspaceFilesRevision = 0;
  var _saveRevision = 0;
  var _initialized = false;
  String? _workspaceRoot;
  String? _workspaceAccessToken;
  bool _sidebarVisible = true;
  double _sidebarWidth = WorkspaceLayout.defaultSidebarWidth;
  bool _outlineVisible = true;

  List<DocumentSession> get documents => List.unmodifiable(_documents);
  DocumentSession? get activeDocument =>
      _documents.isEmpty ? null : _documents[_activeIndex];
  int get activeIndex => _activeIndex;
  String? get workspaceRoot => _workspaceRoot;
  int get workspaceFilesRevision => _workspaceFilesRevision;
  bool get sidebarVisible => _sidebarVisible;
  double get sidebarWidth => _sidebarWidth;
  bool get outlineVisible => _outlineVisible;
  bool get initialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;
    if (defaultWorkspaceDirectory != null) await _resolveDefaultWorkspace();
    try {
      final snapshot = await sessionStore.load();
      if (snapshot != null) {
        // Tree preferences do not select a root or restore security scopes.
        // Keep them available when a workspace is explicitly selected again.
        browser.restore(snapshot.browserState);
        for (final favorite
            in defaultWorkspaceDirectory == null
                ? snapshot.favoriteAccessTokens.entries
                : <MapEntry<String, String>>[]) {
          final path = await fileService.restorePersistentAccess(
            favorite.value,
          );
          if (path != null) {
            _favoriteAccessTokens[path] = favorite.value;
            if (path != favorite.key) browser.remap(favorite.key, path);
          }
        }
        for (final grant
            in defaultWorkspaceDirectory == null
                ? snapshot.operationGrants.entries
                : <MapEntry<String, String>>[]) {
          final restored = await fileService.restorePersistentAccess(
            grant.value,
          );
          if (restored != null) _operationGrants[restored] = grant.value;
        }
        if (defaultWorkspaceDirectory == null) {
          _workspaceRoot = snapshot.workspaceRoot;
          _workspaceAccessToken = snapshot.workspaceAccessToken;
        }
        if (_workspaceAccessToken case final token?) {
          _workspaceRoot =
              await fileService.restorePersistentAccess(token) ??
              _workspaceRoot;
        }
        _sidebarVisible = snapshot.sidebarVisible;
        _sidebarWidth = WorkspaceLayout.normalizeSidebarWidth(
          snapshot.sidebarWidth,
        );
        _outlineVisible = snapshot.outlineVisible;
        for (final documentJson in snapshot.documents) {
          final restored = DocumentSession.fromJson(documentJson);
          var path = restored.path;
          if (defaultWorkspaceDirectory != null &&
              path != null &&
              (_cloudRoot == null || !p.isWithin(_cloudRoot!, path))) {
            if (!restored.controller.isDirty) {
              restored.dispose();
              continue;
            }
            // Retain unsaved edits as drafts, without silently reopening an
            // external workspace or its previously granted security scope.
            restored.path = path = null;
            restored.accessToken = null;
          }
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

  Future<DocumentSession?> openPath(String path) =>
      _serializeFileOperation(() => _openPath(path));

  Future<DocumentSession?> _openPath(String path) async {
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
    workspaceNotice = null;
    notifyListeners();
    _schedulePersist();
  }

  Future<void> _resolveDefaultWorkspace() async {
    try {
      _cloudRoot = _workspaceRoot = await defaultWorkspaceDirectory!();
      _workspaceAccessToken = null;
      workspaceNotice = null;
    } on Object catch (error) {
      _workspaceRoot = null;
      workspaceNotice = error is PlatformException
          ? error.message
          : 'iCloud Drive 暂不可用。请检查 iCloud 设置，或手动选择文件夹。';
    }
  }

  Future<void> useDefaultWorkspace() async {
    if (defaultWorkspaceDirectory == null) return;
    await _resolveDefaultWorkspace();
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

  Future<bool> saveDocument(DocumentSession document, {bool saveAs = false}) {
    _saveRevision += 1;
    final savedText = document.controller.text;
    document.controller.commitHistoryGroup();
    final previousSave = _pendingSaves[document.id];
    late final Future<bool> saving;
    saving = () async {
      if (previousSave != null) {
        try {
          await previousSave;
        } on Object {
          // The previous caller receives its error; a later request can retry.
        }
      }
      try {
        return await _serializeFileOperation(
          () => _saveDocumentSnapshot(document, savedText, saveAs: saveAs),
        );
      } finally {
        if (identical(_pendingSaves[document.id], saving)) {
          _pendingSaves.remove(document.id);
        }
      }
    }();
    _pendingSaves[document.id] = saving;
    return saving;
  }

  Future<bool> _saveDocumentSnapshot(
    DocumentSession document,
    String savedText, {
    required bool saveAs,
  }) async {
    if (!_documents.contains(document)) return false;
    var path = saveAs ? null : document.path;
    path ??= await fileService.chooseSavePath(document.name);
    if (path == null) return false;
    final normalized = p.normalize(p.absolute(path));
    await fileService.writeMarkdownFileAtomic(normalized, savedText);
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
      ..lineEnding = _lineEndingOf(savedText)
      ..markSaved(savedText: savedText);
    if (previousPath == null || !p.equals(previousPath, normalized)) {
      await _unwatch(document.id);
      _watch(document);
    }
    if (_workspaceRoot case final root?) {
      if (p.isWithin(root, normalized)) _workspaceFilesRevision += 1;
    }
    notifyListeners();
    await browser.refresh(directories: [p.dirname(normalized)]);
    await _persistNow();
    return true;
  }

  Future<void> reloadFromDisk(DocumentSession document) async {
    final path = document.path;
    if (path == null) return;
    final file = await fileService.readMarkdownFile(path);
    document
      ..encoding = file.encoding
      ..lineEnding = file.lineEnding
      ..replaceFromDisk(file.contents, preserveHistory: true);
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
    _dirtyStates.remove(document.id);
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

  void setSidebarWidth(double width) {
    if (!width.isFinite) return;
    final normalized = WorkspaceLayout.normalizeSidebarWidth(width);
    if (_sidebarWidth == normalized) return;
    _sidebarWidth = normalized;
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

  Future<T> _serializeFileOperation<T>(Future<T> Function() action) {
    final previous = _fileOperationTail;
    final operation = previous == null
        ? action()
        : previous.then((_) => action());
    late final Future<void> tail;
    tail = operation
        .then<void>((_) {}, onError: (Object _, StackTrace _) {})
        .whenComplete(() {
          if (identical(_fileOperationTail, tail)) _fileOperationTail = null;
        });
    _fileOperationTail = tail;
    return operation;
  }

  bool canManage(String path) {
    final normalized = p.normalize(p.absolute(path));
    return [_workspaceRoot, ..._operationGrants.keys].whereType<String>().any(
      (root) => p.equals(root, normalized) || p.isWithin(root, normalized),
    );
  }

  Future<String?> chooseOperationFolder() async {
    final selected = await fileService.chooseWorkspaceFolder();
    if (selected == null) return null;
    final path = p.normalize(p.absolute(selected));
    final token = await fileService.createPersistentAccessToken(path);
    // Access is valid for this process even if a persistent bookmark is unavailable.
    _operationGrants[path] = token ?? '';
    _schedulePersist();
    return path;
  }

  Future<void> toggleFileFavorite(WorkspaceEntry entry) async {
    if (!browser.preferences.favorites.containsKey(entry.path) &&
        browser.isExternal(entry.path)) {
      final token = await fileService.createPersistentAccessToken(entry.path);
      if (token != null) _favoriteAccessTokens[entry.path] = token;
    }
    browser.toggleFavorite(entry);
  }

  Future<void> openFavorite(String path, {required bool directory}) async {
    if (!directory) {
      await openPath(path);
    } else if (browser.isExternal(path) &&
        !browser.rows.any((row) => row.entry?.path == path)) {
      _requireManaged(path);
      if (!await fileService.entryExists(path)) {
        throw StateError('Favorite folder is no longer available.');
      }
      _workspaceRoot = path;
      _workspaceAccessToken = await fileService.createPersistentAccessToken(
        path,
      );
      notifyListeners();
      await browser.load(path);
      _schedulePersist();
      return;
    }
    await browser.reveal(path);
    if (directory &&
        !browser.isExpanded(path, external: browser.isExternal(path))) {
      browser.toggle(path, external: browser.isExternal(path));
    }
  }

  void _requireManaged(String path) {
    if (!canManage(path)) {
      throw StateError(
        'Open the containing folder to grant access, then retry.',
      );
    }
  }

  static String validateEntryName(String name, {bool markdown = false}) {
    final value = name.trim();
    if (value.isEmpty ||
        value == '.' ||
        value == '..' ||
        value.contains('/') ||
        value.contains('\\') ||
        value.contains(':') ||
        value.contains(RegExp(r'[\x00-\x1f]'))) {
      throw const FormatException(
        'Enter a file name without path separators or control characters.',
      );
    }
    if (value.startsWith('.')) {
      throw const FormatException(
        'Hidden names are not shown in this workspace.',
      );
    }
    return markdown && p.extension(value).isEmpty ? '$value.md' : value;
  }

  Future<String> createFileEntry(
    String directory,
    String name, {
    bool folder = false,
  }) => _serializeFileOperation(() async {
    _requireManaged(directory);
    final path = p.join(directory, validateEntryName(name, markdown: !folder));
    if (!folder && !isMarkdownFileName(path)) {
      throw const FormatException('Use a Markdown or text extension.');
    }
    if (await fileService.entryExists(path)) {
      throw StateError('An item with this name already exists.');
    }
    await fileService.createEntry(path, directory: folder);
    await _afterFileOperation([directory]);
    return path;
  });

  List<DocumentSession> documentsWithin(Iterable<String> paths) => _documents
      .where(
        (document) =>
            document.path != null &&
            paths.any(
              (path) =>
                  p.equals(path, document.path!) ||
                  p.isWithin(path, document.path!),
            ),
      )
      .toList();

  Future<void> moveFileEntry(
    String source,
    String destination,
  ) => _serializeFileOperation(() async {
    source = p.normalize(p.absolute(source));
    destination = p.normalize(p.absolute(destination));
    _requireManaged(p.dirname(source));
    _requireManaged(p.dirname(destination));
    if (p.equals(source, _workspaceRoot ?? '') ||
        p.equals(source, destination) ||
        p.isWithin(source, destination)) {
      throw StateError(
        'Cannot move a workspace root or move an item into itself.',
      );
    }
    if (await fileService.entryExists(destination)) {
      throw StateError(
        'Destination already exists: ${p.basename(destination)}',
      );
    }
    final affected = documentsWithin([source]);
    await fileService.moveEntry(source, destination);
    // Disk success commits the new identity. Bookmark failure must never retain an old path.
    for (final document in affected) {
      if (!_documents.contains(document)) continue;
      final path = p.equals(document.path!, source)
          ? destination
          : p.join(destination, p.relative(document.path!, from: source));
      // Removing the subscription from the map invalidates in-flight reads
      // immediately; native cancellation does not block committing the new path.
      unawaited(_unwatch(document.id));
      document
        ..path = path
        ..name = p.basename(path)
        ..accessToken = null;
      try {
        document.accessToken = await fileService.createPersistentAccessToken(
          path,
        );
      } on Object {
        /* Current directory grant remains valid. */
      }
      _watch(document);
    }
    for (final old
        in _favoriteAccessTokens.keys
            .where((path) => path == source || p.isWithin(source, path))
            .toList()) {
      final path = old == source
          ? destination
          : p.join(destination, p.relative(old, from: source));
      _favoriteAccessTokens.remove(old);
      try {
        final token = await fileService.createPersistentAccessToken(path);
        if (token != null) _favoriteAccessTokens[path] = token;
      } on Object {
        /* Folder scope still grants current-session access. */
      }
    }
    browser.remap(source, destination);
    await _afterFileOperation([p.dirname(source), p.dirname(destination)]);
  });

  Future<String> duplicateFileEntry(
    String source,
  ) => _serializeFileOperation(() async {
    _requireManaged(p.dirname(source));
    final extension = p.extension(source);
    final base = p.withoutExtension(source);
    var destination = '$base copy$extension';
    var number = 2;
    while (await fileService.entryExists(destination)) {
      destination = '$base copy ${number++}$extension';
    }
    // Copy persisted bytes; never implicitly save the source's unsaved buffer.
    await fileService.copyEntry(source, destination);
    await _afterFileOperation([p.dirname(source)]);
    return destination;
  });

  Future<void> trashFileEntry(String path, {bool discardChanges = false}) =>
      _serializeFileOperation(() async {
        _requireManaged(p.dirname(path));
        if (p.equals(path, _workspaceRoot ?? '')) {
          throw StateError('Cannot trash the workspace root.');
        }
        final affected = documentsWithin([path]);
        if (!discardChanges && affected.any((d) => d.controller.isDirty)) {
          throw StateError('Save or discard changes before moving to Trash.');
        }
        final approvedText = {
          for (final document in affected)
            document.id: document.controller.text,
        };
        await fileService.trashEntry(path);
        for (final document in affected) {
          if (!_documents.contains(document)) continue;
          if (document.controller.text != approvedText[document.id]) {
            unawaited(_unwatch(document.id));
            document
              ..path = null
              ..accessToken = null
              ..hasExternalChanges = false;
          } else {
            removeDocument(document);
          }
        }
        _favoriteAccessTokens.removeWhere(
          (key, _) => key == path || p.isWithin(path, key),
        );
        browser.remap(path, null);
        await _afterFileOperation([p.dirname(path)]);
      });

  Future<void> _afterFileOperation(Iterable<String> directories) async {
    _workspaceFilesRevision++;
    notifyListeners();
    await browser.refresh(directories: directories);
    await _persistNow();
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
    _dirtyStates[document.id] = document.controller.isDirty;
    document.controller.addListener(_handleDocumentChanged);
    if (document.path != null) _watch(document);
  }

  void _handleDocumentChanged() {
    var dirtyChanged = false;
    for (final document in _documents) {
      final dirty = document.controller.isDirty;
      if (_dirtyStates[document.id] != dirty) {
        _dirtyStates[document.id] = dirty;
        dirtyChanged = true;
      }
    }
    if (dirtyChanged) notifyListeners();
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
              if (!p.equals(event.path, path)) return;
              unawaited(_checkForExternalChanges(document, path));
            },
            onError: (Object error, StackTrace stackTrace) {
              debugPrint('File watcher failed for $path: $error');
            },
          );
    } on Object catch (error) {
      debugPrint('Unable to watch $path: $error');
    }
  }

  Future<void> _checkForExternalChanges(
    DocumentSession document,
    String path,
  ) async {
    bool isWatching() =>
        _watchers.containsKey(document.id) &&
        document.path != null &&
        p.equals(document.path!, path);
    while (isWatching()) {
      final saveRevision = _saveRevision;
      final pendingSave = _pendingSaves[document.id];
      if (pendingSave != null) {
        try {
          // Compare only after markSaved has committed the written snapshot.
          await pendingSave;
        } on Object {
          // The save caller handles the error; disk may still have changed.
        }
      }
      if (!isWatching()) return;
      final persistedText = document.persistedText;
      var changed = true;
      try {
        final disk = await fileService.readMarkdownFile(path);
        changed = disk.contents != persistedText;
      } on Object catch (error) {
        // Deletion or an unreadable replacement also needs the existing banner.
        debugPrint('Unable to check watched file $path: $error');
      }
      if (!isWatching()) return;
      if (saveRevision != _saveRevision ||
          persistedText != document.persistedText) {
        // A newer save/reload invalidated the asynchronous read. Check again.
        continue;
      }
      if (browser.isExternal(path)) {
        unawaited(browser.refreshExternalMetadata());
      }
      if (changed && !document.hasExternalChanges) {
        document.hasExternalChanges = true;
        notifyListeners();
      }
      return;
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
      sidebarWidth: _sidebarWidth,
      outlineVisible: _outlineVisible,
      browserState: browser.toJson(),
      operationGrants: Map.of(_operationGrants),
      favoriteAccessTokens: Map.of(_favoriteAccessTokens),
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
    browser.removeListener(_schedulePersist);
    browser.dispose();
    for (final watcher in _watchers.values) {
      unawaited(watcher.cancel());
    }
    _watchers.clear();
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
# Welcome to Linefold

This is the full desktop app. It keeps your Markdown files at the center while
adding a workspace, tabs, outline navigation, crash recovery, and file watching.

## Open a workspace

Use the sidebar folder button or **⌘⇧O** to open a folder. Markdown files appear
in a lazy file tree and open in tabs.

## Edit without losing source

Click any rendered block to edit its exact Markdown. Switch between Live
Preview, Source, and Read from the mode control beneath the tabs or the **View** menu.

## Navigate documents

Use **⌘1–9** to select the first nine tabs from left to right. Shortcuts follow
the current tab order after dragging. Create a document with the tab-strip **+**
or **⌘N**; use the **File** menu to open or save files. Filter the workspace
tree with **Search Files**, and change appearance from the **View** menu.

- [ ] Open a folder
- [ ] Edit a document
- [ ] Save with ⌘S
''';
