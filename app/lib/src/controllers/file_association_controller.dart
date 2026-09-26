import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/file_association_service.dart';

class FileAssociationController extends ChangeNotifier {
  FileAssociationController({required this.service});

  final FileAssociationService service;
  FileAssociationState state = const FileAssociationState(supported: false);
  bool initialized = false;
  bool busy = false;
  String? error;
  bool _disposed = false;

  bool get needsPrompt =>
      initialized && state.supported && state.preferLinefold == null;

  Future<void> initialize() async {
    await refresh();
    // An existing system association already expresses the user's choice.
    if (needsPrompt && state.isDefault) await setPreference(true);
  }

  Future<void> refresh() async {
    if (busy || _disposed) return;
    try {
      state = await service.load();
      initialized = true;
    } on Object {
      error = 'Unable to read the default Markdown application. Try again.';
    }
    _notify();
  }

  Future<bool> setPreference(bool preferLinefold) async {
    if (busy || _disposed) return false;
    busy = true;
    error = null;
    _notify();
    var succeeded = false;
    try {
      state = await service.setPreference(preferLinefold);
      succeeded = true;
    } on Object catch (exception) {
      error = exception is PlatformException
          ? exception.message ?? 'Unable to change the default application.'
          : 'Unable to save this preference. Try again.';
      // macOS may decline a change after the preference has been saved.
      // Read back both the saved intention and the actual system association.
      try {
        state = await service.load();
      } on Object {
        // Keep the last known state and the actionable error.
      }
    } finally {
      busy = false;
      _notify();
    }
    return succeeded;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
