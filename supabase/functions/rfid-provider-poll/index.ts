// =====================================================
// rfid-provider-poll: incremental capture from AWS RFID Read API,
// then resolve landing rows and run the ETL pipeline. (spec 2026-06-11)
// =====================================================
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { buildReadsUrl, parseRetryAfter, isValidRecord, toLandingRow } from './lib.ts'
import type { ProviderRecord } from './lib.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const SOURCE_ID = 'aws-rfid-read-api'
const PAGE_LIMIT = 1000
const MAX_PAGES_PER_RUN = 20          // up to 20k records/run; protects rate limit + function timeout
const MAX_RETRIES = 4

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  // Auth: cron secret (same pattern as consolidate-rfid-events-cron)
  const authHeader = req.headers.get('Authorization')
  const cronSecret = Deno.env.get('CRON_SECRET')
  if (!authHeader || authHeader !== `Bearer ${cronSecret}`) {
    return jsonResponse({ error: 'Unauthorized' }, 401)
  }

  const apiUrl = Deno.env.get('RFID_PROVIDER_API_URL')
  const apiKey = Deno.env.get('RFID_PROVIDER_API_KEY')
  if (!apiUrl || !apiKey) {
    return jsonResponse({ error: 'Missing RFID_PROVIDER_API_URL / RFID_PROVIDER_API_KEY' }, 500)
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  )

  // 1. Load ingest state
  const { data: state, error: stateErr } = await supabase
    .from('rfid_ingest_state')
    .select('*')
    .eq('id', SOURCE_ID)
    .single()
  if (stateErr || !state) {
    return jsonResponse({ error: 'ingest_state row missing', details: stateErr?.message }, 500)
  }

  let cursor: string | null = state.next_cursor
  // First run: use since (backfill_since, or 24 months ago as a safe default — spec §8.4)
  let since: string | null = null
  if (!cursor) {
    since = state.backfill_since
      ?? new Date(Date.now() - 24 * 30 * 24 * 60 * 60 * 1000).toISOString()
  }
  const sinceUsed = since   // the since value this run actually started from (null on cursor runs)

  let totalFetched = 0
  let pages = 0
  let rateLimited = false

  try {
    while (pages < MAX_PAGES_PER_RUN) {
      const url = buildReadsUrl(apiUrl, { cursor, since, limit: PAGE_LIMIT })

      // Fetch with retry/backoff
      let resp: Response | null = null
      for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
        resp = await fetch(url, { headers: { 'x-api-key': apiKey } })
        if (resp.status === 429) {
          rateLimited = true
          await sleep(parseRetryAfter(resp.headers.get('Retry-After')) * 1000)
          continue
        }
        if (resp.status >= 500) {
          await sleep(Math.min(2 ** attempt, 8) * 1000)
          continue
        }
        break
      }
      if (!resp) throw new Error('no response from provider')
      if (resp.status === 401 || resp.status === 403) {
        throw new Error(`provider auth error ${resp.status}`)
      }
      if (resp.status === 429) {
        throw new Error(`rate_limited: provider 429 after ${MAX_RETRIES} retries`)
      }
      if (!resp.ok) {
        throw new Error(`provider error ${resp.status}: ${await resp.text()}`)
      }

      const payload = await resp.json() as { data: ProviderRecord[]; next_cursor: string | null }
      const records = (payload.data ?? []).filter(isValidRecord)

      if (records.length > 0) {
        const rows = records.map(toLandingRow)
        const { error: upsertErr } = await supabase
          .from('rfid_provider_reads')
          .upsert(rows, { onConflict: 'id', ignoreDuplicates: true })
        if (upsertErr) throw new Error(`landing upsert failed: ${upsertErr.message}`)
        totalFetched += records.length
      }

      // Advance + persist high-water mark after every page (resumable)
      cursor = payload.next_cursor
      since = null
      await supabase.from('rfid_ingest_state').update({
        next_cursor: cursor,
        last_since: sinceUsed ?? state.last_since,
        updated_at: new Date().toISOString(),
      }).eq('id', SOURCE_ID)

      pages++
      if (!cursor) break          // caught up
    }

    // 2. Resolve landing rows into rfid_events_raw
    const { data: resolved, error: resolveErr } = await supabase.rpc('resolve_provider_reads')
    if (resolveErr) throw new Error(`resolve_provider_reads failed: ${resolveErr.message}`)
    const res = Array.isArray(resolved) ? resolved[0] : resolved

    // 3. Run the ETL pipeline (sequential, after capture)
    const { data: pipeline, error: pipelineErr } = await supabase.rpc('process_all_accounts_pipeline')
    if (pipelineErr) throw new Error(`process_all_accounts_pipeline failed: ${pipelineErr.message}`)

    // 4. Persist run stats
    await supabase.from('rfid_ingest_state').update({
      last_run_at: new Date().toISOString(),
      last_status: rateLimited ? 'rate_limited' : 'ok',
      last_error: null,
      total_fetched: (state.total_fetched ?? 0) + totalFetched,
      last_fetched: totalFetched,
      last_matched: res?.matched ?? 0,
      last_unmatched: (res?.unknown_reader ?? 0) + (res?.tag_decode_failed ?? 0),
      updated_at: new Date().toISOString(),
    }).eq('id', SOURCE_ID)

    return jsonResponse({
      success: true,
      fetched: totalFetched,
      pages,
      resolve: res,
      pipeline_accounts: Array.isArray(pipeline) ? pipeline.length : 0,
    })
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    await supabase.from('rfid_ingest_state').update({
      last_run_at: new Date().toISOString(),
      last_status: message.startsWith('rate_limited') ? 'rate_limited' : 'error',
      last_error: message,
      updated_at: new Date().toISOString(),
    }).eq('id', SOURCE_ID)
    return jsonResponse({ success: false, error: message }, 500)
  }
})
