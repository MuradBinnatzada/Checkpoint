import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:checkpoint/models/browse.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/game_details.dart';
import 'package:checkpoint/models/results_page.dart';
import 'package:checkpoint/services/sync_failure.dart';

class GameApiService {
  // IGDB is reached through the `igdb-handler` Supabase Edge Function. The Twitch
  // credentials and OAuth token live server-side and never ship in the app.

  /// Results per request. The Edge Function allows up to 50.
  static const int searchPageSize = 20;

  /// Games per request for a browse list: a whole number of rows in the 2- and
  /// 3-column grids, and more than a screenful.
  static const int browsePageSize = 30;

  /// Most games one `backfill` request may name (`MAX_BACKFILL_IDS` in
  /// supabase/functions/_shared/game_details.ts).
  static const int maxBackfillIds = 50;

  // 1. Map IGDB platform IDs to the app's platforms, down to the console: PS3 and
  //    PS4 are two platforms. Windows, Mac, Linux and DOS are all "PC"; a few
  //    near-identical IGDB entries share one (the Famicom is the NES, Super Famicom
  //    the SNES, DSi the DS, New 3DS the 3DS, Xbox Live Arcade the Xbox 360, PS VR
  //    the PS4, PS VR2 the PS5, Sega CD and 32X the Genesis).
  //    GamePlatform.steamDeck and GamePlatform.emulator are intentionally absent:
  //    they are manual "played on" choices (the emulator is stored as 'retro' in
  //    the DB), never a release platform; see Game.playedOnOptions.
  //    Platforms not listed here (web, arcade, Atari, etc.) are skipped.
  //    Keep in step with `IGDB_PLATFORM_TO_DB` in supabase/functions/_shared/platforms.ts.
  static const Map<int, GamePlatform> _platformMap = {
    // --- PC ---
    6: GamePlatform.pc, // PC (Microsoft Windows)
    14: GamePlatform.pc, // Mac
    3: GamePlatform.pc, // Linux
    13: GamePlatform.pc, // DOS

    // --- PlayStation ---
    7: GamePlatform.ps1, // PlayStation
    8: GamePlatform.ps2, // PlayStation 2
    9: GamePlatform.ps3, // PlayStation 3
    48: GamePlatform.ps4, // PlayStation 4
    165: GamePlatform.ps4, // PlayStation VR
    167: GamePlatform.ps5, // PlayStation 5
    390: GamePlatform.ps5, // PlayStation VR2
    38: GamePlatform.psp, // PlayStation Portable
    46: GamePlatform.vita, // PlayStation Vita

    // --- Xbox ---
    11: GamePlatform.xboxOriginal, // Xbox
    12: GamePlatform.xbox360, // Xbox 360
    36: GamePlatform.xbox360, // Xbox Live Arcade
    49: GamePlatform.xboxOne, // Xbox One
    169: GamePlatform.xboxSeries, // Xbox Series X|S

    // --- Nintendo ---
    18: GamePlatform.nes, // Nintendo Entertainment System
    99: GamePlatform.nes, // Family Computer
    51: GamePlatform.nes, // Famicom Disk System
    19: GamePlatform.snes, // Super Nintendo
    58: GamePlatform.snes, // Super Famicom
    4: GamePlatform.n64, // Nintendo 64
    21: GamePlatform.gamecube, // Nintendo GameCube
    5: GamePlatform.wii, // Wii
    41: GamePlatform.wiiU, // Wii U
    130: GamePlatform.nswitch, // Nintendo Switch
    508: GamePlatform.nswitch2, // Nintendo Switch 2
    33: GamePlatform.gameBoy, // Game Boy
    22: GamePlatform.gbc, // Game Boy Color
    24: GamePlatform.gba, // Game Boy Advance
    87: GamePlatform.virtualBoy, // Virtual Boy
    20: GamePlatform.nds, // Nintendo DS
    159: GamePlatform.nds, // Nintendo DSi
    37: GamePlatform.n3ds, // Nintendo 3DS
    137: GamePlatform.n3ds, // New Nintendo 3DS

    // --- Sega ---
    64: GamePlatform.masterSystem, // Sega Master System
    29: GamePlatform.genesis, // Sega Mega Drive / Genesis
    78: GamePlatform.genesis, // Sega CD
    30: GamePlatform.genesis, // Sega 32X
    32: GamePlatform.saturn, // Sega Saturn
    23: GamePlatform.dreamcast, // Dreamcast
    35: GamePlatform.gameGear, // Sega Game Gear

    // --- Mobile ---
    34: GamePlatform.android, // Android
    39: GamePlatform.ios, // iOS
    55: GamePlatform.mobile, // Legacy Mobile Device
  };

  // Converts IGDB's `platforms` array into a de-duplicated list of the app's
  // platforms, preserving first-seen order (Windows + Mac -> [pc]).
  static List<GamePlatform> parsePlatforms(dynamic raw) {
    if (raw is! List) return const [];
    final result = <GamePlatform>{};
    for (final p in raw) {
      if (p is! Map) continue;
      final mapped = _platformMap[p['id']];
      if (mapped != null) result.add(mapped);
    }
    return result.toList();
  }

  /// One IGDB hit as a [Game], or null when it has no usable IGDB id. The id is
  /// the game's identity (see [gameIdForIgdb]), so a hit without one can't be
  /// saved consistently and is left out of the results. Every other field is
  /// optional in IGDB's answer: a missing or oddly shaped one falls back to a
  /// placeholder, so one sparse hit can't fail the whole page.
  static Game? gameFromHit(Object? hit) {
    if (hit is! Map) return null;
    final rawId = hit['id'];
    final igdbId = rawId is num ? rawId.toInt() : null;
    if (igdbId == null || igdbId <= 0) return null;

    final cover = hit['cover'];
    final coverPath = cover is Map ? _text(cover['url']) : null;
    final coverUrl = coverPath == null
        ? null
        : 'https:$coverPath'.replaceAll('t_thumb', 't_cover_big');

    final rawGenres = hit['genres'];
    final genres = [
      if (rawGenres is List)
        for (final g in rawGenres) ?(g is Map ? _text(g['name']) : null),
    ];

    // The first involved company that has a name stands in for both publisher
    // and developer.
    String? company;
    final involved = hit['involved_companies'];
    if (involved is List) {
      for (final entry in involved) {
        final details = entry is Map ? entry['company'] : null;
        company = details is Map ? _text(details['name']) : null;
        if (company != null) break;
      }
    }
    company ??= 'Unknown Publisher';

    return Game(
      id: gameIdForIgdb(igdbId),
      igdbId: igdbId,
      title: _text(hit['name']) ?? 'Unknown',
      developer: company,
      publisher: company,
      // 4-digit UTC year, or null if missing / outside 1950-2100. The model has
      // no nullable year, so 0 means "unknown" here; it is stored as NULL in the DB.
      releaseYear: releaseYearFromUnixSeconds(hit['first_release_date']) ?? 0,
      platforms: parsePlatforms(hit['platforms']),
      genres: genres,
      synopsis: _text(hit['summary']) ?? '',
      coverColors: const [Color(0xFF2C2C2C), Color(0xFF1A1A1A)],
      coverIcon: Icons.sports_esports_rounded,
      coverUrl: coverUrl,
    );
  }

  /// One IGDB hit of a browse list as a [BrowseEntry], or null when it is not a
  /// usable game (see [gameFromHit]). The figures are optional like the rest.
  static BrowseEntry? entryFromHit(Object? hit) {
    final game = gameFromHit(hit);
    if (game == null || hit is! Map) return null;
    final score = hit['total_rating'];
    final released = hit['first_release_date'];
    return BrowseEntry(
      game,
      score: score is num && score.isFinite ? score.toDouble() : null,
      // Only a date that also gives a valid release year counts (same range check).
      releaseDate:
          released is num && releaseYearFromUnixSeconds(released) != null
          ? DateTime.fromMillisecondsSinceEpoch(
              released.toInt() * 1000,
              isUtc: true,
            )
          : null,
    );
  }

  /// What the `details` request of `igdb-handler` answered, as [GameDetails], or
  /// null when it is not an answer with a game in it (an `{ "error": ... }`, say).
  /// Every field is optional, like in [gameFromHit]: a sparse game gives a sparse
  /// result, not a failure.
  static GameDetails? detailsFromResponse(Object? response) {
    if (response is! Map) return null;
    final game = response['game'];
    if (game is! Map) return null;
    final rawId = game['id'];
    final igdbId = rawId is num ? rawId.toInt() : null;
    if (igdbId == null || igdbId <= 0) return null;

    List<String> names(Object? list) {
      if (list is! List) return const [];
      final seen = <String>{};
      for (final entry in list) {
        final name = entry is Map ? _text(entry['name']) : null;
        if (name != null) seen.add(name);
      }
      return seen.toList(growable: false);
    }

    // Main developers and publishers: the flagged companies that are not only
    // supporting. With no flags at all, the first company stands in for both.
    final developers = <String>{};
    final publishers = <String>{};
    String? firstCompany;
    final involved = game['involved_companies'];
    if (involved is List) {
      for (final entry in involved) {
        if (entry is! Map) continue;
        final company = entry['company'];
        final name = company is Map ? _text(company['name']) : null;
        if (name == null) continue;
        firstCompany ??= name;
        if (entry['supporting'] == true) continue;
        if (entry['developer'] == true) developers.add(name);
        if (entry['publisher'] == true) publishers.add(name);
      }
    }
    if (developers.isEmpty && publishers.isEmpty && firstCompany != null) {
      developers.add(firstCompany);
      publishers.add(firstCompany);
    }

    final similar = game['similar_games'];
    return GameDetails(
      igdbId: igdbId,
      platforms: parsePlatforms(game['platforms']),
      genres: names(game['genres']),
      themes: names(game['themes']),
      gameModes: names(game['game_modes']),
      perspectives: names(game['player_perspectives']),
      engines: names(game['game_engines']),
      developers: developers.toList(growable: false),
      publishers: publishers.toList(growable: false),
      storyline: _text(game['storyline']),
      similarGames: [
        if (similar is List)
          for (final hit in similar)
            // A bare id (IGDB did not expand it) has no name to show.
            if (hit is Map && hit['name'] != null) ?gameFromHit(hit),
      ],
      timeToBeat: TimeToBeat.fromJson(response['time_to_beat']),
    );
  }

  /// What the `backfill` request of `igdb-handler` answered (`{ "games": [{
  /// "igdb_id", "platforms", "genres" }], "unknown": [...] }`), as each game's
  /// exact platforms and genres, or null when it is not such an answer. The
  /// platforms are the catalog's own names, read like a library row's.
  static List<GameDetails>? backfillFromResponse(Object? response) {
    if (response is! Map) return null;
    final games = response['games'];
    if (games is! List) return null;
    List<String> strings(Object? list) => [
      if (list is List)
        for (final value in list) ?_text(value),
    ];
    return [
      for (final game in games)
        if (game is Map)
          if (game['igdb_id'] case final num rawId when rawId.toInt() > 0)
            GameDetails(
              igdbId: rawId.toInt(),
              platforms: releasePlatformsFromDb(strings(game['platforms'])),
              genres: strings(game['genres']),
            ),
    ];
  }

  /// A failed `backfill` request, from what was thrown while calling it: one that
  /// waiting fixes (IGDB is limiting requests or down, the server is busy) says
  /// how long to wait, the server's `retry_after` or a minute; any other (no
  /// connection, a function deployed before the mode existed) says nothing, so
  /// the backfill stops until the library is loaded again.
  static CatalogBackfillResult backfillFailure(Object error) {
    final failure = SyncFailure.from(error);
    if (!failure.isDelayed || failure.code == SyncFailureCode.offline) {
      return const CatalogBackfillResult.failed();
    }
    return CatalogBackfillResult.failed(
      retryAfter: failure.retryAfter ?? const Duration(minutes: 1),
    );
  }

  /// [value] trimmed, or null when it is not a string or is blank.
  static String? _text(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  // 3. Calls the Edge Function with [body]; returns the raw IGDB array, or null
  //    when the request failed (a non-list body is the function's `{ "error": ... }`).
  Future<List<dynamic>?> _invoke(Map<String, Object> body) async {
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'igdb-handler',
        body: body,
      );
      final raw = res.data;
      final decoded = raw is String ? json.decode(raw) : raw;
      return decoded is List ? decoded : null;
    } catch (e) {
      debugPrint('igdb-handler request failed: $e');
      return null;
    }
  }

  // 4. Search games, one page at a time; null when the request failed. [offset]
  //    counts IGDB hits (the previous pages' [ResultsPage.fetched] added up), not
  //    the games kept: hits without a usable IGDB id are left out of the page.
  Future<ResultsPage<Game>?> searchGames(
    String query, {
    int offset = 0,
    int limit = searchPageSize,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return ResultsPage<Game>(const [], hasMore: false);

    final data = await _invoke({'query': q, 'limit': limit, 'offset': offset});
    if (data == null) return null;
    final games = [for (final hit in data) ?gameFromHit(hit)];

    return ResultsPage<Game>(
      games,
      hasMore: data.length >= limit, // IGDB filled the page: another may exist
      fetched: data.length,
    );
  }

  // 5. One page of a browse list ("Most popular", ...); null when the request
  //    failed. [offset] counts IGDB hits, as in [searchGames].
  Future<ResultsPage<BrowseEntry>?> browseGames(
    BrowseMode mode, {
    int offset = 0,
    int limit = browsePageSize,
  }) async {
    final data = await _invoke({
      'mode': mode.wireName,
      'limit': limit,
      'offset': offset,
    });
    if (data == null) return null;

    return ResultsPage<BrowseEntry>(
      [for (final hit in data) ?entryFromHit(hit)],
      hasMore: data.length >= limit, // IGDB filled the page: another may exist
      fetched: data.length,
    );
  }

  // 6. One game's whole page: exact platforms, genres, themes, game modes,
  //    perspectives, engines, developers, publishers, storyline, similar games
  //    and time to beat. Null when the request failed or IGDB has no such game.
  //    The function also saves the stable part on the game's catalog row.
  Future<GameDetails?> fetchDetails(int igdbId) async {
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'igdb-handler',
        body: {'mode': 'details', 'igdb_id': igdbId},
      );
      final raw = res.data;
      return detailsFromResponse(raw is String ? json.decode(raw) : raw);
    } catch (e) {
      debugPrint('igdb-handler details request failed: $e');
      return null;
    }
  }

  // 7. Fills in the catalog rows of up to [maxBackfillIds] games from IGDB (exact
  //    platforms, genres, themes, modes, perspectives, engines, developers and
  //    publishers) and answers what each row holds now. For the library's games
  //    that were never filled in; see `CatalogBackfill`.
  Future<CatalogBackfillResult> backfillCatalog(List<int> igdbIds) async {
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'igdb-handler',
        body: {'mode': 'backfill', 'igdb_ids': igdbIds},
      );
      final raw = res.data;
      final games = backfillFromResponse(
        raw is String ? json.decode(raw) : raw,
      );
      return games == null
          ? const CatalogBackfillResult.failed()
          : CatalogBackfillResult(games);
    } catch (e) {
      debugPrint('igdb-handler backfill request failed: $e');
      return backfillFailure(e);
    }
  }
}
