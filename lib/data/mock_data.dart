import 'package:flutter/material.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/log_entry.dart';
import 'package:checkpoint/models/user_profile.dart';

abstract final class MockData {
  static UserProfile profile() => UserProfile(
        name: 'Alex Nowak',
        handle: '@alexplays',
        bio: 'Soulslikes by day, cozy farms by night. Professional To Play list optimist.',
        joined: DateTime(2023, 3, 14),
        weeklyGoalHours: 20,
      );

  static List<Game> games(DateTime now) {
    DateTime ago(int days) => now.subtract(Duration(days: days));
    return [
      // ── Playing ──
      Game(
        id: 'elden-ring',
        title: 'Elden Ring',
        publisher: 'Bandai Namco',
        developer: 'FromSoftware',
        releaseYear: 2022,
        platforms: const [GamePlatform.pc, GamePlatform.steamDeck, GamePlatform.ps5, GamePlatform.ps4, GamePlatform.xbox],
        genres: const ['Action RPG', 'Open World'],
        synopsis: 'Wander a vast, broken realm, build your own champion and topple demigods in a world full of secrets.',
        coverColors: const [Color(0xFFB8860B), Color(0xFF1A1206)],
        coverIcon: Icons.auto_awesome_rounded,
        status: GameStatus.playing,
        hoursPlayed: 24,
        playedOn: GamePlatform.ps5,
        purchasePrice: 59.99,
        dateAdded: ago(40),
      ),
      Game(
        id: 'bg3',
        title: "Baldur's Gate 3",
        publisher: 'Larian Studios',
        developer: 'Larian Studios',
        releaseYear: 2023,
        platforms: const [GamePlatform.pc, GamePlatform.steamDeck, GamePlatform.ps5, GamePlatform.xbox],
        genres: const ['RPG', 'Turn-based'],
        synopsis: 'Gather a party, choose your origin and let dice and dialogue decide the fate of a sprawling fantasy saga.',
        coverColors: const [Color(0xFF7B2FBE), Color(0xFF12061F)],
        coverIcon: Icons.casino_rounded,
        status: GameStatus.playing,
        hoursPlayed: 41.5,
        playedOn: GamePlatform.pc,
        purchasePrice: 59.99,
        dateAdded: ago(75),
      ),
      Game(
        id: 'silksong',
        title: 'Hollow Knight: Silksong',
        publisher: 'Team Cherry',
        developer: 'Team Cherry',
        releaseYear: 2025,
        platforms: const [GamePlatform.pc, GamePlatform.steamDeck, GamePlatform.nswitch, GamePlatform.ps5, GamePlatform.xbox],
        genres: const ['Metroidvania', 'Platformer'],
        synopsis: 'Climb through a silk-spun kingdom as a nimble hunter in a hand-drawn, brutally charming adventure.',
        coverColors: const [Color(0xFFC62F4A), Color(0xFF1B0509)],
        coverIcon: Icons.bolt_rounded,
        status: GameStatus.playing,
        hoursPlayed: 9,
        playedOn: GamePlatform.steamDeck,
        purchasePrice: 19.99,
        dateAdded: ago(25),
      ),

      // ── Completed ──
      Game(
        id: 'hades',
        title: 'Hades',
        publisher: 'Supergiant Games',
        developer: 'Supergiant Games',
        releaseYear: 2020,
        platforms: const [GamePlatform.pc, GamePlatform.steamDeck, GamePlatform.nswitch, GamePlatform.ps5, GamePlatform.ps4, GamePlatform.xbox],
        genres: const ['Roguelike', 'Action'],
        synopsis: 'Fight out of the underworld again and again in a fast, stylish roguelike where every escape attempt tells a story.',
        coverColors: const [Color(0xFFD9381E), Color(0xFF260707)],
        coverIcon: Icons.local_fire_department_rounded,
        status: GameStatus.completed,
        rating: 5,
        hoursPlayed: 62,
        playedOn: GamePlatform.nswitch,
        purchasePrice: 24.99,
        dateAdded: ago(420),
      ),
      Game(
        id: 'celeste',
        title: 'Celeste',
        publisher: 'Maddy Makes Games',
        developer: 'Maddy Makes Games',
        releaseYear: 2018,
        platforms: const [GamePlatform.pc, GamePlatform.steamDeck, GamePlatform.nswitch, GamePlatform.ps4, GamePlatform.xbox],
        genres: const ['Platformer', 'Indie'],
        synopsis: 'Scale a haunted mountain in a precise, heartfelt platformer about anxiety, persistence and pixel-perfect jumps.',
        coverColors: const [Color(0xFF3DCBB1), Color(0xFF241A5E)],
        coverIcon: Icons.landscape_rounded,
        status: GameStatus.completed,
        rating: 4.5,
        hoursPlayed: 14,
        playedOn: GamePlatform.nswitch,
        purchasePrice: 19.99,
        dateAdded: ago(610),
      ),
      Game(
        id: 'hollow-knight',
        title: 'Hollow Knight',
        publisher: 'Team Cherry',
        developer: 'Team Cherry',
        releaseYear: 2017,
        platforms: const [GamePlatform.pc, GamePlatform.steamDeck, GamePlatform.nswitch, GamePlatform.ps4, GamePlatform.xbox],
        genres: const ['Metroidvania', 'Indie'],
        synopsis: 'Descend into a ruined insect kingdom and map its caverns, bosses and lonely melodies.',
        coverColors: const [Color(0xFF455A64), Color(0xFF05090B)],
        coverIcon: Icons.nightlight_round,
        status: GameStatus.completed,
        rating: 5,
        hoursPlayed: 48,
        playedOn: GamePlatform.pc,
        purchasePrice: 14.99,
        dateAdded: ago(900),
      ),
      Game(
        id: 'stardew',
        title: 'Stardew Valley',
        publisher: 'ConcernedApe',
        developer: 'ConcernedApe',
        releaseYear: 2016,
        platforms: const [GamePlatform.pc, GamePlatform.steamDeck, GamePlatform.nswitch, GamePlatform.ps4, GamePlatform.xbox, GamePlatform.mobile],
        genres: const ['Farming Sim', 'Cozy'],
        synopsis: 'Inherit a run-down farm and slowly turn it, and your relationships in town, into something thriving.',
        coverColors: const [Color(0xFF7CB342), Color(0xFF14260A)],
        coverIcon: Icons.agriculture_rounded,
        status: GameStatus.completed,
        rating: 4.5,
        hoursPlayed: 126,
        playedOn: GamePlatform.nswitch,
        purchasePrice: 14.99,
        dateAdded: ago(1100),
      ),
      Game(
        id: 'outer-wilds',
        title: 'Outer Wilds',
        publisher: 'Annapurna Interactive',
        developer: 'Mobius Digital',
        releaseYear: 2019,
        platforms: const [GamePlatform.pc, GamePlatform.ps4, GamePlatform.xbox],
        genres: const ['Exploration', 'Mystery'],
        synopsis: 'Explore a tiny solar system stuck in a 22-minute time loop and piece together an ancient mystery.',
        coverColors: const [Color(0xFFEF8A2A), Color(0xFF1C0E29)],
        coverIcon: Icons.rocket_launch_rounded,
        status: GameStatus.completed,
        rating: 5,
        hoursPlayed: 18,
        playedOn: GamePlatform.xbox,
        purchasePrice: 24.99,
        dateAdded: ago(500),
      ),

      // ── To Play ──
      Game(
        id: 'totk',
        title: 'The Legend of Zelda: Tears of the Kingdom',
        publisher: 'Nintendo',
        developer: 'Nintendo EPD',
        releaseYear: 2023,
        platforms: const [GamePlatform.nswitch],
        genres: const ['Adventure', 'Open World'],
        synopsis: 'Take to the skies and caverns of Hyrule and invent your own solutions with a toolbox of strange abilities.',
        coverColors: const [Color(0xFF2E9E6B), Color(0xFF08261B)],
        coverIcon: Icons.explore_rounded,
        status: GameStatus.toPlay,
        purchasePrice: 69.99,
        dateAdded: ago(210),
      ),
      Game(
        id: 'gow-ragnarok',
        title: 'God of War Ragnarök',
        publisher: 'Sony Interactive Entertainment',
        developer: 'Santa Monica Studio',
        releaseYear: 2022,
        platforms: const [GamePlatform.ps5, GamePlatform.ps4, GamePlatform.pc],
        genres: const ['Action Adventure'],
        synopsis: 'A father and son face the end of the world across the nine realms in a cinematic, axe-swinging epic.',
        coverColors: const [Color(0xFF3B8BEB), Color(0xFF0A1830)],
        coverIcon: Icons.ac_unit_rounded,
        status: GameStatus.toPlay,
        hoursPlayed: 3,
        playedOn: GamePlatform.ps5,
        purchasePrice: 49.99,
        dateAdded: ago(330),
      ),
      Game(
        id: 'p5r',
        title: 'Persona 5 Royal',
        publisher: 'Atlus',
        developer: 'Atlus',
        releaseYear: 2019,
        platforms: const [GamePlatform.pc, GamePlatform.steamDeck, GamePlatform.ps5, GamePlatform.ps4, GamePlatform.xbox, GamePlatform.nswitch],
        genres: const ['JRPG', 'Social Sim'],
        synopsis: 'Lead a band of phantom thieves by night and survive high-school life by day in a stylish, jazzy JRPG.',
        coverColors: const [Color(0xFFE5173F), Color(0xFF0D0003)],
        coverIcon: Icons.theater_comedy_rounded,
        status: GameStatus.toPlay,
        purchasePrice: 39.99,
        dateAdded: ago(150),
      ),
      Game(
        id: 'alan-wake-2',
        title: 'Alan Wake 2',
        publisher: 'Epic Games Publishing',
        developer: 'Remedy Entertainment',
        releaseYear: 2023,
        platforms: const [GamePlatform.pc, GamePlatform.ps5, GamePlatform.xbox],
        genres: const ['Survival Horror', 'Thriller'],
        synopsis: 'Two investigators, one nightmare: a layered horror story where writing the plot might change reality.',
        coverColors: const [Color(0xFF2B6F5E), Color(0xFF050D0B)],
        coverIcon: Icons.search_rounded,
        status: GameStatus.toPlay,
        purchasePrice: 59.99,
        dateAdded: ago(95),
      ),

      // ── Dropped ──
      Game(
        id: 'cyberpunk',
        title: 'Cyberpunk 2077',
        publisher: 'CD Projekt',
        developer: 'CD Projekt Red',
        releaseYear: 2020,
        platforms: const [GamePlatform.pc, GamePlatform.steamDeck, GamePlatform.ps5, GamePlatform.xbox],
        genres: const ['Action RPG', 'Open World'],
        synopsis: 'Hustle through Night City as a mercenary with a mysterious chip in your head and a ticking clock.',
        coverColors: const [Color(0xFFF2E600), Color(0xFF2A0B3F)],
        coverIcon: Icons.flare_rounded,
        status: GameStatus.dropped,
        rating: 3,
        hoursPlayed: 11,
        playedOn: GamePlatform.pc,
        purchasePrice: 29.99,
        dateAdded: ago(700),
      ),
      Game(
        id: 'rdr2',
        title: 'Red Dead Redemption 2',
        publisher: 'Rockstar Games',
        developer: 'Rockstar Games',
        releaseYear: 2018,
        platforms: const [GamePlatform.pc, GamePlatform.ps4, GamePlatform.xbox],
        genres: const ['Action Adventure', 'Open World'],
        synopsis: 'Ride with a gang of outlaws through a fading Wild West in a slow-burn, meticulously detailed epic.',
        coverColors: const [Color(0xFFB5542B), Color(0xFF200D07)],
        coverIcon: Icons.park_rounded,
        status: GameStatus.dropped,
        rating: 3.5,
        hoursPlayed: 9,
        playedOn: GamePlatform.ps4,
        purchasePrice: 39.99,
        dateAdded: ago(800),
      ),

      // ── Wishlist ──
      Game(
        id: 'clair-obscur',
        title: 'Clair Obscur: Expedition 33',
        publisher: 'Kepler Interactive',
        developer: 'Sandfall Interactive',
        releaseYear: 2025,
        platforms: const [GamePlatform.pc, GamePlatform.ps5, GamePlatform.xbox],
        genres: const ['RPG', 'Turn-based'],
        synopsis: 'A painterly, turn-based RPG about an expedition racing to stop a curse that erases a new age each year.',
        coverColors: const [Color(0xFF8E7CC3), Color(0xFF17142B)],
        coverIcon: Icons.auto_awesome_rounded,
        status: GameStatus.wishlist,
        dateAdded: ago(20),
      ),
      Game(
        id: 'sekiro',
        title: 'Sekiro: Shadows Die Twice',
        publisher: 'Activision',
        developer: 'FromSoftware',
        releaseYear: 2019,
        platforms: const [GamePlatform.pc, GamePlatform.steamDeck, GamePlatform.ps4, GamePlatform.xbox],
        genres: const ['Action', 'Soulslike'],
        synopsis: 'A one-armed shinobi in a crumbling Sengoku Japan, where posture and parry decide every duel.',
        coverColors: const [Color(0xFFD6502B), Color(0xFF14110F)],
        coverIcon: Icons.sports_martial_arts_rounded,
        status: GameStatus.wishlist,
        dateAdded: ago(12),
      ),

      // ── Catalog only (Discover) ──
      Game(
        id: 'balatro',
        title: 'Balatro',
        publisher: 'Playstack',
        developer: 'LocalThunk',
        releaseYear: 2024,
        platforms: const [GamePlatform.pc, GamePlatform.steamDeck, GamePlatform.nswitch, GamePlatform.ps5, GamePlatform.xbox, GamePlatform.mobile],
        genres: const ['Roguelike', 'Card Game'],
        synopsis: 'Build absurdly powerful poker hands with jokers that bend every rule in this addictive deckbuilder.',
        coverColors: const [Color(0xFF2E7D6B), Color(0xFF3B0F2E)],
        coverIcon: Icons.casino_rounded,
      ),
      Game(
        id: 'disco-elysium',
        title: 'Disco Elysium',
        publisher: 'ZA/UM',
        developer: 'ZA/UM',
        releaseYear: 2019,
        platforms: const [GamePlatform.pc, GamePlatform.steamDeck, GamePlatform.ps5, GamePlatform.ps4, GamePlatform.xbox, GamePlatform.nswitch],
        genres: const ['RPG', 'Mystery'],
        synopsis: 'A washed-up detective with a fractured mind and a talkative skill set investigates a murder in a decaying port city.',
        coverColors: const [Color(0xFFE0A030), Color(0xFF3A1B2B)],
        coverIcon: Icons.psychology_rounded,
      ),
      Game(
        id: 'vampire-survivors',
        title: 'Vampire Survivors',
        publisher: 'poncle',
        developer: 'poncle',
        releaseYear: 2022,
        platforms: const [GamePlatform.pc, GamePlatform.steamDeck, GamePlatform.nswitch, GamePlatform.ps5, GamePlatform.xbox, GamePlatform.mobile],
        genres: const ['Roguelike', 'Action'],
        synopsis: 'Survive endless gothic hordes with weapons that fire themselves, until the screen is pure chaos.',
        coverColors: const [Color(0xFF8E1B3A), Color(0xFF0E0B1F)],
        coverIcon: Icons.nightlight_round,
      ),
    ];
  }

  /// Splits each game's hours into plausible past sessions so that the sum of
  /// a game's logs equals its `hoursPlayed`.
  static List<LogEntry> logs(List<Game> games, DateTime now) {
    final out = <LogEntry>[];
    var seq = 0;
    for (var i = 0; i < games.length; i++) {
      final g = games[i];
      if (g.hoursPlayed <= 0) continue;
      final count = g.hoursPlayed > 40 ? 5 : (g.hoursPlayed > 10 ? 4 : 3);
      var remaining = g.hoursPlayed;
      final base = g.status == GameStatus.playing ? i % 3 : 4 + i * 3;
      for (var k = 0; k < count; k++) {
        final isLast = k == count - 1;
        var share = isLast
            ? remaining
            : ((g.hoursPlayed / count * (0.8 + 0.2 * ((i + k) % 3))) * 2).round() / 2;
        if (!isLast) {
          share = share.clamp(0.5, remaining - 0.5 * (count - 1 - k)).toDouble();
        }
        remaining -= share;
        final platform = (k.isOdd && g.platforms.length > 1 && i.isEven)
            ? g.platforms.first
            : (g.playedOn ?? g.platforms.first);
        out.add(LogEntry(
          id: 'seed-${seq++}',
          gameId: g.id,
          timestamp: now.subtract(Duration(days: base + (count - 1 - k) * 6, hours: (i * 5 + k * 3) % 20)),
          hours: share,
          platform: platform,
          note: k == 0 && isLast ? '' : (k == count - 2 ? 'Finally beat that boss' : ''),
        ));
      }
    }
    return out;
  }
}