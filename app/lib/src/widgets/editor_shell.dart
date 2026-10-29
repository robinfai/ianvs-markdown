import '../reading_typography.dart';
import 'save_conflict_diff_dialog.dart';
import '../services/rich_paste_service.dart';
import 'document_sync_indicator.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_markdown_clipboard/ianvs_markdown_clipboard.dart';
import 'package:ianvs_mermaid/ianvs_mermaid.dart';
import 'package:path/path.dart' as p;

import '../controllers/workspace_controller.dart';
import '../controllers/document_find_controller.dart';
import '../controllers/workspace_search_controller.dart';
import 'workspace_search_dialog.dart';
import 'workspace_references_panel.dart';
import '../editor_commands.dart';
import '../editor_input_target.dart';
import '../models/document_session.dart';
import '../models/workspace_layout.dart';
import '../services/document_link_service.dart';
import '../services/wiki_note_resolver.dart';
import '../services/wiki_link_insertion.dart';
import 'wiki_note_picker.dart';
import 'workspace_palette.dart';
import 'note_template_dialog.dart';
import 'reference_dock.dart';
import 'note_link_preview.dart';
import '../services/note_templates.dart';
import '../services/slash_insertion.dart';
import '../services/attachment_repository.dart';
import '../services/attachment_import_service.dart';
import '../services/attachment_resolver.dart';
import 'document_attachment_scope.dart';
import '../services/markdown_file_service.dart';
import 'local_document_image.dart';
import 'document_diagram.dart';
import 'document_find_bar.dart';
import '../desktop_theme.dart';
import '../desktop_typography.dart';
import 'floating_outline.dart';
import 'desktop_menu_bar.dart';
import 'document_export_dialog.dart';
import '../services/document_export_service.dart';
import '../app_icons.dart';
import '../tab_shortcuts.dart';
import 'title_tabs_bar.dart';
import 'workspace_sidebar.dart';
import 'sidebar_resize_handle.dart';

class EditorShell extends StatefulWidget {
  const EditorShell({
    super.key,
    required this.workspace,
    required this.dark,
    required this.onToggleTheme,
    this.onUseSystemTheme,
    this.onOpenSettings,
    this.enableFileDrop = true,
    this.onRetryInitialization,
    this.attachmentSource = const AppleAttachmentSource(),
    this.attachmentImportPlatform = const AppleAttachmentImportPlatform(),
    this.readClipboardText = readIanvsMarkdownClipboardText,
  });

  final Future<IanvsMarkdownClipboardText?> Function() readClipboardText;
  final WorkspaceController workspace;
  final AttachmentSource attachmentSource;
  final AttachmentImportPlatform attachmentImportPlatform;
  final bool dark;
  final VoidCallback onToggleTheme;
  final VoidCallback? onUseSystemTheme;
  final VoidCallback? onOpenSettings;
  final bool enableFileDrop;
  final Future<void> Function()? onRetryInitialization;

  @override
  State<EditorShell> createState() => _EditorShellState();
}

class _EditorShellState extends State<EditorShell> {
  var _draggingFiles = false;
  final _documentExport = DocumentExportFlow();
  final _mermaidRenderer = NativeMermanRenderer();
  final _editorFocus = FocusNode();
  final _findFocus = FocusNode();
  final _shellFocus = FocusNode();
  late final DocumentInputTarget _documentInputTarget;
  DocumentFindController? _find;
  String _lastFindQuery = '';
  String _lastReplacement = '';
  bool _lastMatchCase = false;
  bool _enablingFindEditing = false;
  double? _beforeFindScroll;
  bool _beforeFindFocused = false;
  IanvsMarkdownController? _resumeLiveController;
  int _findSurfaceEpoch = 0;
  int _wikiGeneration = 0;
  int _attachmentGeneration = 0;
  int _attachmentRevision = 0;
  bool _attachmentPending = false;
  String? _attachmentRoot;
  final _retainedImports =
      <(String root, String documentPath, ImportedAttachment image)>[];
  String? _wikiActiveDocumentId;

  @override
  void initState() {
    super.initState();
    _documentInputTarget = DocumentInputTarget(
      mainFocus: _editorFocus,
      document: () => widget.workspace.activeDocument?.controller,
      onLocalTarget: () {
        ++_wikiGeneration;
        ++_attachmentGeneration;
      },
    );
    _wikiActiveDocumentId = widget.workspace.activeDocument?.id;
    _attachmentRoot = widget.workspace.workspaceRoot;
    widget.workspace.addListener(_workspaceChanged);
    _bindSlashController();
    _referencesVisible = widget.workspace.referenceView['visible'] == true;
  }

  @override
  void didUpdateWidget(covariant EditorShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.workspace, widget.workspace)) {
      ++_attachmentGeneration;
      oldWidget.workspace.removeListener(_workspaceChanged);
      _documentInputTarget.reset();
      ++_wikiGeneration;
      _wikiActiveDocumentId = widget.workspace.activeDocument?.id;
      widget.workspace.addListener(_workspaceChanged);
      _bindSlashController();
      _closeFind(restoreFocus: false, restoreScroll: false);
    }
  }

  void _workspaceChanged() {
    _bindSlashController();
    if ((!_referenceRestoreDone && widget.workspace.initialized) ||
        _attachmentRoot != widget.workspace.workspaceRoot) {
      _referenceRestoreDone = true;
      _referencesVisible = widget.workspace.referenceView['visible'] == true;
    }
    if (_attachmentRoot != widget.workspace.workspaceRoot) {
      _attachmentRoot = widget.workspace.workspaceRoot;
      ++_attachmentGeneration;
    }
    if (_wikiActiveDocumentId != widget.workspace.activeDocument?.id) {
      _wikiActiveDocumentId = widget.workspace.activeDocument?.id;
      ++_wikiGeneration;
      ++_attachmentGeneration;
      _documentInputTarget.reset();
    }
    if (!identical(
      _resumeLiveController,
      widget.workspace.activeDocument?.controller,
    )) {
      _resumeLiveController = null;
    }
    final find = _find;
    if (find != null &&
        !identical(
          find.document,
          widget.workspace.activeDocument?.controller,
        )) {
      _closeFind(restoreFocus: false, restoreScroll: false);
    }
  }

  void _findChanged() {
    if (mounted) setState(() {});
  }

  void _findModeChanged() {
    if (!_enablingFindEditing) _closeFind(restoreScroll: false);
  }

  void _openFind({
    bool seedSelection = true,
    bool? navigateBackwards,
    int? sourceAnchor,
    String? expectedSource,
  }) {
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final document = widget.workspace.activeDocument;
    if (document == null || hasEditorComposition(widget.workspace)) return;
    if (_find != null) {
      if (_find!.isComposing) return;
      _findFocus.requestFocus();
      _find!.query.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _find!.query.text.length,
      );
      return;
    }
    final controller = document.controller;
    _findSurfaceEpoch += 1;
    final selection = controller.selection;
    final selected = selection.isValid && !selection.isCollapsed
        ? selection.textInside(controller.text)
        : '';
    _beforeFindScroll = document.scrollController.hasClients
        ? document.scrollController.offset
        : null;
    _beforeFindFocused = _editorFocus.hasFocus;
    _editorFocus.unfocus();
    final find = DocumentFindController(
      document: controller,
      scope:
          controller.mode != IanvsMarkdownEditorMode.source &&
              sourceAnchor == null
          ? DocumentFindScope.body
          : DocumentFindScope.source,
      query:
          seedSelection &&
              selected.isNotEmpty &&
              selected.length <= 2000 &&
              !selected.contains('\n')
          ? selected
          : _lastFindQuery,
      replacement: _lastReplacement,
      matchCase: _lastMatchCase,
      readOnly: controller.mode == IanvsMarkdownEditorMode.preview,
      revealInitialMatch: false,
    );
    find.query.selection = TextSelection(
      baseOffset: 0,
      extentOffset: find.query.text.length,
    );
    find.addListener(_findChanged);
    controller.modeListenable.addListener(_findModeChanged);
    setState(() => _find = find);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_find, find)) return;
      _restoreDocumentScroll(document, _beforeFindScroll);
      // The old Live editor must be detached before moving the shared source
      // selection: it otherwise redirects matches inside hidden front matter.
      if (sourceAnchor != null && controller.text == expectedSource) {
        controller.selection = TextSelection.collapsed(offset: sourceAnchor);
      }
      find.next(
        backwards: navigateBackwards ?? false,
        skipCurrentSelection: navigateBackwards == false,
      );
      _findFocus.requestFocus();
    });
  }

  Future<void> _handleFileDrop(List<DropItem> files) async {
    if (!(ModalRoute.of(context)?.isCurrent ?? true) || files.isEmpty) return;
    const imageExtensions = {
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.bmp',
      '.tif',
      '.tiff',
      '.svg',
      '.avif',
      '.heic',
      '.heif',
      '.ico',
    };
    final images = files
        .where(
          (file) =>
              file is! DropItemDirectory &&
              (imageExtensions.contains(p.extension(file.path).toLowerCase()) ||
                  (file.mimeType?.startsWith('image/') ?? false)),
        )
        .toList();
    if (images.isEmpty) {
      await widget.workspace.openPaths(files.map((file) => file.path));
      return;
    }
    if (files.length != 1) {
      _showError(
        'Drop one image at a time. Mixed image/file drops are not imported or opened.',
      );
      return;
    }
    final image = images.single;
    if (!{
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.bmp',
      '.tif',
      '.tiff',
    }.contains(p.extension(image.path).toLowerCase())) {
      _showError(
        'Drop a PNG, JPEG, GIF, WebP, BMP or TIFF image. Other image formats are not imported.',
      );
      return;
    }
    if (_attachmentPending) {
      _showError(
        'Wait for the current image import to finish, then drop the image again.',
      );
      return;
    }
    await _importImage(droppedImage: image);
  }

  Future<bool> _pasteFromClipboard() async {
    final workspace = widget.workspace;
    final document = workspace.activeDocument;
    if (document == null) return true;
    final handled = await pasteClipboardHtml(
      controller: document.controller,
      isCurrent: () =>
          mounted &&
          identical(widget.workspace, workspace) &&
          identical(workspace.activeDocument, document),
      read: widget.readClipboardText,
    );
    if (handled) return true;
    return _importImage(fromClipboard: true);
  }

  Future<bool> _importImage({
    bool fromClipboard = false,
    DropItem? droppedImage,
  }) async {
    if (!(ModalRoute.of(context)?.isCurrent ?? true) ||
        hasEditorComposition(widget.workspace)) {
      return true;
    }
    if (_attachmentPending) return !fromClipboard;
    final workspace = widget.workspace;
    final document = workspace.activeDocument;
    if (document == null) return false;
    if (!fromClipboard &&
        document.controller.mode == IanvsMarkdownEditorMode.livePreview &&
        _documentInputTarget.isLocal) {
      _showError(
        'Focus the note body or switch to Source mode before importing an image from a table or property field.',
      );
      return true;
    }
    final edit = AttachmentInsertion.capture(document.controller);
    if (edit == null) {
      if (!fromClipboard) {
        _showError(
          'Enter Live or Source mode and finish composition before importing an image.',
        );
      }
      return true;
    }
    final root = workspace.workspaceRoot;
    final documentPath = document.path;
    final generation = ++_attachmentGeneration;
    var changed = false;
    final pasteFocus = fromClipboard
        ? FocusManager.instance.primaryFocus
        : null;
    void focusChanged() {
      if (fromClipboard && FocusManager.instance.primaryFocus != pasteFocus) {
        changed = true;
      }
    }

    if (fromClipboard) FocusManager.instance.addListener(focusChanged);
    void sourceChanged() {
      if (!edit.current(document.controller)) changed = true;
    }

    bool current() =>
        mounted &&
        !changed &&
        generation == _attachmentGeneration &&
        identical(widget.workspace, workspace) &&
        identical(workspace.activeDocument, document) &&
        workspace.workspaceRoot == root &&
        document.path == documentPath &&
        edit.current(document.controller);
    document.controller.addListener(sourceChanged);
    document.controller.modeListenable.addListener(sourceChanged);
    setState(() => _attachmentPending = true);
    try {
      // A plain-text Paste must still work in an unsaved document. Ask for the
      // destination only after the user-requested read actually returns an image.
      AttachmentImportTarget? target;
      if (!fromClipboard) {
        target = AttachmentImportTarget(root: root, documentPath: documentPath);
      }
      final payload = fromClipboard
          ? await widget.attachmentImportPlatform.readClipboardImage()
          : droppedImage != null
          ? await widget.attachmentImportPlatform.readDroppedImage(
              droppedImage.path,
              bookmark: droppedImage.extraAppleBookmark,
            )
          : await widget.attachmentImportPlatform.pickImage();
      if (payload == null) return !fromClipboard;
      if (!current()) return true;
      target ??= AttachmentImportTarget(root: root, documentPath: documentPath);
      final imported = await AttachmentImportService(
        source: widget.attachmentSource,
        platform: widget.attachmentImportPlatform,
      ).import(target: target, payload: payload, isCurrent: current);
      if (!mounted) return true;
      setState(() => _attachmentRevision++);
      if (!current() || !edit.apply(document.controller, imported.markdown)) {
        setState(() => _retainedImports.add((root!, documentPath!, imported)));
      } else {
        _editorFocus.requestFocus();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Imported ${imported.relativePath}. Undo removes the link, not the image file.',
            ),
          ),
        );
      }
      return true;
    } on Object catch (error) {
      if (mounted &&
          attachmentFailure(error).kind != AttachmentFailureKind.cancelled) {
        final message = error is AttachmentImportFailure
            ? error.message
            : attachmentFailure(error).message;
        final details = error is PlatformException ? error.details : null;
        final retainedPath =
            details is Map &&
                details['fileMayRemain'] == true &&
                details['relativePath'] is String
            ? details['relativePath'] as String
            : null;
        _showError(
          'Image import failed: $message${droppedImage == null ? '' : ' If the drag source does not provide a file grant, use Import Image instead.'}${retainedPath == null ? '' : ' A file may remain at $root/$retainedPath. It was not deleted or linked; inspect it before retrying.'}',
        );
      }
      return true;
    } finally {
      // Closed sessions dispose their controller after notifying the workspace.
      // ChangeNotifier permits removing a listener after disposal.
      if (fromClipboard) FocusManager.instance.removeListener(focusChanged);
      document.controller.removeListener(sourceChanged);
      document.controller.modeListenable.removeListener(sourceChanged);
      if (mounted) setState(() => _attachmentPending = false);
    }
  }

  Future<void> _showImportedLink(
    String root,
    String documentPath,
    ImportedAttachment imported,
  ) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Imported image kept'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: SelectableText(
            'Image: $root/${imported.relativePath}\n\nOriginal note: $documentPath\n\nInsert this link into that note when ready:\n${imported.markdown}',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Future<void> _insertWikiLink() async {
    if (!(ModalRoute.of(context)?.isCurrent ?? true) ||
        hasEditorComposition(widget.workspace)) {
      return;
    }
    final document = widget.workspace.activeDocument;
    if (document == null) return;
    if (document.controller.mode == IanvsMarkdownEditorMode.livePreview &&
        _documentInputTarget.isLocal) {
      _showError(
        'Place the cursor in the document body or use Source mode to insert a note link.',
      );
      return;
    }
    final edit = WikiLinkInsertion.capture(document.controller);
    if (edit == null) {
      _showError(
        'Enter Live or Source mode and finish composition before inserting a note link.',
      );
      return;
    }
    final epoch = widget.workspace.index.epoch;
    final generation = ++_wikiGeneration;
    bool current() =>
        mounted &&
        generation == _wikiGeneration &&
        epoch == widget.workspace.index.epoch &&
        identical(document, widget.workspace.activeDocument);
    final root = widget.workspace.workspaceRoot;
    if (root == null ||
        document.path == null ||
        !p.posix.isWithin(root, document.path!)) {
      _showError(
        'Open a workspace folder and a note inside it to insert Wiki links.',
      );
      return;
    }
    try {
      final resolver = WikiNoteResolver(widget.workspace.index);
      final catalog = await widget.workspace.index.catalog();
      final notes = await resolver.candidates(catalog);
      if (!mounted || !current()) return;
      final selected = await showDialog<WikiNoteCandidate>(
        context: context,
        builder: (_) => WikiNotePicker(
          notes: notes,
          title: 'Insert note link',
          initialQuery: edit.query,
          notice: catalog.complete
              ? null
              : 'The catalog is incomplete. Only known notes are shown; no missing note is inferred.',
        ),
      );
      if (!current() || selected == null) return;
      if (!WikiLinkInsertion.canRepresent(selected.relativePath)) {
        _showError(
          'This filename cannot be represented safely as a Wiki link.',
        );
        return;
      }
      if (!edit.apply(document.controller, selected.relativePath)) {
        _showError('The source or selection changed. Insert the link again.');
      } else {
        _editorFocus.requestFocus();
      }
    } on Object catch (error) {
      if (current()) _showError('Unable to list note links: $error');
    }
  }

  Future<void> _openDocumentLink(
    DocumentSession document,
    IanvsMarkdownLinkTarget link,
  ) {
    if (link.kind == IanvsMarkdownLinkKind.wiki) {
      return _openWikiLink(document, link.href ?? '');
    }
    if (link.kind == IanvsMarkdownLinkKind.tag) {
      return _openWorkspaceReferences(
        tag: (link.href ?? '').replaceFirst(RegExp(r'^tag:#?'), ''),
      );
    }
    return DocumentLinkService(
      workspace: widget.workspace,
      openImage: _openImage,
    ).open(document, link.href);
  }

  Future<void> _openWikiLink(DocumentSession origin, String target) async {
    if (!(ModalRoute.of(context)?.isCurrent ?? true) ||
        hasEditorComposition(widget.workspace)) {
      return;
    }
    final generation = ++_wikiGeneration;
    final epoch = widget.workspace.index.epoch;
    bool current() =>
        mounted &&
        generation == _wikiGeneration &&
        epoch == widget.workspace.index.epoch &&
        identical(origin, widget.workspace.activeDocument);
    ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? progress;
    final progressTimer = Timer(const Duration(milliseconds: 500), () {
      if (!current()) return;
      progress = ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(minutes: 5),
          content: const Text('Resolving local note names and aliases…'),
          action: SnackBarAction(
            label: 'Cancel',
            onPressed: () {
              _wikiGeneration++;
              widget.workspace.references.cancel();
            },
          ),
        ),
      );
    });
    final WikiNoteResolution resolution;
    try {
      resolution = await widget.workspace.references.resolveWiki(
        target,
        originPath: origin.path,
      );
    } finally {
      progressTimer.cancel();
      if (mounted) progress?.close();
    }
    if (!mounted || !current()) return;
    WikiNoteCandidate? selected;
    switch (resolution.status) {
      case WikiNoteStatus.resolved:
        selected = resolution.candidates.single;
      case WikiNoteStatus.ambiguous:
        selected = await showDialog<WikiNoteCandidate>(
          context: context,
          builder: (_) => WikiNotePicker(
            notes: resolution.candidates,
            title: 'Choose linked note',
            notice: resolution.message,
          ),
        );
      case WikiNoteStatus.missing:
        final create = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Note not found'),
            content: Text(resolution.message!),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              if (resolution.createPath != null)
                TextButton(
                  key: const ValueKey('wiki-create-note'),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Create note'),
                ),
            ],
          ),
        );
        if (!current() || create != true) return;
        // Reconcile after the user's decision; never overwrite a racing note or
        // silently turn approval for one path into creation of another.
        final latest = await widget.workspace.references.resolveWiki(
          target,
          originPath: origin.path,
          refreshMetadata: true,
        );
        if (!mounted || !current()) return;
        if (latest.status != WikiNoteStatus.missing ||
            latest.createPath != resolution.createPath) {
          _showError(
            'The target changed. Follow the link again before creating a note.',
          );
          return;
        }
        try {
          final created = await widget.workspace.createWikiNote(
            resolution.createPath!,
            epoch: epoch,
            isCurrent: current,
          );
          if (!created || !current()) return;
          selected = WikiNoteCandidate(
            relativePath: resolution.createPath!,
            comparisonPath: '',
          );
        } on Object catch (error) {
          if (current()) {
            _showError(
              'Unable to create the note: $error. A failed operation may have left an empty file; retry the link to check.',
            );
          }
          return;
        }
      case WikiNoteStatus.unavailable:
      case WikiNoteStatus.unsupported:
        _showError(resolution.message!);
        return;
    }
    if (!current() || selected == null) return;
    final existingSessionIds = widget.workspace.documents
        .map((d) => d.id)
        .toSet();
    final mode = origin.controller.mode;
    final originSource = origin.controller.text;
    final originSelection = origin.controller.selection;
    final originAnchor = origin.controller.viewportAnchor.value;
    final opened = await widget.workspace.openIndexedNote(
      selected.relativePath,
      epoch: epoch,
      isCurrent: current,
    );
    if (mounted &&
        opened != null &&
        !existingSessionIds.contains(opened.id) &&
        identical(widget.workspace.activeDocument, opened)) {
      opened.controller.mode = mode;
    }
    if (mounted && opened != null) {
      widget.workspace.rememberDocumentJump(
        origin,
        opened,
        anchor: originAnchor,
        selection: originSelection,
        source: originSource,
      );
    }
  }

  IanvsMarkdownController? _slashController;
  String _slashPrevious = '';
  bool _slashOpen = false;

  void _bindSlashController() {
    final next = widget.workspace.activeDocument?.controller;
    if (identical(next, _slashController)) return;
    _slashController?.removeListener(_slashChanged);
    _slashController = next;
    _slashPrevious = next?.text ?? '';
    next?.addListener(_slashChanged);
  }

  void _slashChanged() {
    final controller = _slashController;
    if (controller == null) return;
    final value = controller.value;
    final start = slashInsertionStart(_slashPrevious, value);
    _slashPrevious = value.text;
    if (start == null ||
        _slashOpen ||
        _paletteOpen ||
        _documentInputTarget.isLocal ||
        controller.mode == IanvsMarkdownEditorMode.preview) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !identical(controller, _slashController) ||
          controller.value != value ||
          !(ModalRoute.of(context)?.isCurrent ?? true)) {
        return;
      }
      unawaited(_showSlashMenu(controller, value, start));
    });
  }

  Future<void> _showSlashMenu(
    IanvsMarkdownController controller,
    TextEditingValue value,
    int start,
  ) async {
    _slashOpen = true;
    final mode = controller.mode;
    try {
      final choice = await showDialog<WorkspacePaletteSelection>(
        context: context,
        builder: (_) => WorkspacePalette(
          title: 'Insert block',
          entries: [
            for (final title in [...slashSnippets.keys, 'Image', 'Template'])
              WorkspacePaletteEntry(id: title, title: title),
          ],
        ),
      );
      if (!mounted ||
          choice == null ||
          !identical(controller, _slashController) ||
          controller.value != value ||
          controller.mode != mode) {
        return;
      }
      final selected = value.copyWith(
        selection: TextSelection(baseOffset: start, extentOffset: start + 1),
      );
      controller.value = selected;
      final snippet = slashSnippets[choice.id];
      if (snippet != null) {
        CapturedNoteInsertion(selected, mode).apply(controller, snippet);
      } else if (choice.id == 'Template') {
        await _useTemplate(insert: true);
      } else if (choice.id == 'Image') {
        await _importImage();
      }
      if (mounted &&
          identical(controller, _slashController) &&
          controller.value == selected) {
        controller.value = value;
      }
      if (mounted) _editorFocus.requestFocus();
    } finally {
      _slashOpen = false;
    }
  }

  Future<void> _extractSelection() async {
    final workspace = widget.workspace;
    final origin = workspace.activeDocument;
    if (origin == null ||
        workspace.workspaceRoot == null ||
        origin.path == null ||
        _documentInputTarget.isLocal ||
        hasEditorComposition(workspace)) {
      _showError('Select body text in a workspace note first.');
      return;
    }
    final value = origin.controller.value;
    if (!value.selection.isValid || value.selection.isCollapsed) return;
    final edit = CapturedNoteInsertion(value, origin.controller.mode);
    final epoch = workspace.index.epoch;
    final name = TextEditingController();
    final String? title;
    try {
      title = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Extract selection to note'),
          content: TextField(
            controller: name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'New note filename'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, name.text.trim()),
              child: const Text('Extract'),
            ),
          ],
        ),
      );
    } finally {
      name.dispose();
    }
    bool current() =>
        mounted &&
        identical(workspace, widget.workspace) &&
        epoch == workspace.index.epoch;
    if (!current() ||
        title == null ||
        title.isEmpty ||
        origin.controller.value != value) {
      return;
    }
    final String path;
    try {
      path = extractionRelativePath(
        title,
        origin.path!,
        workspace.workspaceRoot!,
      );
    } on FormatException catch (error) {
      _showError(error.message);
      return;
    }
    if (!WikiLinkInsertion.canRepresent(path)) {
      _showError('Use a Markdown filename without link delimiters.');
      return;
    }
    try {
      if (!await workspace.createWikiNote(
        path,
        epoch: epoch,
        isCurrent: current,
      )) {
        return;
      }
      final created = await workspace.openIndexedNote(
        path,
        epoch: epoch,
        isCurrent: current,
      );
      if (!current() || created == null) return;
      final contents = value.selection.textInside(value.text);
      created.controller.value = TextEditingValue(
        text: contents,
        selection: TextSelection.collapsed(offset: contents.length),
      );
      if (!await _saveDocument(created) || !current()) return;
      if (!workspace.documents.contains(origin) ||
          !edit.apply(origin.controller, '[[/$path]]')) {
        _showError(
          'The extracted note was saved; the original changed and was left intact.',
        );
        return;
      }
      workspace.selectDocument(workspace.documents.indexOf(origin));
    } on Object catch (error) {
      if (current()) {
        _showError(
          'Extraction did not finish: $error. Original text is retained until the new note is saved.',
        );
      }
    }
  }

  void _setReferencesVisible(bool value) {
    setState(() => _referencesVisible = value);
    widget.workspace.setReferenceView({'visible': value});
  }

  bool _referencesVisible = false;
  bool _referenceRestoreDone = false;

  Future<void> _insertReference(String text, String? sourcePath) async {
    final workspace = widget.workspace;
    final document = workspace.activeDocument;
    if (document == null || _documentInputTarget.isLocal) return;
    final controller = document.controller;
    final captured = CapturedNoteInsertion(controller.value, controller.mode);
    final epoch = workspace.index.epoch;
    try {
      final references = parseIanvsMarkdownNoteSemantics(text).references;
      if (references.isNotEmpty &&
          (sourcePath == null || document.path == null)) {
        throw const FormatException(
          'Save both notes before transferring references.',
        );
      }
      final targets = <String, String>{};
      for (final reference in references) {
        if (reference.kind != IanvsMarkdownSourceReferenceKind.wikiLink &&
            reference.kind != IanvsMarkdownSourceReferenceKind.wikiEmbed) {
          continue;
        }
        final result = await workspace.references.resolveWiki(
          reference.target,
          originPath: sourcePath,
        );
        if (result.status != WikiNoteStatus.resolved) {
          throw const FormatException(
            'Resolve missing or ambiguous wiki references before inserting.',
          );
        }
        targets[reference.target] = '/${result.candidates.single.relativePath}';
      }
      final transferred = references.isEmpty
          ? text
          : transferNoteContent(
              text,
              originPath: sourcePath!,
              destinationPath: document.path!,
              wikiTargets: targets,
            );
      if (!mounted ||
          epoch != workspace.index.epoch ||
          workspace.activeDocument != document ||
          !captured.apply(controller, transferred)) {
        if (mounted) {
          _showError('The destination changed. Insert the reference again.');
        }
      }
    } on Object catch (error) {
      if (mounted) _showError('Unable to insert reference: $error');
    }
  }

  bool _captureBusy = false;

  Future<void> _useTemplate({bool insert = false}) async {
    if (hasEditorComposition(widget.workspace)) return;
    final workspace = widget.workspace;
    final document = workspace.activeDocument;
    final epoch = workspace.index.epoch;
    if (insert && (document == null || _documentInputTarget.isLocal)) {
      _showError('Place the cursor in the document body to insert a template.');
      return;
    }
    final edit = document == null
        ? null
        : CapturedNoteInsertion(
            document.controller.value,
            document.controller.mode,
          );
    final result = await showDialog<NoteTemplateResult>(
      context: context,
      builder: (_) => NoteTemplateDialog(insert: insert),
    );
    if (!mounted ||
        result == null ||
        !identical(workspace, widget.workspace) ||
        epoch != workspace.index.epoch) {
      return;
    }
    if (insert) {
      if (!identical(document, workspace.activeDocument) ||
          !edit!.apply(document!.controller, result.text)) {
        _showError(
          'The source or selection changed. Insert the template again.',
        );
        return;
      }
    } else {
      final name = result.title.replaceAll(RegExp(r'[/\\]'), '-');
      final created = workspace.newDocument(name: '$name.md');
      created.controller.value = TextEditingValue(
        text: result.text,
        selection: TextSelection.collapsed(offset: result.text.length),
      );
    }
    _editorFocus.requestFocus();
  }

  Future<void> _openCaptureNote({bool inbox = false, String? append}) async {
    if (_captureBusy || hasEditorComposition(widget.workspace)) return;
    final workspace = widget.workspace;
    if (workspace.workspaceRoot == null) {
      _showError('Open a workspace folder to use daily notes and Inbox.');
      return;
    }
    _captureBusy = true;
    final epoch = workspace.index.epoch;
    bool current() =>
        mounted &&
        identical(workspace, widget.workspace) &&
        epoch == workspace.index.epoch;
    final filename = inbox ? 'Inbox.md' : '${noteDate(DateTime.now())}.md';
    try {
      final catalog = await workspace.index.catalog(refresh: true);
      final candidates = await WikiNoteResolver(
        workspace.index,
      ).candidates(catalog);
      if (!current()) return;
      final matches = candidates
          .where((note) => note.comparisonPath == filename.toLowerCase())
          .toList();
      if (matches.length > 1 || (matches.isEmpty && !catalog.complete)) {
        _showError(
          'The capture note cannot be resolved uniquely. Refresh the workspace and retry.',
        );
        return;
      }
      final target = matches.isEmpty ? filename : matches.single.relativePath;
      if (matches.isEmpty) {
        if (!await workspace.createWikiNote(
          target,
          epoch: epoch,
          isCurrent: current,
        )) {
          return;
        }
      }
      final document = await workspace.openIndexedNote(
        target,
        epoch: epoch,
        isCurrent: current,
      );
      if (!current() || document == null) return;
      if (append != null && append.trim().isNotEmpty) {
        final controller = document.controller;
        final prefix = controller.text.isEmpty
            ? ''
            : controller.text.endsWith('\n')
            ? '\n'
            : '\n\n';
        final text = '${controller.text}$prefix${append.trim()}\n';
        controller.commitHistoryGroup();
        controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        controller.commitHistoryGroup();
        if (!await _saveDocument(document) && current()) {
          _showError(
            'Capture remains in the open note. Save it before closing.',
          );
        }
      }
    } on Object catch (error) {
      if (current()) _showError('Unable to open capture note: $error');
    } finally {
      _captureBusy = false;
    }
  }

  Future<void> _quickAppend({required bool inbox}) async {
    final workspace = widget.workspace;
    final epoch = workspace.index.epoch;
    final text = TextEditingController();
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(inbox ? 'Append to Inbox' : 'Append to today'),
          content: SizedBox(
            width: 520,
            child: TextField(
              controller: text,
              autofocus: true,
              minLines: 4,
              maxLines: 10,
              decoration: const InputDecoration(labelText: 'Capture text'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, text.text),
              child: const Text('Append'),
            ),
          ],
        ),
      );
      if (!mounted ||
          result == null ||
          result.trim().isEmpty ||
          !identical(workspace, widget.workspace) ||
          epoch != workspace.index.epoch) {
        return;
      }
      await _openCaptureNote(inbox: inbox, append: result);
    } finally {
      text.dispose();
    }
  }

  bool _paletteOpen = false;

  Future<void> _openPalette({bool commands = false}) async {
    final workspace = widget.workspace;
    if (_paletteOpen ||
        !(ModalRoute.of(context)?.isCurrent ?? true) ||
        hasEditorComposition(workspace)) {
      return;
    }
    _paletteOpen = true;
    final epoch = workspace.index.epoch;
    final origin = workspace.activeDocument;
    bool current() =>
        mounted &&
        identical(workspace, widget.workspace) &&
        epoch == workspace.index.epoch &&
        identical(origin, workspace.activeDocument);
    final actions = <String, VoidCallback>{
      'Extract selection to note': _extractSelection,
      'New note': () => workspace.newDocument(),
      'New note from template': _useTemplate,
      'Insert template': () => _useTemplate(insert: true),
      'Open today’s note': _openCaptureNote,
      'Append to today': () => _quickAppend(inbox: false),
      'Append to Inbox': () => _quickAppend(inbox: true),
      'Open files': () => _guard(workspace.chooseAndOpenFiles),
      'Open workspace folder': () => _guard(workspace.chooseWorkspaceFolder),
      'Save': _saveCommand,
      'Save as': () => _saveCommand(saveAs: true),
      'Import image': () => unawaited(_importImage()),
      for (final action in DocumentExportAction.values)
        'Export ${action.name.toUpperCase()}': () => unawaited(
          _documentExport.run(
            context,
            workspace,
            action,
            renderMermaid: (source) async =>
                (await _mermaidRenderer.render(source)).svg,
            attachmentSource: widget.attachmentSource,
          ),
        ),
      'Search workspace': _openWorkspaceSearch,
      'Find in document': _openFind,
      'Show backlinks': _openWorkspaceReferences,
      'Toggle reference pane': () => _setReferencesVisible(!_referencesVisible),
      'Toggle sidebar': workspace.toggleSidebar,
      'Toggle outline': workspace.toggleOutline,
      'Live preview': () =>
          setEditorMode(workspace, IanvsMarkdownEditorMode.livePreview),
      'Source mode': () =>
          setEditorMode(workspace, IanvsMarkdownEditorMode.source),
      'Reading mode': () =>
          setEditorMode(workspace, IanvsMarkdownEditorMode.preview),
    };
    try {
      final entries = <WorkspacePaletteEntry>[];
      final sessions = <String, DocumentSession>{};
      String? notice;
      if (commands) {
        entries.addAll(
          actions.keys.map(
            (label) => WorkspacePaletteEntry(id: label, title: label),
          ),
        );
      } else {
        for (final document in workspace.documents) {
          sessions[document.path ?? document.id] = document;
        }
        final root = workspace.workspaceRoot;
        if (root != null) {
          final snapshot = await workspace.references.refresh();
          if (!current()) return;
          if (!snapshot.complete) {
            notice =
                'Some notes or aliases are unavailable. Showing known notes.';
          }
          final sources = {
            for (final note in snapshot.notes.values)
              note.source.path: note.source.text,
          };
          for (final note in snapshot.noteCandidates) {
            final absolute = p.posix.join(root, note.relativePath);
            final document = sessions.remove(absolute);
            entries.add(
              WorkspacePaletteEntry(
                id: 'note:${note.relativePath}',
                title: paletteNoteTitle(
                  document?.controller.text ?? sources[absolute] ?? '',
                  p.posix.basenameWithoutExtension(note.relativePath),
                ),
                detail: note.relativePath,
                searchTerms:
                    snapshot.aliases.byPath[note.relativePath]?.join(' ') ?? '',
                recency:
                    document?.lastActivated ??
                    workspace.recentNoteActivation(absolute),
              ),
            );
          }
        }
        for (final document in sessions.values) {
          entries.add(
            WorkspacePaletteEntry(
              id: 'session:${document.id}',
              title: paletteNoteTitle(document.controller.text, document.name),
              detail: document.path ?? 'Unsaved note',
              recency: document.lastActivated,
            ),
          );
        }
      }
      if (!mounted || !current()) return;
      final selection = await showDialog<WorkspacePaletteSelection>(
        context: context,
        builder: (_) => WorkspacePalette(
          title: commands ? 'Command palette' : 'Quick switcher',
          entries: entries,
          allowCreate: !commands,
          notice: notice,
        ),
      );
      if (!current() || selection == null) return;
      _editorFocus.requestFocus();
      if (commands) {
        actions[selection.id]?.call();
      } else if (selection.create) {
        final name = selection.id.toLowerCase().endsWith('.md')
            ? selection.id
            : '${selection.id}.md';
        if (workspace.workspaceRoot == null) {
          workspace.newDocument(name: name);
        } else if (await workspace.createWikiNote(
          name,
          epoch: epoch,
          isCurrent: current,
        )) {
          if (!current()) return;
          await workspace.openIndexedNote(
            name,
            epoch: epoch,
            isCurrent: current,
          );
        }
      } else if (selection.id.startsWith('session:')) {
        workspace.selectDocument(
          workspace.documents.indexWhere(
            (document) => document.id == selection.id.substring(8),
          ),
        );
      } else {
        await workspace.openIndexedNote(
          selection.id.substring(5),
          epoch: epoch,
          isCurrent: current,
        );
      }
    } on Object catch (error) {
      if (mounted) _showError('Unable to complete palette action: $error');
    } finally {
      _paletteOpen = false;
    }
  }

  Future<void> _openWorkspaceSearch() async {
    if (!(ModalRoute.of(context)?.isCurrent ?? true) ||
        hasEditorComposition(widget.workspace)) {
      return;
    }
    final search = WorkspaceSearchController(widget.workspace.index);
    try {
      final match = await showDialog<WorkspaceSourceMatch>(
        context: context,
        builder: (_) => WorkspaceSearchDialog(controller: search),
      );
      if (!mounted || match == null) return;
      search.cancel();
      await _openWorkspaceSourceMatch(match);
    } on Object catch (error) {
      if (mounted) _showError('Unable to open search result: $error');
    } finally {
      search.dispose();
    }
  }

  Future<void> _openWorkspaceReferences({String? tag}) async {
    if (!(ModalRoute.of(context)?.isCurrent ?? true) ||
        hasEditorComposition(widget.workspace)) {
      return;
    }
    final document = widget.workspace.activeDocument;
    final root = widget.workspace.index.root;
    final path = document?.path;
    if (tag == null &&
        (root == null || path == null || !p.posix.isWithin(root, path))) {
      _showError('Open a note inside a workspace to show its backlinks.');
      return;
    }
    final match = await showDialog<WorkspaceSourceMatch>(
      context: context,
      builder: (_) => WorkspaceReferencesPanel(
        index: widget.workspace.references,
        targetPath: tag == null ? p.posix.relative(path!, from: root) : null,
        targetSessionId: document?.id,
        tag: tag,
      ),
    );
    if (mounted && match != null) await _openWorkspaceSourceMatch(match);
  }

  Future<void> _openWorkspaceSourceMatch(WorkspaceSourceMatch match) async {
    final search = WorkspaceSearchController(widget.workspace.index);
    final generation = _wikiGeneration;
    try {
      final snapshot = await search.resolve(match);
      if (!mounted ||
          generation != _wikiGeneration ||
          hasEditorComposition(widget.workspace)) {
        return;
      }
      if (snapshot == null) {
        _showError(
          'Source changed since this result. Search again to use current offsets.',
        );
        return;
      }
      _closeFind(restoreFocus: false, restoreScroll: false);
      DocumentSession? document;
      if (snapshot.sessionId != null) {
        final documents = widget.workspace.documents;
        final position = documents.indexWhere(
          (d) => d.id == snapshot.sessionId,
        );
        if (position >= 0) {
          widget.workspace.selectDocument(position);
          document = documents[position];
        }
      } else if (snapshot.path != null) {
        document = await widget.workspace.openPath(snapshot.path!);
      }
      if (!mounted) return;
      if (document == null ||
          document.controller.text != snapshot.text ||
          widget.workspace.index.epoch != match.scopeEpoch ||
          !identical(widget.workspace.activeDocument, document) ||
          hasEditorComposition(widget.workspace)) {
        _showError(
          'Source changed while opening. Search again to use current offsets.',
        );
        return;
      }
      _lastFindQuery = match.query;
      _lastMatchCase = match.matchCase;
      _openFind(
        seedSelection: false,
        sourceAnchor: match.range.start,
        expectedSource: snapshot.text,
      );
    } on Object catch (error) {
      if (mounted) _showError('Unable to open source result: $error');
    } finally {
      search.dispose();
    }
  }

  void _findNext({bool backwards = false}) {
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    if (_find == null) {
      _openFind(seedSelection: false, navigateBackwards: backwards);
    } else {
      _find!.next(backwards: backwards);
    }
  }

  void _changeFindScope(DocumentFindScope scope) {
    final find = _find;
    if (find == null || find.isComposing || find.scope == scope) return;
    find.setScope(scope, reveal: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_find, find) || find.scope != scope) return;
      // Source selection must change after Live's editing listener detaches.
      find.next();
      _findFocus.requestFocus();
    });
  }

  void _enableFindEditing() {
    final find = _find;
    if (find == null || find.isComposing) return;
    _enablingFindEditing = true;
    try {
      _changeFindScope(DocumentFindScope.source);
      find.readOnly = false;
      widget.workspace.setMode(IanvsMarkdownEditorMode.source);
    } finally {
      _enablingFindEditing = false;
    }
    setState(() {});
  }

  void _closeFind({bool restoreFocus = true, bool restoreScroll = true}) {
    final find = _find;
    if (find == null) return;
    final epoch = ++_findSurfaceEpoch;
    final document = widget.workspace.activeDocument;
    final restoreEditorFocus =
        _beforeFindFocused || _editorFocus.hasFocus || find.highlight != null;
    final scroll =
        identical(find.document, document?.controller) &&
            (find.document.mode == IanvsMarkdownEditorMode.source ||
                find.scope == DocumentFindScope.body) &&
            document!.scrollController.hasClients
        ? document.scrollController.offset
        : restoreScroll
        ? _beforeFindScroll
        : null;
    _lastFindQuery = find.query.text;
    _lastReplacement = find.replacement.text;
    _lastMatchCase = find.matchCase;
    find.document.modeListenable.removeListener(_findModeChanged);
    find.removeListener(_findChanged);
    setState(() {
      _find = null;
      _resumeLiveController =
          restoreFocus &&
              restoreEditorFocus &&
              find.scope == DocumentFindScope.source &&
              find.document.mode == IanvsMarkdownEditorMode.livePreview
          ? find.document
          : null;
    });
    find.dispose();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (epoch == _findSurfaceEpoch) _resumeLiveController = null;
      if (!mounted ||
          epoch != _findSurfaceEpoch ||
          _find != null ||
          !identical(document, widget.workspace.activeDocument)) {
        return;
      }
      if (document != null) _restoreDocumentScroll(document, scroll);
      if (restoreFocus) {
        if (restoreEditorFocus && _editorFocus.parent != null) {
          _editorFocus.requestFocus();
        } else {
          _shellFocus.requestFocus();
        }
      }
      if (scroll != null &&
          document?.controller.mode == IanvsMarkdownEditorMode.source) {
        // Reconnecting input schedules a caret reveal. Restore the viewport
        // after that one-shot reveal so an empty/no-match search does not undo
        // the user's manual scrolling. Never run after another tab/surface won.
        scheduleMicrotask(() {
          if (!mounted) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                epoch == _findSurfaceEpoch &&
                _find == null &&
                identical(document, widget.workspace.activeDocument) &&
                document!.controller.mode == IanvsMarkdownEditorMode.source) {
              _restoreDocumentScroll(document, scroll);
            }
          });
          WidgetsBinding.instance.ensureVisualUpdate();
        });
      }
    });
  }

  void _restoreDocumentScroll(DocumentSession document, double? offset) {
    if (offset == null || !document.scrollController.hasClients) return;
    final position = document.scrollController.position;
    document.scrollController.jumpTo(
      offset.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  @override
  void dispose() {
    _slashController?.removeListener(_slashChanged);
    _documentExport.dispose();
    _documentInputTarget.dispose();
    widget.workspace.removeListener(_workspaceChanged);
    _find?.document.modeListenable.removeListener(_findModeChanged);
    _find?.removeListener(_findChanged);
    _find?.dispose();
    _editorFocus.dispose();
    _findFocus.dispose();
    _shellFocus.dispose();
    _mermaidRenderer.dispose();
    super.dispose();
  }

  Future<void> _openImage(String path) => showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: SizedBox(
        width: 1000,
        height: 700,
        child: Column(
          children: [
            ListTile(
              title: Text(p.basename(path)),
              trailing: IconButton(
                tooltip: 'Close image',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: LocalDocumentImage(
                  path: path,
                  onOpenExternal: () => _guard(
                    () => DocumentLinkService.openExternalUri(Uri.file(path)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.workspace,
      builder: (context, _) {
        final workspace = widget.workspace;
        final document = workspace.activeDocument;
        if (!workspace.initialized && workspace.recoveryError != null) {
          return Scaffold(
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Recovery needs attention'),
                      const SizedBox(height: 12),
                      SelectableText(workspace.recoveryError!),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => _guard(
                          widget.onRetryInitialization ??
                              workspace.retryRecovery,
                        ),
                        child: const Text('Retry recovery'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        if (!workspace.initialized || document == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return DesktopMenuBar(
          workspace: workspace,
          onOpen: () => _guard(workspace.chooseAndOpenFiles),
          onOpenFolder: () => _guard(workspace.chooseWorkspaceFolder),
          onSave: () => _saveCommand(),
          onSaveAs: () => _saveCommand(saveAs: true),
          onImportImage: () => unawaited(_importImage()),
          onExportHtml: () => unawaited(
            _documentExport.run(
              context,
              workspace,
              DocumentExportAction.html,
              renderMermaid: (source) async =>
                  (await _mermaidRenderer.render(source)).svg,
              attachmentSource: widget.attachmentSource,
            ),
          ),
          onExportMarkdown: () => unawaited(
            _documentExport.run(
              context,
              workspace,
              DocumentExportAction.markdown,
              attachmentSource: widget.attachmentSource,
            ),
          ),
          onExportBundle: () => unawaited(
            _documentExport.run(
              context,
              workspace,
              DocumentExportAction.bundle,
              attachmentSource: widget.attachmentSource,
            ),
          ),
          onExportPdf: () => unawaited(
            _documentExport.run(
              context,
              workspace,
              DocumentExportAction.pdf,
              renderMermaid: (source) async =>
                  (await _mermaidRenderer.render(source)).svg,
              attachmentSource: widget.attachmentSource,
            ),
          ),
          onClose: () => _guard(() => _closeDocument(document)),
          onToggleTheme: widget.onToggleTheme,
          onUseSystemTheme: widget.onUseSystemTheme,
          onOpenSettings: widget.onOpenSettings,
          onFind: _openFind,
          onFindNext: _findNext,
          onFindPrevious: () => _findNext(backwards: true),
          child: CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              ...readingSizeShortcuts(workspace),
              for (final useMeta in [true, false]) ...{
                SingleActivator(
                  LogicalKeyboardKey.keyP,
                  meta: useMeta,
                  control: !useMeta,
                ): () =>
                    _openPalette(),
                SingleActivator(
                  LogicalKeyboardKey.keyP,
                  meta: useMeta,
                  control: !useMeta,
                  shift: true,
                ): () =>
                    _openPalette(commands: true),
              },
              const SingleActivator(
                LogicalKeyboardKey.bracketLeft,
                meta: true,
              ): () =>
                  navigateBack(workspace),
              const SingleActivator(
                LogicalKeyboardKey.arrowLeft,
                control: true,
                alt: true,
              ): () =>
                  navigateBack(workspace),
              _WikiLinkActivator(workspace, meta: true): _insertWikiLink,
              _WikiLinkActivator(workspace, control: true): _insertWikiLink,
              const SingleActivator(
                LogicalKeyboardKey.keyF,
                meta: true,
                shift: true,
              ): _openWorkspaceSearch,
              const SingleActivator(
                LogicalKeyboardKey.keyF,
                control: true,
                shift: true,
              ): _openWorkspaceSearch,
              const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
                  _openFind,
              const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                  _openFind,
              const SingleActivator(LogicalKeyboardKey.keyG, meta: true):
                  _findNext,
              const SingleActivator(LogicalKeyboardKey.keyG, control: true):
                  _findNext,
              const SingleActivator(
                LogicalKeyboardKey.keyG,
                meta: true,
                shift: true,
              ): () =>
                  _findNext(backwards: true),
              const SingleActivator(
                LogicalKeyboardKey.keyG,
                control: true,
                shift: true,
              ): () =>
                  _findNext(backwards: true),
              if (_find != null)
                const SingleActivator(LogicalKeyboardKey.escape): () {
                  if (!_find!.isComposing) _closeFind();
                },
              const SingleActivator(LogicalKeyboardKey.comma, meta: true):
                  ?widget.onOpenSettings,
              const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
                  workspace.newDocument,
              const SingleActivator(LogicalKeyboardKey.keyN, control: true):
                  workspace.newDocument,
              const SingleActivator(LogicalKeyboardKey.keyO, meta: true): () =>
                  _guard(workspace.chooseAndOpenFiles),
              const SingleActivator(
                LogicalKeyboardKey.keyO,
                control: true,
              ): () =>
                  _guard(workspace.chooseAndOpenFiles),
              const SingleActivator(
                LogicalKeyboardKey.keyO,
                meta: true,
                shift: true,
              ): () =>
                  _guard(workspace.chooseWorkspaceFolder),
              const SingleActivator(
                LogicalKeyboardKey.keyO,
                control: true,
                shift: true,
              ): () =>
                  _guard(workspace.chooseWorkspaceFolder),
              const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
                  _saveCommand(),
              const SingleActivator(
                LogicalKeyboardKey.keyS,
                control: true,
              ): () =>
                  _saveCommand(),
              const SingleActivator(
                LogicalKeyboardKey.keyS,
                meta: true,
                shift: true,
              ): () =>
                  _saveCommand(saveAs: true),
              const SingleActivator(
                LogicalKeyboardKey.keyS,
                control: true,
                shift: true,
              ): () =>
                  _saveCommand(saveAs: true),
              const SingleActivator(LogicalKeyboardKey.keyW, meta: true): () =>
                  _closeDocument(document),
              const SingleActivator(
                LogicalKeyboardKey.keyW,
                control: true,
              ): () =>
                  _closeDocument(document),
              const SingleActivator(
                LogicalKeyboardKey.keyS,
                meta: true,
                control: true,
              ): workspace.toggleSidebar,
              const SingleActivator(LogicalKeyboardKey.keyB, control: true):
                  workspace.toggleSidebar,
              for (var i = 0; i < tabDigitKeys.length; i++)
                SingleActivator(tabDigitKeys[i], meta: true): () =>
                    workspace.selectDocument(i),
            },
            child: Scaffold(
              body: LayoutBuilder(
                builder: (context, constraints) {
                  final showOutline =
                      workspace.outlineVisible && !_referencesVisible;
                  final referenceWidth = _referencesVisible
                      ? math.min(360.0, constraints.maxWidth * 0.4)
                      : 0.0;
                  final inspectorWidth = showOutline
                      ? DesktopMetrics.inspectorWidth
                      : 0.0;
                  final minContentWidth = math.max(
                    inspectorWidth +
                        WorkspaceLayout.minEditorWidth +
                        referenceWidth,
                    WorkspaceLayout.minContentWidth,
                  );
                  final maxSidebarWidth =
                      (constraints.maxWidth - minContentWidth).clamp(
                        WorkspaceLayout.minSidebarWidth,
                        WorkspaceLayout.maxSidebarWidth,
                      );
                  final sidebarWidth = workspace.sidebarWidth.clamp(
                    WorkspaceLayout.minSidebarWidth,
                    maxSidebarWidth,
                  );
                  final content = Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (workspace.sidebarVisible &&
                          (!_referencesVisible || constraints.maxWidth >= 1100))
                        SizedBox(
                          width: sidebarWidth,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              WorkspaceSidebar(
                                key: ValueKey(workspace.workspaceRoot),
                                workspace: workspace,
                                onSave: _saveDocument,
                                onSearchSource: _openWorkspaceSearch,
                                width: sidebarWidth,
                                onError: _showError,
                              ),
                              Positioned(
                                top: 0,
                                bottom: 0,
                                right: 0,
                                width: 8,
                                child: SidebarResizeHandle(
                                  key: const ValueKey('sidebar-resize-handle'),
                                  width: sidebarWidth,
                                  maxWidth: maxSidebarWidth,
                                  onResize: workspace.setSidebarWidth,
                                ),
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: Column(
                          children: [
                            TitleTabsBar(
                              workspace: workspace,
                              onSave: _saveDocument,
                              onClose: _closeDocument,
                              documentActions: [
                                IconButton(
                                  key: const ValueKey('quick-switcher-button'),
                                  tooltip: 'Quick switcher (⌘P / Ctrl+P)',
                                  onPressed: () => _openPalette(),
                                  icon: const Icon(Icons.search, size: 16),
                                ),
                                IconButton(
                                  key: const ValueKey('command-palette-button'),
                                  tooltip:
                                      'Command palette (⌘⇧P / Ctrl+Shift+P)',
                                  onPressed: () => _openPalette(commands: true),
                                  icon: const Icon(Icons.terminal, size: 16),
                                ),
                                IconButton(
                                  key: const ValueKey('import-image-button'),
                                  tooltip: _attachmentPending
                                      ? 'Importing image…'
                                      : 'Import image',
                                  onPressed: _attachmentPending
                                      ? null
                                      : () => unawaited(_importImage()),
                                  icon: Icon(
                                    _attachmentPending
                                        ? Icons.hourglass_top
                                        : Icons.add_photo_alternate_outlined,
                                    size: 16,
                                    semanticLabel: _attachmentPending
                                        ? 'Importing image'
                                        : 'Import image',
                                  ),
                                  style: const ButtonStyle(
                                    minimumSize: WidgetStatePropertyAll(
                                      Size(32, 32),
                                    ),
                                    padding: WidgetStatePropertyAll(
                                      EdgeInsets.all(6),
                                    ),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                                IconButton(
                                  key: const ValueKey(
                                    'workspace-backlinks-button',
                                  ),
                                  tooltip: 'Backlinks',
                                  onPressed: () => _openWorkspaceReferences(),
                                  icon: const Icon(
                                    Icons.link,
                                    size: 16,
                                    semanticLabel: 'Backlinks',
                                  ),
                                  style: const ButtonStyle(
                                    minimumSize: WidgetStatePropertyAll(
                                      Size(32, 32),
                                    ),
                                    padding: WidgetStatePropertyAll(
                                      EdgeInsets.all(6),
                                    ),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                                IconButton(
                                  key: const ValueKey(
                                    'insert-wiki-link-button',
                                  ),
                                  tooltip:
                                      'Insert note link (⌘⇧K / Ctrl+Shift+K)',
                                  onPressed: _insertWikiLink,
                                  icon: const Icon(
                                    Icons.add_link,
                                    size: 16,
                                    semanticLabel: 'Insert note link',
                                  ),
                                  style: const ButtonStyle(
                                    minimumSize: WidgetStatePropertyAll(
                                      Size(32, 32),
                                    ),
                                    padding: WidgetStatePropertyAll(
                                      EdgeInsets.all(6),
                                    ),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ],
                            ),
                            if (_retainedImports.firstOrNull
                                case final retained?)
                              MaterialBanner(
                                content: Text(
                                  'Image saved to ${retained.$1}/${retained.$3.relativePath}, but the note or selection changed. The file was kept; no link was inserted.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => _showImportedLink(
                                      retained.$1,
                                      retained.$2,
                                      retained.$3,
                                    ),
                                    child: const Text('Show link'),
                                  ),
                                  TextButton(
                                    onPressed: () => setState(
                                      () => _retainedImports.removeAt(0),
                                    ),
                                    child: const Text('Dismiss'),
                                  ),
                                ],
                              ),
                            if (_find case final find?)
                              DocumentFindBar(
                                controller: find,
                                queryFocus: _findFocus,
                                onClose: _closeFind,
                                onEnableEditing: _enableFindEditing,
                                onScopeChanged: _changeFindScope,
                              ),
                            if (workspace.recoveryError != null ||
                                workspace.recoveryNotice != null)
                              MaterialBanner(
                                content: Text(
                                  workspace.recoveryError ??
                                      workspace.recoveryNotice!,
                                ),
                                actions: [
                                  if (workspace.recoveryError != null)
                                    TextButton(
                                      onPressed: () =>
                                          _guard(workspace.retryRecovery),
                                      child: const Text('Retry recovery'),
                                    )
                                  else
                                    TextButton(
                                      onPressed:
                                          workspace.dismissRecoveryNotice,
                                      child: const Text('Dismiss'),
                                    ),
                                ],
                              ),
                            if (document.hasExternalChanges)
                              _ExternalChangeBanner(
                                document: document,
                                onReload: () => _guard(
                                  () => workspace.reloadFromDisk(document),
                                ),
                                onResolve: () =>
                                    _guard(() => _saveDocument(document)),
                              ),
                            Expanded(
                              child: DropTarget(
                                enable: widget.enableFileDrop,
                                onDragEntered: (_) =>
                                    setState(() => _draggingFiles = true),
                                onDragExited: (_) =>
                                    setState(() => _draggingFiles = false),
                                onDragDone: (details) {
                                  setState(() => _draggingFiles = false);
                                  _guard(() => _handleFileDrop(details.files));
                                },
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: LayoutBuilder(
                                            builder: (context, constraints) {
                                              // Center the same document column
                                              // in Live, Source and Read, using
                                              // the space between both panels.
                                              final inset = math.max(
                                                constraints.maxWidth < 500
                                                    ? 24.0
                                                    : 48.0,
                                                (constraints.maxWidth -
                                                        workspace
                                                            .readingPreferences
                                                            .width
                                                            .pixels) /
                                                    2,
                                              );
                                              if (_find case final find?
                                                  when find.scope ==
                                                      DocumentFindScope
                                                          .source) {
                                                return IanvsMarkdownEditor(
                                                  key: ValueKey(
                                                    'find-source-${document.id}',
                                                  ),
                                                  controller:
                                                      document.controller,
                                                  focusNode: _editorFocus,
                                                  scrollController:
                                                      document.scrollController,
                                                  readOnly: find.readOnly,
                                                  onPaste: _pasteFromClipboard,
                                                  highlightedRange:
                                                      find.highlight,
                                                  showToolbar: false,
                                                  enableModeShortcuts: false,
                                                  placeholder:
                                                      'Start writing Markdown…',
                                                  padding: EdgeInsets.fromLTRB(
                                                    inset,
                                                    32,
                                                    inset,
                                                    56,
                                                  ),
                                                  onSaveRequested: (_) =>
                                                      _saveFromEditor(document),
                                                );
                                              }
                                              return DocumentAttachmentScope(
                                                root: workspace.workspaceRoot,
                                                documentPath: document.path,
                                                revision:
                                                    workspace
                                                        .workspaceFilesRevision +
                                                    _attachmentRevision,
                                                source: widget.attachmentSource,
                                                builder: (context, images) => IanvsMarkdownCodeLayout(
                                                  softWrap: workspace
                                                      .readingPreferences
                                                      .wrapCode,
                                                  child: IanvsMarkdownLiveEditor(
                                                    preserveViewport: true,
                                                    styleSheet: readingStyleSheet(
                                                      context,
                                                      workspace
                                                          .readingPreferences,
                                                    ),
                                                    readingHighlights:
                                                        _find?.scope ==
                                                            DocumentFindScope
                                                                .body
                                                        ? IanvsMarkdownReadingHighlights(
                                                            source: document
                                                                .controller
                                                                .text,
                                                            matches: _find!
                                                                .bodyMatches,
                                                            activeIndex: _find!
                                                                .currentIndex,
                                                          )
                                                        : null,
                                                    builders: {
                                                      'a': NoteLinkPreviewBuilder(
                                                        workspace: workspace,
                                                        document: document,
                                                        onTap: (link) => _guard(
                                                          () =>
                                                              _openDocumentLink(
                                                                document,
                                                                link,
                                                              ),
                                                        ),
                                                      ),
                                                    },
                                                    imageBuilder: images.image,
                                                    onPaste:
                                                        _pasteFromClipboard,
                                                    wikiEmbedBuilder:
                                                        images.wiki,
                                                    key: ValueKey(document.id),
                                                    controller:
                                                        document.controller,
                                                    focusNode: _editorFocus,
                                                    autofocus: identical(
                                                      _resumeLiveController,
                                                      document.controller,
                                                    ),
                                                    clipboardWriter: (data) =>
                                                        writeIanvsMarkdownRichClipboard(
                                                          markdown:
                                                              data.markdown,
                                                          html: data.html,
                                                        ),
                                                    onTapLinkTarget: (link) => _guard(
                                                      () =>
                                                          link.kind ==
                                                              IanvsMarkdownLinkKind
                                                                  .wiki
                                                          ? _openWikiLink(
                                                              document,
                                                              link.href ?? '',
                                                            )
                                                          : link.kind ==
                                                                IanvsMarkdownLinkKind
                                                                    .tag
                                                          ? _openWorkspaceReferences(
                                                              tag: (link.href ?? '')
                                                                  .replaceFirst(
                                                                    RegExp(
                                                                      r'^tag:#?',
                                                                    ),
                                                                    '',
                                                                  ),
                                                            )
                                                          : DocumentLinkService(
                                                              workspace:
                                                                  workspace,
                                                              openImage:
                                                                  _openImage,
                                                            ).open(
                                                              document,
                                                              link.href,
                                                            ),
                                                    ),
                                                    diagramBuilder:
                                                        (
                                                          context,
                                                          source,
                                                        ) => DocumentDiagram(
                                                          source: source,
                                                          renderer:
                                                              _mermaidRenderer,
                                                        ),
                                                    scrollController: document
                                                        .scrollController,
                                                    showToolbar: false,
                                                    placeholder:
                                                        'Start writing Markdown…',
                                                    enableModeShortcuts: false,
                                                    enableHeadingFolding: true,
                                                    showNavigationPane: false,
                                                    showOutlineInPreview: false,
                                                    showFrontMatter: false,
                                                    contentMaxWidth: workspace
                                                        .readingPreferences
                                                        .width
                                                        .pixels,
                                                    padding:
                                                        EdgeInsets.fromLTRB(
                                                          inset,
                                                          32,
                                                          inset,
                                                          56,
                                                        ),
                                                    onSaveRequested: (_) =>
                                                        _saveFromEditor(
                                                          document,
                                                        ),
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                        if (showOutline)
                                          FloatingOutline(document: document),
                                      ],
                                    ),
                                    if (_draggingFiles) const _DropOverlay(),
                                  ],
                                ),
                              ),
                            ),
                            _DocumentStatusBar(
                              document: document,
                              workspace: workspace,
                            ),
                          ],
                        ),
                      ),
                      if (_referencesVisible)
                        SizedBox(
                          width: referenceWidth,
                          child: ReferenceDock(
                            key: ValueKey(workspace.workspaceRoot),
                            workspace: workspace,
                            onClose: () => _setReferencesVisible(false),
                            onInsert: _insertReference,
                          ),
                        ),
                    ],
                  );
                  return Focus(
                    focusNode: _shellFocus,
                    autofocus: true,
                    child: content,
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  void _saveCommand({bool saveAs = false}) {
    final controller = widget.workspace.activeDocument?.controller;
    if (controller == null) return;
    if (hasEditorComposition(widget.workspace)) return;
    if (!saveAs &&
        IanvsMarkdownShortcuts.invoke(
          IanvsMarkdownCommand.save,
          controller: controller,
        )) {
      return;
    }
    final document = widget.workspace.activeDocument;
    if (document != null) _guard(() => _saveDocument(document, saveAs: saveAs));
  }

  Future<bool> _saveDocument(DocumentSession document, {bool saveAs = false}) =>
      widget.workspace.saveDocument(
        document,
        saveAs: saveAs,
        onConflict: _resolveSaveConflict,
      );

  Future<SaveConflictChoice> _resolveSaveConflict(
    MarkdownSaveConflict conflict,
  ) async {
    if (!mounted) return SaveConflictChoice.cancel;
    return await showDialog<SaveConflictChoice>(
          context: context,
          builder: (context) => AlertDialog(
            constraints: const BoxConstraints(maxWidth: 520),
            title: Text('“${p.basename(conflict.path)}” changed on disk'),
            content: Text(
              conflict.currentContents == null
                  ? 'The file was removed outside Linefold. Keep Both saves your '
                        'version as a new local copy. Overwrite recreates the original '
                        'file. Cancel keeps your edits unsaved.'
                  : 'The disk version differs from the version you opened. Keep Both '
                        'leaves the disk file untouched and saves your version as a new '
                        'local copy. Overwrite replaces the disk version with your '
                        'captured edits. Cancel keeps your edits unsaved.',
            ),
            actions: [
              if (conflict.localContents != null)
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => SaveConflictDiffDialog(
                      disk: conflict.currentContents,
                      local: conflict.localContents!,
                    ),
                  ),
                  child: const Text('Compare Changes'),
                ),
              OutlinedButton(
                onPressed: () =>
                    Navigator.pop(context, SaveConflictChoice.cancel),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, SaveConflictChoice.overwrite),
                child: const Text('Overwrite'),
              ),
              FilledButton(
                autofocus: true,
                onPressed: () =>
                    Navigator.pop(context, SaveConflictChoice.keepBoth),
                child: const Text('Keep Both'),
              ),
            ],
          ),
        ) ??
        SaveConflictChoice.cancel;
  }

  Future<void> _saveFromEditor(DocumentSession document) async {
    final bool saved;
    try {
      saved = await _saveDocument(document);
    } on Object catch (error) {
      _showError(describeFileError(error));
      // The host has reported the error. Do not let the editor acknowledge
      // this failed snapshot, or report it again as an unhandled shortcut error.
      throw const IanvsMarkdownSaveCancelledException();
    }
    if (!saved) throw const IanvsMarkdownSaveCancelledException();
  }

  void _guard(Future<dynamic> Function() action) {
    unawaited(() async {
      try {
        await action();
      } on Object catch (error) {
        _showError(describeFileError(error));
      }
    }());
  }

  Future<void> _closeDocument(DocumentSession document) async {
    if (document.controller.isDirty) {
      final choice = await showDialog<_CloseChoice>(
        context: context,
        builder: (context) => AlertDialog(
          constraints: const BoxConstraints(maxWidth: 420),
          title: Text('Save changes to “${document.name}”?'),
          content: const Text(
            'Unsaved changes will be lost if you discard them.',
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context, _CloseChoice.cancel),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, _CloseChoice.discard),
              child: const Text('Don’t Save'),
            ),
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context, _CloseChoice.save),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (!mounted || choice == null || choice == _CloseChoice.cancel) return;
      if (choice == _CloseChoice.save) {
        try {
          if (!await _saveDocument(document) || document.controller.isDirty) {
            // A save acknowledges its captured snapshot, not later edits made
            // while resolving the conflict or waiting for disk.
            return;
          }
        } on Object catch (error) {
          _showError(describeFileError(error));
          return;
        }
      }
    }
    widget.workspace.removeDocument(document);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), showCloseIcon: true));
  }
}

enum _CloseChoice { save, discard, cancel }

class _ExternalChangeBanner extends StatelessWidget {
  const _ExternalChangeBanner({
    required this.document,
    required this.onReload,
    required this.onResolve,
  });

  final DocumentSession document;
  final VoidCallback onReload;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context);
    return Material(
      color: colors.surfaceMuted,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.borderSoft)),
        ),
        child: Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(AppIcons.info, size: 16, color: colors.accent),
            Text(
              '${document.name} changed on disk.',
              style: DesktopTypography.body.copyWith(
                color: colors.textSecondary,
              ),
            ),
            OutlinedButton(
              onPressed: onResolve,
              child: const Text('Resolve & Save'),
            ),
            FilledButton(onPressed: onReload, child: const Text('Reload')),
          ],
        ),
      ),
    );
  }
}

class _DropOverlay extends StatelessWidget {
  const _DropOverlay();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      key: const ValueKey('markdown-drop-overlay'),
      color: scheme.surface.withValues(alpha: .94),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.primary, width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(AppIcons.document, size: 42),
              const SizedBox(height: 12),
              Text(
                'Open Notes or Import an Image',
                style: DesktopTypography.title3.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Drop one image to insert at the current caret.\nDrop Markdown files to open them in tabs.',
                style: DesktopTypography.body,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocumentStatusBar extends StatelessWidget {
  const _DocumentStatusBar({required this.document, required this.workspace});
  final DocumentSession document;
  final WorkspaceController workspace;

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: document.controller,
      builder: (context, value, _) {
        final statistics = document.analysis.statistics(value.text);
        return Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 25),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.borderSoft)),
          ),
          child: DefaultTextStyle(
            style: DesktopTypography.subheadline.copyWith(
              color: colors.textTertiary,
            ),
            // A status footer must not consume the document's height at large
            // text scales. Keep all details reachable by horizontal scrolling,
            // with persistence and cloud state first rather than off-screen.
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text(workspace.persistenceStatus(document).label),
                  const SizedBox(width: 12),
                  DocumentSyncIndicator(controller: workspace.sync),
                  const SizedBox(width: 16),
                  Text('${statistics.words} words'),
                  const SizedBox(width: 14),
                  Text('${statistics.characters} characters'),
                  const SizedBox(width: 12),
                  Text(document.encoding),
                  const SizedBox(width: 12),
                  Text(document.lineEnding),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Match at event time, not build time: source/table IME may change without a
/// shell rebuild. Unavailable commands return false so other input handlers can
/// see the keystroke instead of having CallbackShortcuts swallow it.
class _WikiLinkActivator extends SingleActivator {
  _WikiLinkActivator(
    this.workspace, {
    super.meta = false,
    super.control = false,
  }) : super(LogicalKeyboardKey.keyK, shift: true, includeRepeats: false);
  final WorkspaceController workspace;
  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) =>
      super.accepts(event, state) &&
      workspace.activeDocument?.controller.mode !=
          IanvsMarkdownEditorMode.preview &&
      workspace.activeDocument != null &&
      !hasEditorComposition(workspace);
}
