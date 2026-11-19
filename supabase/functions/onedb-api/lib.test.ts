import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import { parseQuery, nextDay, extractApiKey } from './lib.ts'

const u = (qs: string) => new URL('https://x.test/onedb-api?' + qs)

Deno.test('missing dates -> error', () => {
  assertEquals(parseQuery(u('')).ok, false)
  assertEquals(parseQuery(u('start_date=2026-01-01')).ok, false)
})

Deno.test('bad date format -> error', () => {
  assertEquals(parseQuery(u('start_date=01/01/2026&end_date=2026-01-02')).ok, false)
})

Deno.test('defaults and limit cap', () => {
  const r = parseQuery(u('start_date=2026-01-01&end_date=2026-01-31'))
  assertEquals(r, { ok: true, startDate: '2026-01-01', endDate: '2026-01-31', limit: 100, offset: 0, source: null })
  const c = parseQuery(u('start_date=2026-01-01&end_date=2026-01-31&limit=5000'))
  assertEquals(c.ok && c.limit, 1000)
})

Deno.test('invalid limit/offset -> defaults', () => {
  const r = parseQuery(u('start_date=2026-01-01&end_date=2026-01-31&limit=abc&offset=-3'))
  assertEquals(r.ok && [r.limit, r.offset], [100, 0])
})

Deno.test('source validation', () => {
  const base = 'start_date=2026-01-01&end_date=2026-01-31'
  assertEquals(parseQuery(u(base + '&source=otro')).ok, false)
  const r = parseQuery(u(base + '&source=carrier'))
  assertEquals(r.ok && r.source, 'carrier')
})

Deno.test('nextDay handles month/year rollover', () => {
  assertEquals(nextDay('2026-01-31'), '2026-02-01')
  assertEquals(nextDay('2026-12-31'), '2027-01-01')
})

Deno.test('extractApiKey: x-api-key wins over Bearer', () => {
  const h = new Headers({ 'x-api-key': ' k1 ', authorization: 'Bearer k2' })
  assertEquals(extractApiKey(h), 'k1')
})

Deno.test('extractApiKey: Bearer fallback', () => {
  assertEquals(extractApiKey(new Headers({ authorization: 'Bearer k2 ' })), 'k2')
})

Deno.test('extractApiKey: missing or blank -> null', () => {
  assertEquals(extractApiKey(new Headers()), null)
  assertEquals(extractApiKey(new Headers({ 'x-api-key': '   ' })), null)
  assertEquals(extractApiKey(new Headers({ authorization: 'Bearer    ' })), null)
  assertEquals(extractApiKey(new Headers({ authorization: 'Basic abc' })), null)
})
