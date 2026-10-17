import { assertEquals, assertStringIncludes } from 'jsr:@std/assert@1'
import {
  gamesByIdQuery,
  inRankOrder,
  isBrowseMode,
  newReleasesQuery,
  NEW_RELEASES_WINDOW_DAYS,
  popularityQuery,
  rankedGameIds,
  topRatedQuery,
  TOP_RATED_MIN_RATINGS,
} from './browse_queries.ts'

const FIELDS = 'name, cover.url'
const NOW = 1_800_000_000

Deno.test('isBrowseMode accepts the three modes and nothing else', () => {
  for (const mode of ['popular', 'top_rated', 'new_releases']) assertEquals(isBrowseMode(mode), true)
  for (const other of ['Popular', 'top-rated', '', ' popular', null, undefined, 3, {}, ['popular']]) {
    assertEquals(isBrowseMode(other), false, String(other))
  }
})

Deno.test('topRatedQuery sorts by total_rating among games with more than the minimum ratings', () => {
  assertEquals(
    topRatedQuery(FIELDS, 30, 60),
    `fields ${FIELDS}; where total_rating_count > ${TOP_RATED_MIN_RATINGS} & ` +
      'cover != null & parent_game = null & version_parent = null; ' +
      'sort total_rating desc; limit 30; offset 60;',
  )
})

Deno.test('newReleasesQuery covers the window up to now, newest first', () => {
  const since = NOW - NEW_RELEASES_WINDOW_DAYS * 86_400
  assertEquals(
    newReleasesQuery(FIELDS, 20, 0, NOW),
    `fields ${FIELDS}; where first_release_date >= ${since} & first_release_date <= ${NOW} & ` +
      'cover != null & parent_game = null & version_parent = null; ' +
      'sort first_release_date desc; limit 20; offset 0;',
  )
})

Deno.test('newReleasesQuery moves its window with the clock', () => {
  const later = newReleasesQuery(FIELDS, 20, 0, NOW + 86_400)
  assertStringIncludes(later, `first_release_date <= ${NOW + 86_400}`)
  assertStringIncludes(later, `first_release_date >= ${NOW + 86_400 - NEW_RELEASES_WINDOW_DAYS * 86_400}`)
})

Deno.test('popularity ranks game ids by IGDB visits; the games are then fetched by id', () => {
  assertEquals(
    popularityQuery(30, 30),
    'fields game_id, value; where popularity_type = 1; sort value desc; limit 30; offset 30;',
  )
  assertEquals(
    gamesByIdQuery(FIELDS, [121, 1244, 7]),
    `fields ${FIELDS}; where id = (121,1244,7); limit 3;`,
  )
})

Deno.test('rankedGameIds keeps the order and skips entries without a usable id', () => {
  assertEquals(
    rankedGameIds([
      { game_id: 121, value: 0.6 },
      { game_id: '1244' },
      null,
      {},
      { game_id: 0 },
      { game_id: -4 },
      { game_id: 1.5 },
      { game_id: 7 },
    ]),
    [121, 7],
  )
  assertEquals(rankedGameIds(null), [])
  assertEquals(rankedGameIds({ error: 'x' }), [])
})

Deno.test('inRankOrder puts games back in the order of the ids and skips missing ones', () => {
  const games = [{ id: 7, name: 'c' }, { id: 121, name: 'a' }, { id: 1244, name: 'b' }]
  assertEquals(inRankOrder([121, 1244, 7], games).map((g) => (g as { name: string }).name), ['a', 'b', 'c'])
  assertEquals(inRankOrder([121, 999, 7], games).map((g) => (g as { id: number }).id), [121, 7])
  assertEquals(inRankOrder([121], null), [])
  assertEquals(inRankOrder([], games), [])
})
