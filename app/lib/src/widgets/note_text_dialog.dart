import 'package:flutter/material.dart';

/// Owns its input until the dialog route finishes its closing animation.
class NoteTextDialog extends StatefulWidget {
  const NoteTextDialog({
    super.key,
    required this.title,
    required this.label,
    required this.submit,
    this.initialValue = '',
    this.helperText,
    this.inputKey,
    this.multiline = false,
  });
  final String title;
  final String label;
  final String submit;
  final String initialValue;
  final String? helperText;
  final Key? inputKey;
  final bool multiline;

  @override
  State<NoteTextDialog> createState() => _NoteTextDialogState();
}

class _NoteTextDialogState extends State<NoteTextDialog> {
  late final _text = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 520,
      child: TextField(
        key: widget.inputKey,
        controller: _text,
        autofocus: true,
        minLines: widget.multiline ? 4 : 1,
        maxLines: widget.multiline ? 10 : 1,
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: widget.helperText,
        ),
        onSubmitted: widget.multiline
            ? null
            : (value) => Navigator.pop(context, value),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _text.text),
        child: Text(widget.submit),
      ),
    ],
  );
}
