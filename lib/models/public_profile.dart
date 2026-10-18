import 'package:flutter/foundation.dart';

import 'package:checkpoint/models/connected_service.dart';

/// Another member's profile header: what `public_profiles` exposes to signed-in
/// members. That is the name, handle, photo, bio, which services they linked and
/// the account names behind them (what makes the service icons tappable). Never
/// the email.
@immutable
class PublicProfile {
  const PublicProfile({
    required this.id,
    required this.name,
    required this.handle,
    this.avatarUrl,
    this.steamConnected = false,
    this.showSteamAchievements = true,
    this.services = const {},
    this.bio,
    this.steamId,
    this.psnId,
    this.xboxId,
    this.discordId,
    this.instagramId,
    this.twitchId,
    this.joined,
  });

  final String id;
  final String name;

  /// With the leading "@".
  final String handle;
  final String? avatarUrl;
  final bool steamConnected;

  /// Whether they let other members see their Steam achievements
  /// (`show_steam_achievements`, Settings > Privacy). When false the server hands
  /// out none of them, and the profile leaves the Achievements card out.
  final bool showSteamAchievements;

  /// The connected services besides Steam (`profiles.connected_services`).
  final Set<ConnectedService> services;

  /// Null when they wrote none.
  final String? bio;

  /// Steam ID64, PSN id, Xbox gamertag and the Discord, Instagram and Twitch
  /// usernames, as the member entered them. Null when not given (a service can be
  /// connected without a name, until the member's app has uploaded it).
  final String? steamId;
  final String? psnId;
  final String? xboxId;
  final String? discordId;
  final String? instagramId;
  final String? twitchId;

  /// When they joined.
  final DateTime? joined;

  /// Every service the member has connected, Steam (derived from [steamConnected])
  /// included.
  Set<ConnectedService> get connectedServices => {
    if (steamConnected) ConnectedService.steam,
    ...services.where((s) => s != ConnectedService.steam),
  };

  /// The names behind [connectedServices] that the member gave, for the
  /// Connected accounts box.
  Map<ConnectedService, String> get accountNames => {
    for (final (service, name) in [
      (ConnectedService.steam, steamId),
      (ConnectedService.psn, psnId),
      (ConnectedService.xbox, xboxId),
      (ConnectedService.discord, discordId),
      (ConnectedService.instagram, instagramId),
      (ConnectedService.twitch, twitchId),
    ])
      if (name?.trim() case final text? when text.isNotEmpty) service: text,
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
