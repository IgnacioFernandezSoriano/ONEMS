import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import {
  MAX_BODY_BYTES, MAX_ROWS, MAX_DEMANDS, RATE_LIMIT_PER_MINUTE,
  countRows, validateEnvelope, parseRoute, parseDryRun, extractApiKey, needsSampling, summaryStratumIds, sqlErrorToHttp,
} from './lib.ts'

// Server-to-server API: no CORS headers on purpose.
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })

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

class HttpError extends Error {
  constructor(public status: number, public code: string) { super(code) }
}

// Maps a Postgres error to an HTTP error (mapping in lib.ts). Only the CL_ code token is echoed; SQL text is never returned.
function mapSqlError(err: { code?: string; message?: string }): HttpError {
  const mapped = sqlErrorToHttp(err)
  if (mapped) return new HttpError(mapped.status, mapped.code)
  // Log only the SQLSTATE: messages/details may contain personal data.
  console.error('carrier-link-ingest db error', err.code)
  return new HttpError(500, 'Internal server error')
}

// deno-lint-ignore no-explicit-any
async function rpc(sb: any, fn: string, args: Record<string, unknown>) {
  const { data, error } = await sb.rpc(fn, args)
  if (error) throw mapSqlError(error)
  return data
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204 })

  try {
    const sb = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '')

    const apiKey = extractApiKey(req.headers)
    // deno-lint-ignore no-explicit-any
    let key: any = null
    if (apiKey) {
      const { data, error } = await sb.rpc('api_key_resolve', { p_key: apiKey })
      if (!error) key = Array.isArray(data) ? data[0] : data
    }
    if (!key || key.scope !== 'carrier_feed' || !key.feed_id) {
      return json(401, { success: false, error: 'Invalid or inactive API key' })
    }
    const feedId: string = key.feed_id // the ONLY feed ever passed to SQL

    // Rate limit: RATE_LIMIT_PER_MINUTE requests per key per minute (fail closed on DB error)
    const since = new Date(Date.now() - 60_000).toISOString()
    const { count, error: countErr } = await sb.from('api_usage_log').select('id', { count: 'exact', head: true })
      .eq('api_key_id', key.id).gte('request_timestamp', since)
    if (countErr) {
      console.error('carrier-link-ingest rate-limit error', countErr.code)
      return json(500, { success: false, error: 'internal' })
    }
    if ((count ?? 0) >= RATE_LIMIT_PER_MINUTE) {
      return json(429, { success: false, error: `Rate limit exceeded. Maximum ${RATE_LIMIT_PER_MINUTE} requests per minute.` })
    }
    const { error: logErr } = await sb.from('api_usage_log').insert({
      api_key_id: key.id,
      endpoint: '/carrier-link-ingest',
      request_timestamp: new Date().toISOString(),
      ip_address: req.headers.get('x-forwarded-for') || req.headers.get('x-real-ip') || 'unknown',
    })
    if (logErr) console.error('carrier-link-ingest usage log error', logErr.code)

    const url = new URL(req.url)
    const route = parseRoute(url)

    if (route === 'demands' && req.method === 'GET') {
      const { data, error } = await sb.from('cl_demands').select('payload')
        .eq('feed_id', feedId).eq('status', 'open')
        .order('requested_at', { ascending: true }).limit(MAX_DEMANDS)
      if (error) throw mapSqlError(error)
      // deno-lint-ignore no-explicit-any
      return json(200, { demands: (data ?? []).map((d: any) => d.payload) })
    }

    if (route === 'batches' && req.method === 'POST') {
      const dryRun = parseDryRun(url)

      const declared = Number(req.headers.get('content-length') ?? 0)
      if (declared > MAX_BODY_BYTES) return json(413, { success: false, error: 'CL_BODY_TOO_LARGE' })
      const raw = await readCapped(req, MAX_BODY_BYTES)
      if (raw === null) return json(413, { success: false, error: 'CL_BODY_TOO_LARGE' })

      let batch: unknown
      try { batch = JSON.parse(new TextDecoder().decode(raw)) } catch {
        return json(400, { success: false, error: 'CL_BAD_PAYLOAD: invalid JSON' })
      }
      const env = validateEnvelope(batch)
      if (!env.ok) return json(400, { success: false, error: env.error })
      if (countRows(batch) > MAX_ROWS) return json(413, { success: false, error: 'CL_TOO_MANY_ROWS' })

      const { data: feed, error: feedErr } = await sb.from('cl_feeds').select('status').eq('id', feedId).maybeSingle()
      if (feedErr || !feed) throw new HttpError(500, 'Internal server error')
      if (feed.status === 'paused') return json(403, { success: false, error: 'CL_FEED_PAUSED' })
      if (feed.status === 'testing' && !dryRun) {
        return json(403, { success: false, error: 'CL_FEED_TESTING_DRY_RUN_ONLY' })
      }

      const ingest = await rpc(sb, 'cl_ingest_batch', { p_feed_id: feedId, p_payload: batch, p_dry_run: dryRun })
      if (dryRun || ingest?.status !== 'validated' || !ingest?.batch) return json(200, { ingest })

      // Only complete batches that are still 'validated' (also covers a connector retrying a batch
      // whose sampling failed half-way: cl_sample_stratum is idempotent per stratum). The status is
      // read for the summary's batch AND this key's feed, never from the request body.
      const { data: b, error: bErr } = await sb.from('cl_batches')
        .select('status, cl_demands!inner(feed_id)')
        .eq('id', ingest.batch).eq('cl_demands.feed_id', feedId).maybeSingle()
      if (bErr) throw mapSqlError(bErr)
      if (!b || !needsSampling(b.status)) return json(200, { ingest })

      const sampling: unknown[] = []
      for (const stratumId of summaryStratumIds(ingest)) {
        try {
          sampling.push(await rpc(sb, 'cl_sample_stratum', { p_batch_id: ingest.batch, p_stratum_id: stratumId }))
        } catch (e) {
          const he = e instanceof HttpError ? e : new HttpError(500, 'internal')
          const code = he.status === 500 ? 'internal' : he.code
          return json(he.status, { ingest, sampling, failed: { stratum_id: stratumId, code } })
        }
      }
      const finish = await rpc(sb, 'cl_finish_batch', { p_batch_id: ingest.batch })
      return json(200, { ingest, sampling, finish })
    }

    return json(route ? 405 : 404, { success: false, error: route ? 'Method not allowed' : 'Not found' })
  } catch (e) {
    if (e instanceof HttpError) return json(e.status, { success: false, error: e.code })
    console.error('carrier-link-ingest unexpected error')
    return json(500, { success: false, error: 'Internal server error' })
  }
})
