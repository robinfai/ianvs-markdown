import 'dart:convert';
import 'package:ianvs_markdown/ianvs_markdown_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';
import 'package:ianvs_mermaid/ianvs_mermaid.dart';
import 'shared/desktop_theme.dart';
import 'shared/document_render_policy.dart';
import 'shared/models/reading_preferences.dart';
import 'shared/reading_typography.dart';

const bridge = MethodChannel('work.ianvs.linefold.quicklook');

void main(List<String> arguments) {
  WidgetsFlutterBinding.ensureInitialized();
  final input =
      jsonDecode(utf8.decode(base64Decode(arguments.single)))
          as Map<String, dynamic>;
  runApp(
    scrollFrameProbeEnabled
        ? ScrollFrameProbe(
            host: 'finder',
            child: Preview(input: input),
          )
        : Preview(input: input),
  );
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => bridge.invokeMethod<void>('firstFrame'),
  );
}

class Preview extends StatefulWidget {
  const Preview({super.key, required this.input});
  final Map<String, dynamic> input;
  @override
  State<Preview> createState() => _PreviewState();
}

class _PreviewState extends State<Preview> with WidgetsBindingObserver {
  late final renderer = NativeMermanRenderer();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    bridge.setMethodCallHandler((call) async {
      if (call.method == 'copy') {
        return IanvsMarkdownShortcuts.invoke(IanvsMarkdownCommand.copy);
      }
      if (call.method == 'selectAll') {
        return IanvsMarkdownShortcuts.invoke(IanvsMarkdownCommand.selectAll);
      }
      return null;
    });
  }

  @override
  void didChangePlatformBrightness() => setState(() {});
  @override
  void dispose() {
    bridge.setMethodCallHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zh =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'zh';
    return Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery.fromView(
        view: WidgetsBinding.instance.platformDispatcher.views.first,
        child: Localizations(
          locale: Locale(zh ? 'zh' : 'en'),
          delegates: GlobalMaterialLocalizations.delegates,
          child: Theme(
            data: desktopTheme(
              WidgetsBinding.instance.platformDispatcher.platformBrightness,
            ),
            child: IanvsMarkdownLocalization(
              strings: zh
                  ? const IanvsMarkdownStrings.chinese()
                  : const IanvsMarkdownStrings.english(),
              child: Builder(
                builder: (context) => Overlay.wrap(
                  child: Material(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final inset =
                            ((constraints.maxWidth -
                                        ReadingPreferences
                                            .defaults
                                            .width
                                            .pixels) /
                                    2)
                                .clamp(24.0, double.infinity);
                        final source = widget.input['source'] as String;
                        return source.isEmpty
                            ? Padding(
                                padding: EdgeInsets.fromLTRB(
                                  inset,
                                  32,
                                  inset,
                                  48,
                                ),
                                child: Text(
                                  zh ? '文档为空' : 'This document is empty.',
                                ),
                              )
                            : IanvsMarkdown(
                                data: source,
                                renderBudget: linefoldDocumentRenderBudget,
                                clipboardBudget: linefoldDocumentRenderBudget,
                                autofocus: true,
                                scrollable: true,
                                scrollPadding: EdgeInsets.fromLTRB(
                                  inset,
                                  32,
                                  inset,
                                  48,
                                ),
                                styleSheet: readingStyleSheet(
                                  context,
                                  ReadingPreferences.defaults,
                                ),
                                diagramBuilder: (context, source) =>
                                    MermaidView(
                                      source: source,
                                      renderer: renderer,
                                    ),
                                imageBuilder: (uri, title, alt) => PreviewImage(
                                  uri: uri,
                                  label: alt ?? title ?? '',
                                  zh: zh,
                                ),
                              );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PreviewImage extends StatefulWidget {
  const PreviewImage({
    super.key,
    required this.uri,
    required this.label,
    required this.zh,
  });
  final Uri uri;
  final String label;
  final bool zh;
  @override
  State<PreviewImage> createState() => _PreviewImageState();
}

class _PreviewImageState extends State<PreviewImage> {
  late final Future<Uint8List?> bytes = bridge.invokeMethod<Uint8List>(
    'image',
    widget.uri.toString(),
  );
  @override
  Widget build(BuildContext context) {
    final fallback = Text(
      widget.label.isNotEmpty
          ? widget.label
          : widget.zh
          ? '无法访问此图片'
          : 'Image unavailable',
    );
    return FutureBuilder<Uint8List?>(
      future: bytes,
      builder: (context, snapshot) => snapshot.data == null
          ? fallback
          : Image.memory(
              snapshot.data!,
              cacheWidth: 1600,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}
