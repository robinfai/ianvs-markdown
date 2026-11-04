import 'package:flutter/widgets.dart';

import 'src/app.dart';
import 'package:ianvs_markdown/ianvs_markdown_diagnostics.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    scrollFrameProbeEnabled
        ? const ScrollFrameProbe(host: 'app', child: LinefoldApp())
        : const LinefoldApp(),
  );
}
