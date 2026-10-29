import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/workspace_controller.dart';
import '../models/document_session.dart';
import '../services/note_collections.dart';
import '../services/workspace_reference_index.dart';

class NoteCollectionDialog extends StatefulWidget {
  const NoteCollectionDialog({
    super.key,
    required this.workspace,
    required this.onSave,
    this.view = const {},
  });
  final WorkspaceController workspace;
  final Future<bool> Function(DocumentSession) onSave;
  final Map<String, Object?> view;

  @override
  State<NoteCollectionDialog> createState() => _NoteCollectionDialogState();
}

class _NoteCollectionDialogState extends State<NoteCollectionDialog> {
  late final _name = TextEditingController(
    text: widget.view['name'] as String? ?? 'New collection',
  );
  late final _folder = TextEditingController(
    text: widget.view['folder'] as String? ?? '',
  );
  late final _tag = TextEditingController(
    text: widget.view['tag'] as String? ?? '',
  );
  late final _property = TextEditingController(
    text: widget.view['property'] as String? ?? '',
  );
  late final _equals = TextEditingController(
    text: widget.view['equals'] as String? ?? '',
  );
  late final _columns = TextEditingController(
    text: widget.view['columns'] as String? ?? 'title,status,date,category',
  );
  late String _layout = widget.view['layout'] as String? ?? 'table';
  late String _sort = widget.view['sort'] as String? ?? 'filename';
  late bool _descending = widget.view['descending'] as bool? ?? false;
  late final _epoch = widget.workspace.index.epoch;
  WorkspaceReferenceSnapshot? _snapshot;
  String? _notice;
  bool _busy = false;

  bool get _current => mounted && widget.workspace.index.epoch == _epoch;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _folder,
      _tag,
      _property,
      _equals,
      _columns,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final snapshot = await widget.workspace.references.refresh(
        refreshMetadata: true,
      );
      if (_current) setState(() => _snapshot = snapshot);
    } on Object catch (error) {
      if (mounted) setState(() => _notice = '$error');
    }
  }

  Future<void> _saveView() async {
    if (!_current || _name.text.trim().isEmpty) return;
    try {
      await widget.workspace.saveCollectionView({
        'name': _name.text.trim(),
        'folder': _folder.text.trim(),
        'tag': _tag.text.trim(),
        'property': _property.text.trim(),
        'equals': _equals.text,
        'columns': _columns.text,
        'layout': _layout,
        'sort': _sort,
        'descending': _descending,
      });
      if (mounted) setState(() => _notice = 'View saved in the sidebar.');
    } on Object catch (error) {
      if (mounted) setState(() => _notice = 'View could not be saved: $error');
    }
  }

  Future<void> _open(CollectionNote row) async {
    if (!_current || _busy) return;
    try {
      final note = await widget.workspace.openIndexedNote(
        row.relativePath,
        epoch: _epoch,
        isCurrent: () => _current,
      );
      if (mounted && _current && note != null) Navigator.pop(context);
    } on Object catch (error) {
      if (mounted) setState(() => _notice = 'Unable to open note: $error');
    }
  }

  Future<void> _edit(
    CollectionNote row,
    String key, {
    String? replacement,
  }) async {
    if (!_current || _busy || key == 'filename') return;
    String? value = replacement;
    if (value == null) {
      final entry = row.properties[key];
      final input = TextEditingController(
        text: collectionPropertyEditValue(row.note.source.text, key),
      );
      try {
        value = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Edit $key'),
            content: TextField(
              key: const ValueKey('collection-property-input'),
              controller: input,
              autofocus: true,
              decoration: InputDecoration(
                helperText:
                    'Type: ${entry?.type.name ?? 'text'}. Lists use a JSON string array.',
              ),
              onSubmitted: (text) => Navigator.pop(context, text),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, input.text),
                child: const Text('Save property'),
              ),
            ],
          ),
        );
      } finally {
        input.dispose();
      }
    }
    if (!_current || value == null) return;
    setState(() => _busy = true);
    final workspace = widget.workspace;
    final origin = workspace.activeDocument;
    DocumentSession? document;
    try {
      final before = row.note.source.text;
      final after = editCollectionProperty(before, key, value);
      if (after == before && value == collectionPropertyEditValue(before, key)) return;
      if (after == before && value != collectionPropertyEditValue(before, key)) {
        throw const FormatException(
          'This value cannot be edited safely. Use Source mode.',
        );
      }
      document = await workspace.openIndexedNote(
        row.relativePath,
        epoch: _epoch,
        isCurrent: () => _current,
      );
      if (!_current || document == null) return;
      if (document.controller.text != before) {
        throw StateError(
          'Note changed. Refresh the collection before editing.',
        );
      }
      // Property edits are explicit source operations, also available from Read.
      document.controller.commitHistoryGroup();
      document.controller.value = TextEditingValue(
        text: after,
        selection: const TextSelection.collapsed(offset: 0),
      );
      document.controller.commitHistoryGroup();
      final saved = await widget.onSave(document);
      if (_current)
        setState(
          () => _notice = saved
              ? 'Property saved.'
              : 'Property is unsaved in the open note.',
        );
      await _refresh();
    } on Object catch (error) {
      if (mounted) setState(() => _notice = 'Property was not saved: $error');
    } finally {
      if (_current &&
          document != null &&
          identical(workspace.activeDocument, document) &&
          origin != null &&
          workspace.documents.contains(origin)) {
        workspace.selectDocument(workspace.documents.indexOf(origin));
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    double width = 160,
  }) => SizedBox(
    width: width,
    child: TextField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => setState(() {}),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final root = widget.workspace.workspaceRoot;
    final snapshot = _snapshot;
    final columns = [
      'filename',
      ..._columns.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && s != 'filename'),
    ].toSet().toList();
    final rows = snapshot == null || root == null || !_current
        ? <CollectionNote>[]
        : collectionNotes(
            snapshot,
            root,
            folder: _folder.text.trim(),
            tag: _tag.text.trim(),
            property: _property.text.trim(),
            equals: _equals.text,
            sort: _sort,
            descending: _descending,
          );
    return Dialog(
      child: SizedBox(
        width: 1100,
        height: 720,
        child: Column(
          children: [
            ListTile(
              title: const Text('Note collections'),
              trailing: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 12,
                children: [
                  _field('View name', _name),
                  _field('Folder', _folder),
                  _field('Tag', _tag),
                  _field('Property', _property),
                  _field('Equals', _equals),
                  _field('Columns (comma separated)', _columns, width: 300),
                ],
              ),
            ),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final layout in ['list', 'table', 'board'])
                  ChoiceChip(
                    label: Text(layout),
                    selected: _layout == layout,
                    onSelected: (_) => setState(() => _layout = layout),
                  ),
                DropdownButton<String>(
                  value: columns.contains(_sort) ? _sort : 'filename',
                  items: [
                    for (final column in columns)
                      DropdownMenuItem(
                        value: column,
                        child: Text('Sort: $column'),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _sort = value ?? 'filename'),
                ),
                IconButton(
                  tooltip: 'Reverse sort',
                  onPressed: () => setState(() => _descending = !_descending),
                  icon: const Icon(Icons.swap_vert),
                ),
                TextButton(
                  onPressed: _saveView,
                  child: const Text('Save view'),
                ),
                TextButton(onPressed: _refresh, child: const Text('Refresh')),
                if (widget.view['name'] is String)
                  TextButton(
                    onPressed: () async {
                      if (!_current) return;
                      await widget.workspace.deleteCollectionView(
                        widget.view['name'] as String,
                      );
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text('Delete view'),
                  ),
              ],
            ),
            if (_notice != null) Text(_notice!),
            if (!_current)
              const Text('Workspace changed. Close and reopen this view.'),
            if (snapshot != null && !snapshot.complete)
              const Text(
                'Index incomplete: only locally available indexed notes are shown.',
              ),
            Text('${rows.length} notes'),
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              child: _layout == 'board'
                  ? _board(rows)
                  : _layout == 'list'
                  ? _list(rows)
                  : _table(rows, columns),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(List<CollectionNote> rows) => ListView(
    children: [
      for (final row in rows)
        ListTile(
          title: Text(
            row.value('title').isEmpty ? row.relativePath : row.value('title'),
          ),
          subtitle: Text('${row.relativePath} · ${row.value('status')}'),
          onTap: () => _open(row),
          trailing: IconButton(
            tooltip: 'Edit status',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _edit(row, 'status'),
          ),
        ),
    ],
  );

  Widget _table(List<CollectionNote> rows, List<String> columns) =>
      SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              for (final column in columns) DataColumn(label: Text(column)),
            ],
            rows: [
              for (final row in rows)
                DataRow(
                  cells: [
                    for (final column in columns)
                      DataCell(
                        Text(
                          row.value(column).isEmpty ? '—' : row.value(column),
                        ),
                        onTap: column == 'filename'
                            ? () => _open(row)
                            : () => _edit(row, column),
                      ),
                  ],
                ),
            ],
          ),
        ),
      );

  Widget _board(List<CollectionNote> rows) {
    final statuses = {
      '',
      'idea',
      'draft',
      'published',
      for (final row in rows) row.value('status'),
    };
    return ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final status in statuses)
          SizedBox(
            width: 240,
            child: DragTarget<CollectionNote>(
              onWillAcceptWithDetails: (_) => !_busy && _current,
              onAcceptWithDetails: (details) =>
                  unawaited(_edit(details.data, 'status', replacement: status)),
              builder: (context, candidates, rejected) => Card(
                color: candidates.isEmpty
                    ? null
                    : Theme.of(context).colorScheme.primaryContainer,
                child: Column(
                  children: [
                    ListTile(
                      title: Text(status.isEmpty ? 'No status' : status),
                    ),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final row in rows.where(
                            (row) => row.value('status') == status,
                          ))
                            LongPressDraggable<CollectionNote>(
                              data: row,
                              feedback: Material(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(row.relativePath),
                                ),
                              ),
                              child: ListTile(
                                title: Text(
                                  row.value('title').isEmpty
                                      ? row.relativePath
                                      : row.value('title'),
                                ),
                                onTap: () => _open(row),
                                trailing: IconButton(
                                  tooltip: 'Edit status',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _edit(row, 'status'),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
