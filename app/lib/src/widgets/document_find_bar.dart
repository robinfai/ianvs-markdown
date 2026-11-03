import '../app_localizations.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

import '../controllers/document_find_controller.dart';
import '../desktop_typography.dart';

class DocumentFindBar extends StatelessWidget {
  const DocumentFindBar({
    super.key,
    required this.controller,
    required this.queryFocus,
    required this.onClose,
    required this.onEnableEditing,
    this.onScopeChanged,
  });

  final DocumentFindController controller;
  final FocusNode queryFocus;
  final VoidCallback onClose;
  final VoidCallback onEnableEditing;
  final ValueChanged<DocumentFindScope>? onScopeChanged;

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Material(
        color: colors.surfaceMuted,
        child: Container(
          key: const ValueKey('document-find-bar'),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.borderSoft)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final fieldWidth = math.min(280.0, constraints.maxWidth);
              final modeLabel = switch (controller.document.mode) {
                IanvsMarkdownEditorMode.livePreview =>
                  'Close returns to Live Preview',
                IanvsMarkdownEditorMode.preview =>
                  'Read-only · close returns to Read',
                IanvsMarkdownEditorMode.source => 'Current document only',
              };
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    controller.scope == DocumentFindScope.body
                        ? appText(context, "Find in rendered body")
                        : appText(context, "Find in Markdown source · {0}", [
                            modeLabel,
                          ]),
                    style: DesktopTypography.subheadline.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (controller.document.mode !=
                          IanvsMarkdownEditorMode.source)
                        DropdownButton<DocumentFindScope>(
                          key: const ValueKey('document-find-scope'),
                          value: controller.scope,
                          items: [
                            DropdownMenuItem(
                              value: DocumentFindScope.body,
                              child: Text(appText(context, "Body")),
                            ),
                            DropdownMenuItem(
                              value: DocumentFindScope.source,
                              child: Text(appText(context, "Source")),
                            ),
                          ],
                          onChanged: controller.isComposing
                              ? null
                              : (scope) {
                                  if (scope != null) {
                                    (onScopeChanged ?? controller.setScope)(
                                      scope,
                                    );
                                  }
                                  queryFocus.requestFocus();
                                },
                        ),
                      SizedBox(
                        width: fieldWidth,
                        child: Focus(
                          onKeyEvent: (_, event) {
                            final keyboard = HardwareKeyboard.instance;
                            if (event is! KeyDownEvent ||
                                event.logicalKey != LogicalKeyboardKey.enter ||
                                keyboard.isMetaPressed ||
                                keyboard.isControlPressed ||
                                keyboard.isAltPressed ||
                                controller.isComposing) {
                              return KeyEventResult.ignored;
                            }
                            controller.next(backwards: keyboard.isShiftPressed);
                            return KeyEventResult.handled;
                          },
                          child: TextField(
                            key: const ValueKey('document-find-query'),
                            controller: controller.query,
                            focusNode: queryFocus,
                            autofocus: true,
                            decoration: InputDecoration(
                              labelText: appText(context, "Find"),
                              isDense: true,
                            ),
                          ),
                        ),
                      ),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          controller.query.text.isEmpty
                              ? appText(context, "Enter text to find")
                              : controller.isComposing
                              ? appText(context, "Finish composing")
                              : controller.isSearching
                              ? appText(context, "Searching…")
                              : controller.bodyUnavailable
                              ? appText(
                                  context,
                                  "Body search unavailable · use Source",
                                )
                              : appText(context, "{0} of {1}", [
                                  controller.currentIndex + 1,
                                  controller.count,
                                ]),
                          key: const ValueKey('document-find-count'),
                          style: DesktopTypography.callout,
                        ),
                      ),
                      IconButton(
                        tooltip: appText(context, "Match case"),
                        isSelected: controller.matchCase,
                        onPressed: controller.isComposing
                            ? null
                            : () => controller.setMatchCase(
                                !controller.matchCase,
                              ),
                        icon: const Text('Aa'),
                      ),
                      IconButton(
                        tooltip: appText(context, "Previous match (⇧⌘G)"),
                        onPressed: controller.canNavigate
                            ? () => controller.next(backwards: true)
                            : null,
                        icon: const Icon(Icons.keyboard_arrow_up),
                      ),
                      IconButton(
                        tooltip: appText(context, "Next match (⌘G)"),
                        onPressed: controller.canNavigate
                            ? controller.next
                            : null,
                        icon: const Icon(Icons.keyboard_arrow_down),
                      ),
                      IconButton(
                        tooltip: appText(context, "Close find (Esc)"),
                        onPressed: controller.isComposing ? null : onClose,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (controller.scope == DocumentFindScope.body)
                    TextButton(
                      onPressed: controller.isComposing
                          ? null
                          : onEnableEditing,
                      child: Text(appText(context, "Edit source to replace")),
                    )
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: fieldWidth,
                          child: TextField(
                            key: const ValueKey('document-find-replacement'),
                            controller: controller.replacement,
                            decoration: InputDecoration(
                              labelText: appText(context, "Replace with"),
                              isDense: true,
                            ),
                          ),
                        ),
                        if (controller.readOnly)
                          TextButton(
                            onPressed: controller.isComposing
                                ? null
                                : onEnableEditing,
                            child: Text(appText(context, "Edit to replace")),
                          )
                        else ...[
                          TextButton(
                            onPressed: controller.canReplace
                                ? controller.replaceCurrent
                                : null,
                            child: Text(appText(context, "Replace")),
                          ),
                          TextButton(
                            onPressed: controller.canReplaceAll
                                ? controller.replaceAll
                                : null,
                            child: Text(appText(context, "Replace All")),
                          ),
                        ],
                      ],
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
