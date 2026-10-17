import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode, launchUrl;

import 'package:checkpoint/models/connected_service.dart';

/// The icons of the services a member connected, small and in their brand color,
/// the same on your own profile and on anyone else's. Tapping one opens the
/// account once its name is known: Steam, Xbox and PSN open their profile page,
/// Discord has no public profile URL so it copies the username to the clipboard.
/// Nintendo has nothing to open.
class ConnectedServiceBadges extends StatelessWidget {
  const ConnectedServiceBadges({
    super.key,
    required this.services,
    this.steamId,
    this.psnId,
    this.xboxId,
    this.discordId,
  });

  /// Every connected service, Steam included.
  final Set<ConnectedService> services;

  /// Steam ID64, PSN id, Xbox gamertag and Discord username.
  final String? steamId;
  final String? psnId;
  final String? xboxId;
  final String? discordId;

  static bool _has(String? text) => text != null && text.trim().isNotEmpty;

  Future<bool> _open(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);

  /// Where tapping [service]'s badge leads, once its name is saved.
  ({String tooltip, VoidCallback onTap})? _link(
    BuildContext context,
    ConnectedService service,
  ) {
    switch (service) {
      case ConnectedService.steam:
        final id = steamId;
        if (!_has(id)) return null;
        return (
          tooltip: 'Open Steam profile',
          onTap: () => _open(Uri.https('steamcommunity.com', '/profiles/$id')),
        );
      case ConnectedService.xbox:
        final id = xboxId;
        if (!_has(id)) return null;
        return (
          tooltip: 'Open Xbox profile',
          onTap: () => _open(Uri.https('xboxgamertag.com', '/search/$id')),
        );
      case ConnectedService.psn:
        final id = psnId;
        if (!_has(id)) return null;
        return (
          tooltip: 'Open PSN profile',
          onTap: () => _open(Uri.https('psnprofiles.com', '/$id')),
        );
      case ConnectedService.discord:
        final id = discordId;
        if (!_has(id)) return null;
        return (
          tooltip: 'Copy Discord username',
          onTap: () async {
            final messenger = ScaffoldMessenger.of(context);
            await Clipboard.setData(ClipboardData(text: id!));
            messenger
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(
                  content: Text('Discord username copied to clipboard'),
                ),
              );
          },
        );
      case ConnectedService.nintendo:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 8,
      children: [
        // ConnectedService.values keeps the order stable.
        for (final s in ConnectedService.values)
          if (services.contains(s))
            _ServiceBadge(
              service: s,
              tooltip: _link(context, s)?.tooltip,
              onTap: _link(context, s)?.onTap,
            ),
      ],
    );
  }
}

/// Small, subtle icon badge for a connected service. Tappable only when [onTap]
/// is provided.
class _ServiceBadge extends StatelessWidget {
  const _ServiceBadge({required this.service, this.onTap, this.tooltip});
  final ConnectedService service;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? service.label,
      // Transparent Material so the InkWell ripple still has somewhere to paint,
      // without drawing a background or border behind the icon.
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.only(right: 6, top: 4, bottom: 4),
            child: FaIcon(service.icon, size: 20, color: service.color),
          ),
        ),
      ),
    );
  }
}
