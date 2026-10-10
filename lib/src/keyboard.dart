// Raw events are still required for macOS accessibility-generated modifiers.
// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Commands supplied by the Markdown components. Text navigation, IME input,
/// and control-specific arrow/Enter behavior remain platform operations.
enum IanvsMarkdownCommand {
  undo,
  redo,
  bold,
  italic,
  insertLink,
  deleteLine,
  save,
  togglePreview,
  livePreview,
  source,
  reading,
  indent,
  outdent,
  selectAll,
  copy,
  cut,
  paste,
}

/// Configures shortcuts for focused Markdown components below this widget.
///
/// Each [bindings] entry replaces that command's default bindings. An empty
/// list disables its keyboard invocation. Removed default keys are consumed;
/// put a key in [hostShortcuts] to give it an explicit host action instead.
/// Host shortcuts take precedence, then explicit bindings, then unchanged
/// defaults. Two explicit commands cannot share a key combination.
///
/// The nearest scope replaces outer configuration. Other controls in the
/// subtree are unaffected. Configured commands and host actions are suppressed
/// while the focused text field is composing. Keep the maps/lists immutable
/// and replace the widget's configuration when updating it.
class IanvsMarkdownShortcuts extends StatefulWidget {
  const IanvsMarkdownShortcuts({
    super.key,
    this.bindings = const {},
    this.hostShortcuts = const {},
    required this.child,
  });

  final Map<IanvsMarkdownCommand, List<SingleActivator>> bindings;
  final Map<SingleActivator, VoidCallback> hostShortcuts;
  final Widget child;

  /// Display label for the first available binding, or empty when disabled.
  /// This does not imply that the command is enabled in the current mode.
  static String labelOf(BuildContext context, IanvsMarkdownCommand command) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_MarkdownShortcutScopeData>()
        ?.state;
    final platform = Theme.of(context).platform;
    final candidates =
        scope?.widget.bindings[command] ??
        defaultMarkdownBindings(command, platform);
    for (final binding in candidates) {
      if (scope?.widget.hostShortcuts.keys.any(
            (host) => _overlap(host, binding),
          ) ??
          false) {
        continue;
      }
      if (scope?.widget.bindings.entries.any(
            (entry) =>
                entry.key != command &&
                entry.value.any((other) => _overlap(other, binding)),
          ) ??
          false) {
        continue;
      }
      final apple =
          platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;
      return [
        if (binding.control) apple ? '⌃' : 'Ctrl+',
        if (binding.alt) apple ? '⌥' : 'Alt+',
        if (binding.shift) apple ? '⇧' : 'Shift+',
        if (binding.meta) apple ? '⌘' : 'Meta+',
        binding.trigger.keyLabel,
      ].join();
    }
    return '';
  }

  @override
  State<IanvsMarkdownShortcuts> createState() => _IanvsMarkdownShortcutsState();
}

class _IanvsMarkdownShortcutsState extends State<IanvsMarkdownShortcuts> {
  RawKeyEvent? _ownedRawEvent;

  @override
  void initState() {
    super.initState();
    _validate();
    FocusManager.instance.addEarlyKeyEventHandler(_handleKey);
    RawKeyboard.instance.addListener(_handleRawKey);
  }

  @override
  void didUpdateWidget(IanvsMarkdownShortcuts oldWidget) {
    super.didUpdateWidget(oldWidget);
    _validate();
  }

  void _validate() {
    final commands = widget.bindings.entries.toList();
    for (var i = 0; i < commands.length; i++) {
      for (var j = i + 1; j < commands.length; j++) {
        if (commands[i].value.any(
          (a) => commands[j].value.any((b) => _overlap(a, b)),
        )) {
          throw ArgumentError(
            'Markdown shortcut shared by '
            '${commands[i].key.name} and ${commands[j].key.name}',
          );
        }
      }
    }
    final host = widget.hostShortcuts.keys.toList();
    for (var i = 0; i < host.length; i++) {
      for (var j = i + 1; j < host.length; j++) {
        if (_overlap(host[i], host[j])) {
          throw ArgumentError('Overlapping Markdown host shortcuts');
        }
      }
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_handleKey);
    RawKeyboard.instance.removeListener(_handleRawKey);
    super.dispose();
  }

  _ShortcutRoute? _route(
    _MarkdownKey key,
    MarkdownCommandKind kind,
    TargetPlatform platform,
  ) {
    for (final entry in widget.hostShortcuts.entries) {
      if (key.matches(entry.key)) {
        return _ShortcutRoute(entry.key, host: entry.value);
      }
    }
    for (final entry in widget.bindings.entries) {
      for (final binding in entry.value) {
        if (key.matches(binding)) {
          return _ShortcutRoute(binding, command: entry.key);
        }
      }
    }
    for (final command in widget.bindings.keys) {
      for (final binding in defaultMarkdownBindings(
        command,
        platform,
        kind: kind,
      )) {
        if (key.matches(binding)) return _ShortcutRoute(binding);
      }
    }
    return null;
  }

  KeyEventResult _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final focused = _focusedMarkdownScope();
    if (focused == null || focused.scope != this) {
      return KeyEventResult.ignored;
    }
    if (_ownedRawEvent?.physicalKey == event.physicalKey) {
      return KeyEventResult.handled;
    }
    if (event.synthesized) return KeyEventResult.ignored;
    return _dispatch(_MarkdownKey.event(event), focused);
  }

  void _handleRawKey(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return;
    final focused = _focusedMarkdownScope();
    if (focused == null || focused.scope != this) return;
    final key = _MarkdownKey.raw(event);
    if (_route(key, focused.kind, focused.platform) == null) return;
    // RawKeyboard runs before HardwareKeyboard and FocusManager. Retain this
    // identity for their duplicate paths, including raw-only key messages.
    _ownedRawEvent = event;
    scheduleMicrotask(() {
      if (identical(_ownedRawEvent, event)) _ownedRawEvent = null;
    });
    _dispatch(key, focused);
  }

  KeyEventResult _dispatch(_MarkdownKey key, _FocusedMarkdown focused) {
    final route = _route(key, focused.kind, focused.platform);
    if (route == null) return KeyEventResult.ignored;
    final editable = focused.context
        .findAncestorStateOfType<EditableTextState>();
    final composing = editable?.widget.controller.value.composing;
    if (composing != null && composing.isValid && !composing.isCollapsed) {
      return KeyEventResult.handled;
    }
    if (key.repeat && !route.binding.includeRepeats) {
      return KeyEventResult.handled;
    }
    if (route.host != null) {
      route.host!();
    } else if (route.command case final command?) {
      for (final target in focused.targets) {
        if (!focused.context.mounted) break;
        if (target.onCommand(command, focused.context)) break;
      }
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) =>
      _MarkdownShortcutScopeData(state: this, child: widget.child);
}

class _MarkdownShortcutScopeData extends InheritedWidget {
  const _MarkdownShortcutScopeData({required this.state, required super.child});
  final _IanvsMarkdownShortcutsState state;
  @override
  bool updateShouldNotify(_MarkdownShortcutScopeData oldWidget) => true;
}

class _ShortcutRoute {
  const _ShortcutRoute(this.binding, {this.command, this.host});
  final SingleActivator binding;
  final IanvsMarkdownCommand? command;
  final VoidCallback? host;
}

class _MarkdownKey {
  const _MarkdownKey(
    this.key,
    this.control,
    this.meta,
    this.alt,
    this.shift,
    this.repeat,
  );
  factory _MarkdownKey.event(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    return _MarkdownKey(
      event.logicalKey,
      keyboard.isControlPressed,
      keyboard.isMetaPressed,
      keyboard.isAltPressed,
      keyboard.isShiftPressed,
      event is KeyRepeatEvent,
    );
  }
  factory _MarkdownKey.raw(RawKeyDownEvent event) => _MarkdownKey(
    event.logicalKey,
    event.isControlPressed,
    event.isMetaPressed,
    event.isAltPressed,
    event.isShiftPressed,
    event.repeat,
  );
  final LogicalKeyboardKey key;
  final bool control, meta, alt, shift, repeat;
  bool matches(SingleActivator binding) =>
      key == binding.trigger &&
      control == binding.control &&
      meta == binding.meta &&
      alt == binding.alt &&
      shift == binding.shift &&
      (binding.numLock == LockState.ignored ||
          (binding.numLock == LockState.locked) ==
              HardwareKeyboard.instance.lockModesEnabled.contains(
                KeyboardLockMode.numLock,
              ));
}

bool _overlap(SingleActivator a, SingleActivator b) =>
    a.trigger == b.trigger &&
    a.control == b.control &&
    a.meta == b.meta &&
    a.alt == b.alt &&
    a.shift == b.shift &&
    (a.numLock == b.numLock ||
        a.numLock == LockState.ignored ||
        b.numLock == LockState.ignored);

enum MarkdownCommandKind { editor, source, live, table, property, reading }

bool markdownCommandIsMode(IanvsMarkdownCommand command) => switch (command) {
  IanvsMarkdownCommand.togglePreview ||
  IanvsMarkdownCommand.livePreview ||
  IanvsMarkdownCommand.source ||
  IanvsMarkdownCommand.reading => true,
  _ => false,
};

/// Internal command boundary. A false result delegates to the next outer
/// boundary, so local cells/properties can preserve their own editing model.
class MarkdownCommandTarget extends InheritedWidget {
  const MarkdownCommandTarget({
    super.key,
    required this.kind,
    required this.onCommand,
    required super.child,
  });
  final MarkdownCommandKind kind;
  final bool Function(IanvsMarkdownCommand, BuildContext) onCommand;
  @override
  bool updateShouldNotify(MarkdownCommandTarget oldWidget) => false;
}

class _FocusedMarkdown {
  const _FocusedMarkdown(this.context, this.scope, this.targets);
  final BuildContext context;
  final _IanvsMarkdownShortcutsState scope;
  final List<MarkdownCommandTarget> targets;

  TargetPlatform get platform =>
      kind == MarkdownCommandKind.table || kind == MarkdownCommandKind.property
      ? defaultTargetPlatform
      : Theme.of(context).platform;

  MarkdownCommandKind get kind =>
      targets.first.kind == MarkdownCommandKind.reading &&
          context.findAncestorStateOfType<EditableTextState>() != null
      ? MarkdownCommandKind.property
      : targets.first.kind;
}

_FocusedMarkdown? _focusedMarkdownScope() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null || !context.mounted) return null;
  final scope = context
      .getInheritedWidgetOfExactType<_MarkdownShortcutScopeData>()
      ?.state;
  if (scope == null) return null;
  final targets = <MarkdownCommandTarget>[];
  context.visitAncestorElements((element) {
    if (element.widget is MarkdownCommandTarget) {
      targets.add(element.widget as MarkdownCommandTarget);
    }
    return true;
  });
  if (targets.isEmpty) return null;
  return _FocusedMarkdown(context, scope, targets);
}

/// HardwareKeyboard listeners run before FocusManager's early handlers.
bool markdownShortcutOwnsEvent(KeyEvent event) {
  final focused = _focusedMarkdownScope();
  if (focused == null) return false;
  if (focused.scope._ownedRawEvent?.physicalKey == event.physicalKey) {
    return true;
  }
  return focused.scope._route(
        _MarkdownKey.event(event),
        focused.kind,
        focused.platform,
      ) !=
      null;
}

bool markdownShortcutHandledRaw(RawKeyEvent event) =>
    identical(_focusedMarkdownScope()?.scope._ownedRawEvent, event);

bool invokeMarkdownTextCommand(
  IanvsMarkdownCommand command,
  BuildContext context,
) {
  final Intent? intent = switch (command) {
    IanvsMarkdownCommand.copy => CopySelectionTextIntent.copy,
    IanvsMarkdownCommand.cut => const CopySelectionTextIntent.cut(
      SelectionChangedCause.keyboard,
    ),
    IanvsMarkdownCommand.paste => const PasteTextIntent(
      SelectionChangedCause.keyboard,
    ),
    IanvsMarkdownCommand.selectAll => const SelectAllTextIntent(
      SelectionChangedCause.keyboard,
    ),
    _ => null,
  };
  if (intent == null) return false;
  Actions.maybeInvoke(context, intent);
  return true;
}

List<SingleActivator> defaultMarkdownBindings(
  IanvsMarkdownCommand command,
  TargetPlatform platform, {
  MarkdownCommandKind kind = MarkdownCommandKind.editor,
}) {
  final apple =
      platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;
  List<SingleActivator> commandKeys(
    LogicalKeyboardKey key, {
    bool controlOnApple = true,
    bool shift = false,
  }) => [
    SingleActivator(key, meta: true, shift: shift),
    if (!apple || controlOnApple)
      SingleActivator(key, control: true, shift: shift),
  ];
  return switch (command) {
    IanvsMarkdownCommand.undo => commandKeys(LogicalKeyboardKey.keyZ),
    IanvsMarkdownCommand.redo => [
      ...commandKeys(LogicalKeyboardKey.keyZ, shift: true),
      const SingleActivator(LogicalKeyboardKey.keyY, control: true),
    ],
    IanvsMarkdownCommand.bold => commandKeys(
      LogicalKeyboardKey.keyB,
      controlOnApple: false,
    ),
    IanvsMarkdownCommand.italic => commandKeys(LogicalKeyboardKey.keyI),
    IanvsMarkdownCommand.insertLink => commandKeys(
      LogicalKeyboardKey.keyK,
      controlOnApple: false,
    ),
    IanvsMarkdownCommand.deleteLine => commandKeys(
      LogicalKeyboardKey.keyD,
      controlOnApple: false,
    ),
    IanvsMarkdownCommand.save => commandKeys(LogicalKeyboardKey.keyS),
    IanvsMarkdownCommand.togglePreview => commandKeys(
      LogicalKeyboardKey.keyE,
      controlOnApple: false,
    ),
    IanvsMarkdownCommand.livePreview => commandKeys(LogicalKeyboardKey.digit1),
    IanvsMarkdownCommand.source => commandKeys(LogicalKeyboardKey.digit2),
    IanvsMarkdownCommand.reading => commandKeys(LogicalKeyboardKey.digit3),
    IanvsMarkdownCommand.indent => [
      const SingleActivator(LogicalKeyboardKey.tab),
    ],
    IanvsMarkdownCommand.outdent => [
      const SingleActivator(LogicalKeyboardKey.tab, shift: true),
    ],
    IanvsMarkdownCommand.selectAll => commandKeys(
      LogicalKeyboardKey.keyA,
      controlOnApple: kind == MarkdownCommandKind.reading,
    ),
    IanvsMarkdownCommand.copy => commandKeys(
      LogicalKeyboardKey.keyC,
      controlOnApple:
          kind == MarkdownCommandKind.reading ||
          kind == MarkdownCommandKind.live,
    ),
    IanvsMarkdownCommand.cut => commandKeys(
      LogicalKeyboardKey.keyX,
      controlOnApple: false,
    ),
    IanvsMarkdownCommand.paste => commandKeys(
      LogicalKeyboardKey.keyV,
      controlOnApple: false,
    ),
  };
}
