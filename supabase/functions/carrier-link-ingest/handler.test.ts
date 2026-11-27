// deno-lint-ignore-file no-import-prefix
import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import { handle, type Deps, type DbError } from './handler.ts'

const FEED = 'f0000000-0000-0000-0000-0000000000a1'
const DID = 'de000000-0000-0000-0000-0000000000a0'
const SHA = 'b'.repeat(64)
const KEY = 'clk_test_key'

interface Call { fn: string; args: Record<string, unknown> }

// Mock of the I/O layer: records RPC calls and answers from a table per function.
function mock(answers: Record<string, { data?: unknown; error?: DbError }> = {}, opt: {
  key?: { id: string; scope: string; feed_id: string | null } | null
  rate?: 'ok' | 'limited' | 'error'
  sign?: string | null
} = {}) {
  const calls: Call[] = []
  const signed: string[] = []
  const usage: string[] = []
  let kicks = 0
  const deps: Deps = {
    resolveKey: (k) => Promise.resolve(k === KEY ? (opt.key === undefined ? { id: 'k1', scope: 'carrier_feed', feed_id: FEED } : opt.key) : null),
    rateLimit: (_id, endpoint) => { usage.push(endpoint); return Promise.resolve(opt.rate ?? 'ok') },
    rpc: (fn, args) => {
      calls.push({ fn, args })
      const a = answers[fn] ?? { data: null }
      return Promise.resolve({ data: a.data ?? null, error: a.error ?? null })
    },
    signUpload: (path) => { signed.push(path); return Promise.resolve(opt.sign === undefined ? `https://s.test/upload/${path}?token=t` : opt.sign) },
    kickWorker: () => { kicks++ },
    log: () => {},
  }
  return { deps, calls, signed, usage, kicks: () => kicks }
}

const req = (method: string, path: string, body?: unknown, headers: Record<string, string> = { 'x-api-key': KEY }) =>
  new Request('https://x.test/functions/v1/carrier-link-ingest' + path, {
    method, headers: { 'Content-Type': 'application/json', ...headers },
    body: body === undefined ? undefined : typeof body === 'string' ? body : JSON.stringify(body),
  })

const openBody = (o: Record<string, unknown> = {}) => ({
  period_start: '2026-11-16', period_end: '2026-11-22', sha256: SHA,
  control_totals: [{ place_ref: 'NBO', delivered: 10 }], format: 'jsonl', size_bytes: 12345, ...o,
})
const summary = (o: Record<string, unknown> = {}) => ({
  delivery_id: DID, feed_id: FEED, status: 'pending_upload', format: 'jsonl', compression: 'none',
  file_path: `acc/${FEED}/${DID}.jsonl`, existing: false, max_file_bytes: 524288000, ...o,
})

// ---------------------------------------------------------------- old routes, unknown routes, methods
Deno.test('v3 routes answer 410 Gone with the new route names, before any authentication or DB call', async () => {
  for (const [m, p] of [['GET', '/demands'], ['POST', '/batches'], ['POST', '/batches?dry_run=true'], ['GET', '/demands/x']]) {
    const t = mock()
    const r = await handle(req(m, p, m === 'POST' ? {} : undefined, {}), t.deps)
    assertEquals(r.status, 410, p)
    const b = await r.json()
    assertEquals(b.error, 'CL_ENDPOINT_GONE')
    assert(String(b.message).includes('POST /deliveries') && String(b.message).includes('GET /config'), b.message)
    assertEquals(t.calls.length + t.usage.length, 0)
  }
})
Deno.test('unknown route 404, wrong method 405 with Allow', async () => {
  const t = mock()
  const r1 = await handle(req('GET', '/nope'), t.deps)
  assertEquals([r1.status, (await r1.json()).error], [404, 'CL_NOT_FOUND'])
  const r2 = await handle(req('POST', '/config', {}), t.deps)
  assertEquals([r2.status, r2.headers.get('Allow')], [405, 'GET'])
  await r2.body?.cancel()
  const r3 = await handle(req('GET', '/deliveries'), t.deps)
  assertEquals([r3.status, r3.headers.get('Allow')], [405, 'POST'])
  await r3.body?.cancel()
  const r4 = await handle(req('GET', `/deliveries/${DID}/complete`), t.deps)
  assertEquals(r4.status, 405)
  await r4.body?.cancel()
  assertEquals(t.calls.length, 0)
})

// ---------------------------------------------------------------- auth and rate limit
Deno.test('auth: missing / wrong key / wrong scope / key without feed -> 401, no RPC', async () => {
  const cases: [Record<string, string>, Parameters<typeof mock>[1]][] = [
    [{}, {}],
    [{ 'x-api-key': 'other' }, {}],
    [{ 'x-api-key': KEY }, { key: { id: 'k1', scope: 'onedb_read', feed_id: FEED } }],
    [{ 'x-api-key': KEY }, { key: { id: 'k1', scope: 'carrier_feed', feed_id: null } }],
  ]
  for (const [h, o] of cases) {
    const t = mock({}, o)
    const r = await handle(req('GET', '/config', undefined, h), t.deps)
    assertEquals([r.status, (await r.json()).error], [401, 'CL_UNAUTHORIZED'])
    assertEquals(t.calls.length, 0)
  }
})
Deno.test('auth: Bearer works like x-api-key', async () => {
  const t = mock({ cl_connector_config: { data: { schema_version: '4.0' } } })
  const r = await handle(req('GET', '/config', undefined, { authorization: `Bearer ${KEY}` }), t.deps)
  assertEquals(r.status, 200)
  assertEquals(await r.json(), { schema_version: '4.0' })
})
Deno.test('rate limit: 429 with Retry-After; usage-log error fails closed (500)', async () => {
  const t = mock({}, { rate: 'limited' })
  const r = await handle(req('GET', '/config'), t.deps)
  assertEquals([r.status, r.headers.get('Retry-After'), (await r.json()).error], [429, '60', 'CL_RATE_LIMITED'])
  assertEquals(t.calls.length, 0)
  const t2 = mock({}, { rate: 'error' })
  const r2 = await handle(req('GET', '/config'), t2.deps)
  assertEquals([r2.status, (await r2.json()).error], [500, 'CL_INTERNAL'])
})

// ---------------------------------------------------------------- GET /config
Deno.test('GET /config: calls cl_connector_config with the key feed only', async () => {
  const t = mock({ cl_connector_config: { data: { schema_version: '4.0', formats: { compression: ['none'] } } } })
  const r = await handle(req('GET', '/config?feed_id=someone-else'), t.deps)
  assertEquals(r.status, 200)
  assertEquals(t.calls, [{ fn: 'cl_connector_config', args: { p_feed_id: FEED } }])
  assertEquals(t.usage, ['/carrier-link-ingest/config'])
  await r.body?.cancel()
})

// ---------------------------------------------------------------- POST /deliveries
Deno.test('POST /deliveries: opens with the key feed, compression never sent, returns a signed PUT URL', async () => {
  const t = mock({ cl_delivery_open: { data: summary() } })
  const r = await handle(req('POST', '/deliveries', openBody({ sha256: SHA.toUpperCase() })), t.deps)
  assertEquals(r.status, 201)
  assertEquals(t.calls, [{
    fn: 'cl_delivery_open',
    args: {
      p_feed_id: FEED, p_period_start: '2026-11-16', p_period_end: '2026-11-22', p_sha256: SHA,
      p_control_totals: [{ place_ref: 'NBO', delivered: 10 }], p_format: 'jsonl', p_size_bytes: 12345,
    },
  }])
  assertEquals(t.signed, [`acc/${FEED}/${DID}.jsonl`])
  const b = await r.json()
  assertEquals(b.delivery.delivery_id, DID)
  assertEquals(b.delivery.file_path, undefined)
  assertEquals(b.upload, {
    url: `https://s.test/upload/acc/${FEED}/${DID}.jsonl?token=t`, method: 'PUT',
    headers: { 'Content-Type': 'application/x-ndjson' }, expires_in_seconds: 7200,
  })
})
Deno.test('POST /deliveries: existing pending delivery -> 200 with a fresh URL; existing received -> no URL', async () => {
  const t = mock({ cl_delivery_open: { data: summary({ existing: true, format: 'csv', file_path: 'p.csv' }) } })
  const r = await handle(req('POST', '/deliveries', openBody({ format: 'csv' })), t.deps)
  const b = await r.json()
  assertEquals([r.status, b.upload.headers['Content-Type']], [200, 'text/csv'])
  const t2 = mock({ cl_delivery_open: { data: summary({ existing: true, status: 'received' }) } })
  const r2 = await handle(req('POST', '/deliveries', openBody()), t2.deps)
  const b2 = await r2.json()
  assertEquals([r2.status, b2.upload, b2.delivery.status, t2.signed.length], [200, null, 'received', 0])
})
Deno.test('POST /deliveries: gzip / compressed format / Content-Encoding refused before the database', async () => {
  for (const body of [openBody({ compression: 'gzip' }), openBody({ format: 'jsonl.gz' }), openBody({ compression: 'zip' })]) {
    const t = mock()
    const r = await handle(req('POST', '/deliveries', body), t.deps)
    assertEquals([r.status, (await r.json()).error], [400, 'CL_COMPRESSION_UNSUPPORTED'])
    assertEquals(t.calls.length, 0)
  }
  const t = mock()
  const r = await handle(req('POST', '/deliveries', openBody(), { 'x-api-key': KEY, 'Content-Encoding': 'gzip' }), t.deps)
  assertEquals([r.status, (await r.json()).error], [400, 'CL_COMPRESSION_UNSUPPORTED'])
  assertEquals(t.calls.length, 0)
})
Deno.test('POST /deliveries: size cap (bucket limit at the edge, connector limit from the DB) -> 413', async () => {
  const t = mock()
  const r = await handle(req('POST', '/deliveries', openBody({ size_bytes: 524288001 })), t.deps)
  assertEquals([r.status, (await r.json()).error], [413, 'CL_FILE_TOO_LARGE'])
  assertEquals(t.calls.length, 0)
  const t2 = mock({ cl_delivery_open: { error: { code: '22023', message: 'CL_FILE_TOO_LARGE: size_bytes 2000 is over the limit of 1000 bytes' } } })
  const r2 = await handle(req('POST', '/deliveries', openBody({ size_bytes: 2000 })), t2.deps)
  const b2 = await r2.json()
  assertEquals([r2.status, b2.error], [413, 'CL_FILE_TOO_LARGE'])
  assert(!JSON.stringify(b2).includes('2000'), 'SQL text is never echoed')
  assertEquals(t2.signed.length, 0)
})
Deno.test('POST /deliveries: invalid JSON, bad fields, body too large', async () => {
  const t = mock()
  const r = await handle(req('POST', '/deliveries', '{not json'), t.deps)
  assertEquals([r.status, (await r.json()).error], [400, 'CL_BAD_REQUEST'])
  const r2 = await handle(req('POST', '/deliveries', openBody({ size_bytes: undefined })), t.deps)
  const b2 = await r2.json()
  assertEquals([r2.status, b2.error], [400, 'CL_BAD_REQUEST'])
  assert(String(b2.detail).includes('size_bytes'))
  const r3 = await handle(req('POST', '/deliveries', openBody({ control_totals: 'x' })), t.deps)
  assertEquals([r3.status, (await r3.json()).error], [400, 'CL_BAD_CONTROL_TOTALS'])
  const big = JSON.stringify(openBody({ control_totals: [{ place_ref: 'x'.repeat(6 * 1024 * 1024), delivered: 1 }] }))
  const r4 = await handle(req('POST', '/deliveries', big), t.deps)
  assertEquals([r4.status, (await r4.json()).error], [413, 'CL_BODY_TOO_LARGE'])
  assertEquals(t.calls.length, 0)
})
Deno.test('POST /deliveries: database errors mapped by the table', async () => {
  const cases: [DbError, number, string][] = [
    [{ code: '22023', message: 'CL_PERIOD_NOT_CLOSED: the period ends on 2026-11-30 (local date today 2026-11-25)' }, 422, 'CL_PERIOD_NOT_CLOSED'],
    [{ code: '22023', message: 'CL_PERIOD_NOT_IN_CALENDAR: the period ending 2026-11-22 must start on 2026-11-16' }, 422, 'CL_PERIOD_NOT_IN_CALENDAR'],
    [{ code: '22023', message: 'CL_NO_ACTIVE_PLAN: no active plan' }, 422, 'CL_NO_ACTIVE_PLAN'],
    [{ code: 'P0001', message: 'CL_PERIOD_ALREADY_DELIVERED: overlaps delivery x' }, 409, 'CL_PERIOD_ALREADY_DELIVERED'],
    [{ code: '22023', message: 'CL_BAD_PERIOD: period_start is after period_end' }, 400, 'CL_BAD_PERIOD'],
    [{ code: '22023', message: 'CL_BAD_CONTROL_TOTALS: each total is ...' }, 400, 'CL_BAD_CONTROL_TOTALS'],
    [{ code: '22023', message: 'CL_FEED_PAUSED: the connector is paused' }, 403, 'CL_FEED_PAUSED'],
    [{ code: '22023', message: 'CL_FEED_NOT_FOUND' }, 404, 'CL_FEED_NOT_FOUND'],
    [{ code: '42501', message: 'permission denied' }, 403, 'CL_FORBIDDEN'],
    [{ code: 'XX000', message: 'boom with a value' }, 500, 'CL_INTERNAL'],
  ]
  for (const [err, status, code] of cases) {
    const t = mock({ cl_delivery_open: { error: err } })
    const r = await handle(req('POST', '/deliveries', openBody()), t.deps)
    const b = await r.json()
    assertEquals([r.status, b.error], [status, code], err.message)
    if (err.message !== code) assert(!JSON.stringify(b).includes(err.message!), 'never echoes SQL text')
  }
})
Deno.test('POST /deliveries: signing error -> 500 without the URL', async () => {
  const t = mock({ cl_delivery_open: { data: summary() } }, { sign: null })
  const r = await handle(req('POST', '/deliveries', openBody()), t.deps)
  assertEquals([r.status, (await r.json()).error], [500, 'CL_INTERNAL'])
})

// ---------------------------------------------------------------- POST /deliveries/{id}/complete
Deno.test('complete: received -> 202 and the worker is nudged', async () => {
  const t = mock({ cl_delivery_complete: { data: summary({ status: 'received', file_bytes: 12345 }) } })
  const r = await handle(req('POST', `/deliveries/${DID}/complete`), t.deps)
  assertEquals(r.status, 202)
  assertEquals(t.calls, [{ fn: 'cl_delivery_complete', args: { p_feed_id: FEED, p_delivery_id: DID } }])
  assertEquals((await r.json()).delivery.status, 'received')
  assertEquals(t.kicks(), 1)
})
Deno.test('complete: already processing / processed -> 200 (idempotent), no nudge', async () => {
  for (const s of ['processing', 'processed', 'failed']) {
    const t = mock({ cl_delivery_complete: { data: summary({ status: s }) } })
    const r = await handle(req('POST', `/deliveries/${DID}/complete`), t.deps)
    assertEquals([r.status, (await r.json()).delivery.status, t.kicks()], [200, s, 0])
  }
})
Deno.test('complete: rejected delivery answers the status of its error code, with the delivery', async () => {
  const cases: [string, number][] = [
    ['CL_FILE_TOO_LARGE', 413], ['CL_PERIOD_ALREADY_DELIVERED', 409], ['CL_SUPERSEDED', 409],
    ['CL_UPLOAD_EXPIRED', 410], ['CL_SHA256_MISMATCH', 422], ['CL_COMPRESSION_UNSUPPORTED', 400],
  ]
  for (const [code, status] of cases) {
    const t = mock({ cl_delivery_complete: { data: summary({ status: 'rejected', error: code }) } })
    const r = await handle(req('POST', `/deliveries/${DID}/complete`), t.deps)
    const b = await r.json()
    assertEquals([r.status, b.error, b.delivery.status, b.delivery.file_path], [status, code, 'rejected', undefined], code)
    assertEquals(t.kicks(), 0)
  }
})
Deno.test('complete: file not uploaded -> 409', async () => {
  const t = mock({ cl_delivery_complete: { error: { code: '22023', message: 'CL_FILE_NOT_UPLOADED: upload the file before completing the delivery' } } })
  const r = await handle(req('POST', `/deliveries/${DID}/complete`), t.deps)
  assertEquals([r.status, (await r.json()).error], [409, 'CL_FILE_NOT_UPLOADED'])
})

// ---------------------------------------------------------------- GET /deliveries/{id}
Deno.test('GET /deliveries/{id}: cl_delivery_status with the key feed', async () => {
  const st = summary({
    status: 'processed', phase: 'done', rows_total: 10, shipments_drawn: 3,
    rejected_reasons: { rows: { bad_timestamp: 1 }, shipments: { no_end: 2 } },
    alerts: [{ type: 'unknown_product', severity: 'medium', details: { values: ['ZZ'] } }],
  })
  const t = mock({ cl_delivery_status: { data: st } })
  const r = await handle(req('GET', `/deliveries/${DID}`), t.deps)
  assertEquals(r.status, 200)
  assertEquals(t.calls, [{ fn: 'cl_delivery_status', args: { p_feed_id: FEED, p_delivery_id: DID } }])
  const b = await r.json()
  assertEquals([b.delivery.phase, b.delivery.shipments_drawn, b.delivery.alerts.length, b.delivery.file_path], ['done', 3, 1, undefined])
})
Deno.test('missing, foreign and malformed delivery ids give the identical 404', async () => {
  const bodies: string[] = []
  // missing or foreign: the DB raises the same CL_DELIVERY_NOT_FOUND for both
  for (const path of [`/deliveries/${DID}`, `/deliveries/${DID}/complete`]) {
    const t = mock({
      cl_delivery_status: { error: { code: '22023', message: 'CL_DELIVERY_NOT_FOUND' } },
      cl_delivery_complete: { error: { code: '22023', message: 'CL_DELIVERY_NOT_FOUND' } },
    })
    const r = await handle(req(path.endsWith('complete') ? 'POST' : 'GET', path), t.deps)
    assertEquals(r.status, 404)
    bodies.push(await r.text())
  }
  // malformed: answered without calling the database
  for (const path of ['/deliveries/not-a-uuid', "/deliveries/x'%20or%201=1/complete"]) {
    const t = mock()
    const r = await handle(req(path.endsWith('complete') ? 'POST' : 'GET', path), t.deps)
    assertEquals(r.status, 404)
    assertEquals(t.calls.length, 0)
    bodies.push(await r.text())
  }
  assertEquals(new Set(bodies).size, 1, bodies.join(' | '))
})

// ---------------------------------------------------------------- final review: malformed URL, empty RPC result
Deno.test('malformed percent-escape in the path -> controlled 400 CL_BAD_REQUEST, no auth or DB work', async () => {
  for (const [m, p] of [['GET', '/deliveries/%E0%A4%A'], ['POST', '/deliveries/%zz/complete']]) {
    const t = mock()
    const r = await handle(req(m, p), t.deps)
    assertEquals([r.status, (await r.json()).error], [400, 'CL_BAD_REQUEST'], p)
    assertEquals(t.calls.length + t.usage.length, 0)
  }
})
Deno.test('null or non-object RPC result -> 500 CL_INTERNAL, never 201/200 with an empty delivery', async () => {
  const cases: [string, string, unknown, Record<string, unknown>][] = [
    ['POST', '/deliveries', openBody(), { cl_delivery_open: { data: null } }],
    ['POST', '/deliveries', openBody(), { cl_delivery_open: { data: 'x' } }],
    ['POST', `/deliveries/${DID}/complete`, undefined, { cl_delivery_complete: { data: null } }],
    ['GET', `/deliveries/${DID}`, undefined, { cl_delivery_status: { data: [summary()] } }],
    ['GET', '/config', undefined, { cl_connector_config: { data: null } }],
  ]
  for (const [m, p, body, answers] of cases) {
    const t = mock(answers as Parameters<typeof mock>[0])
    const r = await handle(req(m, p, body), t.deps)
    assertEquals([r.status, (await r.json()).error], [500, 'CL_INTERNAL'], `${m} ${p}`)
    assertEquals(t.kicks(), 0)
  }
})

// ---------------------------------------------------------------- GET /query
const QCONFIG = {
  connector: { name: 'Sim', carrier: 'SIMPOST' }, date_timezone: 'Africa/Nairobi', include_all_scans: false,
  fields: { item_id: { field: 'tracking_no' }, product: { field: 'service' }, scan_at: { field: 'event_ts', timezone: 'Africa/Nairobi' },
    place_ref: { field: 'site_code' }, mode_ref: { field: 'event_code' } },
  extra_fields: ['weight_g'], mapping_complete: true, products: [{ code: 'SIM-STD', carrier_codes: ['STD'] }],
  points: [{ place_ref: 'EMR-PO', mode_ref: 'ACC', role: 'origin' }, { place_ref: 'NPT-PO', mode_ref: 'DLV', role: 'destination' }],
  next_period: { period_start: '2026-11-02', period_end: '2026-11-04', deliverable: true },
}
Deno.test('GET /query: the PostgreSQL query of the key feed by default', async () => {
  const t = mock({ cl_connector_config: { data: QCONFIG } })
  const r = await handle(req('GET', '/query'), t.deps)
  assertEquals(r.status, 200)
  const b = await r.json()
  assertEquals([b.db, b.tested, b.period_start, b.period_end, b.table_placeholder], ['postgresql', true, '2026-11-02', '2026-11-04', 'carrier_scans'])
  assert(String(b.sql).includes('"tracking_no"'))
  assertEquals(t.calls, [{ fn: 'cl_connector_config', args: { p_feed_id: FEED } }])
  assertEquals(t.usage, ['/carrier-link-ingest/query'])
})
Deno.test('GET /query?db=oracle: untested dialect', async () => {
  const t = mock({ cl_connector_config: { data: QCONFIG } })
  const b = await (await handle(req('GET', '/query?db=oracle'), t.deps)).json()
  assertEquals([b.db, b.tested], ['oracle', false])
})
Deno.test('GET /query?db=mysql: 400 without database work', async () => {
  const t = mock({ cl_connector_config: { data: QCONFIG } })
  const r = await handle(req('GET', '/query?db=mysql'), t.deps)
  assertEquals([r.status, (await r.json()).error], [400, 'CL_BAD_REQUEST'])
  assertEquals(t.calls.length, 0)
})
Deno.test('GET /query: incomplete mapping is 422 CL_MAPPING_INCOMPLETE', async () => {
  const t = mock({ cl_connector_config: { data: { ...QCONFIG, mapping_complete: false } } })
  const r = await handle(req('GET', '/query'), t.deps)
  assertEquals([r.status, (await r.json()).error], [422, 'CL_MAPPING_INCOMPLETE'])
})
Deno.test('GET /query: no key 401, POST 405', async () => {
  const t = mock({ cl_connector_config: { data: QCONFIG } })
  const r1 = await handle(req('GET', '/query', undefined, {}), t.deps)
  assertEquals([r1.status, (await r1.json()).error], [401, 'CL_UNAUTHORIZED'])
  const r2 = await handle(req('POST', '/query', {}), t.deps)
  assertEquals([r2.status, r2.headers.get('Allow')], [405, 'GET'])
  await r2.body?.cancel()
  assertEquals(t.calls.length, 0)
})
Deno.test('GET /query: a blank mapped field name is 422, not 500', async () => {
  const t = mock({ cl_connector_config: { data: { ...QCONFIG, fields: { ...QCONFIG.fields, item_id: { field: '   ' } } } } })
  const r = await handle(req('GET', '/query'), t.deps)
  assertEquals([r.status, (await r.json()).error], [422, 'CL_MAPPING_INCOMPLETE'])
})
