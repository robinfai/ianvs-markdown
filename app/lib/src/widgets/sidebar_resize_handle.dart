import 'package:ianvs_design/ianvs_design.dart';

import '../desktop_theme.dart';
import '../models/workspace_layout.dart';

/// Ianvs owns pointer, keyboard and accessibility input; the workspace owns width.
class SidebarResizeHandle extends StatelessWidget {
  const SidebarResizeHandle({
    super.key,
    required this.width,
    required this.maxWidth,
    required this.onResize,
  });

  final double width;
  final double maxWidth;
  final ValueChanged<double> onResize;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Drag to resize sidebar. Double-click to reset.',
    excludeFromSemantics: true,
    child: Theme(
      data: desktopTheme(Brightness.dark),
      child: IanvsResizeHandle(
        value: width,
        min: WorkspaceLayout.minSidebarWidth,
        max: maxWidth,
        resetValue: WorkspaceLayout.defaultSidebarWidth,
        hitExtent: 8,
        lineAlignment: Alignment.centerRight,
        semanticLabel: 'Resize sidebar',
        semanticValueFormatter: (value) => '${value.round()} points',
        onChanged: onResize,
      ),
    ),
  );
}
