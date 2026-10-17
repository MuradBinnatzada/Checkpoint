import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:checkpoint/services/auth_service.dart';
import 'package:checkpoint/services/checkpoint_repository.dart';
import 'package:checkpoint/services/connectivity_service.dart';
import 'package:checkpoint/services/game_api_service.dart';
import 'package:checkpoint/services/local_cache.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/browse_store.dart';
import 'package:checkpoint/state/library_store.dart';
import 'package:checkpoint/state/library_view_store.dart';
import 'package:checkpoint/state/nav_store.dart';
import 'package:checkpoint/state/profile_store.dart';
import 'package:checkpoint/state/public_achievements_store.dart';
import 'package:checkpoint/state/public_profile_store.dart';
import 'package:checkpoint/state/search_store.dart';
import 'package:checkpoint/state/social_graph_store.dart';

/// The app's stores and how they depend on each other. Dependencies point one
/// way, with no cycles:
///  * [ProfileStore], [LibraryStore] and [SearchStore] follow [AuthStore] for who
///    is signed in, and load or drop their data when it changes;
///  * [LibraryStore] reads [ProfileStore] for the Steam connection, and
///    [SearchStore] and [BrowseStore] for a search result or a browse-list game
///    being opened or added; [BrowseStore] depends on nothing, its lists are the
///    same for everyone;
///  * [SearchStore] and [LibraryViewStore] use [NavStore] (leaving the Search tab
///    clears its results; opening a Library tab switches to it);
///  * [PublicProfileStore], [SocialGraphStore] and [PublicAchievementsStore] hold
///    what is fetched about OTHER members. They follow [AuthStore] only, so that a
///    sign-out drops it, and never touch [ProfileStore] (the signed-in member's own
///    profile). [LibraryStore] reads [PublicProfileStore] to open a game tapped on
///    someone's profile.
class AppStores {
  AppStores({
    required CheckpointRepository repository,
    required AuthService authService,
    LocalCache? cache,
    GameApiService? apiService,
    ConnectivityService? connectivity,
  }) {
    final localCache = cache ?? LocalCache();
    final network = connectivity ?? ConnectivityService();
    auth = AuthStore(authService);
    nav = NavStore();
    profile = ProfileStore(
      repository: repository,
      auth: auth,
      connectivity: network,
      cache: localCache,
    );
    search = SearchStore(
      repository: repository,
      auth: auth,
      nav: nav,
      apiService: apiService,
    );
    browse = BrowseStore(apiService: apiService);
    publicProfiles = PublicProfileStore(repository: repository, auth: auth);
    socialGraph = SocialGraphStore(repository: repository, auth: auth);
    publicAchievements = PublicAchievementsStore(
      repository: repository,
      auth: auth,
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
          publicProfiles.gameById(id),
    );
    libraryView = LibraryViewStore(nav: nav);
  }

  factory AppStores.supabase(SupabaseClient client) => AppStores(
    repository: CheckpointRepository(client),
    authService: AuthService(client),
  );

  late final AuthStore auth;
  late final NavStore nav;
  late final ProfileStore profile;
  late final SearchStore search;
  late final BrowseStore browse;
  late final PublicProfileStore publicProfiles;
  late final SocialGraphStore socialGraph;
  late final PublicAchievementsStore publicAchievements;
  late final LibraryStore library;
  late final LibraryViewStore libraryView;

  /// Starts following the session and loads each store. [AuthStore] goes first:
  /// the others read the signed-in user from it.
  Future<void> initialize() async {
    await auth.initialize();
    publicProfiles.initialize();
    socialGraph.initialize();
    publicAchievements.initialize();
    await Future.wait([
      profile.initialize(),
      library.initialize(),
      search.initialize(),
    ]);
  }

  void dispose() {
    publicAchievements.dispose();
    socialGraph.dispose();
    publicProfiles.dispose();
    browse.dispose();
    search.dispose();
    library.dispose();
    libraryView.dispose();
    profile.dispose();
    nav.dispose();
    auth.dispose();
  }
}
