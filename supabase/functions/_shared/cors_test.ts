import { assertEquals } from 'jsr:@std/assert@1'
import { corsHeadersFor, parseAllowedOrigins } from './cors.ts'

Deno.test('no ALLOWED_ORIGINS allows every origin', () => {
  assertEquals(parseAllowedOrigins(undefined), null)
  assertEquals(parseAllowedOrigins(' , '), null)
  assertEquals(corsHeadersFor('https://anywhere.example', null)['Access-Control-Allow-Origin'], '*')
})

Deno.test('ALLOWED_ORIGINS is read as a trimmed list without trailing slashes', () => {
  assertEquals(
    parseAllowedOrigins(' https://app.example/ ,http://localhost:3000'),
    new Set(['https://app.example', 'http://localhost:3000']),
  )
})

Deno.test('a listed origin is echoed back, another gets no allow-origin', () => {
  const allowed = parseAllowedOrigins('https://app.example')
  const ok = corsHeadersFor('https://app.example', allowed)
  assertEquals(ok['Access-Control-Allow-Origin'], 'https://app.example')
  assertEquals(ok['Vary'], 'Origin')

  const other = corsHeadersFor('https://evil.example', allowed)
  assertEquals(other['Access-Control-Allow-Origin'], undefined)
  assertEquals(other['Vary'], 'Origin')
})

Deno.test('a request without an Origin (the native apps) is answered as usual', () => {
  const headers = corsHeadersFor(null, parseAllowedOrigins('https://app.example'))
  assertEquals(headers['Access-Control-Allow-Origin'], undefined)
  assertEquals(headers['Access-Control-Allow-Methods'], 'POST, OPTIONS')
})
