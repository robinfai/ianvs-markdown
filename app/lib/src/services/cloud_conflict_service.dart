import 'dart:convert';
import 'package:flutter/services.dart';
import 'apple_workspace_service.dart';
import 'markdown_text_codec.dart';

class CloudConflictReview {
  CloudConflictReview(Map<String, dynamic> data)
    : session = data['session'] as String,
      current = decodeMarkdownUtf8(data['current'] as Uint8List),
      versions = (data['versions'] as List)
          .map(
            (v) => (
              id: v['id'] as String,
              name: v['name'] as String,
              contents: decodeMarkdownUtf8(v['contents'] as Uint8List),
            ),
          )
          .toList();
  final String session;
  final String current;
  final List<({String id, String name, String contents})> versions;
}

class CloudConflictService {
  const CloudConflictService({
    required this.root,
    required this.relativePath,
    this.workspaceToken,
  });
  final String root;
  final String relativePath;
  final String? workspaceToken;
  Map<String, Object?> get _scope => {
    'path': root,
    'relativePath': relativePath,
    if (workspaceToken != null) 'workspaceToken': workspaceToken,
  };
  Future<CloudConflictReview> inspect() async => CloudConflictReview(
    (await AppleWorkspaceService.channel.invokeMapMethod<String, dynamic>(
      'inspectCloudConflict',
      _scope,
    ))!,
  );
  Future<({String contents, List<String> copies, bool resolutionPending})>
  resolve(CloudConflictReview review, String choice, String local) async {
    final result = (await AppleWorkspaceService.channel
        .invokeMapMethod<String, dynamic>('resolveCloudConflict', {
          ..._scope,
          'session': review.session,
          'choice': choice,
          'localContents': Uint8List.fromList(utf8.encode(local)),
        }))!;
    return (
      contents: decodeMarkdownUtf8(result['contents'] as Uint8List),
      copies: List<String>.from(result['copies'] as List),
      resolutionPending: result['resolutionPending'] == true,
    );
  }
}
