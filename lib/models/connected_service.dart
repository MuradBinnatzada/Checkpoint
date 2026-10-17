import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Where a [ConnectedService] is listed on a profile.
enum ServiceGroup {
  /// Places that hold the member's games.
  game('Game profiles'),

  /// Places to find the member as a person.
  social('Social media');

  const ServiceGroup(this.label);
  final String label;
}

/// Services the user can connect, each with its brand icon and color.
enum ConnectedService {
  steam('Steam', FontAwesomeIcons.steam, Color(0xFF66C0F4), ServiceGroup.game),
  psn('PSN', FontAwesomeIcons.playstation, Color(0xFF00439C), ServiceGroup.game),
  xbox('Xbox', FontAwesomeIcons.xbox, Color(0xFF107C10), ServiceGroup.game),
  nintendo('Nintendo', FontAwesomeIcons.gamepad, Color(0xFFE60012), ServiceGroup.game),
  discord('Discord', FontAwesomeIcons.discord, Color(0xFF5865F2), ServiceGroup.social),
  instagram('Instagram', FontAwesomeIcons.instagram, Color(0xFFE4405F), ServiceGroup.social),
  twitch('Twitch', FontAwesomeIcons.twitch, Color(0xFF9146FF), ServiceGroup.social);

  const ConnectedService(this.label, this.icon, this.color, this.group);
  final String label;
  final dynamic icon;
  final Color color;
  final ServiceGroup group;

  /// Whether the member gives a name when connecting it. Steam has its own ID
  /// (saved on the profile) and Nintendo has nothing to save.
  bool get hasAccountName => this != steam && this != nintendo;
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

/// Longest account name the server stores (`profiles_account_names_length`). Real
/// ones are much shorter.
const accountNameMaxLength = 64;

/// What Instagram and Twitch allow in a username. Checked before a name is saved
/// and again before it becomes part of a link, because other members' names come
/// from their own app and a link must never leave the profile page it points to.
final _instagramName = RegExp(r'^[A-Za-z0-9._]{1,30}$');
final _twitchName = RegExp(r'^[A-Za-z0-9_]{1,25}$');

/// [input] as the name to save for [service]: trimmed, and for Instagram and
/// Twitch without a leading "@". Null when it is empty or not a name that
/// [service] allows.
String? cleanAccountName(ConnectedService service, String input) {
  var text = input.trim();
  final isHandle = service == ConnectedService.instagram || service == ConnectedService.twitch;
  if (isHandle) text = text.replaceFirst(RegExp(r'^@+'), '');
  if (text.isEmpty || text.length > accountNameMaxLength) return null;
  return switch (service) {
    ConnectedService.instagram => _instagramName.hasMatch(text) ? text : null,
    ConnectedService.twitch => _twitchName.hasMatch(text) ? text : null,
    _ => text,
  };
}

/// Which services a member has connected and the account names behind PSN, Xbox,
/// Discord, Instagram and Twitch: what the app mirrors to the member's `profiles`
/// row so that other members see the accounts and can open them. Steam is not
/// here: it follows from the Steam ID.
@immutable
class ConnectedAccounts {
  const ConnectedAccounts({
    this.services = const {},
    this.psnId,
    this.xboxId,
    this.discordId,
    this.instagramId,
    this.twitchId,
  });

  final Set<ConnectedService> services;
  final String? psnId;
  final String? xboxId;
  final String? discordId;
  final String? instagramId;
  final String? twitchId;

  /// The name for [service], if it has one.
  String? nameOf(ConnectedService service) => switch (service) {
    ConnectedService.psn => psnId,
    ConnectedService.xbox => xboxId,
    ConnectedService.discord => discordId,
    ConnectedService.instagram => instagramId,
    ConnectedService.twitch => twitchId,
    ConnectedService.steam || ConnectedService.nintendo => null,
  };

  @override
  bool operator ==(Object other) =>
      other is ConnectedAccounts &&
      setEquals(other.services, services) &&
      other.psnId == psnId &&
      other.xboxId == xboxId &&
      other.discordId == discordId &&
      other.instagramId == instagramId &&
      other.twitchId == twitchId;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(services),
    psnId,
    xboxId,
    discordId,
    instagramId,
    twitchId,
  );
}
