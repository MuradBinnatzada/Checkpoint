import 'package:flutter/foundation.dart';

import 'package:checkpoint/models/connected_service.dart';

@immutable
class UserProfile {
  const UserProfile({
    required this.name,
    required this.handle,
    this.bio,
    this.avatarUrl,
    this.steamId,
    this.connectedServices = const {},
    this.psnId,
    this.xboxId,
    this.discordId,
    this.instagramId,
    this.twitchId,
    required this.joined,
    this.followers = 248,
    this.following = 120,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        name: json['name'] as String,
        handle: json['handle'] as String,
        bio: json['bio'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
        steamId: json['steamId'] as String?,
        connectedServices: connectedServicesFromDb(json['connectedServices']),
        psnId: json['psnId'] as String?,
        xboxId: json['xboxId'] as String?,
        discordId: json['discordId'] as String?,
        instagramId: json['instagramId'] as String?,
        twitchId: json['twitchId'] as String?,
        joined: DateTime.parse(json['joined'] as String).toLocal(),
        followers: (json['followers'] as num).toInt(),
        following: (json['following'] as num).toInt(),
      );

  final String name;
  final String handle;
  final String? bio;
  final String? avatarUrl;

  /// Steam ID64 from `profiles.steam_id`. Only ever populated for the signed-in
  /// user's own profile; it is never read for other members.
  final String? steamId;

  /// The services besides Steam that `profiles.connected_services` says are
  /// connected: the list other members see. The PSN / Xbox / Discord names behind
  /// them are not on the server.
  final Set<ConnectedService> connectedServices;

  /// The account names the server has for PSN, Xbox, Discord, Instagram and
  /// Twitch (`profiles.psn_id` and so on): what other members' links open.
  final String? psnId;
  final String? xboxId;
  final String? discordId;
  final String? instagramId;
  final String? twitchId;
  final DateTime joined;
  final int followers; // mock
  final int following; // mock base; the store adds people followed in Search

  /// What the offline cache keeps of the signed-in user's profile; read back by
  /// [UserProfile.fromJson].
  Map<String, dynamic> toJson() => {
        'name': name,
        'handle': handle,
        'bio': bio,
        'avatarUrl': avatarUrl,
        'steamId': steamId,
        'connectedServices': connectedServicesToDb(connectedServices),
        'psnId': psnId,
        'xboxId': xboxId,
        'discordId': discordId,
        'instagramId': instagramId,
        'twitchId': twitchId,
        'joined': joined.toUtc().toIso8601String(),
        'followers': followers,
        'following': following,
      };

  UserProfile copyWith({
    String? name,
    String? handle,
    String? bio,
    String? avatarUrl,
    String? steamId,
    // copyWith can't tell "leave it" from "set to null", so clearing is explicit.
    bool clearSteamId = false,
  }) =>
      UserProfile(
        name: name ?? this.name,
        handle: handle ?? this.handle,
        bio: bio ?? this.bio,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        steamId: clearSteamId ? null : (steamId ?? this.steamId),
        connectedServices: connectedServices,
        psnId: psnId,
        xboxId: xboxId,
        discordId: discordId,
        instagramId: instagramId,
        twitchId: twitchId,
        joined: joined,
        followers: followers,
        following: following,
      );
}