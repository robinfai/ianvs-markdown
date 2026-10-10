import 'dart:io';

import 'package:flutter/widgets.dart';

import 'src/app.dart';
import 'src/preview/preview_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(Platform.isIOS ? const LinefoldPreviewApp() : const LinefoldApp());
}
