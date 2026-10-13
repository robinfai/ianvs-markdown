import 'package:flutter/material.dart';

import 'localization.dart';
import 'theme.dart';

/// Status text outside document selection, never serialized into Markdown.
class MarkdownBudgetNotice extends StatelessWidget {
  const MarkdownBudgetNotice({
    super.key,
    required this.message,
    required this.colors,
  });

  final IanvsMarkdownMessage message;
  final IanvsMarkdownThemeData colors;

  @override
  Widget build(BuildContext context) => SelectionContainer.disabled(
    child: Padding(
      key: const ValueKey('ianvs-markdown-budget-notice'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        message.resolve(context),
        style: TextStyle(
          color: colors.textSecondary,
          fontSize: 13,
          height: 1.4,
        ),
      ),
    ),
  );
}
