// supabase/functions/_shared/cors.ts
//
// The CORS headers of every function's answer. Only browsers read them: the
// Android, iOS and desktop apps send no `Origin` and are never affected.
//
// ALLOWED_ORIGINS (function secret, optional): the web app's origins, comma
// separated, exactly as the browser sends them, e.g.
//   supabase secrets set ALLOWED_ORIGINS=https://checkpoint.example.com,http://localhost:3000
// Set, a page on any other origin can't call the functions from a browser. Not
// set, every origin may ("*"), as before. Either way the functions only act for
// the member whose token is in the Authorization header (never a cookie), so
// another site can't act as a signed-in member.

const ALLOW_HEADERS = 'authorization, x-client-info, apikey, content-type'

/** The origins in ALLOWED_ORIGINS, or null when it is not set (any origin). */
export function parseAllowedOrigins(raw: string | undefined | null): Set<string> | null {
  const origins = (raw ?? '')
    .split(',')
    .map((origin) => origin.trim().replace(/\/+$/, ''))
    .filter((origin) => origin.length > 0)
  return origins.length === 0 ? null : new Set(origins)
}

/** The CORS headers for a request from [origin] (null: no Origin header). */
export function corsHeadersFor(
  origin: string | null,
  allowed: Set<string> | null,
): Record<string, string> {
  const headers: Record<string, string> = {
    'Access-Control-Allow-Headers': ALLOW_HEADERS,
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  }
  if (allowed === null) {
    headers['Access-Control-Allow-Origin'] = '*'
    return headers
  }
  // The answer depends on the Origin, so caches must keep one copy per origin.
  headers['Vary'] = 'Origin'
  if (origin !== null && allowed.has(origin)) headers['Access-Control-Allow-Origin'] = origin
  return headers
}

/**
 * Wraps a function's request handler: answers the browser's preflight (OPTIONS)
 * itself and puts the CORS headers on every answer the handler gives.
 */
export function withCors(
  handler: (req: Request) => Response | Promise<Response>,
): (req: Request) => Promise<Response> {
  const allowed = parseAllowedOrigins(Deno.env.get('ALLOWED_ORIGINS'))
  return async (req) => {
    const cors = corsHeadersFor(req.headers.get('Origin'), allowed)
    if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

    const res = await handler(req)
    const headers = new Headers(res.headers)
    for (const [name, value] of Object.entries(cors)) headers.set(name, value)
    return new Response(res.body, { status: res.status, statusText: res.statusText, headers })
  }
}
