/**
 * sync-achievements — on-demand Steam achievements for ONE game.
 *
 * POST { game_id }   (the caller is identified by their Supabase JWT)
 *   The caller's Steam ID64 is read from `profiles.steam_id` for the verified
 *   user. A `steam_id` sent in the request body is ignored.
 *
 *   0. Profile: look up the caller's `profiles.steam_id`
 *   1. game_id (our deterministic UUID) → Steam app id
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
 * Secrets: STEAM_API_KEY. (SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are
 * injected automatically.)
 *
 * Requires the 20261012120000_add_achievements_to_user_games.sql migration.
 */
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.4"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const STEAM_API = 'https://api.steampowered.com'

class HttpError extends Error {
  status: number
  constructor(status: number, message: string) {
    super(message)
    this.status = status
  }
}

// ---- BEGIN PURE HELPERS ----------------------------------------------------

/** `57e40000-0000-0000-0000-000000001086` → app id `1086`. */
const STEAM_UUID_RE = /^57e40000-0000-0000-0000-(\d{12})$/i

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
  | { kind: 'error'; message: string }

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
  return { kind: 'error', message: message || `Steam returned ${status}` }
}

// ---- END PURE HELPERS ------------------------------------------------------

// ---- Steam -----------------------------------------------------------------
async function steamFetch(path: string, params: Record<string, string>): Promise<Response> {
  const url = new URL(`${STEAM_API}/${path}`)
  url.search = new URLSearchParams(params).toString()
  try {
    return await fetch(url)
  } catch {
    // Don't surface the raw fetch error: it embeds the request URL (and API key).
    throw new HttpError(502, 'Could not reach Steam')
  }
}

async function fetchSchema(apiKey: string, appId: number): Promise<SchemaAchievement[]> {
  const res = await steamFetch('ISteamUserStats/GetSchemaForGame/v2/', {
    key: apiKey,
    appid: String(appId),
    l: 'english',
  })
  if (!res.ok) throw new HttpError(502, `Steam schema request failed (${res.status})`)
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
    return interpretPlayerResponse(res.status, body)
  } catch (e) {
    return { kind: 'error', message: (e as Error).message }
  }
}

// ---- Supabase --------------------------------------------------------------
async function authenticate(req: Request, admin: SupabaseClient): Promise<string> {
  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '').trim()
  if (!token) throw new HttpError(401, 'Missing authorization')
  const { data, error } = await admin.auth.getUser(token)
  if (error || !data.user) throw new HttpError(401, 'Invalid or expired session')
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
    throw new HttpError(400, 'No Steam ID saved on your profile. Connect your Steam account first.')
  }
  return String(steamId).trim()
}

// ---- Orchestration ---------------------------------------------------------
async function syncAchievements(
  admin: SupabaseClient,
  userId: string,
  steamId: string,
  gameId: string,
  appId: number,
): Promise<MergedAchievement[]> {
  const apiKey = Deno.env.get('STEAM_API_KEY')
  if (!apiKey) throw new Error('Server missing Steam API key')

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
      'Your Steam game details are private. Set "Game details" to Public in your Steam privacy settings, then try again.',
    )
  } else {
    console.error('GetPlayerAchievements failed:', player.message)
    throw new HttpError(502, 'Steam could not return your achievements right now')
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
  if (!data || data.length === 0) throw new HttpError(404, 'That game is not in your library')

  return merged
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!supabaseUrl || !serviceKey) throw new Error('Server missing Supabase credentials')

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
    if (!gameId || typeof gameId !== 'string') throw new HttpError(400, 'Missing game_id')

    const appId = steamAppIdFromGameId(gameId)
    if (appId === null) throw new HttpError(400, 'Not a Steam game')

    const steamId = await fetchSteamId(admin, userId)

    const achievements = await syncAchievements(admin, userId, steamId, gameId, appId)
    return json({ success: true, achievements })
  } catch (error) {
    console.error('sync-achievements failed:', error)
    const status = error instanceof HttpError ? error.status : 500
    return json({ error: (error as Error).message }, status)
  }
})