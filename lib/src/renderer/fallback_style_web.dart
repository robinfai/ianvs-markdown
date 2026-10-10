// Copyright 2013 The Flutter Authors. All rights reserved.
// BSD license: LICENSE.flutter_markdown_plus in this directory.
import 'dart:js_interop';

import 'package:flutter/cupertino.dart' show CupertinoTheme;
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// A default style sheet generator.
final MarkdownStyleSheet Function(BuildContext, MarkdownStyleSheetBaseTheme?)
    // ignore: prefer_function_declarations_over_variables
    kFallbackStyle =
    (BuildContext context, MarkdownStyleSheetBaseTheme? baseTheme) {
      final MarkdownStyleSheet result = switch (baseTheme) {
        MarkdownStyleSheetBaseTheme.platform
            when _userAgent.toDart.contains('Mac OS X') =>
          MarkdownStyleSheet.fromCupertinoTheme(CupertinoTheme.of(context)),
        MarkdownStyleSheetBaseTheme.cupertino =>
          MarkdownStyleSheet.fromCupertinoTheme(CupertinoTheme.of(context)),
        _ => MarkdownStyleSheet.fromTheme(Theme.of(context)),
      };

      return result.copyWith(textScaler: MediaQuery.textScalerOf(context));
    };

@JS('window.navigator.userAgent')
external JSString get _userAgent;
