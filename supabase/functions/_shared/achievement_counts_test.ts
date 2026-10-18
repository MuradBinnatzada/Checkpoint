import { assertEquals } from 'jsr:@std/assert@1'
import {
  achievementCountTargets,
  type CountableApp,
  countFromPlayerAchievements,
} from './achievement_counts.ts'

const app = (over: Partial<CountableApp>): CountableApp => ({
  appid: 1,
  gameId: 'g1',
  minutes: 60,
  lastPlayed: 0,
  hasStats: true,
  ...over,
})

Deno.test('only played games with stats are counted, most recently played first', () => {
  const targets = achievementCountTargets(
    [
      app({ appid: 1, gameId: 'old', lastPlayed: 100 }),
      app({ appid: 2, gameId: 'new', lastPlayed: 300 }),
      app({ appid: 3, gameId: 'never-played', minutes: 0, lastPlayed: 500 }),
      app({ appid: 4, gameId: 'no-stats', hasStats: false, lastPlayed: 400 }),
    ],
    new Map(),
  )
  assertEquals(targets, [
    { gameId: 'new', appid: 2, minutes: 60 },
    { gameId: 'old', appid: 1, minutes: 60 },
  ])
})

Deno.test('a game not played since it was counted is skipped', () => {
  const targets = achievementCountTargets(
    [
      app({ appid: 1, gameId: 'same', minutes: 90 }),
      app({ appid: 2, gameId: 'played-more', minutes: 120 }),
      app({ appid: 3, gameId: 'never-counted', minutes: 30 }),
      app({ appid: 4, gameId: 'new-to-library', minutes: 10 }),
    ],
    new Map<string, number | null>([
      ['same', 90],
      ['played-more', 100],
      ['never-counted', null],
    ]),
  )
  assertEquals(targets.map((t) => t.gameId).sort(), ['never-counted', 'new-to-library', 'played-more'])
})

Deno.test('two apps of one game are counted once, through the one played most', () => {
  const targets = achievementCountTargets(
    [
      app({ appid: 10, gameId: 'witcher', minutes: 30 }),
      app({ appid: 11, gameId: 'witcher', minutes: 600 }),
    ],
    new Map(),
  )
  assertEquals(targets, [{ gameId: 'witcher', appid: 11, minutes: 600 }])
})

Deno.test('when Steam says nothing about stats, every played game is counted', () => {
  const targets = achievementCountTargets(
    [app({ appid: 1, gameId: 'a', hasStats: false }), app({ appid: 2, gameId: 'b', hasStats: false })],
    new Map(),
  )
  assertEquals(targets.length, 2)
})

Deno.test('a reply is read as a count, a private profile or an error', () => {
  assertEquals(
    countFromPlayerAchievements(200, {
      playerstats: {
        success: true,
        achievements: [
          { apiname: 'A', achieved: 1, unlocktime: 1 },
          { apiname: 'B', achieved: 0, unlocktime: 0 },
          { apiname: 'C', achieved: 1, unlocktime: 2 },
        ],
      },
    }),
    { kind: 'counted', unlocked: 2, total: 3 },
  )
  // Stats but no achievements.
  assertEquals(countFromPlayerAchievements(200, { playerstats: { success: true } }), {
    kind: 'counted',
    unlocked: 0,
    total: 0,
  })
  assertEquals(
    countFromPlayerAchievements(400, { playerstats: { error: 'Requested app has no stats', success: false } }),
    { kind: 'counted', unlocked: 0, total: 0 },
  )
  assertEquals(
    countFromPlayerAchievements(403, { playerstats: { error: 'Profile is not public', success: false } }),
    { kind: 'private' },
  )
  assertEquals(countFromPlayerAchievements(429, null), { kind: 'error', status: 429 })
  assertEquals(countFromPlayerAchievements(500, { playerstats: {} }), { kind: 'error', status: 500 })
})
