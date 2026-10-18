// supabase/functions/_shared/steam_links.ts
//
// IGDB's own record of which IGDB game a Steam app is (`/external_games` rows
// whose source is Steam and whose `uid` is the app id). sync-steam asks this
// before it matches anything by title: a title can name several games ("Tomb
// Raider" is a 1996 game and a 2013 one, "Deadlock" is a Valve game and an
// unrelated 2021 one), an app id names one. Pure functions with no I/O, so they
// can be tested.
//
// Every value spliced into a query here is a whole number, never text from a
// caller.

/** IGDB's id for Steam among external game sources (`external_game_sources`). */
export const STEAM_SOURCE = 1

/** Most rows one IGDB request answers, and so the most app ids one query names. */
export const STEAM_LINK_BATCH = 500

/**
 * The field naming an external game's source. IGDB renamed `category` to
 * `external_game_source` and deprecated the old name, so the new one is asked
 * first and the old one only if IGDB refuses it.
 */
export type SourceField = 'external_game_source' | 'category'

/** The IGDB games of up to [STEAM_LINK_BATCH] Steam apps, in one query. */
export function steamLinksQuery(appIds: number[], field: SourceField = 'external_game_source'): string {
  const uids = appIds.map((id) => `"${Math.trunc(id)}"`).join(',')
  return `fields game, uid; where ${field} = ${STEAM_SOURCE} & uid = (${uids}); limit ${STEAM_LINK_BATCH};`
}

/**
 * IGDB's answer to [steamLinksQuery] as app id -> IGDB game ids (usually one; a
 * few apps are linked to more than one game, see [pickLinkedGame]). Rows without
 * a whole-number uid or game are skipped. Null when the answer is not a list.
 */
export function steamLinksByApp(rows: unknown): Map<number, number[]> | null {
  if (!Array.isArray(rows)) return null
  const byApp = new Map<number, number[]>()
  for (const row of rows) {
    const r = row as { uid?: unknown; game?: unknown } | null
    const app = typeof r?.uid === 'string' && /^\d+$/.test(r.uid) ? Number(r.uid) : NaN
    const game = r?.game
    if (!Number.isSafeInteger(app) || app <= 0) continue
    if (typeof game !== 'number' || !Number.isSafeInteger(game) || game <= 0) continue
    const games = byApp.get(app)
    if (!games) byApp.set(app, [game])
    else if (!games.includes(game)) games.push(game)
  }
  return byApp
}

/** What [pickLinkedGame] reads of an IGDB game. */
export interface LinkedGame {
  id: number
  name?: string
  version_parent?: number | null
}

/**
 * The game a Steam app is, among the IGDB games IGDB links it to. Nearly every app
 * has exactly one. When it has several (an edition of the game listed beside the
 * game, say), the one whose name matches the Steam title best wins ([score], 0 to
 * 1), then one that is not an edition (no `version_parent`), then the oldest IGDB
 * entry. A link is IGDB's word, so a game whose name does not match at all is
 * still taken when it is the only one.
 */
export function pickLinkedGame<T extends LinkedGame>(
  games: T[],
  score: (name: string) => number,
): T | null {
  let best: T | null = null
  let bestRank: number[] = []
  for (const g of games) {
    const rank = [g.name ? score(g.name) : 0, g.version_parent ? 0 : 1, -g.id]
    if (!best || outranks(rank, bestRank)) {
      best = g
      bestRank = rank
    }
  }
  return best
}

function outranks(a: number[], b: number[]): boolean {
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return a[i] > b[i]
  }
  return false
}
