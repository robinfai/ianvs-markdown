import 'dart:io';
import 'dart:math' as math;

import 'package:ianvs_design/ianvs_design.dart';

import '../desktop_theme.dart';
import '../desktop_typography.dart';

/// Leaves the native macOS window buttons unobstructed.
class WindowAppTitle extends StatelessWidget {
  const WindowAppTitle({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: math.max(
      DesktopMetrics.windowTitleHeight,
      MediaQuery.textScalerOf(context).scale(16) + 8,
    ),
    child: Padding(
      padding: EdgeInsets.only(left: Platform.isMacOS ? 86 : 12, right: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Linefold',
          key: const ValueKey('window-app-title'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DesktopTypography.emphasizedBody.copyWith(
            color: context.ianvs.text,
          ),
        ),
      ),
    ),
  );
}
