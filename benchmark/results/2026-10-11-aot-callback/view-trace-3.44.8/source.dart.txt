import 'package:flutter/material.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

// AOT diagnostic only. Run in the example package so its public path dependency
// resolves the same component revision as the full reading entry point.
void main() => runApp(
  MaterialApp(
    home: Scaffold(
      body: IanvsMarkdownView(data: '# Candidate\n\nA small **Markdown** view.'),
    ),
  ),
);
