import 'dart:convert';

import 'package:yaml/yaml.dart';

const int markdownFrontMatterByteLimit = 64 * 1024;
const int markdownFrontMatterLineLimit = 256;
const int markdownFrontMatterEntryLimit = 40;

final class MarkdownFrontMatterDocument {
  const MarkdownFrontMatterDocument({
    required this.body,
    required this.entries,
    required this.hasFrontMatter,
  });

  final String body;
  final List<MarkdownMetadataEntry> entries;
  final bool hasFrontMatter;
}

enum MarkdownMetadataValueType {
  text,
  number,
  boolean,
  date,
  list,
  object,
  empty,
}

final class MarkdownMetadataEntry {
  const MarkdownMetadataEntry({
    required this.key,
    required this.label,
    required this.value,
    this.items = const <String>[],
    this.type = MarkdownMetadataValueType.text,
  });

  final String key;
  final String label;
  final String value;
  final List<String> items;
  final MarkdownMetadataValueType type;

  bool get isLong => value.length > 72 || value.contains('\n');
}

/// Parses a bounded YAML front matter mapping at the start of [source].
///
/// Invalid, oversized, or non-map front matter is left in the document body.
/// Values are flattened and bounded before they are exposed to the UI.
MarkdownFrontMatterDocument parseMarkdownFrontMatter(String source) {
  final openingEnd = source.indexOf('\n');
  if (openingEnd < 0 ||
      _frontMatterMarkerLine(source.substring(0, openingEnd)) != '---') {
    return _withoutFrontMatter(source);
  }

  var lineStart = openingEnd + 1;
  var lineCount = 0;
  while (lineStart <= source.length &&
      lineCount < markdownFrontMatterLineLimit &&
      lineStart - openingEnd <= markdownFrontMatterByteLimit) {
    final newline = source.indexOf('\n', lineStart);
    final lineEnd = newline < 0 ? source.length : newline;
    final line = _frontMatterMarkerLine(source.substring(lineStart, lineEnd));
    if (line == '---') {
      final raw = source.substring(openingEnd + 1, lineStart);
      if (utf8.encode(raw).length > markdownFrontMatterByteLimit) {
        return _withoutFrontMatter(source);
      }
      final parsed = _parseMetadata(raw);
      if (parsed == null) return _withoutFrontMatter(source);
      final bodyStart = newline < 0 ? source.length : newline + 1;
      return MarkdownFrontMatterDocument(
        body: source.substring(bodyStart),
        entries: parsed,
        hasFrontMatter: true,
      );
    }
    if (newline < 0) break;
    lineStart = newline + 1;
    lineCount += 1;
  }
  return _withoutFrontMatter(source);
}

String _frontMatterMarkerLine(String line) =>
    line.endsWith('\r') ? line.substring(0, line.length - 1) : line;

MarkdownFrontMatterDocument _withoutFrontMatter(String source) {
  return MarkdownFrontMatterDocument(
    body: source,
    entries: const <MarkdownMetadataEntry>[],
    hasFrontMatter: false,
  );
}

List<MarkdownMetadataEntry>? _parseMetadata(String raw) {
  final Object? value;
  try {
    value = loadYaml(raw);
  } on Object {
    return null;
  }
  if (value == null) return const <MarkdownMetadataEntry>[];
  if (value is! Map<Object?, Object?>) return null;

  final result = <MarkdownMetadataEntry>[];
  _collectMetadata(value, result: result);
  // Obsidian's properties panel follows YAML source order. Reordering common
  // keys such as title/author makes the structured view disagree with Source.
  return List<MarkdownMetadataEntry>.unmodifiable(result);
}

void _collectMetadata(
  Map<Object?, Object?> values, {
  required List<MarkdownMetadataEntry> result,
}) {
  for (final entry in values.entries) {
    if (result.length >= markdownFrontMatterEntryLimit) return;
    final key = _boundedText(entry.key, 80);
    if (key.isEmpty) continue;
    final value = entry.value;
    final type = _metadataValueType(value);
    final items = value is Iterable<Object?>
        ? value
              .take(16)
              .map((item) => _metadataItemText(item, 160))
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    final displayValue = switch (type) {
      MarkdownMetadataValueType.object => _boundedJson(value, 1200),
      MarkdownMetadataValueType.date => _metadataDateText(value),
      _ => items.isNotEmpty ? items.join(' · ') : _boundedText(value, 1200),
    };
    // Obsidian keeps explicit empty properties visible and renders their
    // value as a placeholder. Dropping them here made the compact properties
    // panel silently disagree with the source document.
    if (displayValue.isEmpty && value != null && value is! String) continue;
    result.add(
      MarkdownMetadataEntry(
        key: key,
        label: _metadataLabel(key),
        value: displayValue,
        items: items,
        type: type,
      ),
    );
  }
}

MarkdownMetadataValueType _metadataValueType(Object? value) {
  if (value == null || (value is String && value.trim().isEmpty)) {
    return MarkdownMetadataValueType.empty;
  }
  if (value is bool) return MarkdownMetadataValueType.boolean;
  if (value is num) return MarkdownMetadataValueType.number;
  if (value is Map<Object?, Object?>) {
    return MarkdownMetadataValueType.object;
  }
  if (value is Iterable<Object?>) return MarkdownMetadataValueType.list;
  if (value is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return MarkdownMetadataValueType.date;
  }
  if (value is DateTime &&
      value.hour == 0 &&
      value.minute == 0 &&
      value.second == 0 &&
      value.millisecond == 0 &&
      value.microsecond == 0) {
    return MarkdownMetadataValueType.date;
  }
  return MarkdownMetadataValueType.text;
}

String _metadataDateText(Object? value) {
  if (value is String) return value;
  if (value is DateTime) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }
  return _boundedText(value, 32);
}

String _metadataItemText(Object? value, int maximumCharacters) {
  if (value is Map<Object?, Object?> || value is Iterable<Object?>) {
    return _boundedJson(value, maximumCharacters);
  }
  return _boundedText(value, maximumCharacters);
}

String _boundedJson(Object? value, int maximumCharacters) {
  final text = jsonEncode(_plainYamlValue(value));
  if (text.length <= maximumCharacters) return text;
  return '${text.substring(0, maximumCharacters)}…';
}

Object? _plainYamlValue(Object? value) {
  if (value is Map<Object?, Object?>) {
    return <String, Object?>{
      for (final entry in value.entries)
        _boundedText(entry.key, 80): _plainYamlValue(entry.value),
    };
  }
  if (value is Iterable<Object?>) {
    return value.map(_plainYamlValue).toList(growable: false);
  }
  if (value is DateTime) return value.toIso8601String();
  return value;
}

String _boundedText(Object? value, int maximumCharacters) {
  final text = switch (value) {
    null => '',
    bool() => value ? 'true' : 'false',
    DateTime() => value.toIso8601String(),
    _ => value.toString().trim(),
  };
  if (text.length <= maximumCharacters) return text;
  return '${text.substring(0, maximumCharacters)}…';
}

String _metadataLabel(String key) {
  final normalized = key.toLowerCase().replaceAll('-', '_');
  return _metadataLabels[normalized] ?? key;
}

const Map<String, String> _metadataLabels = <String, String>{
  'title': '标题',
  'subtitle': '副标题',
  'description': '摘要',
  'summary': '摘要',
  'author': '作者',
  'authors': '作者',
  'date': '日期',
  'created': '创建时间',
  'updated': '更新时间',
  'last_modified': '更新时间',
  'tags': '标签',
  'tag': '标签',
  'categories': '分类',
  'category': '分类',
  'status': '状态',
  'draft': '草稿',
  'slug': '路径',
  'version': '版本',
  'lang': '语言',
  'language': '语言',
};
