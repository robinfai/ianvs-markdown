import 'package:flutter/material.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

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
    return DocumentSession(
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
  }

  final String id;
  String name;
  String? path;
  String? accessToken;
  String persistedText;
  String encoding;
  String lineEnding;
  bool hasExternalChanges = false;
  final IanvsMarkdownController controller;
  final ScrollController scrollController = ScrollController();

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'path': path,
    'accessToken': accessToken,
    'text': controller.text,
    'persistedText': persistedText,
    'mode': controller.mode.name,
    'encoding': encoding,
    'lineEnding': lineEnding,
  };

  void markSaved({String? savedText}) {
    persistedText = savedText ?? controller.text;
    hasExternalChanges = false;
    controller.markSaved(savedText: persistedText);
  }

  void replaceFromDisk(String text, {bool preserveHistory = false}) {
    final selection = controller.selection;
    controller.commitHistoryGroup();
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: selection.extentOffset.clamp(0, text.length),
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
