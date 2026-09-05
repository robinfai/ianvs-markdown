import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class WorkspaceSnapshot {
  const WorkspaceSnapshot({
    required this.documents,
    required this.activeDocumentId,
    required this.workspaceRoot,
    required this.workspaceAccessToken,
    required this.sidebarVisible,
    required this.outlineVisible,
  });

  factory WorkspaceSnapshot.fromJson(Map<String, Object?> json) {
    final rawDocuments = json['documents'];
    return WorkspaceSnapshot(
      documents: rawDocuments is List
          ? rawDocuments
                .whereType<Map>()
                .map((item) => Map<String, Object?>.from(item))
                .toList(growable: false)
          : const <Map<String, Object?>>[],
      activeDocumentId: json['activeDocumentId'] as String?,
      workspaceRoot: json['workspaceRoot'] as String?,
      workspaceAccessToken: json['workspaceAccessToken'] as String?,
      sidebarVisible: json['sidebarVisible'] as bool? ?? true,
      outlineVisible: json['outlineVisible'] as bool? ?? true,
    );
  }

  final List<Map<String, Object?>> documents;
  final String? activeDocumentId;
  final String? workspaceRoot;
  final String? workspaceAccessToken;
  final bool sidebarVisible;
  final bool outlineVisible;

  Map<String, Object?> toJson() => <String, Object?>{
    'documents': documents,
    'activeDocumentId': activeDocumentId,
    'workspaceRoot': workspaceRoot,
    'workspaceAccessToken': workspaceAccessToken,
    'sidebarVisible': sidebarVisible,
    'outlineVisible': outlineVisible,
  };
}

abstract class WorkspaceSessionStore {
  Future<WorkspaceSnapshot?> load();

  Future<void> save(WorkspaceSnapshot snapshot);
}

class DesktopWorkspaceSessionStore implements WorkspaceSessionStore {
  const DesktopWorkspaceSessionStore();

  Future<File> _sessionFile() async {
    final support = await getApplicationSupportDirectory();
    return File(p.join(support.path, 'ianvs-markdown', 'workspace.json'));
  }

  @override
  Future<WorkspaceSnapshot?> load() async {
    final file = await _sessionFile();
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) return null;
    return WorkspaceSnapshot.fromJson(Map<String, Object?>.from(decoded));
  }

  @override
  Future<void> save(WorkspaceSnapshot snapshot) async {
    final target = await _sessionFile();
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
    try {
      await temporary.rename(target.path);
    } on FileSystemException {
      await target.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
