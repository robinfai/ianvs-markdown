import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Obsidian Border-theme checkbox used by Markdown task items.
///
/// The visible control is 16px with a 6px radius. Its 24px layout box leaves
/// room for Border's two-pixel hover/focus outline and two-pixel outline gap
/// without moving surrounding text.
class IanvsMarkdownTaskCheckbox extends StatefulWidget {
  const IanvsMarkdownTaskCheckbox({
    super.key,
    required this.value,
    this.onChanged,
    this.theme,
  });

  static const double size = 16;
  static const double layoutSize = 24;
  static const double radius = 6;
  static const Duration animationDuration = Duration(milliseconds: 150);

  final bool value;
  final ValueChanged<bool>? onChanged;
  final IanvsMarkdownThemeData? theme;

  @override
  State<IanvsMarkdownTaskCheckbox> createState() =>
      _IanvsMarkdownTaskCheckboxState();
}

class _IanvsMarkdownTaskCheckboxState extends State<IanvsMarkdownTaskCheckbox> {
  late final FocusNode _focusNode;
  bool _hovered = false;
  bool _focused = false;

  bool get _enabled => widget.onChanged != null;

  void _toggle() => widget.onChanged?.call(!widget.value);

  void _activateFromPointer() {
    _focusNode.requestFocus();
    _toggle();
  }

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = IanvsMarkdownThemeData.resolve(context, widget.theme);
    final showOutline = _enabled && (_hovered || _focused);
    final checkedColor = widget.value && _hovered && _enabled
        ? _brightenCheckboxColor(colors.taskCheckboxColor)
        : colors.taskCheckboxColor;
    final box = SizedBox.square(
      key: const ValueKey('ianvs-markdown-task-checkbox'),
      dimension: IanvsMarkdownTaskCheckbox.layoutSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            key: const ValueKey('ianvs-markdown-task-checkbox-outline'),
            duration: IanvsMarkdownTaskCheckbox.animationDuration,
            curve: Curves.easeInOut,
            width: IanvsMarkdownTaskCheckbox.layoutSize,
            height: IanvsMarkdownTaskCheckbox.layoutSize,
            decoration: BoxDecoration(
              border: showOutline
                  ? Border.all(
                      color: colors.taskCheckboxHoverOutlineColor,
                      width: 2,
                    )
                  : null,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          AnimatedContainer(
            key: const ValueKey('ianvs-markdown-task-checkbox-box'),
            duration: IanvsMarkdownTaskCheckbox.animationDuration,
            curve: Curves.easeInOut,
            width: IanvsMarkdownTaskCheckbox.size,
            height: IanvsMarkdownTaskCheckbox.size,
            decoration: BoxDecoration(
              color: widget.value ? checkedColor : Colors.transparent,
              border: Border.all(
                color: widget.value
                    ? checkedColor
                    : colors.taskCheckboxBorderColor,
              ),
              borderRadius: BorderRadius.circular(
                IanvsMarkdownTaskCheckbox.radius,
              ),
            ),
            child: widget.value
                ? CustomPaint(
                    key: const ValueKey('ianvs-markdown-task-checkbox-check'),
                    painter: _IanvsMarkdownTaskCheckPainter(
                      color: colors.surface,
                    ),
                  )
                : null,
          ),
        ],
      ),
    );

    final interactive = MouseRegion(
      cursor: _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) {
        if (!_hovered) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      child: FocusableActionDetector(
        enabled: _enabled,
        focusNode: _focusNode,
        onShowFocusHighlight: (value) {
          if (_focused != value) setState(() => _focused = value);
        },
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _toggle();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _enabled ? _activateFromPointer : null,
          child: box,
        ),
      ),
    );
    return Semantics(
      container: true,
      button: true,
      checked: widget.value,
      enabled: _enabled,
      label: widget.value ? 'Completed task' : 'Incomplete task',
      onTap: _enabled ? _toggle : null,
      child: ExcludeSemantics(child: interactive),
    );
  }
}

class _IanvsMarkdownTaskCheckPainter extends CustomPainter {
  const _IanvsMarkdownTaskCheckPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final scaleX = size.width / 16;
    final scaleY = size.height / 16;
    final path = Path()
      ..moveTo(2.1 * scaleX, 8.1 * scaleY)
      ..lineTo(6.15 * scaleX, 12.05 * scaleY)
      ..lineTo(13.9 * scaleX, 3.65 * scaleY);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * ((scaleX + scaleY) / 2)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _IanvsMarkdownTaskCheckPainter oldDelegate) {
    return color != oldDelegate.color;
  }
}

Color _brightenCheckboxColor(Color color) {
  const factor = 1.075;
  return Color.from(
    alpha: color.a,
    red: (color.r * factor).clamp(0, 1),
    green: (color.g * factor).clamp(0, 1),
    blue: (color.b * factor).clamp(0, 1),
  );
}
