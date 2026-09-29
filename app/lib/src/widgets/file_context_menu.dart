import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/markdown_file_service.dart';

class FileMenuAction {
  const FileMenuAction(this.label, this.run, {this.destructive = false});

  final String label;
  final FutureOr<void> Function() run;
  final bool destructive;
}

/// Shared secondary-click menu for file rows, folders, and document tabs.
class FileContextMenu extends StatefulWidget {
  const FileContextMenu({
    super.key,
    required this.path,
    required this.child,
    this.actions = const [],
    this.onShow,
  });

  final String? path;
  final VoidCallback? onShow;
  final Widget child;
  final List<FileMenuAction> actions;

  static const channel = MethodChannel('work.ianvs.linefold/file_access');

  @override
  State<FileContextMenu> createState() => _FileContextMenuState();
}

class _FileContextMenuState extends State<FileContextMenu> {
  bool _controlPressed = HardwareKeyboard.instance.isControlPressed;
  bool _menuOpen = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_keyboardChanged);
  }

  bool _keyboardChanged(KeyEvent event) {
    final pressed = HardwareKeyboard.instance.isControlPressed;
    if (pressed != _controlPressed) setState(() => _controlPressed = pressed);
    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_keyboardChanged);
    super.dispose();
  }

  Future<void> _show(BuildContext context, Offset position) async {
    if (_menuOpen) return;
    widget.onShow?.call();
    final actions = widget.actions
        .where((action) => !action.destructive)
        .toList();
    final destructive = widget.actions
        .where((action) => action.destructive)
        .toList();
    final entries = <FileMenuAction>[
      ...actions,
      if (widget.path case final path?) ...[
        if (Platform.isMacOS)
          FileMenuAction('Reveal in Finder', () async {
            await FileContextMenu.channel.invokeMethod<void>('revealInFinder', {
              'path': path,
            });
          }),
        FileMenuAction(
          'Copy Path',
          () => Clipboard.setData(ClipboardData(text: path)),
        ),
      ],
      ...destructive,
    ];
    if (entries.isEmpty) return;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final local = overlay.globalToLocal(position);
    _menuOpen = true;
    final selected = await showMenu<FileMenuAction>(
      context: context,
      position: RelativeRect.fromSize(local & Size.zero, overlay.size),
      items: [
        for (var i = 0; i < entries.length; i++) ...[
          if ((i == actions.length && actions.isNotEmpty) ||
              (i > 0 && entries[i].destructive && !entries[i - 1].destructive))
            const PopupMenuDivider(),
          PopupMenuItem(
            value: entries[i],
            height: 32,
            child: Text(
              entries[i].label,
              style: entries[i].destructive
                  ? TextStyle(color: Theme.of(context).colorScheme.error)
                  : null,
            ),
          ),
        ],
      ],
    );
    _menuOpen = false;
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
  Widget build(BuildContext context) {
    final controlClick =
        Theme.of(context).platform == TargetPlatform.macOS && _controlPressed;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapUp: (details) => _show(context, details.globalPosition),
      onTapUp: controlClick
          ? (details) => _show(context, details.globalPosition)
          : null,
      // Let the menu own Control-click before a nested row, tab or button can
      // activate. Other modifiers preserve the child's normal selection input.
      child: IgnorePointer(ignoring: controlClick, child: widget.child),
    );
  }
}
