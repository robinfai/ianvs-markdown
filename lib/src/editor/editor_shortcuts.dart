import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../front_matter_card.dart';
import '../keyboard.dart';
import 'editor_controller.dart';
import 'editor_models.dart';
import 'editor_toolbar.dart';
import 'markdown_paste.dart';

bool _isInsideFrontMatterCard(BuildContext? context) =>
    context?.findAncestorWidgetOfExactType<IanvsMarkdownFrontMatterCard>() !=
    null;

class IanvsMarkdownEditorShortcuts extends StatelessWidget {
  const IanvsMarkdownEditorShortcuts({
    super.key,
    required this.controller,
    required this.child,
    this.enableModeShortcuts = true,
    this.onSaveRequested,
  });

  final IanvsMarkdownController controller;
  final Widget child;
  final bool enableModeShortcuts;
  final IanvsMarkdownSaveCallback? onSaveRequested;

  @override
  Widget build(BuildContext context) {
    final intents = <IanvsMarkdownCommand, Intent>{
      IanvsMarkdownCommand.undo: const _UndoIntent(),
      IanvsMarkdownCommand.redo: const _RedoIntent(),
      IanvsMarkdownCommand.deleteLine: const _DeleteLineIntent(),
      IanvsMarkdownCommand.bold: const _BoldIntent(),
      IanvsMarkdownCommand.italic: const _ItalicIntent(),
      IanvsMarkdownCommand.insertLink: const _LinkIntent(),
      IanvsMarkdownCommand.save: const _SaveIntent(),
      if (enableModeShortcuts) ...{
        IanvsMarkdownCommand.togglePreview: const _ToggleModeIntent(),
        IanvsMarkdownCommand.livePreview: const _SetModeIntent(
          IanvsMarkdownEditorMode.livePreview,
        ),
        IanvsMarkdownCommand.source: const _SetModeIntent(
          IanvsMarkdownEditorMode.source,
        ),
        IanvsMarkdownCommand.reading: const _SetModeIntent(
          IanvsMarkdownEditorMode.preview,
        ),
      },
      IanvsMarkdownCommand.indent: const _IndentIntent(),
      IanvsMarkdownCommand.outdent: const _OutdentIntent(),
    };
    final shortcuts = Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        for (final entry in intents.entries)
          for (final binding in defaultMarkdownBindings(
            entry.key,
            Theme.of(context).platform,
          ))
            binding: entry.value,
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _UndoIntent: CallbackAction<_UndoIntent>(
            onInvoke: (_) {
              if (controller.mode != IanvsMarkdownEditorMode.preview) {
                controller.undo();
              }
              return null;
            },
          ),
          _RedoIntent: CallbackAction<_RedoIntent>(
            onInvoke: (_) {
              if (controller.mode != IanvsMarkdownEditorMode.preview) {
                controller.redo();
              }
              return null;
            },
          ),
          _DeleteLineIntent: _DeleteLineAction(controller),
          PasteTextIntent: _MarkdownPasteAction(controller),
          _BoldIntent: CallbackAction<_BoldIntent>(
            onInvoke: (_) {
              if (controller.mode != IanvsMarkdownEditorMode.preview) {
                controller.toggleInline('**');
              }
              return null;
            },
          ),
          _ItalicIntent: CallbackAction<_ItalicIntent>(
            onInvoke: (_) {
              if (controller.mode != IanvsMarkdownEditorMode.preview) {
                controller.toggleInline('*');
              }
              return null;
            },
          ),
          _LinkIntent: CallbackAction<_LinkIntent>(
            onInvoke: (_) {
              if (controller.mode != IanvsMarkdownEditorMode.preview) {
                controller.insertLink();
              }
              return null;
            },
          ),
          _SaveIntent: CallbackAction<_SaveIntent>(
            onInvoke: (_) {
              unawaited(_save());
              return null;
            },
          ),
          _ToggleModeIntent: CallbackAction<_ToggleModeIntent>(
            onInvoke: (_) {
              controller.mode =
                  controller.mode == IanvsMarkdownEditorMode.preview
                  ? IanvsMarkdownEditorMode.livePreview
                  : IanvsMarkdownEditorMode.preview;
              return null;
            },
          ),
          _SetModeIntent: CallbackAction<_SetModeIntent>(
            onInvoke: (intent) {
              controller.mode = intent.mode;
              return null;
            },
          ),
          _IndentIntent: CallbackAction<_IndentIntent>(
            onInvoke: (_) {
              if (controller.mode != IanvsMarkdownEditorMode.preview &&
                  controller.canIndentSelection) {
                controller.indentSelection();
              } else {
                FocusScope.of(context).nextFocus();
              }
              return null;
            },
          ),
          _OutdentIntent: CallbackAction<_OutdentIntent>(
            onInvoke: (_) {
              if (controller.mode != IanvsMarkdownEditorMode.preview &&
                  controller.canIndentSelection) {
                controller.indentSelection(outdent: true);
              } else {
                FocusScope.of(context).previousFocus();
              }
              return null;
            },
          ),
          DeleteToNextWordBoundaryIntent: _MarkdownWordDeletionAction(
            controller,
          ),
          ExtendSelectionToNextWordBoundaryIntent: _MarkdownWordMovementAction(
            controller,
          ),
          ExtendSelectionToNextWordBoundaryOrCaretLocationIntent:
              _MarkdownWordSelectionAction(controller),
        },
        child: child,
      ),
    );
    return MarkdownCommandTarget(
      kind: MarkdownCommandKind.editor,
      onCommand: (command, focused) {
        if (intents[command] case final intent?) {
          Actions.maybeInvoke(focused, intent);
          return true;
        }
        if (markdownCommandIsMode(command)) return true;
        return invokeMarkdownTextCommand(command, focused);
      },
      child: shortcuts,
    );
  }

  Future<void> _save() async {
    final callback = onSaveRequested;
    if (callback == null) return;
    final savedText = controller.text;
    controller.commitHistoryGroup();
    try {
      await callback(savedText);
    } on IanvsMarkdownSaveCancelledException {
      return;
    }
    controller.markSaved(savedText: savedText);
  }
}

class _UndoIntent extends Intent {
  const _UndoIntent();
}

class _RedoIntent extends Intent {
  const _RedoIntent();
}

class _DeleteLineIntent extends Intent {
  const _DeleteLineIntent();
}

class _DeleteLineAction extends ContextAction<_DeleteLineIntent> {
  _DeleteLineAction(this.controller);

  final IanvsMarkdownController controller;

  @override
  Object? invoke(_DeleteLineIntent intent, [BuildContext? context]) {
    if (controller.mode == IanvsMarkdownEditorMode.preview) return null;
    controller.deleteSelectedLines(
      preferredCaretOffset: context == null
          ? null
          : _preferredDeleteLineCaret(controller, context),
    );
    return null;
  }
}

class _MarkdownPasteAction extends ContextAction<PasteTextIntent> {
  _MarkdownPasteAction(this.controller);

  final IanvsMarkdownController controller;

  @override
  Object? invoke(PasteTextIntent intent, [BuildContext? context]) {
    final defaultAction = callingAction;
    if (controller.mode == IanvsMarkdownEditorMode.preview ||
        _isInsideFrontMatterCard(context)) {
      return defaultAction?.invoke(intent);
    }
    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) {
      return defaultAction?.invoke(intent);
    }
    unawaited(_pasteSelectedText(intent, defaultAction));
    return null;
  }

  Future<void> _pasteSelectedText(
    PasteTextIntent intent,
    Action<PasteTextIntent>? defaultAction,
  ) async {
    final data = await readPlainTextClipboardSafely();
    if (controller.mode == IanvsMarkdownEditorMode.preview) return;
    final pastedText = data?.text;
    if (pastedText == null) return;
    final replacement = smartUrlPasteValue(controller.value, pastedText);
    if (replacement == null) {
      defaultAction?.invoke(intent);
      return;
    }

    controller.commitHistoryGroup();
    controller.value = replacement;
    controller.commitHistoryGroup();
  }
}

int? _preferredDeleteLineCaret(
  IanvsMarkdownController controller,
  BuildContext context,
) {
  final selection = controller.selection;
  if (!selection.isValid) return null;
  final source = controller.text;
  final head = selection.extentOffset.clamp(0, source.length);
  final lineEnd = _sourceLineEnd(source, head);
  if (lineEnd == source.length) return head;

  final editable = _findRenderEditable(context.findRenderObject());
  if (editable == null) return null;
  final nextStart = lineEnd + 1;
  final nextEnd = _sourceLineEnd(source, nextStart);
  final headRect = editable.getLocalRectForCaret(
    TextPosition(offset: head, affinity: selection.affinity),
  );
  final nextLineRect = editable.getLocalRectForCaret(
    TextPosition(offset: nextStart),
  );
  final resolved = editable.getPositionForPoint(
    editable.localToGlobal(Offset(headRect.left, nextLineRect.center.dy)),
  );
  return resolved.offset.clamp(nextStart, nextEnd);
}

RenderEditable? _findRenderEditable(RenderObject? root) {
  if (root == null) return null;
  if (root is RenderEditable) return root;
  RenderEditable? result;
  void visit(RenderObject child) {
    if (result != null) return;
    if (child is RenderEditable) {
      result = child;
      return;
    }
    child.visitChildren(visit);
  }

  root.visitChildren(visit);
  return result;
}

int _sourceLineEnd(String text, int offset) {
  final safeOffset = offset.clamp(0, text.length);
  final newline = text.indexOf('\n', safeOffset);
  return newline < 0 ? text.length : newline;
}

class _BoldIntent extends Intent {
  const _BoldIntent();
}

class _ItalicIntent extends Intent {
  const _ItalicIntent();
}

class _LinkIntent extends Intent {
  const _LinkIntent();
}

class _SaveIntent extends Intent {
  const _SaveIntent();
}

class _ToggleModeIntent extends Intent {
  const _ToggleModeIntent();
}

class _SetModeIntent extends Intent {
  const _SetModeIntent(this.mode);

  final IanvsMarkdownEditorMode mode;
}

class _IndentIntent extends Intent {
  const _IndentIntent();
}

class _OutdentIntent extends Intent {
  const _OutdentIntent();
}

class _MarkdownWordDeletionAction
    extends ContextAction<DeleteToNextWordBoundaryIntent> {
  _MarkdownWordDeletionAction(this.controller);

  final IanvsMarkdownController controller;

  @override
  Object? invoke(
    DeleteToNextWordBoundaryIntent intent, [
    BuildContext? context,
  ]) {
    if (controller.mode == IanvsMarkdownEditorMode.preview ||
        _isInsideFrontMatterCard(context)) {
      return callingAction?.invoke(intent);
    }
    if (controller.deleteMarkdownPunctuationSegment(forward: intent.forward)) {
      return null;
    }
    return callingAction?.invoke(intent);
  }
}

class _MarkdownWordMovementAction
    extends ContextAction<ExtendSelectionToNextWordBoundaryIntent> {
  _MarkdownWordMovementAction(this.controller);

  final IanvsMarkdownController controller;

  @override
  Object? invoke(
    ExtendSelectionToNextWordBoundaryIntent intent, [
    BuildContext? context,
  ]) {
    if (controller.mode == IanvsMarkdownEditorMode.preview ||
        _isInsideFrontMatterCard(context)) {
      return callingAction?.invoke(intent);
    }
    if (controller.moveAcrossMarkdownPunctuation(
      forward: intent.forward,
      extendSelection: !intent.collapseSelection,
    )) {
      return null;
    }
    return callingAction?.invoke(intent);
  }
}

class _MarkdownWordSelectionAction
    extends
        ContextAction<ExtendSelectionToNextWordBoundaryOrCaretLocationIntent> {
  _MarkdownWordSelectionAction(this.controller);

  final IanvsMarkdownController controller;

  @override
  Object? invoke(
    ExtendSelectionToNextWordBoundaryOrCaretLocationIntent intent, [
    BuildContext? context,
  ]) {
    if (controller.mode == IanvsMarkdownEditorMode.preview ||
        _isInsideFrontMatterCard(context)) {
      return callingAction?.invoke(intent);
    }
    if (controller.moveAcrossMarkdownPunctuation(
      forward: intent.forward,
      extendSelection: true,
    )) {
      return null;
    }
    return callingAction?.invoke(intent);
  }
}
