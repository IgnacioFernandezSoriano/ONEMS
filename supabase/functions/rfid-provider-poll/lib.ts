export interface ProviderRecord {
  id: string
  location: string
  readerId: string
  tagId: string
  timestamp: string
  ingested_at: string
}

export interface LandingRow {
  id: string
  location: string
  reader_id: string
  tag_id_raw: string
  read_local_datetime: string
  ingested_at: string
  match_status: 'pending'
}

/** Build the reads URL. Exactly one of cursor|since is sent (cursor wins). */
export function buildReadsUrl(
  baseUrl: string,
  opts: { cursor?: string | null; since?: string | null; limit: number },
): string {
  const params = new URLSearchParams()
  if (opts.cursor) {
    params.set('cursor', opts.cursor)
  } else if (opts.since) {
    params.set('since', opts.since)
  }
  params.set('limit', String(opts.limit))
  return `${baseUrl}?${params.toString()}`
}

/** Parse Retry-After header (seconds). Defaults to 1s on missing/invalid. */
export function parseRetryAfter(headerValue: string | null): number {
  if (!headerValue) return 1
  const n = parseInt(headerValue, 10)
  return Number.isFinite(n) && n > 0 ? n : 1
}

/** Provider guarantees tagId + location populated; defend anyway. */
export function isValidRecord(rec: ProviderRecord): boolean {
  return Boolean(rec && rec.id && rec.tagId && rec.location)
}

export function toLandingRow(rec: ProviderRecord): LandingRow {
  return {
    id: rec.id,
    location: rec.location,
    reader_id: rec.readerId,
    tag_id_raw: rec.tagId,
    read_local_datetime: rec.timestamp,
    ingested_at: rec.ingested_at,
    match_status: 'pending',
  }
}
