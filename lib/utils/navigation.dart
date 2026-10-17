import 'package:flutter/material.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/social_user.dart';
import 'package:checkpoint/screens/game_detail/game_detail_screen.dart';
import 'package:checkpoint/screens/profile/follows_screen.dart';
import 'package:checkpoint/screens/profile/public_library_screen.dart';
import 'package:checkpoint/screens/profile/public_profile_screen.dart';
import 'package:checkpoint/state/library_state.dart';
import 'package:checkpoint/state/social_graph_store.dart';

void openGame(BuildContext context, String id) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GameDetailScreen(gameId: id)));

/// Opens another member's profile. [preview] (the row that was tapped) fills in
/// their name and photo while the rest loads.
void openProfile(BuildContext context, {required String userId, SocialUser? preview}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PublicProfileScreen(userId: userId, preview: preview)),
    );

/// Opens the followers / following screen of [userId] on the tab [kind];
/// [ownerName] is its title.
void openFollows(BuildContext context, {required String userId, required FollowListKind kind, String? ownerName}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FollowsScreen(userId: userId, initialKind: kind, ownerName: ownerName),
      ),
    );

/// Opens another member's library, on the [status] tab if given, sorted by
/// [sortBy] if given.
void openPublicLibrary(
  BuildContext context, {
  required String userId,
  String? ownerName,
  GameStatus? status,
  SortField? sortBy,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => PublicLibraryScreen(userId: userId, ownerName: ownerName, initialStatus: status, sortBy: sortBy),
  ),
);
