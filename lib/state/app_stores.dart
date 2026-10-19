import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:checkpoint/models/share_link.dart';
import 'package:checkpoint/services/auth_service.dart';
import 'package:checkpoint/services/checkpoint_repository.dart';
import 'package:checkpoint/services/connectivity_service.dart';
import 'package:checkpoint/services/game_api_service.dart';
import 'package:checkpoint/services/local_cache.dart';
import 'package:checkpoint/services/steam_link_service.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/browse_store.dart';
import 'package:checkpoint/state/community_times_store.dart';
import 'package:checkpoint/state/company_store.dart';
import 'package:checkpoint/state/friends_feed_store.dart';
import 'package:checkpoint/state/game_details_store.dart';
import 'package:checkpoint/state/game_friends_store.dart';
import 'package:checkpoint/state/library_attributes_store.dart';
import 'package:checkpoint/state/library_store.dart';
import 'package:checkpoint/state/library_view_store.dart';
import 'package:checkpoint/state/lists_store.dart';
import 'package:checkpoint/state/nav_store.dart';
import 'package:checkpoint/state/play_timer_store.dart';
import 'package:checkpoint/state/profile_store.dart';
import 'package:checkpoint/state/public_achievements_store.dart';
import 'package:checkpoint/state/public_library_store.dart';
import 'package:checkpoint/state/public_profile_store.dart';
import 'package:checkpoint/state/release_alerts_store.dart';
import 'package:checkpoint/state/search_store.dart';
import 'package:checkpoint/state/shared_link_store.dart';
import 'package:checkpoint/state/social_graph_store.dart';

/// The app's stores and how they depend on each other. Dependencies point one
/// way, with no cycles:
///  * [ProfileStore], [LibraryStore] and [SearchStore] follow [AuthStore] for who
///    is signed in, and load or drop their data when it changes;
///  * [LibraryStore] reads [ProfileStore] for the Steam connection, and
///    [SearchStore], [BrowseStore], [GameDetailsStore] and [CompanyStore] for a
///    search result, a browse-list game, a similar game or a game on a company's
///    page being opened or added; [CompanyStore], like [BrowseStore], depends on
///    nothing;
///    [GameDetailsStore] hands each game's exact platforms and genres back to
///    [LibraryStore] when they load (a callback set here, not a dependency); [BrowseStore] depends on nothing, its lists are the
///    same for everyone; [LibraryStore] also fills in, in the background, the
///    catalog rows of its games that IGDB never filled in (CatalogBackfill);
///  * [SearchStore] and [LibraryViewStore] use [NavStore] (leaving the Search tab
///    clears its results and filters, and filters handed to it with the tab
///    switch, from a tag on a game's screen, are browsed; opening a Library tab
///    switches to it);
///  * [LibraryAttributesStore] follows [AuthStore] and holds what the Library's
///    filters need that the library itself does not (themes, game modes,
///    developers...), which [LibraryViewStore] reads. [LibraryStore] tells it
///    (a callback set here) when the server filled in catalog rows, so it reads
///    again;
///  * [PublicProfileStore], [PublicLibraryStore], [SocialGraphStore],
///    [PublicAchievementsStore], [GameFriendsStore] and [FriendsFeedStore] hold
///    what is fetched about OTHER members. They follow [AuthStore] only, so
///    that a sign-out drops it, and never touch [ProfileStore] (the signed-in
///    member's own profile).
///    [LibraryStore] reads [PublicProfileStore], [PublicLibraryStore] and
///    [FriendsFeedStore] to open a game tapped on someone's profile or library or
///    in Home's friends feed, and tells
///    [PublicAchievementsStore] when the library was cleared (your own
///    achievements go with it) or synced with Steam (which counts them again).
///    [PublicAchievementsStore] hands the lists of your own games it fetches
///    from Steam back to [LibraryStore];
///  * [PlayTimerStore] follows [AuthStore] only: the timer is the device's, per
///    account, and becomes a session through [LibraryStore] from the UI;
///  * [ListsStore] follows [AuthStore] and asks [LibraryStore] to put a game in
///    the catalog before it goes on a list; [LibraryStore] finds the games of
///    lists through it (a game tapped on a list);
///  * [ReleaseAlertsStore] reads [LibraryStore]'s wishlist and follows
///    [AuthStore] for whose releases were announced;
///  * [CommunityTimesStore] holds how long the members took to finish a game
///    (the medians, never one member's time). It follows [AuthStore] only;
///    [LibraryStore] tells it (a callback set here) when the member's own time
///    for a game reached the server, so it reads that game's again.
class AppStores {
  AppStores({
    required CheckpointRepository repository,
    required AuthService authService,
    LocalCache? cache,
    GameApiService? apiService,
    ConnectivityService? connectivity,
    LinkTarget? initialLink,
    SteamLinkFlow? steamLink,
    String? steamLinkResult,
  }) {
    final localCache = cache ?? LocalCache();
    links = SharedLinkStore(repository: repository, initial: initialLink);
    final network = connectivity ?? ConnectivityService();
    auth = AuthStore(authService);
    nav = NavStore();
    profile = ProfileStore(
      repository: repository,
      auth: auth,
      connectivity: network,
      cache: localCache,
      steamLink: steamLink,
      steamLinkResult: steamLinkResult,
    );
    search = SearchStore(
      repository: repository,
      auth: auth,
      nav: nav,
      apiService: apiService,
    );
    browse = BrowseStore(apiService: apiService);
    companies = CompanyStore(apiService: apiService);
    // Hands what it loads to the library (exact platforms and genres), which is
    // built below: the callback only runs later, by when `library` exists.
    gameDetails = GameDetailsStore(
      apiService: apiService,
      onLoaded: (gameId, details) => library.applyDetails(gameId, details),
    );
    publicProfiles = PublicProfileStore(repository: repository, auth: auth);
    publicLibraries = PublicLibraryStore(repository: repository, auth: auth);
    socialGraph = SocialGraphStore(repository: repository, auth: auth);
    gameFriends = GameFriendsStore(repository: repository, auth: auth);
    friendsFeed = FriendsFeedStore(repository: repository, auth: auth);
    communityTimes = CommunityTimesStore(repository: repository, auth: auth);
    publicAchievements = PublicAchievementsStore(
      repository: repository,
      auth: auth,
      onGameFetched: (userId, gameId, list) {
        if (auth.user?.id == userId) library.adoptAchievements(gameId, list);
      },
    );
    library = LibraryStore(
      repository: repository,
      auth: auth,
      profile: profile,
      cache: localCache,
      connectivity: network,
      externalGame: (id) =>
          search.resultById(id) ??
          browse.gameById(id) ??
          gameDetails.similarGameById(id) ??
          companies.gameById(id) ??
          publicProfiles.gameById(id) ??
          publicLibraries.gameById(id) ??
          friendsFeed.gameById(id) ??
          lists.gameById(id) ??
          links.gameById(id),
      onCleared: publicAchievements.markCleared,
      onCatalogFilled: () => libraryAttributes.markStale(),
      onSteamSynced: publicAchievements.refreshAfterSync,
      onCompletionTimeSaved: (gameId) => unawaited(communityTimes.load(gameId)),
      apiService: apiService,
    );
    libraryAttributes = LibraryAttributesStore(
      repository: repository,
      auth: auth,
    );
    libraryView = LibraryViewStore(nav: nav, attributes: libraryAttributes);
    playTimer = PlayTimerStore(auth: auth);
    lists = ListsStore(
      repository: repository,
      auth: auth,
      ensureInCatalog: library.ensureInCatalog,
    );
    releaseAlerts = ReleaseAlertsStore(auth: auth, library: library);
  }

  factory AppStores.supabase(SupabaseClient client) => AppStores(
    repository: CheckpointRepository(client),
    authService: AuthService(client),
    // The web app opened from a shared link: .../#/game/1942.
    initialLink: kIsWeb ? LinkTarget.parse(Uri.base.fragment) : null,
    // The web app back from "Sign in through Steam": .../?steam_link=ok.
    steamLinkResult: takeWebSteamLinkResult(),
  );

  late final SharedLinkStore links;
  late final AuthStore auth;
  late final NavStore nav;
  late final ProfileStore profile;
  late final SearchStore search;
  late final BrowseStore browse;
  late final CompanyStore companies;
  late final GameDetailsStore gameDetails;
  late final PublicProfileStore publicProfiles;
  late final PublicLibraryStore publicLibraries;
  late final SocialGraphStore socialGraph;
  late final GameFriendsStore gameFriends;
  late final FriendsFeedStore friendsFeed;
  late final CommunityTimesStore communityTimes;
  late final PublicAchievementsStore publicAchievements;
  late final LibraryStore library;
  late final LibraryAttributesStore libraryAttributes;
  late final LibraryViewStore libraryView;
  late final PlayTimerStore playTimer;
  late final ListsStore lists;
  late final ReleaseAlertsStore releaseAlerts;

  /// Starts following the session and loads each store. [AuthStore] goes first:
  /// the others read the signed-in user from it.
  Future<void> initialize() async {
    await auth.initialize();
    publicProfiles.initialize();
    publicLibraries.initialize();
    socialGraph.initialize();
    gameFriends.initialize();
    friendsFeed.initialize();
    communityTimes.initialize();
    publicAchievements.initialize();
    libraryAttributes.initialize();
    lists.initialize();
    await Future.wait([
      profile.initialize(),
      library.initialize(),
      search.initialize(),
      playTimer.initialize(),
      releaseAlerts.initialize(),
    ]);
  }

  void dispose() {
    links.dispose();
    releaseAlerts.dispose();
    lists.dispose();
    playTimer.dispose();
    publicAchievements.dispose();
    friendsFeed.dispose();
    communityTimes.dispose();
    gameFriends.dispose();
    socialGraph.dispose();
    publicLibraries.dispose();
    publicProfiles.dispose();
    gameDetails.dispose();
    companies.dispose();
    browse.dispose();
    search.dispose();
    library.dispose();
    libraryView.dispose();
    libraryAttributes.dispose();
    profile.dispose();
    nav.dispose();
    auth.dispose();
  }
}
