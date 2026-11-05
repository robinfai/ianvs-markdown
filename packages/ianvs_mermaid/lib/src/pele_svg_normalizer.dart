import 'package:xml/xml.dart';

/// Resolve Pele's CSS custom properties before passing SVG to usvg. Browser
/// variables are not supported by the Flutter vector chain. Preserve local scope.
String normalizePeleSvg(
  String svg, {
  required bool dark,
  Map<String, String> overrides = const {},
}) {
  final document = XmlDocument.parse(svg);
  final theme = <String, String>{
    if (dark) ...{
      '--pele-bg': '#111827',
      '--pele-fg': '#e5e7eb',
      '--pele-muted': '#9ca3af',
      '--pele-line': '#cbd5e1',
      '--pele-surface': '#1f2937',
      '--pele-surface-alt': '#374151',
      '--pele-border': '#94a3b8',
      '--pele-accent': '#93c5fd',
    },
    ...overrides,
  };
  String resolve(String value, Map<String, String> vars, [int depth = 0]) {
    if (depth > 24) throw const FormatException('Cyclic Pele theme variable');
    while (value.contains('var(')) {
      final start = value.indexOf('var(');
      var end = start + 4;
      var nesting = 1;
      for (; end < value.length && nesting > 0; end++) {
        if (value[end] == '(') nesting++;
        if (value[end] == ')') nesting--;
      }
      if (nesting != 0) {
        throw const FormatException('Invalid Pele CSS variable');
      }
      final body = value.substring(start + 4, end - 1);
      final comma = body.indexOf(',');
      final key = (comma < 0 ? body : body.substring(0, comma)).trim();
      final replacement =
          vars[key] ?? (comma < 0 ? null : body.substring(comma + 1).trim());
      if (replacement == null) {
        throw FormatException('Unresolved Pele variable $key');
      }
      value = value.replaceRange(
        start,
        end,
        resolve(replacement, vars, depth + 1),
      );
    }
    return value;
  }

  void visit(XmlElement element, Map<String, String> inherited) {
    final variables = <String, String>{...inherited};
    final styles = <String, String>{};
    for (final declaration in (element.getAttribute('style') ?? '').split(
      ';',
    )) {
      final colon = declaration.indexOf(':');
      if (colon < 0) continue;
      final key = declaration.substring(0, colon).trim();
      final value = declaration.substring(colon + 1).trim();
      if (key.startsWith('--')) {
        variables[key] = value;
      } else {
        styles[key] = value;
      }
    }
    // Explicit caller variables take precedence over generated fallback aliases.
    variables.addAll(theme);
    for (final attr in element.attributes) {
      if (attr.name.local != 'style') {
        attr.value = resolve(attr.value, variables);
      }
    }
    element.removeAttribute('style');
    // usvg understands SVG presentation attributes, including rx/ry; expanding
    // these avoids a browser-only CSS geometry requirement.
    for (final entry in styles.entries) {
      final value = resolve(entry.value, variables);
      if (const {
        'rx',
        'ry',
        'fill',
        'stroke',
        'stroke-width',
        'font-family',
        'font-size',
        'font-weight',
        'color',
      }.contains(entry.key)) {
        element.setAttribute(entry.key, value);
      } else {
        final previous = element.getAttribute('style') ?? '';
        element.setAttribute('style', '$previous${entry.key}:$value;');
      }
    }
    for (final child in element.childElements) {
      visit(child, variables);
    }
  }

  visit(document.rootElement, theme);
  return document.toXmlString();
}
