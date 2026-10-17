// supabase/functions/_shared/platforms.ts
//
// Which of the app's platforms a game was released on, from IGDB's `platforms`
// array. This is the server-side twin of `_platformMap` in
// lib/services/game_api_service.dart: keep the two in step. The values are the
// strings the app stores in `games.platforms` (`gamePlatformToDb` in
// lib/models/game.dart).
//
// Release platforms only. "steamDeck" and "emulator" are ways of playing a game
// the user picks themselves, never something a game is released on, so they are
// never produced here. An IGDB platform with no entry (web, arcade, Dreamcast...)
// is left out rather than guessed at.
//
// Pure functions, so the mapping can be tested without IGDB.

export type PlatformDb =
  | 'pc'
  | 'playstation'
  | 'ps4'
  | 'ps5'
  | 'xbox'
  | 'nintendo'
  | 'nswitch'
  | 'mobile'

const IGDB_PLATFORM_TO_DB: Record<number, PlatformDb> = {
  // PC
  6: 'pc', // PC (Microsoft Windows)
  14: 'pc', // Mac
  3: 'pc', // Linux

  // PlayStation family
  7: 'playstation', // PlayStation
  8: 'playstation', // PlayStation 2
  9: 'playstation', // PlayStation 3
  38: 'playstation', // PlayStation Portable
  46: 'playstation', // PlayStation Vita
  48: 'ps4', // PlayStation 4
  165: 'ps4', // PlayStation VR
  167: 'ps5', // PlayStation 5
  390: 'ps5', // PlayStation VR2

  // Xbox family
  11: 'xbox', // Xbox
  12: 'xbox', // Xbox 360
  36: 'xbox', // Xbox Live Arcade
  49: 'xbox', // Xbox One
  169: 'xbox', // Xbox Series X|S

  // Nintendo family
  18: 'nintendo', // Nintendo Entertainment System
  99: 'nintendo', // Family Computer
  51: 'nintendo', // Famicom Disk System
  19: 'nintendo', // Super Nintendo
  58: 'nintendo', // Super Famicom
  4: 'nintendo', // Nintendo 64
  21: 'nintendo', // Nintendo GameCube
  5: 'nintendo', // Wii
  41: 'nintendo', // Wii U
  33: 'nintendo', // Game Boy
  22: 'nintendo', // Game Boy Color
  24: 'nintendo', // Game Boy Advance
  87: 'nintendo', // Virtual Boy
  20: 'nintendo', // Nintendo DS
  159: 'nintendo', // Nintendo DSi
  37: 'nintendo', // Nintendo 3DS
  137: 'nintendo', // New Nintendo 3DS
  130: 'nswitch', // Nintendo Switch
  508: 'nswitch', // Nintendo Switch 2

  // Mobile
  34: 'mobile', // Android
  39: 'mobile', // iOS
  55: 'mobile', // Legacy Mobile Device
}

/**
 * IGDB's `platforms` as the app's platform strings: known platforms only, each
 * once, in IGDB's order. Anything that isn't a well-formed `{ id }` is skipped.
 */
export function igdbPlatformsToDb(platforms: unknown): PlatformDb[] {
  if (!Array.isArray(platforms)) return []
  const result = new Set<PlatformDb>()
  for (const p of platforms) {
    const id = (p as { id?: unknown } | null)?.id
    if (typeof id !== 'number') continue
    const mapped = IGDB_PLATFORM_TO_DB[id]
    if (mapped) result.add(mapped)
  }
  return [...result]
}

/**
 * The platforms of a game found in a user's Steam library. Owning it on Steam
 * means it has a PC release, whether or not IGDB lists one, so PC always leads;
 * IGDB's other platforms follow.
 */
export function steamGamePlatformsToDb(platforms: unknown): PlatformDb[] {
  return [...new Set<PlatformDb>(['pc', ...igdbPlatformsToDb(platforms)])]
}
