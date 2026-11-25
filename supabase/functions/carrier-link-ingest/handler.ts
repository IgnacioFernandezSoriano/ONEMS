// Carrier Link v4 connector API (server to server). The I/O (database RPC, Storage, usage log) is injected, so the
// whole request flow is tested with mocks in handler.test.ts. index.ts wires the real Supabase client.
//
//   GET  /config                     -> cl_connector_config (what the carrier needs to prepare a delivery)
//   GET  /query?db=postgresql|oracle|sqlserver -> the extraction SQL of the next delivery, built from that config
//   POST /deliveries                 -> cl_delivery_open + a signed upload URL (one PUT of the whole file)
//   POST /deliveries/{id}/complete   -> cl_delivery_complete (received: processing starts within a minute)
//   GET  /deliveries/{id}            -> cl_delivery_status (status, phase, counts, rejected reasons, drawn, alerts)
//   /demands, /batches (v3)          -> 410 Gone
import {
  CONTENT_TYPE_BY_FORMAT, MAX_BODY_BYTES, ROUTE_METHOD, UPLOAD_URL_TTL_SECONDS,
  clCode, errorBody, extractApiKey, hasCompressedBody, isUuid, parseRoute, publicDelivery, sqlErrorToHttp, statusOf,
  validateOpenRequest,
} from './lib.ts'
import { QUERY_DBS, buildCarrierQuery, type ConnectorConfig, type QueryDb } from './query.ts'

export interface ApiKey { id: string; scope: string; feed_id: string | null }
export interface DbError { code?: string; message?: string }

export interface Deps {
  /** api_key_resolve(p_key): the active key, or null. */
  resolveKey(apiKey: string): Promise<ApiKey | null>
  /** Counts this key's requests of the last minute and logs this one. 'error' = fail closed. */
  rateLimit(keyId: string, endpoint: string, ip: string): Promise<'ok' | 'limited' | 'error'>
  /** PostgREST RPC as service_role. */
  rpc(fn: string, args: Record<string, unknown>): Promise<{ data: unknown; error: DbError | null }>
  /** Signed upload URL of one object of the cl-deliveries bucket (no upsert). null = Storage error. */
  signUpload(path: string): Promise<string | null>
  /** Optional nudge to the worker after a delivery is received (the pg_cron kick runs anyway). */
  kickWorker?(): void
  /** Logs a code only, never request or file content. */
  log?(event: string, code?: string): void
}

// Server-to-server API: no CORS headers on purpose.
const json = (status: number, body: unknown, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', ...headers } })

const fail = (code: string, detail?: string, extra?: Record<string, unknown>, headers?: Record<string, string>) =>
  json(statusOf(code), errorBody(code, detail, extra), headers)

class HttpError extends Error {
  constructor(public code: string) { super(code) }
}

// Reads the body as a stream; returns null as soon as it exceeds the cap.
async function readCapped(req: Request, cap: number): Promise<Uint8Array | null> {
  if (!req.body) return new Uint8Array(0)
  const reader = req.body.getReader()
  const chunks: Uint8Array[] = []
  let total = 0
  while (true) {
    const { done, value } = await reader.read()
    if (done) break
    total += value.byteLength
    if (total > cap) { await reader.cancel(); return null }
    chunks.push(value)
  }
  const out = new Uint8Array(total)
  let o = 0
  for (const c of chunks) { out.set(c, o); o += c.byteLength }
  return out
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  const log = deps.log ?? (() => {})
  if (req.method === 'OPTIONS') return new Response(null, { status: 204 })

  // A malformed percent-escape in the path (decodeURIComponent throws URIError) is a controlled 400, not a 500.
  let route: ReturnType<typeof parseRoute>
  try { route = parseRoute(new URL(req.url)) } catch { return fail('CL_BAD_REQUEST', 'malformed URL') }
  // Old and unknown routes answer before authentication: nothing to leak, no database work.
  if (route === null) return fail('CL_NOT_FOUND')
  if (route.kind === 'gone') return fail('CL_ENDPOINT_GONE')
  const method = ROUTE_METHOD[route.kind]!
  if (req.method !== method) return fail('CL_METHOD_NOT_ALLOWED', undefined, undefined, { Allow: method })

  try {
    const apiKey = extractApiKey(req.headers)
    const key = apiKey ? await deps.resolveKey(apiKey) : null
    if (!key || key.scope !== 'carrier_feed' || !key.feed_id) return fail('CL_UNAUTHORIZED')
    const feedId = key.feed_id // the ONLY feed ever passed to SQL, never one from the request

    const ip = req.headers.get('x-forwarded-for') || req.headers.get('x-real-ip') || 'unknown'
    const rl = await deps.rateLimit(key.id, `/carrier-link-ingest/${route.kind}`, ip)
    if (rl === 'error') return fail('CL_INTERNAL')
    if (rl === 'limited') return fail('CL_RATE_LIMITED', undefined, undefined, { 'Retry-After': '60' })

    const call = async (fn: string, args: Record<string, unknown>) => {
      const { data, error } = await deps.rpc(fn, args)
      if (error) {
        const mapped = sqlErrorToHttp(error)
        if (mapped) throw new HttpError(mapped.code)
        log('db_error', error.code) // SQLSTATE only: messages may contain values
        throw new HttpError('CL_INTERNAL')
      }
      // Every RPC here returns a JSON object; anything else (null, scalar, array) is a server fault, never a 2xx.
      if (data === null || typeof data !== 'object' || Array.isArray(data)) {
        log('db_empty_result', fn)
        throw new HttpError('CL_INTERNAL')
      }
      return data
    }

    if (route.kind === 'config') {
      return json(200, await call('cl_connector_config', { p_feed_id: feedId }))
    }

    if (route.kind === 'query') {
      const db = new URL(req.url).searchParams.get('db') ?? 'postgresql'
      if (!(QUERY_DBS as readonly string[]).includes(db)) {
        return fail('CL_BAD_REQUEST', `db must be one of: ${QUERY_DBS.join(', ')}`)
      }
      const cfg = await call('cl_connector_config', { p_feed_id: feedId }) as unknown as ConnectorConfig
      if (cfg.mapping_complete !== true) return fail('CL_MAPPING_INCOMPLETE')
      return json(200, buildCarrierQuery(cfg, db as QueryDb))
    }

    if (route.kind === 'deliveries') {
      if (hasCompressedBody(req.headers)) {
        return fail('CL_COMPRESSION_UNSUPPORTED', 'Content-Encoding is not supported: send a plain JSON body')
      }
      const declared = Number(req.headers.get('content-length') ?? 0)
      if (declared > MAX_BODY_BYTES) return fail('CL_BODY_TOO_LARGE')
      const raw = await readCapped(req, MAX_BODY_BYTES)
      if (raw === null) return fail('CL_BODY_TOO_LARGE')
      let body: unknown
      try { body = JSON.parse(new TextDecoder().decode(raw)) } catch { return fail('CL_BAD_REQUEST', 'invalid JSON') }
      const v = validateOpenRequest(body)
      if (!v.ok) return fail(v.code, v.detail)

      // deno-lint-ignore no-explicit-any
      const d: any = await call('cl_delivery_open', {
        p_feed_id: feedId, p_period_start: v.value.period_start, p_period_end: v.value.period_end,
        p_sha256: v.value.sha256, p_control_totals: v.value.control_totals, p_format: v.value.format,
        p_size_bytes: v.value.size_bytes,
      })
      let upload: Record<string, unknown> | null = null
      if (d?.status === 'pending_upload') {
        const url = await deps.signUpload(d.file_path)
        if (!url) { log('storage_sign_error'); return fail('CL_INTERNAL') }
        upload = {
          url, method: 'PUT', headers: { 'Content-Type': CONTENT_TYPE_BY_FORMAT[d.format] ?? 'application/octet-stream' },
          expires_in_seconds: UPLOAD_URL_TTL_SECONDS,
        }
      }
      return json(d?.existing ? 200 : 201, { delivery: publicDelivery(d), upload })
    }

    // complete / delivery: an id that is not a UUID is the same "not found" as a foreign or missing delivery.
    if (!isUuid(route.id)) return fail('CL_DELIVERY_NOT_FOUND')

    if (route.kind === 'complete') {
      // deno-lint-ignore no-explicit-any
      const d: any = await call('cl_delivery_complete', { p_feed_id: feedId, p_delivery_id: route.id })
      if (d?.status === 'rejected') {
        const cl = clCode(typeof d.error === 'string' ? d.error : null)
        const code = cl && statusOf(cl) < 500 ? cl : 'CL_INTERNAL'
        return fail(code, undefined, { delivery: publicDelivery(d) })
      }
      if (d?.status === 'received') deps.kickWorker?.()
      return json(d?.status === 'received' ? 202 : 200, { delivery: publicDelivery(d) })
    }

    // route.kind === 'delivery'
    const d = await call('cl_delivery_status', { p_feed_id: feedId, p_delivery_id: route.id })
    return json(200, { delivery: publicDelivery(d) })
  } catch (e) {
    if (e instanceof HttpError) return fail(e.code)
    log('unexpected_error')
    return fail('CL_INTERNAL')
  }
}
