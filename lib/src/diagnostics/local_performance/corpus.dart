import 'dart:convert';

const localCorpusVersion = 1;
const localCorpusSizes = [10240, 102400, 1048576];
const localWarmup = 5;
const localSamples = 20;
const localOperations = [
  'sourceType',
  'sourcePaste',
  'liveType',
  'livePaste',
  'liveToSource',
  'sourceToRead',
  'readToLive',
  'sourceTail',
  'liveTail',
];

/// Exact UTF-8 sizes, bounded lines, no network images or native diagrams.
/// The large case crosses the syntax-token budget rather than a padding line.
String localCorpus(int bytes) {
  if (!localCorpusSizes.contains(bytes)) throw ArgumentError.value(bytes);
  const first = 'Editable paragraph 中文与 emoji 😀 remain complete.\n\n';
  final out = StringBuffer(first);
  var used = utf8.encode(first).length;
  var index = 0;
  while (true) {
    final section =
        '''## Section $index

中文与 English **bold** and *italic* and `code`.

- First item
- Second item
- [ ] Task

```dart
final value = $index;
```

| Name | Value |
| --- | ---: |
| Row $index | 123 |

A plain paragraph keeps every source byte available for editing and saving.

''';
    final length = utf8.encode(section).length;
    if (used + length > bytes) break;
    out.write(section);
    used += length;
    index++;
  }
  while (used < bytes) {
    final remaining = bytes - used;
    final line = remaining > 80 ? '${'x' * 79}\n' : 'x' * remaining;
    out.write(line);
    used += line.length;
  }
  return out.toString();
}

/// Models insertion after the clipboard read; does not touch system clipboard.
String get localPaste => 'paste 中文 😀 plain text. ' * 32;
