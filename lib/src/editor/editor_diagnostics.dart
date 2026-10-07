import 'package:flutter/foundation.dart';

/// Internal counters for tests and opt-in profile runs; not a public export.
abstract final class IanvsMarkdownEditorDiagnostics {
  static const enabled =
      kDebugMode || bool.fromEnvironment('IANVS_MARKDOWN_DIAGNOSTICS');
  static const forceDocumentRefresh =
      enabled && bool.fromEnvironment('IANVS_MARKDOWN_FORCE_DOCUMENT_PARSE');

  static var _documentParses = 0;
  static int get documentParses => _documentParses;

  static void recordDocumentParse() {
    if (enabled) _documentParses += 1;
  }
}
