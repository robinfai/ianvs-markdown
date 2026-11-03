import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/app_localizations.dart';
import 'package:linefold/src/widgets/finder_preview_settings.dart';

void main() {
  test(
    'matches zh/en variants in system order, otherwise falls back to en',
    () {
      for (final locale in [
        const Locale('zh', 'CN'),
        const Locale('zh', 'TW'),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      ]) {
        expect(
          resolveAppLocale([locale], appSupportedLocales),
          const Locale('zh'),
        );
      }
      expect(
        resolveAppLocale([
          const Locale('en', 'GB'),
          const Locale('zh'),
        ], appSupportedLocales),
        const Locale('en'),
      );
      expect(
        resolveAppLocale([
          const Locale('fr'),
          const Locale('zh'),
        ], appSupportedLocales),
        const Locale('zh'),
      );
      expect(
        resolveAppLocale([const Locale('ja')], appSupportedLocales),
        const Locale('en'),
      );
      expect(resolveAppLocale([], appSupportedLocales), const Locale('en'));
      expect(resolveAppLocale(null, appSupportedLocales), const Locale('en'));
    },
  );

  test('all bilingual templates preserve their arguments', () {
    final placeholder = RegExp(r'\{\d+\}');
    for (final entry in appMessages.entries) {
      expect(entry.value.length, 2, reason: entry.key);
      expect(entry.value.every((v) => v.isNotEmpty), isTrue, reason: entry.key);
      expect(
        placeholder.allMatches(entry.value[0]).map((m) => m[0]).toSet(),
        placeholder.allMatches(entry.value[1]).map((m) => m[0]).toSet(),
        reason: entry.key,
      );
    }
  });

  testWidgets('follows system changes and keeps user text literal', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = [const Locale('zh', 'TW')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: appSupportedLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        localeListResolutionCallback: resolveAppLocale,
        home: Builder(
          builder: (context) => Scaffold(
            body: Text(appText(context, 'Close {0}', ['Settings {0}.md'])),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('关闭 Settings {0}.md'), findsOneWidget);
    tester.platformDispatcher.localesTestValue = [const Locale('de')];
    await tester.pumpAndSettle();
    expect(find.text('Close Settings {0}.md'), findsOneWidget);
  });

  for (final language in ['zh', 'en']) {
    testWidgets(
      '$language preview guidance fits a narrow window without sample action',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          finderPreviewChannel,
          (call) async => {'installed': true, 'bundled': true},
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            finderPreviewChannel,
            null,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            supportedLocales: appSupportedLocales,
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: const Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: FinderPreviewSettings(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(language == 'zh' ? '访达预览' : 'Finder preview'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('manage-finder-preview')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('verify-finder-preview')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
