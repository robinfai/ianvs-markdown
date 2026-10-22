import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/widgets/local_document_image.dart';

import 'attachment_test_support.dart';

void main() {
  testWidgets(
    'explicit image viewer clears an old result when its path changes',
    (tester) async {
      final root = Directory.systemTemp.createTempSync(
        'linefold-image-fixture-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final first = File('${root.path}/first.png');
      await tester.runAsync(() => first.writeAsBytes(tinyPng));
      Widget app(String path) => MaterialApp(
        home: Scaffold(body: LocalDocumentImage(path: path)),
      );
      await tester.pumpWidget(app(first.path));
      for (var i = 0; i < 30 && find.byType(Image).evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.byType(Image), findsOneWidget);
      await tester.pumpWidget(app('${root.path}/missing.png'));
      expect(find.byType(Image), findsNothing);
      for (
        var i = 0;
        i < 30 && find.byType(SelectableText).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.byType(SelectableText), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
