import { assertEquals } from 'jsr:@std/assert@1'
import {
  classifyFailure,
  DELAYED_RETRY_MIN_MS,
  failureDelayMs,
  FAILURE_BACKOFF_MAX_MS,
  NEEDS_USER_RETRY_MS,
  shouldStopBatch,
  successDelayMs,
  SYNC_INTERVAL_MS,
  UPSTREAM_RETRY_MIN_MS,
} from './sync_schedule.ts'

Deno.test('a finished sync waits the normal interval', () => {
  assertEquals(successDelayMs(false, null), SYNC_INTERVAL_MS)
  assertEquals(successDelayMs(false, 300), SYNC_INTERVAL_MS)
})

Deno.test('a delayed sync comes back sooner, but not before IGDB said it may', () => {
  assertEquals(successDelayMs(true, null), DELAYED_RETRY_MIN_MS)
  assertEquals(successDelayMs(true, 60), DELAYED_RETRY_MIN_MS)
  assertEquals(successDelayMs(true, 7200), 7_200_000)
})

Deno.test('failures are sorted by who has to fix them', () => {
  assertEquals(classifyFailure('STEAM_PROFILE_PRIVATE'), 'needs_user')
  assertEquals(classifyFailure('NO_STEAM_ID'), 'needs_user')
  assertEquals(classifyFailure('STEAM_RATE_LIMITED'), 'upstream')
  assertEquals(classifyFailure('IGDB_UNAVAILABLE'), 'upstream')
  assertEquals(classifyFailure('INTERNAL'), 'other')
  assertEquals(classifyFailure('SOMETHING_NEW'), 'other')
})

Deno.test('a user who has to act is not retried for a week', () => {
  assertEquals(failureDelayMs('STEAM_PROFILE_PRIVATE', 0, null), { delayMs: NEEDS_USER_RETRY_MS, countsAsFailure: true })
})

Deno.test('an upstream limit waits for its Retry-After and does not count against the user', () => {
  assertEquals(failureDelayMs('STEAM_RATE_LIMITED', 4, null), { delayMs: UPSTREAM_RETRY_MIN_MS, countsAsFailure: false })
  assertEquals(failureDelayMs('STEAM_RATE_LIMITED', 4, 3600), { delayMs: 3_600_000, countsAsFailure: false })
})

Deno.test('other failures back off exponentially up to a day', () => {
  const hours = (n: number) => n * 3_600_000
  assertEquals(failureDelayMs('INTERNAL', 0, null).delayMs, hours(1))
  assertEquals(failureDelayMs('INTERNAL', 1, null).delayMs, hours(2))
  assertEquals(failureDelayMs('INTERNAL', 3, null).delayMs, hours(8))
  assertEquals(failureDelayMs('INTERNAL', 10, null).delayMs, FAILURE_BACKOFF_MAX_MS)
  assertEquals(failureDelayMs('INTERNAL', 0, null).countsAsFailure, true)
})

Deno.test('only failures that would hit every user end the batch', () => {
  assertEquals(shouldStopBatch('STEAM_RATE_LIMITED'), true)
  assertEquals(shouldStopBatch('STEAM_UNAVAILABLE'), true)
  assertEquals(shouldStopBatch('NOT_CONFIGURED'), true)
  assertEquals(shouldStopBatch('STEAM_PROFILE_PRIVATE'), false)
  assertEquals(shouldStopBatch('INTERNAL'), false)
})
