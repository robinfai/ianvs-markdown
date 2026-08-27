import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../front_matter_card.dart';
import 'editor_controller.dart';
import 'editor_models.dart';
import 'editor_toolbar.dart';
import 'markdown_paste.dart';

class IanvsMarkdownEditorShortcuts extends StatelessWidget {
  const IanvsMarkdownEditorShortcuts({
    super.key,
    required this.controller,
    required this.child,
    this.onSaveRequested,
  });

  final IanvsMarkdownController controller;
  final Widget child;
  final IanvsMarkdownSaveCallback? onSaveRequested;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final usesCommandModifier =
        platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
            const _UndoIntent(),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            const _UndoIntent(),
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            const _RedoIntent(),
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): const _RedoIntent(),
        const SingleActivator(LogicalKeyboardKey.keyY, control: true):
            const _RedoIntent(),
        const SingleActivator(LogicalKeyboardKey.keyD, meta: true):
            const _DeleteLineIntent(),
        if (!usesCommandModifier)
          const SingleActivator(LogicalKeyboardKey.keyD, control: true):
              const _DeleteLineIntent(),
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true):
            const _BoldIntent(),
        if (!usesCommandModifier)
          const SingleActivator(LogicalKeyboardKey.keyB, control: true):
              const _BoldIntent(),
        const SingleActivator(LogicalKeyboardKey.keyI, meta: true):
            const _ItalicIntent(),
        const SingleActivator(LogicalKeyboardKey.keyI, control: true):
            const _ItalicIntent(),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            const _LinkIntent(),
        if (!usesCommandModifier)
          const SingleActivator(LogicalKeyboardKey.keyK, control: true):
              const _LinkIntent(),
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
            const _SaveIntent(),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            const _SaveIntent(),
        const SingleActivator(LogicalKeyboardKey.keyE, meta: true):
            const _ToggleModeIntent(),
        if (!usesCommandModifier)
          const SingleActivator(LogicalKeyboardKey.keyE, control: true):
              const _ToggleModeIntent(),
        const SingleActivator(LogicalKeyboardKey.digit1, meta: true):
            const _SetModeIntent(IanvsMarkdownEditorMode.livePreview),
        const SingleActivator(LogicalKeyboardKey.digit1, control: true):
            const _SetModeIntent(IanvsMarkdownEditorMode.livePreview),
        const SingleActivator(LogicalKeyboardKey.digit2, meta: true):
            const _SetModeIntent(IanvsMarkdownEditorMode.source),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true):
            const _SetModeIntent(IanvsMarkdownEditorMode.source),
        const SingleActivator(LogicalKeyboardKey.digit3, meta: true):
            const _SetModeIntent(IanvsMarkdownEditorMode.preview),
        const SingleActivator(LogicalKeyboardKey.digit3, control: true):
            const _SetModeIntent(IanvsMarkdownEditorMode.preview),
        const SingleActivator(LogicalKeyboardKey.tab): const _IndentIntent(),
        const SingleActivator(LogicalKeyboardKey.tab, shift: true):
            const _OutdentIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _UndoIntent: CallbackAction<_UndoIntent>(
            onInvoke: (_) {
              controller.undo();
              return null;
            },
          ),
          _RedoIntent: CallbackAction<_RedoIntent>(
            onInvoke: (_) {
              controller.redo();
              return null;
            },
          ),
          _DeleteLineIntent: _DeleteLineAction(controller),
          PasteTextIntent: _MarkdownPasteAction(controller),
          _BoldIntent: CallbackAction<_BoldIntent>(
            onInvoke: (_) {
              controller.toggleInline('**');
              return null;
            },
          ),
          _ItalicIntent: CallbackAction<_ItalicIntent>(
            onInvoke: (_) {
              controller.toggleInline('*');
              return null;
            },
          ),
          _LinkIntent: CallbackAction<_LinkIntent>(
            onInvoke: (_) {
              controller.insertLink();
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
              if (controller.canIndentSelection) {
                controller.indentSelection();
              } else {
                FocusScope.of(context).nextFocus();
              }
              return null;
            },
          ),
          _OutdentIntent: CallbackAction<_OutdentIntent>(
            onInvoke: (_) {
              if (controller.canIndentSelection) {
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
  }

  Future<void> _save() async {
    final callback = onSaveRequested;
    if (callback == null) return;
    await callback(controller.text);
    controller.markSaved();
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
    if (context
            ?.findAncestorWidgetOfExactType<IanvsMarkdownFrontMatterCard>() !=
        null) {
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
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final pastedText = data?.text;
    final replacement = pastedText == null
        ? null
        : smartUrlPasteValue(controller.value, pastedText);
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
    extends Action<DeleteToNextWordBoundaryIntent> {
  _MarkdownWordDeletionAction(this.controller);

  final IanvsMarkdownController controller;

  @override
  Object? invoke(DeleteToNextWordBoundaryIntent intent) {
    if (controller.deleteMarkdownPunctuationSegment(forward: intent.forward)) {
      return null;
    }
    return callingAction?.invoke(intent);
  }
}

class _MarkdownWordMovementAction
    extends Action<ExtendSelectionToNextWordBoundaryIntent> {
  _MarkdownWordMovementAction(this.controller);

  final IanvsMarkdownController controller;

  @override
  Object? invoke(ExtendSelectionToNextWordBoundaryIntent intent) {
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
    extends Action<ExtendSelectionToNextWordBoundaryOrCaretLocationIntent> {
  _MarkdownWordSelectionAction(this.controller);

  final IanvsMarkdownController controller;

  @override
  Object? invoke(
    ExtendSelectionToNextWordBoundaryOrCaretLocationIntent intent,
  ) {
    if (controller.moveAcrossMarkdownPunctuation(
      forward: intent.forward,
      extendSelection: true,
    )) {
      return null;
    }
    return callingAction?.invoke(intent);
  }
}
