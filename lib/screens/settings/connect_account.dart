import 'dart:async';

import 'package:flutter/material.dart';

import 'package:checkpoint/l10n/l10n.dart';
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
          title: context.l10n.connectService('Nintendo'),
          hint: context.l10n.nintendoIdHint,
          validate: (text) => text.isEmpty ? context.l10n.nintendoIdRequired : null,
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
          title: editing ? context.l10n.changeServiceUsername(label) : context.l10n.connectService(label),
          hint: context.l10n.serviceUsernameHint(label),
          initial: editing ? store.accountNames[service] : null,
          confirmLabel: editing ? context.l10n.save : context.l10n.connect,
          prefix: isHandle ? '@' : null,
          validate: (text) {
            if (text.isEmpty) return context.l10n.serviceUsernameHint(label);
            if (cleanAccountName(service, text) == null) {
              return context.l10n.serviceUsernameInvalid(label);
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
      title: Text(context.l10n.disconnectServiceTitle(service.label)),
      content: Text(
        service == ConnectedService.steam
            ? context.l10n.disconnectSteamBody
            : context.l10n.disconnectServiceBody,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(context.l10n.disconnect),
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
      title: Text(context.l10n.connectService('Steam')),
      content: Row(
        children: [
          const SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(context.l10n.connectSteamBody),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.onCancel();
            Navigator.pop(context);
          },
          child: Text(context.l10n.cancel),
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
    this.confirmLabel,
  });

  final String title;
  final String hint;
  final String? initial;
  final String? prefix;
  final String? Function(String text) validate;
  final String? Function(String text)? clean;
  final String? confirmLabel;

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
          child: Text(context.l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel ?? context.l10n.connect)),
      ],
    );
  }
}
