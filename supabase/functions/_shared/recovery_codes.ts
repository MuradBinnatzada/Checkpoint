// supabase/functions/_shared/recovery_codes.ts
//
// Two-factor backup codes (mfa-recovery, 20261019204652_mfa_recovery_codes.sql):
// how they are made, how a typed one is read, and the hash that is stored.
//
// A code is 10 characters of Crockford's base32 (the digits and the capital
// letters without I, L, O and U, so no character reads as another), 50 random
// bits, shown as two groups of five: `7K3QD-M9XHT`. Reading one forgives how
// people type it: lower case, spaces and dashes, and O, I and L for 0, 1 and 1.

import type { FactorsOf } from './mfa.ts'

/** Codes made at a time. */
export const CODE_COUNT = 10

/** Characters in a code, without the dash. */
export const CODE_LENGTH = 10

const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ'

/** Fills [bytes] with random values. The functions use crypto.getRandomValues. */
export type RandomFill = (bytes: Uint8Array) => Uint8Array

const secureRandom: RandomFill = (bytes) => crypto.getRandomValues(bytes)

/**
 * [count] different new codes, unformatted (what normalizeCode() gives back).
 * Each character takes 5 bits of its own random byte; 256 is a multiple of 32,
 * so every character is equally likely.
 */
export function generateCodes(count = CODE_COUNT, random: RandomFill = secureRandom): string[] {
  const codes = new Set<string>()
  // Two of 2^50 codes are the same about never; the cap only stops a broken
  // random source from looping forever.
  for (let tries = 0; codes.size < count; tries++) {
    if (tries >= count * 10) throw new Error('The random source keeps repeating itself')
    const bytes = random(new Uint8Array(CODE_LENGTH))
    codes.add(Array.from(bytes, (b) => ALPHABET[b & 31]).join(''))
  }
  return [...codes]
}

/** [code] (from generateCodes()) as it is shown: two groups of five. */
export function formatCode(code: string): string {
  return `${code.slice(0, CODE_LENGTH / 2)}-${code.slice(CODE_LENGTH / 2)}`
}

/**
 * A typed code the way generateCodes() wrote it: upper case, without spaces and
 * dashes, O as 0, I and L as 1. Null when that is not a possible code.
 */
export function normalizeCode(typed: string): string | null {
  const code = typed
    .toUpperCase()
    .replace(/[\s-]+/g, '')
    .replace(/O/g, '0')
    .replace(/[IL]/g, '1')
  if (code.length !== CODE_LENGTH) return null
  for (const c of code) {
    if (!ALPHABET.includes(c)) return null
  }
  return code
}

/**
 * What the table keeps of [code] (normalized): the SHA-256 of the member's id
 * and the code, as lowercase hex. The id makes the same code hash differently
 * for every member, so one table of precomputed hashes can't serve them all.
 */
export async function hashCode(userId: string, code: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`${userId}:${code}`))
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, '0')).join('')
}

/**
 * The oldest time a code of [user] may have been made and still work: when
 * their oldest verified factor was added (ISO time). Codes from an earlier time
 * two-factor was on (turned off with the switch, then on again) don't count.
 * Null when no verified factor says when it was added: then no code counts.
 */
export function codesValidSince(user: FactorsOf): string | null {
  const times = (user.factors ?? [])
    .filter((factor) => factor.status === 'verified')
    .map((factor) => Date.parse(factor.created_at ?? ''))
    .filter((time) => Number.isFinite(time))
  return times.length === 0 ? null : new Date(Math.min(...times)).toISOString()
}
