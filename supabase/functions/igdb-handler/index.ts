// supabase/functions/igdb-handler/index.ts
//
// Proxies game searches to IGDB so the Twitch credentials never ship in the app.
// Only logged-in Supabase users may call it.
//
// Request  (POST, JSON): { "query": "zelda", "limit": 20 }   // limit optional, 1-50
//          Header:       Authorization: Bearer <user access token>
// Response (JSON):       the raw IGDB /v4/games array, or { "error": "..." }
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

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
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
    throw new HttpError(500, "Server is not configured");
  }

  const res = await fetch(TWITCH_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      grant_type: "client_credentials",
    }),
  });

  if (!res.ok) {
    console.error(`Twitch token request failed with status ${res.status}`);
    throw new HttpError(502, "Could not authenticate with Twitch");
  }

  const data = await res.json();
  if (typeof data?.access_token !== "string") {
    throw new HttpError(502, "Unexpected response from Twitch");
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

function igdbRequest(apicalypse: string, token: string): Promise<Response> {
  return fetch(IGDB_GAMES_URL, {
    method: "POST",
    headers: {
      "Client-ID": Deno.env.get("TWITCH_CLIENT_ID")!,
      "Authorization": `Bearer ${token}`,
      "Accept": "application/json",
      "Content-Type": "text/plain",
    },
    body: apicalypse,
  });
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

async function searchGames(term: string, limit: number): Promise<unknown> {
  const apicalypse =
    `search "${term}"; fields ${GAME_FIELDS}; limit ${limit};`;

  let token = await getToken();
  let res = await igdbRequest(apicalypse, token);

  // Token revoked or expired early: refresh once and retry.
  if (res.status === 401) {
    token = await getToken(true);
    res = await igdbRequest(apicalypse, token);
  }

  if (res.status === 429) {
    throw new HttpError(429, "IGDB rate limit reached, try again shortly");
  }
  if (!res.ok) {
    console.error(`IGDB request failed with status ${res.status}`);
    throw new HttpError(502, "IGDB request failed");
  }

  return await res.json();
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
    throw new HttpError(401, "Unauthorized");
  }

  const supabaseUrl = Deno.env.get("");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !supabaseAnonKey) {
    console.error("SUPABASE_URL / SUPABASE_ANON_KEY are not set");
    throw new HttpError(500, "Server is not configured");
  }

  // A per-request client that acts as the caller (their Authorization header).
  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // The token is passed explicitly so verification doesn't depend on a stored session.
  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data?.user) {
    throw new HttpError(401, "Unauthorized");
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
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    await requireUser(req);

    const payload = await req.json().catch(() => null);

    const rawQuery = typeof payload?.query === "string" ? payload.query : "";
    const term = sanitizeSearchTerm(rawQuery.slice(0, MAX_QUERY_LENGTH));
    if (!term) {
      return jsonResponse({ error: "A non-empty `query` string is required" }, 400);
    }

    const games = await searchGames(term, parseLimit(payload?.limit));
    return jsonResponse(games);
  } catch (err) {
    if (err instanceof HttpError) {
      return jsonResponse({ error: err.message }, err.status);
    }
    console.error("Unhandled error in igdb-handler:", err);
    return jsonResponse({ error: "Internal error" }, 500);
  }
});