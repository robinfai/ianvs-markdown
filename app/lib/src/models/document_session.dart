import 'package:flutter/material.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

import 'document_analysis.dart';

class DocumentSession {
  DocumentSession({
    required this.id,
    required this.name,
    required String text,
    this.path,
    this.accessToken,
    String? persistedText,
    IanvsMarkdownEditorMode mode = IanvsMarkdownEditorMode.livePreview,
    this.encoding = 'UTF-8',
    this.lineEnding = 'LF',
  }) : persistedText = persistedText ?? text,
       controller = IanvsMarkdownController(
         text: persistedText ?? text,
         mode: mode,
       ) {
    if (text != this.persistedText) {
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  factory DocumentSession.fromJson(Map<String, Object?> json) {
    final modeName = json['mode'] as String?;
    final mode = IanvsMarkdownEditorMode.values.firstWhere(
      (value) => value.name == modeName,
      orElse: () => IanvsMarkdownEditorMode.livePreview,
    );
    final document = DocumentSession(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Untitled.md',
      text: json['text'] as String? ?? '',
      path: json['path'] as String?,
      accessToken: json['accessToken'] as String?,
      persistedText: json['persistedText'] as String?,
      mode: mode,
      encoding: json['encoding'] as String? ?? 'UTF-8',
      lineEnding: json['lineEnding'] as String? ?? 'LF',
    );
    final selection = json['selection'];
    if (selection is Map) {
      final base = selection['base'];
      final extent = selection['extent'];
      if (base is int &&
          extent is int &&
          base >= 0 &&
          extent >= 0 &&
          base <= document.controller.text.length &&
          extent <= document.controller.text.length) {
        document.controller.selection = TextSelection(
          baseOffset: base,
          extentOffset: extent,
          affinity: selection['affinity'] == 'upstream'
              ? TextAffinity.upstream
              : TextAffinity.downstream,
          isDirectional: selection['directional'] == true,
        );
      }
    }
    final viewport = json['viewport'];
    if (viewport is Map) {
      final offset = viewport['sourceOffset'];
      final dy = viewport['viewportOffset'];
      if (offset is int && dy is num && dy.isFinite) {
        document.controller.rememberViewport(
          IanvsMarkdownViewportAnchor(
            source: document.controller.text,
            sourceOffset: offset,
            viewportOffset: dy.toDouble(),
          ),
        );
      }
    }
    document.lastActivated = json['lastActivated'] as int? ?? 0;
    return document;
  }

  int lastActivated = DateTime.now().millisecondsSinceEpoch;

  final String id;
  String name;
  String? path;
  String? accessToken;
  String persistedText;
  String encoding;
  String lineEnding;
  bool hasExternalChanges = false;
  final IanvsMarkdownController controller;
  final DocumentAnalysis analysis = DocumentAnalysis();
  final ScrollController scrollController = ScrollController();

  Map<String, Object?> toJson() => <String, Object?>{
    'lastActivated': lastActivated,
    'id': id,
    'name': name,
    'path': path,
    'accessToken': accessToken,
    'text': controller.text,
    'persistedText': persistedText,
    'mode': controller.mode.name,
    'encoding': encoding,
    'lineEnding': lineEnding,
    if (controller.viewportAnchor.value case final anchor?)
      'viewport': <String, Object?>{
        'sourceOffset': anchor.sourceOffset,
        'viewportOffset': anchor.viewportOffset,
      },
    if (controller.selection.isValid)
      'selection': <String, Object?>{
        'base': controller.selection.baseOffset,
        'extent': controller.selection.extentOffset,
        'affinity': controller.selection.affinity.name,
        'directional': controller.selection.isDirectional,
      },
  };

  void markSaved({String? savedText}) {
    persistedText = savedText ?? controller.text;
    hasExternalChanges = false;
    controller.markSaved(savedText: persistedText);
  }

  void replaceFromDisk(String text, {bool preserveHistory = false}) {
    final selection = controller.selection;
    final previous = controller.text;
    // Preserve positions in the unchanged prefix/suffix. For a replaced span,
    // fall back to its start instead of selecting unrelated replacement text.
    var prefix = 0;
    while (prefix < previous.length &&
        prefix < text.length &&
        previous.codeUnitAt(prefix) == text.codeUnitAt(prefix)) {
      prefix++;
    }
    bool splitsSurrogate(String source, int offset) =>
        offset > 0 &&
        offset < source.length &&
        source.codeUnitAt(offset - 1) >= 0xd800 &&
        source.codeUnitAt(offset - 1) <= 0xdbff &&
        source.codeUnitAt(offset) >= 0xdc00 &&
        source.codeUnitAt(offset) <= 0xdfff;
    if (splitsSurrogate(previous, prefix) || splitsSurrogate(text, prefix)) {
      prefix--;
    }
    var suffix = 0;
    while (suffix < previous.length - prefix &&
        suffix < text.length - prefix &&
        previous.codeUnitAt(previous.length - suffix - 1) ==
            text.codeUnitAt(text.length - suffix - 1)) {
      suffix++;
    }
    if (splitsSurrogate(previous, previous.length - suffix) ||
        splitsSurrogate(text, text.length - suffix)) {
      suffix--;
    }
    int relocate(int offset) {
      if (offset < 0) return 0;
      if (offset <= prefix) return offset;
      if (offset >= previous.length - suffix) {
        return (offset + text.length - previous.length).clamp(0, text.length);
      }
      return prefix;
    }

    controller.commitHistoryGroup();
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: relocate(selection.baseOffset),
        extentOffset: relocate(selection.extentOffset),
        affinity: selection.affinity,
        isDirectional: selection.isDirectional,
      ),
    );
    if (preserveHistory) {
      // Reload is a single reversible edit. Undo recovers the local draft,
      // while the saved baseline continues to describe the bytes on disk.
      controller.commitHistoryGroup();
    } else {
      controller.clearHistory();
    }
    controller.markSaved(savedText: text);
    persistedText = text;
    hasExternalChanges = false;
  }

  void dispose() {
    scrollController.dispose();
    controller.dispose();
  }
}
