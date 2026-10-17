import { assertEquals } from 'jsr:@std/assert@1'
import {
  backoffDelayMs,
  fetchWithBackoff,
  MAX_RETRY_AFTER_S,
  parseRetryAfter,
  retryAfterSeconds,
} from './backoff.ts'

const NOW = Date.parse('2026-01-01T00:00:00Z')

Deno.test('retryAfterSeconds reads delta-seconds and HTTP dates, clamped to 1..max', () => {
  assertEquals(retryAfterSeconds('30'), 30)
  assertEquals(retryAfterSeconds(' 7 '), 7)
  assertEquals(retryAfterSeconds('0'), 1)
  assertEquals(retryAfterSeconds('999999'), MAX_RETRY_AFTER_S)
  assertEquals(retryAfterSeconds('Thu, 01 Jan 2026 00:01:30 GMT', NOW), 90)
  assertEquals(retryAfterSeconds('Wed, 31 Dec 2025 00:00:00 GMT', NOW), 1) // already past
})

Deno.test('retryAfterSeconds is null for a missing or unreadable header, parseRetryAfter falls back', () => {
  assertEquals(retryAfterSeconds(null), null)
  assertEquals(retryAfterSeconds(''), null)
  assertEquals(retryAfterSeconds('soon'), null)
  assertEquals(parseRetryAfter(null), 120)
  assertEquals(parseRetryAfter('soon', 60), 60)
  assertEquals(parseRetryAfter('45', 60), 45)
})

Deno.test('backoffDelayMs doubles, is capped, and keeps at least half the step', () => {
  assertEquals(backoffDelayMs(0, 1000, 8000, () => 1), 1000)
  assertEquals(backoffDelayMs(1, 1000, 8000, () => 1), 2000)
  assertEquals(backoffDelayMs(2, 1000, 8000, () => 1), 4000)
  assertEquals(backoffDelayMs(5, 1000, 8000, () => 1), 8000) // capped
  assertEquals(backoffDelayMs(2, 1000, 8000, () => 0), 2000) // jitter floor: half the step
  assertEquals(backoffDelayMs(2, 1000, 8000, () => 0.5), 3000)
})

/** A fetch stand-in that answers with `statuses` in order (the last one repeats). */
function scripted(statuses: number[], headers: Record<number, Record<string, string>> = {}) {
  let calls = 0
  const attempt = () => {
    const status = statuses[Math.min(calls, statuses.length - 1)]
    const res = new Response(status === 200 ? 'ok' : 'limited', { status, headers: headers[calls] })
    calls++
    return Promise.resolve(res)
  }
  return { attempt, calls: () => calls }
}

function sleeper() {
  const waits: number[] = []
  return { sleep: (ms: number) => (waits.push(ms), Promise.resolve()), waits }
}

Deno.test('fetchWithBackoff passes a success straight through', async () => {
  const s = scripted([200])
  const { sleep, waits } = sleeper()
  const res = await fetchWithBackoff(s.attempt, { retries: 3, baseDelayMs: 100, maxDelayMs: 1000, sleep })
  assertEquals(res.status, 200)
  assertEquals(s.calls(), 1)
  assertEquals(waits, [])
})

Deno.test('fetchWithBackoff retries a 429 with exponential waits until it succeeds', async () => {
  const s = scripted([429, 429, 200])
  const { sleep, waits } = sleeper()
  const res = await fetchWithBackoff(s.attempt, {
    retries: 3,
    baseDelayMs: 100,
    maxDelayMs: 1000,
    sleep,
    random: () => 1,
  })
  assertEquals(res.status, 200)
  assertEquals(s.calls(), 3)
  assertEquals(waits, [100, 200])
})

Deno.test('fetchWithBackoff returns the 429 once the retries are used up', async () => {
  const s = scripted([429])
  const { sleep, waits } = sleeper()
  const res = await fetchWithBackoff(s.attempt, { retries: 2, baseDelayMs: 100, maxDelayMs: 1000, sleep, random: () => 1 })
  assertEquals(res.status, 429)
  assertEquals(s.calls(), 3) // the first attempt and two retries
  assertEquals(waits, [100, 200])
})

Deno.test('fetchWithBackoff waits for a Retry-After that fits', async () => {
  const s = scripted([429, 200], { 0: { 'Retry-After': '2' } })
  const { sleep, waits } = sleeper()
  const res = await fetchWithBackoff(s.attempt, { retries: 3, baseDelayMs: 100, maxDelayMs: 5000, sleep })
  assertEquals(res.status, 200)
  assertEquals(waits, [2000])
})

Deno.test('fetchWithBackoff does not hold the caller for a Retry-After beyond maxDelayMs', async () => {
  const s = scripted([429, 200], { 0: { 'Retry-After': '120' } })
  const { sleep, waits } = sleeper()
  const res = await fetchWithBackoff(s.attempt, { retries: 3, baseDelayMs: 100, maxDelayMs: 5000, sleep })
  assertEquals(res.status, 429)
  assertEquals(res.headers.get('Retry-After'), '120') // still there for the caller to pass on
  assertEquals(s.calls(), 1)
  assertEquals(waits, [])
})

Deno.test('fetchWithBackoff stops when the waits would exceed the time budget', async () => {
  const s = scripted([429])
  const { sleep, waits } = sleeper()
  const res = await fetchWithBackoff(s.attempt, {
    retries: 10,
    baseDelayMs: 100,
    maxDelayMs: 1000,
    budgetMs: 350,
    sleep,
    random: () => 1,
  })
  assertEquals(res.status, 429)
  assertEquals(waits, [100, 200]) // the next wait (400) would pass the 350 ms budget
  assertEquals(s.calls(), 3)
})

Deno.test('fetchWithBackoff leaves other errors alone unless asked to retry them', async () => {
  const plain = scripted([503, 200])
  const a = sleeper()
  assertEquals((await fetchWithBackoff(plain.attempt, { retries: 3, baseDelayMs: 100, maxDelayMs: 1000, sleep: a.sleep })).status, 503)
  assertEquals(plain.calls(), 1)

  const asked = scripted([503, 200])
  const b = sleeper()
  const res = await fetchWithBackoff(asked.attempt, {
    retries: 3,
    baseDelayMs: 100,
    maxDelayMs: 1000,
    statuses: [429, 503],
    sleep: b.sleep,
    random: () => 1,
  })
  assertEquals(res.status, 200)
  assertEquals(b.waits, [100])
})
