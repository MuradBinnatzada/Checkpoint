/**
 * sync-achievements — on-demand Steam achievements for ONE game.
 *
 * POST { game_id, user_id? }   (the caller is identified by their Supabase JWT)
 *   Without `user_id` (or with the caller's own id) it loads the caller's
 *   achievements. With another member's `user_id` it loads THEIRS, for their
 *   profile: the game must be in their library, they must have a Steam ID on
 *   their profile, and they must not have turned off "Show Steam Achievements"
 *   (`profiles.show_steam_achievements`, see
 *   20261018210000_steam_achievements_privacy.sql). A `steam_id` sent in the
 *   request body is always ignored: the
 *   Steam ID is read from `profiles.steam_id` of the member whose achievements
 *   these are, so nobody can attach someone else's Steam account to a profile.
 *
 *   Another member's list is what Steam shows anyone on their public Steam
 *   profile, and members can already read each other's stored lists
 *   (`public_game_achievements`), so this hands out nothing new; it only fetches
 *   a game they never opened themselves. Their row is updated with what Steam
 *   says (nothing the caller sends is written), and a list fetched in the last
 *   OTHERS_REFRESH_MS is answered from the database instead of asking Steam again,
 *   so viewers can't make the function hammer Steam.
 *
 *   0. Profile: for another member, check they share their achievements; then look
 *      up the member's `profiles.steam_id`
 *   1. game_id → Steam app id: `games.steam_app_id`, or (a legacy Steam-keyed
 *      row that sync-steam hasn't adopted yet) decoded from its `57e40000-…` id
 *   2. ISteamUserStats/GetSchemaForGame/v2     → the game's global achievement
 *      dictionary (names, descriptions, icons)
 *   3. ISteamUserStats/GetPlayerAchievements/v0001 → this player's unlock flags
 *      and timestamps
 *   4. ISteamUserStats/GetGlobalAchievementPercentagesForApp/v0002 → how many
 *      players have each one (optional: left out when Steam doesn't answer)
 *   5. Merge them into one array, save it to user_games.achievements (JSONB)
 *      for this user + game, and return it. The database trigger keeps
 *      `achievements_unlocked` / `achievements_total` / `achievements_synced_at`
 *      in step (20261018160000_steam_achievement_counts.sql).
 *
 * Response: { success: true, achievements: [
 *   { name, description, icon_url, unlocked, unlocked_at, global_percent } ] }
 *   - `[]` means the game has no Steam achievements (stored as `[]`, not NULL,
 *     so the app doesn't offer to load them again).
 *   - `global_percent` is null when Steam's global stats were unavailable.
 *
 * A failed request is `{ error, code, retry_after? }` with a matching HTTP status
 * and, when a retry makes sense, a `Retry-After` header; see `ErrorCode`.
 *
 * Secrets: STEAM_API_KEY. (SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are
 * injected automatically.)
 *
 * Requires the 20261012120000_add_achievements_to_user_games.sql migration
 * (note: that file currently holds the steam_id migration; 20261016120000 adds
 * the `achievements` column if it is missing) and
 * 20261016120000_unify_game_ids_on_igdb_id.sql (`games.steam_app_id`).
 */
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.4"
import { type BackoffOptions, fetchWithBackoff, parseRetryAfter } from '../_shared/backoff.ts'
import { withCors } from '../_shared/cors.ts'
import { secondFactorMissing } from '../_shared/mfa.ts'
import { RATE_LIMITS, rateLimitWait } from '../_shared/rate_limit.ts'

const STEAM_API = 'https://api.steampowered.com'

/** How long another member's stored list is answered as is, without asking Steam. */
const OTHERS_REFRESH_MS = 10 * 60 * 1000

/**
 * Machine-readable failure codes; the app keys off `code`, not the `error` text.
 * Same scheme as `sync-steam` (see `SyncFailureCode` in lib/services/sync_failure.dart).
 *   Retry later: STEAM_RATE_LIMITED, STEAM_UNAVAILABLE, RATE_LIMITED (this member
 *                made too many requests, _shared/rate_limit.ts)
 *   Needs the user: UNAUTHENTICATED, MFA_REQUIRED (_shared/mfa.ts), NO_STEAM_ID, STEAM_PROFILE_PRIVATE,
 *                   GAME_NOT_LINKED, NOT_IN_LIBRARY, ACHIEVEMENTS_HIDDEN, BAD_REQUEST
 *   Needs the owner: NOT_CONFIGURED, STEAM_ERROR, INTERNAL
 */
type ErrorCode =
  | 'UNAUTHENTICATED'
  | 'MFA_REQUIRED'
  | 'NO_STEAM_ID'
  | 'STEAM_PROFILE_PRIVATE'
  | 'STEAM_RATE_LIMITED'
  | 'STEAM_UNAVAILABLE'
  | 'RATE_LIMITED'
  | 'STEAM_ERROR'
  | 'GAME_NOT_LINKED'
  | 'NOT_IN_LIBRARY'
  | 'ACHIEVEMENTS_HIDDEN'
  | 'BAD_REQUEST'
  | 'NOT_CONFIGURED'
  | 'INTERNAL'

class HttpError extends Error {
  status: number
  code: ErrorCode
  retryAfter?: number // seconds
  constructor(status: number, code: ErrorCode, message: string, retryAfter?: number) {
    super(message)
    this.status = status
    this.code = code
    this.retryAfter = retryAfter
  }
}

const DEFAULT_RETRY_AFTER_S = 120

// The user is waiting on this, so a Steam 429 is retried only briefly (two retries,
// at most ~6 s of waiting); past that it is reported as STEAM_RATE_LIMITED.
const STEAM_BACKOFF: BackoffOptions = { retries: 2, baseDelayMs: 1_000, maxDelayMs: 4_000, budgetMs: 6_000 }

/** The error for a non-OK Steam reply: rate limited, down, or something else. */
function steamStatusError(status: number, retryAfter: string | null, what: string): HttpError {
  if (status === 429) {
    return new HttpError(429, 'STEAM_RATE_LIMITED', 'Steam is limiting requests right now', parseRetryAfter(retryAfter, 300))
  }
  if (status >= 500) {
    return new HttpError(503, 'STEAM_UNAVAILABLE', `Steam is unavailable right now (${status})`, parseRetryAfter(retryAfter))
  }
  return new HttpError(502, 'STEAM_ERROR', `${what} (${status})`)
}

// ---- BEGIN PURE HELPERS ----------------------------------------------------

/**
 * Legacy rows only: `57e40000-0000-0000-0000-000000001086` → app id `1086`.
 * Games are now keyed by IGDB id and carry their app id in `games.steam_app_id`.
 */
const STEAM_UUID_RE = /^57e40000-0000-0000-0000-(\d{12})$/i
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

interface SchemaAchievement {
  name: string // API name, the join key with the player's achievements
  displayName?: string
  description?: string
  hidden?: number
  icon?: string // colour icon (unlocked)
  icongray?: string // grey icon (locked) — unused; the app greys `icon` itself
}

interface PlayerAchievement {
  apiname: string
  achieved: number // 0 | 1
  unlocktime?: number // unix seconds, 0 when locked
  description?: string
}

interface MergedAchievement {
  name: string
  description: string
  icon_url: string
  unlocked: boolean
  unlocked_at: string | null
  global_percent: number | null // share of all players who have it, 0-100
}

type PlayerResult =
  | { kind: 'ok'; achievements: PlayerAchievement[] }
  | { kind: 'no_stats' } // Steam: "Requested app has no stats"
  | { kind: 'private' } // game details not public
  // `status` is absent when Steam could not be reached at all.
  | { kind: 'error'; message: string; status?: number; retryAfter?: string | null }

function steamAppIdFromGameId(gameId: string): number | null {
  const m = STEAM_UUID_RE.exec(gameId)
  if (!m) return null
  const appId = parseInt(m[1], 10)
  return appId > 0 ? appId : null
}

/**
 * Join the global schema with the player's state on the API name. Schema order
 * is kept (the app does its own sorting). Hidden achievements usually ship an
 * empty description in the schema, so fall back to the player's copy and then
 * to a placeholder.
 */
function mergeAchievements(
  schema: SchemaAchievement[],
  player: PlayerAchievement[],
  globalPercents: Map<string, number> = new Map(),
): MergedAchievement[] {
  const byApiName = new Map(player.map((p) => [p.apiname, p]))
  return schema.map((s) => {
    const p = byApiName.get(s.name)
    const unlocked = p?.achieved === 1
    const unlockTime = p?.unlocktime ?? 0
    const description =
      (s.description ?? '').trim() ||
      (p?.description ?? '').trim() ||
      (s.hidden === 1 ? 'Hidden achievement' : '')
    return {
      name: (s.displayName ?? '').trim() || s.name,
      description,
      icon_url: s.icon ?? '',
      unlocked,
      unlocked_at: unlocked && unlockTime > 0 ? new Date(unlockTime * 1000).toISOString() : null,
      global_percent: globalPercents.get(s.name) ?? null,
    }
  })
}

/**
 * Steam's global unlock rates, by API name, rounded to one decimal. Steam has sent
 * `percent` both as a number and as a string, so both are read.
 */
function interpretGlobalPercents(body: unknown): Map<string, number> {
  const list = (body as { achievementpercentages?: { achievements?: unknown } } | null)
    ?.achievementpercentages?.achievements
  const byName = new Map<string, number>()
  if (!Array.isArray(list)) return byName
  for (const item of list) {
    const name = (item as { name?: unknown })?.name
    const percent = Number((item as { percent?: unknown })?.percent)
    if (typeof name !== 'string' || !Number.isFinite(percent)) continue
    byName.set(name, Math.round(Math.min(Math.max(percent, 0), 100) * 10) / 10)
  }
  return byName
}

/** Classify Steam's GetPlayerAchievements reply (HTTP status + parsed body, if any). */
function interpretPlayerResponse(status: number, body: unknown): PlayerResult {
  const ps = (body as { playerstats?: Record<string, unknown> } | null)?.playerstats
  if (ps?.success === true) {
    return {
      kind: 'ok',
      achievements: Array.isArray(ps.achievements) ? (ps.achievements as PlayerAchievement[]) : [],
    }
  }
  const message = String(ps?.error ?? '').toLowerCase()
  if (message.includes('not public') || message.includes('private')) return { kind: 'private' }
  if (message.includes('no stats')) return { kind: 'no_stats' }
  return { kind: 'error', message: message || `Steam returned ${status}`, status }
}

// ---- END PURE HELPERS ------------------------------------------------------

// ---- Steam -----------------------------------------------------------------
async function steamFetch(path: string, params: Record<string, string>): Promise<Response> {
  const url = new URL(`${STEAM_API}/${path}`)
  url.search = new URLSearchParams(params).toString()
  try {
    return await fetchWithBackoff(() => fetch(url), STEAM_BACKOFF)
  } catch {
    // Don't surface the raw fetch error: it embeds the request URL (and API key).
    throw new HttpError(503, 'STEAM_UNAVAILABLE', 'Could not reach Steam', DEFAULT_RETRY_AFTER_S)
  }
}

async function fetchSchema(apiKey: string, appId: number): Promise<SchemaAchievement[]> {
  const res = await steamFetch('ISteamUserStats/GetSchemaForGame/v2/', {
    key: apiKey,
    appid: String(appId),
    l: 'english',
  })
  if (!res.ok) throw steamStatusError(res.status, res.headers.get('Retry-After'), 'Steam schema request failed')
  const data = await res.json().catch(() => null)
  const list = data?.game?.availableGameStats?.achievements
  // Games without achievements come back as `{ game: {} }`.
  return Array.isArray(list) ? list : []
}

/** Never throws: the list is complete without the rates, which are only shown when here. */
async function fetchGlobalPercents(appId: number): Promise<Map<string, number>> {
  try {
    const res = await steamFetch('ISteamUserStats/GetGlobalAchievementPercentagesForApp/v0002/', {
      gameid: String(appId),
    })
    if (!res.ok) return new Map()
    return interpretGlobalPercents(await res.json().catch(() => null))
  } catch {
    return new Map()
  }
}

async function fetchPlayer(apiKey: string, steamId: string, appId: number): Promise<PlayerResult> {
  try {
    const res = await steamFetch('ISteamUserStats/GetPlayerAchievements/v0001/', {
      key: apiKey,
      steamid: steamId,
      appid: String(appId),
      l: 'english',
    })
    // Steam sends useful JSON bodies on 4xx too (private profile, no stats).
    const body = await res.json().catch(() => null)
    const result = interpretPlayerResponse(res.status, body)
    return result.kind === 'error' ? { ...result, retryAfter: res.headers.get('Retry-After') } : result
  } catch (e) {
    return { kind: 'error', message: (e as Error).message }
  }
}

// ---- Supabase --------------------------------------------------------------
async function authenticate(req: Request, admin: SupabaseClient): Promise<string> {
  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '').trim()
  if (!token) throw new HttpError(401, 'UNAUTHENTICATED', 'Missing authorization')
  const { data, error } = await admin.auth.getUser(token)
  if (error || !data.user) throw new HttpError(401, 'UNAUTHENTICATED', 'Invalid or expired session')
  if (secondFactorMissing(data.user, token)) {
    throw new HttpError(403, 'MFA_REQUIRED', 'Enter your two-factor code to finish signing in')
  }
  return data.user.id
}

/**
 * A member's Steam ID64, read from their own `profiles` row: the caller's (`userId`
 * from the verified JWT) or, for another member's profile, theirs. Never one sent in
 * the request, so achievements are only ever loaded for the Steam account a member
 * saved on their own profile. (Same lookup as `sync-steam`.)
 */
async function fetchSteamId(admin: SupabaseClient, userId: string, own = true): Promise<string> {
  const { data, error } = await admin
    .from('profiles')
    .select('steam_id')
    .eq('id', userId)
    .maybeSingle()
  if (error) throw new Error(`profiles lookup failed: ${error.message}`)

  const steamId = data?.steam_id
  if (steamId === null || steamId === undefined || String(steamId).trim() === '') {
    throw new HttpError(
      400,
      'NO_STEAM_ID',
      own
        ? 'No Steam ID saved on your profile. Connect your Steam account first.'
        : 'This member has not connected a Steam account.',
    )
  }
  return String(steamId).trim()
}

/**
 * Throws ACHIEVEMENTS_HIDDEN when another member turned off "Show Steam Achievements":
 * then neither their stored list nor Steam's is handed out. A member who doesn't
 * exist passes, and fails later as NOT_IN_LIBRARY.
 */
async function assertAchievementsShared(admin: SupabaseClient, userId: string): Promise<void> {
  const { data, error } = await admin
    .from('profiles')
    .select('show_steam_achievements')
    .eq('id', userId)
    .maybeSingle()
  // Before the privacy migration there is no such column: fail rather than share.
  if (error) throw new Error(`profiles lookup failed: ${error.message}`)
  if (data && data.show_steam_achievements !== true) {
    throw new HttpError(403, 'ACHIEVEMENTS_HIDDEN', 'This member keeps their achievements private.')
  }
}

// ---- Orchestration ---------------------------------------------------------

/**
 * The Steam app a game is: `games.steam_app_id` (set by sync-steam), falling back
 * to decoding a legacy `57e40000-…` id. `null` when the game isn't linked to a
 * Steam app (for example one added through in-app search that no Steam sync has
 * matched yet).
 */
async function steamAppIdForGame(admin: SupabaseClient, gameId: string): Promise<number | null> {
  const { data, error } = await admin
    .from('games')
    .select('steam_app_id')
    .eq('id', gameId)
    .maybeSingle()
  if (error) throw new Error(`games lookup failed: ${error.message}`)

  const stored = Number(data?.steam_app_id)
  if (Number.isInteger(stored) && stored > 0) return stored
  return steamAppIdFromGameId(gameId)
}

/**
 * Another member's stored list when it was fetched from Steam a moment ago, so it
 * can be answered as is; null when Steam has to be asked. Throws NOT_IN_LIBRARY
 * when the game is not in their library.
 */
async function recentStoredAchievements(
  admin: SupabaseClient,
  userId: string,
  gameId: string,
): Promise<MergedAchievement[] | null> {
  const { data, error } = await admin
    .from('user_games')
    .select('achievements, achievements_synced_at')
    .eq('user_id', userId)
    .eq('game_id', gameId)
    .maybeSingle()
  if (error) {
    // Before the counts migration there is no achievements_synced_at: just ask Steam.
    console.error('sync-achievements: stored list lookup failed:', error.message)
    return null
  }
  if (!data) throw new HttpError(404, 'NOT_IN_LIBRARY', 'That game is not in their library')
  const syncedAt = Date.parse(String(data.achievements_synced_at ?? ''))
  const fresh = Number.isFinite(syncedAt) && Date.now() - syncedAt < OTHERS_REFRESH_MS
  return fresh && Array.isArray(data.achievements) ? (data.achievements as MergedAchievement[]) : null
}

async function syncAchievements(
  admin: SupabaseClient,
  userId: string,
  steamId: string,
  gameId: string,
  appId: number,
  own = true,
): Promise<MergedAchievement[]> {
  const apiKey = Deno.env.get('STEAM_API_KEY')
  if (!apiKey) {
    console.error('STEAM_API_KEY is not set')
    throw new HttpError(500, 'NOT_CONFIGURED', 'Server is not configured')
  }

  // The Steam calls are independent, so run them together.
  const [schema, player, globalPercents] = await Promise.all([
    fetchSchema(apiKey, appId),
    fetchPlayer(apiKey, steamId, appId),
    fetchGlobalPercents(appId),
  ])

  let merged: MergedAchievement[]
  if (schema.length === 0) {
    merged = [] // no achievements in this game; whatever the player call said is moot
  } else if (player.kind === 'ok') {
    merged = mergeAchievements(schema, player.achievements, globalPercents)
  } else if (player.kind === 'no_stats') {
    merged = mergeAchievements(schema, [], globalPercents) // owned but nothing unlocked yet
  } else if (player.kind === 'private') {
    throw new HttpError(
      403,
      'STEAM_PROFILE_PRIVATE',
      own
        ? 'Your Steam game details are private. Set "Game details" to Public in your Steam privacy settings, then try again.'
        : 'Their Steam game details are private.',
    )
  } else {
    console.error('GetPlayerAchievements failed:', player.message)
    // No status = Steam was unreachable, which is the same "try again" as a 5xx.
    throw steamStatusError(player.status ?? 503, player.retryAfter ?? null, 'Steam could not return the achievements')
  }

  // Updating (not upserting) means a game that isn't in this user's library
  // simply matches no row, which we report instead of creating anything.
  const { data, error } = await admin
    .from('user_games')
    .update({ achievements: merged })
    .eq('user_id', userId)
    .eq('game_id', gameId)
    .select('game_id')
  if (error) throw new Error(`user_games update failed: ${error.message}`)
  if (!data || data.length === 0) {
    throw new HttpError(404, 'NOT_IN_LIBRARY', own ? 'That game is not in your library' : 'That game is not in their library')
  }

  return merged
}

const json = (body: unknown, status = 200, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...headers },
  })

/**
 * `{ error, code, retry_after? }` plus a `Retry-After` header when a retry makes
 * sense. Anything that is not an `HttpError` is logged and answered with a generic
 * message, so database / library error text never reaches the client.
 */
function errorResponse(error: unknown): Response {
  if (error instanceof HttpError) {
    const retryAfter = error.retryAfter
    return json(
      { error: error.message, code: error.code, ...(retryAfter ? { retry_after: retryAfter } : {}) },
      error.status,
      retryAfter ? { 'Retry-After': String(retryAfter) } : {},
    )
  }
  return json({ error: 'Something went wrong on our side. Try again later.', code: 'INTERNAL' }, 500)
}

serve(withCors(async (req) => {
  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!supabaseUrl || !serviceKey) {
      console.error('SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are not set')
      throw new HttpError(500, 'NOT_CONFIGURED', 'Server is not configured')
    }

    // Service-role client: bypasses RLS, so the write below is explicitly
    // scoped to the verified user.
    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    })

    const callerId = await authenticate(req, admin)
    const wait = await rateLimitWait(admin, callerId, RATE_LIMITS.achievements)
    if (wait > 0) throw new HttpError(429, 'RATE_LIMITED', 'Too many requests, try again shortly', wait)

    // Only `game_id` and `user_id` are read from the body. Any `steam_id` in it is
    // ignored on purpose: the Steam ID comes from the member's own profile, so it
    // can't be swapped for someone else's.
    const body = await req.json().catch(() => ({}))
    const gameId = body?.game_id
    if (!gameId || typeof gameId !== 'string') throw new HttpError(400, 'BAD_REQUEST', 'Missing game_id')
    if (!UUID_RE.test(gameId)) throw new HttpError(400, 'BAD_REQUEST', 'Invalid game_id')

    const requested = body?.user_id
    if (requested !== undefined && requested !== null && (typeof requested !== 'string' || !UUID_RE.test(requested))) {
      throw new HttpError(400, 'BAD_REQUEST', 'Invalid user_id')
    }
    const userId = typeof requested === 'string' ? requested.toLowerCase() : callerId
    const own = userId === callerId.toLowerCase()

    if (!own) {
      await assertAchievementsShared(admin, userId)
      const recent = await recentStoredAchievements(admin, userId, gameId)
      if (recent) return json({ success: true, achievements: recent })
    }

    const appId = await steamAppIdForGame(admin, gameId)
    if (appId === null) {
      throw new HttpError(
        400,
        'GAME_NOT_LINKED',
        'This game is not linked to a Steam app yet. Sync your Steam library first.',
      )
    }

    const steamId = await fetchSteamId(admin, userId, own)

    const achievements = await syncAchievements(admin, userId, steamId, gameId, appId, own)
    return json({ success: true, achievements })
  } catch (error) {
    console.error('sync-achievements failed:', error)
    return errorResponse(error)
  }
}))