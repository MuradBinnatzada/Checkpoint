import 'package:flutter/material.dart';

import 'package:checkpoint/screens/settings/danger_panel.dart';
import 'package:checkpoint/state/profile_store.dart';
import 'package:checkpoint/state/store_scope.dart';

/// "Delete account": what it removes, and the button that asks before doing it.
/// Lives at the bottom of Settings > Account.
class DeleteAccountPanel extends StatefulWidget {
  const DeleteAccountPanel({super.key, required this.onDeletingChanged});

  /// Called with true when the deletion starts and with false if it did not
  /// work. (When it works the screen is left, so there is nothing to say.)
  final ValueChanged<bool> onDeletingChanged;

  @override
  State<DeleteAccountPanel> createState() => _DeleteAccountPanelState();
}

class _DeleteAccountPanelState extends State<DeleteAccountPanel> {
  bool _deleting = false;

  Future<void> _confirmDelete() async {
    if (_deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'This permanently deletes your profile, library, play logs, follows '
          'and photo, and removes your sign-in. It can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: DangerPanel.colorOf(context)),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _deleteAccount();
  }

  Future<void> _deleteAccount() async {
    FocusScope.of(context).unfocus();
    final store = context.read<ProfileStore>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _deleting = true);
    widget.onDeletingChanged(true);
    final error = await store.deleteAccount();
    if (!mounted) return;

    if (error == null) {
      // Signed out now: leave every screen that was opened from the signed-in app.
      navigator.popUntil((route) => route.isFirst);
    } else {
      setState(() => _deleting = false);
      widget.onDeletingChanged(false);
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(error ?? 'Your account was deleted')),
      );
  }

  @override
  Widget build(BuildContext context) {
    return DangerPanel(
      title: 'Delete account',
      description:
          'Permanently deletes your profile, library, play logs, follows and '
          'photo, and removes your sign-in. This can\'t be undone.',
      buttonLabel: 'Delete account',
      icon: Icons.delete_forever_rounded,
      busy: _deleting,
      onPressed: _confirmDelete,
    );
  }
}
