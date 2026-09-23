/// Selects the built-in syntax and source transformations of `IanvsMarkdown`.
enum IanvsMarkdownSyntaxPreset {
  /// Obsidian-compatible documents, including metadata, math, and inert HTML
  /// controls. This preserves the renderer's original behavior.
  obsidian,

  /// Standard Markdown with GFM extensions by default.
  ///
  /// Does not add Obsidian syntax, math, HTML controls, or source projections.
  /// Hosts can still supply an extension set, custom syntax, and builders.
  /// Images remain blocked unless the host supplies an image builder.
  standard,
}
