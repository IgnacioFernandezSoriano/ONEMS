import { describe, expect, it } from 'vitest'
import { analyzeCity, type CityAnalysisInput } from '../cityAnalysis'
import type { NodeDayLoad } from '../../hooks/useNodeLoadBalancing'

const row = (node_code: string, day: string, o: Partial<NodeDayLoad> = {}): NodeDayLoad => ({
  city_id: 'c', city_name: 'C', node_id: node_code, node_code, panelist_name: `P ${node_code}`, day,
  shipment_count: 0, pending_count: 0, is_working_day: true, is_unavailable: false, ...o,
})

const base: CityAnalysisInput = {
  weekCells: [{ node_code: 'N1', week_number: 10, shipment_count: 3 }],
  highThreshold: 7.2, saturatedThreshold: 7.8, dayRows: [], datePolicy: 'daily', pobox: false, today: '2027-03-01',
}
const codes = (i: CityAnalysisInput) => analyzeCity(i).map((f) => f.code)

describe('analyzeCity', () => {
  it('carga normal y sin datos diarios: solo "load_ok"', () => {
    expect(codes(base)).toEqual(['load_ok'])
  })

  it('celdas saturadas y altas se cuentan por separado y piden balancear', () => {
    const weekCells = [
      { node_code: 'N1', week_number: 10, shipment_count: 9 },
      { node_code: 'N1', week_number: 11, shipment_count: 7.5 },
      { node_code: 'N2', week_number: 10, shipment_count: 1 },
      { node_code: 'N2', week_number: 11, shipment_count: 1 },
    ]
    const f = analyzeCity({ ...base, weekCells })
    expect(f.map((x) => x.code)).toEqual(['load_critical', 'load_warning', 'action_balance'])
    expect(f[0].params).toMatchObject({ count: 1, pct: 25, threshold: '7.8' })
    expect(f[1].params).toMatchObject({ count: 1, pct: 25, threshold: '7.2' })
  })

  it('envios pendientes en dia de ausencia o no laborable son criticos (solo de hoy en adelante)', () => {
    const dayRows = [
      row('N1', '2027-03-02', { is_unavailable: true, pending_count: 2 }),
      row('N1', '2027-03-06', { is_working_day: false, pending_count: 1 }),
      row('N1', '2027-02-20', { is_working_day: false, pending_count: 5 }), // pasado: no cuenta aqui
    ]
    const f = analyzeCity({ ...base, dayRows }).find((x) => x.code === 'conflicts')!
    expect(f.severity).toBe('critical')
    expect(f.params).toMatchObject({ count: 3, nodes: 'N1' })
  })

  it('nodo sin panelista con envios pendientes', () => {
    const dayRows = [row('N3', '2027-03-02', { panelist_name: null, pending_count: 4 })]
    const f = analyzeCity({ ...base, dayRows }).find((x) => x.code === 'no_panelist')!
    expect(f.params).toMatchObject({ count: 4, nodes: 'N3' })
  })

  it('atrasados: pendientes con fecha anterior a hoy', () => {
    const dayRows = [row('N1', '2027-02-25', { pending_count: 3 })]
    const f = analyzeCity({ ...base, dayRows }).find((x) => x.code === 'overdue')!
    expect(f.severity).toBe('warning')
    expect(f.params).toMatchObject({ count: 3 })
  })

  it('picos diarios solo con politica diaria', () => {
    const dayRows = [
      row('N1', '2027-03-02', { pending_count: 6 }),
      row('N1', '2027-03-03'), row('N1', '2027-03-04'), row('N1', '2027-03-05'),
    ]
    const daily = analyzeCity({ ...base, dayRows, datePolicy: 'daily' }).find((x) => x.code === 'daily_peaks')!
    expect(daily.params).toMatchObject({ count: 1, max: 6, node: 'N1', date: '2027-03-02' })
    expect(codes({ ...base, dayRows, datePolicy: 'weekly' })).not.toContain('daily_peaks')
  })

  it('POBOX: dias laborables sin ningun envio en la ciudad son criticos; fines de semana no cuentan', () => {
    const dayRows = [
      row('N1', '2027-03-02', { shipment_count: 1 }),
      row('N2', '2027-03-02', { shipment_count: 0 }),
      row('N1', '2027-03-03'), row('N2', '2027-03-03'),
      row('N1', '2027-03-06', { is_working_day: false }), row('N2', '2027-03-06', { is_working_day: false }),
    ]
    const f = analyzeCity({ ...base, dayRows, pobox: true }).find((x) => x.code === 'pobox_gap')!
    expect(f.severity).toBe('critical')
    expect(f.params).toMatchObject({ count: 1, dates: '2027-03-03' })
    expect(codes({ ...base, dayRows, pobox: false })).not.toContain('pobox_gap')
  })

  it('POBOX cubierto: pobox_ok', () => {
    const dayRows = [row('N1', '2027-03-02', { shipment_count: 1, pending_count: 1 })]
    expect(codes({ ...base, dayRows, pobox: true })).toContain('pobox_ok')
  })

  it('ordena por gravedad: critical antes que warning, info y ok', () => {
    const dayRows = [row('N1', '2027-02-25', { pending_count: 3 }), row('N3', '2027-03-02', { panelist_name: null, pending_count: 1 })]
    const sev = analyzeCity({ ...base, dayRows }).map((f) => f.severity)
    expect(sev).toEqual([...sev].sort((a, b) => ['critical', 'warning', 'info', 'ok'].indexOf(a) - ['critical', 'warning', 'info', 'ok'].indexOf(b)))
  })
})
