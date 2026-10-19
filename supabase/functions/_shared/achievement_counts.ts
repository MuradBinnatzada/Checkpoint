// supabase/functions/_shared/achievement_counts.ts
//
// Achievement counts for a whole Steam library, kept by `sync-steam` in
// user_games.achievements_unlocked / achievements_total (see
// 20261018160000_steam_achievement_counts.sql) so that a profile can list every
// game with its progress without loading any game's achievements.
//
// Counting a game is one ISteamUserStats/GetPlayerAchievements request (Steam has no
// web API key call that answers for many games at once), so a sync only asks about
// the games that can have changed: played at all, with achievements (when Steam
// says), and played since the last count. Pure functions, tested on their own.

/** One owned Steam app, as far as counting its achievements goes. */
export interface CountableApp {
  appid: number
  /** The `games.id` the app resolved to. */
  gameId: string
  /** `playtime_forever`, in minutes. */
  minutes: number
  /** `rtime_last_played`, in UNIX seconds; 0 when Steam does not say. */
  lastPlayed: number
  /** `has_community_visible_stats`: Steam only sends it (true) for games with stats. */
  hasStats: boolean
}

/** A game to count, through the app that stands for it. */
export interface CountTarget {
  gameId: string
  appid: number
  /** Recorded with the count (`achievements_playtime`). */
  minutes: number
}

/**
 * The games whose achievements to count in this sync, most recently played first,
 * so that a sync that runs out of time or budget leaves the least interesting ones
 * for the next. `countedPlaytime` holds, per game, the minutes recorded when it was
 * last counted (null or missing: never): a game not played since then is skipped.
 *
 * Of two apps that are the same game (a base game and its "Complete Edition"), the
 * one played most stands for it. When no app at all says it has stats, Steam left
 * the field out, so every played game is counted rather than none.
 */
export function achievementCountTargets(
  apps: CountableApp[],
  countedPlaytime: Map<string, number | null>,
): CountTarget[] {
  const statsKnown = apps.some((a) => a.hasStats)
  const byGame = new Map<string, CountableApp>()
  for (const app of apps) {
    if (app.minutes <= 0) continue
    if (statsKnown && !app.hasStats) continue
    const current = byGame.get(app.gameId)
    if (!current || app.minutes > current.minutes) byGame.set(app.gameId, app)
  }
  return [...byGame.values()]
    .filter((app) => {
      const counted = countedPlaytime.get(app.gameId)
      return counted === undefined || counted === null || counted !== app.minutes
    })
    .sort((a, b) => b.lastPlayed - a.lastPlayed || b.minutes - a.minutes || a.appid - b.appid)
    .map((app) => ({ gameId: app.gameId, appid: app.appid, minutes: app.minutes }))
}

export type CountResult =
  | { kind: 'counted'; unlocked: number; total: number }
  /** The member's game details are not public: every other game will say the same. */
  | { kind: 'private' }
  | { kind: 'error'; status: number }

/**
 * What a GetPlayerAchievements reply (HTTP status + parsed body) says about one game.
 * A game without stats ("Requested app has no stats") counts as 0 of 0, so it is not
 * asked about again until it is played again.
 */
export function countFromPlayerAchievements(status: number, body: unknown): CountResult {
  const stats = (body as { playerstats?: Record<string, unknown> } | null)?.playerstats
  if (stats?.success === true) {
    const list = Array.isArray(stats.achievements) ? stats.achievements : []
    const unlocked = list.filter((a) => (a as { achieved?: unknown })?.achieved === 1).length
    return { kind: 'counted', unlocked, total: list.length }
  }
  const message = String(stats?.error ?? '').toLowerCase()
  if (message.includes('not public') || message.includes('private')) return { kind: 'private' }
  if (message.includes('no stats')) return { kind: 'counted', unlocked: 0, total: 0 }
  return { kind: 'error', status }
}
