import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

String paletteNoteTitle(String source, String fallback) {
  final metadata = parseMarkdownFrontMatter(source);
  for (final entry in metadata.entries) {
    if (entry.key == 'title' && entry.value.trim().isNotEmpty) {
      return entry.value.trim();
    }
  }
  final heading = RegExp(
    r'^# +(.+)$',
    multiLine: true,
  ).firstMatch(metadata.body);
  return heading?.group(1)?.trim() ?? fallback;
}

class WorkspacePaletteEntry {
  const WorkspacePaletteEntry({
    required this.id,
    required this.title,
    this.detail = '',
    this.searchTerms = '',
    this.recency = 0,
  });

  final String id;
  final String title;
  final String detail;
  final String searchTerms;
  final int recency;
}

class WorkspacePaletteSelection {
  const WorkspacePaletteSelection(this.id, {this.create = false});
  final String id;
  final bool create;
}

/// One keyboard interaction model for commands and note navigation.
class WorkspacePalette extends StatefulWidget {
  const WorkspacePalette({
    super.key,
    required this.title,
    required this.entries,
    this.allowCreate = false,
    this.notice,
  });

  final String title;
  final List<WorkspacePaletteEntry> entries;
  final bool allowCreate;
  final String? notice;

  @override
  State<WorkspacePalette> createState() => _WorkspacePaletteState();
}

class _WorkspacePaletteState extends State<WorkspacePalette> {
  final _query = TextEditingController();
  final _scroll = ScrollController();
  int _selected = 0;

  bool get _composing =>
      _query.value.composing.isValid && !_query.value.composing.isCollapsed;

  List<WorkspacePaletteEntry> get _matches {
    final words = _query.text.trim().toLowerCase().split(RegExp(r'\s+'));
    final entries = widget.entries.where((entry) {
      final text = '${entry.title} ${entry.detail} ${entry.searchTerms}'
          .toLowerCase();
      return words.every(text.contains);
    }).toList();
    entries.sort((a, b) {
      final recent = b.recency.compareTo(a.recency);
      return recent != 0 ? recent : a.title.compareTo(b.title);
    });
    return entries;
  }

  void _choose(WorkspacePaletteEntry entry) {
    if (!_composing) {
      Navigator.pop(context, WorkspacePaletteSelection(entry.id));
    }
  }

  void _create() {
    if (!_composing && _query.text.trim().isNotEmpty) {
      Navigator.pop(
        context,
        WorkspacePaletteSelection(_query.text.trim(), create: true),
      );
    }
  }

  void _move(int delta) {
    if (_composing) return;
    final entries = _matches;
    if (entries.isEmpty) return;
    setState(
      () => _selected = (_selected + delta).clamp(0, entries.length - 1),
    );
    if (_scroll.hasClients) {
      _scroll.jumpTo(
        (_selected * 64.0).clamp(0, _scroll.position.maxScrollExtent),
      );
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _matches;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 560,
        height: 400,
        child: Column(
          children: [
            CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                    _move(1),
                const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                    _move(-1),
              },
              child: TextField(
                key: const ValueKey('workspace-palette-query'),
                controller: _query,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Search'),
                onChanged: (_) => setState(() => _selected = 0),
                onSubmitted: (_) {
                  if (entries.isNotEmpty) {
                    _choose(entries[_selected.clamp(0, entries.length - 1)]);
                  } else if (widget.allowCreate) {
                    _create();
                  }
                },
              ),
            ),
            if (widget.notice != null) Text(widget.notice!),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                itemExtent: 64,
                itemCount: entries.length,
                itemBuilder: (context, i) => ListTile(
                  selected: i == _selected,
                  title: Text(entries[i].title, maxLines: 1),
                  subtitle: Text(entries[i].detail, maxLines: 1),
                  onTap: () => _choose(entries[i]),
                ),
              ),
            ),
            if (entries.isEmpty)
              if (widget.allowCreate && _query.text.trim().isNotEmpty)
                TextButton(
                  onPressed: _create,
                  child: Text('Create “${_query.text.trim()}”'),
                )
              else
                const Text('No matching results'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
