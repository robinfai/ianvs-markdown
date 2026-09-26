import 'dart:io';

import 'package:flutter/services.dart';

class FileAssociationState {
  const FileAssociationState({
    this.supported = true,
    this.preferLinefold,
    this.isDefault = false,
    this.currentApplicationName,
    this.previousApplicationName,
  });

  factory FileAssociationState.fromMap(Map<Object?, Object?> value) {
    return FileAssociationState(
      preferLinefold: value['preferLinefold'] as bool?,
      isDefault: value['isDefault'] as bool? ?? false,
      currentApplicationName: value['currentApplicationName'] as String?,
      previousApplicationName: value['previousApplicationName'] as String?,
    );
  }

  final bool supported;
  final bool? preferLinefold;
  final bool isDefault;
  final String? currentApplicationName;
  final String? previousApplicationName;
}

abstract class FileAssociationService {
  Future<FileAssociationState> load();
  Future<FileAssociationState> setPreference(bool preferLinefold);
}

class MacOSFileAssociationService implements FileAssociationService {
  const MacOSFileAssociationService();

  static const channel = MethodChannel('work.ianvs.linefold/file_association');

  @override
  Future<FileAssociationState> load() async {
    if (!Platform.isMacOS) {
      return const FileAssociationState(supported: false);
    }
    try {
      final result = await channel.invokeMapMethod<Object?, Object?>(
        'getState',
      );
      return FileAssociationState.fromMap(result!);
    } on MissingPluginException {
      return const FileAssociationState(supported: false);
    }
  }

  @override
  Future<FileAssociationState> setPreference(bool preferLinefold) async {
    final result = await channel.invokeMapMethod<Object?, Object?>(
      'setPreference',
      <String, Object?>{'preferLinefold': preferLinefold},
    );
    return FileAssociationState.fromMap(result!);
  }
}
