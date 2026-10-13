import 'package:flutter/material.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

import 'controllers/workspace_controller.dart';

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
