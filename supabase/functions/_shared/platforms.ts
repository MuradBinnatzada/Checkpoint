// supabase/functions/_shared/platforms.ts
//
// Which of the app's platforms a game was released on, from IGDB's `platforms`
// array, down to the console: a PS3 and a PS4 release are two platforms, as on
// IGDB. This is the server-side twin of `_platformMap` in
// lib/services/game_api_service.dart: keep the two in step. The values are the
// strings the app stores in `games.platforms` (`gamePlatformToDb` in
// lib/models/game.dart, i.e. the `GamePlatform` enum names).
//
// Windows, Mac, Linux and DOS are all 'pc'. A few near-identical IGDB entries
// share one platform (Famicom = NES, Super Famicom = SNES, DSi = DS, New 3DS =
// 3DS, Xbox Live Arcade = Xbox 360, PS VR = PS4, PS VR2 = PS5, Sega CD and 32X =
// Genesis).
//
// Release platforms only. "steamDeck" and "emulator" are ways of playing a game
// the user picks themselves, never something a game is released on, so they are
// never produced here. The generic 'playstation' / 'xbox' / 'nintendo' / 'mobile'
// the app used to store are not produced either (only 'mobile' for IGDB's "Legacy
// Mobile Device"). An IGDB platform with no entry (web, arcade, Atari...) is left
// out rather than guessed at.
//
// Pure functions, so the mapping can be tested without IGDB.

export type PlatformDb =
  | 'pc'
  | 'ps5' | 'ps4' | 'ps3' | 'ps2' | 'ps1' | 'vita' | 'psp'
  | 'xboxSeries' | 'xboxOne' | 'xbox360' | 'xboxOriginal'
  | 'nswitch2' | 'nswitch' | 'wiiU' | 'wii' | 'gamecube' | 'n64' | 'snes' | 'nes'
  | 'n3ds' | 'nds' | 'gba' | 'gbc' | 'gameBoy' | 'virtualBoy'
  | 'dreamcast' | 'saturn' | 'genesis' | 'masterSystem' | 'gameGear'
  | 'ios' | 'android' | 'mobile'

export const IGDB_PLATFORM_TO_DB: Record<number, PlatformDb> = {
  // PC
  6: 'pc', // PC (Microsoft Windows)
  14: 'pc', // Mac
  3: 'pc', // Linux
  13: 'pc', // DOS

  // PlayStation
  7: 'ps1', // PlayStation
  8: 'ps2', // PlayStation 2
  9: 'ps3', // PlayStation 3
  48: 'ps4', // PlayStation 4
  165: 'ps4', // PlayStation VR
  167: 'ps5', // PlayStation 5
  390: 'ps5', // PlayStation VR2
  38: 'psp', // PlayStation Portable
  46: 'vita', // PlayStation Vita

  // Xbox
  11: 'xboxOriginal', // Xbox
  12: 'xbox360', // Xbox 360
  36: 'xbox360', // Xbox Live Arcade
  49: 'xboxOne', // Xbox One
  169: 'xboxSeries', // Xbox Series X|S

  // Nintendo
  18: 'nes', // Nintendo Entertainment System
  99: 'nes', // Family Computer
  51: 'nes', // Famicom Disk System
  19: 'snes', // Super Nintendo
  58: 'snes', // Super Famicom
  4: 'n64', // Nintendo 64
  21: 'gamecube', // Nintendo GameCube
  5: 'wii', // Wii
  41: 'wiiU', // Wii U
  130: 'nswitch', // Nintendo Switch
  508: 'nswitch2', // Nintendo Switch 2
  33: 'gameBoy', // Game Boy
  22: 'gbc', // Game Boy Color
  24: 'gba', // Game Boy Advance
  87: 'virtualBoy', // Virtual Boy
  20: 'nds', // Nintendo DS
  159: 'nds', // Nintendo DSi
  37: 'n3ds', // Nintendo 3DS
  137: 'n3ds', // New Nintendo 3DS

  // Sega
  64: 'masterSystem', // Sega Master System
  29: 'genesis', // Sega Mega Drive / Genesis
  78: 'genesis', // Sega CD
  30: 'genesis', // Sega 32X
  32: 'saturn', // Sega Saturn
  23: 'dreamcast', // Dreamcast
  35: 'gameGear', // Sega Game Gear

  // Mobile
  34: 'android', // Android
  39: 'ios', // iOS
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
