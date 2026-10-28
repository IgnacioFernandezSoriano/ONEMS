import type { NodeDayLoad } from '../hooks/useNodeLoadBalancing'

export interface DayColumn {
  day: string // yyyy-MM-dd
  dow: number // 0 = domingo
  dayNum: number
  isWorkingDay: boolean
}

export interface DayView {
  columns: DayColumn[]
  /** clave `${node_code}|${day}` -> fila */
  cells: Map<string, NodeDayLoad>
}

export const dayCellKey = (nodeCode: string, day: string) => `${nodeCode}|${day}`

/** Orden natural: "KE 2" antes que "KE 10" (el orden alfabetico puro pone el 10 antes que el 2). */
export const compareNatural = (a: string, b: string) =>
  a.localeCompare(b, undefined, { numeric: true, sensitivity: 'base' })

/**
 * Numeros de semana distintos en orden cronologico. Si hay week_start_date se ordena por ella (asi la semana
 * 1 va despues de la 52 al cruzar el ano); si no, numericamente. `Array.sort()` sin comparador ordena los
 * numeros como texto (el 10 antes que el 9), que era el fallo.
 */
export function orderWeekNumbers(rows: Array<{ week_number: number; week_start_date?: string | null }>): number[] {
  const start = new Map<number, string>()
  for (const r of rows) {
    const s = r.week_start_date ?? ''
    const cur = start.get(r.week_number)
    if (cur === undefined || (s && (!cur || s < cur))) start.set(r.week_number, s)
  }
  return [...start.keys()].sort((a, b) => {
    const sa = start.get(a) ?? ''
    const sb = start.get(b) ?? ''
    if (sa && sb && sa !== sb) return sa < sb ? -1 : 1
    return a - b
  })
}

/** Dia de la semana (0 = domingo) de una fecha yyyy-MM-dd, sin depender de la zona horaria. */
export function dowOf(day: string): number {
  const [y, m, d] = day.split('-').map(Number)
  return new Date(Date.UTC(y, m - 1, d)).getUTCDay()
}

/** Una columna por dia distinto (ordenadas) y un mapa de celdas para busqueda O(1). */
export function buildDayView(rows: NodeDayLoad[]): DayView {
  const cells = new Map<string, NodeDayLoad>()
  const dayWorking = new Map<string, boolean>()
  for (const r of rows) {
    cells.set(dayCellKey(r.node_code, r.day), r)
    // un dia es laborable en la columna si lo es para algun nodo (es global a la cuenta)
    dayWorking.set(r.day, (dayWorking.get(r.day) ?? false) || r.is_working_day)
  }
  const columns = [...dayWorking.keys()].sort().map((day) => ({
    day,
    dow: dowOf(day),
    dayNum: Number(day.slice(8, 10)),
    isWorkingDay: dayWorking.get(day) ?? false,
  }))
  return { columns, cells }
}

/** Total de envios de la ciudad por dia (suma de sus nodos). */
export function dayTotals(view: DayView): Map<string, number> {
  const totals = new Map<string, number>()
  for (const r of view.cells.values()) totals.set(r.day, (totals.get(r.day) ?? 0) + r.shipment_count)
  return totals
}

/** Con POBOX, un dia laborable sin ningun envio en la ciudad es un hueco (problema), no un cero normal. */
export function isPoboxGap(total: number, isWorkingDay: boolean, pobox: boolean): boolean {
  return pobox && isWorkingDay && total === 0
}

/** Celda sombreada con envios = conflicto. */
export function isConflict(r: NodeDayLoad | undefined): boolean {
  return !!r && (r.is_unavailable || !r.is_working_day) && r.shipment_count > 0
}

export interface MonthView {
  months: string[] // yyyy-MM ordenados
  nodes: string[] // node_code ordenados
  /** node_code -> yyyy-MM -> total */
  totals: Record<string, Record<string, number>>
  monthTotals: Record<string, number>
  /** media mensual por nodo (total del nodo / nº de meses) */
  nodeAverages: Record<string, number>
  grandTotal: number
}

export function buildMonthView(rows: NodeDayLoad[]): MonthView {
  const totals: Record<string, Record<string, number>> = {}
  const monthTotals: Record<string, number> = {}
  const monthSet = new Set<string>()
  let grandTotal = 0
  for (const r of rows) {
    const month = r.day.slice(0, 7)
    monthSet.add(month)
    const n = (totals[r.node_code] ??= {})
    n[month] = (n[month] ?? 0) + r.shipment_count
    monthTotals[month] = (monthTotals[month] ?? 0) + r.shipment_count
    grandTotal += r.shipment_count
  }
  const months = [...monthSet].sort()
  const nodes = Object.keys(totals).sort(compareNatural)
  const nodeAverages: Record<string, number> = {}
  for (const node of nodes) {
    const sum = Object.values(totals[node]).reduce((s, v) => s + v, 0)
    nodeAverages[node] = months.length ? sum / months.length : 0
  }
  return { months, nodes, totals, monthTotals, nodeAverages, grandTotal }
}
