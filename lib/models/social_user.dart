import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Another Checkpoint member, as listed in search and in follower lists.
/// [gamesLogged], [followers] and [startsFollowed] are read for the Users tab
/// only; the other lists leave them at 0 / false.
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

  /// Whether the signed-in member followed them when the list was read.
  final bool startsFollowed;

  /// Public URL of the member's photo; null shows their initials.
  final String? avatarUrl;

  /// [followers] with the signed-in member's own follow or unfollow since the
  /// list was read applied, so the count moves as soon as the button does.
  /// [viewerFollows] is the signed-in member's follow state now.
  int followersFor({required bool viewerFollows}) {
    final delta = (viewerFollows ? 1 : 0) - (startsFollowed ? 1 : 0);
    return math.max(0, followers + delta);
  }
}
