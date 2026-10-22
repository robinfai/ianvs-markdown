import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../controllers/workspace_search_controller.dart';
import '../services/workspace_index_source.dart';

class WorkspaceSearchDialog extends StatefulWidget {
  const WorkspaceSearchDialog({super.key, required this.controller});
  final WorkspaceSearchController controller;
  @override
  State<WorkspaceSearchDialog> createState() => _WorkspaceSearchDialogState();
}

class _WorkspaceSearchDialogState extends State<WorkspaceSearchDialog> {
  late final _query = TextEditingController(text: widget.controller.query);
  bool _composing = false;
  @override
  void initState() {
    super.initState();
    _query.addListener(_queryChanged);
  }

  void _queryChanged() {
    final range = _query.value.composing;
    final composing = range.isValid && !range.isCollapsed;
    final wasComposing = _composing;
    if (composing != _composing) setState(() => _composing = composing);
    if (composing) {
      if (!wasComposing) widget.controller.cancel();
    } else if (wasComposing || _query.text != widget.controller.query) {
      widget.controller.search(_query.text);
    }
  }

  @override
  void dispose() {
    _query.removeListener(_queryChanged);
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_composing,
    child: Dialog(
      key: const ValueKey('workspace-source-search-dialog'),
      child: SizedBox(
        width: 720,
        height: 560,
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            final search = widget.controller;
            final root = search.index.root;
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Search Markdown Source',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close source search',
                        onPressed: _composing
                            ? null
                            : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Text(
                    root == null
                        ? 'Open buffers only. No folder is scanned.'
                        : '${p.basename(root)} + open buffers · local files only',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey('workspace-source-query'),
                    controller: _query,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText:
                          'Literal text, including code and Markdown syntax',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('Match case'),
                        selected: search.matchCase,
                        onSelected: _composing
                            ? null
                            : (value) =>
                                  search.search(_query.text, matchCase: value),
                      ),
                      TextButton.icon(
                        onPressed: _composing || search.query.isEmpty
                            ? null
                            : () => search.search(
                                _query.text,
                                immediate: true,
                                refresh: true,
                              ),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Refresh metadata'),
                      ),
                      if (search.searching)
                        TextButton(
                          onPressed: search.cancel,
                          child: const Text('Cancel'),
                        ),
                    ],
                  ),
                  if (_composing)
                    const Text('Finish composing to search or open a result.'),
                  if (search.searching) const LinearProgressIndicator(),
                  const SizedBox(height: 6),
                  Text(
                    search.query.isEmpty
                        ? 'Searches source, not rendered text. Cloud-only files are not downloaded.'
                        : '${search.searching ? 'Searching · ' : ''}${search.scanned}/${search.known} known documents searched · ${search.matchCount} matches${search.displayLimited ? ' · showing first ${search.results.length}' : ''}',
                    key: const ValueKey('workspace-source-progress'),
                  ),
                  if (search.error case final error?)
                    Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (search.partial)
                    Text(
                      'Incomplete search: ${[if (search.cancelled) 'cancelled', for (final entry in search.issues.entries) '${entry.value} ${_issueLabel(entry.key)}'].join(', ')}. Results do not include all source.',
                      key: const ValueKey('workspace-source-partial'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (root != null)
                    Text(
                      'Metadata is reconciled on search/refresh. File providers are not guaranteed to update live.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: search.results.isEmpty
                        ? Center(
                            child: Text(
                              search.query.isEmpty
                                  ? 'Enter text to search.'
                                  : search.searching
                                  ? 'Searching local source…'
                                  : search.partial
                                  ? 'No matches in the source that could be searched.'
                                  : 'No matches.',
                            ),
                          )
                        : ListView.builder(
                            itemCount: search.results.length,
                            itemBuilder: (context, i) {
                              final match = search.results[i];
                              final path = match.path;
                              final label = path == null
                                  ? match.name
                                  : root != null && p.isWithin(root, path)
                                  ? p.relative(path, from: root)
                                  : path;
                              return ListTile(
                                key: ValueKey('workspace-source-result-$i'),
                                dense: true,
                                title: Text(
                                  '$label:${match.line}${match.sessionId != null ? ' · buffer' : ''}${match.externalConflict ? ' · external conflict' : ''}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  match.snippet,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: _composing
                                    ? null
                                    : () => Navigator.of(context).pop(match),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}

String _issueLabel(WorkspaceReadIssue issue) => switch (issue) {
  WorkspaceReadIssue.offline => 'cloud-only/offline',
  WorkspaceReadIssue.denied => 'denied',
  WorkspaceReadIssue.oversized => 'over 5 MiB',
  WorkspaceReadIssue.invalid => 'unsupported text',
  WorkspaceReadIssue.missing => 'missing',
  WorkspaceReadIssue.unavailable => 'unavailable',
  WorkspaceReadIssue.changed => 'changed during search',
  WorkspaceReadIssue.limit => 'incomplete folders or metadata limits',
  WorkspaceReadIssue.cancelled => 'cancelled',
};
