import '../app_localizations.dart';
import 'package:flutter/material.dart';
import '../services/cloud_conflict_service.dart';
import 'save_conflict_diff_dialog.dart';

/// Nothing is written from this review route. Its result is the explicit choice
/// applied by the shell after checking the document and workspace are unchanged.
class CloudConflictDialog extends StatefulWidget {
  const CloudConflictDialog({
    super.key,
    required this.review,
    required this.local,
  });
  final CloudConflictReview review;
  final String local;
  @override
  State<CloudConflictDialog> createState() => _CloudConflictDialogState();
}

class _CloudConflictDialogState extends State<CloudConflictDialog> {
  String? selected;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(appText(context, "解决 iCloud 冲突")),
    scrollable: true,
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appText(
              context,
              "选择要作为当前文档的版本。其他不同内容会先保存为同目录下的 conflict 副本，成功后才将这些云端版本标记为已解决。",
            ),
          ),
          const SizedBox(height: 12),
          for (final version in widget.review.versions)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                selected == version.id
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              title: Text(version.name),
              onTap: () => setState(() => selected = version.id),
              trailing: TextButton(
                child: Text(appText(context, "比较")),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => SaveConflictDiffDialog(
                    disk: version.contents,
                    local: widget.local,
                  ),
                ),
              ),
            ),
          TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => SaveConflictDiffDialog(
                disk: widget.review.current,
                local: widget.local,
              ),
            ),
            child: Text(appText(context, "比较磁盘与当前编辑")),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(appText(context, "取消")),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, 'keepAll'),
        child: Text(appText(context, "全部保留")),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, 'local'),
        child: Text(appText(context, "使用当前编辑")),
      ),
      FilledButton(
        onPressed: selected == null
            ? null
            : () => Navigator.pop(context, selected),
        child: Text(appText(context, "使用所选云端版本")),
      ),
    ],
  );
}
