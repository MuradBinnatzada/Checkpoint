import { assert, assertEquals } from 'jsr:@std/assert@1'
import {
  afterSteamConfirmed,
  checkAuthenticationForm,
  CONFIRM_LIFETIME_SECONDS,
  confirmationExpiry,
  confirmedBySteam,
  confirmPageSetting,
  confirmPageUrl,
  openConfirmation,
  openState,
  readAssertion,
  returnUrlAllowed,
  signConfirmation,
  signState,
  stateKey,
  STEAM_OPENID_ENDPOINT,
  steamLoginUrl,
  withLinkResult,
} from './steam_openid.ts'

const RETURN = 'https://abc.supabase.co/functions/v1/steam-link?state=payload.signature'
const STEAM_ID = '76561198000000000'

/** What Steam sends back after a sign-in, as the browser brings it. */
function answer(changes: Record<string, string | null> = {}): URLSearchParams {
  const params = new URLSearchParams({
    'state': 'payload.signature',
    'openid.ns': 'http://specs.openid.net/auth/2.0',
    'openid.mode': 'id_res',
    'openid.op_endpoint': STEAM_OPENID_ENDPOINT,
    'openid.claimed_id': `https://steamcommunity.com/openid/id/${STEAM_ID}`,
    'openid.identity': `https://steamcommunity.com/openid/id/${STEAM_ID}`,
    'openid.return_to': RETURN,
    'openid.response_nonce': '2026-10-19T13:00:00Zabcdef',
    'openid.assoc_handle': '1234567890',
    'openid.signed': 'signed,op_endpoint,claimed_id,identity,return_to,response_nonce,assoc_handle',
    'openid.sig': 'c2lnbmF0dXJl',
  })
  for (const [key, value] of Object.entries(changes)) {
    if (value === null) params.delete(key)
    else params.set(key, value)
  }
  return params
}

Deno.test('the sign-in page asks Steam to pick the account and come back to the state', () => {
  const url = new URL(steamLoginUrl(RETURN))
  assertEquals(`${url.origin}${url.pathname}`, STEAM_OPENID_ENDPOINT)
  assertEquals(url.searchParams.get('openid.mode'), 'checkid_setup')
  assertEquals(url.searchParams.get('openid.return_to'), RETURN)
  assertEquals(url.searchParams.get('openid.realm'), 'https://abc.supabase.co/')
  assertEquals(
    url.searchParams.get('openid.claimed_id'),
    'http://specs.openid.net/auth/2.0/identifier_select',
  )
})

Deno.test("Steam's answer names the SteamID64 that signed in", () => {
  assertEquals(readAssertion(answer(), RETURN), { kind: 'claimed', steamId: STEAM_ID })
})

Deno.test('a cancelled sign-in is told apart from a bad answer', () => {
  assertEquals(readAssertion(answer({ 'openid.mode': 'cancel' }), RETURN), { kind: 'cancelled' })
  assertEquals(readAssertion(answer({ 'openid.mode': 'setup_needed' }), RETURN).kind, 'invalid')
})

Deno.test("an answer given for another member's sign-in is refused", () => {
  const other = 'https://abc.supabase.co/functions/v1/steam-link?state=other.signature'
  assertEquals(readAssertion(answer(), other), { kind: 'invalid', reason: 'return_to' })
})

Deno.test('an answer from anywhere but Steam is refused', () => {
  assertEquals(
    readAssertion(answer({ 'openid.op_endpoint': 'https://evil.example/openid/login' }), RETURN),
    { kind: 'invalid', reason: 'op_endpoint' },
  )
  const claimed = 'https://evil.example/openid/id/76561198000000000'
  assertEquals(
    readAssertion(answer({ 'openid.claimed_id': claimed, 'openid.identity': claimed }), RETURN),
    { kind: 'invalid', reason: 'claimed_id' },
  )
})

Deno.test('a claimed id outside the signature, or unlike the identity, is refused', () => {
  assertEquals(
    readAssertion(answer({ 'openid.signed': 'op_endpoint,identity,return_to,response_nonce' }), RETURN),
    { kind: 'invalid', reason: 'signed' },
  )
  assertEquals(
    readAssertion(answer({ 'openid.identity': 'https://steamcommunity.com/openid/id/76561198000000001' }), RETURN),
    { kind: 'invalid', reason: 'identity' },
  )
  assertEquals(readAssertion(answer({ 'openid.sig': null }), RETURN), { kind: 'invalid', reason: 'sig' })
})

Deno.test('a claimed id that is not a 17-digit SteamID64 is refused', () => {
  const claimed = 'https://steamcommunity.com/openid/id/123'
  assertEquals(
    readAssertion(answer({ 'openid.claimed_id': claimed, 'openid.identity': claimed }), RETURN).kind,
    'invalid',
  )
})

Deno.test('an answer with a field sent twice is refused', () => {
  const victim = 'https://steamcommunity.com/openid/id/76561198000000001'
  const genuine = [...answer()]
  // Another member's id put before the genuine one, which Steam would confirm.
  const before = new URLSearchParams([['openid.claimed_id', victim], ['openid.identity', victim], ...genuine])
  assertEquals(readAssertion(before, RETURN), { kind: 'invalid', reason: 'repeated' })
  const after = new URLSearchParams([...genuine, ['openid.claimed_id', victim], ['openid.identity', victim]])
  assertEquals(readAssertion(after, RETURN), { kind: 'invalid', reason: 'repeated' })
  const state = new URLSearchParams([['state', 'other.signature'], ...genuine])
  assertEquals(readAssertion(state, RETURN), { kind: 'invalid', reason: 'repeated' })
})

Deno.test('Steam is asked to confirm the copy of each field that was checked', () => {
  const victim = 'https://steamcommunity.com/openid/id/76561198000000001'
  const form = checkAuthenticationForm(new URLSearchParams([['openid.claimed_id', victim], ...answer()]))
  assertEquals(form.getAll('openid.claimed_id'), [victim])
})

Deno.test('Steam is asked to confirm exactly the openid fields it sent', () => {
  const form = checkAuthenticationForm(answer())
  assertEquals(form.get('openid.mode'), 'check_authentication')
  assertEquals(form.get('openid.sig'), 'c2lnbmF0dXJl')
  assertEquals(form.get('openid.claimed_id'), `https://steamcommunity.com/openid/id/${STEAM_ID}`)
  assertEquals(form.has('state'), false)
})

Deno.test("only Steam's is_valid:true confirms an answer", () => {
  assert(confirmedBySteam('ns:http://specs.openid.net/auth/2.0\nis_valid:true\n'))
  assert(confirmedBySteam('ns:http://specs.openid.net/auth/2.0\r\nis_valid:true\r\n'))
  assert(!confirmedBySteam('ns:http://specs.openid.net/auth/2.0\nis_valid:false\n'))
  assert(!confirmedBySteam('<html>is_valid:true</html>'))
  assert(!confirmedBySteam(''))
})

Deno.test('the browser goes back to the app on this computer or to the web app', () => {
  const web = new Set(['https://checkpoint.example'])
  assert(returnUrlAllowed('http://127.0.0.1:49152/steam-link', web))
  assert(returnUrlAllowed('http://localhost:3000/', web))
  assert(returnUrlAllowed('https://checkpoint.example/app/', web))
  assert(!returnUrlAllowed('https://evil.example/', web))
  assert(!returnUrlAllowed('http://checkpoint.example/', web))
  assert(!returnUrlAllowed('http://127.0.0.1.evil.example/', web))
  assert(!returnUrlAllowed('https://user:pass@checkpoint.example/', web))
  assert(!returnUrlAllowed('javascript:alert(1)', web))
  assert(!returnUrlAllowed('not a url', web))
  assert(!returnUrlAllowed(`https://checkpoint.example/${'a'.repeat(500)}`, web))
  // Without ALLOWED_ORIGINS any https address, as CORS allows any origin then.
  assert(returnUrlAllowed('https://anywhere.example/', null))
  assert(!returnUrlAllowed('http://anywhere.example/', null))
})

Deno.test('the outcome goes on the return address, before its fragment', () => {
  assertEquals(withLinkResult('http://127.0.0.1:5000/steam-link', 'ok'), 'http://127.0.0.1:5000/steam-link?steam_link=ok')
  assertEquals(
    withLinkResult('https://checkpoint.example/?a=1#/game/1', 'STEAM_LINK_CANCELLED'),
    'https://checkpoint.example/?a=1&steam_link=STEAM_LINK_CANCELLED#/game/1',
  )
})

Deno.test('a signed state opens to what was signed, and only with its key', async () => {
  const key = await stateKey('service-role-key')
  const state = { userId: 'u1', returnTo: 'http://127.0.0.1:5000/steam-link', expiresAt: 1_800_000_000 }
  const token = await signState(state, key)
  assert(/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(token), token)
  assertEquals(await openState(token, key), state)

  const otherKey = await stateKey('another-project-key')
  assertEquals(await openState(token, otherKey), null)
})

Deno.test('a changed state is refused', async () => {
  const key = await stateKey('service-role-key')
  const token = await signState({ userId: 'u1', returnTo: null, expiresAt: 1_800_000_000 }, key)
  const [payload, signature] = token.split('.')

  // Someone else's id in the payload, the signature kept.
  const forged = btoa(JSON.stringify({ u: 'u2', r: null, x: 1_800_000_000, n: 'x' }))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
  assertEquals(await openState(`${forged}.${signature}`, key), null)
  assertEquals(await openState(`${payload}.${signature.slice(1)}`, key), null)
  assertEquals(await openState(payload, key), null)
  assertEquals(await openState('', key), null)
  assertEquals(await openState('a.b.c', key), null)
  assertEquals(await openState('***.***', key), null)
})

Deno.test('two states for the same member differ', async () => {
  const key = await stateKey('service-role-key')
  const state = { userId: 'u1', returnTo: null, expiresAt: 1_800_000_000 }
  assert(await signState(state, key) !== await signState(state, key))
})

// ---- The confirmation ----------------------------------------------------------

const SIGN_IN = { userId: 'u1', returnTo: 'http://127.0.0.1:5000/steam-link', expiresAt: 1_800_000_600 }

Deno.test('a confirmation opens to the sign-in and the Steam ID it was made for', async () => {
  const key = await stateKey('service-role-key')
  const state = await signState(SIGN_IN, key)
  const token = await signConfirmation(state, STEAM_ID, 1_800_000_300, key)
  assert(/^[A-Za-z0-9_.-]+$/.test(token), token)
  assertEquals(await openConfirmation(token, key), { state: SIGN_IN, steamId: STEAM_ID, expiresAt: 1_800_000_300 })
  assertEquals(await openConfirmation(token, await stateKey('another-project-key')), null)
})

Deno.test('a confirmation with another Steam ID, expiry or sign-in is refused', async () => {
  const key = await stateKey('service-role-key')
  const state = await signState(SIGN_IN, key)
  const token = await signConfirmation(state, STEAM_ID, 1_800_000_300, key)
  const [payload, stateSignature, , , signature] = token.split('.')
  const changed = (parts: string[]) => openConfirmation(parts.join('.'), key)

  // The victim's account put in place of the one Steam confirmed.
  assertEquals(await changed([payload, stateSignature, '76561198000000001', '1800000300', signature]), null)
  assertEquals(await changed([payload, stateSignature, STEAM_ID, '1900000000', signature]), null)
  assertEquals(await changed([payload, stateSignature, STEAM_ID, '01800000300', signature]), null)
  // The signature moved onto another member's sign-in.
  const [otherPayload, otherSignature] = (await signState({ ...SIGN_IN, userId: 'u2' }, key)).split('.')
  assertEquals(await changed([otherPayload, otherSignature, STEAM_ID, '1800000300', signature]), null)
  // A state the key never signed, under a confirmation signed over it.
  const forged = btoa(JSON.stringify({ u: 'u2', r: null, x: 1_800_000_600, n: 'x' }))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
  const forgedToken = await signConfirmation(`${forged}.${stateSignature}`, STEAM_ID, 1_800_000_300, key)
  assertEquals(await openConfirmation(forgedToken, key), null)

  assertEquals(await changed([payload, stateSignature, STEAM_ID, '1800000300']), null)
  assertEquals(await changed([payload, stateSignature, '123', '1800000300', signature]), null)
  assertEquals(await changed([payload, stateSignature, STEAM_ID, '1800000300', '***']), null)
  assertEquals(await openConfirmation('', key), null)
})

Deno.test('a state and a confirmation never pass for each other', async () => {
  const key = await stateKey('service-role-key')
  const state = await signState(SIGN_IN, key)
  assertEquals(await openConfirmation(state, key), null)
  assertEquals(await openConfirmation(`${state}.${STEAM_ID}.1800000300.${state.split('.')[1]}`, key), null)
  const token = await signConfirmation(state, STEAM_ID, 1_800_000_300, key)
  assertEquals(await openState(token, key), null)
})

Deno.test('a confirmation lasts five minutes, never past its sign-in', () => {
  assertEquals(confirmationExpiry(SIGN_IN, 1_800_000_000), 1_800_000_000 + CONFIRM_LIFETIME_SECONDS)
  assertEquals(confirmationExpiry(SIGN_IN, 1_800_000_500), SIGN_IN.expiresAt)
})

Deno.test('the confirm page gets the token and the function after #', () => {
  const fn = 'https://abc.supabase.co/functions/v1/steam-link'
  const url = new URL(confirmPageUrl('https://checkpoint.example/steam-link.html', 'p.s.76561198000000000.1.sig', fn))
  assertEquals(`${url.origin}${url.pathname}${url.search}`, 'https://checkpoint.example/steam-link.html')
  const fragment = new URLSearchParams(url.hash.slice(1))
  assertEquals(fragment.get('t'), 'p.s.76561198000000000.1.sig')
  assertEquals(fragment.get('f'), fn)
  // A fragment already on the page's address is replaced, not added to.
  assertEquals(new URL(confirmPageUrl('https://checkpoint.example/c#old', 't', fn)).hash.includes('old'), false)
})

Deno.test('the confirm step is on only with a confirm page address set', () => {
  assertEquals(confirmPageSetting(undefined), null)
  assertEquals(confirmPageSetting(''), null)
  assertEquals(confirmPageSetting('  '), null)
  assertEquals(
    confirmPageSetting(' https://checkpoint.example/steam-link.html '),
    'https://checkpoint.example/steam-link.html',
  )
  assertEquals(confirmPageSetting('http://127.0.0.1:5000/steam-link.html'), 'http://127.0.0.1:5000/steam-link.html')
  assertEquals(confirmPageSetting('http://checkpoint.example/steam-link.html'), 'invalid')
  assertEquals(confirmPageSetting('checkpoint.example/steam-link.html'), 'invalid')
  assertEquals(confirmPageSetting('javascript:alert(1)'), 'invalid')
})

Deno.test('without a confirm page, a Steam ID Steam confirmed is saved right away', async () => {
  const key = await stateKey('service-role-key')
  const signIn = { stateToken: await signState(SIGN_IN, key), state: SIGN_IN, steamId: STEAM_ID }
  const fn = 'https://abc.supabase.co/functions/v1/steam-link'
  assertEquals(await afterSteamConfirmed(null, signIn, 1_800_000_000, key, fn), { kind: 'save' })
})

Deno.test('with a confirm page, nothing is saved and the page gets a confirmation for it', async () => {
  const key = await stateKey('service-role-key')
  const stateToken = await signState(SIGN_IN, key)
  const signIn = { stateToken, state: SIGN_IN, steamId: STEAM_ID }
  const fn = 'https://abc.supabase.co/functions/v1/steam-link'
  const next = await afterSteamConfirmed('https://checkpoint.example/steam-link.html', signIn, 1_800_000_000, key, fn)
  assert(next.kind === 'confirm', next.kind)
  const page = new URL(next.page)
  assertEquals(`${page.origin}${page.pathname}`, 'https://checkpoint.example/steam-link.html')
  const fragment = new URLSearchParams(page.hash.slice(1))
  assertEquals(fragment.get('f'), fn)
  assertEquals(await openConfirmation(fragment.get('t') ?? '', key), {
    state: SIGN_IN,
    steamId: STEAM_ID,
    expiresAt: 1_800_000_000 + CONFIRM_LIFETIME_SECONDS,
  })
})

Deno.test('with a confirm page address that is not allowed, nothing is saved', async () => {
  const key = await stateKey('service-role-key')
  const signIn = { stateToken: await signState(SIGN_IN, key), state: SIGN_IN, steamId: STEAM_ID }
  const fn = 'https://abc.supabase.co/functions/v1/steam-link'
  assertEquals(await afterSteamConfirmed('invalid', signIn, 1_800_000_000, key, fn), { kind: 'not_configured' })
})
