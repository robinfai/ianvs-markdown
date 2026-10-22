import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

import '../services/attachment_repository.dart';
import '../services/attachment_resolver.dart';

/// Shared wiring for the desktop editor and iOS reader. The root must be the
/// user's opened workspace, never the parent of a separately opened note.
class DocumentAttachmentScope extends StatefulWidget {
  const DocumentAttachmentScope({
    super.key,
    required this.root,
    required this.documentPath,
    required this.builder,
    this.revision = 0,
    this.source = const AppleAttachmentSource(),
  });

  final String? root;
  final String? documentPath;
  final int revision;
  final AttachmentSource source;
  final Widget Function(BuildContext context, DocumentAttachmentBuilders images)
  builder;

  @override
  State<DocumentAttachmentScope> createState() =>
      _DocumentAttachmentScopeState();
}

class _DocumentAttachmentScopeState extends State<DocumentAttachmentScope>
    with WidgetsBindingObserver {
  late AttachmentRepository _repository;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _createRepository();
    // Metadata-only refresh catches image replacement, including subfolders
    // which the Markdown sidebar's non-recursive watchers do not observe.
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _repository.refresh();
      }
    });
  }

  void _createRepository() {
    _repository = AttachmentRepository(
      root: widget.root,
      source: widget.source,
    );
  }

  @override
  void didUpdateWidget(covariant DocumentAttachmentScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.root != oldWidget.root ||
        widget.documentPath != oldWidget.documentPath ||
        widget.source != oldWidget.source) {
      _repository.dispose();
      _createRepository();
    } else if (widget.revision != oldWidget.revision) {
      // Do not synchronously notify descendants while this ancestor builds.
      final repository = _repository;
      scheduleMicrotask(() {
        if (mounted && identical(repository, _repository)) repository.refresh();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _repository.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _AttachmentContext(
    repository: _repository,
    documentPath: widget.documentPath,
    child: widget.builder(
      context,
      DocumentAttachmentBuilders(_repository, widget.documentPath),
    ),
  );
}

// Rendered Markdown may retain its parsed child widgets while only host
// builders change. Depend on the live scope, not a captured old callback.
class _AttachmentContext extends InheritedWidget {
  const _AttachmentContext({
    required this.repository,
    required this.documentPath,
    required super.child,
  });
  final AttachmentRepository repository;
  final String? documentPath;
  @override
  bool updateShouldNotify(_AttachmentContext oldWidget) =>
      repository != oldWidget.repository ||
      documentPath != oldWidget.documentPath;
}

class DocumentAttachmentBuilders {
  const DocumentAttachmentBuilders(this.repository, this.documentPath);
  final AttachmentRepository repository;
  final String? documentPath;

  Widget image(Uri uri, String? title, String? alt) => DocumentAttachmentImage(
    repository: repository,
    documentPath: documentPath,
    target: uri.toString(),
    kind: AttachmentLinkKind.markdown,
    label: alt ?? title,
  );

  Widget wiki(
    BuildContext context,
    IanvsMarkdownWikiEmbedReference reference,
  ) => reference.isImageEmbed
      ? DocumentAttachmentImage(
          repository: repository,
          documentPath: documentPath,
          target: reference.target,
          kind: AttachmentLinkKind.wiki,
          label: reference.alias,
        )
      : Text(reference.displayLabel);
}

class DocumentAttachmentImage extends StatefulWidget {
  const DocumentAttachmentImage({
    super.key,
    required this.repository,
    required this.documentPath,
    required this.target,
    required this.kind,
    this.label,
  });

  final AttachmentRepository repository;
  final String? documentPath;
  final String target;
  final AttachmentLinkKind kind;
  final String? label;

  @override
  State<DocumentAttachmentImage> createState() =>
      _DocumentAttachmentImageState();
}

class _DocumentAttachmentImageState extends State<DocumentAttachmentImage> {
  AttachmentImageLease? _image;
  AttachmentFailure? _error;
  int _request = 0;
  AttachmentRepository? _repository;
  String? _documentPath;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind();
  }

  void _bind() {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_AttachmentContext>();
    final repository = scope?.repository ?? widget.repository;
    final documentPath = scope == null
        ? widget.documentPath
        : scope.documentPath;
    if (repository == _repository && documentPath == _documentPath) return;
    _repository?.removeListener(_reload);
    _repository = repository;
    _documentPath = documentPath;
    repository.addListener(_reload);
    _image?.dispose();
    _image = null;
    _error = null;
    _reload();
  }

  @override
  void didUpdateWidget(covariant DocumentAttachmentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.documentPath != widget.documentPath ||
        oldWidget.target != widget.target ||
        oldWidget.kind != widget.kind) {
      _bind();
      _image?.dispose();
      _image = null;
      _error = null;
      _reload();
    }
  }

  void _reload() {
    final request = ++_request;
    unawaited(() async {
      try {
        final image = await _repository!.load(
          documentPath: _documentPath,
          target: widget.target,
          kind: widget.kind,
        );
        if (!mounted || request != _request) {
          image.dispose();
          return;
        }
        setState(() {
          _image?.dispose();
          _image = image;
          _error = null;
        });
      } on Object catch (error) {
        if (!mounted || request != _request) return;
        final failure = attachmentFailure(error);
        if (failure.kind == AttachmentFailureKind.cancelled) return;
        setState(() {
          _image?.dispose();
          _image = null;
          _error = failure;
        });
      }
    }());
  }

  @override
  void dispose() {
    ++_request;
    _repository?.removeListener(_reload);
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_image case final image?) {
      return Semantics(
        image: true,
        label: widget.label ?? 'Image attachment',
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 2048, maxHeight: 2048),
          child: RawImage(image: image.image, fit: BoxFit.contain),
        ),
      );
    }
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          const Icon(Icons.image_outlined, size: 20),
          Text(_error?.message ?? 'Loading image…'),
          if (_error != null &&
              !{
                AttachmentFailureKind.needsFolder,
                AttachmentFailureKind.unsupported,
                AttachmentFailureKind.invalid,
              }.contains(_error!.kind))
            TextButton(
              onPressed: _repository!.refresh,
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}
