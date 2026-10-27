import type { BalanceResult, MatrixCell } from '../hooks/useNodeLoadBalancing'
import { compareNatural } from './loadViews'

export interface AllCitiesRow {
  cityId: string
  cityName: string
  result?: BalanceResult
  error?: string
}

export interface AllCitiesTotals {
  cities: number
  failed: number
  movements: number
  poboxMoved: number
  poboxCreated: number
  poboxUncovered: number
  warnings: number
}

/** Una ciudad cuenta como fallida si trae error o su resultado no es success. */
export function isCityFailed(r: AllCitiesRow): boolean {
  return !!r.error || !r.result || r.result.success === false || !!r.result.error
}

/** Algo que aplicar: envios movidos o dias POBOX movidos/creados */
export function cityHasChanges(r?: BalanceResult): boolean {
  return !!r && !r.error && r.success !== false &&
    ((r.movements_count || 0) > 0 || (r.pobox?.days_moved || 0) > 0 || (r.pobox?.days_created || 0) > 0)
}

/** Ids exactos a aplicar tras la vista previa: ciudades no fallidas y con cambios. */
export function cityIdsToApply(rows: AllCitiesRow[]): string[] {
  return rows.filter((r) => !isCityFailed(r) && cityHasChanges(r.result)).map((r) => r.cityId)
}

/** Totales de la tabla "todas las ciudades". Las ciudades fallidas no suman. */
export function totalsForAllCities(rows: AllCitiesRow[]): AllCitiesTotals {
  const t: AllCitiesTotals = {
    cities: rows.length, failed: 0, movements: 0, poboxMoved: 0, poboxCreated: 0, poboxUncovered: 0, warnings: 0,
  }
  for (const r of rows) {
    if (isCityFailed(r)) {
      t.failed++
      continue
    }
    const res = r.result!
    t.movements += res.movements_count || 0
    t.poboxMoved += res.pobox?.days_moved || 0
    t.poboxCreated += res.pobox?.days_created || 0
    t.poboxUncovered += res.pobox?.days_uncovered || 0
    t.warnings += (res.warnings || []).length
  }
  return t
}

export interface WeekMatrix {
  nodes: string[]
  /** Columnas ordenadas: key unico (week_start si existe) y numero de semana para la etiqueta */
  weeks: Array<{ key: string; weekNum: number }>
  /** `${node}|${weekKey}` -> carga sumada de los dias de la semana */
  lookup: Record<string, number>
}

/** Agrupa una matriz (semanal o diaria) por nodo y semana, sumando los dias. */
export function groupMatrixByWeek(cells: MatrixCell[]): WeekMatrix {
  const nodes = Array.from(new Set(cells.map((c) => c.node_code))).sort(compareNatural)
  const weekMap = new Map<string, number>()
  const lookup: Record<string, number> = {}
  for (const c of cells) {
    const key = c.week_start ?? String(c.week_num).padStart(3, '0')
    weekMap.set(key, c.week_num)
    const k = `${c.node_code}|${key}`
    lookup[k] = (lookup[k] || 0) + c.load_count
  }
  const weeks = Array.from(weekMap.entries())
    .sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))
    .map(([key, weekNum]) => ({ key, weekNum }))
  return { nodes, weeks, lookup }
}
