import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// These source contracts run on Linux too. They are deliberately not a claim
// that Swift compiles or Apple filesystem/provider behavior has been exercised.
void main() {
  final source = File('apple/CloudWorkspace.swift').readAsStringSync();
  final core = source.substring(
    source.indexOf('class WorkspaceFileScope {'),
    source.indexOf('final class AttachmentScope:'),
  );
  final attachments = source.substring(
    source.indexOf('final class AttachmentScope:'),
    source.indexOf('final class WorkspaceTextScope:'),
  );
  final text = source.substring(
    source.indexOf('final class WorkspaceTextScope:'),
  );

  test(
    'native Wiki creation is exclusive root-relative without parent creation',
    () {
      expect(source, contains('case "createWorkspaceNote":'));
      expect(
        source,
        contains('try scope.createNote(relativePath: relativePath)'),
      );
      expect(
        text,
        contains('O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC'),
      );
      expect(text, contains('let parent = try parentDescriptor(components)'));
      expect(
        text,
        contains(
          'current.st_dev == attributes.st_dev && current.st_ino == attributes.st_ino',
        ),
      );
      expect(text, contains('listing["complete"] as? Bool == true'));
      expect(text, contains('comparisonPath'));
      expect(
        text,
        contains('precomposedStringWithCanonicalMapping.lowercased()'),
      );
      expect(text, isNot(contains('createDirectory(')));
      expect(source, contains('coordinator.coordinate(writingItemAt: target'));
      expect(
        text,
        contains('let finalParent = try parentDescriptor(components)'),
      );
      expect(
        text,
        contains(
          'finalTarget.st_dev == created.st_dev && finalTarget.st_ino == created.st_ino',
        ),
      );
      expect(
        text,
        contains('Self.revision(finalTarget) == Self.revision(created)'),
      );
      expect(text, contains('try afterExclusiveCreate?()'));
      expect(text, isNot(contains('unlinkat(')));
      expect(text, isNot(contains('O_TRUNC')));
      expect(text, isNot(contains('rename(')));
    },
  );

  test('native text source contract: serial scoped channels and raw bytes', () {
    expect(source, contains('private let searchQueue = DispatchQueue('));
    expect(source, contains('isSearch ? self.searchQueue'));
    expect(source, contains('case "listWorkspaceDirectory":'));
    expect(source, contains('case "readWorkspaceTextBytes":'));
    expect(source, contains('arguments["relativePath"] as? String'));
    expect(source, contains('CFGetTypeID(number) != CFBooleanGetTypeID()'));
    expect(
      source,
      contains(
        '["bytes": FlutterStandardTypedData(bytes: contents.bytes), '
        '"revision": contents.revision]',
      ),
    );
  });

  test(
    'native text source contract: shared pinned root, no absolute fallback',
    () {
      expect(source, contains('AttachmentScope: WorkspaceFileScope'));
      expect(source, contains('WorkspaceTextScope: WorkspaceFileScope'));
      expect(core, contains('O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC'));
      expect(core, contains('fcntl(descriptor, F_GETPATH'));
      expect(core, contains('openat(current, name,'));
      expect(core, contains('openat(parent, components.last!,'));
      expect(core, contains('O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC'));
      expect(core, contains('current.st_dev == identity.st_dev'));
      expect(core, contains('current.st_ino == identity.st_ino'));
      expect(core, contains(r'$0 != "." && $0 != ".."'));
      expect(
        text,
        contains(r'!components.contains(where: { $0.hasPrefix(".") })'),
      );
      expect(text, isNot(contains('Data(contentsOf:')));
      expect(text, isNot(contains('FileHandle(')));
    },
  );

  test(
    'native text source contract: search never downloads or coordinates',
    () {
      expect(core, contains('IOPOL_MATERIALIZE_DATALESS_FILES_OFF'));
      expect(core, contains('IOPOL_SCOPE_THREAD, policy)'));
      expect(core, contains('SF_DATALESS'));
      expect(text, contains('guard try !isPlaceholder(components)'));
      expect(text, contains('verifyRevision: true'));
      for (final section in [core, text]) {
        expect(section, isNot(contains('startDownloadingUbiquitousItem')));
        expect(section, isNot(contains('NSFileCoordinator')));
        expect(section, isNot(contains('CloudWorkspace.read(')));
      }
      expect(
        source,
        contains(
          'return try WorkspaceFileScope.withoutMaterialization {\n'
          '        try WorkspaceTextScope(root).readText(',
        ),
      );
    },
  );

  test(
    'native text source contract: exact pre/post identity and read bounds',
    () {
      expect(text, contains('maximumTextBytes = 5 * 1024 * 1024'));
      expect(text, contains('min(maximumBytes, Self.maximumTextBytes)'));
      expect(core, contains('attributes.st_size <= Int64(maximumBytes)'));
      expect(core, contains('maximumBytes - bytes.count + 1'));
      expect(core, contains('bytes.count + count <= maximumBytes'));
      expect(core, contains('DispatchTime.now().uptimeNanoseconds < deadline'));
      expect(core, contains('fstat(descriptor, &after)'));
      expect(
        core,
        contains(
          'fstatat(parent, components.last!, &current, AT_SYMLINK_NOFOLLOW)',
        ),
      );
      expect(core, contains('Self.revision(original) == Self.revision(after)'));
      expect(
        core,
        contains('Self.revision(original) == Self.revision(current)'),
      );
      expect(core, contains('Int64(byteCount) == original.st_size'));
      for (final field in [
        'st_dev',
        'st_ino',
        'st_size',
        'st_mtimespec.tv_sec',
        'st_mtimespec.tv_nsec',
        'st_ctimespec.tv_sec',
        'st_ctimespec.tv_nsec',
      ]) {
        expect(core, contains('attributes.$field'));
      }
    },
  );

  test(
    'native text source contract: metadata bounds never hide truncation',
    () {
      expect(text, contains('maximumDirectoryEntries = 50_000'));
      expect(text, contains('maximumVisitedDirectoryEntries = 100_000'));
      expect(text, contains('directoryTimeout: TimeInterval = 1'));
      expect(text, contains('entries.count >= entryLimit'));
      expect(text, contains('visited <= visitedLimit'));
      expect(text, contains('DispatchTime.now().uptimeNanoseconds < end'));
      expect(
        text,
        contains('fstatat(descriptor, name, &attributes, AT_SYMLINK_NOFOLLOW)'),
      );
      expect(text, contains('type == mode_t(S_IFREG)'));
      expect(text, contains('"complete": reason == nil'));
      expect(text, contains('result["reason"] = reason.code'));
      expect(text, contains('"local": !entry.placeholder'));
      expect(text, contains('CloudWorkspace.extensions.contains'));
      expect(text, isNot(contains('try visit(')));
      expect(text, isNot(contains('contentsOfDirectory(')));
    },
  );

  test(
    'native text source contract: original attachment policy stays separate',
    () {
      expect(attachments, contains('maximumImageBytes = 32 * 1024 * 1024'));
      expect(attachments, contains('maximumSettingsBytes = 64 * 1024'));
      expect(attachments, contains('if path == ".obsidian/app.json"'));
      expect(attachments, contains('Self.imageExtensions.contains'));
      expect(
        attachments,
        contains('startDownloadingUbiquitousItem(at: target)'),
      );
      expect(attachments, contains('NSFileCoordinator()'));
      expect(attachments, contains('verifyRevision: false'));
      expect(text, isNot(contains('if path == ".obsidian/app.json"')));
    },
  );
}
