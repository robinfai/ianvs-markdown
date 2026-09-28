import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/markdown_file_service.dart';

class FileMenuAction {
  const FileMenuAction(this.label, this.run);

  final String label;
  final FutureOr<void> Function() run;
}

/// Shared secondary-click menu for file rows, folders, and document tabs.
class FileContextMenu extends StatelessWidget {
  const FileContextMenu({
    super.key,
    required this.path,
    required this.child,
    this.actions = const [],
  });

  final String? path;
  final Widget child;
  final List<FileMenuAction> actions;

  static const channel = MethodChannel('work.ianvs.linefold/file_access');

  Future<void> _show(BuildContext context, Offset position) async {
    final entries = <FileMenuAction>[
      ...actions,
      if (path case final path?) ...[
        if (Platform.isMacOS)
          FileMenuAction('Reveal in Finder', () async {
            await channel.invokeMethod<void>('revealInFinder', {'path': path});
          }),
        FileMenuAction(
          'Copy Path',
          () => Clipboard.setData(ClipboardData(text: path)),
        ),
      ],
    ];
    if (entries.isEmpty) return;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final local = overlay.globalToLocal(position);
    final selected = await showMenu<FileMenuAction>(
      context: context,
      position: RelativeRect.fromSize(local & Size.zero, overlay.size),
      items: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i == actions.length && actions.isNotEmpty)
            const PopupMenuDivider(),
          PopupMenuItem(
            value: entries[i],
            height: 32,
            child: Text(entries[i].label),
          ),
        ],
      ],
    );
    if (selected == null || !context.mounted) return;
    // Capture the messenger before an action potentially removes this tab.
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await selected.run();
    } catch (error) {
      if (messenger?.mounted ?? false) {
        messenger!.showSnackBar(
          SnackBar(
            content: Text(describeFileError(error)),
            showCloseIcon: true,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onSecondaryTapUp: (details) => _show(context, details.globalPosition),
    child: child,
  );
}
