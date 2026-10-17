// supabase/functions/igdb-handler/index.ts
//
// Proxies game searches and browse lists to IGDB so the Twitch credentials never
// ship in the app. Only logged-in Supabase users may call it.
//
// Request  (POST, JSON): { "query": "zelda", "limit": 20, "offset": 0 }
//                        or, to browse instead of search:
//                        { "mode": "popular" | "top_rated" | "new_releases",
//                          "limit": 20, "offset": 0 }
//                        limit optional, 1-50; offset optional, for paging.
//                        With a `mode` the `query` is ignored. Modes:
//                          popular       most popular first (IGDB visits)
//                          top_rated     best total_rating, with more than 50 ratings
//                          new_releases  released in the last 90 days, newest first
//                        (the queries live in _shared/browse_queries.ts)
//          Header:       Authorization: Bearer <user access token>
// Response (JSON):       the raw IGDB /v4/games array, or
//                        { "error": "...", "code": "...", "retry_after"?: seconds }
//                        An offset at or past MAX_RESULTS answers `[]`.
//                        Failures carry a `Retry-After` header when a retry makes
//                        sense. A 429 from IGDB / Twitch is first retried with a
//                        short exponential backoff (_shared/backoff.ts); only a
//                        limit that outlasts that is reported, and then this
//                        instance answers further searches IGDB_RATE_LIMITED
//                        without calling IGDB for up to a minute. Codes:
//                          IGDB_RATE_LIMITED (429)  IGDB / Twitch is limiting requests
//                          IGDB_UNAVAILABLE  (503)  IGDB / Twitch is down or unreachable
//                          IGDB_ERROR        (502)  IGDB / Twitch refused our request
//                          UNAUTHENTICATED   (401)  no valid user session
//                          BAD_REQUEST       (400 / 405)
//                          NOT_CONFIGURED    (500)  missing secrets
//                          INTERNAL          (500)  anything else
//
// Secrets (set with `supabase secrets set`):
//   TWITCH_CLIENT_ID
//   TWITCH_CLIENT_SECRET
// SUPABASE_URL and SUPABASE_ANON_KEY are injected automatically by Supabase.

import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  type BackoffOptions,
  fetchWithBackoff,
  parseRetryAfter,
} from "../_shared/backoff.ts";
import {
  type BrowseMode,
  gamesByIdQuery,
  inRankOrder,
  isBrowseMode,
  newReleasesQuery,
  popularityQuery,
  rankedGameIds,
  topRatedQuery,
} from "../_shared/browse_queries.ts";

const TWITCH_TOKEN_URL = "https://id.twitch.tv/oauth2/token";
const IGDB_GAMES_URL = "https://api.igdb.com/v4/games";
const IGDB_POPULARITY_URL = "https://api.igdb.com/v4/popularity_primitives";

// The Apicalypse query is built here, not by the client, so this function can't
// be used as an open proxy to spend your IGDB quota on arbitrary queries.
const GAME_FIELDS = [
  "name",
  "cover.url",
  "first_release_date",
  "total_rating",
  "total_rating_count",
  "platforms.id",
  "platforms.name",
  "genres.name",
  "summary",
  "involved_companies.company.name",
].join(", ");

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;
const MAX_QUERY_LENGTH = 100;
// How deep a search may be paged. IGDB's relevance ranking is noise long before
// this, and every page costs a request against the Twitch/IGDB quota.
const MAX_RESULTS = 200;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type ErrorCode =
  | "IGDB_RATE_LIMITED"
  | "IGDB_UNAVAILABLE"
  | "IGDB_ERROR"
  | "UNAUTHENTICATED"
  | "BAD_REQUEST"
  | "NOT_CONFIGURED"
  | "INTERNAL";

class HttpError extends Error {
  constructor(
    public status: number,
    public code: ErrorCode,
    message: string,
    public retryAfter?: number, // seconds
  ) {
    super(message);
  }
}

const DEFAULT_RETRY_AFTER_S = 60;

// A search is something a person is waiting on, so a 429 is retried only briefly:
// two retries, about 3.5 s of waiting at most. Past that the 429 is reported
// (IGDB_RATE_LIMITED + retry_after) and the app shows its own "try again" state.
const BACKOFF: BackoffOptions = {
  retries: 2,
  baseDelayMs: 400,
  maxDelayMs: 2_000,
  budgetMs: 3_500,
};

// While IGDB is limiting us, every further request from this instance would only
// be limited again (and count against us). After a 429 that retrying did not clear,
// answer IGDB_RATE_LIMITED straight away for a short while instead of calling out.
const COOLDOWN_MAX_S = 60;
let rateLimitedUntil = 0; // ms since epoch

function throwIfCoolingDown(): void {
  const remainingMs = rateLimitedUntil - Date.now();
  if (remainingMs > 0) {
    throw new HttpError(
      429,
      "IGDB_RATE_LIMITED",
      "IGDB rate limit reached, try again shortly",
      Math.ceil(remainingMs / 1000),
    );
  }
}

// The error for a non-OK Twitch / IGDB reply: rate limited, down, or our fault.
function upstreamError(res: Response, what: string): HttpError {
  if (res.status === 429) {
    const retryAfter = parseRetryAfter(
      res.headers.get("Retry-After"),
      DEFAULT_RETRY_AFTER_S,
    );
    rateLimitedUntil = Date.now() + Math.min(retryAfter, COOLDOWN_MAX_S) * 1000;
    return new HttpError(
      429,
      "IGDB_RATE_LIMITED",
      "IGDB rate limit reached, try again shortly",
      retryAfter,
    );
  }
  if (res.status >= 500) {
    return new HttpError(
      503,
      "IGDB_UNAVAILABLE",
      "IGDB is unavailable right now",
      parseRetryAfter(res.headers.get("Retry-After"), 120),
    );
  }
  // Another 4xx is our request or credentials being wrong; a retry won't fix it.
  console.error(`${what} failed with status ${res.status}`);
  return new HttpError(502, "IGDB_ERROR", `${what} failed`);
}

function jsonResponse(
  body: unknown,
  status = 200,
  headers: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json", ...headers },
  });
}

function errorResponse(err: HttpError): Response {
  const retryAfter = err.retryAfter;
  return jsonResponse(
    {
      error: err.message,
      code: err.code,
      ...(retryAfter ? { retry_after: retryAfter } : {}),
    },
    err.status,
    retryAfter ? { "Retry-After": String(retryAfter) } : {},
  );
}

// ---------------------------------------------------------------------------
// Twitch app-access token: cached in module scope, so warm instances reuse it.
// ---------------------------------------------------------------------------

type CachedToken = { value: string; expiresAt: number };

let cachedToken: CachedToken | null = null;
let inflightToken: Promise<string> | null = null;

// Refresh a minute early so we never send a token that's about to expire.
const EXPIRY_BUFFER_MS = 60_000;

async function requestNewToken(): Promise<string> {
  const clientId = Deno.env.get("TWITCH_CLIENT_ID");
  const clientSecret = Deno.env.get("TWITCH_CLIENT_SECRET");
  if (!clientId || !clientSecret) {
    console.error("TWITCH_CLIENT_ID / TWITCH_CLIENT_SECRET are not set");
    throw new HttpError(500, "NOT_CONFIGURED", "Server is not configured");
  }

  let res: Response;
  try {
    res = await fetchWithBackoff(() =>
      fetch(TWITCH_TOKEN_URL, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          client_id: clientId,
          client_secret: clientSecret,
          grant_type: "client_credentials",
        }),
      }), BACKOFF);
  } catch (err) {
    console.error("Twitch token request failed:", err);
    throw new HttpError(503, "IGDB_UNAVAILABLE", "Could not reach Twitch", 120);
  }

  if (!res.ok) throw upstreamError(res, "Twitch authentication");

  const data = await res.json().catch(() => null);
  if (typeof data?.access_token !== "string") {
    throw new HttpError(502, "IGDB_ERROR", "Unexpected response from Twitch");
  }

  const ttlSeconds = typeof data.expires_in === "number" ? data.expires_in : 3600;
  cachedToken = {
    value: data.access_token,
    expiresAt: Date.now() + ttlSeconds * 1000,
  };
  return cachedToken.value;
}

async function getToken(forceRefresh = false): Promise<string> {
  if (
    !forceRefresh &&
    cachedToken &&
    Date.now() < cachedToken.expiresAt - EXPIRY_BUFFER_MS
  ) {
    return cachedToken.value;
  }

  // Concurrent requests share a single token request.
  inflightToken ??= requestNewToken().finally(() => {
    inflightToken = null;
  });
  return await inflightToken;
}

// ---------------------------------------------------------------------------
// IGDB
// ---------------------------------------------------------------------------

async function igdbRequest(
  url: string,
  apicalypse: string,
  token: string,
): Promise<Response> {
  try {
    return await fetchWithBackoff(() =>
      fetch(url, {
        method: "POST",
        headers: {
          "Client-ID": Deno.env.get("TWITCH_CLIENT_ID")!,
          "Authorization": `Bearer ${token}`,
          "Accept": "application/json",
          "Content-Type": "text/plain",
        },
        body: apicalypse,
      }), BACKOFF);
  } catch (err) {
    console.error("IGDB request failed:", err);
    throw new HttpError(503, "IGDB_UNAVAILABLE", "Could not reach IGDB", 120);
  }
}

// Strip control characters and escape what would break out of the quoted
// Apicalypse string.
function sanitizeSearchTerm(term: string): string {
  return term
    // deno-lint-ignore no-control-regex
    .replace(/[\u0000-\u001f\u007f]/g, " ")
    .replace(/\\/g, "\\\\")
    .replace(/"/g, '\\"')
    .trim();
}

function parseLimit(value: unknown): number {
  const n = Math.floor(Number(value));
  if (!Number.isFinite(n) || n < 1) return DEFAULT_LIMIT;
  return Math.min(n, MAX_LIMIT);
}

function parseOffset(value: unknown): number {
  const n = Math.floor(Number(value));
  return Number.isFinite(n) && n > 0 ? n : 0;
}

// Runs one Apicalypse query against an IGDB endpoint and returns the parsed body.
async function queryIgdb(url: string, apicalypse: string): Promise<unknown> {
  throwIfCoolingDown();
  let token = await getToken();
  let res = await igdbRequest(url, apicalypse, token);

  // Token revoked or expired early: refresh once and retry.
  if (res.status === 401) {
    token = await getToken(true);
    res = await igdbRequest(url, apicalypse, token);
  }

  if (!res.ok) throw upstreamError(res, "IGDB request");

  return await res.json().catch(() => {
    throw new HttpError(502, "IGDB_ERROR", "Unexpected response from IGDB");
  });
}

function searchGames(
  term: string,
  limit: number,
  offset: number,
): Promise<unknown> {
  return queryIgdb(
    IGDB_GAMES_URL,
    `search "${term}"; fields ${GAME_FIELDS}; limit ${limit}; offset ${offset};`,
  );
}

async function browseGames(
  mode: BrowseMode,
  limit: number,
  offset: number,
): Promise<unknown> {
  switch (mode) {
    case "top_rated":
      return await queryIgdb(
        IGDB_GAMES_URL,
        topRatedQuery(GAME_FIELDS, limit, offset),
      );
    case "new_releases":
      return await queryIgdb(
        IGDB_GAMES_URL,
        newReleasesQuery(GAME_FIELDS, limit, offset, Math.floor(Date.now() / 1000)),
      );
    case "popular": {
      // IGDB ranks game ids on one endpoint and describes games on another.
      const primitives = await queryIgdb(
        IGDB_POPULARITY_URL,
        popularityQuery(limit, offset),
      );
      if (!Array.isArray(primitives)) {
        throw new HttpError(502, "IGDB_ERROR", "Unexpected response from IGDB");
      }
      const ids = rankedGameIds(primitives);
      if (ids.length === 0) return [];
      const games = await queryIgdb(
        IGDB_GAMES_URL,
        gamesByIdQuery(GAME_FIELDS, ids),
      );
      return inRankOrder(ids, games);
    }
  }
}

// ---------------------------------------------------------------------------
// Authentication
// ---------------------------------------------------------------------------

// Throws a 401 unless the request carries a valid *user* access token. The anon
// key (what logged-out clients send) is a valid JWT but has no user behind it,
// so getUser() rejects it.
async function requireUser(req: Request): Promise<void> {
  const authHeader = req.headers.get("Authorization");
  const token = authHeader ? /^Bearer\s+(.+)$/i.exec(authHeader)?.[1] : undefined;
  if (!authHeader || !token) {
    throw new HttpError(401, "UNAUTHENTICATED", "Unauthorized");
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !supabaseAnonKey) {
    console.error("SUPABASE_URL / SUPABASE_ANON_KEY are not set");
    throw new HttpError(500, "NOT_CONFIGURED", "Server is not configured");
  }

  // A per-request client that acts as the caller (their Authorization header).
  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // The token is passed explicitly so verification doesn't depend on a stored session.
  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data?.user) {
    throw new HttpError(401, "UNAUTHENTICATED", "Unauthorized");
  }
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed", code: "BAD_REQUEST" }, 405);
  }

  try {
    await requireUser(req);

    const payload = await req.json().catch(() => null);

    // A `mode` browses a list; without one the request is a text search.
    const mode = payload?.mode ?? null;
    if (mode !== null && !isBrowseMode(mode)) {
      return jsonResponse(
        {
          error: "`mode` must be one of: popular, top_rated, new_releases",
          code: "BAD_REQUEST",
        },
        400,
      );
    }

    const rawQuery = typeof payload?.query === "string" ? payload.query : "";
    const term = sanitizeSearchTerm(rawQuery.slice(0, MAX_QUERY_LENGTH));
    if (mode === null && !term) {
      return jsonResponse(
        { error: "A non-empty `query` string is required", code: "BAD_REQUEST" },
        400,
      );
    }

    const offset = parseOffset(payload?.offset);
    // Past the paging ceiling there is nothing more to give; answer without
    // spending an IGDB request.
    if (offset >= MAX_RESULTS) return jsonResponse([]);

    const limit = parseLimit(payload?.limit);
    const games = mode === null
      ? await searchGames(term, limit, offset)
      : await browseGames(mode, limit, offset);
    return jsonResponse(games);
  } catch (err) {
    if (err instanceof HttpError) return errorResponse(err);
    console.error("Unhandled error in igdb-handler:", err);
    return jsonResponse({ error: "Internal error", code: "INTERNAL" }, 500);
  }
});