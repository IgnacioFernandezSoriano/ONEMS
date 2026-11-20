import { carriersForCapture } from '../carrierCapture'
import { parseWeekKey, weekKey } from './sampleView'

/**
 * Planes de Asignación con planes de Carrier Link: el registro de un plan de Carrier Link es una cuota
 * ruta × semana (cl_plan_quotas), de solo lectura (la cambian el generador y el balanceo).
 * Sin Carrier Link (producción, sin permiso o sin carriers de Carrier Link) la página es la de siempre.
 */

/** Se muestran planes de Carrier Link: flag (DEV), View en cl_plans, cuenta elegida y un carrier carrier_link|both. */
export function carrierLinkPlansVisible(p: {
  flagOn: boolean
  canViewPlans: boolean
  accountId: string | null
  carriers: { capture_method?: string | null }[]
}): boolean {
  return p.flagOn && p.canViewPlans && p.accountId !== null && carriersForCapture(p.carriers, 'carrier_link').length > 0
}

const CL_OPTION_PREFIX = 'cl:'

/** Valor de un plan de Carrier Link en el selector de plan (los de panelistas siguen con su id). */
export const clPlanOptionValue = (planId: string) => `${CL_OPTION_PREFIX}${planId}`

/** Id del plan de Carrier Link de un valor del selector; null si es un plan de panelistas o "todos". */
export function parseClPlanOption(value: string): string | null {
  if (!value.startsWith(CL_OPTION_PREFIX)) return null
  return value.slice(CL_OPTION_PREFIX.length) || null
}

/** Texto de la opción: nombre · marca de captura · estado. */
export function clPlanOptionLabel(plan: { plan_name: string; status: string }, t: (key: string) => string): string {
  return `${plan.plan_name} · ${t('cl.capture_method.carrier_link')} · ${t(`cl.plans.status.${plan.status}`)}`
}

/** Estados de una cuota (CHECK de cl_plan_quotas). */
export const QUOTA_STATUSES = ['pending', 'open', 'fulfilled', 'carried', 'unfilled'] as const

export interface QuotaFilters {
  /** Ciudad de origen (id) o '' = todas. */
  origin: string
  destination: string
  /** Semana 'YYYY-Www' o '' = todas. */
  week: string
  /** Estado de la cuota o '' = todos. */
  status: string
}

export const EMPTY_QUOTA_FILTERS: QuotaFilters = { origin: '', destination: '', week: '', status: '' }

export const QUOTA_COLUMNS =
  'id, origin_city_id, destination_city_id, iso_year, iso_week, period_start, period_end, samples_planned, samples_carried_in, samples_obtained, demands_count, status'

/** Orden estable de la tabla: semana, ruta e id (para que las páginas no se solapen). */
export const QUOTA_ORDER = ['iso_year', 'iso_week', 'origin_city_id', 'destination_city_id', 'id'] as const

/** Aplica el plan y los filtros a la consulta de cuotas (todo en el servidor). Semana o estado no válidos se ignoran. */
export function applyQuotaFilters<B extends { eq(column: string, value: unknown): B }>(q: B, planId: string, f: QuotaFilters): B {
  let out = q.eq('plan_id', planId)
  if (f.origin) out = out.eq('origin_city_id', f.origin)
  if (f.destination) out = out.eq('destination_city_id', f.destination)
  const wk = f.week ? parseWeekKey(f.week) : null
  if (wk) out = out.eq('iso_year', wk.iso_year).eq('iso_week', wk.iso_week)
  if ((QUOTA_STATUSES as readonly string[]).includes(f.status)) out = out.eq('status', f.status)
  return out
}

/** Rango inclusivo de `.range()` para una página 1-based. */
export function quotaPageRange(page: number, pageSize: number): { from: number; to: number } {
  const from = Math.max(0, page - 1) * pageSize
  return { from, to: from + pageSize - 1 }
}

export interface QuotaRecord {
  id: string
  origin_city_id: string
  destination_city_id: string
  /** 'YYYY-Www' */
  week: string
  period_start: string
  period_end: string
  planned: number
  carried_in: number
  obtained: number
  demands: number
  status: string
}

/** Fila de cl_plan_quotas como registro de la tabla. */
export function toQuotaRecord(r: Record<string, any>): QuotaRecord {
  return {
    id: r.id,
    origin_city_id: r.origin_city_id,
    destination_city_id: r.destination_city_id,
    week: weekKey(r.iso_year, r.iso_week),
    period_start: r.period_start,
    period_end: r.period_end,
    planned: r.samples_planned ?? 0,
    carried_in: r.samples_carried_in ?? 0,
    obtained: r.samples_obtained ?? 0,
    demands: r.demands_count ?? 0,
    status: r.status,
  }
}

export function quotaTotals(rows: QuotaRecord[]): { planned: number; carried_in: number; obtained: number; demands: number } {
  return rows.reduce(
    (a, r) => ({
      planned: a.planned + r.planned,
      carried_in: a.carried_in + r.carried_in,
      obtained: a.obtained + r.obtained,
      demands: a.demands + r.demands,
    }),
    { planned: 0, carried_in: 0, obtained: 0, demands: 0 },
  )
}

/** Totales de todas las cuotas que cumplen los filtros (cl_plan_quota_totals). */
export interface QuotaFilterTotals {
  quotas: number
  planned: number
  carried_in: number
  obtained: number
  demands: number
}

/** Parámetros de cl_plan_quota_totals con los mismos filtros que la tabla (vacíos o no válidos = sin filtro). */
export function quotaTotalsParams(planId: string, f: QuotaFilters): Record<string, string | number | null> {
  const wk = f.week ? parseWeekKey(f.week) : null
  return {
    p_plan_id: planId,
    p_origin: f.origin || null,
    p_destination: f.destination || null,
    p_iso_year: wk ? wk.iso_year : null,
    p_iso_week: wk ? wk.iso_week : null,
    p_status: (QUOTA_STATUSES as readonly string[]).includes(f.status) ? f.status : null,
  }
}

/** Fila devuelta por cl_plan_quota_totals (bigint puede llegar como texto). Sin fila: null. */
export function toQuotaFilterTotals(data: unknown): QuotaFilterTotals | null {
  const row = (Array.isArray(data) ? data[0] : data) as Record<string, unknown> | null | undefined
  if (!row) return null
  const n = (v: unknown) => Number(v ?? 0) || 0
  return {
    quotas: n(row.quotas),
    planned: n(row.planned),
    carried_in: n(row.carried),
    obtained: n(row.obtained),
    demands: n(row.demands),
  }
}

export const SAMPLES_PATH = '/carrier-link/samples'

/** Enlace a Muestras filtrado por el plan y, si se da, la semana y la ruta de una cuota. */
export function samplesLink(
  planId: string,
  quota?: { week: string; origin_city_id: string; destination_city_id: string },
): string {
  const p = new URLSearchParams({ plan: planId })
  if (quota) {
    p.set('week', quota.week)
    p.set('origin', quota.origin_city_id)
    p.set('destination', quota.destination_city_id)
  }
  return `${SAMPLES_PATH}?${p.toString()}`
}

/** Filtros iniciales de Muestras desde la URL (sin parámetros: los de siempre). */
export function samplesParams(search: URLSearchParams): {
  plan: string | null
  week: string | null
  origin: string
  destination: string
} {
  const week = search.get('week')
  return {
    plan: search.get('plan') || null,
    week: week && parseWeekKey(week) ? week : null,
    origin: search.get('origin') ?? '',
    destination: search.get('destination') ?? '',
  }
}
