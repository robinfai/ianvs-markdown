import 'package:flutter/material.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

void main() => runApp(const BodyExampleApp());

/// Run independently with `flutter run -d macos -t lib/body.dart`.
class BodyExampleApp extends StatelessWidget {
  const BodyExampleApp({super.key});

  @override
  Widget build(BuildContext context) =>
      MaterialApp(title: 'Markdown body', home: const _BodyPage());
}

class _BodyPage extends StatefulWidget {
  const _BodyPage();

  @override
  State<_BodyPage> createState() => _BodyPageState();
}

class _BodyPageState extends State<_BodyPage> {
  var _preset = IanvsMarkdownSyntaxPreset.standard;
  String? _requestedLink;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Markdown in a card')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        SegmentedButton<IanvsMarkdownSyntaxPreset>(
          segments: const [
            ButtonSegment(
              value: IanvsMarkdownSyntaxPreset.standard,
              label: Text('GFM'),
            ),
            ButtonSegment(
              value: IanvsMarkdownSyntaxPreset.obsidian,
              label: Text('Obsidian'),
            ),
          ],
          selected: {_preset},
          onSelectionChanged: (value) => setState(() => _preset = value.single),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: IanvsMarkdown(
              data: bodyMarkdown,
              syntaxPreset: _preset,
              // This host explicitly resolves one virtual asset. Unknown URLs
              // stay blocked; no file or network access is performed.
              imageBuilder: (uri, title, alt) =>
                  uri.toString() == 'asset:approved-logo'
                  ? Semantics(
                      label: alt ?? 'Host supplied logo',
                      image: true,
                      child: const Align(
                        alignment: Alignment.centerLeft,
                        child: FlutterLogo(size: 48),
                      ),
                    )
                  : const Text('Image not approved by this host'),
              onTapLink: (text, href, title) {
                setState(() => _requestedLink = href);
              },
            ),
          ),
        ),
        if (_requestedLink case final link?) Text('Host received link: $link'),
      ],
    ),
  );
}

const bodyMarkdown = '''
# A message-sized renderer

The host owns scrolling, links and images. This card is **selectable**.

Switch the preset to compare ==highlighted words== with standard GFM text.

[Open the guide](guide.md)

![Approved local logo](asset:approved-logo)

![Unapproved image](https://example.invalid/blocked.png)
''';
