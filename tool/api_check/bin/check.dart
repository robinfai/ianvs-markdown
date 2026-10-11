import 'dart:convert';
import 'dart:io';

import 'package:ianvs_api_check/surface.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  if (args.length != 2 || !['--check', '--write'].contains(args.first)) {
    stderr.writeln(
      'Usage: dart run bin/check.dart --check|--write /repository/root',
    );
    exitCode = 64;
    return;
  }
  final root = p.normalize(p.absolute(args[1]));
  final file = File(p.join(root, 'tool/api_check/api_baseline.json'));
  final surface = await readSurface(p.join(root, 'lib/ianvs_markdown.dart'));
  final encoded = encodeSurface(surface);
  if (args.first == '--write') {
    file.writeAsStringSync(encoded);
    stdout.writeln(
      'Wrote ${file.path}; review the diff and migration notes before committing.',
    );
    return;
  }
  final differences = compareSurface(
    jsonDecode(file.readAsStringSync()),
    surface,
  );
  if (differences.isNotEmpty) {
    stderr.writeln(differences.join('\n'));
    stderr.writeln(
      'Public API drift: inspect the diff, update migration notes, then explicitly use --write.',
    );
    exitCode = 1;
  } else {
    stdout.writeln(
      'Public API matches: ${(surface['symbols'] as Map).length} exports, '
      '${(surface['declarations'] as Map).length} declarations.',
    );
  }
}
