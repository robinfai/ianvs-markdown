import 'dart:convert';

import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'workspace_reference_index.dart';

class CollectionNote {
  CollectionNote(this.note, this.relativePath)
    : properties = {
        for (final entry in parseMarkdownFrontMatter(note.source.text).entries)
          entry.key: entry,
      };
  final WorkspaceSemanticNote note;
  final String relativePath;
  final Map<String, MarkdownMetadataEntry> properties;
  String value(String key) =>
      key == 'filename' ? relativePath : properties[key]?.value ?? '';
}

List<CollectionNote> collectionNotes(
  WorkspaceReferenceSnapshot snapshot,
  String root, {
  String folder = '',
  String tag = '',
  String property = '',
  String equals = '',
  String sort = 'filename',
  bool descending = false,
}) {
  final rows = <CollectionNote>[];
  final tagPaths = {
    for (final occurrence
        in snapshot.tags[tag.replaceFirst(RegExp(r'^#'), '')] ?? [])
      occurrence.note.source.path,
  };
  final prefix = folder.replaceAll(RegExp(r'^/+|/+$'), '');
  for (final note in snapshot.notes.values) {
    final path = note.source.path;
    if (path == null || !p.isWithin(root, path)) continue;
    final relative = p.relative(path, from: root);
    if (prefix.isNotEmpty && !relative.startsWith('$prefix/')) continue;
    if (tag.isNotEmpty && !tagPaths.contains(path)) continue;
    final row = CollectionNote(note, relative);
    if (property.isNotEmpty && row.value(property) != equals) continue;
    rows.add(row);
  }
  rows.sort((a, b) {
    final av = a.value(sort);
    final bv = b.value(sort);
    final an = num.tryParse(av);
    final bn = num.tryParse(bv);
    var result = an != null && bn != null ? an.compareTo(bn) : av.compareTo(bv);
    if (result == 0) result = a.relativePath.compareTo(b.relativePath);
    return descending ? -result : result;
  });
  return rows;
}

// Read the original YAML, never the bounded display metadata, for edits.
({YamlNode node, int offset})? _collectionYaml(String source) {
  if (!parseMarkdownFrontMatter(source).hasFrontMatter) return null;
  final offset = source.indexOf('\n') + 1;
  final closing = RegExp(
    r'^---\r?$',
    multiLine: true,
  ).allMatches(source).firstWhere((match) => match.start >= offset);
  return (
    node: loadYamlNode(source.substring(offset, closing.start)),
    offset: offset,
  );
}

String collectionPropertyEditValue(String source, String key) {
  final yaml = _collectionYaml(source)?.node;
  if (yaml is! YamlMap) return '';
  final value = yaml[key];
  if (value is List) return jsonEncode(value);
  if (value is Map) {
    throw const FormatException('Edit nested objects in Source mode.');
  }
  return value?.toString() ?? '';
}

String editCollectionProperty(String source, String key, String value) {
  final result = _editCollectionProperty(source, key, value);
  if (result == source) return source;
  final before = parseMarkdownFrontMatter(source);
  final after = parseMarkdownFrontMatter(result);
  if (!after.hasFrontMatter || after.body != before.body) {
    throw const FormatException('This YAML structure needs editing in Source mode.');
  }
  return result;
}

String _editCollectionProperty(String source, String key, String value) {
  if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_-]*$').hasMatch(key)) {
    throw const FormatException('Use a simple property name.');
  }
  final parsed = parseMarkdownFrontMatter(source);
  MarkdownMetadataEntry? entry;
  for (final candidate in parsed.entries) {
    if (candidate.key == key) entry = candidate;
  }
  if (entry != null && value == collectionPropertyEditValue(source, key)) {
    return source;
  }
  if (entry == null) {
    final newline = source.contains('\r\n') ? '\r\n' : '\n';
    final line = '$key: ${jsonEncode(value)}$newline';
    if (parsed.hasFrontMatter) {
      if (parsed.entries.length >= markdownFrontMatterEntryLimit) {
        throw const FormatException(
          'This note has more properties than this view can safely edit. Use Source mode.',
        );
      }
      final yaml = _collectionYaml(source)!;
      final node = yaml.node;
      if (node is YamlMap && node.span.text.startsWith('{')) {
        final offset = yaml.offset + node.span.start.offset + 1;
        return source.replaceRange(
          offset,
          offset,
          '${jsonEncode(key)}: ${jsonEncode(value)}${node.isEmpty ? '' : ', '}',
        );
      }
      return source.replaceRange(
        source.indexOf('\n') + 1,
        source.indexOf('\n') + 1,
        line,
      );
    }
    if (source.startsWith('---')) {
      throw const FormatException(
        'Repair the front matter in Source mode first.',
      );
    }
    return '---$newline$line---$newline$source';
  }
  return switch (entry.type) {
    MarkdownMetadataValueType.boolean => switch (value) {
      'true' => replaceMarkdownFrontMatterBooleanValue(source, entry, true),
      'false' => replaceMarkdownFrontMatterBooleanValue(source, entry, false),
      _ => throw const FormatException('Enter true or false.'),
    },
    MarkdownMetadataValueType.number => replaceMarkdownFrontMatterNumberValue(
      source,
      entry,
      num.parse(value),
    ),
    MarkdownMetadataValueType.date => replaceMarkdownFrontMatterDateValue(
      source,
      entry,
      value,
    ),
    MarkdownMetadataValueType.list => replaceMarkdownFrontMatterListValue(
      source,
      entry,
      (jsonDecode(value) as List).cast<String>(),
    ),
    MarkdownMetadataValueType.object => throw const FormatException(
      'Edit nested objects in Source mode.',
    ),
    _ => replaceMarkdownFrontMatterTextValue(source, entry, value),
  };
}
