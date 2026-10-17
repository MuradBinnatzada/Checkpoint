// supabase/functions/_shared/browse_queries.ts
//
// The IGDB (Apicalypse) queries behind igdb-handler's browse modes, the "Browse by"
// lists on the Discover screen. Pure functions with no I/O, so they can be tested.
//
// Every value spliced into a query here is a number computed on the server, never
// text from the caller. The handler's `mode` picks one of these queries, so it
// can't be used to run arbitrary ones against the IGDB quota.

export const BROWSE_MODES = ['popular', 'top_rated', 'new_releases'] as const
export type BrowseMode = (typeof BROWSE_MODES)[number]

export function isBrowseMode(value: unknown): value is BrowseMode {
  return typeof value === 'string' && (BROWSE_MODES as readonly string[]).includes(value)
}

/** `top_rated` leaves out games with this many ratings or fewer (user + critic). */
export const TOP_RATED_MIN_RATINGS = 50

/** `new_releases` covers games released within this many days up to now. */
export const NEW_RELEASES_WINDOW_DAYS = 90

/**
 * The popularity primitive `popular` ranks by: IGDB visits. It is the example in
 * IGDB's popularity docs (`GET /popularity_types` lists the others: want to play,
 * playing, played, Steam peak players...). `games.follows` would be the obvious
 * field, but IGDB has deprecated it ("to be removed").
 */
export const POPULARITY_TYPE_IGDB_VISITS = 1

const SECONDS_PER_DAY = 86_400

// Every browse list is a grid of posters, so a game needs a cover. Editions
// (`version_parent`) and DLC, expansions or bundle parts (`parent_game`) are other
// rows of a game that is already listed, so they stay out.
const BROWSE_GAMES = 'cover != null & parent_game = null & version_parent = null'

/** `top_rated`: the best average of user and critic scores, among well-rated games. */
export function topRatedQuery(fields: string, limit: number, offset: number): string {
  return `fields ${fields}; where total_rating_count > ${TOP_RATED_MIN_RATINGS} & ${BROWSE_GAMES}; ` +
    `sort total_rating desc; limit ${limit}; offset ${offset};`
}

/** `new_releases`: released in the last NEW_RELEASES_WINDOW_DAYS days, newest first. */
export function newReleasesQuery(
  fields: string,
  limit: number,
  offset: number,
  nowSeconds: number,
): string {
  const since = nowSeconds - NEW_RELEASES_WINDOW_DAYS * SECONDS_PER_DAY
  // Upcoming games have a release date too, so the window is closed at "now".
  return `fields ${fields}; ` +
    `where first_release_date >= ${since} & first_release_date <= ${nowSeconds} & ${BROWSE_GAMES}; ` +
    `sort first_release_date desc; limit ${limit}; offset ${offset};`
}

// `popular` takes two IGDB requests: /popularity_primitives ranks game ids, then
// /games answers for those ids.

/** `popular`, step 1 (POST /popularity_primitives): game ids, most popular first. */
export function popularityQuery(limit: number, offset: number): string {
  return `fields game_id, value; where popularity_type = ${POPULARITY_TYPE_IGDB_VISITS}; ` +
    `sort value desc; limit ${limit}; offset ${offset};`
}

/** `popular`, step 2 (POST /games): the games for the ids [popularityQuery] ranked. */
export function gamesByIdQuery(fields: string, ids: number[]): string {
  return `fields ${fields}; where id = (${ids.join(',')}); limit ${ids.length};`
}

/** The ids of a /popularity_primitives answer, in rank order; entries without a usable id are skipped. */
export function rankedGameIds(primitives: unknown): number[] {
  if (!Array.isArray(primitives)) return []
  const ids: number[] = []
  for (const entry of primitives) {
    const id = (entry as { game_id?: unknown } | null)?.game_id
    if (typeof id === 'number' && Number.isInteger(id) && id > 0) ids.push(id)
  }
  return ids
}

/**
 * IGDB answers `where id = (...)` in its own order, not the order asked: put the
 * games back in rank order. An id IGDB didn't return is skipped.
 */
export function inRankOrder(ids: number[], games: unknown): unknown[] {
  if (!Array.isArray(games)) return []
  const byId = new Map<number, unknown>()
  for (const game of games) {
    const id = (game as { id?: unknown } | null)?.id
    if (typeof id === 'number') byId.set(id, game)
  }
  return ids.flatMap((id) => (byId.has(id) ? [byId.get(id)] : []))
}
