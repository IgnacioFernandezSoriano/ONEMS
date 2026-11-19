export const MAX_BODY_BYTES = 5 * 1024 * 1024
export const MAX_ROWS = 5000
export const RATE_LIMIT_PER_MINUTE = 30

const isObj = (v: unknown): v is Record<string, unknown> =>
  typeof v === 'object' && v !== null && !Array.isArray(v)

export function countRows(batch: unknown): number {
  if (!isObj(batch) || !Array.isArray(batch.strata)) return 0
  let n = 0
  for (const s of batch.strata) {
    if (isObj(s) && Array.isArray(s.rows)) n += s.rows.length
  }
  return n
}

export function validateEnvelope(batch: unknown): { ok: true } | { ok: false; error: string } {
  if (!isObj(batch)) return { ok: false, error: 'CL_BAD_PAYLOAD: the batch must be a JSON object' }
  const nonEmpty = (v: unknown) => typeof v === 'string' && v.trim() !== ''
  if (!nonEmpty(batch.demand_id)) return { ok: false, error: 'CL_BAD_PAYLOAD: demand_id is required' }
  if (!nonEmpty(batch.batch_id)) return { ok: false, error: 'CL_BAD_PAYLOAD: batch_id is required' }
  if (!Array.isArray(batch.strata) || batch.strata.length === 0) {
    return { ok: false, error: 'CL_BAD_PAYLOAD: strata must be a non-empty array' }
  }
  for (const s of batch.strata) {
    if (!isObj(s)) return { ok: false, error: 'CL_BAD_PAYLOAD: every stratum must be an object' }
    if (!nonEmpty(s.stratum_id)) return { ok: false, error: 'CL_BAD_PAYLOAD: every stratum needs stratum_id' }
    if (typeof s.population_size !== 'number' || !Number.isInteger(s.population_size) || s.population_size < 0) {
      return { ok: false, error: 'CL_BAD_PAYLOAD: population_size must be a non-negative integer' }
    }
    if (!nonEmpty(s.selection_method)) return { ok: false, error: 'CL_BAD_PAYLOAD: every stratum needs selection_method' }
    if (!Array.isArray(s.rows)) return { ok: false, error: 'CL_BAD_PAYLOAD: every stratum needs a rows array' }
  }
  return { ok: true }
}

export function parseRoute(url: URL): 'demands' | 'batches' | null {
  const path = url.pathname.replace(/\/+$/, '')
  if (path.endsWith('/carrier-link-ingest/demands')) return 'demands'
  if (path.endsWith('/carrier-link-ingest/batches')) return 'batches'
  return null
}

export function parseDryRun(url: URL): boolean {
  return url.searchParams.get('dry_run') === 'true'
}

export const MAX_DEMANDS = 100

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

// Sampling is (re)run only while the stored batch is still 'validated'. A replayed batch that is
// 'sampled', 'undone' or 'rejected' just returns its stored summary.
export function needsSampling(batchStatus: unknown): boolean {
  return batchStatus === 'validated'
}

// Stratum ids to sample, taken from the ingest summary (never from the request body).
export function summaryStratumIds(summary: unknown): string[] {
  if (!isObj(summary) || !Array.isArray(summary.strata)) return []
  const out: string[] = []
  for (const s of summary.strata) {
    if (isObj(s) && typeof s.stratum_id === 'string') out.push(s.stratum_id)
  }
  return out
}
