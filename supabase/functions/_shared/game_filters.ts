// supabase/functions/_shared/game_filters.ts
//
// The filters of the Discover tab (genres, themes, game modes, platforms and a
// release-year range) and the IGDB (Apicalypse) queries they narrow: a text search
// with filters, and a filtered browse with no text at all. Pure functions with no
// I/O, so they can be tested.
//
// Every value spliced into a query here is a whole number checked by
// parseGameFilters, or one computed on the server; the only text is the search
// term, which the handler sanitizes. The caller picks ids and a sort from fixed
// sets, so this can't be used to run arbitrary queries against the IGDB quota.
//
// Of one kind, a game needs ANY of the picked values (`genres = (12,31)`: RPG or
// Adventure); the kinds narrow each other down (`&`). That is how the Library's
// filters combine too.

/** Most values one kind may pick: more than any filter sheet offers. */
export const MAX_FILTER_IDS = 40

/** Release years outside this range are refused (the app's own valid range). */
export const MIN_FILTER_YEAR = 1950
export const MAX_FILTER_YEAR = 2100

/** `top_rated` with filters leaves out games with this many ratings or fewer. */
export const FILTERED_TOP_RATED_MIN_RATINGS = 10

export const DISCOVER_SORTS = ['popular', 'top_rated', 'newest', 'oldest'] as const
export type DiscoverSort = (typeof DISCOVER_SORTS)[number]

export function isDiscoverSort(value: unknown): value is DiscoverSort {
  return typeof value === 'string' && (DISCOVER_SORTS as readonly string[]).includes(value)
}

/** IGDB ids per kind (empty: not filtered), and an inclusive year range (null: open). */
export type GameFilters = {
  genres: number[]
  themes: number[]
  game_modes: number[]
  platforms: number[]
  year: { from: number | null; to: number | null }
}

export const NO_FILTERS: GameFilters = {
  genres: [],
  themes: [],
  game_modes: [],
  platforms: [],
  year: { from: null, to: null },
}

const ID_KINDS = ['genres', 'themes', 'game_modes', 'platforms'] as const

/**
 * The request's `filters` object as [GameFilters], or a message saying what is
 * wrong with it. Missing (or null) means no filters; so does a missing kind. Each
 * kind is a list of up to MAX_FILTER_IDS positive whole numbers (repeats dropped);
 * `year` is `{ from?, to? }`, whole years from MIN_FILTER_YEAR to MAX_FILTER_YEAR
 * with `from` not after `to`.
 */
export function parseGameFilters(value: unknown): GameFilters | string {
  if (value === undefined || value === null) return NO_FILTERS
  if (typeof value !== 'object' || Array.isArray(value)) return '`filters` must be an object'
  const raw = value as Record<string, unknown>

  const filters: GameFilters = { ...NO_FILTERS, year: { from: null, to: null } }
  for (const kind of ID_KINDS) {
    const list = raw[kind]
    if (list === undefined || list === null) continue
    const ids = parseIds(list)
    if (ids === null) {
      return `\`filters.${kind}\` must be a list of up to ${MAX_FILTER_IDS} positive whole numbers`
    }
    filters[kind] = ids
  }

  const year = raw.year
  if (year !== undefined && year !== null) {
    if (typeof year !== 'object' || Array.isArray(year)) return '`filters.year` must be an object'
    const { from, to } = year as Record<string, unknown>
    const parsedFrom = parseYear(from)
    const parsedTo = parseYear(to)
    if (parsedFrom === undefined || parsedTo === undefined) {
      return `\`filters.year\` must give whole years from ${MIN_FILTER_YEAR} to ${MAX_FILTER_YEAR}`
    }
    if (parsedFrom !== null && parsedTo !== null && parsedFrom > parsedTo) {
      return '`filters.year.from` must not be after `filters.year.to`'
    }
    filters.year = { from: parsedFrom, to: parsedTo }
  }
  return filters
}

function parseIds(list: unknown): number[] | null {
  if (!Array.isArray(list) || list.length > MAX_FILTER_IDS) return null
  const ids = new Set<number>()
  for (const id of list) {
    if (typeof id !== 'number' || !Number.isSafeInteger(id) || id <= 0) return null
    ids.add(id)
  }
  return [...ids]
}

// A year, null when not given, undefined when malformed.
function parseYear(value: unknown): number | null | undefined {
  if (value === undefined || value === null) return null
  if (typeof value !== 'number' || !Number.isInteger(value)) return undefined
  if (value < MIN_FILTER_YEAR || value > MAX_FILTER_YEAR) return undefined
  return value
}

/** Whether [filters] narrow anything down. */
export function hasFilters(filters: GameFilters): boolean {
  return ID_KINDS.some((kind) => filters[kind].length > 0) ||
    filters.year.from !== null ||
    filters.year.to !== null
}

/** 00:00 UTC on 1 January of [year], in Unix seconds. */
export function startOfYear(year: number): number {
  return Date.UTC(year, 0, 1) / 1000
}

/** The `where` conditions of [filters], one per kind picked; none without filters. */
export function filterConditions(filters: GameFilters): string[] {
  const conditions: string[] = []
  for (const kind of ID_KINDS) {
    const ids = filters[kind]
    if (ids.length > 0) conditions.push(`${kind} = (${ids.join(',')})`)
  }
  const { from, to } = filters.year
  if (from !== null) conditions.push(`first_release_date >= ${startOfYear(from)}`)
  // Up to the end of `to`: before 1 January of the year after.
  if (to !== null) conditions.push(`first_release_date < ${startOfYear(to + 1)}`)
  return conditions
}

/**
 * A text search narrowed by [filters], without the games of [excludeIds] (the
 * title matches listed ahead of it, see game_search.ts). IGDB orders a search
 * by relevance, so there is no sort; [term] must already be sanitized for the
 * quoted string, and [excludeIds] be IGDB ids from IGDB's own answer.
 */
export function filteredSearchQuery(
  fields: string,
  term: string,
  filters: GameFilters,
  limit: number,
  offset: number,
  excludeIds: number[] = [],
): string {
  const conditions = filterConditions(filters)
  if (excludeIds.length > 0) conditions.push(`id != (${excludeIds.join(',')})`)
  const where = conditions.length > 0 ? ` where ${conditions.join(' & ')};` : ''
  return `search "${term}"; fields ${fields};${where} limit ${limit}; offset ${offset};`
}

// What a filtered browse lists, like the "Browse by" lists: games with a cover,
// without their editions (`version_parent`) or DLC and bundle parts (`parent_game`).
const DISCOVER_GAMES = 'cover != null & parent_game = null & version_parent = null'

/**
 * Games matching [filters], with no search term, in [sort] order:
 *   popular    most ratings first (IGDB's popularity ranking can't be filtered)
 *   top_rated  best total_rating, among games with more than FILTERED_TOP_RATED_MIN_RATINGS
 *   newest     latest release first, up to [nowSeconds] (no upcoming games)
 *   oldest     earliest release first
 */
export function discoverQuery(
  fields: string,
  filters: GameFilters,
  sort: DiscoverSort,
  limit: number,
  offset: number,
  nowSeconds: number,
): string {
  const [order, condition] = sortClause(sort, nowSeconds)
  const where = [...filterConditions(filters), condition, DISCOVER_GAMES].join(' & ')
  return `fields ${fields}; where ${where}; sort ${order}; limit ${limit}; offset ${offset};`
}

// The sort of [sort], and what a game needs for that order to mean anything.
function sortClause(sort: DiscoverSort, nowSeconds: number): [string, string] {
  switch (sort) {
    case 'popular':
      return ['total_rating_count desc', 'total_rating_count != null']
    case 'top_rated':
      return ['total_rating desc', `total_rating_count > ${FILTERED_TOP_RATED_MIN_RATINGS}`]
    case 'newest':
      return ['first_release_date desc', `first_release_date <= ${nowSeconds}`]
    case 'oldest':
      return ['first_release_date asc', 'first_release_date != null']
  }
}
