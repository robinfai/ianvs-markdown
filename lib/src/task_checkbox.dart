import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
    this.marker,
    this.onChanged,
    this.theme,
  }) : assert(marker == null || marker.length == 1),
       assert(marker == null || (marker == ' ') == !value);

  static const double size = 16;
  static const double layoutSize = 24;
  static const double radius = 6;
  static const Duration animationDuration = Duration(milliseconds: 150);

  final bool value;

  /// Exact Obsidian character between `[` and `]`.
  ///
  /// When omitted, [value] maps to the ordinary space / `x` states. Known
  /// Border markers receive their themed icon; unknown non-space markers keep
  /// Obsidian core's ordinary checked appearance.
  final String? marker;
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
    final marker = widget.value ? (widget.marker ?? 'x') : ' ';
    final showOutline = _enabled && (_hovered || _focused);
    final baseMarkerColor = _taskMarkerColor(marker, colors);
    final markerColor = widget.value && _hovered && _enabled
        ? _brightenCheckboxColor(baseMarkerColor)
        : baseMarkerColor;
    final standaloneSvg = _standaloneMarkerSvg(marker);
    final filledSvg = _filledMarkerSvg(marker);
    final progress = marker == '/';
    final standalone = standaloneSvg != null;
    final Widget? markerWidget;
    if (!widget.value) {
      markerWidget = null;
    } else if (standaloneSvg != null) {
      markerWidget = SvgPicture.string(
        standaloneSvg,
        key: const ValueKey('ianvs-markdown-task-checkbox-alternative-icon'),
        width: IanvsMarkdownTaskCheckbox.size,
        height: IanvsMarkdownTaskCheckbox.size,
        colorFilter: ColorFilter.mode(markerColor, BlendMode.srcIn),
      );
    } else if (filledSvg != null) {
      markerWidget = Padding(
        // Obsidian core keeps checked pseudo-element masks at 65% of 16px.
        padding: const EdgeInsets.all(2.8),
        child: SvgPicture.string(
          filledSvg,
          key: const ValueKey('ianvs-markdown-task-checkbox-alternative-icon'),
          colorFilter: ColorFilter.mode(colors.surface, BlendMode.srcIn),
        ),
      );
    } else if (progress) {
      markerWidget = CustomPaint(
        key: const ValueKey('ianvs-markdown-task-checkbox-alternative-icon'),
        painter: _IanvsMarkdownTaskProgressPainter(color: markerColor),
      );
    } else {
      markerWidget = CustomPaint(
        key: const ValueKey('ianvs-markdown-task-checkbox-check'),
        painter: _IanvsMarkdownTaskCheckPainter(color: colors.surface),
      );
    }
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
              color: widget.value && !standalone && !progress
                  ? markerColor
                  : Colors.transparent,
              border: standalone
                  ? null
                  : Border.all(
                      color: widget.value
                          ? markerColor
                          : colors.taskCheckboxBorderColor,
                      width: progress ? 2 : 1,
                    ),
              borderRadius: BorderRadius.circular(
                standalone ? 0 : IanvsMarkdownTaskCheckbox.radius,
              ),
            ),
            child: markerWidget,
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
          // CodeMirror decorations toggle tasks without stealing the caret
          // from the editor. The control remains keyboard-focusable through
          // normal focus traversal, but a pointer click preserves text focus.
          onTap: _enabled ? _toggle : null,
          child: box,
        ),
      ),
    );
    return Semantics(
      container: true,
      button: true,
      checked: widget.value,
      enabled: _enabled,
      label: _taskMarkerSemanticLabel(marker),
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

class _IanvsMarkdownTaskProgressPainter extends CustomPainter {
  const _IanvsMarkdownTaskProgressPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    canvas
      ..save()
      ..clipRRect(
        RRect.fromRectAndRadius(
          bounds.deflate(2),
          const Radius.circular(IanvsMarkdownTaskCheckbox.radius - 2),
        ),
      );
    final path = Path()
      ..moveTo(bounds.center.dx, bounds.center.dy)
      ..lineTo(bounds.center.dx, bounds.top)
      ..arcTo(bounds, -1.5707963267948966, 2.356194490192345, false)
      ..close();
    canvas
      ..drawPath(path, Paint()..color = color)
      ..restore();
  }

  @override
  bool shouldRepaint(covariant _IanvsMarkdownTaskProgressPainter oldDelegate) {
    return color != oldDelegate.color;
  }
}

/// Whether Obsidian treats [marker] as a checked task.
bool ianvsMarkdownTaskMarkerIsChecked(String marker) => marker != ' ';

/// Whether Border applies muted strike-through text to [marker].
bool ianvsMarkdownTaskMarkerUsesDoneText(String marker) {
  return marker == 'x' || marker == 'X' || marker == '-';
}

Color _taskMarkerColor(String marker, IanvsMarkdownThemeData colors) {
  return switch (marker) {
    'l' || 'c' || 'd' => colors.taskStatusRed,
    '!' || 'I' => colors.taskStatusOrange,
    '*' || '/' => colors.taskStatusYellow,
    'i' || 'n' => colors.taskStatusCyan,
    'b' || '<' => colors.taskStatusBlue,
    '"' || '“' => colors.taskStatusPurple,
    '?' || '>' => colors.taskStatusPink,
    '-' => colors.taskDoneColor,
    _ => colors.taskCheckboxColor,
  };
}

String _taskMarkerSemanticLabel(String marker) {
  return switch (marker) {
    ' ' => 'Incomplete task',
    'x' || 'X' => 'Completed task',
    '/' => 'In progress task',
    '-' => 'Cancelled task',
    '>' => 'Forwarded task',
    '<' => 'Scheduled task',
    '?' => 'Question task',
    '!' => 'Important task',
    '*' => 'Starred task',
    'i' => 'Information task',
    'I' => 'Idea task',
    'l' => 'Location task',
    'b' => 'Bookmark task',
    'n' => 'Note task',
    'p' => 'Positive task',
    'c' => 'Negative task',
    '"' || '“' => 'Quote task',
    'S' => 'Savings task',
    'u' => 'Up task',
    'd' => 'Down task',
    _ => 'Checked task $marker',
  };
}

String? _filledMarkerSvg(String marker) {
  return switch (marker) {
    '!' => _importantSvg,
    '?' => _questionSvg,
    'i' => _informationSvg,
    '-' => _cancelledSvg,
    _ => null,
  };
}

String? _standaloneMarkerSvg(String marker) {
  return switch (marker) {
    '*' => _starredSvg,
    'I' => _ideaSvg,
    'l' => _locationSvg,
    'b' => _bookmarkSvg,
    'n' => _noteSvg,
    'p' => _positiveSvg,
    'c' => _negativeSvg,
    '"' || '“' => _quoteSvg,
    'S' => _savingsSvg,
    'u' => _upSvg,
    'd' => _downSvg,
    '>' => _forwardedSvg,
    '<' => _scheduledSvg,
    _ => null,
  };
}

const _importantSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M8 0a2.463 2.463 0 0 0-2.43 2.864v.002L6.686 9.55a1.334 1.334 0 0 0 2.63 0l1.114-6.685v-.002A2.463 2.463 0 0 0 8 0Zm0 12a2 2 0 1 0 0 4 2 2 0 0 0 0-4Z"/></svg>
''';
const _questionSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M12.871 3.692c0 3.56-3.956 3.319-3.956 5.78v.014c0 .284-.23.514-.514.514H6.243a.514.514 0 0 1-.515-.514V9.34c0-3.803 3.473-3.56 3.473-5.341 0-.77-.571-1.23-1.517-1.23-.768 0-1.554.335-2.268 1.022a.512.512 0 0 1-.67.031l-1.419-1.11a.513.513 0 0 1-.056-.76C4.457.731 5.997 0 8.036 0c3.23 0 4.835 1.736 4.835 3.692ZM9.355 14c0 1.099-.88 2-2 2-1.1 0-2-.901-2-2s.9-2 2-2c1.12 0 2 .901 2 2Z"/></svg>
''';
const _informationSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M10.34 14.025c-.007.002-.56.186-1.04.186-.265 0-.372-.055-.406-.08-.168-.116-.48-.335.054-1.4l1-1.993c.593-1.184.681-2.33.245-3.226-.356-.733-1.039-1.236-1.92-1.416A5 5 0 0 0 7.315 6C5.466 6 4.221 7.08 4.17 7.125a.5.5 0 0 0 .493.848c.005-.002.559-.187 1.04-.187.262 0 .368.055.401.078.17.119.482.34-.05 1.403l-1.001 1.995c-.594 1.185-.681 2.33-.245 3.225.356.733 1.038 1.236 1.921 1.416.314.063.636.097.954.097 1.85 0 3.096-1.08 3.148-1.126a.5.5 0 0 0-.49-.85ZM9.5 5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5Z"/></svg>
''';
const _cancelledSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M0 8a1.5 1.5 0 0 1 1.5-1.5h13a1.5 1.5 0 0 1 0 3h-13A1.5 1.5 0 0 1 0 8Z"/></svg>
''';
const _starredSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M8.91.58c-.08-.17-.21-.32-.37-.42C8.38.05 8.19 0 8 0s-.38.05-.54.16c-.16.1-.29.25-.37.42L5.16 4.7.85 5.36c-.18.03-.35.1-.49.22-.14.12-.25.27-.3.45-.06.17-.07.36-.03.54.04.18.13.34.26.48l3.15 3.23-.75 4.57c-.03.19 0 .38.06.55.07.17.19.32.35.43.15.11.33.17.52.18.19 0 .37-.03.54-.12L8 13.76l3.84 2.13c.16.09.35.13.54.12.19-.01.37-.07.52-.18.15-.11.27-.26.35-.43.07-.17.09-.36.06-.55l-.75-4.57 3.15-3.23c.13-.13.22-.3.26-.48.04-.18.03-.37-.03-.54-.06-.17-.16-.33-.31-.45-.14-.12-.31-.2-.49-.22l-4.31-.66L8.91.58Z"/></svg>
''';
const _ideaSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M9 1c0-.27-.11-.52-.29-.71C8.52.1 8.27 0 8 0s-.52.11-.71.29C7.1.48 7 .73 7 1v1c0 .27.11.52.29.71.19.19.44.29.71.29s.52-.11.71-.29C8.9 2.52 9 2.27 9 2V1Zm4.66 2.76c.18-.19.28-.44.28-.7 0-.26-.11-.51-.29-.7s-.44-.29-.7-.29c-.26 0-.51.1-.7.28l-.71.71c-.18.19-.28.44-.28.7 0 .26.11.51.29.7s.44.29.7.29c.26 0 .51-.1.7-.28l.71-.71ZM16 8c0 .27-.11.52-.29.71-.19.19-.44.29-.71.29h-1c-.27 0-.52-.11-.71-.29C13.1 8.52 13 8.27 13 8s.11-.52.29-.71c.19-.19.44-.29.71-.29h1c.27 0 .52.11.71.29.19.19.29.44.29.71ZM3.05 4.46c.09.1.2.17.32.22.12.05.25.08.39.08.13 0 .26-.02.39-.07.12-.05.23-.12.33-.22.09-.09.17-.21.22-.33.05-.12.08-.25.07-.39 0-.13-.03-.26-.08-.39-.05-.12-.13-.23-.22-.32l-.71-.71c-.19-.18-.44-.28-.7-.28-.26 0-.51.11-.7.29s-.29.44-.29.7c0 .26.1.51.28.7l.71.71ZM3 8c0 .27-.11.52-.29.71C2.52 8.9 2.27 9 2 9H1c-.27 0-.52-.11-.71-.29C.1 8.52 0 8.27 0 8s.11-.52.29-.71C.48 7.1.73 7 1 7h1c.27 0 .52.11.71.29.19.19.29.44.29.71Zm3 6v-1h4v1c0 .53-.21 1.04-.59 1.41-.38.38-.88.59-1.41.59s-1.04-.21-1.41-.59C6.21 15.03 6 14.53 6 14Zm4-2c.02-.34.21-.65.48-.86.65-.51 1.13-1.22 1.36-2.02.23-.8.21-1.65-.06-2.43-.27-.79-.78-1.47-1.46-1.95C9.64 4.26 8.83 4 8 4s-1.64.26-2.32.74C5 5.22 4.49 5.9 4.22 6.69c-.27.79-.29 1.64-.06 2.43.23.8.71 1.5 1.36 2.02.27.21.46.52.48.86h4Z"/></svg>
''';
const _locationSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M8 .12c-1.64 0-3.21.65-4.37 1.81a6.18 6.18 0 0 0-1.81 4.37c0 1.34.44 2.64 1.25 3.71l.2.25L8.01 15.86l4.75-5.6.19-.25c.81-1.07 1.25-2.37 1.25-3.71 0-1.64-.65-3.21-1.81-4.37A6.18 6.18 0 0 0 8 .12Zm0 8.44c-.45 0-.88-.13-1.25-.38-.37-.25-.66-.6-.83-1.01-.17-.41-.21-.86-.13-1.3.09-.44.3-.84.62-1.15.31-.31.72-.53 1.15-.62.44-.09.89-.04 1.3.13.41.17.76.46 1.01.83.25.37.38.81.38 1.25 0 .6-.24 1.17-.66 1.59-.42.42-.99.66-1.59.66Z"/></svg>
''';
const _bookmarkSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M4.25.5c-.6 0-1.17.24-1.59.66C2.24 1.58 2 2.15 2 2.75V14.1c0 .2.05.39.15.56.1.17.24.31.41.41.17.1.36.15.56.15.2 0 .39-.05.56-.15l3.94-2.25c.11-.06.24-.1.37-.1s.26.03.37.1l3.95 2.25c.17.1.36.15.56.15.2 0 .39-.05.56-.15.17-.1.31-.24.41-.41s.15-.36.15-.56V2.75c0-.6-.24-1.17-.66-1.59C12.91.74 12.34.5 11.74.5H4.25Z"/></svg>
''';
const _noteSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M2.75 14.75c-.41 0-.77-.15-1.06-.44-.29-.29-.44-.65-.44-1.06V2.75c0-.41.15-.77.44-1.06.29-.29.65-.44 1.06-.44h10.5c.41 0 .77.15 1.06.44.29.29.44.65.44 1.06v7.5l-4.5 4.5h-7.5Zm4.5-5.25c.21 0 .39-.07.53-.22.14-.14.22-.32.22-.53s-.07-.39-.22-.53C7.64 8.07 7.46 8 7.25 8H5c-.21 0-.39.07-.53.22-.14.14-.22.32-.22.53s.07.39.22.53c.14.14.32.22.53.22h2.25Zm3.75-3c.21 0 .39-.07.53-.22.14-.14.22-.32.22-.53s-.07-.39-.22-.53C11.39 5.07 11.21 5 11 5H5c-.21 0-.39.07-.53.22-.14.14-.22.32-.22.53s.07.39.22.53.32.22.53.22h6Zm-1.5 6.75 3.75-3.75h-3c-.21 0-.39.07-.53.22s-.22.32-.22.53v3Z"/></svg>
''';
const _positiveSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M3.33 15h-.72c-.33 0-.66-.13-.9-.35-.25-.23-.4-.54-.43-.87L.73 7.11c-.02-.18 0-.37.07-.54.06-.18.16-.34.28-.47.13-.14.28-.25.45-.32.17-.07.35-.11.54-.11h1.27c.36 0 .69.14.94.39.25.25.39.59.39.94v6.67c0 .35-.14.7-.39.94-.25.25-.59.39-.94.39Z"/><path d="m15.4 7.69-1.79 6.34c-.08.28-.25.53-.48.7-.23.17-.52.27-.81.27H6.67c-.36 0-.69-.14-.94-.39-.25-.25-.39-.59-.39-.94V7.13c0-.53.32-1.02.81-1.25.79-.37 1.38-.82 1.62-1.22.36-.6.53-1.78.57-2.65 0-.06 0-.12.01-.18.06-.41.34-.72.73-.8.07-.01.14-.02.21-.02.8 0 1.73.83 2.12 1.48.29.48.41 1.09.36 1.84-.03.55-.18 1.05-.33 1.55L11.4 6h2.72c.21 0 .41.05.6.14.18.09.34.23.47.39.12.17.21.35.24.55.04.2.03.41-.03.61Z"/></svg>
''';
const _negativeSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M3.33 1h-.72c-.33 0-.66.13-.9.35-.25.23-.4.54-.43.87L.72 8.89c-.02.18 0 .37.07.54.06.18.16.34.28.47.13.14.28.25.45.32.17.07.35.11.54.11h1.27c.36 0 .69-.14.94-.39.25-.25.39-.59.39-.94V2.33c0-.35-.14-.7-.39-.94C4.02 1.14 3.68 1 3.33 1Z"/><path d="m15.4 8.31-1.79-6.34c-.08-.28-.25-.53-.48-.7-.23-.17-.52-.27-.81-.27H6.67c-.36 0-.69.14-.94.39-.25.25-.39.59-.39.94v6.54c0 .53.32 1.02.81 1.25.79.37 1.38.82 1.62 1.22.36.6.53 1.78.57 2.65 0 .06 0 .12.01.18.06.41.34.72.73.8.07.01.14.02.21.02.8 0 1.73-.83 2.12-1.48.29-.48.41-1.09.36-1.84-.03-.55-.18-1.05-.33-1.55L11.4 10h2.72c.21 0 .41-.05.6-.14.18-.09.34-.23.47-.39.12-.17.21-.35.24-.55.04-.2.03-.41-.03-.61Z"/></svg>
''';
const _quoteSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M2.46 4.19c.94-1.01 2.35-1.53 4.21-1.53h.67v1.88l-.54.11c-.91.18-1.55.54-1.89 1.07-.18.28-.28.61-.29.94h2.05c.18 0 .35.07.47.2.13.13.2.29.2.47V12c0 .74-.6 1.33-1.33 1.33H2c-.18 0-.35-.07-.47-.2-.13-.12-.2-.29-.2-.47V7.39c0-.07-.13-1.83 1.13-3.19ZM13.33 13.33h-4c-.18 0-.35-.07-.47-.2-.13-.12-.2-.29-.2-.47V7.39c0-.07-.13-1.83 1.13-3.19.94-1.01 2.35-1.53 4.21-1.53h.67v1.88l-.54.11c-.91.18-1.55.54-1.89 1.07-.18.28-.28.61-.29.94H14c.18 0 .35.07.47.2.12.13.2.29.2.47V12c0 .74-.6 1.33-1.33 1.33Z"/></svg>
''';
const _savingsSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M12.781 8.34c-.84-.665-2.146-1.247-3.354-1.715V4.396c.696.22 1.403.478 2.123.772.096.04.209.006.265-.082l1.193-1.805a.219.219 0 0 0-.079-.314c-.68-.365-2.072-.93-3.502-1.293V.366a.27.27 0 0 0-.27-.271H6.985a.271.271 0 0 0-.271.271v.973c-2.014.092-3.38.795-4.166 2.147-.616 1.06-.613 2.255.004 3.118.645.922 1.699 1.332 3.031 1.851l.172.066c.309.118.634.239.959.359v2.715c-1.41-.335-2.736-1.023-2.98-1.189a.218.218 0 0 0-.296.048l-1.444 1.883a.211.211 0 0 0-.043.163.22.22 0 0 0 .086.145c.874.648 2.145 1.266 3.403 1.654.42.13.846.235 1.275.316v1.018c0 .148.121.27.271.27h2.173a.27.27 0 0 0 .27-.27v-.845c1.928-.16 3.368-.997 4.192-2.45.793-1.402.49-2.858-.839-3.998ZM6.712 4.014v1.643c-.624-.2-.993-.394-.953-.872.04-.49.51-.69.954-.771Zm2.716 5.875c.458.205.806.42.927.689.069.152.063.326-.016.533-.14.364-.502.553-.912.649V9.889Z"/></svg>
''';
const _upSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M10 5c-.27 0-.52-.11-.71-.29C9.1 4.52 9 4.27 9 4s.11-.52.29-.71C9.48 3.1 9.73 3 10 3h5c.27 0 .52.11.71.29.19.19.29.44.29.71v5c0 .27-.11.52-.29.71-.19.19-.44.29-.71.29s-.52-.11-.71-.29C14.1 9.52 14 9.27 14 9V6.41l-4.29 4.29c-.19.19-.44.29-.71.29s-.52-.11-.71-.29L6 8.41l-4.29 4.3c-.19.18-.44.28-.7.28-.26 0-.51-.11-.7-.29s-.3-.44-.3-.7c0-.26.1-.51.28-.7l5-5.01C5.48 6.1 5.73 6 6 6s.52.11.71.29L9 8.58l3.59-3.59H10Z"/></svg>
''';
const _downSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M10 11c-.27 0-.52.11-.71.29C9.1 11.48 9 11.73 9 12s.11.52.29.71c.19.19.44.29.71.29h5c.27 0 .52-.11.71-.29.19-.19.29-.44.29-.71V7c0-.27-.11-.52-.29-.71C15.52 6.1 15.27 6 15 6s-.52.11-.71.29C14.1 6.48 14 6.73 14 7v2.59L9.71 5.3C9.52 5.11 9.27 5 9 5s-.52.11-.71.29L6 7.58l-4.29-4.29c-.19-.18-.44-.28-.7-.28-.26 0-.51.11-.7.29S.01 3.74.01 4c0 .26.1.51.28.7l5 5c.19.19.44.29.71.29s.52-.11.71-.29L9 7.41 12.59 11H10Z"/></svg>
''';
const _forwardedSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M1.72 1.05c-.08-.04-.18-.06-.27-.05-.09 0-.18.04-.26.1-.07.06-.13.13-.16.22-.03.09-.04.18-.02.27l1.4 4.85c.03.09.08.17.15.23.07.06.16.1.25.12l5.69.95c.27.05.27.44 0 .49l-5.69.95c-.09.02-.18.06-.25.12s-.12.14-.15.23l-1.4 4.85c-.02.09-.01.19.02.27.03.09.09.16.16.22.07.06.16.09.26.1.09 0 .19 0 .27-.05l13-6.5c.08-.04.15-.11.2-.18.05-.08.07-.17.07-.26s-.03-.18-.07-.26c-.05-.08-.12-.14-.2-.18l-13-6.5Z"/></svg>
''';
const _scheduledSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M2.75 15.5h10.5c.83 0 1.5-.67 1.5-1.5V3.5c0-.83-.67-1.5-1.5-1.5h-1.5V.5h-1.5V2h-4.5V.5h-1.5V2h-1.5c-.83 0-1.5.67-1.5 1.5V14c0 .83.67 1.5 1.5 1.5Zm0-11.25h10.5v1.5H2.75v-1.5Z"/></svg>
''';

Color _brightenCheckboxColor(Color color) {
  const factor = 1.075;
  return Color.from(
    alpha: color.a,
    red: (color.r * factor).clamp(0, 1),
    green: (color.g * factor).clamp(0, 1),
    blue: (color.b * factor).clamp(0, 1),
  );
}
