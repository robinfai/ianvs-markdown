import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import 'attachment_repository.dart';
import 'attachment_resolver.dart';

/// Immutable command-time source, not the persisted file or a later editor value.
class DocumentExportSnapshot {
  const DocumentExportSnapshot({
    required this.documentId,
    required this.title,
    required this.source,
    this.documentPath,
    this.root,
    this.protectedPaths = const [],
  });
  final String documentId;
  final String title;
  final String source;
  final String? documentPath;
  final String? root;
  final List<String> protectedPaths;
}

enum DocumentExportAction { html, markdown, pdf }

class DocumentExportFailure implements Exception {
  const DocumentExportFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class ExportedDocument {
  const ExportedDocument(this.content, this.notices);
  final String content;
  final List<String> notices;
}

const documentExportFidelityNotice =
    'Basic offline export, not an exact copy of the editor. '
    'Math and Mermaid are included as readable source, not rendered diagrams. '
    'Images use the first frame and at most 2048 pixels per side. '
    'Missing or blocked images become labeled placeholders. '
    'Local note links are text only; remote images are never downloaded. '
    'Your Markdown original and unsaved edits are not changed.';

const documentExportMarkdownNotice =
    'Exports the current Markdown text verbatim as a UTF-8 copy. '
    'Attachments are not copied. Relative image and note links stay unchanged '
    'and may not resolve in the destination folder. '
    'Your original and unsaved edits are not changed.';

const documentExportPdfNotice =
    'PDF is a readable paged export, not a pixel-perfect copy. '
    'Copy/search text and reading order vary by PDF viewer, including punctuation. '
    'Some Chinese characters may copy or search as visually similar CJK radicals. '
    'Table headers may appear only on the first page, and a blank trailing page may occur. '
    'Complex math and Mermaid remain readable source, as described above.';

/// No raw HTML is copied through. Only known AST elements and individually
/// checked attributes are serialized; source HTML is visible escaped text.
/// HTML is a complete offline document. Markdown copies skip parsing and assets.
class DocumentExportService {
  const DocumentExportService({
    this.attachmentSource = const AppleAttachmentSource(),
    this.maximumImages = 32,
    this.maximumImageBytes = 16 * 1024 * 1024,
    this.maximumOutputBytes = 32 * 1024 * 1024,
  });
  final AttachmentSource attachmentSource;
  final int maximumImages;
  final int maximumImageBytes;
  final int maximumOutputBytes;

  ExportedDocument buildMarkdown(
    DocumentExportSnapshot snapshot, {
    required bool Function() isCurrent,
  }) {
    if (!isCurrent()) {
      throw const DocumentExportFailure(
        'Export cancelled because the document or folder changed.',
      );
    }
    // Verbatim copies need no parser, rendering budget, or attachment I/O.
    // Charge UTF-8 incrementally before the platform codec allocates its copy.
    _ExportByteBudget(
      maximumOutputBytes,
    ).chargeText(snapshot.source, 0, snapshot.source.length);
    for (var index = 0; index < snapshot.source.length; index++) {
      final unit = snapshot.source.codeUnitAt(index);
      if (unit < 0xd800 || unit > 0xdfff) continue;
      if (unit <= 0xdbff && index + 1 < snapshot.source.length) {
        final next = snapshot.source.codeUnitAt(index + 1);
        if (next >= 0xdc00 && next <= 0xdfff) {
          index++;
          continue;
        }
      }
      throw const DocumentExportFailure(
        'Markdown contains invalid Unicode and cannot be exported losslessly.',
      );
    }
    return ExportedDocument(snapshot.source, const [
      documentExportMarkdownNotice,
    ]);
  }

  Future<ExportedDocument> build(
    DocumentExportSnapshot snapshot, {
    required bool Function() isCurrent,
    bool forPdf = false,
  }) async {
    void check() {
      if (!isCurrent()) {
        throw const DocumentExportFailure(
          'Export cancelled because the document or folder changed.',
        );
      }
    }

    check();
    final decision = scanMarkdownForRendering(
      snapshot.source,
      budget: const IanvsMarkdownRenderBudget(),
    );
    if (!decision.useMarkdown) {
      throw const DocumentExportFailure(
        'This document exceeds the safe export limit. '
        'Export a smaller document; no truncated file was created.',
      );
    }
    final repository = AttachmentRepository(
      root: snapshot.root,
      source: _ScopedAttachmentSource(attachmentSource, check),
    );
    try {
      final budget = _ExportByteBudget(maximumOutputBytes);
      final output = _BoundedHtmlBuffer(budget);
      // Reserve the fixed document and visible notices before any asset reads.
      final notesOutput = _BoundedHtmlBuffer(budget);
      final ending = _BoundedHtmlBuffer(budget);
      output.write('''<!doctype html>
<html lang="und"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; object-src 'none'">
<title>''');
      output.writeEscaped(snapshot.title);
      output.write('</title><style>$_exportCss</style></head><body><article>');
      notesOutput.write(
        '</article><aside class="export-notes"><h2>Export notes</h2><ul><li>',
      );
      notesOutput.writeEscaped(documentExportFidelityNotice);
      notesOutput.write('</li>');
      if (forPdf) {
        notesOutput.write('<li>');
        notesOutput.writeEscaped(documentExportPdfNotice);
        notesOutput.write('</li>');
      }
      ending.write('</ul></aside></body></html>');
      final writer = _ExportWriter(
        this,
        snapshot,
        repository,
        check,
        output,
        notesOutput,
      );
      final frontMatter = parseMarkdownFrontMatter(snapshot.source);
      final parser = md.Document(
        extensionSet: md.ExtensionSet.gitHubFlavored,
        encodeHtml: false,
        blockSyntaxes: const [
          IanvsMarkdownWikiEmbedSyntax(),
          IanvsMarkdownDisplayMathSyntax(),
        ],
        inlineSyntaxes: [
          _ExportWikiEmbedSyntax(),
          IanvsMarkdownWikiLinkSyntax(),
          IanvsMarkdownInlineDisplayMathSyntax(),
          IanvsMarkdownInlineMathSyntax(),
          IanvsMarkdownEntitySyntax(
            presentation: IanvsMarkdownEntityPresentation.reading,
          ),
        ],
      );
      final nodes = parser.parseLines(
        const LineSplitter().convert(frontMatter.body),
      );
      if (frontMatter.hasFrontMatter) {
        final raw = snapshot.source.substring(
          0,
          snapshot.source.length - frontMatter.body.length,
        );
        output.write('<section><h2>Document properties (source)</h2><pre>');
        output.writeEscaped(raw);
        output.write('</pre></section>');
      }
      for (final node in nodes) {
        await writer.node(node);
        check();
      }
      final notices = [
        documentExportFidelityNotice,
        if (forPdf) documentExportPdfNotice,
        ...writer.notices,
      ];
      // Each segment was already charged against the shared UTF-8 budget.
      // Concatenation is now bounded, unlike checking a completed large string.
      final html = '$output$notesOutput$ending';
      check();
      return ExportedDocument(html, List.unmodifiable(notices));
    } finally {
      repository.dispose();
    }
  }
}

/// Every I/O boundary rechecks command-time scope, including failed awaits.
/// An already-started native operation cannot be recalled, but invalidation
/// prevents its result from starting settings/normalization/image I/O next.
class _ScopedAttachmentSource implements AttachmentSource {
  _ScopedAttachmentSource(this.source, this.check);
  final AttachmentSource source;
  final void Function() check;

  Future<T> _guard<T>(Future<T> Function() operation) async {
    check();
    try {
      return await operation();
    } finally {
      check();
    }
  }

  @override
  Future<List<AttachmentMetadata>> list(String root) =>
      _guard(() => source.list(root));
  @override
  Future<List<String>> normalize(List<String> paths) =>
      _guard(() => source.normalize(paths));
  @override
  Future<Uint8List> read(String root, String relativePath, int maximumBytes) =>
      _guard(() => source.read(root, relativePath, maximumBytes));
  @override
  Future<Uint8List> readImportSettings(String root) =>
      _guard(() => source.readImportSettings(root));
}

/// Shares a single byte budget across body, fixed envelope and dynamic notices.
/// Counts UTF-8 without allocating a second byte array. UTF-16 surrogate pairs
/// use four bytes; lone surrogates use the encoder's three-byte replacement.
class _ExportByteBudget {
  _ExportByteBudget(this.maximum);
  final int maximum;
  int used = 0;

  void ensureCapacity(int bytes) {
    if (bytes > maximum - used) {
      throw const DocumentExportFailure(
        'Export exceeds the output size limit. No file was created.',
      );
    }
  }

  void charge(int bytes) {
    ensureCapacity(bytes);
    used += bytes;
  }

  void chargeText(String value, int start, int end) {
    var bytes = 0;
    final remaining = maximum - used;
    for (var i = start; i < end; i++) {
      final unit = value.codeUnitAt(i);
      if (unit < 0x80) {
        bytes++;
      } else if (unit < 0x800) {
        bytes += 2;
      } else if (unit >= 0xd800 &&
          unit <= 0xdbff &&
          i + 1 < end &&
          value.codeUnitAt(i + 1) >= 0xdc00 &&
          value.codeUnitAt(i + 1) <= 0xdfff) {
        bytes += 4;
        i++;
      } else {
        bytes += 3;
      }
      if (bytes > remaining) {
        ensureCapacity(bytes);
      }
    }
    charge(bytes);
  }
}

class _BoundedHtmlBuffer {
  _BoundedHtmlBuffer(this.budget);
  final _ExportByteBudget budget;
  final _buffer = StringBuffer();

  void write(String value) {
    budget.chargeText(value, 0, value.length);
    _buffer.write(value);
  }

  // Only use for our generated base64 data URI, never user-controlled text.
  void writeAscii(String value) {
    budget.charge(value.length);
    _buffer.write(value);
  }

  void _writeRange(String value, int start, int end) {
    if (start == end) return;
    budget.chargeText(value, start, end);
    // Allocate a slice only after it fits. Escaping never builds a large
    // intermediate string that can exceed the output budget.
    _buffer.write(
      start == 0 && end == value.length ? value : value.substring(start, end),
    );
  }

  void writeEscaped(String value) {
    var start = 0;
    for (var i = 0; i < value.length; i++) {
      final replacement = switch (value.codeUnitAt(i)) {
        0x26 => '&amp;',
        0x3c => '&lt;',
        0x3e => '&gt;',
        0x22 => '&quot;',
        0x27 => '&#39;',
        0x2f => '&#47;',
        _ => null,
      };
      if (replacement == null) continue;
      _writeRange(value, start, i);
      writeAscii(replacement);
      start = i + 1;
    }
    _writeRange(value, start, value.length);
  }

  @override
  String toString() => _buffer.toString();
}

class _ExportWriter {
  _ExportWriter(
    this.service,
    this.snapshot,
    this.repository,
    this.check,
    this.output,
    this.notesOutput,
  );
  final DocumentExportService service;
  final DocumentExportSnapshot snapshot;
  final AttachmentRepository repository;
  final void Function() check;
  final _BoundedHtmlBuffer output;
  final _BoundedHtmlBuffer notesOutput;
  final notices = <String>[];
  final images = <String, String>{};
  int imageCount = 0;
  int imageBytes = 0;

  Future<void> node(md.Node node) async {
    check();
    if (node is md.Text) {
      output.writeEscaped(node.text);
      return;
    }
    if (node is! md.Element) return;
    final tag = node.tag;
    final attributes = node.attributes;
    if (tag == 'img' || tag == 'ianvs-wiki-embed') {
      final wiki = tag == 'ianvs-wiki-embed';
      final target = attributes[wiki ? 'data-target' : 'src'] ?? '';
      final label = attributes[wiki ? 'data-alias' : 'alt'] ?? '';
      if (wiki &&
          !IanvsMarkdownWikiEmbedReference(
            source: '',
            target: target,
            note: target.split('#').first,
          ).isImageEmbed) {
        output.write('<p class="placeholder">Note embed: ');
        output.writeEscaped(label.isEmpty ? target : label);
        output.write(' (not expanded)</p>');
        return;
      }
      await image(
        target,
        label,
        wiki ? AttachmentLinkKind.wiki : AttachmentLinkKind.markdown,
      );
      return;
    }
    if (tag.contains('math')) {
      final inline = tag == 'ianvs-inline-math';
      output.write(
        inline
            ? '<code class="math-source">\$'
            : '<pre class="math-source">\$\$\n',
      );
      output.writeEscaped(attributes['data-expression'] ?? node.textContent);
      output.write(inline ? '\$</code>' : '\n\$\$</pre>');
      return;
    }
    if (tag == 'input') {
      if (attributes['type'] == 'checkbox') {
        output.write(attributes.containsKey('checked') ? '☑ ' : '☐ ');
      }
      return;
    }
    final known = _tags.contains(tag);
    if (known) {
      output.write('<$tag');
      if (tag == 'a') {
        final href = attributes['href'];
        if (href != null &&
            attributes['data-ianvs-wiki-link'] != 'true' &&
            _safeLink(href)) {
          output.write(' href="');
          output.writeEscaped(href);
          output.write('" rel="noreferrer noopener"');
        }
      } else if (tag == 'ol') {
        final start = int.tryParse(attributes['start'] ?? '');
        if (start != null && start >= 0 && start <= 1000000) {
          output.write(' start="$start"');
        }
      } else if (tag == 'th' || tag == 'td') {
        final align = attributes['align'];
        if (const ['left', 'center', 'right'].contains(align)) {
          output.write(' class="align-$align"');
        }
      } else if (tag == 'code' && attributes['class'] == 'language-mermaid') {
        output.write(' class="mermaid-source"');
      }
      output.write('>');
    }
    for (final child in node.children ?? <md.Node>[]) {
      await this.node(child);
    }
    if (known && tag != 'hr' && tag != 'br') output.write('</$tag>');
  }

  Future<void> image(
    String target,
    String label,
    AttachmentLinkKind kind,
  ) async {
    final number = ++imageCount;
    void unavailable(String reason) {
      final notice = 'Image $number: $reason';
      // Charge notices immediately, not after subsequent image reads.
      notesOutput.write('<li>');
      notesOutput.writeEscaped(notice);
      notesOutput.write('</li>');
      notices.add(notice);
      output.write(
        '<span class="placeholder" role="img" aria-label="Image unavailable">',
      );
      output.writeEscaped(label.isEmpty ? 'Image $number' : label);
      output.write(' [image unavailable]</span>');
    }

    if (number > service.maximumImages) {
      unavailable('Image count limit reached.');
      return;
    }
    final key = '${kind.name}:$target';
    var uri = images[key];
    if (uri == null) {
      AttachmentImageLease? lease;
      try {
        check();
        output.budget.ensureCapacity(1);
        lease = await repository.load(
          documentPath: snapshot.documentPath,
          target: target,
          kind: kind,
        );
        check();
        final bytes = await lease.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        check();
        if (bytes == null ||
            imageBytes + bytes.lengthInBytes > service.maximumImageBytes) {
          unavailable('Embedded image byte limit reached.');
          return;
        }
        // Reject before allocating base64 if it cannot fit even once. Cached
        // reuse is still charged per occurrence when it is appended below.
        final uriBytes =
            'data:image/png;base64,'.length +
            4 * ((bytes.lengthInBytes + 2) ~/ 3);
        output.budget.ensureCapacity(uriBytes);
        imageBytes += bytes.lengthInBytes;
        uri =
            'data:image/png;base64,${base64Encode(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes))}';
        images[key] = uri;
      } on DocumentExportFailure {
        rethrow;
      } on Object catch (error) {
        check();
        unavailable(attachmentFailure(error).message);
        return;
      } finally {
        lease?.dispose();
      }
    }
    output.write('<img src="');
    output.writeAscii(uri);
    output.write('" alt="');
    output.writeEscaped(label);
    output.write('">');
  }
}

class _ExportWikiEmbedSyntax extends md.InlineSyntax {
  _ExportWikiEmbedSyntax()
    : super(r'!\[\[([^\]\n]+)\]\]', startCharacter: 0x21);
  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final parts = match[1]!.split('|');
    parser.addNode(
      md.Element.empty('ianvs-wiki-embed')
        ..attributes['data-target'] = parts.first.trim()
        ..attributes['data-alias'] = parts.length > 1
            ? parts.sublist(1).join('|').trim()
            : '',
    );
    return true;
  }
}

bool _safeLink(String value) {
  if (value.contains(RegExp(r'[\x00-\x20\x7f\\]'))) return false;
  if (value.startsWith('#')) return true;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !const ['https', 'http', 'mailto'].contains(uri.scheme.toLowerCase())) {
    return false;
  }
  return uri.scheme.toLowerCase() == 'mailto' || uri.host.isNotEmpty;
}

const _tags = {
  'p',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'blockquote',
  'pre',
  'code',
  'em',
  'strong',
  'del',
  's',
  'ul',
  'ol',
  'li',
  'table',
  'thead',
  'tbody',
  'tfoot',
  'tr',
  'th',
  'td',
  'a',
  'hr',
  'br',
  'sup',
  'sub',
};

const _exportCss = '''
@page { margin: 18mm; }
* { box-sizing: border-box; }
body { margin: 0 auto; max-width: 174mm; padding: 12px; color: #171717; background: #fff;
 font: 11pt/1.6 -apple-system, BlinkMacSystemFont, "PingFang SC", "Hiragino Sans GB", "Noto Sans CJK SC", "Microsoft YaHei", sans-serif; overflow-wrap: anywhere; }
h1,h2,h3,h4,h5,h6 { break-after: avoid; line-height: 1.25; }
p,li { orphans: 3; widows: 3; }
pre,code { font-family: "SFMono-Regular", Menlo, "Noto Sans Mono CJK SC", monospace; font-size: 9pt; }
pre { white-space: pre-wrap; overflow-wrap: anywhere; word-break: break-word; padding: 10px; border: 1px solid #ccc; }
code { white-space: pre-wrap; overflow-wrap: anywhere; }
blockquote { border-left: 3px solid #aaa; margin-left: 0; padding-left: 12px; }
table { border-collapse: collapse; table-layout: fixed; width: 100%; font-size: 9pt; }
thead { display: table-header-group; }
tfoot { display: table-footer-group; }
th,td { border: 1px solid #999; padding: 5px; vertical-align: top; overflow-wrap: anywhere; word-break: break-word; }
tr { break-inside: avoid; }
img { max-width: 100%; height: auto; break-inside: avoid; }
a { color: #174c91; }
.align-left { text-align: left; } .align-center { text-align: center; } .align-right { text-align: right; }
.placeholder { border: 1px dashed #777; padding: 4px; }
.export-notes { margin-top: 24px; border-top: 1px solid #aaa; font-size: 9pt; }
@media print { body { width: 100%; max-width: none; margin: 0; padding: 1px; } }
''';

abstract class DocumentExportPlatform {
  Future<bool> output({
    required DocumentExportAction action,
    required ExportedDocument document,
    required DocumentExportSnapshot snapshot,
    required bool Function() isCurrent,
  });
  Future<void> cancel(DocumentExportSnapshot snapshot);
}

class AppleDocumentExportPlatform implements DocumentExportPlatform {
  const AppleDocumentExportPlatform();
  static const channel = MethodChannel('work.ianvs.linefold/document_export');
  // A restarted Dart isolate must never approve an old native panel whose
  // counter happens to match a new export. This nonce is not exported content.
  static final _session = base64Url.encode(
    List<int>.generate(16, (_) => _random.nextInt(256)),
  );
  static final _random = Random.secure();
  static int _sequence = 0;
  static final _pending =
      <
        String,
        ({DocumentExportSnapshot snapshot, bool Function() isCurrent})
      >{};

  static void _installHandler() {
    channel.setMethodCallHandler((call) async {
      if (call.method != 'approveCommit' || call.arguments is! Map) {
        return false;
      }
      final id = (call.arguments as Map)['operationId'];
      // Native asks again AFTER the user's SavePanel choice. Cancellation alone
      // is insufficient: its cross-bridge message could arrive after selection.
      return _pending[id]?.isCurrent() ?? false;
    });
  }

  @override
  Future<void> cancel(DocumentExportSnapshot snapshot) async {
    final ids = [
      for (final entry in _pending.entries)
        if (identical(entry.value.snapshot, snapshot)) entry.key,
    ];
    for (final id in ids) {
      await channel.invokeMethod<bool>('cancel', {'operationId': id});
    }
  }

  @override
  Future<bool> output({
    required DocumentExportAction action,
    required ExportedDocument document,
    required DocumentExportSnapshot snapshot,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return false;
    _installHandler();
    final id = '$_session:${++_sequence}';
    _pending[id] = (snapshot: snapshot, isCurrent: isCurrent);
    try {
      return await channel.invokeMethod<bool>(action.name, {
            'operationId': id,
            'content': document.content,
            'title': snapshot.title,
            'sourcePath': snapshot.documentPath,
            'protectedPaths': snapshot.protectedPaths,
          }) ??
          false;
    } finally {
      _pending.remove(id);
    }
  }
}
