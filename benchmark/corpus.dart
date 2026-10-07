import 'dart:convert';

/// Versioned, deterministic UTF-8 fixtures; sizes are binary KiB/MiB.
const corpusVersion = 1;
const corpusSizes = [10 * 1024, 100 * 1024, 1024 * 1024];

String benchmarkCorpus(int bytes) {
  const start = 'Benchmark editable paragraph 中文输入与选区保持源码一致。\n\n';
  final buffer = StringBuffer(start);
  var used = utf8.encode(start).length;
  var index = 0;
  while (true) {
    final chunk =
        '''
## Section $index

中文与 English 混排，包含 **bold**、*emphasis* 与 `inline code`。

- First item
- Second item
- [ ] A task

```dart
final value = $index;
print(value);
```

| Name | Value |
| --- | ---: |
| Row $index | 123 |

${List.filled(30, 'Long single line 中文 and plain English text.').join(' ')}

''';
    final length = utf8.encode(chunk).length;
    if (used + length > bytes) break;
    buffer.write(chunk);
    used += length;
    index += 1;
  }
  // ASCII padding preserves an exact UTF-8 byte length without cutting a rune.
  buffer.write(List.filled(bytes - used, 'x').join());
  return buffer.toString();
}
