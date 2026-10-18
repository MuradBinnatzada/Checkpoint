import { assertEquals } from 'jsr:@std/assert@1'
import { pickLinkedGame, steamLinksByApp, steamLinksQuery } from './steam_links.ts'

Deno.test('steamLinksQuery names every app id as a Steam uid', () => {
  assertEquals(
    steamLinksQuery([203160, 1422450]),
    'fields game, uid; where external_game_source = 1 & uid = ("203160","1422450"); limit 500;',
  )
  assertEquals(
    steamLinksQuery([10], 'category'),
    'fields game, uid; where category = 1 & uid = ("10"); limit 500;',
  )
})

Deno.test('steamLinksByApp groups IGDB games by app id and skips malformed rows', () => {
  const byApp = steamLinksByApp([
    { id: 1, uid: '203160', game: 1164 },
    { id: 2, uid: '203160', game: 7201 },
    { id: 3, uid: '203160', game: 1164 }, // duplicate link
    { id: 4, uid: '1422450', game: 327_146 },
    { id: 5, uid: 'not-a-number', game: 1 },
    { id: 6, uid: '42' }, // no game
    { id: 7, uid: '43', game: -3 },
    null,
  ])
  assertEquals(byApp, new Map([[203160, [1164, 7201]], [1422450, [327_146]]]))
  assertEquals(steamLinksByApp({ message: 'error' }), null)
})

Deno.test('pickLinkedGame takes the only link even when its name differs', () => {
  const only = { id: 5, name: 'Totally Different Name' }
  assertEquals(pickLinkedGame([only], () => 0), only)
  assertEquals(pickLinkedGame([], () => 1), null)
})

Deno.test('pickLinkedGame prefers the matching name, then the base game, then the oldest entry', () => {
  const score = (name: string) => (name === 'Tomb Raider' ? 1 : 0)
  const reboot = { id: 1164, name: 'Tomb Raider' }
  const goty = { id: 7201, name: 'Tomb Raider: Game of the Year Edition', version_parent: 1164 }
  assertEquals(pickLinkedGame([goty, reboot], score), reboot)

  const edition = { id: 30, name: 'Foo: Deluxe', version_parent: 40 }
  const base = { id: 40, name: 'Foo Remake' }
  assertEquals(pickLinkedGame([edition, base], () => 0), base)

  const older = { id: 10, name: 'Bar' }
  const newer = { id: 99, name: 'Bar' }
  assertEquals(pickLinkedGame([newer, older], () => 1), older)
})
