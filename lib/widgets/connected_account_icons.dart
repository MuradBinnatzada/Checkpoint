import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:checkpoint/models/connected_service.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/widgets/service_link.dart';

/// A row of small brand icons, one per connected account: game profiles first,
/// then social media. Each opens the account (Discord copies the username); one
/// with nothing to open yet (no name saved, or Nintendo) is shown but not tappable.
///
/// Empty when nothing is connected.
class ConnectedAccountIcons extends StatelessWidget {
  const ConnectedAccountIcons({
    super.key,
    required this.services,
    required this.names,
  });

  /// Every connected service, Steam included.
  final Set<ConnectedService> services;

  /// The Steam ID and the PSN, Xbox, Discord, Instagram and Twitch names the
  /// member gave. A connected service may have none yet.
  final Map<ConnectedService, String> names;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (final group in ServiceGroup.values) {
      final shown = [
        for (final s in ConnectedService.values)
          if (s.group == group && services.contains(s)) s,
      ];
      if (shown.isEmpty) continue;
      if (items.isNotEmpty) items.add(const _GroupGap());
      for (final s in shown) {
        items.add(_AccountIcon(service: s, name: names[s]));
      }
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: items,
    );
  }
}

/// A hairline between the game profiles and the social media icons.
class _GroupGap extends StatelessWidget {
  const _GroupGap();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      color: context.palette.text.withValues(alpha: 0.14),
    );
  }
}

class _AccountIcon extends StatelessWidget {
  const _AccountIcon({required this.service, required this.name});

  final ConnectedService service;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final link = serviceLink(service, name);
    final tile = Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.palette.legible(service.color).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: FaIcon(service.icon, size: 16, color: context.palette.legible(service.color)),
    );

    if (link == null) {
      return Tooltip(
        message: service.label,
        child: Semantics(label: service.label, child: tile),
      );
    }
    return Tooltip(
      message: link.tooltip,
      child: Semantics(
        button: true,
        label: link.tooltip,
        excludeSemantics: true,
        // Transparent Material so the InkWell ripple still has somewhere to paint.
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => openServiceLink(context, service, link),
            child: tile,
          ),
        ),
      ),
    );
  }
}
