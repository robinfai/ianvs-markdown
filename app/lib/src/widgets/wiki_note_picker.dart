import 'package:flutter/material.dart';
import '../services/wiki_note_resolver.dart';
import '../services/attachment_repository.dart';

/// Both ambiguity and insertion show full vault-relative names, never a hidden
/// arbitrary winner. This picker filters metadata locally and never reads text.
class WikiNotePicker extends StatefulWidget {
  const WikiNotePicker({
    super.key,
    required this.notes,
    required this.title,
    this.initialQuery = '',
    this.notice,
    this.normalize,
  });
  final List<WikiNoteCandidate> notes;
  final String title;
  final String initialQuery;
  final String? notice;
  final WikiPathNormalizer? normalize;
  @override
  State<WikiNotePicker> createState() => _WikiNotePickerState();
}

class _WikiNotePickerState extends State<WikiNotePicker> {
  late final _query = TextEditingController(text: widget.initialQuery)
    ..addListener(_changed);
  String _comparisonQuery = '';
  int _generation = 0;
  bool _normalizationIssue = false;
  @override
  void initState() {
    super.initState();
    _changed();
  }

  void _changed() async {
    final generation = ++_generation;
    final raw = _query.text.toLowerCase().replaceFirst(RegExp(r'^/'), '');
    _comparisonQuery = raw;
    _normalizationIssue = false;
    if (mounted) setState(() {});
    if (raw.codeUnits.every((c) => c < 128) ||
        (_query.value.composing.isValid &&
            !_query.value.composing.isCollapsed)) {
      return;
    }
    try {
      final values =
          await (widget.normalize ?? const AppleAttachmentSource().normalize)([
            raw,
          ]);
      if (!mounted || generation != _generation) return;
      if (values.length != 1) throw StateError('Normalization unavailable');
      setState(() => _comparisonQuery = values.single);
    } on Object {
      if (mounted && generation == _generation) {
        setState(() => _normalizationIssue = true);
      }
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final composing =
        _query.value.composing.isValid && !_query.value.composing.isCollapsed;
    final query = _comparisonQuery;
    final matches = widget.notes
        .where(
          (n) =>
              n.comparisonPath.contains(query) ||
              n.relativePath.toLowerCase().contains(query),
        )
        .toList();
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 560,
        height: 420,
        child: CustomScrollView(
          key: const ValueKey('wiki-note-scroll'),
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const ValueKey('wiki-note-query'),
                    controller: _query,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Filter notes by path',
                    ),
                    onSubmitted: (_) {
                      if (!composing && matches.length == 1) {
                        Navigator.pop(context, matches.single);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.notice ??
                        'Current workspace .md notes only. YAML aliases, heading and block targets are not available yet.',
                  ),
                  if (_normalizationIssue)
                    const Text(
                      'Unicode normalization is unavailable. Some matches may be missing.',
                    ),
                  if (matches.length > 100)
                    const Text(
                      'Showing the first 100 notes. Narrow the filter to see others.',
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            if (matches.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('No matching notes.')),
              )
            else
              SliverList.builder(
                itemCount: matches.length > 100 ? 100 : matches.length,
                itemBuilder: (context, i) {
                  final note = matches[i];
                  return ListTile(
                    key: ValueKey('wiki-note-${note.relativePath}'),
                    title: Text(note.relativePath),
                    subtitle: Text(
                      note.sessionId != null
                          ? 'Open buffer'
                          : note.metadata?.local == false
                          ? 'Not locally available'
                          : 'Workspace note',
                    ),
                    enabled: !composing,
                    onTap: () => Navigator.pop(context, note),
                  );
                },
              ),
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
