// Carrier Link v4 connector API: pure helpers (routing, auth header, request validation, error table).
// No I/O here, so everything is unit-tested in lib.test.ts.

/** Cap of the JSON body of POST /deliveries (control_totals can hold up to 10000 entries). */
export const MAX_BODY_BYTES = 5 * 1024 * 1024
/** Hard cap of one delivery file: the cl-deliveries bucket limit (500 MB). Each connector may have a lower cap. */
export const ABSOLUTE_MAX_FILE_BYTES = 524_288_000
export const MAX_CONTROL_TOTALS = 10_000
export const RATE_LIMIT_PER_MINUTE = 30
export const BUCKET = 'cl-deliveries'
/** Supabase signed upload URLs are valid for 2 hours (fixed by Storage). */
export const UPLOAD_URL_TTL_SECONDS = 7200
export const FORMATS = ['jsonl', 'csv'] as const
export const CONTENT_TYPE_BY_FORMAT: Record<string, string> = { jsonl: 'application/x-ndjson', csv: 'text/csv' }

export const NEW_ROUTES = 'GET /config, POST /deliveries, POST /deliveries/{id}/complete, GET /deliveries/{id}'

export type Route =
  | { kind: 'config' }
  | { kind: 'deliveries' }
  | { kind: 'complete'; id: string }
  | { kind: 'delivery'; id: string }
  | { kind: 'gone' }

/** Method each route accepts ('gone' answers 410 to any method). */
export const ROUTE_METHOD: Record<Route['kind'], string | null> = {
  config: 'GET', deliveries: 'POST', complete: 'POST', delivery: 'GET', gone: null,
}

/** Path after `/carrier-link-ingest` (with or without the `/functions/v1` prefix). null = unknown route. */
export function parseRoute(url: URL): Route | null {
  const path = url.pathname.replace(/\/+$/, '')
  const m = /\/carrier-link-ingest(\/.*)?$/.exec(path)
  if (!m) return null
  const seg = (m[1] ?? '').split('/').filter((s) => s !== '')
  if (seg.length === 1 && seg[0] === 'config') return { kind: 'config' }
  if (seg.length === 1 && seg[0] === 'deliveries') return { kind: 'deliveries' }
  if (seg.length === 2 && seg[0] === 'deliveries') return { kind: 'delivery', id: decodeURIComponent(seg[1]) }
  if (seg.length === 3 && seg[0] === 'deliveries' && seg[2] === 'complete') {
    return { kind: 'complete', id: decodeURIComponent(seg[1]) }
  }
  // v3 demand / batch routes (and anything under them): removed.
  if (seg.length >= 1 && (seg[0] === 'demands' || seg[0] === 'batches')) return { kind: 'gone' }
  return null
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
export const isUuid = (s: string) => UUID_RE.test(s)

export function extractApiKey(headers: Headers): string | null {
  const direct = headers.get('x-api-key')?.trim()
  if (direct) return direct
  const auth = headers.get('authorization')
  if (auth && /^Bearer\s/i.test(auth)) {
    const k = auth.replace(/^Bearer\s+/i, '').trim()
    if (k) return k
  }
  return null
}

const isObj = (v: unknown): v is Record<string, unknown> =>
  typeof v === 'object' && v !== null && !Array.isArray(v)

// Any compression name, alone or as a suffix (jsonl.gz, csv.zip...).
const COMPRESSION_RE = /(gz|gzip|zip|bz2|bzip2|xz|zst|zstd|br|brotli|deflate|compress|lz4|7z)$/i

export interface OpenRequest {
  period_start: string
  period_end: string
  sha256: string
  control_totals: unknown[]
  format: string
  size_bytes: number
}
export type Invalid = { ok: false; code: string; detail: string }

const OPEN_KEYS = new Set(['period_start', 'period_end', 'sha256', 'control_totals', 'format', 'size_bytes', 'compression'])

function isIsoDate(v: unknown): v is string {
  if (typeof v !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(v)) return false
  const d = new Date(v + 'T00:00:00Z')
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === v
}

/** Validates the body of POST /deliveries. The database re-checks everything (calendar, plan, totals content). */
export function validateOpenRequest(body: unknown): { ok: true; value: OpenRequest } | Invalid {
  const bad = (detail: string, code = 'CL_BAD_REQUEST'): Invalid => ({ ok: false, code, detail })
  if (!isObj(body)) return bad('the body must be a JSON object')
  for (const k of Object.keys(body)) if (!OPEN_KEYS.has(k)) return bad(`unknown field: ${k.slice(0, 50)}`)

  // v4 accepts only uncompressed files.
  if (body.compression !== undefined && body.compression !== null && body.compression !== 'none') {
    return bad('compressed files are not supported: upload the plain file (compression "none")', 'CL_COMPRESSION_UNSUPPORTED')
  }
  const format = body.format === undefined || body.format === null ? 'jsonl' : body.format
  if (typeof format !== 'string') return bad('format must be "jsonl" or "csv"')
  if (COMPRESSION_RE.test(format.trim())) {
    return bad('compressed files are not supported: format must be "jsonl" or "csv"', 'CL_COMPRESSION_UNSUPPORTED')
  }
  if (!(FORMATS as readonly string[]).includes(format)) return bad('format must be "jsonl" or "csv"')

  if (!isIsoDate(body.period_start)) return bad('period_start must be a date YYYY-MM-DD')
  if (!isIsoDate(body.period_end)) return bad('period_end must be a date YYYY-MM-DD')
  if (typeof body.sha256 !== 'string' || !/^[0-9a-fA-F]{64}$/.test(body.sha256)) {
    return bad('sha256 must be the 64-character hexadecimal SHA-256 of the file')
  }
  if (!Array.isArray(body.control_totals)) {
    return bad('control_totals must be an array (it may be empty)', 'CL_BAD_CONTROL_TOTALS')
  }
  if (body.control_totals.length > MAX_CONTROL_TOTALS) {
    return bad(`control_totals holds at most ${MAX_CONTROL_TOTALS} entries`, 'CL_BAD_CONTROL_TOTALS')
  }
  const size = body.size_bytes
  if (typeof size !== 'number' || !Number.isSafeInteger(size) || size < 1) {
    return bad('size_bytes must be the file size in bytes (a positive integer)')
  }
  if (size > ABSOLUTE_MAX_FILE_BYTES) {
    return bad(`the file is larger than ${ABSOLUTE_MAX_FILE_BYTES} bytes`, 'CL_FILE_TOO_LARGE')
  }
  return {
    ok: true,
    value: {
      period_start: body.period_start, period_end: body.period_end, sha256: body.sha256.toLowerCase(),
      control_totals: body.control_totals, format, size_bytes: size,
    },
  }
}

/** A Content-Encoding other than identity on the request itself is refused (no compression in v4). */
export function hasCompressedBody(headers: Headers): boolean {
  const ce = headers.get('content-encoding')?.trim().toLowerCase()
  return !!ce && ce !== 'identity'
}

// ============================================================ error table
// EVERY CL_* code of the v4 database functions (Tasks 1-3) and of the worker, with its HTTP status and a fixed
// English message (SQL text is never returned). lib.test.ts checks that the table covers every code in those sources.
// status 500 = never an HTTP answer of this API: either an internal code that cannot reach the connector routes, or
// a code that only appears in `delivery.error` of a FAILED delivery (retried automatically, reported by
// GET /deliveries/{id} with 200).
export const ERRORS: Record<string, { status: number; message: string }> = {
  // --- edge (transport, auth, routing)
  CL_UNAUTHORIZED: { status: 401, message: 'Invalid or inactive API key.' },
  CL_RATE_LIMITED: { status: 429, message: `Rate limit exceeded: at most ${RATE_LIMIT_PER_MINUTE} requests per minute.` },
  CL_NOT_FOUND: { status: 404, message: `Unknown route. Routes: ${NEW_ROUTES}.` },
  CL_METHOD_NOT_ALLOWED: { status: 405, message: 'Method not allowed on this route.' },
  CL_ENDPOINT_GONE: {
    status: 410,
    message: `Carrier Link v4 removed the demand and batch endpoints. Deliver every complete shipment of the period as one file: ${NEW_ROUTES}.`,
  },
  CL_BODY_TOO_LARGE: { status: 413, message: `The request body is larger than ${MAX_BODY_BYTES} bytes.` },
  CL_INTERNAL: { status: 500, message: 'Internal server error.' },
  // --- open a delivery (POST /deliveries)
  CL_BAD_REQUEST: { status: 400, message: 'Invalid request.' },
  CL_COMPRESSION_UNSUPPORTED: { status: 400, message: 'Compressed files are not supported: upload the plain JSON Lines or CSV file.' },
  CL_BAD_PERIOD: { status: 400, message: 'period_start is after period_end.' },
  CL_BAD_CONTROL_TOTALS: {
    status: 400,
    message: 'control_totals must be an array (max 10000) of {place_ref, mode_ref?, product?, delivered} with delivered an integer >= 0.',
  },
  CL_FILE_TOO_LARGE: { status: 413, message: "The file is larger than this connector's max_file_bytes (see GET /config limits)." },
  CL_FEED_NOT_FOUND: { status: 404, message: 'The connector of this API key no longer exists.' },
  CL_FEED_PAUSED: { status: 403, message: 'The connector is paused.' },
  CL_FORBIDDEN: { status: 403, message: 'Forbidden.' },
  CL_PERIOD_NOT_CLOSED: { status: 422, message: 'The period is not closed yet: its last day must be before today (account time zone).' },
  CL_PERIOD_NOT_IN_CALENDAR: {
    status: 422,
    message: 'The period does not match the delivery calendar. Use next_period from GET /config.',
  },
  CL_NO_ACTIVE_PLAN: { status: 422, message: 'No active plan of this connector covers the period.' },
  CL_PERIOD_ALREADY_DELIVERED: { status: 409, message: 'The period (or part of it) was already delivered.' },
  CL_SUPERSEDED: { status: 409, message: 'This delivery was replaced by a newer delivery of the same period with another file.' },
  // --- complete / status
  CL_DELIVERY_NOT_FOUND: { status: 404, message: 'Delivery not found.' },
  CL_FILE_NOT_UPLOADED: { status: 409, message: 'The file was not uploaded yet: upload it to the upload URL, then complete.' },
  CL_UPLOAD_EXPIRED: { status: 410, message: 'The delivery expired before the file was completed (7 days). Open the delivery again.' },
  // --- final rejection of a delivery (rejected; reported by complete and GET /deliveries/{id})
  CL_SHA256_MISMATCH: { status: 422, message: 'The uploaded file does not match the declared sha256 / size.' },
  CL_TOO_MANY_ROWS: { status: 413, message: 'The file has more rows than the connector allows (see GET /config limits.max_rows).' },
  CL_RECORD_TOO_LONG: { status: 413, message: 'A record (line) of the file is too long.' },
  CL_MAPPING_INCOMPLETE: { status: 422, message: 'The field mapping of the connector is incomplete (ask the regulator).' },
  CL_BAD_ENCODING: { status: 422, message: 'The file is not valid UTF-8.' },
  CL_BAD_CSV_HEADER: { status: 422, message: 'The CSV header row is missing, blank or has duplicate column names.' },
  CL_FILE_MISSING: { status: 422, message: 'The uploaded file could not be found when processing started.' },
  CL_RETRIES_EXHAUSTED: { status: 422, message: 'Processing failed 3 times; the delivery was rejected. Deliver the period again.' },
  // --- failed delivery (retried automatically; only seen in delivery.error)
  CL_STORAGE_ERROR: { status: 500, message: 'Temporary storage error (retried automatically).' },
  CL_STORAGE_SHORT_READ: { status: 500, message: 'Temporary storage error (retried automatically).' },
  CL_FILE_SIZE_UNKNOWN: { status: 500, message: 'Temporary storage error (retried automatically).' },
  CL_WORKER_ERROR: { status: 500, message: 'Temporary processing error (retried automatically).' },
  CL_WORKER_LOST: { status: 500, message: 'Temporary processing error (retried automatically).' },
  CL_BAD_SHA_STATE: { status: 500, message: 'Temporary processing error (retried automatically).' },
  CL_PROCESSING_ERROR: { status: 500, message: 'Temporary processing error (retried automatically).' },
  // --- internal to the worker / database (never reach the connector routes)
  CL_CURSOR_MISMATCH: { status: 500, message: 'Internal server error.' },
  CL_DELIVERY_NOT_LOADING: { status: 500, message: 'Internal server error.' },
  CL_LEASE_LOST: { status: 500, message: 'Internal server error.' },
  CL_STAGING_LOST: { status: 500, message: 'Internal server error.' },
  CL_STAGING_NOT_EMPTY: { status: 500, message: 'Internal server error.' },
  CL_STOPPED: { status: 500, message: 'Internal server error.' },
  CL_DELIVERY_BAD_TRANSITION: { status: 500, message: 'Internal server error.' },
  CL_DELIVERY_IMMUTABLE: { status: 500, message: 'Internal server error.' },
  CL_QUOTA_NOT_FOUND: { status: 500, message: 'Internal server error.' },
}

/** First CL_ token of a message (`CL_PROCESSING_ERROR 57014` -> CL_PROCESSING_ERROR). */
export function clCode(message: string | null | undefined): string | null {
  const m = /^(CL_[A-Z0-9_]*[A-Z0-9])/.exec(message ?? '')
  return m ? m[1] : null
}

/** HTTP status of a CL_ code; unknown codes are 500. */
export function statusOf(code: string | null | undefined): number {
  const e = code ? ERRORS[code] : undefined
  return e ? e.status : 500
}

/**
 * Maps a Postgres error to { status, code }. null = unexpected (the caller answers 500 and logs only the SQLSTATE).
 * A known CL_ code decides the status whatever its SQLSTATE (22023, P0001, 42501). Without one: 22023 -> 400
 * CL_BAD_REQUEST, 42501 -> 403 CL_FORBIDDEN. Codes with status 500 in the table are unexpected here.
 */
export function sqlErrorToHttp(err: { code?: string; message?: string }): { status: number; code: string } | null {
  const cl = clCode(err.message)
  if (cl && Object.prototype.hasOwnProperty.call(ERRORS, cl)) {
    const status = ERRORS[cl].status
    return status < 500 ? { status, code: cl } : null
  }
  if (cl) return null
  if (err.code === '22023') return { status: 400, code: 'CL_BAD_REQUEST' }
  if (err.code === '42501') return { status: 403, code: 'CL_FORBIDDEN' }
  return null
}

/** Error body: { success: false, error, message, detail? }. */
export function errorBody(code: string, detail?: string, extra?: Record<string, unknown>) {
  return {
    success: false, error: code, message: (ERRORS[code] ?? ERRORS.CL_INTERNAL).message,
    ...(detail ? { detail } : {}), ...(extra ?? {}),
  }
}

/** Delivery summary as shown to the connector: without the internal storage path. */
export function publicDelivery(summary: unknown): Record<string, unknown> | null {
  if (!isObj(summary)) return null
  const { file_path: _path, ...rest } = summary
  return rest
}
