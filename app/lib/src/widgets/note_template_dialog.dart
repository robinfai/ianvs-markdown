import 'package:flutter/material.dart';

import '../services/note_templates.dart';

class NoteTemplateResult {
  const NoteTemplateResult(this.title, this.text);
  final String title;
  final String text;
}

class NoteTemplateDialog extends StatefulWidget {
  const NoteTemplateDialog({super.key, this.insert = false});
  final bool insert;

  @override
  State<NoteTemplateDialog> createState() => _NoteTemplateDialogState();
}

class _NoteTemplateDialogState extends State<NoteTemplateDialog> {
  final _title = TextEditingController();
  final _source = TextEditingController(text: noteTemplates.values.first);
  String _template = noteTemplates.keys.first;

  @override
  void dispose() {
    _title.dispose();
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.insert ? 'Insert template' : 'New note from template'),
    content: SizedBox(
      width: 600,
      height: 440,
      child: Column(
        children: [
          DropdownButton<String>(
            value: _template,
            isExpanded: true,
            items: [
              for (final name in noteTemplates.keys)
                DropdownMenuItem(value: name, child: Text(name)),
            ],
            onChanged: (name) {
              if (name == null) return;
              setState(() {
                _template = name;
                _source.text = noteTemplates[name]!;
              });
            },
          ),
          TextField(
            key: const ValueKey('template-title'),
            controller: _title,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Note title'),
          ),
          const Text(
            'Variables: {{title}}, {{title_yaml}}, {{date}}, {{time}}. '
            'Use title_yaml for a quoted YAML title.',
          ),
          Expanded(
            child: TextField(
              key: const ValueKey('template-source'),
              controller: _source,
              expands: true,
              maxLines: null,
              minLines: null,
              decoration: const InputDecoration(labelText: 'Template Markdown'),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_title.text.trim().isEmpty) return;
          Navigator.pop(
            context,
            NoteTemplateResult(
              _title.text.trim(),
              expandNoteTemplate(_source.text, _title.text.trim(), DateTime.now()),
            ),
          );
        },
        child: Text(widget.insert ? 'Insert' : 'Create'),
      ),
    ],
  );
}
