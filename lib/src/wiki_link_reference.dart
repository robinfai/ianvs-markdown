/// One structurally valid Obsidian Wiki-link body.
///
/// Obsidian only treats `|` as an alias separator when a non-empty target
/// precedes it. A leading pipe therefore belongs to the target itself:
/// `[[|Alias]]` links to and displays `|Alias`.
final class IanvsMarkdownWikiLinkReference {
  const IanvsMarkdownWikiLinkReference({
    required this.target,
    required this.label,
    required this.aliasSeparator,
  });

  final String target;
  final String label;
  final int? aliasSeparator;
}

IanvsMarkdownWikiLinkReference? parseIanvsMarkdownWikiLinkBody(String body) {
  if (body.isEmpty) return null;
  final candidateSeparator = body.indexOf('|');
  final aliasSeparator = candidateSeparator > 0 ? candidateSeparator : null;
  final target =
      (aliasSeparator == null ? body : body.substring(0, aliasSeparator))
          .trim();
  final label =
      (aliasSeparator == null ? body : body.substring(aliasSeparator + 1))
          .trim();
  if (target.isEmpty || label.isEmpty) return null;
  return IanvsMarkdownWikiLinkReference(
    target: target,
    label: label,
    aliasSeparator: aliasSeparator,
  );
}
