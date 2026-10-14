import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_markdown/src/editor/block_identity.dart';

Finder findLiveBlock(int start, String type) => find.byWidgetPredicate(
  (widget) =>
      widget is MarkdownBlockRegion &&
      widget.block.start == start &&
      widget.block.type.name == type,
);
