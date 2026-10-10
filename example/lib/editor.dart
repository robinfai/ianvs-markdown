import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

import 'document_session.dart';

void main() => runApp(const EditorExampleApp());

/// Run independently with `flutter run -d macos -t lib/editor.dart`.
class EditorExampleApp extends StatelessWidget {
  const EditorExampleApp({super.key, this.write});

  /// A real host supplies durable storage. The default demo saves in memory.
  final Future<void> Function(String id, String source)? write;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Markdown editor',
    home: _EditorPage(write: write),
  );
}

class _EditorPage extends StatefulWidget {
  const _EditorPage({this.write});
  final Future<void> Function(String id, String source)? write;

  @override
  State<_EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<_EditorPage> {
  final _focus = FocusNode();
  final _memory = <String, String>{'draft.md': editorMarkdown};
  late final ExampleDocumentSession _session;
  var _english = true;
  var _simplified = false;
  var _status =
      'F5 saves. Ctrl/⌘L switches language. Demo storage is in memory.';

  @override
  void initState() {
    super.initState();
    _session = ExampleDocumentSession(
      id: 'draft.md',
      source: _memory['draft.md']!,
      write: widget.write ?? (id, source) async => _memory[id] = source,
    );
  }

  @override
  void dispose() {
    _session.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toggleLanguage() => setState(() => _english = !_english);

  Future<void> _save(String capturedText) async {
    await _session.persist(capturedText);
    if (mounted) {
      setState(
        () => _status = 'Saved draft.md: ${capturedText.length} characters',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Draft editor'),
      actions: [
        TextButton(
          onPressed: () {
            _toggleLanguage();
            _focus.requestFocus();
          },
          child: Text(_english ? 'English → 中文' : '中文 → English'),
        ),
      ],
    ),
    body: IanvsMarkdownLocalization(
      strings: _english
          ? const IanvsMarkdownStrings.english(
              overrides: {IanvsMarkdownMessage.save: 'Save draft'},
            )
          : const IanvsMarkdownStrings.chinese(
              overrides: {IanvsMarkdownMessage.save: '保存草稿'},
            ),
      child: IanvsMarkdownShortcuts(
        bindings: const {
          IanvsMarkdownCommand.save: [
            SingleActivator(LogicalKeyboardKey.f5, includeRepeats: false),
          ],
        },
        hostShortcuts: {
          const SingleActivator(
            LogicalKeyboardKey.keyL,
            meta: true,
            includeRepeats: false,
          ): _toggleLanguage,
          const SingleActivator(
            LogicalKeyboardKey.keyL,
            control: true,
            includeRepeats: false,
          ): _toggleLanguage,
        },
        child: Column(
          children: [
            IanvsMarkdownEditorToolbar(
              controller: _session.controller,
              focusNode: _focus,
              onSaveRequested: _save,
            ),
            Expanded(
              child: IanvsMarkdownLiveEditor(
                controller: _session.controller,
                focusNode: _focus,
                onSaveRequested: _save,
                showToolbar: false,
                showNavigationPane: false,
                autofocus: true,
                onRenderDecision: (decision) {
                  final simplified = !decision.useMarkdown;
                  if (_simplified != simplified) {
                    setState(() => _simplified = simplified);
                  }
                },
              ),
            ),
            if (_simplified)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  _english
                      ? 'Large document: simplified display; full source can still be edited and saved.'
                      : '内容较大，显示已简化；完整原文仍可编辑和保存。',
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: ValueListenableBuilder<bool>(
                valueListenable: _session.controller.dirtyListenable,
                builder: (_, dirty, _) => Text(
                  '${dirty ? 'Unsaved changes' : 'Saved snapshot'} · $_status',
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

const editorMarkdown = '''
# Your draft

Edit in **Live Preview**, Source or Reading mode.

The host owns the controller and serializes captured save requests. Edits made
while a save is running stay dirty until their own snapshot is saved.

| Feature | Host responsibility |
| --- | --- |
| Save | Persistence and errors |
| Shortcuts | Reserved commands |

- [ ] Try F5 after editing
- [ ] Change the interface language
''';
