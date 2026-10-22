import { assertEquals, assertStringIncludes } from 'jsr:@std/assert@1'
import {
  backfillGame,
  backfillQuery,
  CATALOG_FIELDS,
  type CatalogRow,
  catalogPatch,
  companiesByRole,
  DETAIL_FIELDS,
  detailsQuery,
  firstRow,
  gamesById,
  isDue,
  MAX_BACKFILL_IDS,
  names,
  parseIgdbId,
  parseIgdbIds,
  planBackfill,
  releaseDate,
  REFRESH_AFTER_DAYS,
} from './game_details.ts'

const NOW_ISO = '2026-10-18T12:00:00.000Z'

// Skyrim as IGDB answers for it (trimmed).
const skyrim = {
  id: 472,
  name: 'The Elder Scrolls V: Skyrim',
  platforms: [{ id: 6, name: 'PC (Microsoft Windows)' }, { id: 9, name: 'PlayStation 3' }, { id: 12, name: 'Xbox 360' }],
  genres: [{ name: 'Role-playing (RPG)' }, { name: 'Adventure' }],
  themes: [{ name: 'Action' }, { name: 'Fantasy' }, { name: 'Stealth' }, { name: 'Sandbox' }, { name: 'Open world' }],
  game_modes: [{ name: 'Single player' }],
  player_perspectives: [{ name: 'First person' }, { name: 'Third person' }],
  game_engines: [{ name: 'Creation Engine' }],
  involved_companies: [
    { developer: true, publisher: false, company: { name: 'Bethesda Game Studios' } },
    { developer: false, publisher: true, company: { name: 'Bethesda Softworks' } },
    { developer: true, publisher: false, supporting: true, company: { name: 'Some Helper Studio' } },
  ],
}

Deno.test('parseIgdbId accepts a positive whole number and nothing else', () => {
  assertEquals(parseIgdbId(472), 472)
  for (const bad of [0, -1, 1.5, NaN, Infinity, '472', null, undefined, {}, [472], 2 ** 60]) {
    assertEquals(parseIgdbId(bad), null, String(bad))
  }
})

Deno.test('the queries splice in only the number', () => {
  assertStringIncludes(detailsQuery(472), 'where id = 472; limit 1;')
  for (const field of ['storyline', 'themes.name', 'game_modes.name', 'game_engines.name', 'similar_games.name']) {
    assertStringIncludes(detailsQuery(472), field)
  }
})

Deno.test('firstRow is the first object of a list, else null', () => {
  assertEquals(firstRow([{ a: 1 }, { a: 2 }]), { a: 1 })
  for (const other of [[], null, undefined, 'x', {}, [null], [3]]) assertEquals(firstRow(other), null, String(other))
})

Deno.test('names lists each IGDB name once, in order', () => {
  assertEquals(names([{ name: 'A' }, { name: ' B ' }, { name: 'A' }, {}, null, { name: '' }, { name: 3 }]), ['A', 'B'])
  for (const other of [undefined, null, 'x', {}]) assertEquals(names(other), [], String(other))
})

Deno.test('companiesByRole: main developers and publishers, not the supporting studios', () => {
  assertEquals(companiesByRole(skyrim.involved_companies), {
    developers: ['Bethesda Game Studios'],
    publishers: ['Bethesda Softworks'],
  })
})

Deno.test('companiesByRole: a company that both develops and publishes is in both', () => {
  assertEquals(companiesByRole([{ developer: true, publisher: true, company: { name: 'Valve' } }]), {
    developers: ['Valve'],
    publishers: ['Valve'],
  })
})

Deno.test('companiesByRole: with no flags at all the first company stands in for both', () => {
  assertEquals(companiesByRole([{ company: { name: 'First' } }, { company: { name: 'Second' } }]), {
    developers: ['First'],
    publishers: ['First'],
  })
  assertEquals(companiesByRole(undefined), { developers: [], publishers: [] })
  assertEquals(companiesByRole([{ developer: true, company: {} }]), { developers: [], publishers: [] })
})

Deno.test('catalogPatch fills the row from IGDB, with the exact platforms', () => {
  assertEquals(catalogPatch(skyrim, false, NOW_ISO), {
    igdb_synced_at: NOW_ISO,
    platforms: ['pc', 'ps3', 'xbox360'],
    genres: ['Role-playing (RPG)', 'Adventure'],
    themes: ['Action', 'Fantasy', 'Stealth', 'Sandbox', 'Open world'],
    game_modes: ['Single player'],
    player_perspectives: ['First person', 'Third person'],
    game_engines: ['Creation Engine'],
    developers: ['Bethesda Game Studios'],
    developer: 'Bethesda Game Studios',
    publishers: ['Bethesda Softworks'],
    publisher: 'Bethesda Softworks',
  })
})

Deno.test('catalogPatch never empties what IGDB has nothing for', () => {
  assertEquals(catalogPatch({}, false, NOW_ISO), { igdb_synced_at: NOW_ISO })
  // 82 = Web browser: not a platform the app has.
  assertEquals(catalogPatch({ platforms: [{ id: 82 }] }, false, NOW_ISO), { igdb_synced_at: NOW_ISO })
})

Deno.test('a game imported from Steam keeps PC first, even when IGDB does not list it', () => {
  const consoleOnly = { platforms: [{ id: 9 }, { id: 12 }] }
  assertEquals(catalogPatch(consoleOnly, true, NOW_ISO).platforms, ['pc', 'ps3', 'xbox360'])
  assertEquals(catalogPatch(consoleOnly, false, NOW_ISO).platforms, ['ps3', 'xbox360'])
})

Deno.test('catalogPatch caps each list below the table limit of 50', () => {
  const many = Array.from({ length: 80 }, (_, i) => ({ name: `Theme ${i}` }))
  assertEquals((catalogPatch({ themes: many }, false, NOW_ISO).themes as string[]).length, 30)
})

Deno.test('a row is due again after a week, or when it was never filled in', () => {
  const now = Date.parse(NOW_ISO)
  const daysAgo = (d: number) => new Date(now - d * 86_400_000).toISOString()
  assertEquals(isDue(null, now), true)
  assertEquals(isDue('not a date', now), true)
  assertEquals(isDue(daysAgo(1), now), false)
  assertEquals(isDue(daysAgo(REFRESH_AFTER_DAYS), now), true)
})

// ---- backfill ----

const row = (igdbId: number, overrides: Partial<CatalogRow> = {}): CatalogRow => ({
  id: `00000000-0000-4000-8000-${String(igdbId).padStart(12, '0')}`,
  igdb_id: igdbId,
  steam_app_id: null,
  igdb_synced_at: null,
  platforms: ['pc'],
  genres: ['RPG'],
  ...overrides,
})

Deno.test('parseIgdbIds takes 1 to 50 positive whole numbers, once each', () => {
  assertEquals(parseIgdbIds([472, 1942, 472]), [472, 1942])
  const most = Array.from({ length: MAX_BACKFILL_IDS }, (_, i) => i + 1)
  assertEquals(parseIgdbIds(most), most)
})

Deno.test('parseIgdbIds refuses the whole list for one bad id, or a list of the wrong size', () => {
  const tooMany = Array.from({ length: MAX_BACKFILL_IDS + 1 }, (_, i) => i + 1)
  for (const bad of [[], tooMany, [472, 0], [472, '1942'], [1.5], [null], 472, '472', null, undefined, {}]) {
    assertEquals(parseIgdbIds(bad), null, JSON.stringify(bad))
  }
})

Deno.test('backfillQuery asks for the catalog fields of every id at once, and no more', () => {
  const query = backfillQuery([472, 1942, 7346])
  assertStringIncludes(query, 'where id = (472,1942,7346); limit 3;')
  for (const field of CATALOG_FIELDS) assertStringIncludes(query, field)
  for (const field of ['storyline', 'similar_games', 'summary', 'cover.url']) {
    assertEquals(query.includes(field), false, field)
  }
})

Deno.test('the details screen asks for everything the catalog keeps', () => {
  for (const field of CATALOG_FIELDS) assertStringIncludes(DETAIL_FIELDS, field)
})

Deno.test('planBackfill: due rows go to IGDB, fresh rows answer as they are, missing ids are unknown', () => {
  const now = Date.parse(NOW_ISO)
  const yesterday = new Date(now - 86_400_000).toISOString()
  const lastMonth = new Date(now - 30 * 86_400_000).toISOString()
  const plan = planBackfill(
    [1, 2, 3, 4],
    [row(1), row(2, { igdb_synced_at: yesterday }), row(3, { igdb_synced_at: lastMonth })],
    now,
  )
  assertEquals(plan.due.map((r) => r.igdb_id), [1, 3])
  assertEquals(plan.fresh.map((r) => r.igdb_id), [2])
  assertEquals(plan.unknown, [4])
})

Deno.test('planBackfill ignores rows it did not ask for, and reads an id sent as text', () => {
  const plan = planBackfill([1], [row(9), { ...row(1), igdb_id: '1' as unknown as number }, row(1)], 0)
  assertEquals(plan.due.map((r) => r.igdb_id), [1])
  assertEquals(plan.fresh, [])
  assertEquals(plan.unknown, [])
})

Deno.test('gamesById keys IGDB games by id, and is null for an answer that is not a list', () => {
  const byId = gamesById([{ id: 472, name: 'Skyrim' }, { name: 'no id' }, null, { id: -1 }])!
  assertEquals([...byId.keys()], [472])
  assertEquals(byId.get(472)?.name, 'Skyrim')
  for (const other of [null, undefined, {}, 'x']) assertEquals(gamesById(other), null, String(other))
})

Deno.test('backfillGame is what the row holds once the patch is written', () => {
  const patch = catalogPatch(skyrim, false, NOW_ISO)
  assertEquals(backfillGame(row(472, { platforms: ['playstation'] }), patch), {
    igdb_id: 472,
    platforms: ['pc', 'ps3', 'xbox360'],
    genres: ['Role-playing (RPG)', 'Adventure'],
  })
  // IGDB had nothing: the row keeps (and answers) what it had.
  assertEquals(backfillGame(row(472), catalogPatch({}, true, NOW_ISO)), {
    igdb_id: 472,
    platforms: ['pc'],
    genres: ['RPG'],
  })
  // A fresh row is answered as it is; NULL lists are empty.
  assertEquals(backfillGame(row(472, { platforms: null, genres: null })), { igdb_id: 472, platforms: [], genres: [] })
})

Deno.test('the release day is kept as the UTC date IGDB gives, when it is one the column takes', () => {
  // 2011-11-11T00:00:00Z
  assertEquals(releaseDate(1320969600), '2011-11-11')
  assertEquals(catalogPatch({ first_release_date: 1320969600 }, false, NOW_ISO).release_date, '2011-11-11')
  assertEquals(releaseDate(undefined), null)
  assertEquals(releaseDate('2011'), null)
  assertEquals(releaseDate(-2000000000), null) // 1906
  assertEquals(catalogPatch({}, false, NOW_ISO).release_date, undefined)
})
