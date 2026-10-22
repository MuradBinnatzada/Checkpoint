// supabase/functions/_shared/game_details.ts
//
// What igdb-handler's `details` and `backfill` modes ask IGDB for, and what they
// keep of the answer: the Apicalypse queries, and the columns of the shared `games`
// catalog row that the answer fills in. Pure functions with no I/O, so they can be
// tested.
//
// Every value spliced into a query is a number, never text from the caller, so
// neither mode can be used to run arbitrary queries against the IGDB quota.

import { igdbPlatformsToDb, steamGamePlatformsToDb } from './platforms.ts'

/** What the catalog keeps of a game ([catalogPatch] reads exactly these). */
export const CATALOG_FIELDS = [
  'first_release_date',
  'platforms.id',
  'genres.name',
  'themes.name',
  'game_modes.name',
  'player_perspectives.name',
  'game_engines.name',
  'involved_companies.developer',
  'involved_companies.publisher',
  'involved_companies.supporting',
  'involved_companies.company.name',
]

/** What the details screen shows, and what the catalog keeps. */
export const DETAIL_FIELDS = [
  'name',
  'cover.url',
  'total_rating',
  'total_rating_count',
  'summary',
  'storyline',
  'platforms.name',
  ...CATALOG_FIELDS,
  // Enough of each similar game to show a card and to open its screen.
  'similar_games.name',
  'similar_games.cover.url',
  'similar_games.first_release_date',
  'similar_games.total_rating',
  'similar_games.platforms.id',
  'similar_games.genres.name',
].join(', ')

/** An IGDB id the caller sent, or null when it is not a positive whole number. */
export function parseIgdbId(value: unknown): number | null {
  return typeof value === 'number' && Number.isSafeInteger(value) && value > 0 ? value : null
}

/** One game with everything [DETAIL_FIELDS] lists. */
export function detailsQuery(igdbId: number): string {
  return `fields ${DETAIL_FIELDS}; where id = ${igdbId}; limit 1;`
}

/** The first row of an IGDB answer, or null when it is empty or not a list. */
export function firstRow(rows: unknown): Record<string, unknown> | null {
  const row = Array.isArray(rows) ? rows[0] : null
  return row !== null && typeof row === 'object' ? (row as Record<string, unknown>) : null
}

/** The `name` of each entry of an IGDB expanded list, once each, in order. */
export function names(list: unknown): string[] {
  if (!Array.isArray(list)) return []
  const seen = new Set<string>()
  for (const entry of list) {
    const name = (entry as { name?: unknown } | null)?.name
    if (typeof name === 'string' && name.trim()) seen.add(name.trim())
  }
  return [...seen]
}

/**
 * The main developers and the publishers of a game. IGDB marks each involved
 * company with `developer` / `publisher` flags and a `supporting` flag for those
 * that only helped, which are left out, as IGDB's own page does. A game none of
 * whose companies is flagged gives its first company as both.
 */
export function companiesByRole(involved: unknown): { developers: string[]; publishers: string[] } {
  if (!Array.isArray(involved)) return { developers: [], publishers: [] }
  const developers = new Set<string>()
  const publishers = new Set<string>()
  const all: string[] = []
  for (const entry of involved) {
    const e = entry as
      | { developer?: unknown; publisher?: unknown; supporting?: unknown; company?: { name?: unknown } }
      | null
    const name = typeof e?.company?.name === 'string' ? e.company.name.trim() : ''
    if (!name) continue
    all.push(name)
    if (e?.supporting === true) continue
    if (e?.developer === true) developers.add(name)
    if (e?.publisher === true) publishers.add(name)
  }
  if (developers.size === 0 && publishers.size === 0 && all.length > 0) {
    return { developers: [all[0]], publishers: [all[0]] }
  }
  return { developers: [...developers], publishers: [...publishers] }
}

/** Most entries one array column of the catalog keeps (the table caps them at 50). */
export const MAX_LIST = 30

const capped = (list: string[]): string[] => list.slice(0, MAX_LIST)

/**
 * What an IGDB game fills in on its `games` row: the exact release platforms (see
 * platforms.ts), the genres, themes, game modes, player perspectives, engines,
 * developers and publishers, and when this was done. Left out when IGDB has
 * nothing for it, so a sparse answer never empties what the row already holds.
 *
 * [onSteam]: the game is one Steam sync imported. Owning it there means it has a
 * PC release whether or not IGDB lists one, so PC leads its platforms.
 */
export function catalogPatch(
  game: Record<string, unknown>,
  onSteam: boolean,
  nowIso: string,
): Record<string, unknown> {
  const patch: Record<string, unknown> = { igdb_synced_at: nowIso }
  const platforms = onSteam ? steamGamePlatformsToDb(game.platforms) : igdbPlatformsToDb(game.platforms)
  if (platforms.length > 0) patch.platforms = capped(platforms)

  const lists: [string, string[]][] = [
    ['genres', names(game.genres)],
    ['themes', names(game.themes)],
    ['game_modes', names(game.game_modes)],
    ['player_perspectives', names(game.player_perspectives)],
    ['game_engines', names(game.game_engines)],
  ]
  for (const [column, values] of lists) if (values.length > 0) patch[column] = capped(values)

  const released = releaseDate(game.first_release_date)
  if (released !== null) patch.release_date = released

  const { developers, publishers } = companiesByRole(game.involved_companies)
  if (developers.length > 0) {
    patch.developers = capped(developers)
    patch.developer = developers[0]
  }
  if (publishers.length > 0) {
    patch.publishers = capped(publishers)
    patch.publisher = publishers[0]
  }
  return patch
}

/**
 * `games.release_date` (YYYY-MM-DD, the UTC day IGDB gives) from IGDB's
 * `first_release_date` (UNIX seconds), or null when there is none or it is not a
 * date the column can hold.
 */
export function releaseDate(seconds: unknown): string | null {
  if (typeof seconds !== 'number' || !Number.isFinite(seconds)) return null
  const day = new Date(seconds * 1000)
  const year = day.getUTCFullYear()
  if (year < 1950 || year > 2100) return null
  return day.toISOString().slice(0, 10)
}

/** A game whose catalog row was filled in less than this long ago is left alone. */
export const REFRESH_AFTER_DAYS = 7

/** Whether a row last filled in at [syncedAt] (ISO text, or null: never) is due again. */
export function isDue(syncedAt: unknown, nowMs: number): boolean {
  if (typeof syncedAt !== 'string') return true
  const at = Date.parse(syncedAt)
  return !Number.isFinite(at) || nowMs - at >= REFRESH_AFTER_DAYS * 86_400_000
}

// ---------------------------------------------------------------------------
// `backfill`: the catalog rows of many games at once
// ---------------------------------------------------------------------------

/** Most games one `backfill` request may name: one IGDB request answers them all. */
export const MAX_BACKFILL_IDS = 50

/**
 * The IGDB ids of a `backfill` request, once each, or null unless [value] is a
 * list of 1 to [MAX_BACKFILL_IDS] ids that are all positive whole numbers (see
 * [parseIgdbId]). One bad id refuses the whole request instead of being skipped,
 * so a caller's mistake shows rather than games silently never being filled in.
 */
export function parseIgdbIds(value: unknown): number[] | null {
  if (!Array.isArray(value) || value.length === 0 || value.length > MAX_BACKFILL_IDS) return null
  const ids = new Set<number>()
  for (const entry of value) {
    const id = parseIgdbId(entry)
    if (id === null) return null
    ids.add(id)
  }
  return [...ids]
}

/**
 * What the catalog keeps of each of [igdbIds] (at most [MAX_BACKFILL_IDS]), in one
 * query: no storyline or similar games, which are only for the
 * details screen. The limit is spelled out because IGDB's default is 10.
 */
export function backfillQuery(igdbIds: number[]): string {
  return `fields ${CATALOG_FIELDS.join(', ')}; where id = (${igdbIds.join(',')}); limit ${igdbIds.length};`
}

/** What `backfill` reads of a `games` row. */
export type CatalogRow = {
  id: string
  igdb_id: number
  steam_app_id: number | null
  igdb_synced_at: string | null
  platforms: string[] | null
  genres: string[] | null
}

/** The columns of [CatalogRow], for the select. */
export const CATALOG_ROW_COLUMNS = 'id, igdb_id, steam_app_id, igdb_synced_at, platforms, genres'

/**
 * Sorts the rows found for a `backfill` request: [due] ones (see [isDue]) are
 * filled in from IGDB, [fresh] ones were filled in recently enough to answer from
 * the row as it is, without asking IGDB. [unknown]: ids with no catalog row, so
 * nothing to fill in (a row is added when someone adds the game).
 */
export function planBackfill(
  igdbIds: number[],
  rows: CatalogRow[],
  nowMs: number,
): { due: CatalogRow[]; fresh: CatalogRow[]; unknown: number[] } {
  const asked = new Set(igdbIds)
  const found = new Set<number>()
  const due: CatalogRow[] = []
  const fresh: CatalogRow[] = []
  for (const row of rows) {
    const igdbId = Number(row.igdb_id)
    if (!asked.has(igdbId) || found.has(igdbId)) continue
    found.add(igdbId)
    const normalized = { ...row, igdb_id: igdbId }
    if (isDue(row.igdb_synced_at, nowMs)) due.push(normalized)
    else fresh.push(normalized)
  }
  return { due, fresh, unknown: igdbIds.filter((id) => !found.has(id)) }
}

/** The games of an IGDB answer by id; null when the answer is not a list. */
export function gamesById(rows: unknown): Map<number, Record<string, unknown>> | null {
  if (!Array.isArray(rows)) return null
  const byId = new Map<number, Record<string, unknown>>()
  for (const row of rows) {
    if (row === null || typeof row !== 'object') continue
    const id = parseIgdbId((row as { id?: unknown }).id)
    if (id !== null) byId.set(id, row as Record<string, unknown>)
  }
  return byId
}

/** What `backfill` answers for one game: what its catalog row holds now. */
export type BackfillGame = { igdb_id: number; platforms: string[]; genres: string[] }

const strings = (value: unknown): string[] =>
  Array.isArray(value) ? value.filter((v): v is string => typeof v === 'string') : []

/**
 * What [row] holds once [patch] (from [catalogPatch]) is written over it: the
 * patch's platforms and genres where it has them, the row's own otherwise, as a
 * patch leaves out what IGDB had nothing for.
 */
export function backfillGame(row: CatalogRow, patch: Record<string, unknown> = {}): BackfillGame {
  return {
    igdb_id: row.igdb_id,
    platforms: strings(patch.platforms ?? row.platforms),
    genres: strings(patch.genres ?? row.genres),
  }
}
