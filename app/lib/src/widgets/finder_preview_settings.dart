import '../app_localizations.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const finderPreviewChannel = MethodChannel(
  'work.ianvs.linefold/file_association',
);

Future<void> offerFinderPreviewSetup(BuildContext context) async {
  if (!Platform.isMacOS) return;
  try {
    final state = await finderPreviewChannel.invokeMapMethod<String, dynamic>(
      'getFinderPreviewState',
    );
    if (!context.mounted || state?['needsSetup'] != true) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appText(context, "Preview Markdown in Finder")),
        content: const SizedBox(
          width: 440,
          child: SingleChildScrollView(child: FinderPreviewSettings()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(appText(context, "Done / Set Up Later")),
          ),
        ],
      ),
    );
    await finderPreviewChannel.invokeMethod<void>('dismissFinderPreviewSetup');
  } on MissingPluginException {
    // Other platforms and older native hosts do not expose this integration.
  } on PlatformException {
    // Settings retains a retryable entry if the native check fails.
  }
}

class FinderPreviewSettings extends StatefulWidget {
  const FinderPreviewSettings({super.key});

  @override
  State<FinderPreviewSettings> createState() => _FinderPreviewSettingsState();
}

class _FinderPreviewSettingsState extends State<FinderPreviewSettings>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _state;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final state = await finderPreviewChannel
          .invokeMapMethod<String, dynamic>('getFinderPreviewState')
          .timeout(const Duration(seconds: 5));
      if (state == null) {
        throw MissingPluginException(
          'Preview setup is not available in this host.',
        );
      }
      if (mounted) {
        setState(() {
          _state = state;
          _error = null;
        });
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Unable to check the preview installation. Try again.',
        );
      }
    }
  }

  Future<void> _perform(String method) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await finderPreviewChannel.invokeMethod<void>(method);
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'Unable to open preview settings. Open System Settings → General → Login Items & Extensions → Quick Look.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final installed = _state?['installed'] == true;
    final bundled = _state?['bundled'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          appText(context, "Finder preview"),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (_state == null && _error == null) const LinearProgressIndicator(),
        if (_state != null)
          Text(
            !installed
                ? appText(
                    context,
                    "Move Linefold from the DMG to Applications, then open that copy to finish setup.",
                  )
                : !bundled
                ? appText(
                    context,
                    "The preview extension is missing. Reinstall Linefold from the official DMG.",
                  )
                : appText(
                    context,
                    "Preview extension installed. Its on/off switch is managed by macOS.",
                  ),
          ),
        const SizedBox(height: 8),
        Text(
          appText(
            context,
            "Enable or disable Linefold under Quick Look in System Settings. On macOS 15 or later: General → Login Items & Extensions → Quick Look (or By App → Linefold). On older versions, search for Extensions → Quick Look.",
          ),
        ),
        const SizedBox(height: 8),
        Text(
          appText(
            context,
            "If macOS asks to open Linefold or allow LinefoldQuickLook to access data from an earlier version, approve the system dialog to continue. If you decline, you can return here later. No Terminal commands are needed.",
          ),
        ),
        const SizedBox(height: 8),
        Text(
          appText(
            context,
            "After changing the switch, close any existing preview and reopen it. This does not change the default app for opening .md files.",
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              key: const ValueKey('manage-finder-preview'),
              onPressed: _busy
                  ? null
                  : () => _perform('openFinderPreviewSettings'),
              child: Text(appText(context, "Enable / Disable in macOS…")),
            ),
            TextButton(
              onPressed: _busy ? null : _refresh,
              child: Text(appText(context, "Check Again")),
            ),
          ],
        ),
        if (_error != null)
          Text(
            appText(context, _error!),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}
