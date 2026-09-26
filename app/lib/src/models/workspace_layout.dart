abstract final class WorkspaceLayout {
  static const defaultSidebarWidth = 248.0;
  static const minSidebarWidth = 180.0;
  static const maxSidebarWidth = 560.0;
  static const minEditorWidth = 320.0;
  static const minContentWidth = 480.0;

  static double normalizeSidebarWidth(double width) => width.isFinite
      ? width.clamp(minSidebarWidth, maxSidebarWidth)
      : defaultSidebarWidth;
}
