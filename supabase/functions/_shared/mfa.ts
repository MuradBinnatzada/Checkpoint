// supabase/functions/_shared/mfa.ts
//
// Two-factor authentication for the Edge Functions, the same rule as the
// database's (public.mfa_satisfied(), 20261019135155_require_mfa.sql): a member
// who turned it on (a verified authenticator-app factor) only counts as signed in
// once this session entered a code, which makes the access token's `aal` claim
// aal2. Without the check, a token from the password alone could do through a
// function (sync, delete the account) what the tables refuse it.
//
// Each function calls secondFactorMissing() right after getUser() accepted the
// token, with the user it returned (getUser() lists the factors) and answers
// MFA_REQUIRED (403).

/** What the check needs of the user getUser() returns. */
export type FactorsOf = { factors?: ReadonlyArray<{ status?: string; created_at?: string }> | null }

/** Whether [user] has two-factor authentication on: a verified factor. */
export function twoFactorOn(user: FactorsOf): boolean {
  return (user.factors ?? []).some((factor) => factor.status === 'verified')
}

/**
 * The `aal` claim of [token], or null. The signature is not checked here: only
 * call it for a token getUser() has just accepted.
 */
export function tokenAal(token: string): string | null {
  const payload = token.split('.')[1]
  if (!payload) return null
  try {
    const base64 = payload.replace(/-/g, '+').replace(/_/g, '/')
    const padded = base64 + '='.repeat((4 - (base64.length % 4)) % 4)
    const bytes = Uint8Array.from(atob(padded), (c) => c.charCodeAt(0))
    const claims = JSON.parse(new TextDecoder().decode(bytes))
    return typeof claims?.aal === 'string' ? claims.aal : null
  } catch {
    return null
  }
}

/** Whether [user] has two-factor authentication on and [token] has not passed it. */
export function secondFactorMissing(user: FactorsOf, token: string): boolean {
  return twoFactorOn(user) && tokenAal(token) !== 'aal2'
}
