import 'package:flutter/material.dart';

import 'package:checkpoint/models/social_user.dart';
import 'package:checkpoint/screens/game_detail/game_detail_screen.dart';
import 'package:checkpoint/screens/profile/follow_list_screen.dart';
import 'package:checkpoint/screens/profile/public_profile_screen.dart';
import 'package:checkpoint/state/social_graph_store.dart';

void openGame(BuildContext context, String id) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GameDetailScreen(gameId: id)));

/// Opens another member's profile. [preview] (the row that was tapped) fills in
/// their name and photo while the rest loads.
void openProfile(BuildContext context, {required String userId, SocialUser? preview}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PublicProfileScreen(userId: userId, preview: preview)),
    );

/// Opens the followers or following list of [userId]; [ownerName] is shown under
/// the title.
void openFollowList(BuildContext context, {required String userId, required FollowListKind kind, String? ownerName}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FollowListScreen(userId: userId, kind: kind, ownerName: ownerName),
      ),
    );
