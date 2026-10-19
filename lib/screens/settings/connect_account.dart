import 'dart:async';

import 'package:flutter/material.dart';

import 'package:checkpoint/models/connected_service.dart';
import 'package:checkpoint/state/profile_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/widgets/connected_accounts_panel.dart';

/// What the buttons of the Connect accounts box in Settings do: sign in through
/// Steam, or ask for the name of another service and save it, change it, or
/// disconnect the service.
AccountEditor accountEditorFor(BuildContext context) => AccountEditor(
  onConnect: (service) => connectService(context, service),
  onEdit: (service) => connectService(context, service, editing: true),
  onDisconnect: (service) => disconnectService(context, service),
);

/// Asks for what [service] needs, then connects it (or, with [editing], changes
/// the name it already has).
Future<void> connectService(
  BuildContext context,
  ConnectedService service, {
  bool editing = false,
}) async {
  final store = context.read<ProfileStore>();
  final messenger = ScaffoldMessenger.of(context);

  switch (service) {
    case ConnectedService.steam:
      // Proved by signing in through Steam, never typed in: the server saves
      // the Steam ID Steam confirms, and Steam shows as connected by itself once
      // the profile has it. A dialog waits for the sign-in and can call it off.
      final linking = store.connectSteam();
      final message = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _SteamLinkDialog(
          linking: linking,
          onCancel: store.cancelSteamLink,
        ),
      );
      if (message != null) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
    case ConnectedService.nintendo:
      final id = await showDialog<String>(
        context: context,
        builder: (_) => _TextDialog(
          title: 'Connect Nintendo',
          hint: 'Enter your Nintendo Gamertag/ID',
          validate: (text) => text.isEmpty ? 'Enter your Nintendo ID' : null,
        ),
      );
      // Nintendo has nothing to open, so only the fact that it is connected is kept.
      if (id != null && !store.isConnected(service)) {
        store.toggleService(service);
      }
    case ConnectedService.psn ||
        ConnectedService.xbox ||
        ConnectedService.discord ||
        ConnectedService.instagram ||
        ConnectedService.twitch:
      final label = service.label;
      final isHandle =
          service == ConnectedService.instagram ||
          service == ConnectedService.twitch;
      final name = await showDialog<String>(
        context: context,
        builder: (_) => _TextDialog(
          title: editing ? 'Change $label username' : 'Connect $label',
          hint: 'Enter your $label username',
          initial: editing ? store.accountNames[service] : null,
          confirmLabel: editing ? 'Save' : 'Connect',
          prefix: isHandle ? '@' : null,
          validate: (text) {
            if (text.isEmpty) return 'Enter your $label username';
            if (cleanAccountName(service, text) == null) {
              return "That isn't a valid $label username";
            }
            return null;
          },
          clean: (text) => cleanAccountName(service, text),
        ),
      );
      if (name != null) store.setServiceId(service, name);
  }
}

/// Disconnects [service] after a confirmation.
Future<void> disconnectService(
  BuildContext context,
  ConnectedService service,
) async {
  final store = context.read<ProfileStore>();
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Disconnect ${service.label}?'),
      content: Text(
        service == ConnectedService.steam
            ? 'Your Steam ID is removed and library sync stops. Games already in '
                  'your library stay.'
            : "It's removed from your profile. You can connect it again any time.",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Disconnect'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  if (service == ConnectedService.steam) {
    final error = await store.disconnectSteam();
    if (error != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
    }
    return;
  }
  if (store.isConnected(service)) store.toggleService(service);
}

/// Waits for the Steam sign-in [linking] (ProfileStore.connectSteam) and pops
/// with what it says. Cancel stops waiting and pops with nothing.
class _SteamLinkDialog extends StatefulWidget {
  const _SteamLinkDialog({required this.linking, required this.onCancel});

  final Future<String?> linking;
  final VoidCallback onCancel;

  @override
  State<_SteamLinkDialog> createState() => _SteamLinkDialogState();
}

class _SteamLinkDialogState extends State<_SteamLinkDialog> {
  @override
  void initState() {
    super.initState();
    unawaited(
      widget.linking.then((message) {
        if (mounted) Navigator.pop(context, message);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connect Steam'),
      content: const Row(
        children: [
          SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Text(
              "Sign in on Steam's page to show the account is yours. "
              'Checkpoint gets your Steam ID from Steam, never your password.',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.onCancel();
            Navigator.pop(context);
          },
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// One text field in a dialog. Pops with the text (passed through [clean] when
/// given), or nothing if cancelled; [validate] returns what to say about text that
/// can't be accepted.
class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.hint,
    required this.validate,
    this.initial,
    this.prefix,
    this.clean,
    this.confirmLabel = 'Connect',
  });

  final String title;
  final String hint;
  final String? initial;
  final String? prefix;
  final String? Function(String text) validate;
  final String? Function(String text)? clean;
  final String confirmLabel;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    final error = widget.validate(text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, widget.clean?.call(text) ?? text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: InputDecoration(
          hintText: widget.hint,
          errorText: _error,
          prefixText: widget.prefix,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
