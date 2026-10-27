import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Only wrap non-interactive header space: tabs own their reorder gestures.
class WindowDragRegion extends StatelessWidget {
  const WindowDragRegion({super.key, required this.child});

  final Widget child;
  static const channel = MethodChannel('work.ianvs.linefold/window');

  Future<void> _startDrag() async {
    try {
      await channel.invokeMethod<void>('startDrag');
    } on MissingPluginException {
      // Widget tests and component-only hosts do not have an AppKit window.
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: (event) {
      if (defaultTargetPlatform == TargetPlatform.macOS &&
          event.kind == PointerDeviceKind.mouse &&
          event.buttons == kPrimaryMouseButton) {
        unawaited(_startDrag());
      }
    },
    child: child,
  );
}
