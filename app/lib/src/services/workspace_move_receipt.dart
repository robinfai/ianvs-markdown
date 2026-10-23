import 'workspace_index_source.dart';

/// Independent evidence that the directory itself moved, including empty trees.
class WorkspaceDirectoryMoveReceipt {
  const WorkspaceDirectoryMoveReceipt({
    required this.sourcePath,
    required this.destinationPath,
    required this.identity,
    required this.memberCount,
    this.actualPath,
    this.moved = false,
    this.synced = false,
    this.verified = false,
  });
  final String sourcePath;
  final String destinationPath;
  final String identity;
  final int memberCount;
  final String? actualPath;
  final bool moved;
  final bool synced;
  final bool verified;
  bool get completed =>
      moved && synced && verified && actualPath == destinationPath;

  factory WorkspaceDirectoryMoveReceipt.fromMap(Map<Object?, Object?> value) {
    final source = value['sourcePath'];
    final destination = value['destinationPath'];
    final identity = value['identity'];
    final count = value['memberCount'];
    final actual = value['actualPath'];
    if (source is! String ||
        destination is! String ||
        !safeWorkspaceRelativePath(source) ||
        !safeWorkspaceRelativePath(destination) ||
        identity is! String ||
        !RegExp(r'^\d+:\d+$').hasMatch(identity) ||
        count is! int ||
        count < 1 ||
        count > 256 ||
        (actual != null && actual != source && actual != destination) ||
        value['moved'] is! bool ||
        value['synced'] is! bool ||
        value['verified'] is! bool ||
        (value['synced'] == true && value['moved'] != true)) {
      throw const FormatException('Invalid directory namespace receipt.');
    }
    return WorkspaceDirectoryMoveReceipt(
      sourcePath: source,
      destinationPath: destination,
      identity: identity,
      memberCount: count,
      actualPath: actual as String?,
      moved: value['moved'] == true,
      synced: value['synced'] == true,
      verified: value['verified'] == true,
    );
  }
}

/// One independent root observation within a v3 batch, not an atomic batch.
class WorkspaceBatchMoveReceipt extends WorkspaceDirectoryMoveReceipt {
  const WorkspaceBatchMoveReceipt({
    required super.sourcePath,
    required super.destinationPath,
    required super.identity,
    required super.memberCount,
    required this.kind,
    super.actualPath,
    super.moved,
    super.synced,
    super.verified,
  });
  final String kind;
  bool get atSource =>
      verified && !moved && !synced && actualPath == sourcePath;

  factory WorkspaceBatchMoveReceipt.fromMap(Map<Object?, Object?> value) {
    final receipt = WorkspaceDirectoryMoveReceipt.fromMap(value);
    final kind = value['kind'];
    if ((kind != 'note' && kind != 'directory') ||
        (kind == 'note' && receipt.memberCount != 1)) {
      throw const FormatException('Invalid batch root receipt.');
    }
    return WorkspaceBatchMoveReceipt(
      sourcePath: receipt.sourcePath,
      destinationPath: receipt.destinationPath,
      identity: receipt.identity,
      memberCount: receipt.memberCount,
      kind: kind as String,
      actualPath: receipt.actualPath,
      moved: receipt.moved,
      synced: receipt.synced,
      verified: receipt.verified,
    );
  }
}

List<WorkspaceBatchMoveReceipt> parseWorkspaceBatchReceipts(Object? value) {
  if (value is! List || value.length < 2 || value.length > 8) {
    throw const FormatException('Invalid batch root receipt count.');
  }
  final roots = <WorkspaceBatchMoveReceipt>[
    for (final root in value)
      if (root is Map)
        WorkspaceBatchMoveReceipt.fromMap(root)
      else
        throw const FormatException('Invalid batch root receipt.'),
  ];
  if (roots.map((r) => r.sourcePath).toSet().length != roots.length ||
      roots.map((r) => r.destinationPath).toSet().length != roots.length ||
      roots.fold<int>(0, (sum, r) => sum + r.memberCount) > 256) {
    throw const FormatException('Invalid batch root receipt set.');
  }
  return List.unmodifiable(roots);
}
