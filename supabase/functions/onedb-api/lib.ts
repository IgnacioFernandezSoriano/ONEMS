export type ParsedQuery =
  | { ok: true; startDate: string; endDate: string; limit: number; offset: number; source: 'panelist' | 'carrier' | null }
  | { ok: false; error: string }

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/

function isRealDate(s: string): boolean {
  const d = new Date(s + 'T00:00:00Z')
  return !isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s
}

export function parseQuery(url: URL): ParsedQuery {
  const p = url.searchParams
  const startDate = p.get('start_date')
  const endDate = p.get('end_date')
  if (!startDate || !endDate) {
    return { ok: false, error: 'Missing required parameters: start_date and end_date (format: YYYY-MM-DD)' }
  }
  if (!DATE_RE.test(startDate) || !DATE_RE.test(endDate) || !isRealDate(startDate) || !isRealDate(endDate)) {
    return { ok: false, error: 'Invalid date format. Use YYYY-MM-DD' }
  }
  const rawLimit = parseInt(p.get('limit') || '100', 10)
  const limit = Number.isFinite(rawLimit) && rawLimit > 0 ? Math.min(rawLimit, 1000) : 100
  const rawOffset = parseInt(p.get('offset') || '0', 10)
  const offset = Number.isFinite(rawOffset) && rawOffset > 0 ? rawOffset : 0
  const rawSource = p.get('source')
  if (rawSource !== null && rawSource !== 'panelist' && rawSource !== 'carrier') {
    return { ok: false, error: "Invalid source. Use 'panelist' or 'carrier'" }
  }
  return { ok: true, startDate, endDate, limit, offset, source: rawSource }
}

/** Day after a YYYY-MM-DD date (UTC), as YYYY-MM-DD. */
export function nextDay(date: string): string {
  const d = new Date(date + 'T00:00:00Z')
  d.setUTCDate(d.getUTCDate() + 1)
  return d.toISOString().slice(0, 10)
}

/** API key from `x-api-key` (preferred) or `Authorization: Bearer <key>`. Null if missing/blank. */
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
