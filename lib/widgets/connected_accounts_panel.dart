import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:checkpoint/models/connected_service.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/widgets/panel.dart';
import 'package:checkpoint/widgets/service_link.dart';

/// What the buttons of the box do.
class AccountEditor {
  const AccountEditor({
    required this.onConnect,
    required this.onEdit,
    required this.onDisconnect,
  });

  final void Function(ConnectedService service) onConnect;

  /// Change the name of a connected service.
  final void Function(ConnectedService service) onEdit;
  final void Function(ConnectedService service) onDisconnect;
}

/// The "Connect accounts" box of Settings: Game profiles (Steam, PSN, Xbox,
/// Nintendo) and Social media (Discord, Instagram, Twitch), one row each. A service
/// that is not connected has Connect; one that is has a menu to rename or
/// disconnect it, and tapping its row opens the account (Discord copies the
/// username). [gameFooter] goes under the game profiles, where the library sync
/// lives.
class ConnectedAccountsPanel extends StatelessWidget {
  const ConnectedAccountsPanel({
    super.key,
    required this.services,
    required this.names,
    required this.editor,
    this.gameFooter,
  });

  /// Every connected service, Steam included.
  final Set<ConnectedService> services;

  /// The Steam ID and the PSN, Xbox, Discord, Instagram and Twitch names the
  /// member gave. A connected service may have none yet.
  final Map<ConnectedService, String> names;

  final AccountEditor editor;
  final Widget? gameFooter;

  @override
  Widget build(BuildContext context) {
    final groups = <Widget>[];
    for (final group in ServiceGroup.values) {
      groups.add(
        _Group(
          label: group.label,
          footer: group == ServiceGroup.game ? gameFooter : null,
          children: [
            for (final s in ConnectedService.values)
              if (s.group == group)
                _AccountRow(
                  service: s,
                  connected: services.contains(s),
                  name: names[s],
                  editor: editor,
                ),
          ],
        ),
      );
    }
    return Panel(
      title: 'Connect accounts',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < groups.length; i++) ...[
            if (i > 0) const SizedBox(height: 18),
            groups[i],
          ],
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.label, required this.children, this.footer});

  final String label;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: Palette.muted,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
          children[i],
        ],
        if (footer != null) ...[const SizedBox(height: 12), footer!],
      ],
    );
  }
}

enum _MenuAction { edit, disconnect }

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.service,
    required this.connected,
    required this.name,
    required this.editor,
  });

  final ConnectedService service;
  final bool connected;
  final String? name;
  final AccountEditor editor;

  /// What the row says under the service: the name, "Connected" while it has none,
  /// or "Not connected".
  String get _subtitle {
    if (!connected) return 'Not connected';
    final text = name;
    if (text == null || text.isEmpty) return 'Connected';
    return service == ConnectedService.instagram ? '@$text' : text;
  }

  @override
  Widget build(BuildContext context) {
    final link = connected ? serviceLink(service, name) : null;

    final Widget trailing;
    if (!connected) {
      trailing = TextButton(
        onPressed: () => editor.onConnect(service),
        child: const Text('Connect'),
      );
    } else {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (link != null)
            Icon(
              link.copyText != null
                  ? Icons.content_copy_rounded
                  : Icons.open_in_new_rounded,
              size: 18,
              color: Palette.muted,
            ),
          PopupMenuButton<_MenuAction>(
            tooltip: '${service.label} options',
            icon: const Icon(Icons.more_vert_rounded, color: Palette.muted),
            onSelected: (action) => switch (action) {
              _MenuAction.edit => editor.onEdit(service),
              _MenuAction.disconnect => editor.onDisconnect(service),
            },
            itemBuilder: (_) => [
              // Nintendo has no name. Steam's ID is proved by signing in, not
              // typed: another account is Disconnect, then Connect.
              if (service != ConnectedService.nintendo &&
                  service != ConnectedService.steam)
                const PopupMenuItem(
                  value: _MenuAction.edit,
                  child: Text('Change username'),
                ),
              const PopupMenuItem(
                value: _MenuAction.disconnect,
                child: Text('Disconnect'),
              ),
            ],
          ),
        ],
      );
    }

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: service.color.withValues(alpha: connected ? 0.16 : 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: FaIcon(
              service.icon,
              size: 18,
              color: connected ? service.color : Palette.muted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.label,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: connected && (name?.isNotEmpty ?? false)
                        ? Colors.white70
                        : Palette.muted,
                  ),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );

    if (link == null) return row;
    return Tooltip(
      message: link.tooltip,
      // Transparent Material so the InkWell ripple still has somewhere to paint.
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => openServiceLink(context, service, link),
          child: row,
        ),
      ),
    );
  }
}
