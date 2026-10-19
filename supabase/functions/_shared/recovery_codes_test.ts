import { assertEquals, assertMatch, assertNotEquals, assertThrows } from 'jsr:@std/assert@1'
import {
  CODE_COUNT,
  codesValidSince,
  formatCode,
  generateCodes,
  hashCode,
  normalizeCode,
} from './recovery_codes.ts'

/** A random source that counts up from [start], one byte at a time. */
function counting(start = 0) {
  let next = start
  return (bytes: Uint8Array) => {
    for (let i = 0; i < bytes.length; i++) bytes[i] = next++ & 255
    return bytes
  }
}

Deno.test('ten different codes of Crockford base32 are made', () => {
  const codes = generateCodes()
  assertEquals(codes.length, CODE_COUNT)
  assertEquals(new Set(codes).size, CODE_COUNT)
  for (const code of codes) assertMatch(code, /^[0-9A-HJKMNP-TV-Z]{10}$/)
})

Deno.test('each character comes from 5 bits of its own byte', () => {
  // Bytes 0..9, then 10..19.
  assertEquals(generateCodes(2, counting()), ['0123456789', 'ABCDEFGHJK'])
  // 32..41 have the same 5 bits as 0..9.
  assertEquals(generateCodes(1, counting(32)), ['0123456789'])
  // The top three bits are dropped: 255 is 31, the last character.
  assertEquals(generateCodes(1, (bytes) => bytes.fill(255)), ['ZZZZZZZZZZ'])
})

Deno.test('a random source that keeps repeating itself is refused', () => {
  assertThrows(() => generateCodes(2, (bytes) => bytes.fill(7)), Error, 'repeating')
})

Deno.test('a code is shown as two groups of five', () => {
  assertEquals(formatCode('7K3QDM9XHT'), '7K3QD-M9XHT')
})

Deno.test('a typed code is read the way it was written', () => {
  assertEquals(normalizeCode('7K3QD-M9XHT'), '7K3QDM9XHT')
  assertEquals(normalizeCode(' 7k3qd m9xht '), '7K3QDM9XHT')
  assertEquals(normalizeCode('7K3QD--M9X-HT'), '7K3QDM9XHT')
  // O, I and L are read as 0, 1 and 1, which they look like.
  assertEquals(normalizeCode('OIL00-11111'), '0110011111')
  for (const code of generateCodes()) assertEquals(normalizeCode(formatCode(code)), code)
})

Deno.test('what cannot be a code is no code', () => {
  assertEquals(normalizeCode(''), null)
  assertEquals(normalizeCode('7K3QD-M9XH'), null) // too short
  assertEquals(normalizeCode('7K3QD-M9XHTT'), null) // too long
  assertEquals(normalizeCode('7K3QD-M9XHU'), null) // U is not in the alphabet
  assertEquals(normalizeCode('7K3QD_M9XHT'), null)
  assertEquals(normalizeCode('7K3QD-M9XH%'), null)
})

Deno.test('the hash is the SHA-256 of the member and the code, in hex', async () => {
  assertEquals(
    await hashCode('u1', '7K3QDM9XHT'),
    'c28595cc07f0b1730f1489ddab6a232ca1158208fa4fcb7f9cece23841c4ca95',
  )
  assertMatch(await hashCode('00000000-0000-4000-8000-000000000001', 'ZZZZZZZZZZ'), /^[0-9a-f]{64}$/)
  // The same code is a different hash for another member.
  assertNotEquals(await hashCode('u2', '7K3QDM9XHT'), await hashCode('u1', '7K3QDM9XHT'))
})

Deno.test('codes count from when the oldest verified factor was added', () => {
  assertEquals(
    codesValidSince({
      factors: [
        { status: 'verified', created_at: '2026-10-19T12:00:00.123456Z' },
        { status: 'verified', created_at: '2026-10-19T09:30:00Z' },
        // A setup that was never finished says nothing.
        { status: 'unverified', created_at: '2026-10-01T00:00:00Z' },
      ],
    }),
    '2026-10-19T09:30:00.000Z',
  )
  // Microseconds are cut to milliseconds, never rounded up past the factor.
  assertEquals(
    codesValidSince({ factors: [{ status: 'verified', created_at: '2026-10-19T12:00:00.123999Z' }] }),
    '2026-10-19T12:00:00.123Z',
  )
})

Deno.test('without a verified factor that says when, no code counts', () => {
  assertEquals(codesValidSince({}), null)
  assertEquals(codesValidSince({ factors: null }), null)
  assertEquals(codesValidSince({ factors: [{ status: 'unverified', created_at: '2026-10-19T12:00:00Z' }] }), null)
  assertEquals(codesValidSince({ factors: [{ status: 'verified' }] }), null)
  assertEquals(codesValidSince({ factors: [{ status: 'verified', created_at: 'yesterday' }] }), null)
})
