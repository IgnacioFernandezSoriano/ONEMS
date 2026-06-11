import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import { buildReadsUrl, parseRetryAfter, isValidRecord, toLandingRow } from './lib.ts'

Deno.test('buildReadsUrl uses cursor when present', () => {
  const url = buildReadsUrl('https://api.example.com/v1/reads', { cursor: 'abc', limit: 1000 })
  assertEquals(url, 'https://api.example.com/v1/reads?cursor=abc&limit=1000')
})

Deno.test('buildReadsUrl uses since when no cursor', () => {
  const url = buildReadsUrl('https://api.example.com/v1/reads', { since: '2024-01-01T00:00:00Z', limit: 500 })
  assertEquals(url, 'https://api.example.com/v1/reads?since=2024-01-01T00%3A00%3A00Z&limit=500')
})

Deno.test('parseRetryAfter parses seconds, defaults on garbage', () => {
  assertEquals(parseRetryAfter('5'), 5)
  assertEquals(parseRetryAfter(null), 1)
  assertEquals(parseRetryAfter('not-a-number'), 1)
})

Deno.test('isValidRecord requires tagId and location', () => {
  assertEquals(isValidRecord({ id: '1', tagId: 't', location: 'a|b|c|d', readerId: 'r', timestamp: 'x', ingested_at: 'y' }), true)
  assertEquals(isValidRecord({ id: '1', tagId: '', location: 'a', readerId: 'r', timestamp: 'x', ingested_at: 'y' }), false)
  assertEquals(isValidRecord({ id: '1', location: 'a', readerId: 'r', timestamp: 'x', ingested_at: 'y' } as never), false)
})

Deno.test('toLandingRow maps provider record to DB columns', () => {
  const row = toLandingRow({
    id: '1a66a44f-c905-4ac4-a8b0-3d1811ef86f0',
    location: 'Brazil | X | Y | GO',
    readerId: 'J11DBRA02100000319',
    tagId: 'urn:oid:1.0.15961.14.B.A00122245737',
    timestamp: '2024-05-07T09:53:06.238-03:00',
    ingested_at: '2024-05-07T12:53:08.412Z',
  })
  assertEquals(row, {
    id: '1a66a44f-c905-4ac4-a8b0-3d1811ef86f0',
    location: 'Brazil | X | Y | GO',
    reader_id: 'J11DBRA02100000319',
    tag_id_raw: 'urn:oid:1.0.15961.14.B.A00122245737',
    read_local_datetime: '2024-05-07T09:53:06.238-03:00',
    ingested_at: '2024-05-07T12:53:08.412Z',
    match_status: 'pending',
  })
})
