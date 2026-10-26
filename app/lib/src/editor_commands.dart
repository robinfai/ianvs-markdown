import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

import 'controllers/workspace_controller.dart';
import 'models/reading_preferences.dart';

/// Shared by the native View menu and the in-window mode picker.
void setEditorMode(
  WorkspaceController workspace,
  IanvsMarkdownEditorMode mode,
) {
  final controller = workspace.activeDocument?.controller;
  if (controller == null) return;
  final command = switch (mode) {
    IanvsMarkdownEditorMode.livePreview => IanvsMarkdownCommand.livePreview,
    IanvsMarkdownEditorMode.source => IanvsMarkdownCommand.source,
    IanvsMarkdownEditorMode.preview => IanvsMarkdownCommand.reading,
  };
  if (IanvsMarkdownShortcuts.invoke(command, controller: controller)) return;
  final composing = controller.value.composing;
  if (composing.isValid && !composing.isCollapsed) return;
  workspace.setMode(mode);
}

/// Table cells own a local composing range, separate from the document value.
bool hasEditorComposition(WorkspaceController workspace) {
  final controller = workspace.activeDocument?.controller;
  if (controller == null) return false;
  final composing = controller.value.composing;
  if (composing.isValid && !composing.isCollapsed) return true;
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null ||
      !focused.mounted ||
      (focused is Element && focused.renderObject?.attached != true)) {
    return false;
  }
  if (!identical(
    focused
        .findAncestorWidgetOfExactType<IanvsMarkdownLiveEditor>()
        ?.controller,
    controller,
  )) {
    return false;
  }
  final local = focused
      .findAncestorStateOfType<EditableTextState>()
      ?.widget
      .controller
      .value
      .composing;
  return local != null && local.isValid && !local.isCollapsed;
}

/// Resizing during composition can rebuild the active editor's text layout.
/// Keep the same guard for window shortcuts and native menu invocations.
void changeReadingTextSize(WorkspaceController workspace, {double? delta}) {
  if (hasEditorComposition(workspace)) return;
  final current = workspace.readingPreferences;
  workspace.setReadingPreferences(
    current.copyWith(
      fontSize: delta == null
          ? ReadingPreferences.defaults.fontSize
          : current.fontSize + delta,
    ),
  );
}

Map<ShortcutActivator, VoidCallback> readingSizeShortcuts(
  WorkspaceController workspace,
) => {
  for (final command in [true, false]) ...{
    for (final shift in [false, true])
      SingleActivator(
        LogicalKeyboardKey.equal,
        meta: command,
        control: !command,
        shift: shift,
      ): () =>
          changeReadingTextSize(workspace, delta: 0.5),
    SingleActivator(
      LogicalKeyboardKey.add,
      meta: command,
      control: !command,
    ): () =>
        changeReadingTextSize(workspace, delta: 0.5),
    SingleActivator(
      LogicalKeyboardKey.minus,
      meta: command,
      control: !command,
    ): () =>
        changeReadingTextSize(workspace, delta: -0.5),
    SingleActivator(
      LogicalKeyboardKey.numpadSubtract,
      meta: command,
      control: !command,
    ): () =>
        changeReadingTextSize(workspace, delta: -0.5),
    SingleActivator(
      LogicalKeyboardKey.digit0,
      meta: command,
      control: !command,
    ): () =>
        changeReadingTextSize(workspace),
  },
};

/// Returns within the active document, preserving local IME composition.
void navigateBack(WorkspaceController workspace) {
  if (!hasEditorComposition(workspace)) {
    workspace.navigateBack();
  }
}
