import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:checkpoint/models/game.dart';

class GameApiService {
  // IGDB is reached through the `igdb-handler` Supabase Edge Function. The Twitch
  // credentials and OAuth token live server-side and never ship in the app.

  // 1. Pad IGDB integers into strict Supabase UUIDs
  String _igdbToUuid(int id) {
    final padded = id.toString().padLeft(12, '0');
    return '00000000-0000-4000-8000-$padded';
  }

  // 2. Map IGDB platform IDs to brand families.
  //    Every historical console rolls up into its parent brand.
  //    PlayStation: PS5 / PS VR2 -> ps5, PS4 / PS VR -> ps4, older consoles -> generic playstation.
  //    GamePlatform.emulator is intentionally absent: it is a manual user selection
  //    (stored as 'retro' in the DB), never an official release platform.
  //    Platforms not listed here (mobile, web, etc.) are skipped.
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
  List<GamePlatform> _parsePlatforms(dynamic raw) {
    if (raw is! List) return const [];
    final result = <GamePlatform>{};
    for (final p in raw) {
      if (p is! Map) continue;
      final mapped = _platformMap[p['id']];
      if (mapped != null) result.add(mapped);
    }
    return result.toList();
  }

  // 3. Calls the Edge Function; returns the raw IGDB array (empty on any failure).
  Future<List<dynamic>> _invokeSearch(String query) async {
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'igdb-handler',
        body: {'query': query, 'limit': 20},
      );
      final raw = res.data;
      final decoded = raw is String ? json.decode(raw) : raw;
      return decoded is List ? decoded : const [];
    } catch (e) {
      debugPrint('igdb-handler request failed: $e');
      return const [];
    }
  }

  // 4. Search games
  Future<List<Game>> searchGames(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    final data = await _invokeSearch(q);
    return data.map((json) {
      String? coverUrl;
      if (json['cover'] != null && json['cover']['url'] != null) {
        coverUrl = 'https:${json['cover']['url']}'.replaceAll('t_thumb', 't_cover_big');
      }

      // 4-digit UTC year, or null if missing / outside 1950-2100. The model has no
      // nullable year, so 0 means "unknown" here; it is stored as NULL in the DB.
      final year = releaseYearFromUnixSeconds(json['first_release_date']) ?? 0;

      final genres = (json['genres'] as List?)?.map((g) => g['name'].toString()).toList() ?? [];
      
      String company = 'Unknown Publisher';
      if (json['involved_companies'] != null && (json['involved_companies'] as List).isNotEmpty) {
        company = json['involved_companies'][0]['company']['name'] ?? company;
      }

      return Game(
        id: _igdbToUuid(json['id']),
        title: json['name'] ?? 'Unknown',
        developer: company,
        publisher: company,
        releaseYear: year,
        platforms: _parsePlatforms(json['platforms']),
        genres: genres,
        synopsis: json['summary'] ?? '',
        coverColors: const [Color(0xFF2C2C2C), Color(0xFF1A1A1A)],
        coverIcon: Icons.sports_esports_rounded,
        coverUrl: coverUrl,
      );
    }).toList();
  }
}