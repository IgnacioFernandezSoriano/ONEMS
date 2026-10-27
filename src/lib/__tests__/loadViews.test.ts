import { describe, it, expect } from 'vitest'
import { buildDayView, buildMonthView, isConflict, dayCellKey, dowOf } from '../loadViews'
import type { NodeDayLoad } from '../../hooks/useNodeLoadBalancing'

// 3 nodos x 5 dias: 2027-01-29 (vie) .. 2027-02-02 (mar); sab/dom no laborables
const days = ['2027-01-29', '2027-01-30', '2027-01-31', '2027-02-01', '2027-02-02']
const mk = (node: string, day: string, n: number, extra: Partial<NodeDayLoad> = {}): NodeDayLoad => ({
  city_id: 'c', city_name: 'C', node_id: node, node_code: node, panelist_name: null,
  day, shipment_count: n, pending_count: 0,
  is_working_day: ![ '2027-01-30', '2027-01-31' ].includes(day), is_unavailable: false, ...extra,
})
const counts: Record<string, number[]> = { A: [1, 2, 0, 3, 4], B: [2, 0, 0, 1, 1], C: [0, 0, 0, 0, 5] }
const rows: NodeDayLoad[] = Object.entries(counts).flatMap(([node, cs]) =>
  cs.map((n, i) => mk(node, days[i], n, node === 'C' && i === 3 ? { is_unavailable: true } : {})))

describe('loadViews', () => {
  it('dowOf', () => {
    expect(dowOf('2027-01-31')).toBe(0)
    expect(dowOf('2027-02-01')).toBe(1)
  })
  it('vista dia: columnas ordenadas y celdas', () => {
    const v = buildDayView([...rows].reverse())
    expect(v.columns.map((c) => c.day)).toEqual(days)
    expect(v.columns.map((c) => c.isWorkingDay)).toEqual([true, false, false, true, true])
    expect(v.columns[0].dayNum).toBe(29)
    expect(v.cells.get(dayCellKey('A', '2027-02-01'))?.shipment_count).toBe(3)
  })
  it('conflicto: celda sombreada con envios', () => {
    const v = buildDayView(rows)
    expect(isConflict(v.cells.get(dayCellKey('A', '2027-01-30')))).toBe(true) // sabado, 2 envios
    expect(isConflict(v.cells.get(dayCellKey('A', '2027-01-31')))).toBe(false) // domingo, 0
    expect(isConflict(v.cells.get(dayCellKey('A', '2027-02-01')))).toBe(false) // laborable
    expect(isConflict(v.cells.get(dayCellKey('C', '2027-02-01')))).toBe(false) // no disponible, 0 envios
    expect(isConflict(mk('X', '2027-02-02', 2, { is_unavailable: true }))).toBe(true)
    expect(isConflict(undefined)).toBe(false)
  })
  it('vista mes: totales exactos', () => {
    const m = buildMonthView(rows)
    expect(m.months).toEqual(['2027-01', '2027-02'])
    expect(m.nodes).toEqual(['A', 'B', 'C'])
    expect(m.totals.A).toEqual({ '2027-01': 3, '2027-02': 7 })
    expect(m.totals.B).toEqual({ '2027-01': 2, '2027-02': 2 })
    expect(m.totals.C).toEqual({ '2027-01': 0, '2027-02': 5 })
    expect(m.monthTotals).toEqual({ '2027-01': 5, '2027-02': 14 })
    expect(m.grandTotal).toBe(19)
    expect(m.nodeAverages).toEqual({ A: 5, B: 2, C: 2.5 })
  })
  it('vacio', () => {
    expect(buildDayView([]).columns).toEqual([])
    expect(buildMonthView([]).grandTotal).toBe(0)
  })
})
