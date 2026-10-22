import 'package:flutter/material.dart';

import 'package:checkpoint/app/nav_tab.dart';
import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/models/filter_options.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/social_user.dart';
import 'package:checkpoint/screens/company/company_screen.dart';
import 'package:checkpoint/screens/game_detail/game_detail_screen.dart';
import 'package:checkpoint/screens/profile/follows_screen.dart';
import 'package:checkpoint/screens/profile/milestones_screen.dart';
import 'package:checkpoint/screens/profile/public_library_screen.dart';
import 'package:checkpoint/screens/profile/public_profile_screen.dart';
import 'package:checkpoint/state/library_state.dart';
import 'package:checkpoint/state/library_store.dart';
import 'package:checkpoint/state/shared_link_store.dart';
import 'package:checkpoint/state/nav_store.dart';
import 'package:checkpoint/state/social_graph_store.dart';
import 'package:checkpoint/state/store_scope.dart';

void openGame(BuildContext context, String id) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GameDetailScreen(gameId: id)));

/// Opens the game with the IGDB id [igdbId]: from the library, or from the catalog
/// when it is not there (a game a discussion is about). Says so when it can't be found.
Future<void> openGameByIgdbId(BuildContext context, int igdbId) async {
  final library = context.read<LibraryStore>();
  final links = context.read<SharedLinkStore>();
  final messenger = ScaffoldMessenger.of(context);
  final message = context.l10n.linkGameNotFound;
  final game = library.maybeGame(gameIdForIgdb(igdbId)) ?? await links.loadGame(igdbId);
  if (!context.mounted) return;
  if (game == null) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  } else {
    openGame(context, game.id);
  }
}

/// Opens a publisher's or developer's page, by IGDB company id. [name] (what
/// was tapped) is its title while the page loads.
void openCompany(BuildContext context, int companyId, {String? name}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CompanyScreen(companyId: companyId, name: name)),
    );

/// Shows the Discover tab on the games matching [filters] (a tag tapped on a
/// game's screen), closing every screen opened over the tabs first.
void openDiscover(BuildContext context, FilterOptions filters) {
  final nav = context.read<NavStore>();
  Navigator.of(context).popUntil((route) => route.isFirst);
  nav.switchTab(NavTab.search, discoverFilters: filters);
}

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

/// Opens every milestone of [userId], with how far along they are on your own;
/// [ownerName] is the title on someone else's.
void openMilestones(BuildContext context, {required String userId, String? ownerName}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MilestonesScreen(userId: userId, ownerName: ownerName),
      ),
    );
