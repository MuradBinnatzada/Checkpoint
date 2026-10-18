import 'package:flutter/material.dart';

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
        title: const Text('Clear your library?'),
        content: const Text(
          'This removes every game from your library, along with your '
          'ratings, favorites, play logs and achievements. Your profile and '
          'connected accounts stay. It can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: DangerPanel.color),
            child: const Text('Clear library'),
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

    setState(() => _clearing = true);
    final error = await library.clearLibrary();
    if (mounted) setState(() => _clearing = false);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(error ?? 'Your library was cleared')),
      );
  }

  @override
  Widget build(BuildContext context) {
    final syncing = context.watch<LibraryStore>().isSyncing;
    return DangerPanel(
      title: 'Clear library',
      description:
          'Removes every game, rating and play log from your library, e.g. to '
          'start over with another Steam account. Your profile and connected '
          'accounts stay. This can\'t be undone.',
      buttonLabel: 'Clear library',
      icon: Icons.layers_clear_rounded,
      busy: _clearing,
      // A sync is running; clearing waits for it, but only Sync shows progress.
      disabled: syncing,
      onPressed: _confirmClear,
    );
  }
}
