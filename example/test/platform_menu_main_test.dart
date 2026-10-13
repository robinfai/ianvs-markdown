import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_markdown_example/main.dart';

import '../../test/fixtures/large_documents.dart';

void main() {
  testWidgets(
    'native menu channel pastes, reads and copies full large source',
    (tester) async {
      final source = largeDocuments['sourceLength']!;
      String? copied;
      final menuIds = <String, int>{};
      final messenger = tester.binding.defaultBinaryMessenger;
      void collect(dynamic value) {
        if (value is Map) {
          if (value['label'] is String && value['id'] is int) {
            menuIds[value['label'] as String] = value['id'] as int;
          }
          value.values.forEach(collect);
        } else if (value is List) {
          value.forEach(collect);
        }
      }

      messenger.setMockMethodCallHandler(SystemChannels.menu, (call) async {
        if (call.method == 'Menu.setMenus') {
          collect(call.arguments);
        }
        return null;
      });
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') {
          return {'text': source};
        }
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(const ExampleApp());
      await tester.pumpAndSettle();
      final controller = tester
          .widget<IanvsMarkdownLiveEditor>(find.byType(IanvsMarkdownLiveEditor))
          .controller;
      Future<void> menu(String label) async {
        expect(
          menuIds.containsKey(label),
          isTrue,
          reason: '$label must be routed into Flutter',
        );
        await messenger.handlePlatformMessage(
          SystemChannels.menu.name,
          SystemChannels.menu.codec.encodeMethodCall(
            MethodCall('Menu.selectedCallback', menuIds[label]),
          ),
          (_) {},
        );
        await tester.pumpAndSettle();
      }

      await menu('Source');
      await tester.enterText(
        find.byKey(const ValueKey('ianvs-markdown-source-field')),
        'seed',
      );
      await tester.pumpAndSettle();
      await menu('Select All');
      await menu('Paste');
      expect(controller.text == source, isTrue);
      await menu('Read');
      expect(
        find.byKey(const ValueKey('ianvs-markdown-budget-notice')),
        findsOneWidget,
      );
      await menu('Select All');
      await menu('Copy');
      expect(copied == source, isTrue);
      await menu('Source');
      expect(tester.testTextInput.hasAnyClients, isTrue);
      expect(controller.text == source, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
