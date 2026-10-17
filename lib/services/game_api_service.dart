import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:checkpoint/models/browse.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/results_page.dart';

class GameApiService {
  // IGDB is reached through the `igdb-handler` Supabase Edge Function. The Twitch
  // credentials and OAuth token live server-side and never ship in the app.

  /// Results per request. The Edge Function allows up to 50.
  static const int searchPageSize = 20;

  /// Games per request for a browse list: a whole number of rows in the 2- and
  /// 3-column grids, and more than a screenful.
  static const int browsePageSize = 30;

  // 1. Map IGDB platform IDs to brand families.
  //    Every historical console rolls up into its parent brand.
  //    PlayStation: PS5 / PS VR2 -> ps5, PS4 / PS VR -> ps4, older consoles -> generic playstation.
  //    GamePlatform.steamDeck and GamePlatform.emulator are intentionally absent:
  //    they are manual "played on" choices (the emulator is stored as 'retro' in
  //    the DB), never a release platform; see Game.playedOnOptions.
  //    Platforms not listed here (web, arcade, Dreamcast, etc.) are skipped.
  //    Keep in step with `igdbPlatformToDb` in supabase/functions/_shared/platforms.ts.
  static const Map<int, GamePlatform> _platformMap = {
    // --- PC ---
    6: GamePlatform.pc, // PC (Microsoft Windows)
    14: GamePlatform.pc, // Mac
    3: GamePlatform.pc, // Linux

    // --- PlayStation family ---
    7: GamePlatform.playstation, // PlayStation (PS1)
    8: GamePlatform.playstation, // PlayStation 2
    9: GamePlatform.playstation, // PlayStation 3
    38: GamePlatform.playstation, // PlayStation Portable (PSP)
    46: GamePlatform.playstation, // PlayStation Vita
    48: GamePlatform.ps4, // PlayStation 4
    165: GamePlatform.ps4, // PlayStation VR
    167: GamePlatform.ps5, // PlayStation 5
    390: GamePlatform.ps5, // PlayStation VR2

    // --- Xbox family ---
    11: GamePlatform.xbox, // Xbox (original)
    12: GamePlatform.xbox, // Xbox 360
    36: GamePlatform.xbox, // Xbox Live Arcade
    49: GamePlatform.xbox, // Xbox One
    169: GamePlatform.xbox, // Xbox Series X|S

    // --- Nintendo family ---
    18: GamePlatform.nintendo, // Nintendo Entertainment System (NES)
    99: GamePlatform.nintendo, // Family Computer (Famicom)
    51: GamePlatform.nintendo, // Famicom Disk System
    19: GamePlatform.nintendo, // Super Nintendo (SNES)
    58: GamePlatform.nintendo, // Super Famicom
    4: GamePlatform.nintendo, // Nintendo 64
    21: GamePlatform.nintendo, // Nintendo GameCube
    5: GamePlatform.nintendo, // Wii
    41: GamePlatform.nintendo, // Wii U
    33: GamePlatform.nintendo, // Game Boy
    22: GamePlatform.nintendo, // Game Boy Color
    24: GamePlatform.nintendo, // Game Boy Advance
    87: GamePlatform.nintendo, // Virtual Boy
    20: GamePlatform.nintendo, // Nintendo DS
    159: GamePlatform.nintendo, // Nintendo DSi
    37: GamePlatform.nintendo, // Nintendo 3DS
    137: GamePlatform.nintendo, // New Nintendo 3DS
    130: GamePlatform.nswitch, // Nintendo Switch
    508: GamePlatform.nswitch, // Nintendo Switch 2

    // --- Mobile family ---
    34: GamePlatform.mobile, // Android
    39: GamePlatform.mobile, // iOS
    55: GamePlatform.mobile, // Legacy Mobile
  };

  // Converts IGDB's `platforms` array into a de-duplicated list of brand families,
  // preserving first-seen order (e.g. PS1 + PS2 + PS3 -> [playStation]).
  static List<GamePlatform> _parsePlatforms(dynamic raw) {
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
      platforms: _parsePlatforms(hit['platforms']),
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
}