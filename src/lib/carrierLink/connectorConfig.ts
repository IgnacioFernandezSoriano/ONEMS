import { clErrorKey } from './clErrors'

/** Campos estándar de una lectura del carrier (CHECK de cl_field_mappings.standard_field). */
export const STANDARD_FIELDS = ['item_id', 'product', 'scan_at', 'place_ref', 'mode_ref'] as const
export type StandardField = (typeof STANDARD_FIELDS)[number]

/** Sin estos tres el motor no puede leer un lote (product y mode_ref son opcionales). */
export const REQUIRED_STANDARD_FIELDS: readonly StandardField[] = ['item_id', 'scan_at', 'place_ref']

export type ConnectorStatus = 'testing' | 'active' | 'paused'
export const CONNECTOR_STATUSES: readonly ConnectorStatus[] = ['testing', 'active', 'paused']

/** Días ISO (1 = lunes … 7 = domingo). */
export const ISO_DAYS = [1, 2, 3, 4, 5, 6, 7] as const

export function validateFieldMappings(m: { standard_field: string; carrier_field: string }[]): {
  ok: boolean
  missing: string[]
  duplicates: string[]
} {
  const counts = new Map<string, number>()
  const present = new Set<string>()
  for (const r of m) {
    counts.set(r.standard_field, (counts.get(r.standard_field) ?? 0) + 1)
    if (r.carrier_field.trim() !== '') present.add(r.standard_field)
  }
  const missing = REQUIRED_STANDARD_FIELDS.filter((f) => !present.has(f))
  const duplicates = [...counts.entries()].filter(([, n]) => n > 1).map(([f]) => f)
  return { ok: missing.length === 0 && duplicates.length === 0, missing, duplicates }
}

export function validateCalendar(c: { emit_days: number[]; emit_hour: number; emit_timezone: string | null }): {
  ok: boolean
  error?: 'no_days' | 'bad_day' | 'bad_hour'
} {
  if (c.emit_days.length === 0) return { ok: false, error: 'no_days' }
  const valid = c.emit_days.every((d) => Number.isInteger(d) && d >= 1 && d <= 7)
  if (!valid || new Set(c.emit_days).size !== c.emit_days.length) return { ok: false, error: 'bad_day' }
  if (!Number.isInteger(c.emit_hour) || c.emit_hour < 0 || c.emit_hour > 23) return { ok: false, error: 'bad_hour' }
  return { ok: true }
}

/** Las claves de conector solo las emite un superadmin o el UPU Account Manager de la cuenta. */
export function canManageCarrierKeys(p: { isSuperadmin: boolean; isUpuAm: boolean }): boolean {
  return p.isSuperadmin || p.isUpuAm
}

/** Clave i18n del error al escribir la configuración de un conector. */
export function connectorErrorKey(err: { message?: string; code?: string } | null): string {
  if (err && /CL_[A-Z_]+/.test(err.message ?? '')) return clErrorKey(err)
  if (err?.code === '23505') return 'cl.connectors.error.duplicate'
  if (err?.code === '23503') return 'cl.connectors.error.in_use'
  if (err?.code === '23514') return 'cl.connectors.error.invalid_value'
  return clErrorKey(err)
}

export interface DryRunReasonCount {
  reason: string
  count: number
}

export interface DryRunStratum {
  stratum_id: string
  population_size: number | null
  rows: number | null
  candidates: number | null
  candidates_valid: number | null
  /** Candidatos rechazados por motivo. */
  rejected: DryRunReasonCount[]
  /** Lecturas rechazadas por motivo propio (lugar o producto desconocido…). */
  rows_rejected: DryRunReasonCount[]
}

export interface DryRunSummary {
  status: string | null
  /** Motivo de rechazo del lote entero (p. ej. 'selection_method'). */
  reason: string | null
  expected: string | null
  /** true = ese lote (batch_id) ya se habia ensayado: es el resumen guardado, no un ensayo nuevo. */
  replayed: boolean
  strata: DryRunStratum[]
}

const num = (v: unknown): number | null => (typeof v === 'number' && Number.isFinite(v) ? v : null)
const str = (v: unknown): string | null => (typeof v === 'string' ? v : null)
const counts = (v: unknown): DryRunReasonCount[] =>
  v && typeof v === 'object' && !Array.isArray(v)
    ? Object.entries(v as Record<string, unknown>)
        .map(([reason, n]) => ({ reason, count: num(n) ?? 0 }))
        .sort((a, b) => b.count - a.count || a.reason.localeCompare(b.reason))
    : []

/** Resultado del ensayo: aceptado solo si la base dice 'validated'; cualquier otra cosa no se da por buena. */
export function dryRunOutcome(s: DryRunSummary): 'accepted' | 'rejected' | 'unknown' {
  if (s.status === 'validated') return 'accepted'
  if (s.status === 'rejected') return 'rejected'
  return 'unknown'
}

/** Lee el jsonb que devuelve cl_dry_run_batch (mismo resumen que cl_ingest_batch) sin fiarse de su forma. */
export function parseDryRunResult(data: unknown): DryRunSummary {
  const o = data && typeof data === 'object' && !Array.isArray(data) ? (data as Record<string, unknown>) : {}
  const strata = Array.isArray(o.strata) ? o.strata : []
  return {
    status: str(o.status),
    reason: str(o.reason),
    expected: str(o.expected),
    replayed: o.replayed === true,
    strata: strata
      .filter((e): e is Record<string, unknown> => !!e && typeof e === 'object')
      .map((e) => ({
        stratum_id: str(e.stratum_id) ?? '',
        population_size: num(e.population_size),
        rows: num(e.rows),
        candidates: num(e.candidates),
        candidates_valid: num(e.candidates_valid),
        rejected: counts(e.rejected),
        rows_rejected: counts(e.rows_rejected),
      })),
  }
}
