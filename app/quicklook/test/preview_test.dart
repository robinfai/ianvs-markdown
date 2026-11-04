import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold_quicklook/main.dart';

void main() {
  testWidgets('system locale falls back to English and follows Chinese', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localeTestValue = const Locale('fr');
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
    await tester.pumpWidget(
      const Preview(input: {'source': '', 'merman': '/unused'}),
    );
    await tester.pumpAndSettle();
    expect(find.text('This document is empty.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    tester.binding.platformDispatcher.localeTestValue = const Locale(
      'zh',
      'CN',
    );
    await tester.pumpWidget(
      const Preview(input: {'source': '', 'merman': '/unused'}),
    );
    await tester.pumpAndSettle();
    expect(find.text('文档为空'), findsOneWidget);
  });
  testWidgets(
    'native copy with no selection is safe; select all copies offscreen source',
    (tester) async {
      final source = List.generate(200, (i) => 'Paragraph $i').join('\n\n');
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        Preview(input: {'source': source, 'merman': '/unused'}),
      );
      await tester.pumpAndSettle();
      Future<void> command(String name) async {
        final done = Completer<void>();
        tester.binding.channelBuffers.push(
          bridge.name,
          const StandardMethodCodec().encodeMethodCall(MethodCall(name)),
          (_) => done.complete(),
        );
        await tester.pumpAndSettle();
        await done.future;
      }

      await command('copy');
      expect(copied, isNull);
      await command('selectAll');
      await command('copy');
      expect(copied, source);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('renders Markdown and follows system appearance', (tester) async {
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;
    addTearDown(
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
    );
    await tester.pumpWidget(
      const Preview(
        input: {'source': '# Heading\n\nBody', 'merman': '/unused'},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Heading', findRichText: true), findsOneWidget);
    expect(
      Theme.of(tester.element(find.byType(Material))).brightness,
      Brightness.dark,
    );
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.light;
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Material))).brightness,
      Brightness.light,
    );
    expect(tester.takeException(), isNull);
  });
}
