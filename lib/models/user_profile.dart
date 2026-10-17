import 'package:flutter/foundation.dart';

@immutable
class UserProfile {
  const UserProfile({
    required this.name,
    required this.handle,
    this.bio,
    this.avatarUrl,
    this.steamId,
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
        joined: joined,
        followers: followers,
        following: following,
      );
}