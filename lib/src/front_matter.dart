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
    this.sourceKeyStart,
    this.sourceKeyEnd,
    this.sourceValueStart,
    this.sourceValueEnd,
  });

  final String key;
  final String label;
  final String value;
  final List<String> items;
  final MarkdownMetadataValueType type;

  /// UTF-16 source offsets for the top-level YAML key and value.
  ///
  /// These offsets are relative to the complete Markdown source passed to
  /// [parseMarkdownFrontMatter]. They let an editor update one property while
  /// retaining comments and unsupported YAML that Obsidian leaves untouched.
  final int? sourceKeyStart;
  final int? sourceKeyEnd;
  final int? sourceValueStart;
  final int? sourceValueEnd;

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
      final parsed = _parseMetadata(raw, sourceOffset: openingEnd + 1);
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

List<MarkdownMetadataEntry>? _parseMetadata(
  String raw, {
  required int sourceOffset,
}) {
  final YamlNode value;
  try {
    value = loadYamlNode(raw);
  } on Object {
    return null;
  }
  if (value is YamlScalar && value.value == null) {
    return const <MarkdownMetadataEntry>[];
  }
  if (value is! YamlMap) return null;

  final result = <MarkdownMetadataEntry>[];
  _collectMetadata(value, result: result, sourceOffset: sourceOffset);
  // Obsidian's properties panel follows YAML source order. Reordering common
  // keys such as title/author makes the structured view disagree with Source.
  return List<MarkdownMetadataEntry>.unmodifiable(result);
}

void _collectMetadata(
  YamlMap values, {
  required List<MarkdownMetadataEntry> result,
  required int sourceOffset,
}) {
  for (final entry in values.nodes.entries) {
    if (result.length >= markdownFrontMatterEntryLimit) return;
    final keyNode = entry.key as YamlNode;
    final valueNode = entry.value;
    final key = _boundedText(keyNode.value, 80);
    if (key.isEmpty) continue;
    final value = valueNode.value;
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
        sourceKeyStart: sourceOffset + keyNode.span.start.offset,
        sourceKeyEnd: sourceOffset + keyNode.span.end.offset,
        sourceValueStart: sourceOffset + valueNode.span.start.offset,
        sourceValueEnd: sourceOffset + valueNode.span.end.offset,
      ),
    );
  }
}

/// Replaces one top-level front-matter property with a text scalar.
///
/// Obsidian's Properties editor rewrites top-level flow lists to block lists
/// when a field is committed. This function mirrors that observed rewrite but
/// otherwise edits source spans in place, preserving key order, comments, and
/// YAML constructs that the property panel does not own.
String replaceMarkdownFrontMatterTextValue(
  String source,
  MarkdownMetadataEntry entry,
  String value,
) => _replaceMarkdownFrontMatterValue(
  source,
  entry,
  _yamlTextScalar(value),
  canonicalizeFlowLists: true,
);

/// Replaces one top-level front-matter property with a boolean scalar.
String replaceMarkdownFrontMatterBooleanValue(
  String source,
  MarkdownMetadataEntry entry,
  bool value,
) => _replaceMarkdownFrontMatterValue(
  source,
  entry,
  value ? 'true' : 'false',
  canonicalizeFlowLists: false,
);

/// Replaces one top-level front-matter property with a finite number scalar.
///
/// Like a text-property commit, Obsidian also canonicalizes unrelated
/// top-level flow lists when a number field is committed.
String replaceMarkdownFrontMatterNumberValue(
  String source,
  MarkdownMetadataEntry entry,
  num value,
) {
  if (!value.isFinite) return source;
  return _replaceMarkdownFrontMatterValue(
    source,
    entry,
    '$value',
    canonicalizeFlowLists: true,
  );
}

String _replaceMarkdownFrontMatterValue(
  String source,
  MarkdownMetadataEntry entry,
  String replacement, {
  required bool canonicalizeFlowLists,
}) {
  final valueStart = entry.sourceValueStart;
  final valueEnd = entry.sourceValueEnd;
  if (valueStart == null ||
      valueEnd == null ||
      valueStart < 0 ||
      valueEnd < valueStart ||
      valueEnd > source.length) {
    return source;
  }

  final openingEnd = source.indexOf('\n');
  if (openingEnd < 0 ||
      _frontMatterMarkerLine(source.substring(0, openingEnd)) != '---') {
    return source;
  }
  final closingStart = _frontMatterClosingStart(source, openingEnd + 1);
  if (closingStart == null || valueEnd > closingStart) return source;
  final raw = source.substring(openingEnd + 1, closingStart);
  final YamlNode root;
  try {
    root = loadYamlNode(raw);
  } on Object {
    return source;
  }
  if (root is! YamlMap) return source;

  final rawOffset = openingEnd + 1;
  final targetFound = root.nodes.entries.any((nodeEntry) {
    final keyNode = nodeEntry.key as YamlNode;
    final valueNode = nodeEntry.value;
    return rawOffset + keyNode.span.start.offset == entry.sourceKeyStart &&
        rawOffset + keyNode.span.end.offset == entry.sourceKeyEnd &&
        rawOffset + valueNode.span.start.offset == valueStart &&
        rawOffset + valueNode.span.end.offset == valueEnd;
  });
  if (!targetFound) return source;

  final edits = <_FrontMatterSourceEdit>[
    _FrontMatterSourceEdit(
      start: valueStart,
      end: valueEnd,
      replacement: replacement,
    ),
  ];
  final lineBreak = source.contains('\r\n') ? '\r\n' : '\n';
  for (final nodeEntry
      in canonicalizeFlowLists
          ? root.nodes.entries
          : const <MapEntry<dynamic, YamlNode>>[]) {
    final keyNode = nodeEntry.key as YamlNode;
    final valueNode = nodeEntry.value;
    if (valueNode is! YamlList ||
        valueNode.style != CollectionStyle.FLOW ||
        valueNode.nodes.any((node) => node is! YamlScalar)) {
      continue;
    }
    final flowStart = rawOffset + valueNode.span.start.offset;
    final flowEnd = rawOffset + valueNode.span.end.offset;
    if (valueStart < flowEnd && valueEnd > flowStart) continue;
    final keyEnd = rawOffset + keyNode.span.end.offset;
    final separator = source.indexOf(':', keyEnd);
    if (separator < keyEnd || separator >= flowStart) continue;
    final flowLineEnd = source.indexOf('\n', flowEnd);
    final trailing = source.substring(
      flowEnd,
      flowLineEnd < 0 ? source.length : flowLineEnd,
    );
    if (trailing.trim().isNotEmpty) continue;
    final lineStart = source.lastIndexOf('\n', keyEnd - 1) + 1;
    final keyStart = rawOffset + keyNode.span.start.offset;
    final indentation = source.substring(lineStart, keyStart);
    final items = valueNode.nodes
        .cast<YamlScalar>()
        .map((node) => '$indentation  - ${_yamlScalarNodeSource(node)}')
        .join(lineBreak);
    edits.add(
      _FrontMatterSourceEdit(
        start: separator + 1,
        end: flowEnd,
        replacement: items.isEmpty ? ' []' : '$lineBreak$items',
      ),
    );
  }

  edits.sort((left, right) => right.start.compareTo(left.start));
  var updated = source;
  for (final edit in edits) {
    if (edit.start < 0 || edit.end < edit.start || edit.end > updated.length) {
      return source;
    }
    updated = updated.replaceRange(edit.start, edit.end, edit.replacement);
  }
  return updated;
}

int? _frontMatterClosingStart(String source, int lineStart) {
  var start = lineStart;
  while (start <= source.length) {
    final newline = source.indexOf('\n', start);
    final end = newline < 0 ? source.length : newline;
    if (_frontMatterMarkerLine(source.substring(start, end)) == '---') {
      return start;
    }
    if (newline < 0) return null;
    start = newline + 1;
  }
  return null;
}

String _yamlScalarNodeSource(YamlScalar node) {
  final value = node.value;
  return switch (value) {
    null => 'null',
    bool() => value ? 'true' : 'false',
    num() => '$value',
    DateTime()
        when value.hour == 0 &&
            value.minute == 0 &&
            value.second == 0 &&
            value.millisecond == 0 &&
            value.microsecond == 0 =>
      _metadataDateText(value),
    DateTime() => value.toIso8601String(),
    _ => _yamlTextScalar('$value'),
  };
}

String _yamlTextScalar(String value) {
  if (value.isEmpty ||
      value.trim() != value ||
      value.contains('\n') ||
      value.contains('\r') ||
      value.codeUnits.any((unit) => unit < 0x20) ||
      RegExp(
        r'^(?:null|~|true|false|yes|no|on|off)$',
        caseSensitive: false,
      ).hasMatch(value) ||
      num.tryParse(value) != null ||
      RegExp(r'^\d{4}-\d{2}-\d{2}(?:[Tt ].*)?$').hasMatch(value) ||
      RegExp(r'''^[\-?:,!&*#{}\[\]|>@`"'%]''').hasMatch(value) ||
      value.endsWith(':') ||
      value.contains(': ') ||
      value.contains(':\t') ||
      value.contains(' #')) {
    return jsonEncode(value);
  }
  return value;
}

final class _FrontMatterSourceEdit {
  const _FrontMatterSourceEdit({
    required this.start,
    required this.end,
    required this.replacement,
  });

  final int start;
  final int end;
  final String replacement;
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
