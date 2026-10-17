import { assertEquals } from 'jsr:@std/assert@1'
import { igdbPlatformsToDb, steamGamePlatformsToDb } from './platforms.ts'

Deno.test('igdbPlatformsToDb rolls consoles up into their brand and keeps IGDB order', () => {
  assertEquals(igdbPlatformsToDb([{ id: 167 }, { id: 6 }, { id: 130 }]), ['ps5', 'pc', 'nswitch'])
  assertEquals(igdbPlatformsToDb([{ id: 7 }, { id: 8 }, { id: 9 }]), ['playstation'])
  assertEquals(igdbPlatformsToDb([{ id: 6 }, { id: 14 }, { id: 3 }]), ['pc'])
  assertEquals(igdbPlatformsToDb([{ id: 48 }, { id: 165 }, { id: 390 }]), ['ps4', 'ps5'])
})

Deno.test('a mobile-only game is mobile and nothing else', () => {
  // Dream League Soccer: Android + iOS on IGDB.
  assertEquals(igdbPlatformsToDb([{ id: 34, name: 'Android' }, { id: 39, name: 'iOS' }]), ['mobile'])
})

Deno.test('Steam Deck and the emulator are never a release platform', () => {
  const all = Array.from({ length: 600 }, (_, id) => ({ id }))
  const produced = new Set<string>(igdbPlatformsToDb(all))
  assertEquals(produced.has('steamDeck'), false)
  assertEquals(produced.has('emulator'), false)
  assertEquals(produced.has('retro'), false)
})

Deno.test('platforms with no entry, and malformed ones, are skipped', () => {
  // 82 = Web browser, 52 = Arcade, 23 = Dreamcast.
  assertEquals(igdbPlatformsToDb([{ id: 82 }, { id: 52 }, { id: 23 }]), [])
  assertEquals(igdbPlatformsToDb([{ name: 'PC (Microsoft Windows)' }, null, 6, { id: '6' }, { id: 6 }]), ['pc'])
  for (const other of [undefined, null, 'pc', 6, {}]) assertEquals(igdbPlatformsToDb(other), [], String(other))
})

Deno.test('a game owned on Steam always has PC, first', () => {
  assertEquals(steamGamePlatformsToDb(undefined), ['pc'])
  assertEquals(steamGamePlatformsToDb([]), ['pc'])
  assertEquals(steamGamePlatformsToDb([{ id: 130 }, { id: 6 }, { id: 167 }]), ['pc', 'nswitch', 'ps5'])
  assertEquals(steamGamePlatformsToDb([{ id: 82 }]), ['pc'])
})
