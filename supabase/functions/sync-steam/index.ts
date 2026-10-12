/**
 * sync-steam — bulk Steam → Supabase library sync.
 *
 * Pipeline (all heavy lifting server-side, no per-game round trips):
 *   1. Steam       fetch owned games, junk-filter, map appid → deterministic UUID
 *   2. Cache check query `games` for all UUIDs (chunked `in` queries, in parallel)
 *   3. IGDB        bulk `where name = (...)` lookup for the missing games only
 *   4. Base games  bulk upsert newly fetched games into `games`
 *   5. Library     bulk upsert `user_games` (new rows get defaults; existing rows
 *                  only ever get a higher `hours_played`)
 *
 * Secrets (set with `supabase secrets set`):
 *   STEAM_API_KEY, TWITCH_CLIENT_ID, TWITCH_CLIENT_SECRET
 *   (SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.)
 *
 * ── SCHEMA ASSUMPTIONS ────────────────────────────────────────────────────────
 * checkpoint_repository.dart wasn't available when this was written, so column
 * names are inferred from the Dart `Game` model and `upsertUserGame` parameters
 * (snake_case). If your schema differs, every column name lives in
 * `toGameRow` / `newUserGameRow` below, plus:
 *   • `user_games` has a unique constraint on (user_id, game_id)
 *   • `user_games.hours_played` is the column read when comparing hours
 */
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.4"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// ---- Tuning ----------------------------------------------------------------
const STEAM_UUID_PREFIX = '57e40000-0000-0000-0000-'
const DB_IN_CHUNK = 150          // ids per `.in()` query (keeps the PostgREST URL short)
const DB_WRITE_CHUNK = 1000      // rows per upsert call
const IGDB_TITLE_BATCH = 100     // titles per bulk `where name = (...)` request
const IGDB_MULTIQUERY_BATCH = 10 // IGDB's hard limit of sub-queries per /multiquery
const IGDB_FALLBACK_CAP = 60     // max fuzzy-search fallbacks per sync (rest retried next sync)
const IGDB_PACING_MS = 260       // IGDB allows ~4 req/s

/**
 * Extra columns merged into every new `games` row. The Dart model also carries
 * coverColors / coverIcon; if those are real (NOT NULL) columns in `games`,
 * add the same placeholder values `upsertBaseGame` writes, e.g.
 *   { cover_colors: [...], cover_icon: '...' }
 */
const GAME_ROW_EXTRAS: Record<string, unknown> = {}

class HttpError extends Error {
  status: number
  constructor(status: number, message: string) {
    super(message)
    this.status = status
  }
}

// ---- BEGIN PURE HELPERS ----------------------------------------------------

interface SteamGame {
  appid?: number
  name?: string
  playtime_forever?: number
}

interface SteamEntry {
  id: string // deterministic Supabase UUID
  title: string
  hours: number
}

interface IgdbGame {
  id: number
  name?: string
  cover?: { url?: string }
  first_release_date?: number
  platforms?: { name?: string }[]
  genres?: { name?: string }[]
  summary?: string
  involved_companies?: { company?: { name?: string } }[]
}

const IGDB_FIELDS =
  'name, cover.url, first_release_date, platforms.name, genres.name, summary, involved_companies.company.name'

// Non-game software Steam lists alongside games. Word boundaries keep short
// terms like "obs" from matching titles such as "Observer". (No `g` flag: .test() stays stateless.)
const JUNK_RE = /\b(?:blender|wallpaper engine|soundpad|aseprite|obs|3dmark)\b/i

const chunk = <T>(arr: T[], size: number): T[][] => {
  const out: T[][] = []
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size))
  return out
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

/** Quote a string for IGDB's Apicalypse query language. */
const quote = (s: string) => `"${s.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`

const steamUuid = (appid: number) => `${STEAM_UUID_PREFIX}${String(appid).padStart(12, '0')}`

// ---- Steam title cleanup so IGDB can match the base game (port of Dart) ----
const TRADEMARK_RE = /[™®©]/g
const COLON_NO_SPACE_RE = /:(?=\p{L})/gu
const SEPARATORS_RE = /[:\-–—]/g
const APOSTROPHE_RE = /['’]/g

// "Title (Deluxe Edition)" / "Title [Director's Cut]"
const BRACKETED_EDITION_RE =
  /\s*[\(\[][^\)\]]*\b(?:edition|director['’]?s\s+cut)\b[^\)\]]*[\)\]]/gi

// "Title - Complete Edition"
const DASHED_EDITION_RE = /\s+[-–—]\s+[^-–—]*\b(?:edition|director['’]?s\s+cut)\b.*$/gi

// "Title Special Edition", "Title: Game of the Year Edition"
const TRAILING_EDITION_RE =
  /\s*:?\s*(?:(?:game\s+of\s+the\s+year|goty|definitive|complete|enhanced|deluxe|ultimate|gold|special|anniversary|collector['’]?s|legendary|standard|premium|extended|digital)\s+)*(?:edition|director['’]?s\s+cut)\b.*$/gi

const SPACES_RE = /\s+/g
const DANGLING_RE = /[\s\-–—:]+$/g

function cleanSteamTitle(raw: string): string {
  const stripped = raw
    .replace(TRADEMARK_RE, '')
    .replace(COLON_NO_SPACE_RE, ': ')
    .replace(SPACES_RE, ' ')
    .trim()
  const cleaned = stripped
    .replace(BRACKETED_EDITION_RE, '')
    .replace(DASHED_EDITION_RE, '')
    .replace(TRAILING_EDITION_RE, '')
    .replace(DANGLING_RE, '')
    .trim()
  // Never search for an empty string (e.g. a game literally named "Edition").
  return cleaned === '' ? stripped : cleaned
}

/** Colons and hyphens -> spaces, apostrophes removed, whitespace collapsed. */
const stripPunctuation = (s: string): string =>
  s.replace(APOSTROPHE_RE, '').replace(SEPARATORS_RE, ' ').replace(SPACES_RE, ' ').trim()

/**
 * Pick the IGDB result for a cleaned Steam title. Exact (case-insensitive) name
 * matches win so sequels (PoE 2) can't override the original; if several games
 * share the exact name, prefer a PC release, then one with a cover. If nothing
 * is exact, fall back to the top search hit (same as the old Dart behaviour).
 */
function pickMatch(results: IgdbGame[], cleanTitle: string): IgdbGame | null {
  if (results.length === 0) return null
  const target = cleanTitle.toLowerCase()
  const exact = results.filter((g) => g.name?.toLowerCase() === target)
  if (exact.length === 0) return results[0]
  const score = (g: IgdbGame) =>
    (g.platforms?.some((p) => p.name?.includes('PC (Microsoft Windows)')) ? 2 : 0) +
    (g.cover?.url ? 1 : 0)
  return [...exact].sort((a, b) => score(b) - score(a))[0]
}

/** Junk-filter, dedupe, and translate Steam's list into our UUID format. */
function toSteamEntries(raw: SteamGame[]): { entries: SteamEntry[]; junk: number } {
  const byId = new Map<string, SteamEntry>()
  let junk = 0
  for (const g of raw) {
    const title = (g.name ?? '').trim()
    if (!title || typeof g.appid !== 'number') continue
    if (JUNK_RE.test(title)) {
      junk++
      continue
    }
    const id = steamUuid(g.appid)
    byId.set(id, {
      id,
      title,
      hours: Math.round(((g.playtime_forever ?? 0) / 60) * 100) / 100,
    })
  }
  return { entries: [...byId.values()], junk }
}

/** Map an IGDB record to a `games` row. Column names live here. */
function toGameRow(id: string, g: IgdbGame): Record<string, unknown> {
  let coverUrl: string | null = null
  if (g.cover?.url) {
    const url = g.cover.url.startsWith('//') ? `https:${g.cover.url}` : g.cover.url
    coverUrl = url.replace('t_thumb', 't_cover_big')
  }
  const company = g.involved_companies?.[0]?.company?.name ?? 'Unknown Publisher'
  return {
    id,
    title: g.name ?? 'Unknown',
    developer: company,
    publisher: company,
    release_year: g.first_release_date
      ? new Date(g.first_release_date * 1000).getUTCFullYear()
      : 0,
    platforms: [],
    genres: (g.genres ?? []).map((x) => x.name).filter((n): n is string => !!n),
    synopsis: g.summary ?? '',
    cover_url: coverUrl,
    ...GAME_ROW_EXTRAS,
  }
}

/** Defaults for a game the user doesn't have yet. Column names live here. */
function newUserGameRow(userId: string, e: SteamEntry, nowIso: string): Record<string, unknown> {
  return {
    user_id: userId,
    game_id: e.id,
    status: 'playing',
    played_on: 'pc',
    hours_played: e.hours,
    date_added: nowIso,
  }
}

// ---- END PURE HELPERS ------------------------------------------------------

// ---- Steam -----------------------------------------------------------------
async function fetchSteamGames(steamId: string): Promise<SteamGame[]> {
  const apiKey = Deno.env.get('STEAM_API_KEY')
  if (!apiKey) throw new Error('Server missing Steam API key')

  const url = new URL('https://api.steampowered.com/IPlayerService/GetOwnedGames/v0001/')
  url.search = new URLSearchParams({
    key: apiKey,
    steamid: steamId,
    format: 'json',
    include_appinfo: 'true',
    include_played_free_games: 'true',
  }).toString()

  let res: Response
  try {
    res = await fetch(url)
  } catch {
    // Don't surface the raw fetch error: it embeds the request URL (and API key).
    throw new HttpError(502, 'Could not reach Steam')
  }
  if (!res.ok) throw new HttpError(502, `Steam API returned ${res.status}`)

  const data = await res.json()
  // Private profiles return `{ response: {} }`.
  return data?.response?.games ?? []
}

// ---- IGDB ------------------------------------------------------------------
let igdbToken: { value: string; expiresAt: number } | null = null

async function getIgdbToken(): Promise<string> {
  if (igdbToken && Date.now() < igdbToken.expiresAt - 60_000) return igdbToken.value

  const clientId = Deno.env.get('TWITCH_CLIENT_ID')
  const clientSecret = Deno.env.get('TWITCH_CLIENT_SECRET')
  if (!clientId || !clientSecret) throw new Error('Server missing Twitch/IGDB credentials')

  const res = await fetch('https://id.twitch.tv/oauth2/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      grant_type: 'client_credentials',
    }),
  })
  if (!res.ok) throw new Error(`Twitch auth failed (${res.status})`)

  const data = await res.json()
  igdbToken = {
    value: data.access_token,
    expiresAt: Date.now() + (data.expires_in ?? 3600) * 1000,
  }
  return igdbToken.value
}

async function igdbFetch<T>(endpoint: string, body: string, attempt = 0): Promise<T> {
  const token = await getIgdbToken()
  const res = await fetch(`https://api.igdb.com/v4/${endpoint}`, {
    method: 'POST',
    headers: {
      'Client-ID': Deno.env.get('TWITCH_CLIENT_ID')!,
      Authorization: `Bearer ${token}`,
      Accept: 'application/json',
    },
    body,
  })

  if (res.status === 401 && attempt === 0) {
    igdbToken = null // token revoked/expired early: re-auth once
    return igdbFetch<T>(endpoint, body, 1)
  }
  if (res.status === 429 && attempt < 2) {
    await sleep(1000 * (attempt + 1))
    return igdbFetch<T>(endpoint, body, attempt + 1)
  }
  if (!res.ok) {
    throw new Error(`IGDB /${endpoint} failed (${res.status}): ${(await res.text()).slice(0, 200)}`)
  }
  return (await res.json()) as T
}

/** Fuzzy `search` for many terms at once via /multiquery (10 per request). */
async function igdbSearchMany(terms: string[]): Promise<IgdbGame[][]> {
  const out: IgdbGame[][] = terms.map(() => [])
  for (const [b, batch] of chunk(terms, IGDB_MULTIQUERY_BATCH).entries()) {
    const body = batch
      .map((t, j) => `query games "q${j}" { search ${quote(t)}; fields ${IGDB_FIELDS}; limit 20; };`)
      .join('\n')
    const res = await igdbFetch<{ name: string; result?: IgdbGame[] }[]>('multiquery', body)
    for (const r of res) {
      const j = Number(r.name.slice(1))
      if (Number.isInteger(j)) out[b * IGDB_MULTIQUERY_BATCH + j] = r.result ?? []
    }
    await sleep(IGDB_PACING_MS)
  }
  return out
}

/**
 * Resolve Steam games missing from the cache to IGDB records.
 *   Pass 1: one bulk exact-name query per 100 titles (the 1–2 request happy path).
 *   Pass 2: capped fuzzy fallback (clean title, then punctuation-stripped), the
 *           batched equivalent of the old per-game retry in the Dart client.
 * An IGDB failure never aborts the sync: whatever matched so far is kept.
 */
async function resolveMissingGames(missing: SteamEntry[], warnings: string[]) {
  const matched = new Map<string, IgdbGame>()
  let deferred = 0
  if (missing.length === 0) return { matched, unmatched: [] as string[], deferred }

  const prepared = missing.map((entry) => ({ entry, clean: cleanSteamTitle(entry.title) }))

  try {
    // Pass 1 — bulk exact match.
    const byName = new Map<string, IgdbGame[]>()
    const titles = [...new Set(prepared.map((p) => p.clean))]
    for (const part of chunk(titles, IGDB_TITLE_BATCH)) {
      const results = await igdbFetch<IgdbGame[]>(
        'games',
        `fields ${IGDB_FIELDS}; where name = (${part.map(quote).join(',')}); limit 500;`,
      )
      for (const g of results) {
        if (!g.name) continue
        const key = g.name.toLowerCase()
        const list = byName.get(key)
        if (list) list.push(g)
        else byName.set(key, [g])
      }
      await sleep(IGDB_PACING_MS)
    }

    const leftovers: typeof prepared = []
    for (const p of prepared) {
      const hits = byName.get(p.clean.toLowerCase())
      const best = hits ? pickMatch(hits, p.clean) : null
      if (best) matched.set(p.entry.id, best)
      else leftovers.push(p)
    }

    // Pass 2 — fuzzy fallback for whatever the exact query missed.
    const toSearch = leftovers.slice(0, IGDB_FALLBACK_CAP)
    deferred = leftovers.length - toSearch.length
    if (toSearch.length > 0) {
      const retry: { p: (typeof prepared)[number]; loose: string }[] = []
      const first = await igdbSearchMany(toSearch.map((p) => p.clean))
      toSearch.forEach((p, i) => {
        const best = pickMatch(first[i], p.clean)
        if (best) {
          matched.set(p.entry.id, best)
          return
        }
        const loose = stripPunctuation(p.clean)
        if (loose && loose !== p.clean) retry.push({ p, loose })
      })

      if (retry.length > 0) {
        const second = await igdbSearchMany(retry.map((r) => r.loose))
        retry.forEach((r, i) => {
          const best = pickMatch(second[i], r.p.clean)
          if (best) matched.set(r.p.entry.id, best)
        })
      }
    }
  } catch (e) {
    console.error('IGDB lookup failed:', e)
    warnings.push(`IGDB lookup incomplete: ${(e as Error).message}`)
  }

  const unmatched = missing.filter((m) => !matched.has(m.id)).map((m) => m.title)
  return { matched, unmatched, deferred }
}

// ---- Supabase --------------------------------------------------------------
async function authenticate(req: Request, admin: SupabaseClient): Promise<string> {
  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '').trim()
  if (!token) throw new HttpError(401, 'Missing authorization')
  const { data, error } = await admin.auth.getUser(token)
  if (error || !data.user) throw new HttpError(401, 'Invalid or expired session')
  return data.user.id
}

/** Which of these game UUIDs already exist in the global `games` catalog? */
async function fetchCachedGameIds(admin: SupabaseClient, ids: string[]): Promise<Set<string>> {
  const found = new Set<string>()
  const results = await Promise.all(
    chunk(ids, DB_IN_CHUNK).map((part) => admin.from('games').select('id').in('id', part)),
  )
  for (const { data, error } of results) {
    if (error) throw new Error(`games cache lookup failed: ${error.message}`)
    for (const row of data ?? []) found.add(row.id as string)
  }
  return found
}

/** The user's existing `user_games` rows (full rows, keyed by game_id). */
async function fetchExistingUserGames(
  admin: SupabaseClient,
  userId: string,
  ids: string[],
): Promise<Map<string, Record<string, unknown>>> {
  const byGame = new Map<string, Record<string, unknown>>()
  const results = await Promise.all(
    chunk(ids, DB_IN_CHUNK).map((part) =>
      admin.from('user_games').select('*').eq('user_id', userId).in('game_id', part),
    ),
  )
  for (const { data, error } of results) {
    if (error) throw new Error(`user_games lookup failed: ${error.message}`)
    for (const row of data ?? []) byGame.set(row.game_id as string, row as Record<string, unknown>)
  }
  return byGame
}

async function upsertChunked(
  admin: SupabaseClient,
  table: string,
  rows: Record<string, unknown>[],
  onConflict: string,
) {
  for (const part of chunk(rows, DB_WRITE_CHUNK)) {
    // defaultToNull:false → columns missing from a row use the column default
    // instead of NULL (new rows and existing rows have different key sets).
    const { error } = await admin.from(table).upsert(part, { onConflict, defaultToNull: false })
    if (error) throw new Error(`${table} upsert failed: ${error.message}`)
  }
}

// ---- Orchestration ---------------------------------------------------------
async function syncLibrary(admin: SupabaseClient, userId: string, steamId: string) {
  const warnings: string[] = []

  // 1. Steam
  const owned = await fetchSteamGames(steamId)
  const { entries, junk } = toSteamEntries(owned)
  const ids = entries.map((e) => e.id)

  // 2. Global cache check + the user's current library, in parallel.
  const [cachedIds, existingByGame] = ids.length
    ? await Promise.all([
        fetchCachedGameIds(admin, ids),
        fetchExistingUserGames(admin, userId, ids),
      ])
    : [new Set<string>(), new Map<string, Record<string, unknown>>()]
  const missing = entries.filter((e) => !cachedIds.has(e.id))

  // 3. Bulk IGDB fetch for the missing games only.
  const { matched, unmatched, deferred } = await resolveMissingGames(missing, warnings)

  // 4. Bulk insert newly fetched base games.
  if (matched.size > 0) {
    const rows = [...matched.entries()].map(([id, g]) => toGameRow(id, g))
    await upsertChunked(admin, 'games', rows, 'id')
  }
  const availableIds = new Set<string>([...cachedIds, ...matched.keys()])

  // 5. Smart library upsert.
  const nowIso = new Date().toISOString()
  const libraryRows: Record<string, unknown>[] = []
  let added = 0
  let updated = 0
  let unchanged = 0

  for (const e of entries) {
    const existing = existingByGame.get(e.id)
    if (existing) {
      // Already in the library: only ever raise hours_played. We re-send the
      // row we just read with that single field changed, so status / rating /
      // is_favorite / etc. are written back exactly as they are.
      const current = Number(existing.hours_played) || 0
      if (e.hours > current) {
        libraryRows.push({ ...existing, hours_played: e.hours })
        updated++
      } else {
        unchanged++
      }
      continue
    }
    if (!availableIds.has(e.id)) continue // no IGDB match → skip rather than save a stub
    libraryRows.push(newUserGameRow(userId, e, nowIso))
    added++
  }

  if (libraryRows.length > 0) {
    await upsertChunked(admin, 'user_games', libraryRows, 'user_id,game_id')
  }

  return {
    summary: {
      steam_total: owned.length,
      junk_filtered: junk,
      candidates: entries.length,
      cached: entries.length - missing.length,
      fetched_from_igdb: matched.size,
      added,
      updated,
      unchanged,
      unmatched: unmatched.length,
      deferred,
    },
    unmatched_titles: unmatched.slice(0, 50),
    warnings,
  }
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

    // Service-role client: writes the global `games` catalog and bypasses RLS,
    // so every user_games query below is explicitly scoped to the verified user.
    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    })

    const userId = await authenticate(req, admin)

    const body = await req.json().catch(() => ({}))
    const steamId = body?.steam_id
    if (!steamId || (typeof steamId !== 'string' && typeof steamId !== 'number')) {
      throw new HttpError(400, 'Missing steam_id')
    }

    const result = await syncLibrary(admin, userId, String(steamId))
    return json({ success: true, ...result })
  } catch (error) {
    console.error('sync-steam failed:', error)
    const status = error instanceof HttpError ? error.status : 500
    return json({ error: (error as Error).message }, status)
  }
})