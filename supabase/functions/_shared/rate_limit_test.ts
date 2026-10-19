import { assertEquals } from 'jsr:@std/assert@1'
import { RATE_LIMITS, rateLimitWait, type RpcClient, waitSeconds } from './rate_limit.ts'

function client(answer: { data: unknown; error: unknown }, calls: unknown[] = []): RpcClient {
  return {
    rpc(fn, args) {
      calls.push({ fn, args })
      return Promise.resolve(answer)
    },
  }
}

Deno.test('the database is asked with the member, bucket and limit', async () => {
  const calls: unknown[] = []
  const wait = await rateLimitWait(client({ data: 0, error: null }, calls), 'u1', RATE_LIMITS.igdb)
  assertEquals(wait, 0)
  assertEquals(calls, [{
    fn: 'consume_rate_limit',
    args: { target_user: 'u1', bucket_name: 'igdb-handler', max_hits: 200, window_seconds: 60 },
  }])
})

Deno.test('over the limit, the seconds to wait come back', async () => {
  assertEquals(await rateLimitWait(client({ data: 42, error: null }), 'u1', RATE_LIMITS.steamSync), 42)
})

Deno.test('a limiter that fails never blocks the call', async () => {
  const failing: RpcClient = { rpc: () => Promise.reject(new Error('down')) }
  assertEquals(await rateLimitWait(failing, 'u1', RATE_LIMITS.igdb), 0)
  assertEquals(await rateLimitWait(client({ data: null, error: { message: 'boom' } }), 'u1', RATE_LIMITS.igdb), 0)
})

Deno.test('odd answers read as "go ahead" or whole seconds', () => {
  assertEquals(waitSeconds(null), 0)
  assertEquals(waitSeconds('x'), 0)
  assertEquals(waitSeconds(-3), 0)
  assertEquals(waitSeconds(2.2), 3)
  assertEquals(waitSeconds('15'), 15)
})
