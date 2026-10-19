import { assertEquals } from 'jsr:@std/assert@1'
import { secondFactorMissing, tokenAal } from './mfa.ts'

/** A JWT with [claims] as its payload (base64url, unpadded) and no real signature. */
function token(claims: Record<string, unknown>): string {
  const base64url = (text: string) =>
    btoa(text).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
  return `${base64url('{"alg":"HS256","typ":"JWT"}')}.${base64url(JSON.stringify(claims))}.signature`
}

const verified = { factors: [{ status: 'verified' }] }

Deno.test('the aal claim is read from the payload', () => {
  assertEquals(tokenAal(token({ sub: 'u1', aal: 'aal2' })), 'aal2')
  assertEquals(tokenAal(token({ sub: 'u1', aal: 'aal1' })), 'aal1')
  // Characters that base64url writes as - and _.
  assertEquals(tokenAal(token({ sub: '>>>???', aal: 'aal2', name: 'ÿÿ' })), 'aal2')
})

Deno.test('a token without the claim, or not a JWT, has no aal', () => {
  assertEquals(tokenAal(token({ sub: 'u1' })), null)
  assertEquals(tokenAal(token({ aal: 2 })), null)
  assertEquals(tokenAal('not-a-jwt'), null)
  assertEquals(tokenAal('a.%%%.c'), null)
  assertEquals(tokenAal(''), null)
})

Deno.test('a member without two-factor is never stopped', () => {
  assertEquals(secondFactorMissing({}, token({ aal: 'aal1' })), false)
  assertEquals(secondFactorMissing({ factors: null }, token({ aal: 'aal1' })), false)
  assertEquals(secondFactorMissing({ factors: [] }, token({ aal: 'aal1' })), false)
  // A setup that was never finished does not turn it on.
  assertEquals(secondFactorMissing({ factors: [{ status: 'unverified' }] }, token({ aal: 'aal1' })), false)
})

Deno.test('a member with two-factor needs an aal2 token', () => {
  assertEquals(secondFactorMissing(verified, token({ aal: 'aal2' })), false)
  assertEquals(secondFactorMissing(verified, token({ aal: 'aal1' })), true)
  assertEquals(secondFactorMissing(verified, token({})), true)
  assertEquals(secondFactorMissing(verified, 'garbage'), true)
  assertEquals(
    secondFactorMissing({ factors: [{ status: 'unverified' }, { status: 'verified' }] }, token({ aal: 'aal1' })),
    true,
  )
})
