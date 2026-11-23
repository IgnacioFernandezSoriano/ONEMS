/** Vista del Monitor de Carrier Link: textos de los avisos (las entregas estan en deliveryView). */

function num(v: unknown): number {
  return typeof v === 'number' && Number.isFinite(v) ? v : 0
}

export const MONITOR_PAGE_SIZE = 25

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
  // v4 (entregas completas)
  'quota_already_settled',
  'delivery_retries_exhausted',
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
      // v3: candidates_valid / samples_required; v4: population / quota_for_delivery.
      out.push({
        key: 'cl.alert.detail.insufficient_candidates',
        params: { valid: num(d.candidates_valid ?? d.population), required: num(d.samples_required ?? d.quota_for_delivery) },
      })
      break
    case 'quota_unfilled':
      out.push({ key: 'cl.alert.detail.quota_unfilled', params: { missing: num(d.missing), planned: num(d.samples_planned) } })
      break
    case 'rejected_ratio':
      out.push({
        key: 'cl.alert.detail.rejected_ratio',
        params: { rejected: num(d.rejected), candidates: num(d.candidates ?? d.shipments), percent: Math.round(num(d.ratio) * 100) },
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
      // v4 possible_misrouting: samples [{sample_id, item_id}].
      const items = list(d.item_ids) ?? list(d.samples, (x) => (x && typeof x === 'object' && typeof x.item_id === 'string' ? x.item_id : null))
      if (items) out.push({ key: 'cl.alert.detail.items', params: { items } })
      break
    }
    case 'quota_already_settled':
      out.push({ key: 'cl.alert.detail.quota_already_settled', params: { skipped: num(d.skipped) } })
      break
    case 'delivery_retries_exhausted':
      out.push({ key: 'cl.alert.detail.retries_exhausted', params: { voided: num(d.samples_voided) } })
      break
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
