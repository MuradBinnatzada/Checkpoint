import 'package:flutter/foundation.dart';

/// Another Checkpoint member, as listed in search and in follower lists.
/// [gamesLogged] and [followers] are placeholders: those lists don't load them.
@immutable
class SocialUser {
  const SocialUser({
    required this.id,
    required this.name,
    required this.handle,
    required this.gamesLogged,
    required this.followers,
    this.startsFollowed = false,
    this.avatarUrl,
  });
  final String id;
  final String name;
  final String handle;
  final int gamesLogged;
  final int followers;
  final bool startsFollowed;

  /// Public URL of the member's photo; null shows their initials.
  final String? avatarUrl;
}
