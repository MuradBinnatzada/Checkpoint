import 'package:flutter/foundation.dart';

@immutable
class UserProfile {
  const UserProfile({
    required this.name,
    required this.handle,
    required this.bio,
    required this.joined,
    required this.weeklyGoalHours,
    this.followers = 248,
    this.following = 120,
  });

  final String name;
  final String handle;
  final String bio;
  final DateTime joined;
  final double weeklyGoalHours;
  final int followers; // mock
  final int following; // mock base; the store adds people followed in Search

  UserProfile copyWith({double? weeklyGoalHours}) => UserProfile(
        name: name,
        handle: handle,
        bio: bio,
        joined: joined,
        weeklyGoalHours: weeklyGoalHours ?? this.weeklyGoalHours,
        followers: followers,
        following: following,
      );
}
