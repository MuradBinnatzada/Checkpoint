import { assertEquals } from 'jsr:@std/assert@1'
import { MIN_SESSION_MINUTES, playtimeUpdates, sessionTimeMs, steamSessionPlatform } from './steam_sessions.ts'

const NOW = Date.UTC(2026, 9, 19, 12)
const YESTERDAY_S = (NOW - 24 * 3600_000) / 1000

Deno.test('more playtime than the baseline is logged as a session, dated when it was last played', () => {
  const updates = playtimeUpdates(
    [{ gameId: 'g1', minutes: 1290, lastPlayed: YESTERDAY_S }],
    new Map([['g1', 1200]]),
    NOW,
  )
  assertEquals(updates, [{
    gameId: 'g1',
    baseline: 1290,
    session: { hours: 1.5, loggedAt: new Date(YESTERDAY_S * 1000).toISOString() },
  }])
})

Deno.test('the first playtime seen is only a baseline: it is the whole history, not a session', () => {
  const updates = playtimeUpdates(
    [
      { gameId: 'new', minutes: 6000, lastPlayed: YESTERDAY_S },
      { gameId: 'old', minutes: 300, lastPlayed: 0 },
    ],
    new Map([['old', null]]),
    NOW,
  )
  assertEquals(updates, [
    { gameId: 'new', baseline: 6000, session: null },
    { gameId: 'old', baseline: 300, session: null },
  ])
})

Deno.test('a few minutes wait for the next sync instead of being dropped', () => {
  const short = playtimeUpdates(
    [{ gameId: 'g1', minutes: 1200 + MIN_SESSION_MINUTES - 1, lastPlayed: 0 }],
    new Map([['g1', 1200]]),
    NOW,
  )
  assertEquals(short, [])

  const later = playtimeUpdates(
    [{ gameId: 'g1', minutes: 1210, lastPlayed: 0 }],
    new Map([['g1', 1200]]),
    NOW,
  )
  assertEquals(later[0].session?.hours, 0.17)
})

Deno.test('unchanged playtime writes nothing, and a playtime Steam lowered is the new baseline', () => {
  assertEquals(playtimeUpdates([{ gameId: 'g1', minutes: 50, lastPlayed: 0 }], new Map([['g1', 50]]), NOW), [])
  assertEquals(
    playtimeUpdates([{ gameId: 'g1', minutes: 40, lastPlayed: 0 }], new Map([['g1', 50]]), NOW),
    [{ gameId: 'g1', baseline: 40, session: null }],
  )
})

Deno.test('a session is dated now when Steam has no date, or one in the future', () => {
  assertEquals(sessionTimeMs(0, NOW), NOW)
  assertEquals(sessionTimeMs(NOW / 1000 + 3600, NOW), NOW)
  assertEquals(sessionTimeMs(YESTERDAY_S, NOW), YESTERDAY_S * 1000)
})

Deno.test('Steam sessions are on PC unless the game is played on the Steam Deck', () => {
  assertEquals(steamSessionPlatform('steamDeck'), 'steamDeck')
  assertEquals(steamSessionPlatform('pc'), 'pc')
  assertEquals(steamSessionPlatform(null), 'pc')
  assertEquals(steamSessionPlatform('ps5'), 'pc')
})
