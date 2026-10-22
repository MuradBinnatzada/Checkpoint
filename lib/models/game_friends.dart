import 'package:flutter/foundation.dart';

import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/social_user.dart';

/// A member the signed-in one follows who has a game in their library.
@immutable
class FriendWithGame {
  const FriendWithGame({
    required this.member,
    required this.status,
    this.rating = 0,
    this.dateAdded,
    this.review = '',
  });

  final SocialUser member;
  final GameStatus status;

  /// Out of 5, in halves; 0 when they did not rate it.
  final double rating;
  final DateTime? dateAdded;

  /// Their short review; empty when they wrote none.
  final String review;
}

/// The rows of the Friends panel on a game's screen. Dropped is left out: the
/// panel is about who liked, is playing or wants to play the game.
enum FriendGroup {
  completed({GameStatus.completed}),
  playing({GameStatus.playing}),
  wantToPlay({GameStatus.toPlay, GameStatus.wishlist});

  const FriendGroup(this.statuses);
  final Set<GameStatus> statuses;

  String get label => switch (this) {
    completed => L10n.current.friendGroupCompleted,
    playing => L10n.current.friendGroupPlaying,
    wantToPlay => L10n.current.friendGroupWantToPlay,
  };
}

/// Which of the members the signed-in one follows have a game, and how. The
/// server sends a few members per status (see `CheckpointRepository.fetchFriendsWithGame`)
/// with the full count of each, so [countOf] can be more than [membersOf] holds.
@immutable
class GameFriends {
  const GameFriends({this.friends = const [], this.totals = const {}});

  /// Rated first, then the most recently added, within each status.
  final List<FriendWithGame> friends;

  /// How many followed members have each status, all of them.
  final Map<GameStatus, int> totals;

  bool get isEmpty => FriendGroup.values.every((g) => countOf(g) == 0);

  /// The friends who wrote a review, rated first, then the newest.
  List<FriendWithGame> get reviews =>
      [for (final f in friends) if (f.review.isNotEmpty) f]..sort(_ratedThenNewest);

  int countOf(FriendGroup group) =>
      group.statuses.fold(0, (sum, s) => sum + (totals[s] ?? 0));

  /// The members of [group] that were sent: rated first, then the most
  /// recently added (To Play and Wishlist are merged, so they are sorted again).
  List<FriendWithGame> membersOf(FriendGroup group) {
    final members = [
      for (final f in friends)
        if (group.statuses.contains(f.status)) f,
    ];
    if (group.statuses.length > 1) members.sort(_ratedThenNewest);
    return members;
  }
}

int _ratedThenNewest(FriendWithGame a, FriendWithGame b) {
  final rated = (b.rating > 0 ? 1 : 0) - (a.rating > 0 ? 1 : 0);
  if (rated != 0) return rated;
  final at = a.dateAdded;
  final bt = b.dateAdded;
  // Undated last.
  if (at == null || bt == null) {
    return (at == null ? 1 : 0) - (bt == null ? 1 : 0);
  }
  return bt.compareTo(at);
}
