import { assertEquals } from 'jsr:@std/assert@1'
import { igdbPlatformsToDb, steamGamePlatformsToDb } from './platforms.ts'

Deno.test('igdbPlatformsToDb keeps each console apart and keeps IGDB order', () => {
  assertEquals(igdbPlatformsToDb([{ id: 167 }, { id: 6 }, { id: 130 }]), ['ps5', 'pc', 'nswitch'])
  assertEquals(igdbPlatformsToDb([{ id: 7 }, { id: 8 }, { id: 9 }]), ['ps1', 'ps2', 'ps3'])
  assertEquals(igdbPlatformsToDb([{ id: 6 }, { id: 14 }, { id: 3 }, { id: 13 }]), ['pc'])
  assertEquals(igdbPlatformsToDb([{ id: 48 }, { id: 165 }, { id: 390 }]), ['ps4', 'ps5'])
})

Deno.test('Skyrim: PC, PlayStation 3 and Xbox 360, exactly', () => {
  // IGDB lists Skyrim on exactly these three.
  assertEquals(igdbPlatformsToDb([{ id: 6 }, { id: 9 }, { id: 12 }]), ['pc', 'ps3', 'xbox360'])
})

Deno.test('near-identical IGDB entries share one platform', () => {
  assertEquals(igdbPlatformsToDb([{ id: 18 }, { id: 99 }, { id: 51 }]), ['nes'])
  assertEquals(igdbPlatformsToDb([{ id: 19 }, { id: 58 }]), ['snes'])
  assertEquals(igdbPlatformsToDb([{ id: 20 }, { id: 159 }]), ['nds'])
  assertEquals(igdbPlatformsToDb([{ id: 37 }, { id: 137 }]), ['n3ds'])
  assertEquals(igdbPlatformsToDb([{ id: 12 }, { id: 36 }]), ['xbox360'])
  assertEquals(igdbPlatformsToDb([{ id: 29 }, { id: 78 }, { id: 30 }]), ['genesis'])
})

Deno.test('Nintendo, Xbox and Sega consoles are named one by one', () => {
  assertEquals(igdbPlatformsToDb([{ id: 41 }, { id: 5 }, { id: 21 }, { id: 4 }]), ['wiiU', 'wii', 'gamecube', 'n64'])
  assertEquals(igdbPlatformsToDb([{ id: 11 }, { id: 12 }, { id: 49 }, { id: 169 }]), [
    'xboxOriginal',
    'xbox360',
    'xboxOne',
    'xboxSeries',
  ])
  assertEquals(igdbPlatformsToDb([{ id: 23 }, { id: 32 }, { id: 64 }, { id: 35 }]), [
    'dreamcast',
    'saturn',
    'masterSystem',
    'gameGear',
  ])
})

Deno.test('a mobile-only game is Android and iOS, not "mobile"', () => {
  // Dream League Soccer: Android + iOS on IGDB.
  assertEquals(igdbPlatformsToDb([{ id: 34, name: 'Android' }, { id: 39, name: 'iOS' }]), ['android', 'ios'])
  assertEquals(igdbPlatformsToDb([{ id: 55 }]), ['mobile'])
})

Deno.test('Steam Deck and the emulator are never a release platform', () => {
  const all = Array.from({ length: 600 }, (_, id) => ({ id }))
  const produced = new Set<string>(igdbPlatformsToDb(all))
  assertEquals(produced.has('steamDeck'), false)
  assertEquals(produced.has('emulator'), false)
  assertEquals(produced.has('retro'), false)
})

Deno.test('platforms with no entry, and malformed ones, are skipped', () => {
  // 82 = Web browser, 52 = Arcade, 59 = Atari 2600.
  assertEquals(igdbPlatformsToDb([{ id: 82 }, { id: 52 }, { id: 59 }]), [])
  assertEquals(igdbPlatformsToDb([{ name: 'PC (Microsoft Windows)' }, null, 6, { id: '6' }, { id: 6 }]), ['pc'])
  for (const other of [undefined, null, 'pc', 6, {}]) assertEquals(igdbPlatformsToDb(other), [], String(other))
})

Deno.test('a game owned on Steam always has PC, first', () => {
  assertEquals(steamGamePlatformsToDb(undefined), ['pc'])
  assertEquals(steamGamePlatformsToDb([]), ['pc'])
  assertEquals(steamGamePlatformsToDb([{ id: 130 }, { id: 6 }, { id: 167 }]), ['pc', 'nswitch', 'ps5'])
  assertEquals(steamGamePlatformsToDb([{ id: 9 }, { id: 6 }, { id: 12 }]), ['pc', 'ps3', 'xbox360'])
  assertEquals(steamGamePlatformsToDb([{ id: 82 }]), ['pc'])
})
