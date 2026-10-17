/**
 * sync-achievements — on-demand Steam achievements for ONE game.
 *
 * POST { game_id }   (the caller is identified by their Supabase JWT)
 *   The caller's Steam ID64 is read from `profiles.steam_id` for the verified
 *   user. A `steam_id` sent in the request body is ignored.
 *
 *   0. Profile: look up the caller's `profiles.steam_id`
 *   1. game_id → Steam app id: `games.steam_app_id`, or (a legacy Steam-keyed
 *      row that sync-steam hasn't adopted yet) decoded from its `57e40000-…` id
 *   2. ISteamUserStats/GetSchemaForGame/v2     → the game's global achievement
 *      dictionary (names, descriptions, icons)
 *   3. ISteamUserStats/GetPlayerAchievements/v0001 → this player's unlock flags
 *      and timestamps
 *   4. Merge both into one array, save it to user_games.achievements (JSONB)
 *      for this user + game, and return it.
 *
 * Response: { success: true, achievements: [
 *   { name, description, icon_url, unlocked, unlocked_at } ] }
 *   - `[]` means the game has no Steam achievements (stored as `[]`, not NULL,
 *     so the app doesn't offer to load them again).
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

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const STEAM_API = 'https://api.steampowered.com'

/**
 * Machine-readable failure codes; the app keys off `code`, not the `error` text.
 * Same scheme as `sync-steam` (see `SyncFailureCode` in lib/services/sync_failure.dart).
 *   Retry later: STEAM_RATE_LIMITED, STEAM_UNAVAILABLE
 *   Needs the user: UNAUTHENTICATED, NO_STEAM_ID, STEAM_PROFILE_PRIVATE,
 *                   GAME_NOT_LINKED, NOT_IN_LIBRARY, BAD_REQUEST
 *   Needs the owner: NOT_CONFIGURED, STEAM_ERROR, INTERNAL
 */
type ErrorCode =
  | 'UNAUTHENTICATED'
  | 'NO_STEAM_ID'
  | 'STEAM_PROFILE_PRIVATE'
  | 'STEAM_RATE_LIMITED'
  | 'STEAM_UNAVAILABLE'
  | 'STEAM_ERROR'
  | 'GAME_NOT_LINKED'
  | 'NOT_IN_LIBRARY'
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
    }
  })
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
  return data.user.id
}

/**
 * The caller's Steam ID64, read from their own `profiles` row. `userId` comes
 * from the verified JWT (`authenticate`), never from the request, so a client
 * can only ever load achievements for the Steam account saved on its own
 * profile. (Same lookup as `sync-steam`.)
 */
async function fetchSteamId(admin: SupabaseClient, userId: string): Promise<string> {
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
      'No Steam ID saved on your profile. Connect your Steam account first.',
    )
  }
  return String(steamId).trim()
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

async function syncAchievements(
  admin: SupabaseClient,
  userId: string,
  steamId: string,
  gameId: string,
  appId: number,
): Promise<MergedAchievement[]> {
  const apiKey = Deno.env.get('STEAM_API_KEY')
  if (!apiKey) {
    console.error('STEAM_API_KEY is not set')
    throw new HttpError(500, 'NOT_CONFIGURED', 'Server is not configured')
  }

  // Both Steam calls are independent, so run them together.
  const [schema, player] = await Promise.all([
    fetchSchema(apiKey, appId),
    fetchPlayer(apiKey, steamId, appId),
  ])

  let merged: MergedAchievement[]
  if (schema.length === 0) {
    merged = [] // no achievements in this game; whatever the player call said is moot
  } else if (player.kind === 'ok') {
    merged = mergeAchievements(schema, player.achievements)
  } else if (player.kind === 'no_stats') {
    merged = mergeAchievements(schema, []) // owned but nothing unlocked yet
  } else if (player.kind === 'private') {
    throw new HttpError(
      403,
      'STEAM_PROFILE_PRIVATE',
      'Your Steam game details are private. Set "Game details" to Public in your Steam privacy settings, then try again.',
    )
  } else {
    console.error('GetPlayerAchievements failed:', player.message)
    // No status = Steam was unreachable, which is the same "try again" as a 5xx.
    throw steamStatusError(player.status ?? 503, player.retryAfter ?? null, 'Steam could not return your achievements')
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
  if (!data || data.length === 0) throw new HttpError(404, 'NOT_IN_LIBRARY', 'That game is not in your library')

  return merged
}

const json = (body: unknown, status = 200, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json', ...headers },
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

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

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

    const userId = await authenticate(req, admin)

    // Only `game_id` is read from the body. Any `steam_id` in it is ignored on
    // purpose: the Steam ID comes from the caller's own profile, so it can't be
    // swapped for someone else's.
    const body = await req.json().catch(() => ({}))
    const gameId = body?.game_id
    if (!gameId || typeof gameId !== 'string') throw new HttpError(400, 'BAD_REQUEST', 'Missing game_id')

    if (!UUID_RE.test(gameId)) throw new HttpError(400, 'BAD_REQUEST', 'Invalid game_id')

    const appId = await steamAppIdForGame(admin, gameId)
    if (appId === null) {
      throw new HttpError(
        400,
        'GAME_NOT_LINKED',
        'This game is not linked to a Steam app yet. Sync your Steam library first.',
      )
    }

    const steamId = await fetchSteamId(admin, userId)

    const achievements = await syncAchievements(admin, userId, steamId, gameId, appId)
    return json({ success: true, achievements })
  } catch (error) {
    console.error('sync-achievements failed:', error)
    return errorResponse(error)
  }
})