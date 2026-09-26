import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:linefold/src/controllers/file_association_controller.dart';

import 'support/fakes.dart';

void main() {
  for (final choice in [false, true]) {
    test(
      'remembers $choice and does not prompt or apply again after restart',
      () async {
        final service = MemoryFileAssociationService();
        final first = FileAssociationController(service: service);
        addTearDown(first.dispose);
        await first.initialize();
        expect(first.needsPrompt, isTrue);
        expect(service.changes, isEmpty);
        expect(await first.setPreference(choice), isTrue);

        final restarted = FileAssociationController(service: service);
        addTearDown(restarted.dispose);
        await restarted.initialize();
        expect(restarted.needsPrompt, isFalse);
        expect(restarted.state.preferLinefold, choice);
        expect(service.changes, [choice]);
      },
    );
  }

  test(
    'a denied system change saves intent without reporting success or nagging',
    () async {
      final service = MemoryFileAssociationService()..rejectChange = true;
      final controller = FileAssociationController(service: service);
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(await controller.setPreference(true), isFalse);
      expect(controller.state.preferLinefold, isTrue);
      expect(controller.state.isDefault, isFalse);
      expect(controller.error, contains('macOS did not change'));
      expect(controller.needsPrompt, isFalse);

      final restarted = FileAssociationController(service: service);
      addTearDown(restarted.dispose);
      await restarted.initialize();
      expect(restarted.needsPrompt, isFalse);
      expect(service.changes, [true]);
      service.rejectChange = false;
      expect(await restarted.setPreference(true), isTrue);
      expect(restarted.state.isDefault, isTrue);
      expect(restarted.error, isNull);
    },
  );

  test(
    'an existing default is acknowledged without a redundant prompt',
    () async {
      final service = MemoryFileAssociationService()..isDefault = true;
      final controller = FileAssociationController(service: service);
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.needsPrompt, isFalse);
      expect(service.preference, isTrue);
    },
  );

  test(
    'refresh observes an external change without taking the association back',
    () async {
      final service = MemoryFileAssociationService()
        ..preference = true
        ..isDefault = true;
      final controller = FileAssociationController(service: service);
      addTearDown(controller.dispose);
      await controller.initialize();
      service.isDefault = false;
      await controller.refresh();
      expect(controller.state.preferLinefold, isTrue);
      expect(controller.state.isDefault, isFalse);
      expect(controller.state.currentApplicationName, 'Other Editor');
      expect(service.changes, isEmpty);
      expect(controller.needsPrompt, isFalse);
    },
  );

  test(
    'serializes changes and can finish safely after the UI is disposed',
    () async {
      final service = MemoryFileAssociationService()
        ..pendingChange = Completer<void>();
      final controller = FileAssociationController(service: service);
      await controller.initialize();
      final first = controller.setPreference(true);
      expect(controller.busy, isTrue);
      expect(await controller.setPreference(false), isFalse);
      expect(service.changes, [true]);
      controller.dispose();
      service.pendingChange!.complete();
      expect(await first, isTrue);
    },
  );
}
