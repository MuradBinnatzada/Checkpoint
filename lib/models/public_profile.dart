import 'package:flutter/foundation.dart';

import 'package:checkpoint/models/connected_service.dart';

/// Another member's profile header: what `public_profiles` exposes. No email, bio
/// or Steam ID; [steamConnected] only says that a Steam account is linked. The
/// same goes for the other services: [services] names them, and the account names
/// behind PSN, Xbox and Discord stay on the owner's device.
@immutable
class PublicProfile {
  const PublicProfile({
    required this.id,
    required this.name,
    required this.handle,
    this.avatarUrl,
    this.steamConnected = false,
    this.services = const {},
  });

  final String id;
  final String name;

  /// With the leading "@".
  final String handle;
  final String? avatarUrl;
  final bool steamConnected;

  /// The connected services besides Steam (`profiles.connected_services`).
  final Set<ConnectedService> services;

  /// Every service the member has connected, Steam (derived from [steamConnected])
  /// included.
  Set<ConnectedService> get connectedServices => {
    if (steamConnected) ConnectedService.steam,
    ...services.where((s) => s != ConnectedService.steam),
  };
}

/// The numbers of a profile page, from one request (`public_profile_stats`).
@immutable
class PublicProfileStats {
  const PublicProfileStats({
    required this.followers,
    required this.following,
    required this.viewerFollows,
    required this.games,
  });

  final int followers;
  final int following;

  /// Whether the signed-in member followed this one when the numbers were read.
  final bool viewerFollows;

  /// Games in their library.
  final int games;
}
