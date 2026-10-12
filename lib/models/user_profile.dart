import 'package:flutter/foundation.dart';

@immutable
class UserProfile {
  const UserProfile({
    required this.name,
    required this.handle,
    this.bio,
    this.avatarUrl,
    required this.joined,
    this.followers = 248,
    this.following = 120,
  });

  final String name;
  final String handle;
  final String? bio;
  final String? avatarUrl;
  final DateTime joined;
  final int followers; // mock
  final int following; // mock base; the store adds people followed in Search

  UserProfile copyWith({
    String? name,
    String? handle,
    String? bio,
    String? avatarUrl,
  }) => 
      UserProfile(
        name: name ?? this.name,
        handle: handle ?? this.handle,
        bio: bio ?? this.bio,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        joined: joined,
        followers: followers,
        following: following,
      );
}