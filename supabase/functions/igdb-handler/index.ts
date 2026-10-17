// supabase/functions/igdb-handler/index.ts
//
// Proxies game searches to IGDB so the Twitch credentials never ship in the app.
// Only logged-in Supabase users may call it.
//
// Request  (POST, JSON): { "query": "zelda", "limit": 20, "offset": 0 }
//                        limit optional, 1-50; offset optional, for paging
//          Header:       Authorization: Bearer <user access token>
// Response (JSON):       the raw IGDB /v4/games array, or
//                        { "error": "...", "code": "...", "retry_after"?: seconds }
//                        An offset at or past MAX_RESULTS answers `[]`.
//                        Failures carry a `Retry-After` header when a retry makes
//                        sense. Codes:
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

const TWITCH_TOKEN_URL = "https://id.twitch.tv/oauth2/token";
const IGDB_GAMES_URL = "https://api.igdb.com/v4/games";

// The Apicalypse query is built here, not by the client, so this function can't
// be used as an open proxy to spend your IGDB quota on arbitrary queries.
const GAME_FIELDS = [
  "name",
  "cover.url",
  "first_release_date",
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
const MAX_RETRY_AFTER_S = 3600;

// A `Retry-After` header (delta-seconds or an HTTP date) as whole seconds,
// clamped to 1..MAX_RETRY_AFTER_S. Falls back to `fallback` when absent or unreadable.
function parseRetryAfter(
  value: string | null,
  fallback = DEFAULT_RETRY_AFTER_S,
): number {
  if (value) {
    const seconds = /^\d+$/.test(value.trim())
      ? Number(value)
      : (Date.parse(value) - Date.now()) / 1000;
    if (Number.isFinite(seconds)) {
      return Math.min(Math.max(Math.ceil(seconds), 1), MAX_RETRY_AFTER_S);
    }
  }
  return fallback;
}

// The error for a non-OK Twitch / IGDB reply: rate limited, down, or our fault.
function upstreamError(res: Response, what: string): HttpError {
  if (res.status === 429) {
    return new HttpError(
      429,
      "IGDB_RATE_LIMITED",
      "IGDB rate limit reached, try again shortly",
      parseRetryAfter(res.headers.get("Retry-After")),
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
    res = await fetch(TWITCH_TOKEN_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: clientId,
        client_secret: clientSecret,
        grant_type: "client_credentials",
      }),
    });
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

async function igdbRequest(apicalypse: string, token: string): Promise<Response> {
  try {
    return await fetch(IGDB_GAMES_URL, {
      method: "POST",
      headers: {
        "Client-ID": Deno.env.get("TWITCH_CLIENT_ID")!,
        "Authorization": `Bearer ${token}`,
        "Accept": "application/json",
        "Content-Type": "text/plain",
      },
      body: apicalypse,
    });
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

async function searchGames(
  term: string,
  limit: number,
  offset: number,
): Promise<unknown> {
  const apicalypse =
    `search "${term}"; fields ${GAME_FIELDS}; limit ${limit}; offset ${offset};`;

  let token = await getToken();
  let res = await igdbRequest(apicalypse, token);

  // Token revoked or expired early: refresh once and retry.
  if (res.status === 401) {
    token = await getToken(true);
    res = await igdbRequest(apicalypse, token);
  }

  if (!res.ok) throw upstreamError(res, "IGDB request");

  return await res.json().catch(() => {
    throw new HttpError(502, "IGDB_ERROR", "Unexpected response from IGDB");
  });
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

    const rawQuery = typeof payload?.query === "string" ? payload.query : "";
    const term = sanitizeSearchTerm(rawQuery.slice(0, MAX_QUERY_LENGTH));
    if (!term) {
      return jsonResponse(
        { error: "A non-empty `query` string is required", code: "BAD_REQUEST" },
        400,
      );
    }

    const offset = parseOffset(payload?.offset);
    // Past the paging ceiling there is nothing more to give; answer without
    // spending an IGDB request.
    if (offset >= MAX_RESULTS) return jsonResponse([]);

    const games = await searchGames(term, parseLimit(payload?.limit), offset);
    return jsonResponse(games);
  } catch (err) {
    if (err instanceof HttpError) return errorResponse(err);
    console.error("Unhandled error in igdb-handler:", err);
    return jsonResponse({ error: "Internal error", code: "INTERNAL" }, 500);
  }
});