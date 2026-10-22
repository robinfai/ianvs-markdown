import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

import '../services/literal_source_matcher.dart';

/// Literal, non-overlapping search over the current unsaved source buffer.
///
/// This is transient UI state, not a file index or a second document model.
class DocumentFindController extends ChangeNotifier {
  DocumentFindController({
    required this.document,
    String query = '',
    String replacement = '',
    this._matchCase = false,
    this.readOnly = false,
    bool revealInitialMatch = true,
  }) : query = TextEditingController(text: query),
       replacement = TextEditingController(text: replacement),
       _source = document.text {
    this.query.addListener(_queryChanged);
    this.replacement.addListener(_replacementChanged);
    document.addListener(_documentChanged);
    _refresh(reveal: revealInitialMatch);
  }

  // Small documents stay immediate. Large searches yield between bounded source
  // windows, including when there are no matches, rather than scanning the whole
  // remaining document in a single RegExp iterator step.
  static const _synchronousLimit = 64 * 1024;
  static const _chunkSize = 16 * 1024;
  static const _debounce = Duration(milliseconds: 150);

  final IanvsMarkdownController document;
  final TextEditingController query;
  final TextEditingController replacement;
  bool readOnly;
  bool _matchCase;
  String _source;
  String _effectiveQuery = '';
  List<TextRange> _matches = const [];
  int _currentIndex = -1;
  bool _updating = false;
  bool _disposed = false;
  bool _isSearching = false;
  int _generation = 0;
  Timer? _searchTimer;
  ({bool backwards, bool skipCurrentSelection})? _pendingNavigation;
  bool _completionSelectionMoved = false;
  TextSelection _documentSelection = const TextSelection.collapsed(offset: -1);
  TextRange _queryComposition = TextRange.empty;
  TextRange _replacementComposition = TextRange.empty;
  TextRange _documentComposition = TextRange.empty;
  IanvsMarkdownSourceHighlight? _highlight;

  bool get matchCase => _matchCase;
  List<TextRange> get matches => List.unmodifiable(_matches);
  int get count => _matches.length;
  int get currentIndex => _currentIndex;
  TextRange? get currentMatch =>
      _currentIndex < 0 ? null : _matches[_currentIndex];
  IanvsMarkdownSourceHighlight? get highlight => _highlight;
  bool get isSearching => _isSearching;
  bool get isComposing =>
      _composing(query.value) ||
      _composing(replacement.value) ||
      _composing(document.value);
  bool get canNavigate =>
      !_disposed &&
      !_isSearching &&
      !isComposing &&
      _source == document.text &&
      _effectiveQuery == query.text &&
      _matches.isNotEmpty;
  bool get canReplace => !readOnly && canNavigate && _highlight != null;
  bool get canReplaceAll => !readOnly && canNavigate;

  static bool _composing(TextEditingValue value) =>
      value.composing.isValid && !value.composing.isCollapsed;

  void setMatchCase(bool value) {
    if (_disposed || isComposing || value == _matchCase) return;
    _matchCase = value;
    _refresh(reveal: true);
    notifyListeners();
  }

  void _queryChanged() {
    if (query.text != _effectiveQuery ||
        query.value.composing != _queryComposition) {
      _refresh(reveal: true);
    }
    notifyListeners();
  }

  void _replacementChanged() {
    if (replacement.value.composing != _replacementComposition) {
      _refresh(reveal: false);
    }
    notifyListeners();
  }

  void _documentChanged() {
    if (_updating) return;
    if (document.text != _source ||
        document.value.composing != _documentComposition) {
      // Typing and undo update results without replacing the user's caret.
      _refresh(reveal: false);
    } else if (_isSearching && document.selection != _documentSelection) {
      // A delayed search must not steal a caret the user moved while waiting.
      _completionSelectionMoved = true;
      _pendingNavigation = null;
    }
    _documentSelection = document.selection;
    notifyListeners();
  }

  void _refresh({required bool reveal, int? anchor}) {
    final generation = ++_generation;
    _searchTimer?.cancel();
    _searchTimer = null;
    _pendingNavigation = null;
    _completionSelectionMoved = false;
    _documentSelection = document.selection;
    _isSearching = false;
    _source = document.text;
    _effectiveQuery = query.text;
    _queryComposition = query.value.composing;
    _replacementComposition = replacement.value.composing;
    _documentComposition = document.value.composing;
    _highlight = null;
    _matches = const [];
    _currentIndex = -1;
    if (_effectiveQuery.isEmpty || isComposing) return;

    final source = _source;
    final searchQuery = _effectiveQuery;
    final matchCase = _matchCase;
    final scanner = LiteralSourceMatcher(
      source,
      searchQuery,
      matchCase: matchCase,
    );
    if (source.length < _synchronousLimit) {
      _publish(
        scanner.next(chunkSize: _synchronousLimit),
        reveal: reveal,
        anchor: anchor,
      );
      return;
    }

    _isSearching = true;
    final matches = <TextRange>[];
    bool isCurrent() =>
        !_disposed &&
        generation == _generation &&
        source == document.text &&
        searchQuery == query.text &&
        matchCase == _matchCase &&
        !isComposing;

    void scanChunk() {
      if (!isCurrent()) return;
      matches.addAll(scanner.next(chunkSize: _chunkSize));
      if (!scanner.complete) {
        _searchTimer = Timer(Duration.zero, scanChunk);
      } else if (isCurrent()) {
        _searchTimer = null;
        _publish(matches, reveal: reveal, anchor: anchor);
        notifyListeners();
      }
    }

    _searchTimer = Timer(_debounce, scanChunk);
  }

  void _publish(List<TextRange> matches, {required bool reveal, int? anchor}) {
    _isSearching = false;
    _matches = matches;
    final pendingNavigation = _pendingNavigation;
    _pendingNavigation = null;
    if (pendingNavigation != null) {
      _navigate(
        backwards: pendingNavigation.backwards,
        skipCurrentSelection: pendingNavigation.skipCurrentSelection,
      );
    } else if (reveal && !_completionSelectionMoved) {
      final start = anchor ?? document.selection.start.clamp(0, _source.length);
      _currentIndex = _matches.indexWhere((match) => match.start >= start);
      if (_currentIndex < 0 && _matches.isNotEmpty) _currentIndex = 0;
      _reveal();
    }
  }

  void _reveal() {
    final range = currentMatch;
    if (range == null || isComposing) return;
    _updating = true;
    try {
      document.selection = TextSelection(
        baseOffset: range.start,
        extentOffset: range.end,
      );
      _documentSelection = document.selection;
      _highlight = IanvsMarkdownSourceHighlight(source: _source, range: range);
    } finally {
      _updating = false;
    }
  }

  void next({bool backwards = false, bool skipCurrentSelection = false}) {
    if (_disposed || isComposing) return;
    if (_isSearching) {
      // The shell reveals after its Source editor has mounted. Preserve that
      // navigation intent when this search has not finished by the next frame.
      _pendingNavigation = (
        backwards: backwards,
        skipCurrentSelection: skipCurrentSelection,
      );
      return;
    }
    if (!canNavigate) return;
    _navigate(backwards: backwards, skipCurrentSelection: skipCurrentSelection);
    notifyListeners();
  }

  void _navigate({
    required bool backwards,
    required bool skipCurrentSelection,
  }) {
    if (_matches.isEmpty) return;
    if (_highlight == null) {
      final anchor = document.selection.start.clamp(0, _source.length);
      _currentIndex = backwards
          ? _matches.lastIndexWhere((match) => match.end <= anchor)
          : _matches.indexWhere((match) => match.start >= anchor);
      if (_currentIndex < 0) {
        _currentIndex = backwards ? _matches.length - 1 : 0;
      }
      final match = currentMatch!;
      if (skipCurrentSelection &&
          match.start == document.selection.start &&
          match.end == document.selection.end) {
        _currentIndex =
            (_currentIndex + (backwards ? -1 : 1)) % _matches.length;
      }
    } else {
      _currentIndex = (_currentIndex + (backwards ? -1 : 1)) % _matches.length;
    }
    _reveal();
  }

  bool replaceCurrent() {
    if (!canReplace) return false;
    final range = currentMatch!;
    final inserted = replacement.text;
    final updated = _source.replaceRange(range.start, range.end, inserted);
    _applyReplacement(updated, range.start + inserted.length);
    return true;
  }

  int replaceAll() {
    if (!canReplaceAll) return 0;
    final count = _matches.length;
    final inserted = replacement.text;
    final result = StringBuffer();
    var offset = 0;
    for (final range in _matches) {
      result
        ..write(_source.substring(offset, range.start))
        ..write(inserted);
      offset = range.end;
    }
    result.write(_source.substring(offset));
    _applyReplacement(
      result.toString(),
      _matches.first.start + inserted.length,
    );
    return count;
  }

  void _applyReplacement(String text, int caret) {
    _updating = true;
    try {
      document.commitHistoryGroup();
      document.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: caret),
      );
      document.commitHistoryGroup();
    } finally {
      _updating = false;
    }
    _refresh(reveal: true, anchor: caret);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _searchTimer?.cancel();
    _searchTimer = null;
    document.removeListener(_documentChanged);
    query.dispose();
    replacement.dispose();
    super.dispose();
  }
}
