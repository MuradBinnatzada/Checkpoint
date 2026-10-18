import { assertEquals, assertStringIncludes } from 'jsr:@std/assert@1'
import {
  discoverQuery,
  FILTERED_TOP_RATED_MIN_RATINGS,
  filterConditions,
  filteredSearchQuery,
  type GameFilters,
  hasFilters,
  isDiscoverSort,
  MAX_FILTER_IDS,
  NO_FILTERS,
  parseGameFilters,
  startOfYear,
} from './game_filters.ts'

const FIELDS = 'name, cover.url'
const NOW = 1_800_000_000

function filters(value: unknown): GameFilters {
  const parsed = parseGameFilters(value)
  if (typeof parsed === 'string') throw new Error(parsed)
  return parsed
}

Deno.test('no filters object, or empty kinds, means no filters', () => {
  assertEquals(parseGameFilters(undefined), NO_FILTERS)
  assertEquals(parseGameFilters(null), NO_FILTERS)
  assertEquals(filters({}), NO_FILTERS)
  assertEquals(filters({ genres: [], themes: null, year: {} }), NO_FILTERS)
  assertEquals(hasFilters(NO_FILTERS), false)
})

Deno.test('parseGameFilters keeps each kind, without repeats', () => {
  assertEquals(
    filters({ genres: [12, 31, 12], themes: [19], game_modes: [1], platforms: [6, 14], year: { from: 2010, to: 2019 } }),
    { genres: [12, 31], themes: [19], game_modes: [1], platforms: [6, 14], year: { from: 2010, to: 2019 } },
  )
  assertEquals(hasFilters(filters({ themes: [19] })), true)
  assertEquals(hasFilters(filters({ year: { to: 1999 } })), true)
})

Deno.test('parseGameFilters refuses anything but lists of positive whole numbers', () => {
  const tooMany = Array.from({ length: MAX_FILTER_IDS + 1 }, (_, i) => i + 1)
  for (const bad of [[0], [-3], [1.5], ['12'], [null], '12', 12, { 0: 12 }, tooMany, [Number.MAX_SAFE_INTEGER + 1]]) {
    const parsed = parseGameFilters({ genres: bad })
    assertEquals(typeof parsed, 'string', JSON.stringify(bad))
    assertStringIncludes(parsed as string, 'filters.genres')
  }
  for (const bad of ['genres', [12], 12, true]) {
    assertEquals(typeof parseGameFilters(bad), 'string', JSON.stringify(bad))
  }
})

Deno.test('parseGameFilters refuses years out of range, fractional or the wrong way round', () => {
  for (const bad of [{ from: 1949 }, { to: 2101 }, { from: 2000.5 }, { from: '2000' }, [2000], 2000]) {
    assertEquals(typeof parseGameFilters({ year: bad }), 'string', JSON.stringify(bad))
  }
  assertStringIncludes(parseGameFilters({ year: { from: 2020, to: 2010 } }) as string, 'must not be after')
  assertEquals(filters({ year: { from: 2015, to: 2015 } }).year, { from: 2015, to: 2015 })
})

Deno.test('the conditions take any value of a kind, and every kind', () => {
  assertEquals(
    filterConditions(filters({ genres: [12, 31], game_modes: [3], platforms: [6, 14, 3, 13] })),
    ['genres = (12,31)', 'game_modes = (3)', 'platforms = (6,14,3,13)'],
  )
  assertEquals(filterConditions(NO_FILTERS), [])
})

Deno.test('a year range covers whole years, in UTC', () => {
  assertEquals(startOfYear(1970), 0)
  assertEquals(startOfYear(2020), 1_577_836_800)
  assertEquals(filterConditions(filters({ year: { from: 2010, to: 2019 } })), [
    `first_release_date >= ${startOfYear(2010)}`,
    `first_release_date < ${startOfYear(2020)}`,
  ])
  assertEquals(filterConditions(filters({ year: { to: 1999 } })), [`first_release_date < ${startOfYear(2000)}`])
})

Deno.test('a filtered search keeps IGDB relevance and adds the conditions', () => {
  assertEquals(
    filteredSearchQuery(FIELDS, 'zelda', filters({ platforms: [130] }), 20, 40),
    `search "zelda"; fields ${FIELDS}; where platforms = (130); limit 20; offset 40;`,
  )
  // Without filters it is the plain search the handler always made.
  assertEquals(
    filteredSearchQuery(FIELDS, 'zelda', NO_FILTERS, 20, 0),
    `search "zelda"; fields ${FIELDS}; limit 20; offset 0;`,
  )
})

Deno.test('a filtered browse lists main games with a cover, in the sort asked', () => {
  const horror = filters({ themes: [19] })
  const tail = 'cover != null & parent_game = null & version_parent = null'
  assertEquals(
    discoverQuery(FIELDS, horror, 'popular', 30, 0, NOW),
    `fields ${FIELDS}; where themes = (19) & total_rating_count != null & ${tail}; ` +
      'sort total_rating_count desc; limit 30; offset 0;',
  )
  assertEquals(
    discoverQuery(FIELDS, horror, 'top_rated', 30, 30, NOW),
    `fields ${FIELDS}; where themes = (19) & total_rating_count > ${FILTERED_TOP_RATED_MIN_RATINGS} & ${tail}; ` +
      'sort total_rating desc; limit 30; offset 30;',
  )
  assertEquals(
    discoverQuery(FIELDS, horror, 'newest', 30, 0, NOW),
    `fields ${FIELDS}; where themes = (19) & first_release_date <= ${NOW} & ${tail}; ` +
      'sort first_release_date desc; limit 30; offset 0;',
  )
  assertEquals(
    discoverQuery(FIELDS, horror, 'oldest', 30, 0, NOW),
    `fields ${FIELDS}; where themes = (19) & first_release_date != null & ${tail}; ` +
      'sort first_release_date asc; limit 30; offset 0;',
  )
})

Deno.test('isDiscoverSort accepts the four sorts and nothing else', () => {
  for (const sort of ['popular', 'top_rated', 'newest', 'oldest']) assertEquals(isDiscoverSort(sort), true)
  for (const other of ['Popular', 'new_releases', '', null, undefined, 1, ['popular']]) {
    assertEquals(isDiscoverSort(other), false, String(other))
  }
})
