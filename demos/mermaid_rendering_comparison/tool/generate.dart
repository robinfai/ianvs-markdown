import 'dart:convert';
import 'dart:io';
import 'package:merman/merman.dart';
import 'package:ianvs_mermaid/src/mermaid_render_options.dart';
import 'package:ianvs_mermaid/src/mermaid_svg_normalizer.dart';

void main(List<String> args) {
  final config = File('../../app/.dart_tool/package_config.json');
  final packages =
      (jsonDecode(config.readAsStringSync()) as Map)['packages'] as List;
  final package = packages.cast<Map>().singleWhere(
    (item) => item['name'] == 'merman',
  );
  final packagePath = config.uri
      .resolve(package['rootUri'] as String)
      .toFilePath();
  final engine = Merman.openPath(
    '$packagePath/macos/Libraries/libmerman_ffi.dylib',
  );
  const options = MermaidRenderOptions(fontFamily: 'Hiragino Sans GB');
  final sources = <String, (String, String)>{
    'flow': (
      '中文流程 · 箭头与换行',
      '''flowchart LR
  A["输入中文问题"] --> B{"命中缓存？"}
  B -->|是| C["返回结果"]
  B -.->|否| D["模型推理<br/>生成下一个 Token"]
  D ==> C
  style A fill:#e0f2fe,stroke:#0284c7
  style C fill:#dcfce7,stroke:#16a34a''',
    ),
    'sequence': (
      '时序图 · 虚线与激活条',
      '''sequenceDiagram
  participant U as 用户
  participant A as 应用服务
  participant M as 模型引擎
  U->>A: 提交问题
  activate A
  A->>M: 请求推理
  loop 流式生成
    M-->>A: Token 分片
    A-->>U: 增量显示
  end
  deactivate A
  Note over U,M: 中文标签 / English / 123''',
    ),
    'class': (
      '类图 · 空心箭头与菱形',
      '''classDiagram
  Animal <|-- Duck
  Animal <|-- Fish
  Pond *-- Fish
  Pond o-- Duck
  class Animal {
    +String name
    +move()
  }
  class Duck {
    +swim()
  }
  class Fish {
    +breathe()
  }''',
    ),
    'state': (
      '状态图 · 起止节点',
      '''stateDiagram-v2
  [*] --> Idle
  Idle --> Loading: 打开文件
  Loading --> Ready: 读取完成
  Loading --> Error: 读取失败
  Error --> Loading: 重试
  Ready --> Editing: 输入内容
  Editing --> Ready: 保存
  Ready --> [*]: 关闭''',
    ),
    'dense': (
      '压力样例 · 64 个节点',
      'flowchart TB\n${List.generate(8, (r) => List.generate(8, (c) => 'N${r}_$c["节点 ${r + 1}·${c + 1}"]${c < 7 ? ' --> N${r}_${c + 1}' : ''}').join('\n')).join('\n')}',
    ),
  };
  if (args.isNotEmpty) {
    for (final name in ['01-01', '04-01']) {
      final source = File('${args.first}/assets/mermaid/$name.mmd');
      if (source.existsSync())
        sources['article-$name'] = ('实际文章 · $name', source.readAsStringSync());
    }
  }
  final manifest = <Map<String, Object?>>[];
  for (final entry in sources.entries) {
    final dir = Directory('assets/${entry.key}')..createSync(recursive: true);
    File('${dir.path}/source.mmd').writeAsStringSync(entry.value.$2);
    final times = <double>[];
    var svg = '';
    for (var i = 0; i < 6; i++) {
      final watch = Stopwatch()..start();
      svg = normalizeMermaidSvgForFlutter(
        engine.renderSvg(entry.value.$2, optionsJson: options.toOptionsJson()),
      );
      times.add(watch.elapsedMicroseconds / 1000);
    }
    File('${dir.path}/input.svg').writeAsStringSync(svg);
    final warm = times.skip(1).toList()..sort();
    manifest.add({
      'id': entry.key,
      'title': entry.value.$1,
      'source': entry.value.$2,
      'merman_version': engine.packageVersion,
      'merman_median_ms': warm[warm.length ~/ 2],
      'font': 'Hiragino Sans GB',
      'pipeline': 'resvg-safe',
      'markers': RegExp(r'<marker[\s>]').allMatches(svg).length,
      'foreign_objects': RegExp(r'<foreignObject[\s>]').allMatches(svg).length,
    });
    stdout.writeln('${entry.key}: ${svg.length} chars');
  }
  File(
    'assets/cases.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));
}
