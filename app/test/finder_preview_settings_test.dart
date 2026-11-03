import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/widgets/finder_preview_settings.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  var installed = true;
  var bundled = true;
  var failSettings = false;
  var needsSetup = false;
  var stall = false;
  final calls = <String>[];
  setUp(() {
    installed = true;
    bundled = true;
    failSettings = false;
    needsSetup = false;
    stall = false;
    calls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      finderPreviewChannel,
      (call) async {
        calls.add(call.method);
        if (call.method == 'getFinderPreviewState') {
          if (stall) await Completer<void>().future;
          return {
            'needsSetup': needsSetup,
            'installed': installed,
            'bundled': bundled,
            'registered': installed,
          };
        }
        if (call.method == 'dismissFinderPreviewSetup') needsSetup = false;
        if (call.method == 'openFinderPreviewSettings' && failSettings) {
          throw PlatformException(
            code: 'failed',
            message: 'Open System Settings manually.',
          );
        }
        return null;
      },
    );
  });
  tearDown(
    () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
      finderPreviewChannel,
      null,
    ),
  );

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: FinderPreviewSettings()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'management and verification use separate native actions without claiming enabled',
    (tester) async {
      await mount(tester);
      expect(
        find.textContaining('on/off switch is managed by macOS'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('manage-finder-preview')));
      await tester.pumpAndSettle();
      expect(calls, contains('openFinderPreviewSettings'));
      await tester.tap(find.byKey(const ValueKey('verify-finder-preview')));
      await tester.pumpAndSettle();
      expect(calls, contains('revealFinderPreviewExample'));
      expect(calls, isNot(contains('setPreference')));
    },
  );

  testWidgets(
    'DMG launch explains installation and prevents premature verification',
    (tester) async {
      installed = false;
      await mount(tester);
      expect(find.textContaining('Move Linefold from the DMG'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('verify-finder-preview')),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'missing extension and failed settings navigation remain actionable',
    (tester) async {
      bundled = false;
      failSettings = true;
      await mount(tester);
      expect(find.textContaining('extension is missing'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('manage-finder-preview')));
      await tester.pumpAndSettle();
      expect(find.text('Open System Settings manually.'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('manage-finder-preview')),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets('first-run guide is dismissible and not repeated', (
    tester,
  ) async {
    needsSetup = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => offerFinderPreviewSetup(context),
              child: const Text('Launch'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Launch'));
    await tester.pumpAndSettle();
    expect(find.text('Preview Markdown in Finder'), findsOneWidget);
    await tester.tap(find.text('Done / Set Up Later'));
    await tester.pumpAndSettle();
    expect(calls, contains('dismissFinderPreviewSetup'));
    await tester.tap(find.text('Launch'));
    await tester.pumpAndSettle();
    expect(find.text('Preview Markdown in Finder'), findsNothing);
  });
  testWidgets('native status timeout is finite and retryable', (tester) async {
    stall = true;
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: FinderPreviewSettings()),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.textContaining('Unable to check'), findsOneWidget);
    stall = false;
    await tester.tap(find.text('Check Again'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('on/off switch is managed by macOS'),
      findsOneWidget,
    );
  });
}
