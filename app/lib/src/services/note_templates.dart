import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:ianvs_markdown/ianvs_markdown.dart';

String noteDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String expandNoteTemplate(String source, String title, DateTime now) {
  final variables = {
    'title': title,
    'title_yaml': jsonEncode(title),
    'date': noteDate(now),
    'time': '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}',
  };
  return source.replaceAllMapped(
    RegExp(r'\{\{(title_yaml|title|date|time)\}\}'),
    (match) => variables[match[1]]!,
  );
}

const noteTemplates = <String, String>{
  'Meeting notes': '''---
title: {{title_yaml}}
date: {{date}}
category: meeting
---
# {{title}}

## Attendees

## Agenda

## Notes — {{time}}

## Actions
- [ ] 
''',
  'Reading card': '''---
title: {{title_yaml}}
date: {{date}}
category: reading
status: to-read
---
# {{title}}

## Source

## Key ideas

## Quotes

## My thoughts
''',
  'Technical proposal': '''---
title: {{title_yaml}}
date: {{date}}
category: proposal
status: draft
---
# {{title}}

## Problem

## Goals

## Proposed approach

## Alternatives

## Validation
''',
  'Blog draft': '''---
title: {{title_yaml}}
date: {{date}}
category: blog
status: idea
---
# {{title}}

## Outline

## Draft

## References
''',
};

/// Delayed template insertion must target the captured source and selection.
class CapturedNoteInsertion {
  CapturedNoteInsertion(this.value, this.mode);
  final TextEditingValue value;
  final IanvsMarkdownEditorMode mode;

  bool apply(IanvsMarkdownController controller, String text) {
    final selection = value.selection;
    if (controller.value != value ||
        controller.mode != mode ||
        mode == IanvsMarkdownEditorMode.preview ||
        !selection.isValid ||
        selection.end > value.text.length ||
        (value.composing.isValid && !value.composing.isCollapsed)) {
      return false;
    }
    controller.commitHistoryGroup();
    controller.value = TextEditingValue(
      text: value.text.replaceRange(selection.start, selection.end, text),
      selection: TextSelection.collapsed(offset: selection.start + text.length),
    );
    controller.commitHistoryGroup();
    return true;
  }
}
