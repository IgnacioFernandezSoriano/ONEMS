// deno-lint-ignore-file no-import-prefix
import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import {
  ABSOLUTE_MAX_FILE_BYTES, ERRORS, clCode, extractApiKey, hasCompressedBody, isUuid, parseRoute, publicDelivery,
  sqlErrorToHttp, statusOf, validateOpenRequest,
} from './lib.ts'

const u = (p: string) => new URL('https://x.test' + p)
const SHA = 'a'.repeat(64)
const ok = (o: Record<string, unknown> = {}) => ({
  period_start: '2026-11-16', period_end: '2026-11-22', sha256: SHA, control_totals: [], format: 'jsonl',
  size_bytes: 1000, ...o,
})

// ---------------------------------------------------------------- routing
Deno.test('parseRoute: v4 routes, with or without /functions/v1 and trailing slash', () => {
  assertEquals(parseRoute(u('/carrier-link-ingest/config')), { kind: 'config' })
  assertEquals(parseRoute(u('/functions/v1/carrier-link-ingest/config/')), { kind: 'config' })
  assertEquals(parseRoute(u('/carrier-link-ingest/deliveries')), { kind: 'deliveries' })
  assertEquals(parseRoute(u('/carrier-link-ingest/deliveries/abc')), { kind: 'delivery', id: 'abc' })
  assertEquals(parseRoute(u('/carrier-link-ingest/deliveries/abc/complete')), { kind: 'complete', id: 'abc' })
})
Deno.test('parseRoute: v3 routes are gone, others unknown', () => {
  assertEquals(parseRoute(u('/carrier-link-ingest/demands')), { kind: 'gone' })
  assertEquals(parseRoute(u('/carrier-link-ingest/batches?dry_run=true')), { kind: 'gone' })
  assertEquals(parseRoute(u('/functions/v1/carrier-link-ingest/batches/x/y')), { kind: 'gone' })
  assertEquals(parseRoute(u('/carrier-link-ingest')), null)
  assertEquals(parseRoute(u('/carrier-link-ingest/other')), null)
  assertEquals(parseRoute(u('/carrier-link-ingest/deliveries/a/b')), null)
  assertEquals(parseRoute(u('/carrier-link-ingest/deliveries/a/complete/x')), null)
  assertEquals(parseRoute(u('/elsewhere/config')), null)
})
Deno.test('isUuid', () => {
  assert(isUuid('de000000-0000-0000-0000-0000000000a0'))
  assert(!isUuid('abc'))
  assert(!isUuid("de000000-0000-0000-0000-0000000000a0' or 1=1"))
})

// ---------------------------------------------------------------- auth header
Deno.test('extractApiKey: x-api-key wins over Bearer', () => {
  assertEquals(extractApiKey(new Headers({ 'x-api-key': ' k1 ', authorization: 'Bearer k2' })), 'k1')
})
Deno.test('extractApiKey: Bearer fallback, none, empty bearer, other scheme', () => {
  assertEquals(extractApiKey(new Headers({ authorization: 'bearer  k2 ' })), 'k2')
  assertEquals(extractApiKey(new Headers()), null)
  assertEquals(extractApiKey(new Headers({ authorization: 'Bearer ' })), null)
  assertEquals(extractApiKey(new Headers({ authorization: 'Basic abc' })), null)
})

// ---------------------------------------------------------------- POST /deliveries body
Deno.test('validateOpenRequest: valid body, defaults to jsonl, sha256 lower-cased', () => {
  const r = validateOpenRequest(ok({ format: undefined, sha256: 'A'.repeat(64) }))
  assert(r.ok)
  if (r.ok) {
    assertEquals(r.value.format, 'jsonl')
    assertEquals(r.value.sha256, 'a'.repeat(64))
  }
  assert(validateOpenRequest(ok({ format: 'csv', compression: 'none' })).ok)
  assert(validateOpenRequest(ok({ compression: null })).ok)
})
Deno.test('validateOpenRequest: gzip and any compression refused', () => {
  for (const c of ['gzip', 'zip', 'br', 'zstd', 'GZIP', true, 1]) {
    const r = validateOpenRequest(ok({ compression: c }))
    assertEquals(r.ok ? null : r.code, 'CL_COMPRESSION_UNSUPPORTED', String(c))
  }
  for (const f of ['jsonl.gz', 'csv.gz', 'gzip', 'csv.zip', 'jsonl.bz2']) {
    const r = validateOpenRequest(ok({ format: f }))
    assertEquals(r.ok ? null : r.code, 'CL_COMPRESSION_UNSUPPORTED', f)
  }
})
Deno.test('validateOpenRequest: bad fields', () => {
  const code = (b: unknown) => { const r = validateOpenRequest(b); return r.ok ? 'ok' : r.code }
  assertEquals(code(null), 'CL_BAD_REQUEST')
  assertEquals(code([]), 'CL_BAD_REQUEST')
  assertEquals(code(ok({ format: 'xlsx' })), 'CL_BAD_REQUEST')
  assertEquals(code(ok({ period_start: '2026-02-30' })), 'CL_BAD_REQUEST')
  assertEquals(code(ok({ period_end: '22/11/2026' })), 'CL_BAD_REQUEST')
  assertEquals(code(ok({ sha256: 'abc' })), 'CL_BAD_REQUEST')
  assertEquals(code(ok({ sha256: undefined })), 'CL_BAD_REQUEST')
  assertEquals(code(ok({ recipient_name: 'X' })), 'CL_BAD_REQUEST')
  assertEquals(code(ok({ control_totals: {} })), 'CL_BAD_CONTROL_TOTALS')
  assertEquals(code(ok({ control_totals: undefined })), 'CL_BAD_CONTROL_TOTALS')
  assertEquals(code(ok({ control_totals: new Array(10001).fill({}) })), 'CL_BAD_CONTROL_TOTALS')
})
Deno.test('validateOpenRequest: size_bytes required, positive integer, capped at the bucket limit', () => {
  const code = (b: unknown) => { const r = validateOpenRequest(b); return r.ok ? 'ok' : r.code }
  assertEquals(code(ok({ size_bytes: undefined })), 'CL_BAD_REQUEST')
  assertEquals(code(ok({ size_bytes: 0 })), 'CL_BAD_REQUEST')
  assertEquals(code(ok({ size_bytes: -5 })), 'CL_BAD_REQUEST')
  assertEquals(code(ok({ size_bytes: 1.5 })), 'CL_BAD_REQUEST')
  assertEquals(code(ok({ size_bytes: '1000' })), 'CL_BAD_REQUEST')
  assertEquals(code(ok({ size_bytes: ABSOLUTE_MAX_FILE_BYTES })), 'ok')
  assertEquals(code(ok({ size_bytes: ABSOLUTE_MAX_FILE_BYTES + 1 })), 'CL_FILE_TOO_LARGE')
})
Deno.test('hasCompressedBody', () => {
  assert(hasCompressedBody(new Headers({ 'content-encoding': 'gzip' })))
  assert(hasCompressedBody(new Headers({ 'content-encoding': 'br' })))
  assert(!hasCompressedBody(new Headers({ 'content-encoding': 'identity' })))
  assert(!hasCompressedBody(new Headers()))
})

// ---------------------------------------------------------------- error table
Deno.test('error table: statuses used are only the agreed ones', () => {
  const allowed = new Set([400, 401, 403, 404, 405, 409, 410, 413, 422, 429, 500])
  for (const [code, e] of Object.entries(ERRORS)) assert(allowed.has(e.status), `${code} -> ${e.status}`)
})
Deno.test('error table: key statuses', () => {
  const want: Record<string, number> = {
    CL_UNAUTHORIZED: 401, CL_RATE_LIMITED: 429, CL_ENDPOINT_GONE: 410, CL_NOT_FOUND: 404, CL_BAD_REQUEST: 400,
    CL_COMPRESSION_UNSUPPORTED: 400, CL_BAD_PERIOD: 400, CL_BAD_CONTROL_TOTALS: 400, CL_FILE_TOO_LARGE: 413,
    CL_BODY_TOO_LARGE: 413, CL_FEED_PAUSED: 403, CL_FORBIDDEN: 403, CL_DELIVERY_NOT_FOUND: 404, CL_FEED_NOT_FOUND: 404,
    CL_PERIOD_ALREADY_DELIVERED: 409, CL_SUPERSEDED: 409, CL_FILE_NOT_UPLOADED: 409, CL_UPLOAD_EXPIRED: 410,
    CL_PERIOD_NOT_CLOSED: 422, CL_PERIOD_NOT_IN_CALENDAR: 422, CL_NO_ACTIVE_PLAN: 422, CL_SHA256_MISMATCH: 422,
    CL_TOO_MANY_ROWS: 413, CL_RETRIES_EXHAUSTED: 422, CL_STORAGE_ERROR: 500, CL_LEASE_LOST: 500,
  }
  for (const [code, status] of Object.entries(want)) assertEquals(statusOf(code), status, code)
  assertEquals(statusOf('CL_NOT_IN_TABLE'), 500)
  assertEquals(statusOf(null), 500)
})
Deno.test('error table covers every CL_ code of the v4 database functions and the worker', async () => {
  const root = new URL('../../', import.meta.url)
  const sources = [
    'migrations/20261124100000_cl_deliveries.sql',
    'migrations/20261124100100_cl_process_delivery.sql',
    'migrations/20261124100200_cl_delivery_api.sql',
    'functions/carrier-link-worker/loader.ts',
    'functions/carrier-link-worker/records.ts',
  ]
  // Names that look like codes but are not (worker secret in the Vault / env).
  const NOT_ERROR_CODES = new Set(['CL_WORKER_SECRET'])
  const missing = new Set<string>()
  for (const s of sources) {
    const text = await Deno.readTextFile(new URL(s, root))
    for (const m of text.matchAll(/CL_[A-Z][A-Z0-9_]*[A-Z0-9]/g)) {
      if (!(m[0] in ERRORS) && !NOT_ERROR_CODES.has(m[0])) missing.add(m[0])
    }
  }
  assertEquals([...missing].sort(), [])
})
Deno.test('clCode', () => {
  assertEquals(clCode('CL_PROCESSING_ERROR 57014'), 'CL_PROCESSING_ERROR')
  assertEquals(clCode('CL_PERIOD_NOT_IN_CALENDAR: the period ending 2026-11-22 must start on 2026-11-16'), 'CL_PERIOD_NOT_IN_CALENDAR')
  assertEquals(clCode('CL_SHA256_MISMATCH'), 'CL_SHA256_MISMATCH')
  assertEquals(clCode('plain error'), null)
  assertEquals(clCode(undefined), null)
})
Deno.test('sqlErrorToHttp: a known code decides the status whatever the SQLSTATE', () => {
  assertEquals(sqlErrorToHttp({ code: 'P0001', message: 'CL_PERIOD_ALREADY_DELIVERED: 2026-11-16 to ... overlaps delivery x' }),
    { status: 409, code: 'CL_PERIOD_ALREADY_DELIVERED' })
  assertEquals(sqlErrorToHttp({ code: '22023', message: 'CL_PERIOD_NOT_CLOSED: the period ends on 2026-11-30' }),
    { status: 422, code: 'CL_PERIOD_NOT_CLOSED' })
  assertEquals(sqlErrorToHttp({ code: '22023', message: 'CL_FILE_TOO_LARGE: size_bytes 2 is over the limit of 1 bytes' }),
    { status: 413, code: 'CL_FILE_TOO_LARGE' })
  assertEquals(sqlErrorToHttp({ code: '22023', message: 'CL_DELIVERY_NOT_FOUND' }), { status: 404, code: 'CL_DELIVERY_NOT_FOUND' })
  assertEquals(sqlErrorToHttp({ code: '22023', message: 'CL_FEED_PAUSED: the connector is paused' }), { status: 403, code: 'CL_FEED_PAUSED' })
})
Deno.test('sqlErrorToHttp: defaults and unexpected errors', () => {
  assertEquals(sqlErrorToHttp({ code: '22023', message: 'plan not found' }), { status: 400, code: 'CL_BAD_REQUEST' })
  assertEquals(sqlErrorToHttp({ code: '42501', message: 'permission denied for function x' }), { status: 403, code: 'CL_FORBIDDEN' })
  assertEquals(sqlErrorToHttp({}), null)
  assertEquals(sqlErrorToHttp({ code: 'P0001', message: 'something else' }), null)
  assertEquals(sqlErrorToHttp({ code: '22023', message: 'CL_UNKNOWN_THING: x' }), null)
  assertEquals(sqlErrorToHttp({ code: '22023', message: 'CL_LEASE_LOST' }), null) // internal: 500
  assertEquals(sqlErrorToHttp({ code: '23505', message: 'duplicate key' }), null)
})
Deno.test('publicDelivery drops the storage path', () => {
  assertEquals(publicDelivery({ delivery_id: 'x', file_path: 'a/b/c.jsonl', status: 'received' }), { delivery_id: 'x', status: 'received' })
  assertEquals(publicDelivery(null), null)
})
