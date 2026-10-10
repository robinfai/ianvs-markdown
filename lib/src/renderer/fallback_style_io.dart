// Copyright 2013 The Flutter Authors. All rights reserved.
// BSD license: LICENSE.flutter_markdown_plus in this directory.
import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoTheme;
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// A default style sheet generator.
final MarkdownStyleSheet Function(BuildContext, MarkdownStyleSheetBaseTheme?)
    // ignore: prefer_function_declarations_over_variables
    kFallbackStyle =
    (BuildContext context, MarkdownStyleSheetBaseTheme? baseTheme) {
      MarkdownStyleSheet result;
      switch (baseTheme) {
        case MarkdownStyleSheetBaseTheme.platform:
          result = (Platform.isIOS || Platform.isMacOS)
              ? MarkdownStyleSheet.fromCupertinoTheme(
                  CupertinoTheme.of(context),
                )
              : MarkdownStyleSheet.fromTheme(Theme.of(context));
        case MarkdownStyleSheetBaseTheme.cupertino:
          result = MarkdownStyleSheet.fromCupertinoTheme(
            CupertinoTheme.of(context),
          );
        case MarkdownStyleSheetBaseTheme.material:
        // ignore: no_default_cases
        default:
          result = MarkdownStyleSheet.fromTheme(Theme.of(context));
      }

      return result.copyWith(textScaler: MediaQuery.textScalerOf(context));
    };
