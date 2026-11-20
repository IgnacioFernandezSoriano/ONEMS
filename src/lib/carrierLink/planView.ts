/** Cuota tal y como se lee de cl_plan_quotas (o se previsualiza desde el generador). */
export interface QuotaInput {
  origin_city_id: string
  destination_city_id: string
  iso_year: number
  iso_week: number
  samples_planned: number
  samples_carried_in: number
  samples_obtained: number
  status: string
}

export interface QuotaCell {
  planned: number
  carried: number
  obtained: number
  /** Estado de la cuota; en la vista por mes, 'mixed' si las semanas no coinciden. */
  status: string
}

export interface QuotaRow {
  route: string
  /** `${origin_city_id}|${destination_city_id}` */
  key: string
  origin_city_id: string
  origin: string
  cells: Record<string, QuotaCell | null>
  /** Suma de previsto + arrastrado de la ruta. */
  total: number
}

export interface QuotaMatrixData {
  /** Columnas: '2026-W45' (semana ISO) o '2027-01' (mes). */
  weeks: string[]
  rows: QuotaRow[]
}

export interface OriginGroup {
  origin_city_id: string
  origin: string
  rows: QuotaRow[]
  cells: Record<string, { planned: number; carried: number; obtained: number }>
  total: number
}

export const routeKey = (originCityId: string, destinationCityId: string) => `${originCityId}|${destinationCityId}`

const weekKey = (y: number, w: number) => `${y}-W${String(w).padStart(2, '0')}`

function parseWeekKey(k: string): { y: number; w: number } {
  const m = /^(\d{4})-W(\d{2})$/.exec(k)
  return m ? { y: Number(m[1]), w: Number(m[2]) } : { y: 0, w: 0 }
}

/** Mes ('YYYY-MM') del lunes de una semana ISO. */
function mondayMonth(y: number, w: number): string {
  const jan4 = Date.UTC(y, 0, 4)
  const jan4Dow = (new Date(jan4).getUTCDay() + 6) % 7 // 0 = lunes
  const monday = new Date(jan4 + ((w - 1) * 7 - jan4Dow) * 86400000)
  return `${monday.getUTCFullYear()}-${String(monday.getUTCMonth() + 1).padStart(2, '0')}`
}

/** Tabla ruta × semana. Filas ordenadas por nombre de ruta 'Origen → Destino'; semana sin cuota = null. */
export function quotaMatrix(quotas: QuotaInput[], cityName: (id: string) => string): QuotaMatrixData {
  const weekSet = new Map<string, { y: number; w: number }>()
  const byRoute = new Map<string, QuotaRow>()
  for (const q of quotas) {
    const wk = weekKey(q.iso_year, q.iso_week)
    weekSet.set(wk, { y: q.iso_year, w: q.iso_week })
    const key = routeKey(q.origin_city_id, q.destination_city_id)
    let row = byRoute.get(key)
    if (!row) {
      const origin = cityName(q.origin_city_id)
      row = {
        route: `${origin} → ${cityName(q.destination_city_id)}`,
        key,
        origin_city_id: q.origin_city_id,
        origin,
        cells: {},
        total: 0,
      }
      byRoute.set(key, row)
    }
    row.cells[wk] = { planned: q.samples_planned, carried: q.samples_carried_in, obtained: q.samples_obtained, status: q.status }
    row.total += q.samples_planned + q.samples_carried_in
  }
  const weeks = [...weekSet.entries()].sort((a, b) => a[1].y - b[1].y || a[1].w - b[1].w).map(([k]) => k)
  const rows = [...byRoute.values()].sort((a, b) => a.route.localeCompare(b.route) || a.key.localeCompare(b.key))
  for (const r of rows) for (const wk of weeks) if (!(wk in r.cells)) r.cells[wk] = null
  return { weeks, rows }
}

/** Misma tabla con columnas por mes (suma de las semanas cuyo lunes cae en ese mes) si `by = 'month'`. */
export function groupQuotaMatrix(m: QuotaMatrixData, by: 'week' | 'month'): QuotaMatrixData {
  if (by === 'week') return m
  const monthOf = new Map<string, string>()
  for (const wk of m.weeks) {
    const { y, w } = parseWeekKey(wk)
    monthOf.set(wk, mondayMonth(y, w))
  }
  const months = [...new Set(m.weeks.map((wk) => monthOf.get(wk)!))].sort()
  const rows = m.rows.map((r) => {
    const cells: Record<string, QuotaCell | null> = {}
    for (const mo of months) cells[mo] = null
    for (const wk of m.weeks) {
      const c = r.cells[wk]
      if (!c) continue
      const mo = monthOf.get(wk)!
      const acc = cells[mo]
      cells[mo] = acc
        ? {
            planned: acc.planned + c.planned,
            carried: acc.carried + c.carried,
            obtained: acc.obtained + c.obtained,
            status: acc.status === c.status ? acc.status : 'mixed',
          }
        : { ...c }
    }
    return { ...r, cells }
  })
  return { weeks: months, rows }
}

/** Filas agrupadas por ciudad de origen (orden por nombre), con totales por columna y total del grupo. */
export function originGroups(rows: QuotaRow[]): OriginGroup[] {
  const groups = new Map<string, OriginGroup>()
  for (const r of rows) {
    let g = groups.get(r.origin_city_id)
    if (!g) {
      g = { origin_city_id: r.origin_city_id, origin: r.origin, rows: [], cells: {}, total: 0 }
      groups.set(r.origin_city_id, g)
    }
    g.rows.push(r)
    g.total += r.total
    for (const [col, c] of Object.entries(r.cells)) {
      if (!c) continue
      const acc = g.cells[col] ?? { planned: 0, carried: 0, obtained: 0 }
      g.cells[col] = { planned: acc.planned + c.planned, carried: acc.carried + c.carried, obtained: acc.obtained + c.obtained }
    }
  }
  return [...groups.values()].sort((a, b) => a.origin.localeCompare(b.origin) || a.origin_city_id.localeCompare(b.origin_city_id))
}

/** Máximo de celdas desplegadas a la vez antes de dejar abierto un solo grupo. */
export const MAX_EXPANDED_CELLS = 2000

/** Abre o cierra un grupo; si los abiertos superan el límite de celdas, solo queda abierto el nuevo. */
export function nextExpandedGroups(
  expanded: string[],
  toggled: string,
  cellCount: (group: string) => number,
  limit = MAX_EXPANDED_CELLS,
): string[] {
  if (expanded.includes(toggled)) return expanded.filter((g) => g !== toggled)
  const next = [...expanded, toggled]
  const cells = next.reduce((a, g) => a + cellCount(g), 0)
  return cells > limit ? [toggled] : next
}

export interface PlanForm {
  plan_name: string
  carrier_id: string
  product_id: string
  feed_id: string
  start_date: string
  end_date: string
  total_samples: number
  feed_diagnosis: boolean
}

export type PlanRowResult =
  | { ok: true; row: Record<string, unknown> }
  | { ok: false; error: 'no_account' | 'bad_period' | 'bad_total' | 'missing_field' }

/** Fila de cl_plans desde el formulario. El conector es opcional al crear (activar lo exige). */
export function buildPlanRow(accountId: string | null, f: PlanForm): PlanRowResult {
  if (!accountId) return { ok: false, error: 'no_account' }
  const name = f.plan_name.trim()
  if (!name || !f.carrier_id || !f.product_id || !f.start_date || !f.end_date) return { ok: false, error: 'missing_field' }
  if (f.end_date < f.start_date) return { ok: false, error: 'bad_period' }
  if (!Number.isInteger(f.total_samples) || f.total_samples < 1) return { ok: false, error: 'bad_total' }
  return {
    ok: true,
    row: {
      account_id: accountId,
      plan_name: name,
      carrier_id: f.carrier_id,
      product_id: f.product_id,
      feed_id: f.feed_id || null,
      start_date: f.start_date,
      end_date: f.end_date,
      total_samples: f.total_samples,
      feed_diagnosis: f.feed_diagnosis,
    },
  }
}

/** Campos que la base fija cuando el plan deja de ser borrador (CL_PLAN_LOCKED_FIELD). */
export const LOCKED_WHEN_NOT_DRAFT = ['carrier_id', 'product_id', 'feed_id', 'start_date'] as const
