/** Vista del Monitor de Carrier Link: recuentos de demandas, resumen de lotes y textos de avisos. */

export const MONITOR_PAGE_SIZE = 25

export const DEMAND_STATUSES = ['open', 'fulfilled', 'partial', 'failed'] as const
export type DemandStatus = (typeof DEMAND_STATUSES)[number]

/** Recuento por estado; los estados desconocidos se ignoran. */
export function demandCounts(demands: { status: string }[]): Record<DemandStatus, number> {
  const out: Record<DemandStatus, number> = { open: 0, fulfilled: 0, partial: 0, failed: 0 }
  for (const d of demands) if ((DEMAND_STATUSES as readonly string[]).includes(d.status)) out[d.status as DemandStatus]++
  return out
}

function num(v: unknown): number {
  return typeof v === 'number' && Number.isFinite(v) ? v : 0
}

/**
 * Resumen de un lote. `cl_batches.summary` (de cl_ingest_batch) trae `strata[]` con `candidates` (envios distintos del
 * estrato) y `rejected` ({motivo: n}); los elegidos no estan en el resumen: salen de cl_sampling_runs y se pasan en
 * `selected` (si el resumen trajera `samples_selected` por estrato, se usa). Campos ausentes -> 0.
 */
export function batchSummary(b: { summary: unknown; selected?: number }): {
  shipments: number
  rejected: number
  selected: number
} {
  const strata = (b.summary as { strata?: unknown } | null)?.strata
  let shipments = 0
  let rejected = 0
  let selectedInSummary = 0
  if (Array.isArray(strata)) {
    for (const s of strata as Record<string, unknown>[]) {
      if (!s || typeof s !== 'object') continue
      shipments += num(s.candidates)
      if (s.rejected && typeof s.rejected === 'object') {
        for (const n of Object.values(s.rejected as Record<string, unknown>)) rejected += num(n)
      }
      selectedInSummary += num(s.samples_selected)
    }
  }
  return { shipments, rejected, selected: selectedInSummary || num(b.selected) }
}

/** Tipos de aviso de la spec (§5) mas los que lanza el codigo de la base. Cada uno tiene `cl.alert.<tipo>`. */
export const CL_ALERT_TYPES = [
  'insufficient_candidates',
  'empty_stratum',
  'population_drop',
  'population_incoherent',
  'suspicious_distribution',
  'late_batch',
  'unknown_product',
  'unknown_reading_point',
  'possible_misrouting',
  'missing_standard',
  'rejected_ratio',
  'quota_unfilled',
  'feed_silent',
  'missing_points',
  'invalid_timezone',
  'emit_failed',
  'selection_method',
  'reader_without_city',
  'undo_after_carry',
] as const

export function alertLabelKey(alertType: string): string {
  return `cl.alert.${alertType}`
}

export interface AlertDetailLine {
  key: string
  params?: Record<string, string | number>
}

const MAX_LISTED = 5

function list(v: unknown, pick: (x: any) => string | null = (x) => (typeof x === 'string' ? x : null)): string | null {
  if (!Array.isArray(v) || v.length === 0) return null
  const items = v.map(pick).filter((x): x is string => !!x)
  if (items.length === 0) return null
  const shown = items.slice(0, MAX_LISTED).join(', ')
  return items.length > MAX_LISTED ? `${shown} (+${items.length - MAX_LISTED})` : shown
}

/**
 * Lineas legibles con los datos de un aviso (nunca JSON crudo). `route` = ruta de la cuota o de details, ya con
 * nombres de ciudad. Tipos sin datos utiles para el usuario (p. ej. emit_failed, con el error interno) no dan lineas.
 */
export function alertDetailLines(
  alertType: string,
  details: unknown,
  route: { origin: string; destination: string } | null,
): AlertDetailLine[] {
  const d = (details && typeof details === 'object' ? details : {}) as Record<string, any>
  const out: AlertDetailLine[] = []
  if (route) out.push({ key: 'cl.alert.route', params: { origin: route.origin, destination: route.destination } })
  switch (alertType) {
    case 'insufficient_candidates':
      out.push({
        key: 'cl.alert.detail.insufficient_candidates',
        params: { valid: num(d.candidates_valid), required: num(d.samples_required) },
      })
      break
    case 'quota_unfilled':
      out.push({ key: 'cl.alert.detail.quota_unfilled', params: { missing: num(d.missing), planned: num(d.samples_planned) } })
      break
    case 'rejected_ratio':
      out.push({
        key: 'cl.alert.detail.rejected_ratio',
        params: { rejected: num(d.rejected), candidates: num(d.candidates), percent: Math.round(num(d.ratio) * 100) },
      })
      break
    case 'population_incoherent':
      out.push({
        key: 'cl.alert.detail.population_incoherent',
        params: { population: num(d.population_size), candidates: num(d.candidates) },
      })
      break
    case 'suspicious_distribution':
      out.push({ key: 'cl.alert.detail.suspicious_distribution', params: { samples: num(d.samples) } })
      break
    case 'missing_points':
      out.push({ key: 'cl.alert.detail.missing_points', params: { start: num(d.start_points), end: num(d.end_points) } })
      break
    case 'possible_misrouting':
    case 'reader_without_city': {
      const items = list(d.item_ids)
      if (items) out.push({ key: 'cl.alert.detail.items', params: { items } })
      break
    }
    case 'unknown_product': {
      const values = list(d.values)
      if (values) out.push({ key: 'cl.alert.detail.products', params: { values } })
      break
    }
    case 'unknown_reading_point': {
      const points = list(d.points, (p) => (p && typeof p === 'object' ? `${p.place_ref ?? '-'} / ${p.mode_ref ?? '-'}` : null))
      if (points) out.push({ key: 'cl.alert.detail.points', params: { points } })
      break
    }
    case 'feed_silent':
      if (typeof d.requested_at === 'string')
        out.push({ key: 'cl.alert.detail.feed_silent', params: { date: new Date(d.requested_at).toLocaleDateString() } })
      break
    case 'selection_method':
      if (typeof d.expected === 'string') out.push({ key: 'cl.alert.detail.selection_method', params: { expected: d.expected } })
      break
    default:
      break
  }
  return out
}
