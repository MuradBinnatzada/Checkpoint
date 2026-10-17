// supabase/functions/_shared/sync_schedule.ts
//
// When the background Steam sync (sync-steam, cron mode) tries a user again.
// The outcome of each attempt is stored in `steam_sync_state.next_attempt_at`;
// the database function `steam_sync_due` only hands out users whose time has come.
//
// Pure functions, so the schedule can be tested without a database or a clock.
// Error codes are those of `ErrorCode` in sync-steam/index.ts.

const MINUTE_MS = 60_000
const HOUR_MS = 60 * MINUTE_MS
const DAY_MS = 24 * HOUR_MS

/** How often an active user's library is refreshed in the background. */
export const SYNC_INTERVAL_MS = 12 * HOUR_MS

/** After a sync IGDB only got part of the way through: come back sooner for the rest. */
export const DELAYED_RETRY_MIN_MS = 30 * MINUTE_MS

/** Steam / IGDB are limiting or down: not the user's doing, so don't wait long. */
export const UPSTREAM_RETRY_MIN_MS = 15 * MINUTE_MS

/** The user has to act (private Steam profile, no Steam ID): checking often is pointless. */
export const NEEDS_USER_RETRY_MS = 7 * DAY_MS

/** Any other failure: wait 1 h, then 2 h, 4 h ... up to a day. */
export const FAILURE_BACKOFF_BASE_MS = HOUR_MS
export const FAILURE_BACKOFF_MAX_MS = DAY_MS

/** Wait before the next background sync after one that finished. */
export function successDelayMs(delayed: boolean, retryAfterS: number | null): number {
  if (!delayed) return SYNC_INTERVAL_MS
  return Math.max(DELAYED_RETRY_MIN_MS, (retryAfterS ?? 0) * 1000)
}

export type FailureKind = 'needs_user' | 'upstream' | 'other'

export function classifyFailure(code: string): FailureKind {
  switch (code) {
    case 'NO_STEAM_ID':
    case 'STEAM_PROFILE_PRIVATE':
      return 'needs_user'
    case 'STEAM_RATE_LIMITED':
    case 'STEAM_UNAVAILABLE':
    case 'IGDB_RATE_LIMITED':
    case 'IGDB_UNAVAILABLE':
      return 'upstream'
    default:
      return 'other'
  }
}

/**
 * Wait before retrying a user whose background sync failed with `code`.
 * `failuresBefore` is their consecutive failures so far. `countsAsFailure` is false
 * when the cause was Steam / IGDB rather than the user, so an outage does not push
 * every user's retries out to a day.
 */
export function failureDelayMs(
  code: string,
  failuresBefore: number,
  retryAfterS: number | null,
): { delayMs: number; countsAsFailure: boolean } {
  const hintMs = (retryAfterS ?? 0) * 1000
  switch (classifyFailure(code)) {
    case 'needs_user':
      return { delayMs: NEEDS_USER_RETRY_MS, countsAsFailure: true }
    case 'upstream':
      return { delayMs: Math.max(UPSTREAM_RETRY_MIN_MS, hintMs), countsAsFailure: false }
    case 'other': {
      const backoff = Math.min(FAILURE_BACKOFF_MAX_MS, FAILURE_BACKOFF_BASE_MS * 2 ** Math.max(0, failuresBefore))
      return { delayMs: Math.max(backoff, hintMs), countsAsFailure: true }
    }
  }
}

/**
 * Whether a failure says every remaining user would fail the same way (Steam is
 * limiting us or down, or the function is missing a secret): the batch ends, and
 * the rest wait for the next run instead of each spending a request on it.
 */
export function shouldStopBatch(code: string): boolean {
  return code === 'STEAM_RATE_LIMITED' || code === 'STEAM_UNAVAILABLE' || code === 'NOT_CONFIGURED'
}
