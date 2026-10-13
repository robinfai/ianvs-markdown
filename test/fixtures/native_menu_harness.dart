import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class NativeMenuHarness {
  NativeMenuHarness(this.tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.menu,
      (call) async {
        if (call.method == 'Menu.setMenus') {
          items.clear();
          _collect(call.arguments);
        }
        return null;
      },
    );
  }
  final WidgetTester tester;
  final items = <String, Map<dynamic, dynamic>>{};
  void _collect(dynamic value) {
    if (value is Map) {
      if (value['label'] is String && value['id'] is int) {
        items[value['label'] as String] = value;
      }
      value.values.forEach(_collect);
    } else if (value is List) {
      value.forEach(_collect);
    }
  }

  Future<void> select(String label) async {
    expect(items, contains(label));
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.menu.name,
      SystemChannels.menu.codec.encodeMethodCall(
        MethodCall('Menu.selectedCallback', items[label]!['id']),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
  }
}

Future<void> commandKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pumpAndSettle();
}
