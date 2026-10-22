/// Cloud metadata is an observation, never a receipt for a local save and never
/// evidence that another device has received a particular revision.
enum CloudSyncState {
  unknown,
  localOnly,
  uploading,
  uploadPending,
  downloading,
  downloadPending,
  uploaded,
  failure,
  conflict,
}

class DocumentConflictVersion {
  const DocumentConflictVersion({required this.name, this.modified});
  final String name;
  final DateTime? modified;
}

class DocumentSyncMetadata {
  const DocumentSyncMetadata({
    this.state = CloudSyncState.unknown,
    this.observedAt,
    this.detail,
    this.conflicts = const [],
    this.conflictsAvailable = false,
  });

  final CloudSyncState state;
  final DateTime? observedAt;
  final String? detail;
  final List<DocumentConflictVersion> conflicts;
  final bool conflictsAvailable;

  factory DocumentSyncMetadata.fromMap(Map<Object?, Object?> map) {
    DateTime? timestamp(Object? value) => value is num && value.isFinite
        ? DateTime.fromMillisecondsSinceEpoch(value.toInt())
        : null;
    final observed = timestamp(map['observedAt']);
    final versions = <DocumentConflictVersion>[];
    if (map['conflicts'] case final List values) {
      for (final entry in values) {
        if (entry is Map && entry['name'] is String) {
          versions.add(
            DocumentConflictVersion(
              name: entry['name'] as String,
              modified: timestamp(entry['modified']),
            ),
          );
        }
      }
    }
    final uploadError = map['uploadError'];
    final downloadError = map['downloadError'];
    final failure = uploadError is String && uploadError.isNotEmpty
        ? 'Upload failed: $uploadError'
        : downloadError is String && downloadError.isNotEmpty
        ? 'Download failed: $downloadError'
        : null;
    final CloudSyncState state;
    if (observed == null || map['isUbiquitous'] != true) {
      // A non-ubiquitous item may still belong to a third-party provider. Do not
      // infer either "local only" or "synced" from Apple's missing capability.
      state = CloudSyncState.unknown;
    } else if (map['hasUnresolvedConflicts'] == true || versions.isNotEmpty) {
      state = CloudSyncState.conflict;
    } else if (failure != null) {
      state = CloudSyncState.failure;
    } else if (map['isUploading'] == true) {
      state = CloudSyncState.uploading;
    } else if (map['isDownloading'] == true) {
      state = CloudSyncState.downloading;
    } else if (map['downloadingStatus'] == 'notDownloaded' ||
        map['downloadingStatus'] == 'downloaded') {
      state = CloudSyncState.downloadPending;
    } else if (map['isUploaded'] == false) {
      state = CloudSyncState.uploadPending;
    } else if (map['isUploaded'] == true) {
      state = CloudSyncState.uploaded;
    } else {
      state = CloudSyncState.unknown;
    }
    return DocumentSyncMetadata(
      state: state,
      observedAt: observed,
      detail: failure,
      conflicts: List.unmodifiable(versions),
      conflictsAvailable: map['conflictsAvailable'] == true,
    );
  }

  String get label => switch (state) {
    CloudSyncState.unknown => 'Cloud status unknown',
    CloudSyncState.localOnly => 'Local only',
    CloudSyncState.uploading => 'iCloud uploading',
    CloudSyncState.uploadPending => 'iCloud upload pending',
    CloudSyncState.downloading => 'iCloud downloading',
    CloudSyncState.downloadPending => 'iCloud download pending',
    CloudSyncState.uploaded => 'iCloud reports uploaded',
    CloudSyncState.failure => 'iCloud transfer failed',
    CloudSyncState.conflict => 'iCloud conflict',
  };

  String get explanation =>
      detail ??
      switch (state) {
        CloudSyncState.unknown =>
          'The provider has not supplied a current cloud status. Local saving does not confirm cloud upload.',
        CloudSyncState.localOnly => 'This document is stored locally only.',
        CloudSyncState.uploading => 'iCloud reports an upload in progress.',
        CloudSyncState.uploadPending =>
          'iCloud has not reported this item uploaded. Pending does not identify a network problem.',
        CloudSyncState.downloading => 'iCloud reports a download in progress.',
        CloudSyncState.downloadPending =>
          'The local copy is missing or older than the latest version known to this device.',
        CloudSyncState.uploaded =>
          'iCloud reports data uploaded for this item. This is not confirmation that other devices have received your latest edits.',
        CloudSyncState.failure =>
          'iCloud reported a transfer error. Retry checking the status after addressing the error.',
        CloudSyncState.conflict =>
          'iCloud reports unresolved versions. No version has been replaced, resolved or deleted.',
      };
}

/// Optional capability: adding it never changes existing file-service mocks or
/// permits fetching file contents, enumerating a vault, or acquiring new scopes.
abstract interface class DocumentSyncSource {
  Future<DocumentSyncMetadata> readSyncMetadata(String path);
}

enum LocalDocumentState { restoring, draft, edited, saving, saved, failed }

enum RecoveryCopyState { pending, saved, failed }

class DocumentPersistenceStatus {
  const DocumentPersistenceStatus({
    required this.local,
    required this.recovery,
    this.conflict = false,
  });
  final LocalDocumentState local;
  final RecoveryCopyState recovery;
  final bool conflict;

  String get label {
    final primary = switch (local) {
      LocalDocumentState.restoring => 'Restoring draft',
      LocalDocumentState.draft => 'Draft',
      LocalDocumentState.edited => 'Edited',
      LocalDocumentState.saving => 'Saving locally',
      LocalDocumentState.saved => 'Saved locally',
      LocalDocumentState.failed => 'Local save failed',
    };
    if (conflict) return '$primary · disk conflict';
    if (local == LocalDocumentState.saved ||
        local == LocalDocumentState.saving) {
      return primary;
    }
    return '$primary · ${switch (recovery) {
      RecoveryCopyState.pending => 'recovery pending',
      RecoveryCopyState.saved => 'recovery saved',
      RecoveryCopyState.failed => 'recovery failed',
    }}';
  }
}
