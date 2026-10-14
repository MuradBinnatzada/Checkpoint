import 'package:flutter/foundation.dart';

/// Another Checkpoint member (mock, no backend yet).
@immutable
class SocialUser {
  const SocialUser({
    required this.id,
    required this.name,
    required this.handle,
    required this.gamesLogged,
    required this.followers,
    this.startsFollowed = false,
  });
  final String id;
  final String name;
  final String handle;
  final int gamesLogged;
  final int followers;
  final bool startsFollowed;
}
