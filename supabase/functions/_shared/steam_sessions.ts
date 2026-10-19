// supabase/functions/_shared/steam_sessions.ts
//
// Play sessions from Steam. Steam only says how long a game has been played in all
// (`playtime_forever`, in minutes) and when it was last played. sync-steam keeps
// the playtime it saw on the library row (`user_games.steam_playtime_minutes`), and
// a later sync that sees more logs the difference as a play session, dated when
// Steam says the game was last played. With the background sync every 12 hours, a
// session is what was played since the sync before.
//
// The first time a game's playtime is seen (a game just imported, or one synced
// before this existed) only the baseline is kept: that playtime is the game's whole
// history, not a session.
//
// Pure functions, so the rules can be tested without Steam or a database.

/** Less than this since the last session is kept for the next sync rather than logged. */
export const MIN_SESSION_MINUTES = 5

/** `log_entries_hours_range` (20261019013500_value_limits_and_atomic_deletes.sql). */
const MAX_SESSION_HOURS = 100_000

/** A library game's Steam playtime this sync, its apps added together. */
export interface PlaytimeSeen {
  gameId: string
  /** playtime_forever, in minutes */
  minutes: number
  /** rtime_last_played (UNIX seconds) of the app played last, 0 when unknown */
  lastPlayed: number
}

/** What to write for one game: its new baseline, and the session to log, if any. */
export interface PlaytimeUpdate {
  gameId: string
  /** The value for `user_games.steam_playtime_minutes`. */
  baseline: number
  session: { hours: number; loggedAt: string } | null
}

/**
 * The baselines and sessions this sync writes. [before] holds each game's stored
 * baseline: a game missing from it, or with null, has none yet. A playtime that
 * went down (Steam corrected it) becomes the new baseline without a session. A
 * rise under MIN_SESSION_MINUTES keeps the old baseline, so short plays add up to
 * a session on a later sync instead of being dropped.
 */
export function playtimeUpdates(
  seen: PlaytimeSeen[],
  before: Map<string, number | null>,
  nowMs: number,
): PlaytimeUpdate[] {
  const updates: PlaytimeUpdate[] = []
  for (const s of seen) {
    const minutes = Math.max(0, Math.round(s.minutes))
    const previous = before.get(s.gameId)
    if (previous === undefined || previous === null || minutes < previous) {
      if (previous !== minutes) updates.push({ gameId: s.gameId, baseline: minutes, session: null })
      continue
    }
    const played = minutes - previous
    if (played < MIN_SESSION_MINUTES) continue
    const hours = Math.min(MAX_SESSION_HOURS, Math.round((played / 60) * 100) / 100)
    updates.push({
      gameId: s.gameId,
      baseline: minutes,
      session: { hours, loggedAt: new Date(sessionTimeMs(s.lastPlayed, nowMs)).toISOString() },
    })
  }
  return updates
}

/** When Steam says the game was last played, or now when it doesn't (or says the future). */
export function sessionTimeMs(lastPlayed: number, nowMs: number): number {
  const at = lastPlayed * 1000
  return lastPlayed > 0 && at <= nowMs ? at : nowMs
}

/** The platform a Steam session is logged on: the Steam Deck when that is where the game is played. */
export function steamSessionPlatform(playedOn: unknown): string {
  return playedOn === 'steamDeck' ? 'steamDeck' : 'pc'
}
