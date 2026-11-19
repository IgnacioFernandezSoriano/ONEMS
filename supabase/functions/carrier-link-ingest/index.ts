import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { extractApiKey } from '../onedb-api/lib.ts'
import {
  MAX_BODY_BYTES, MAX_ROWS, RATE_LIMIT_PER_MINUTE,
  countRows, validateEnvelope, parseRoute, parseDryRun,
} from './lib.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-api-key, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
}

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

class HttpError extends Error {
  constructor(public status: number, public code: string) { super(code) }
}

// Maps a Postgres error to an HTTP error. Only the CL_ code token is echoed; SQL text is never returned.
function mapSqlError(err: { code?: string; message?: string }): HttpError {
  const codeMatch = /^(CL_[A-Z_]+)/.exec(err.message ?? '')
  if (err.code === '22023') return new HttpError(400, codeMatch ? codeMatch[1] : 'CL_BAD_REQUEST')
  if (err.code === '42501') return new HttpError(403, codeMatch ? codeMatch[1] : 'CL_FORBIDDEN')
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
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

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

    // Rate limit: RATE_LIMIT_PER_MINUTE requests per key per minute
    const since = new Date(Date.now() - 60_000).toISOString()
    const { count } = await sb.from('api_usage_log').select('id', { count: 'exact', head: true })
      .eq('api_key_id', key.id).gte('request_timestamp', since)
    if ((count ?? 0) >= RATE_LIMIT_PER_MINUTE) {
      return json(429, { success: false, error: `Rate limit exceeded. Maximum ${RATE_LIMIT_PER_MINUTE} requests per minute.` })
    }
    try {
      await sb.from('api_usage_log').insert({
        api_key_id: key.id,
        endpoint: '/carrier-link-ingest',
        request_timestamp: new Date().toISOString(),
        ip_address: req.headers.get('x-forwarded-for') || req.headers.get('x-real-ip') || 'unknown',
      })
    } catch { /* logging must not fail the request */ }

    const url = new URL(req.url)
    const route = parseRoute(url)

    if (route === 'demands' && req.method === 'GET') {
      const { data, error } = await sb.from('cl_demands').select('payload')
        .eq('feed_id', feedId).eq('status', 'open').order('requested_at', { ascending: true })
      if (error) throw mapSqlError(error)
      // deno-lint-ignore no-explicit-any
      return json(200, { demands: (data ?? []).map((d: any) => d.payload) })
    }

    if (route === 'batches' && req.method === 'POST') {
      const dryRun = parseDryRun(url)

      const declared = Number(req.headers.get('content-length') ?? 0)
      if (declared > MAX_BODY_BYTES) return json(413, { success: false, error: 'CL_BODY_TOO_LARGE' })
      const raw = new Uint8Array(await req.arrayBuffer())
      if (raw.byteLength > MAX_BODY_BYTES) return json(413, { success: false, error: 'CL_BODY_TOO_LARGE' })

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

      const sampling: unknown[] = []
      for (const s of ingest.strata ?? []) {
        sampling.push(await rpc(sb, 'cl_sample_stratum', { p_batch_id: ingest.batch, p_stratum_id: s.stratum_id }))
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
