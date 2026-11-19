import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import { countRows, validateEnvelope, parseRoute, parseDryRun, MAX_ROWS } from './lib.ts'

const ok = () => ({
  demand_id: 'd1', batch_id: 'b1',
  strata: [{ stratum_id: 's1', population_size: 10, selection_method: 'random', rows: [{}, {}] }],
})
const u = (p: string) => new URL('https://x.test' + p)

Deno.test('valid envelope', () => assertEquals(validateEnvelope(ok()), { ok: true }))
Deno.test('missing batch_id', () => {
  const b: any = ok(); delete b.batch_id
  assertEquals(validateEnvelope(b).ok, false)
})
Deno.test('missing demand_id / non-object / empty strata', () => {
  const b: any = ok(); delete b.demand_id
  assertEquals(validateEnvelope(b).ok, false)
  assertEquals(validateEnvelope(null).ok, false)
  assertEquals(validateEnvelope({ ...ok(), strata: [] }).ok, false)
})
Deno.test('negative / fractional population_size', () => {
  const b: any = ok(); b.strata[0].population_size = -1
  assertEquals(validateEnvelope(b).ok, false)
  b.strata[0].population_size = 1.5
  assertEquals(validateEnvelope(b).ok, false)
})
Deno.test('stratum without rows / without stratum_id / without method', () => {
  const b: any = ok(); delete b.strata[0].rows
  assertEquals(validateEnvelope(b).ok, false)
  const c: any = ok(); delete c.strata[0].stratum_id
  assertEquals(validateEnvelope(c).ok, false)
  const d: any = ok(); delete d.strata[0].selection_method
  assertEquals(validateEnvelope(d).ok, false)
})
Deno.test('countRows sums all strata', () => {
  const b: any = ok(); b.strata.push({ stratum_id: 's2', population_size: 1, selection_method: 'x', rows: [{}, {}, {}] })
  assertEquals(countRows(b), 5)
  assertEquals(countRows(null), 0)
  assertEquals(countRows({ strata: [{}] }), 0)
})
Deno.test('MAX_ROWS is 5000', () => assertEquals(MAX_ROWS, 5000))
Deno.test('parseRoute', () => {
  assertEquals(parseRoute(u('/carrier-link-ingest/demands')), 'demands')
  assertEquals(parseRoute(u('/functions/v1/carrier-link-ingest/batches?dry_run=true')), 'batches')
  assertEquals(parseRoute(u('/carrier-link-ingest/batches/')), 'batches')
  assertEquals(parseRoute(u('/carrier-link-ingest/other')), null)
  assertEquals(parseRoute(u('/carrier-link-ingest')), null)
})
Deno.test('parseDryRun', () => {
  assertEquals(parseDryRun(u('/b?dry_run=true')), true)
  assertEquals(parseDryRun(u('/b?dry_run=false')), false)
  assertEquals(parseDryRun(u('/b')), false)
  assertEquals(parseDryRun(u('/b?dry_run=1')), false)
})

import { extractApiKey, needsSampling, summaryStratumIds } from './lib.ts'

Deno.test('extractApiKey: x-api-key wins over Bearer', () => {
  const h = new Headers({ 'x-api-key': ' k1 ', authorization: 'Bearer k2' })
  assertEquals(extractApiKey(h), 'k1')
})
Deno.test('extractApiKey: Bearer fallback, none, empty bearer', () => {
  assertEquals(extractApiKey(new Headers({ authorization: 'bearer  k2 ' })), 'k2')
  assertEquals(extractApiKey(new Headers()), null)
  assertEquals(extractApiKey(new Headers({ authorization: 'Bearer ' })), null)
  assertEquals(extractApiKey(new Headers({ authorization: 'Basic abc' })), null)
})
Deno.test('needsSampling only for validated', () => {
  assertEquals(needsSampling('validated'), true)
  for (const s of ['sampled', 'undone', 'rejected', 'received', null, undefined]) assertEquals(needsSampling(s), false)
})
Deno.test('summaryStratumIds', () => {
  assertEquals(summaryStratumIds({ strata: [{ stratum_id: 'a' }, { stratum_id: 'b' }, {}] }), ['a', 'b'])
  assertEquals(summaryStratumIds(null), [])
  assertEquals(summaryStratumIds({}), [])
})
