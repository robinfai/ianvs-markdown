import '../app_localizations.dart';
import 'package:flutter/material.dart';
import '../models/conflict_diff.dart';

class SaveConflictDiffDialog extends StatelessWidget {
  SaveConflictDiffDialog({
    super.key,
    required String? disk,
    required String local,
  }) : deleted = disk == null,
       diff = ConflictDiff.compare(disk ?? '', local);
  final bool deleted;
  final ConflictDiff diff;

  @override
  Widget build(BuildContext context) => AlertDialog(
    constraints: const BoxConstraints(maxWidth: 1000),
    title: Text(appText(context, "Compare Changes")),
    content: SizedBox(
      width: 900,
      height: 500,
      child: ListView.builder(
        itemCount: diff.lines.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deleted
                        ? appText(
                            context,
                            "Disk file removed. + lines are your captured local version.",
                          )
                        : appText(
                            context,
                            "− Disk version    + Captured local version",
                          ),
                  ),
                  Text(
                    appText(
                      context,
                      "Read-only snapshot. Overwrite will recheck the disk before saving.",
                    ),
                  ),
                  if (diff.coarse)
                    Text(
                      appText(
                        context,
                        "Large changed region: showing complete removed and added lines.",
                      ),
                    ),
                ],
              ),
            );
          }
          final line = diff.lines[index - 1];

          final sign = switch (line.kind) {
            ConflictDiffKind.added => '+',
            ConflictDiffKind.removed => '−',
            _ => ' ',
          };
          final ending = line.text.endsWith('\r\n')
              ? 'CRLF'
              : line.text.endsWith('\n')
              ? 'LF'
              : line.text.endsWith('\r')
              ? 'CR'
              : 'No newline';
          final text = line.text.replaceFirst(RegExp(r'[\r\n]+$'), '');
          final description = switch (line.kind) {
            ConflictDiffKind.added => 'Added, local line ${line.localLine}',
            ConflictDiffKind.removed => 'Removed, disk line ${line.diskLine}',
            ConflictDiffKind.unchanged =>
              'Unchanged, disk line ${line.diskLine}, local line ${line.localLine}',
          };
          final color = switch (line.kind) {
            ConflictDiffKind.added => Colors.green.withValues(alpha: .12),
            ConflictDiffKind.removed => Colors.red.withValues(alpha: .12),
            _ => Colors.transparent,
          };
          return Semantics(
            container: true,
            excludeSemantics: true,
            label:
                '$description. ${text.isEmpty ? "Blank line" : text}. $ending',
            child: ColoredBox(
              color: color,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 95,
                      child: Text(
                        '${line.diskLine ?? "–"} / ${line.localLine ?? "–"}  $sign',
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        text,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(ending, style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(appText(context, "Back to conflict")),
      ),
    ],
  );
}
