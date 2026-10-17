// supabase/functions/_shared/backoff.ts
//
// Retry-with-backoff for the third-party APIs the Edge Functions call (Steam,
// IGDB / Twitch), which answer HTTP 429 when we go over their rate limits.
//
// `fetchWithBackoff` waits and retries a few times, so a short burst of limiting
// is absorbed instead of surfacing as an error. It never holds the caller for long:
// when the API asks for a longer wait than `maxDelayMs`, or the retries are used
// up, the 429 itself is returned and the caller reports it (`*_RATE_LIMITED` with a
// `retry_after`), which the app shows as "Sync Delayed".

export const MAX_RETRY_AFTER_S = 3600

/**
 * A `Retry-After` header (delta-seconds or an HTTP date) as whole seconds, clamped
 * to 1..MAX_RETRY_AFTER_S. Null when absent or unreadable.
 */
export function retryAfterSeconds(value: string | null, now = Date.now()): number | null {
  if (!value) return null
  const trimmed = value.trim()
  const seconds = /^\d+$/.test(trimmed) ? Number(trimmed) : (Date.parse(trimmed) - now) / 1000
  if (!Number.isFinite(seconds)) return null
  return Math.min(Math.max(Math.ceil(seconds), 1), MAX_RETRY_AFTER_S)
}

/** `retryAfterSeconds`, or `fallback` when the header is absent or unreadable. */
export function parseRetryAfter(value: string | null, fallback = 120): number {
  return retryAfterSeconds(value) ?? fallback
}

/**
 * The wait before retry number `retry` (0 = the first retry): doubles from
 * `baseDelayMs`, capped at `maxDelayMs`, with "equal jitter" (half fixed, half
 * random) so concurrent callers spread out without a retry ever firing at once.
 */
export function backoffDelayMs(
  retry: number,
  baseDelayMs: number,
  maxDelayMs: number,
  random: () => number = Math.random,
): number {
  const ceiling = Math.min(maxDelayMs, baseDelayMs * 2 ** retry)
  return Math.round(ceiling / 2 + random() * (ceiling / 2))
}

export interface BackoffOptions {
  /** Retries after the first attempt. */
  retries: number
  /** First backoff step; doubles on every retry. */
  baseDelayMs: number
  /**
   * Longest single wait. A `Retry-After` beyond it is not waited out: the response
   * is returned so the caller can pass the hint on instead of holding the request.
   */
  maxDelayMs: number
  /** Most time all the waits together may take. Default: no limit besides `retries`. */
  budgetMs?: number
  /** Statuses worth retrying. Default: 429 only. */
  statuses?: number[]
  /** Test seams. */
  sleep?: (ms: number) => Promise<void>
  random?: () => number
}

/**
 * Runs `attempt` and, while it answers a retryable status, waits and runs it again:
 * for the `Retry-After` the API sent, else an exponential backoff. Returns the
 * first other response, or the last one once the retries or the time budget are
 * spent (so the caller still sees the 429). A network error from `attempt` is not
 * caught here.
 */
export async function fetchWithBackoff(
  attempt: () => Promise<Response>,
  options: BackoffOptions,
): Promise<Response> {
  const statuses = options.statuses ?? [429]
  const sleep = options.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)))
  const budgetMs = options.budgetMs ?? Infinity
  let waitedMs = 0

  for (let retry = 0; ; retry++) {
    const res = await attempt()
    if (!statuses.includes(res.status) || retry >= options.retries) return res

    const hinted = retryAfterSeconds(res.headers.get('Retry-After'))
    const delayMs = hinted !== null
      ? hinted * 1000
      : backoffDelayMs(retry, options.baseDelayMs, options.maxDelayMs, options.random)
    if (delayMs > options.maxDelayMs || waitedMs + delayMs > budgetMs) return res

    // The answer is being thrown away: free its connection.
    await res.body?.cancel().catch(() => {})
    waitedMs += delayMs
    await sleep(delayMs)
  }
}
