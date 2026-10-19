// supabase/functions/_shared/steam_openid.ts
//
// "Sign in through Steam" (OpenID 2.0) for steam-link: the address that sends a
// member to Steam, the checks on what Steam sends back, the signed state that
// ties the round trip to the member who started it, and the signed confirmation
// the confirm page posts back to save the Steam ID. Steam tells us one thing,
// the SteamID64 of the account that signed in; never a password or anything else.

export const STEAM_OPENID_ENDPOINT = 'https://steamcommunity.com/openid/login'

const OPENID_NS = 'http://specs.openid.net/auth/2.0'
const IDENTIFIER_SELECT = 'http://specs.openid.net/auth/2.0/identifier_select'

// Steam's claimed id is its own address with the account's SteamID64.
const CLAIMED_ID = /^https?:\/\/steamcommunity\.com\/openid\/id\/(\d{17})$/

// What Steam's signature must cover: anything outside it could have been
// changed or added on the way.
const MUST_BE_SIGNED = ['op_endpoint', 'claimed_id', 'identity', 'return_to', 'response_nonce']

/** How long a started link may take: signing in at Steam, Steam Guard included. */
export const STATE_LIFETIME_SECONDS = 600

/** Longest `return_to` accepted (the app's own addresses are far shorter). */
const MAX_RETURN_URL = 500

/** Steam's sign-in page, which sends the browser back to [returnTo] when done. */
export function steamLoginUrl(returnTo: string): string {
  const params = new URLSearchParams({
    'openid.ns': OPENID_NS,
    'openid.mode': 'checkid_setup',
    'openid.return_to': returnTo,
    // Steam shows the realm on its page: "Sign in to <realm>".
    'openid.realm': `${new URL(returnTo).origin}/`,
    'openid.identity': IDENTIFIER_SELECT,
    'openid.claimed_id': IDENTIFIER_SELECT,
  })
  return `${STEAM_OPENID_ENDPOINT}?${params}`
}

/** What the browser brought back from Steam, before Steam has confirmed it. */
export type Assertion =
  | { kind: 'cancelled' }
  | { kind: 'invalid'; reason: string }
  | { kind: 'claimed'; steamId: string }

/**
 * Reads Steam's answer, sent to [returnTo] (exactly the address the sign-in was
 * started with, state included). A `claimed` answer is only a claim until Steam
 * confirms it: see [checkAuthenticationForm].
 */
export function readAssertion(params: URLSearchParams, returnTo: string): Assertion {
  const invalid = (reason: string): Assertion => ({ kind: 'invalid', reason })
  // Steam sends each field once. These checks read a field's first copy, so a
  // second one could put another account's id past them while Steam is asked
  // to confirm the genuine answer.
  const keys = [...params.keys()]
  if (new Set(keys).size !== keys.length) return invalid('repeated')
  const mode = params.get('openid.mode')
  if (mode === 'cancel') return { kind: 'cancelled' }
  if (mode !== 'id_res') return invalid('mode')
  if (params.get('openid.ns') !== OPENID_NS) return invalid('ns')
  if (params.get('openid.op_endpoint') !== STEAM_OPENID_ENDPOINT) return invalid('op_endpoint')
  // Steam signs return_to, and the state is in it: an answer given for one
  // member's sign-in can't be carried over to another's.
  if (params.get('openid.return_to') !== returnTo) return invalid('return_to')
  const signed = (params.get('openid.signed') ?? '').split(',')
  if (!MUST_BE_SIGNED.every((field) => signed.includes(field))) return invalid('signed')
  if (!params.get('openid.sig') || !params.get('openid.assoc_handle')) return invalid('sig')
  const claimed = params.get('openid.claimed_id') ?? ''
  if (params.get('openid.identity') !== claimed) return invalid('identity')
  const match = CLAIMED_ID.exec(claimed)
  if (!match) return invalid('claimed_id')
  return { kind: 'claimed', steamId: match[1] }
}

/**
 * The form to post to [STEAM_OPENID_ENDPOINT] (never to an address taken from the
 * answer) to have Steam confirm an answer: its `openid.*` fields as they came,
 * with the mode `check_authentication`. Each field is the copy [readAssertion]
 * checked, its first, so Steam confirms the very answer whose id is saved.
 */
export function checkAuthenticationForm(params: URLSearchParams): URLSearchParams {
  const form = new URLSearchParams()
  for (const key of new Set(params.keys())) {
    if (key.startsWith('openid.')) form.set(key, params.get(key) ?? '')
  }
  form.set('openid.mode', 'check_authentication')
  return form
}

/** Whether Steam's reply to check_authentication (`key:value` lines) confirms the answer. */
export function confirmedBySteam(reply: string): boolean {
  for (const line of reply.split('\n')) {
    const colon = line.indexOf(':')
    if (colon > 0 && line.slice(0, colon).trim() === 'is_valid') {
      return line.slice(colon + 1).trim() === 'true'
    }
  }
  return false
}

// ---- Where the browser goes when the link is done ----------------------------

/**
 * Whether the browser may be sent to [url] when the link is done: the app on the
 * member's own computer (plain http on a loopback address, any port: the desktop
 * app listens there, and so does the web app under `flutter run`), or the web
 * app. With ALLOWED_ORIGINS set (cors.ts) the web app is one of its origins;
 * without it any https address, the way CORS then allows any origin.
 */
export function returnUrlAllowed(url: string, allowedOrigins: Set<string> | null): boolean {
  if (url.length > MAX_RETURN_URL) return false
  let parsed: URL
  try {
    parsed = new URL(url)
  } catch {
    return false
  }
  if (parsed.username || parsed.password) return false
  if (parsed.protocol === 'http:') {
    return ['127.0.0.1', 'localhost', '[::1]'].includes(parsed.hostname)
  }
  if (parsed.protocol !== 'https:') return false
  return allowedOrigins === null || allowedOrigins.has(parsed.origin)
}

/** [returnTo] with the outcome as `steam_link`: `ok` or an error code. */
export function withLinkResult(returnTo: string, result: string): string {
  const url = new URL(returnTo)
  url.searchParams.set('steam_link', result)
  return url.toString()
}

// ---- The signed state ---------------------------------------------------------

/** Who started a link, where the browser goes after it, and until when it counts. */
export type LinkState = {
  userId: string
  returnTo: string | null
  /** Unix seconds. */
  expiresAt: number
}

/**
 * The key that signs states (HMAC-SHA256), derived from [secret] (the service
 * role key) for this use only, so there is no secret of its own to set.
 */
export async function stateKey(secret: string): Promise<CryptoKey> {
  const encoder = new TextEncoder()
  const root = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const derived = await crypto.subtle.sign('HMAC', root, encoder.encode('checkpoint steam-link state v1'))
  return crypto.subtle.importKey('raw', derived, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify'])
}

/** [state] as `<payload>.<signature>`, both base64url, safe in a URL as it is. */
export async function signState(state: LinkState, key: CryptoKey): Promise<string> {
  const payload = base64Url(new TextEncoder().encode(JSON.stringify({
    u: state.userId,
    r: state.returnTo,
    x: state.expiresAt,
    // Makes every sign-in's return address its own.
    n: base64Url(crypto.getRandomValues(new Uint8Array(12))),
  })))
  const signature = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(payload))
  return `${payload}.${base64Url(new Uint8Array(signature))}`
}

/**
 * The state in [token], or null when this function did not sign it (or it was
 * changed). Whether it has expired is the caller's to check.
 */
export async function openState(token: string, key: CryptoKey): Promise<LinkState | null> {
  const parts = token.split('.')
  if (parts.length !== 2) return null
  const [payload, signature] = parts
  const signatureBytes = fromBase64Url(signature)
  const payloadBytes = fromBase64Url(payload)
  if (signatureBytes === null || payloadBytes === null) return null
  // crypto.subtle.verify compares in constant time.
  const genuine = await crypto.subtle.verify('HMAC', key, signatureBytes, new TextEncoder().encode(payload))
  if (!genuine) return null
  try {
    const data = JSON.parse(new TextDecoder().decode(payloadBytes))
    if (typeof data?.u !== 'string' || typeof data?.x !== 'number') return null
    return {
      userId: data.u,
      returnTo: typeof data.r === 'string' ? data.r : null,
      expiresAt: data.x,
    }
  } catch {
    return null
  }
}

// ---- The confirmation ---------------------------------------------------------

/**
 * Longest a checked answer waits for its confirmation on the confirm page. It
 * never outlives the sign-in's state, which the apps wait for.
 */
export const CONFIRM_LIFETIME_SECONDS = 300

/** Until when the confirm page may save what Steam confirmed for [state]. */
export const confirmationExpiry = (state: LinkState, now: number) =>
  Math.min(now + CONFIRM_LIFETIME_SECONDS, state.expiresAt)

/** What a confirmation token stands for, once [openConfirmation] has checked it. */
export type Confirmation = {
  state: LinkState
  steamId: string
  /** Unix seconds. */
  expiresAt: number
}

// Signed apart from states: a state signature covers its base64url payload
// alone, which never has this prefix, so neither passes for the other.
const CONFIRM_PREFIX = 'checkpoint steam-link confirm v1\n'

const confirmationText = (stateToken: string, steamId: string, expiry: string) =>
  new TextEncoder().encode(`${CONFIRM_PREFIX}${stateToken}\n${steamId}\n${expiry}`)

/**
 * The token the confirm page posts back to save [steamId], once Steam has
 * confirmed it for the sign-in [stateToken] stands for:
 * `<state>.<steamId>.<expiresAt>.<signature>`, safe in a URL as it is. Saving
 * needs no second word from Steam (it confirms an answer once); the token is
 * what says this one was confirmed, for this sign-in.
 */
export async function signConfirmation(
  stateToken: string,
  steamId: string,
  expiresAt: number,
  key: CryptoKey,
): Promise<string> {
  const signature = await crypto.subtle.sign('HMAC', key, confirmationText(stateToken, steamId, String(expiresAt)))
  return `${stateToken}.${steamId}.${expiresAt}.${base64Url(new Uint8Array(signature))}`
}

/**
 * The confirmation in [token], or null when this function did not sign it (or
 * it, or the state in it, was changed). Whether it has expired is the caller's
 * to check.
 */
export async function openConfirmation(token: string, key: CryptoKey): Promise<Confirmation | null> {
  const parts = token.split('.')
  if (parts.length !== 5) return null
  const [payload, stateSignature, steamId, expiry, signature] = parts
  if (!/^\d{17}$/.test(steamId) || !/^\d{1,12}$/.test(expiry)) return null
  const signatureBytes = fromBase64Url(signature)
  if (signatureBytes === null) return null
  const stateToken = `${payload}.${stateSignature}`
  const genuine = await crypto.subtle.verify('HMAC', key, signatureBytes, confirmationText(stateToken, steamId, expiry))
  if (!genuine) return null
  const state = await openState(stateToken, key)
  return state === null ? null : { state, steamId, expiresAt: Number(expiry) }
}

/**
 * The confirm page at [pageUrl], given [token] and the address of the function
 * it posts back to ([functionUrl]). Both go after `#`, which the browser never
 * sends to the page's server or in a Referer.
 */
export function confirmPageUrl(pageUrl: string, token: string, functionUrl: string): string {
  const url = new URL(pageUrl)
  url.hash = new URLSearchParams({ t: token, f: functionUrl }).toString()
  return url.toString()
}

/**
 * The confirm page's address from STEAM_LINK_CONFIRM_URL ([raw]): null when it
 * is not set, 'invalid' when it is not an https (or loopback http) address.
 */
export function confirmPageSetting(raw: string | undefined): string | null | 'invalid' {
  const url = raw?.trim() ?? ''
  if (url === '') return null
  return returnUrlAllowed(url, null) ? url : 'invalid'
}

/** What steam-link does with a Steam ID Steam has confirmed: see [afterSteamConfirmed]. */
export type NextStep =
  | { kind: 'save' }
  | { kind: 'confirm'; page: string }
  | { kind: 'not_configured' }

/**
 * What steam-link does once Steam has confirmed [steamId] for the sign-in
 * [stateToken] stands for, by [confirmPage] ([confirmPageSetting]):
 *  * an address: nothing is saved yet. The browser goes to the confirm page with
 *    a confirmation ([signConfirmation]), and the page has it saved once the
 *    person who signed in to Steam says so;
 *  * null (not set: on `supabase start`, or a backend without the web app): it
 *    is saved right away, as before the confirm page existed;
 *  * 'invalid': neither, since saving right away is what the setting was there
 *    to stop.
 */
export async function afterSteamConfirmed(
  confirmPage: string | null | 'invalid',
  signIn: { stateToken: string; state: LinkState; steamId: string },
  now: number,
  key: CryptoKey,
  functionUrl: string,
): Promise<NextStep> {
  if (confirmPage === null) return { kind: 'save' }
  if (confirmPage === 'invalid') return { kind: 'not_configured' }
  const { stateToken, state, steamId } = signIn
  const token = await signConfirmation(stateToken, steamId, confirmationExpiry(state, now), key)
  return { kind: 'confirm', page: confirmPageUrl(confirmPage, token, functionUrl) }
}

function base64Url(bytes: Uint8Array): string {
  let binary = ''
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

function fromBase64Url(text: string): Uint8Array<ArrayBuffer> | null {
  if (!/^[A-Za-z0-9_-]*$/.test(text)) return null
  try {
    const binary = atob(text.replace(/-/g, '+').replace(/_/g, '/'))
    return Uint8Array.from(binary, (c) => c.charCodeAt(0))
  } catch {
    return null
  }
}
