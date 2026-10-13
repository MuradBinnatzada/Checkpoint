/**
 * sync-steam — bulk Steam → Supabase library sync.
 *
 * Pipeline (all heavy lifting server-side, no per-game round trips):
 *   1. Steam       fetch owned games, drop software junk and test/beta/server
 *                  builds, map appid → deterministic UUID
 *   2. Cache check query `games` for all UUIDs (chunked `in` queries, in parallel)
 *   3. IGDB        multi-pass match for the missing games only
 *                  (`resolveMissingGames`). The Steam title is cleaned first
 *                  (™/®, edition + "Test Server"/"Open Beta" junk), then:
 *                    Pass 1  cleaned title  → bulk case-insensitive exact match,
 *                                             then a fuzzy search
 *                    Pass 2  publisher prefix stripped ("Tom Clancy's ", "Sid Meier's ")
 *                    Pass 3  primary title only (text before ":" / " - ": "ARK", "PUBG")
 *                  Every IGDB hit is validated against the Steam title; the top
 *                  search hit is never accepted blindly.
 *                  Fuzzy searches are one `/games` request per term. They must
 *                  NOT go through `/multiquery`: IGDB answers a `search` block
 *                  there with bare ids (or nothing), so no hit has a name to validate.
 *   4. Base games  bulk upsert newly fetched games into `games`
 *   5. Library     bulk upsert `user_games` (new rows get defaults; existing rows
 *                  only ever get a higher `hours_played`)
 *
 * Secrets (set with `supabase secrets set`):
 *   STEAM_API_KEY, TWITCH_CLIENT_ID, TWITCH_CLIENT_SECRET
 *   (SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.)
 *
 * ── SCHEMA NOTES ──────────────────────────────────────────────────────────────
 * Column names follow checkpoint_repository.dart (`upsertBaseGame`,
 * `upsertUserGame`, `Db.*`). If a name in data/db_schema.dart differs from the
 * snake_case used here, fix it in `toGameRow` / `newUserGameRow`. The games'
 * cover colours and icon are computed in the app, not stored, so nothing is
 * written for them.
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
const IGDB_TITLE_BATCH = 50      // titles per bulk exact-name request
const IGDB_SEARCH_LIMIT = 30     // hits per fuzzy search (the real game can sit behind DLC / mods)
const IGDB_SEARCH_BUDGET = 300   // max fuzzy-search requests per sync, shared by passes 1b-3.
                                 // Games are searched most-played first; the rest wait for the next sync.
const IGDB_SEARCH_CONCURRENCY = 4 // searches in flight at once (IGDB allows 8 open requests)
const IGDB_MAX_CONSECUTIVE_FAILURES = 2 // stop the bulk exact pass early when IGDB keeps erroring
const IGDB_MAX_CONSECUTIVE_SEARCH_FAILURES = 5 // same for the search passes (one request per term)
const IGDB_PACING_MS = 260       // IGDB allows ~4 req/s: requests start at least this far apart
const IGDB_TIME_BUDGET_MS = 100_000 // stop *starting* fuzzy searches after this long, so the
                                    // sync always reaches its database writes before the
                                    // edge function's wall-clock limit (150 s on the free plan)
const PREFIX_MIN_RATIO = 0.8     // see `matchScore`
const LOOSE_MAX_EXTRA_WORDS = 3  // see `matchScore`

/**
 * Columns of an existing user_games row that are never re-sent when we rewrite
 * it, because another feature owns them. `achievements` is a (potentially large)
 * JSONB blob written by sync-achievements: re-sending a stale copy could wipe a
 * concurrent load, and would ship the blob for nothing.
 */
const NOT_RESENT_COLUMNS = ['achievements']

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

// Steam also lists test / beta / server / demo builds as separate apps next to the
// real game ("… - Test Server", "… Dedicated Server", "… Open Beta", "… Playtest",
// "… - Unstable", "… - Public Test", "…: Free Sample", "… Demo").
// They are not games, and matching them to the base game would add a duplicate
// row to the library, so they are dropped before any IGDB lookup. The patterns
// are deliberately narrow: a bare "Beta" or "Server" inside a longer word, or as
// the whole title ("Server"), is left alone.
const SERVER_BUILD_RE = new RegExp(
  [
    String.raw`\b(?:dedicated|test(?:ing)?|public\s+test|ptr|ptb|experimental|staging|beta)\s+server\b`,
    String.raw`[\s\-–—:(\[]server\s*[)\]]?$`, // "<Game> Server", "<Game> - Server"
  ].join('|'),
  'i',
)
const BETA_BUILD_RE = new RegExp(
  [
    String.raw`\b(?:open|closed|public|private|technical|stress)\s+beta\b`, // "Open Beta"
    String.raw`\bbeta\s+(?:test|build|branch|client)\b`, // "Beta Test"
    String.raw`[\s\-–—:(\[]beta\s*[)\]]?$`, // trailing "Beta" / "(Beta)" / "- Beta"
    String.raw`\bplaytest\b`,
  ].join('|'),
  'i',
)

// Public-test-realm / unstable-branch apps. A bare tag ("Unstable", "Test") only counts
// after a dash, colon or bracket, so real titles like "The Turing Test" or
// "Unstable Unicorns" are never touched.
const TEST_BUILD_RE = new RegExp(
  [
    String.raw`\bpublic\s+test\b`, // "For Honor - Public Test", "… Public Test Realm"
    String.raw`\btest\s+(?:realm|client|branch)\b`,
    String.raw`\bunstable\s+(?:branch|build)\b`,
    String.raw`[\-–—:(\[]\s*(?:unstable|experimental|testing|test|nightly|pts|ptr|ptb)\s*[)\]]?$`, // "Starbound - Unstable"
  ].join('|'),
  'i',
)

// Demo apps. Matching one to the base game would add a duplicate row, and it has no
// IGDB entry of its own. "Prologue" is NOT here: some standalone games use it.
const DEMO_BUILD_RE = new RegExp(
  [
    String.raw`\bfree\s+sample\b`, // "Schedule I: Free Sample"
    String.raw`\bdemo\s+(?:version|build)\b`,
    String.raw`[\s\-–—:(\[]\s*demo\s*[)\]]?$`, // "Foo Demo", "Foo - Demo", "Foo (Demo)"
  ].join('|'),
  'i',
)

/** True for a Steam app that is a test / beta / server / demo build rather than a game. (No `g` flag: stateless.) */
const isNonGameBuild = (title: string): boolean =>
  SERVER_BUILD_RE.test(title) ||
  BETA_BUILD_RE.test(title) ||
  TEST_BUILD_RE.test(title) ||
  DEMO_BUILD_RE.test(title)

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
const TRADEMARK_RE = /[™®©℠]/g
const COLON_NO_SPACE_RE = /:(?=\p{L})/gu
const APOSTROPHE_RE = /['’]/g

// "Title (Deluxe Edition)" / "Title [Director's Cut]"
const BRACKETED_EDITION_RE =
  /\s*[\(\[][^\)\]]*\b(?:edition|director['’]?s\s+cut)\b[^\)\]]*[\)\]]/gi

// "Title - Complete Edition"
const DASHED_EDITION_RE = /\s+[-–—]\s+[^-–—]*\b(?:edition|director['’]?s\s+cut)\b.*$/gi

// "Title - Remastered", "Title — Definitive": a qualifier after a spaced dash with no
// "Edition" behind it. Only after a dash: a bare trailing "Remastered" can be the real
// name ("Crysis Remastered" is its own IGDB entry), so that form is left alone.
const DASHED_QUALIFIER_RE = new RegExp(
  String.raw`\s+[-–—]\s+(?:remastered|remaster|reloaded|definitive|complete|deluxe|ultimate|enhanced|goty|game\s+of\s+the\s+year|anniversary)\s*$`,
  'i',
)

// "Title Special Edition", "Title: Game of the Year Edition", "Title: Reloaded Edition".
// Only these known qualifiers are stripped. A subtitle that merely ends in
// "Edition" ("The Elder Scrolls V: Skyrim Special Edition") must keep its subtitle.
const EDITION_QUALIFIERS = [
  String.raw`game\s+of\s+the\s+year`,
  'goty',
  String.raw`day\s+one`,
  'definitive',
  'complete',
  'enhanced',
  'deluxe',
  'ultimate',
  'super',
  'gold',
  'platinum',
  'special',
  'anniversary',
  String.raw`collector['’]?s`,
  String.raw`founder['’]?s`,
  'legendary',
  'standard',
  'premium',
  'extended',
  'expanded',
  'digital',
  'reloaded',
  'remastered',
  'remaster',
  'royal',
  'limited',
  'launch',
  'classic',
  'bonus',
  'steam',
  'pc',
].join('|')
const TRAILING_EDITION_RE = new RegExp(
  String.raw`\s*:?\s*(?:(?:${EDITION_QUALIFIERS})\s+)*(?:edition|director['’]?s\s+cut)\b.*$`,
  'gi',
)

// Steam junk strings left on a title: "(Open Beta)", "- Test Server", "Dedicated Server".
// Titles carrying them are normally dropped as non-games (`isNonGameBuild`); this
// strips them anyway so the cleaned title is never searched with them attached.
const JUNK_TAIL_RE = new RegExp(
  String.raw`\s*[-–—:]?\s*[(\[]?\s*\b(?:(?:public\s+)?test(?:ing)?\s+server|dedicated\s+server|(?:(?:open|closed|public|private|technical|stress)\s+)?beta(?:\s+test)?|playtest|server)\s*[)\]]?\s*$`,
  'i',
)

const SPACES_RE = /\s+/g
const DANGLING_RE = /[\s\-–—:]+$/g

/** Strips junk strings off the end of a title; repeated for "Foo - Test Server (Open Beta)". */
function stripJunkTail(s: string): string {
  let out = s
  for (let i = 0; i < 3; i++) {
    const next = out.replace(JUNK_TAIL_RE, '')
    if (next === out) break
    out = next
  }
  return out
}

function cleanSteamTitle(raw: string): string {
  const stripped = raw
    .replace(TRADEMARK_RE, '')
    .replace(COLON_NO_SPACE_RE, ': ')
    .replace(SPACES_RE, ' ')
    .trim()
  const cleaned = stripJunkTail(stripped)
    .replace(BRACKETED_EDITION_RE, '')
    .replace(DASHED_EDITION_RE, '')
    .replace(DASHED_QUALIFIER_RE, '')
    .replace(TRAILING_EDITION_RE, '')
    .replace(DANGLING_RE, '')
    .trim()
  // Never search for an empty string (e.g. a game literally named "Edition").
  return cleaned === '' ? stripped : cleaned
}

// ---- Pass 2 / Pass 3 search terms ------------------------------------------

// Possessive "author / publisher" prefixes that IGDB and Steam often disagree on.
// The possessive is required, so "Marvel Rivals" or "Disney Dreamlight Valley" are untouched.
const PUBLISHER_PREFIX_RE = new RegExp(
  String.raw`^(?:${[
    'tom clancy',
    'sid meier',
    'marvel',
    'disney',
    'clive barker',
    'stephen king',
    'peter jackson',
    'ken follett',
    'frank herbert',
    'terry pratchett',
    'michael crichton',
    'bram stoker',
  ].join('|')})['’]?s\s+`,
  'i',
)

/** Pass 2 term: "Tom Clancy's Rainbow Six Siege" -> "Rainbow Six Siege". Null when there is no prefix. */
function stripPublisherPrefix(title: string): string | null {
  const stripped = title.replace(PUBLISHER_PREFIX_RE, '').trim()
  return stripped !== title && stripped.length >= 3 ? stripped : null
}

// Colon, or a *spaced* dash. An in-word hyphen ("Half-Life", "Spider-Man", "Counter-Strike") is not a split point.
const SUBTITLE_SPLIT_RE = /\s*:\s*|\s+[-–—]\s+/

/** Pass 3 term: "ARK: Survival Evolved" -> "ARK". Null when there is no subtitle to drop. */
function primaryTitle(title: string): string | null {
  const head = (title.split(SUBTITLE_SPLIT_RE)[0] ?? '').trim()
  return head.length >= 2 && head.length < title.length ? head : null
}

// ---- Validating IGDB hits --------------------------------------------------

const COMBINING_MARKS_RE = /[̀-ͯ]/g
const LEADING_THE_RE = /^the /

/** Comparison key: case, punctuation, apostrophes, accents, ™/® and a leading "the" don't matter. */
function normalizeTitle(s: string): string {
  return s
    .replace(TRADEMARK_RE, '')
    .normalize('NFKD')
    .replace(COMBINING_MARKS_RE, '')
    .toLowerCase()
    .replace(APOSTROPHE_RE, '') // "Clancy's" -> "clancys", not "clancy s"
    .replace(/&/g, ' and ')
    .replace(/[^\p{L}\p{N}]+/gu, ' ') // "Need for Speed: Heat" == "Need for Speed Heat"
    .trim()
    .replace(LEADING_THE_RE, '')
}

// Sequel markers (2, VI, XIII…). A bare "X" is excluded: "Rainbow Six Siege X" is the same game.
const SEQUEL_TOKEN_RE = /^(?:\d+|i{1,3}|iv|vi{0,3}|ix|xi{1,3}|xiv|xvi{0,3}|xix|xx)$/
// Words that mean "this is something other than the base game".
const NON_BASE_TOKENS = new Set([
  'soundtrack', 'ost', 'dlc', 'demo', 'bundle', 'pack', 'artbook', 'expansion',
  'upgrade', 'sdk', 'editor', 'wallpaper', 'skin', 'skins',
])

/**
 * How well does an IGDB name match a Steam title? 0 = reject, 1 = same name.
 *   1      names are identical once case / punctuation / accents are ignored
 *   <1     one name is the other plus trailing words ("… Siege" vs "… Siege X"),
 *          accepted only when the shorter has 2+ words, makes up at least
 *          PREFIX_MIN_RATIO of the longer, and the extra words are not a sequel
 *          number or "soundtrack"/"dlc"/…. With the ratio at 0.8 a single extra
 *          word is tolerated only after 4+ shared words, so "Need for Speed
 *          Payback" can never resolve to "Need for Speed", nor "Far Cry 3 Blood
 *          Dragon" to "Far Cry 3".
 *   <0.4   loose tier: a *numbered* Steam title that IGDB has given a subtitle
 *          ("Dying Light 2" -> "Dying Light 2 Stay Human"). The Steam title must be
 *          the shorter side, end in a sequel number, and IGDB may add at most
 *          LOOSE_MAX_EXTRA_WORDS plain words. Always scores below the 0.8 tier, so it
 *          only wins when no better candidate is among the search results, and the
 *          candidate with the fewest extra words wins among loose ones.
 *   0      anything else
 */
function matchScore(title: string, candidate: string): number {
  const a = normalizeTitle(title)
  const b = normalizeTitle(candidate)
  if (!a || !b) return 0
  if (a === b) return 1

  const ta = a.split(' ')
  const tb = b.split(' ')
  const [short, long] = ta.length <= tb.length ? [ta, tb] : [tb, ta]
  if (short.length < 2 || !short.every((t, i) => t === long[i])) return 0
  const extra = long.slice(short.length)
  if (extra.some((t) => SEQUEL_TOKEN_RE.test(t) || NON_BASE_TOKENS.has(t))) return 0
  const ratio = short.length / long.length
  if (ratio >= PREFIX_MIN_RATIO) return ratio

  const steamIsShort = short === ta
  if (
    steamIsShort &&
    SEQUEL_TOKEN_RE.test(short[short.length - 1]) &&
    extra.length <= LOOSE_MAX_EXTRA_WORDS
  ) {
    return ratio / 2
  }
  return 0
}

/**
 * Choose the IGDB result for a Steam title, or null when none is trustworthy.
 * `targets` are the spellings the hit may match: the cleaned title, plus the
 * prefix-stripped one in Pass 2 (IGDB may list "Civilization VI" for Steam's
 * "Sid Meier's Civilization VI"). Test/beta/server entries are never accepted.
 * Best score wins; ties prefer a PC release, then one with a cover — so sequels
 * can't override the original and the top search hit is never taken blindly.
 */
function pickBest(results: IgdbGame[], targets: string[]): IgdbGame | null {
  let best: IgdbGame | null = null
  let bestRank: number[] = []
  for (const g of results) {
    if (!g.name || isNonGameBuild(g.name)) continue
    const name = g.name
    const score = Math.max(...targets.map((t) => matchScore(t, name)))
    if (score === 0) continue
    const rank = [
      score,
      g.platforms?.some((p) => p.name?.includes('PC (Microsoft Windows)')) ? 1 : 0,
      g.cover?.url ? 1 : 0,
    ]
    if (!best || outranks(rank, bestRank)) {
      best = g
      bestRank = rank
    }
  }
  return best
}

/** Lexicographic: is rank `a` strictly better than rank `b`? */
function outranks(a: number[], b: number[]): boolean {
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return a[i] > b[i]
  }
  return false
}

/**
 * Junk-filter, dedupe, and translate Steam's list into our UUID format.
 * `nonGames` lists the test / beta / server builds that were dropped.
 */
function toSteamEntries(raw: SteamGame[]): {
  entries: SteamEntry[]
  junk: number
  nonGames: string[]
} {
  const byId = new Map<string, SteamEntry>()
  const nonGames: string[] = []
  let junk = 0
  for (const g of raw) {
    const title = (g.name ?? '').trim()
    if (!title || typeof g.appid !== 'number') continue
    if (JUNK_RE.test(title)) {
      junk++
      continue
    }
    if (isNonGameBuild(title)) {
      nonGames.push(title)
      continue
    }
    const id = steamUuid(g.appid)
    byId.set(id, {
      id,
      title,
      hours: Math.round(((g.playtime_forever ?? 0) / 60) * 100) / 100,
    })
  }
  return { entries: [...byId.values()], junk, nonGames }
}

/** `games.release_year` must be NULL or 1950-2100 (`games_release_year_check`). */
function sanitizeReleaseYear(year: unknown): number | null {
  return typeof year === 'number' && Number.isInteger(year) && year >= 1950 && year <= 2100
    ? year
    : null
}

/**
 * IGDB `first_release_date` (UNIX seconds, UTC) -> 4-digit year, or null when the
 * value is missing, malformed, or falls outside 1950-2100.
 */
function releaseYearFromUnixSeconds(seconds: unknown): number | null {
  if (typeof seconds !== 'number' || !Number.isFinite(seconds)) return null
  return sanitizeReleaseYear(new Date(seconds * 1000).getUTCFullYear())
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
    release_year: releaseYearFromUnixSeconds(g.first_release_date),
    genres: (g.genres ?? []).map((x) => x.name).filter((n): n is string => !!n),
    summary: g.summary ?? '',
    cover_url: coverUrl,
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

/** Record a warning once (a failing IGDB repeats the same message for every batch). */
const warn = (warnings: string[], message: string) => {
  if (!warnings.includes(message)) warnings.push(message)
}

/**
 * Exact-name lookup for a batch of titles. `~` is IGDB's case-insensitive equals,
 * which matters because Steam shouts ("FOR HONOR™", "PUBG: BATTLEGROUNDS") while
 * IGDB doesn't ("For Honor"). If IGDB rejects the OR-chained query for any reason,
 * retry once with the case-sensitive `= (...)` list form so the pass still works.
 */
async function igdbExactBatch(titles: string[]): Promise<IgdbGame[]> {
  try {
    const where = titles.map((t) => `name ~ ${quote(t)}`).join(' | ')
    return await igdbFetch<IgdbGame[]>('games', `fields ${IGDB_FIELDS}; where ${where}; limit 500;`)
  } catch (e) {
    console.warn('IGDB case-insensitive bulk lookup failed, retrying with "=":', e)
    return await igdbFetch<IgdbGame[]>(
      'games',
      `fields ${IGDB_FIELDS}; where name = (${titles.map(quote).join(',')}); limit 500;`,
    )
  }
}

/** Bulk exact lookup for many titles, indexed by normalized IGDB name. A failed batch is skipped, not fatal. */
async function igdbExactMany(titles: string[], warnings: string[]): Promise<Map<string, IgdbGame[]>> {
  const byName = new Map<string, IgdbGame[]>()
  let failures = 0
  for (const part of chunk(titles, IGDB_TITLE_BATCH)) {
    if (failures >= IGDB_MAX_CONSECUTIVE_FAILURES) break
    try {
      for (const g of await igdbExactBatch(part)) {
        if (!g.name) continue
        const key = normalizeTitle(g.name)
        const list = byName.get(key)
        if (list) list.push(g)
        else byName.set(key, [g])
      }
      failures = 0
    } catch (e) {
      failures++
      console.error('IGDB exact lookup failed:', e)
      warn(warnings, `IGDB exact lookup incomplete: ${(e as Error).message}`)
    }
    await sleep(IGDB_PACING_MS)
  }
  return byName
}

/**
 * Fuzzy `search` for one term. This is a plain `/games` request on purpose:
 * inside `/multiquery` IGDB ignores `fields` for a `search` block and answers with
 * bare ids (or nothing), so there are no names to validate and every hit is lost.
 */
async function igdbSearchOne(term: string): Promise<IgdbGame[]> {
  return await igdbFetch<IgdbGame[]>(
    'games',
    `search ${quote(term)}; fields ${IGDB_FIELDS}; limit ${IGDB_SEARCH_LIMIT};`,
  )
}

/**
 * Fuzzy search for many terms: one request each, started at most every
 * IGDB_PACING_MS (so ~3.8 req/s across all workers) with up to
 * IGDB_SEARCH_CONCURRENCY in flight.
 *
 * `results` lines up with `terms`: an array (possibly empty) means the term was
 * searched; `undefined` means it was not (its request failed, or the run stopped
 * early), so the caller can leave it for the next sync instead of treating it as
 * "IGDB has nothing". A failed request never throws. The run stops early, with
 * `stopped: true`, after IGDB_MAX_CONSECUTIVE_SEARCH_FAILURES errors in a row or
 * once `deadline` has passed.
 */
async function igdbSearchMany(
  terms: string[],
  warnings: string[],
  deadline: number,
): Promise<{ results: (IgdbGame[] | undefined)[]; stopped: boolean }> {
  const results: (IgdbGame[] | undefined)[] = terms.map(() => undefined)
  let next = 0
  let nextSlot = 0 // earliest time the next request may start
  let failures = 0
  let stopped = false

  const worker = async () => {
    while (!stopped && next < terms.length) {
      const i = next++
      if (Date.now() >= deadline) {
        stopped = true
        warn(warnings, 'IGDB search stopped early (time budget); the rest will be matched on the next sync')
        return
      }
      // Reserve a start slot. JS is single-threaded, so this is race-free and keeps
      // request starts IGDB_PACING_MS apart no matter how many workers there are.
      const startAt = Math.max(Date.now(), nextSlot)
      nextSlot = startAt + IGDB_PACING_MS
      await sleep(startAt - Date.now())
      if (stopped) return
      try {
        results[i] = await igdbSearchOne(terms[i])
        failures = 0
      } catch (e) {
        failures++
        console.error('IGDB search failed:', e)
        warn(warnings, `IGDB search incomplete: ${(e as Error).message}`)
        if (failures >= IGDB_MAX_CONSECUTIVE_SEARCH_FAILURES) stopped = true
      }
    }
  }
  await Promise.all(
    Array.from({ length: Math.min(IGDB_SEARCH_CONCURRENCY, terms.length) }, worker),
  )
  return { results, stopped }
}

/** Per-game state while a Steam title works its way through the passes. */
interface Pending {
  entry: SteamEntry
  clean: string // Pass 1 term
  stripped: string | null // Pass 2 term: publisher prefix removed
  primary: string | null // Pass 3 term: text before the first ":" / " - "
  tried: Set<string> // normalized search terms already sent, so a pass never repeats one
}

type PassName = 'exact' | 'search' | 'prefix_stripped' | 'subtitle_split'

/** The fuzzy-search passes, in order. Each yields the term to search, or null to skip that game. */
const SEARCH_PASSES: { name: PassName; term: (p: Pending) => string | null }[] = [
  { name: 'search', term: (p) => p.clean },
  { name: 'prefix_stripped', term: (p) => p.stripped },
  { name: 'subtitle_split', term: (p) => p.primary },
]

/**
 * Resolve Steam games missing from the cache to IGDB records.
 *
 *   Clean    Strip ™/®, edition suffixes and "Test Server"/"Open Beta" junk.
 *   Pass 1   Cleaned title. A bulk, case-insensitive exact-name query (the 1–2
 *            request happy path), then a fuzzy `search` for whatever it missed.
 *   Pass 2   Publisher prefix stripped ("Tom Clancy's Rainbow Six Siege" ->
 *            "Rainbow Six Siege"). Only for titles that have such a prefix.
 *   Pass 3   Primary title only, split at ":" or " - " ("ARK: Survival Evolved"
 *            -> "ARK"). Only for titles that have a subtitle.
 *
 * Every hit is validated with `pickBest`, always against the *full* title, so a
 * broad Pass-3 search for "ARK" can only ever resolve to the game actually named
 * "ARK: Survival Evolved" — never to an unrelated "Ark". A title that no pass can
 * validate stays unmatched instead of being saved as the wrong game.
 *
 * Games are searched most-played first and the fuzzy passes share a budget of
 * IGDB_SEARCH_BUDGET requests (identical terms are searched once), so a long tail of
 * unmatchable apps can't starve the games a user actually plays. An IGDB failure
 * never aborts the sync: whatever matched so far is kept, and games that could not
 * be searched (budget, errors or time) are counted in `deferred` for the next sync.
 */
async function resolveMissingGames(missing: SteamEntry[], warnings: string[]) {
  const matched = new Map<string, IgdbGame>()
  const byPass: Record<PassName, number> = { exact: 0, search: 0, prefix_stripped: 0, subtitle_split: 0 }
  if (missing.length === 0) return { matched, unmatched: [] as string[], deferred: 0, byPass }

  const pending: Pending[] = missing.map((entry) => {
    const clean = cleanSteamTitle(entry.title)
    return {
      entry,
      clean,
      stripped: stripPublisherPrefix(clean),
      primary: primaryTitle(clean),
      tried: new Set<string>(),
    }
  })

  const accept = (p: Pending, g: IgdbGame, pass: PassName) => {
    matched.set(p.entry.id, g)
    byPass[pass]++
  }
  const skipped = new Set<string>() // games a pass could not search (budget, error or time)
  const deadline = Date.now() + IGDB_TIME_BUDGET_MS

  try {
    // Pass 1a — bulk case-insensitive exact match on the cleaned title.
    const byName = await igdbExactMany([...new Set(pending.map((p) => p.clean))], warnings)
    let remaining: Pending[] = []
    for (const p of pending) {
      const best = pickBest(byName.get(normalizeTitle(p.clean)) ?? [], [p.clean])
      if (best) accept(p, best, 'exact')
      else remaining.push(p)
    }

    // Most-played first, so the search budget goes to the games people care about.
    remaining.sort((a, b) => b.entry.hours - a.entry.hours)

    // Pass 1b (cleaned title), Pass 2 (prefix stripped), Pass 3 (subtitle split).
    let budget = IGDB_SEARCH_BUDGET
    for (const pass of SEARCH_PASSES) {
      // One search per distinct term; games that share a term share its results.
      const jobs = new Map<string, { term: string; games: Pending[] }>()
      for (const p of remaining) {
        const term = pass.term(p)
        if (!term) continue
        const key = normalizeTitle(term)
        if (p.tried.has(key)) continue
        const job = jobs.get(key)
        if (job) job.games.push(p)
        else jobs.set(key, { term, games: [p] })
      }
      const all = [...jobs.values()]
      const run = all.slice(0, Math.max(0, budget))
      for (const j of all.slice(run.length)) for (const p of j.games) skipped.add(p.entry.id)
      if (run.length === 0) continue
      budget -= run.length

      const { results, stopped } = await igdbSearchMany(run.map((j) => j.term), warnings, deadline)
      run.forEach((j, i) => {
        const hits = results[i]
        if (!hits) {
          for (const p of j.games) skipped.add(p.entry.id) // never searched: retry next sync
          return
        }
        const key = normalizeTitle(j.term)
        for (const p of j.games) {
          p.tried.add(key)
          // Pass 2 may match the stripped spelling too; every other pass must match the full title.
          const targets = pass.name === 'prefix_stripped' ? [p.clean, j.term] : [p.clean]
          const best = pickBest(hits, targets)
          if (best) accept(p, best, pass.name)
        }
      })
      remaining = remaining.filter((p) => !matched.has(p.entry.id))
      // IGDB is failing or out of time: don't spend the next passes' requests on it.
      if (stopped) {
        for (const p of remaining) skipped.add(p.entry.id)
        break
      }
      if (remaining.length === 0) break
    }
  } catch (e) {
    console.error('IGDB lookup failed:', e)
    warn(warnings, `IGDB lookup incomplete: ${(e as Error).message}`)
  }

  const unmatched = missing.filter((m) => !matched.has(m.id)).map((m) => m.title)
  const deferred = [...skipped].filter((id) => !matched.has(id)).length
  return { matched, unmatched, deferred, byPass }
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

/** The user's existing `user_games` rows, keyed by game_id (minus NOT_RESENT_COLUMNS). */
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
    for (const row of data ?? []) {
      const copy = { ...(row as Record<string, unknown>) }
      for (const col of NOT_RESENT_COLUMNS) delete copy[col]
      byGame.set(row.game_id as string, copy)
    }
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
  const { entries, junk, nonGames } = toSteamEntries(owned)
  const ids = entries.map((e) => e.id)

  // 2. Global cache check + the user's current library, in parallel.
  const [cachedIds, existingByGame] = ids.length
    ? await Promise.all([
        fetchCachedGameIds(admin, ids),
        fetchExistingUserGames(admin, userId, ids),
      ])
    : [new Set<string>(), new Map<string, Record<string, unknown>>()]
  const missing = entries.filter((e) => !cachedIds.has(e.id))

  // 3. Multi-pass IGDB match for the missing games only.
  const { matched, unmatched, deferred, byPass } = await resolveMissingGames(missing, warnings)

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
      non_game_filtered: nonGames.length,
      candidates: entries.length,
      cached: entries.length - missing.length,
      fetched_from_igdb: matched.size,
      matched_by_pass: byPass,
      added,
      updated,
      unchanged,
      unmatched: unmatched.length,
      deferred,
    },
    unmatched_titles: unmatched.slice(0, 50),
    non_game_titles: nonGames.slice(0, 50), // test / beta / server / demo builds that were skipped
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