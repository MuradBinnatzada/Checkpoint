import 'package:flutter/material.dart';

import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/screens/settings/danger_panel.dart';
import 'package:checkpoint/state/library_store.dart';
import 'package:checkpoint/state/store_scope.dart';

/// "Clear library": what it removes, and the button that asks before doing it.
/// Sits above Delete account in Settings > Account, e.g. for someone who
/// imported their Steam library and wants to start over with another account.
class ClearLibraryPanel extends StatefulWidget {
  const ClearLibraryPanel({super.key});

  @override
  State<ClearLibraryPanel> createState() => _ClearLibraryPanelState();
}

class _ClearLibraryPanelState extends State<ClearLibraryPanel> {
  bool _clearing = false;

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.clearLibraryTitle),
        content: Text(context.l10n.clearLibraryBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: DangerPanel.colorOf(context)),
            child: Text(context.l10n.clearLibrary),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _clear();
  }

  Future<void> _clear() async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);
    final cleared = context.l10n.libraryCleared;

    setState(() => _clearing = true);
    final error = await library.clearLibrary();
    if (mounted) setState(() => _clearing = false);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(error ?? cleared)),
      );
  }

  @override
  Widget build(BuildContext context) {
    final syncing = context.watch<LibraryStore>().isSyncing;
    return DangerPanel(
      title: context.l10n.clearLibrary,
      description: context.l10n.clearLibraryDescription,
      buttonLabel: context.l10n.clearLibrary,
      icon: Icons.layers_clear_rounded,
      busy: _clearing,
      // A sync is running; clearing waits for it, but only Sync shows progress.
      disabled: syncing,
      onPressed: _confirmClear,
    );
  }
}
