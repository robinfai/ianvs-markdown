import 'package:flutter/material.dart';
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
