import 'dart:typed_data';

enum ConflictDiffKind { unchanged, removed, added }

class ConflictDiffLine {
  const ConflictDiffLine(this.kind, this.text, this.diskLine, this.localLine);
  final ConflictDiffKind kind;

  /// Exact line bytes as decoded text, including its original line ending.
  final String text;
  final int? diskLine;
  final int? localLine;
}

class ConflictDiff {
  const ConflictDiff(this.lines, {required this.coarse});
  final List<ConflictDiffLine> lines;

  /// Large changed regions are shown as complete removal/addition groups.
  final bool coarse;

  factory ConflictDiff.compare(String disk, String local) {
    final a = _lines(disk), b = _lines(local);
    var prefix = 0;
    while (prefix < a.length && prefix < b.length && a[prefix] == b[prefix]) {
      prefix++;
    }
    var ae = a.length, be = b.length;
    while (ae > prefix && be > prefix && a[ae - 1] == b[be - 1]) {
      ae--;
      be--;
    }
    final result = <ConflictDiffLine>[];
    void add(ConflictDiffKind kind, int i, int j) => result.add(
      ConflictDiffLine(
        kind,
        kind == ConflictDiffKind.added ? b[j] : a[i],
        kind == ConflictDiffKind.added ? null : i + 1,
        kind == ConflictDiffKind.removed ? null : j + 1,
      ),
    );
    for (var i = 0; i < prefix; i++) {
      add(ConflictDiffKind.unchanged, i, i);
    }
    final n = ae - prefix, m = be - prefix;
    final coarse = (n + 1) * (m + 1) > 1000000;
    if (coarse) {
      for (var i = prefix; i < ae; i++) {
        add(ConflictDiffKind.removed, i, prefix);
      }
      for (var j = prefix; j < be; j++) {
        add(ConflictDiffKind.added, prefix, j);
      }
    } else {
      final width = m + 1;
      final lengths = Uint32List((n + 1) * width);
      for (var i = n - 1; i >= 0; i--) {
        for (var j = m - 1; j >= 0; j--) {
          final down = lengths[(i + 1) * width + j];
          final right = lengths[i * width + j + 1];
          lengths[i * width + j] = a[prefix + i] == b[prefix + j]
              ? 1 + lengths[(i + 1) * width + j + 1]
              : (down > right ? down : right);
        }
      }
      var i = 0, j = 0;
      while (i < n || j < m) {
        if (i < n && j < m && a[prefix + i] == b[prefix + j]) {
          add(ConflictDiffKind.unchanged, prefix + i++, prefix + j++);
        } else if (i < n &&
            (j == m ||
                lengths[(i + 1) * width + j] >= lengths[i * width + j + 1])) {
          add(ConflictDiffKind.removed, prefix + i++, prefix + j);
        } else {
          add(ConflictDiffKind.added, prefix + i, prefix + j++);
        }
      }
    }
    for (var i = ae, j = be; i < a.length; i++, j++) {
      add(ConflictDiffKind.unchanged, i, j);
    }
    return ConflictDiff(List.unmodifiable(result), coarse: coarse);
  }
}

List<String> _lines(String text) {
  final result = <String>[];
  var start = 0;
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit != 10 && unit != 13) continue;
    if (unit == 13 && i + 1 < text.length && text.codeUnitAt(i + 1) == 10) i++;
    result.add(text.substring(start, i + 1));
    start = i + 1;
  }
  if (start < text.length) result.add(text.substring(start));
  return result;
}
