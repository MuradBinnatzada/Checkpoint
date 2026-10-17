import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Services the user can connect, each with its brand icon and color.
enum ConnectedService {
  steam('Steam', FontAwesomeIcons.steam, Color(0xFF66C0F4), true),
  discord('Discord', FontAwesomeIcons.discord, Color(0xFF5865F2), true),
  psn('PSN', FontAwesomeIcons.playstation, Color(0xFF00439C), false),
  xbox('Xbox', FontAwesomeIcons.xbox, Color(0xFF107C10), false),
  nintendo('Nintendo', FontAwesomeIcons.gamepad, Color(0xFFE60012), false);

  const ConnectedService(this.label, this.icon, this.color, this.supportsSync);
  final String label;
  final dynamic icon;
  final Color color;
  final bool supportsSync;
}

/// Names for `profiles.connected_services`, the services other members can see
/// are connected. Steam is left out: it is connected exactly when the profile has
/// a Steam ID, so it never has a name of its own in that list. Sorted, so the same
/// set always saves the same list.
List<String> connectedServicesToDb(Iterable<ConnectedService> services) => [
  for (final s in ConnectedService.values)
    if (s != ConnectedService.steam && services.contains(s)) s.name,
]..sort();

/// The services named in a `connected_services` value. A name this build doesn't
/// know (a newer app wrote it) and Steam are skipped rather than failing the read.
Set<ConnectedService> connectedServicesFromDb(Object? value) => {
  if (value is List)
    for (final s in ConnectedService.values)
      if (s != ConnectedService.steam && value.contains(s.name)) s,
};
