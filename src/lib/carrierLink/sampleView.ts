import { isoWeekOf } from './quotaCalculator'

export interface SampleFilters {
  /** Semana ISO "YYYY-Www" o null (todas). */
  week: string | null
  /** Ruta "origen>destino" (ids de ciudad); cualquiera de las dos partes puede ir vacía (= cualquiera). */
  route: string | null
  misroutedOnly: boolean
}

export const SAMPLES_PAGE_SIZE = 50

export function sampleRouteKey(origin: string | null | undefined, destination: string | null | undefined): string {
  return `${origin ?? ''}>${destination ?? ''}`
}

export function weekKey(isoYear: number, isoWeek: number): string {
  return `${isoYear}-W${String(isoWeek).padStart(2, '0')}`
}

export function parseWeekKey(w: string): { iso_year: number; iso_week: number } | null {
  const m = /^(\d{4})-W(\d{1,2})$/.exec(w)
  return m ? { iso_year: Number(m[1]), iso_week: Number(m[2]) } : null
}

export function parseRouteFilter(route: string | null): { origin: string | null; destination: string | null } {
  if (!route) return { origin: null, destination: null }
  const [o, d] = route.split('>')
  return { origin: o || null, destination: d || null }
}

/** Refinamiento en memoria (la pantalla filtra en la consulta; esto sirve para tests y refinamientos locales). */
export function filterSamples<T extends { quota_week?: string; route_key: string; possible_misrouting: boolean }>(
  rows: T[],
  f: SampleFilters,
): T[] {
  const { origin, destination } = parseRouteFilter(f.route)
  return rows.filter((r) => {
    if (f.week && r.quota_week !== f.week) return false
    if (origin || destination) {
      const [o, d] = r.route_key.split('>')
      if (origin && o !== origin) return false
      if (destination && d !== destination) return false
    }
    if (f.misroutedOnly && !r.possible_misrouting) return false
    return true
  })
}

/** Tránsito real entre la lectura de inicio y la de fin: días con un decimal y horas enteras. */
export function transitLabel(startAt: string, endAt: string): { days: number; hours: number } {
  const ms = new Date(endAt).getTime() - new Date(startAt).getTime()
  const hoursExact = ms / 3600000
  return { days: Math.round((hoursExact / 24) * 10) / 10, hours: Math.floor(hoursExact) }
}

/** Semanas ISO que cubre un plan, en orden (para el selector de semana). */
export function planWeekKeys(startDate: string, endDate: string): string[] {
  const out: string[] = []
  const d = new Date(`${startDate}T12:00:00`)
  const end = new Date(`${endDate}T12:00:00`)
  if (isNaN(d.getTime()) || isNaN(end.getTime())) return out
  while (d <= end) {
    const { iso_year, iso_week } = isoWeekOf(d)
    const k = weekKey(iso_year, iso_week)
    if (out[out.length - 1] !== k) out.push(k)
    d.setDate(d.getDate() + 1)
  }
  return out
}

/** Página válida más cercana (0-based): si el total se reduce y la página queda fuera de rango, vuelve a la última (o a 0). */
export function clampPage(page: number, total: number, pageSize: number = SAMPLES_PAGE_SIZE): number {
  const last = Math.max(0, Math.ceil(total / pageSize) - 1)
  return Math.min(Math.max(0, page), last)
}
