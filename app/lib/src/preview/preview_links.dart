import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:path/path.dart' as p;

import '../services/workspace_index_source.dart';
import 'preview_library.dart';

class PreviewLinkDestination {
  const PreviewLinkDestination(this.paths, this.fragment);
  final List<String> paths;
  final String fragment;
}

/// Metadata-only navigation inside an explicitly selected workspace. Imported
/// single files are copies: their former parent is never searched or granted.
PreviewLinkDestination resolvePreviewLink({
  required IanvsMarkdownLinkTarget link,
  required String root,
  required String origin,
  required List<PreviewDocument> documents,
}) {
  final href = link.href ?? '';
  String target;
  String fragment;
  final wiki = link.kind == IanvsMarkdownLinkKind.wiki;
  if (wiki) {
    final hash = href.indexOf('#');
    target = hash < 0 ? href : href.substring(0, hash);
    fragment = hash < 0 ? '' : href.substring(hash + 1);
  } else {
    final uri = Uri.parse(href);
    if (uri.hasScheme || uri.hasAuthority || uri.hasQuery) {
      throw const FormatException('只能导航当前文件夹内的相对 Markdown 链接。');
    }
    target = Uri.decodeComponent(uri.path);
    fragment = Uri.decodeComponent(uri.fragment);
  }
  if (fragment.startsWith('^')) {
    throw const FormatException('此版本暂不支持块引用导航。');
  }
  if (target.isEmpty) return PreviewLinkDestination([origin], fragment);
  if (target.contains('\\') ||
      p.isAbsolute(target) ||
      target.contains(RegExp(r'[:\x00-\x1f\x7f]'))) {
    throw const FormatException('链接超出当前文件夹。');
  }
  if (wiki && !target.toLowerCase().endsWith('.md')) target += '.md';
  final paths = <String>[];
  if (wiki && !target.contains('/')) {
    for (final doc in documents) {
      if (p.isWithin(root, doc.path) &&
          p.basename(doc.path).toLowerCase() == target.toLowerCase()) {
        paths.add(doc.path);
      }
    }
  } else {
    final resolved = p.normalize(
      p.join(wiki ? root : p.dirname(origin), target),
    );
    final relative = p.relative(resolved, from: root);
    if (!p.isWithin(root, resolved) ||
        !safeWorkspaceRelativePath(relative) ||
        !previewExtensions.contains(p.extension(resolved).toLowerCase())) {
      throw const FormatException('链接超出当前文件夹或不是 Markdown 文档。');
    }
    for (final doc in documents) {
      if (p.equals(doc.path, resolved)) paths.add(doc.path);
    }
  }
  if (paths.isEmpty) throw const FormatException('当前文件夹未找到此文档，请刷新列表或手动导入。');
  paths.sort();
  return PreviewLinkDestination(paths, fragment);
}
