// deno-lint-ignore-file no-import-prefix
// Carrier Link v4 connector API. Wiring only: the request flow lives in handler.ts (tested with mocks).
// Secrets: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (set by Supabase); optional CL_WORKER_SECRET to nudge the worker
// right after a delivery is received (without it the pg_cron kick starts processing within a minute).
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { handle, type ApiKey, type Deps } from './handler.ts'
import { BUCKET, RATE_LIMIT_PER_MINUTE } from './lib.ts'

const url = Deno.env.get('SUPABASE_URL') ?? ''
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const workerSecret = Deno.env.get('CL_WORKER_SECRET') ?? ''
const sb = createClient(url, serviceKey)

const deps: Deps = {
  async resolveKey(apiKey) {
    const { data, error } = await sb.rpc('api_key_resolve', { p_key: apiKey })
    if (error) return null
    return ((Array.isArray(data) ? data[0] : data) ?? null) as ApiKey | null
  },

  // RATE_LIMIT_PER_MINUTE requests per key per minute, counted in api_usage_log (fail closed on a DB error).
  async rateLimit(keyId, endpoint, ip) {
    const since = new Date(Date.now() - 60_000).toISOString()
    const { count, error } = await sb.from('api_usage_log').select('id', { count: 'exact', head: true })
      .eq('api_key_id', keyId).gte('request_timestamp', since)
    if (error) { console.error('carrier-link-ingest rate-limit error', error.code); return 'error' }
    if ((count ?? 0) >= RATE_LIMIT_PER_MINUTE) return 'limited'
    const { error: logErr } = await sb.from('api_usage_log').insert({
      api_key_id: keyId, endpoint, request_timestamp: new Date().toISOString(), ip_address: ip,
    })
    if (logErr) console.error('carrier-link-ingest usage log error', logErr.code)
    return 'ok'
  },

  async rpc(fn, args) {
    const { data, error } = await sb.rpc(fn, args)
    return { data, error }
  },

  // No upsert: once a file is in place it cannot be replaced through a URL (re-uploading answers 409 from Storage).
  async signUpload(path) {
    const { data, error } = await sb.storage.from(BUCKET).createSignedUploadUrl(path)
    if (error || !data?.signedUrl) return null
    return data.signedUrl
  },

  kickWorker() {
    if (!workerSecret) return
    const p = fetch(`${url}/functions/v1/carrier-link-worker`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-cl-worker-secret': workerSecret, Authorization: `Bearer ${serviceKey}` },
      body: '{}',
    }).then((r) => r.body?.cancel()).catch(() => {})
    // deno-lint-ignore no-explicit-any
    const rt = (globalThis as any).EdgeRuntime
    if (rt?.waitUntil) rt.waitUntil(p)
  },

  log(event, code) {
    console.error('carrier-link-ingest', event, code ?? '')
  },
}

Deno.serve((req) => handle(req, deps))
