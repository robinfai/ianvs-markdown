import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() {
  test('history accounting and process RSS', () {
    const unlimited = bool.fromEnvironment('UNBOUNDED');
    final before = ProcessInfo.currentRss;
    final controller = IanvsMarkdownController(
      historyPolicy: unlimited ? null : const IanvsMarkdownHistoryPolicy(),
    );
    final source = ('a' * 127 + '\n') * 8192;
    for (var i = 0; i < 64; i++) {
      controller.commitHistoryGroup();
      controller.value = TextEditingValue(text: '$i$source');
    }
    controller.commitHistoryGroup();
    stdout.writeln(
      'HISTORY_PROBE ${jsonEncode({'policy': unlimited ? 'unlimited' : 'default', 'edits': 64, 'sourceCodeUnits': controller.text.length, 'retainedEntries': controller.retainedHistoryEntries, 'accountedTextBytes': controller.retainedHistoryTextBytes, 'rssBefore': before, 'rssAfter': ProcessInfo.currentRss, 'maxRss': ProcessInfo.maxRss, 'platform': Platform.operatingSystemVersion, 'dart': Platform.version})}',
    );
    controller.dispose();
  });
}
