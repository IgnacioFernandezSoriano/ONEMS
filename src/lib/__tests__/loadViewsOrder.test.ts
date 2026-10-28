import { describe, expect, it } from 'vitest'
import { buildDayView, compareNatural, dayTotals, isPoboxGap, orderWeekNumbers } from '../loadViews'

describe('orden natural de nodos', () => {
  it('KE 2 va antes que KE 10 (no orden alfabetico)', () => {
    const nodes = ['SR-BMT-010', 'SR-BMT-002', 'KE 10', 'KE 2', 'KE 1']
    expect([...nodes].sort(compareNatural)).toEqual(['KE 1', 'KE 2', 'KE 10', 'SR-BMT-002', 'SR-BMT-010'])
  })
})

describe('orden de semanas', () => {
  it('numerico: la 9 antes que la 10 (Array.sort() sin comparador las pone al reves)', () => {
    const rows = [10, 9, 44, 2].map((week_number) => ({ week_number }))
    expect(orderWeekNumbers(rows)).toEqual([2, 9, 10, 44])
  })

  it('con fechas: al cruzar el ano la semana 1 va despues de la 52', () => {
    const rows = [
      { week_number: 1, week_start_date: '2027-01-04' },
      { week_number: 52, week_start_date: '2026-12-28' },
      { week_number: 51, week_start_date: '2026-12-21' },
    ]
    expect(orderWeekNumbers(rows)).toEqual([51, 52, 1])
  })

  it('no repite semanas aunque haya una fila por nodo', () => {
    const rows = [44, 44, 45, 45].map((week_number) => ({ week_number }))
    expect(orderWeekNumbers(rows)).toEqual([44, 45])
  })
})

describe('hueco POBOX', () => {
  it('solo es hueco con POBOX, dia laborable y total cero', () => {
    expect(isPoboxGap(0, true, true)).toBe(true)
    expect(isPoboxGap(0, true, false)).toBe(false) // sin POBOX un cero es normal
    expect(isPoboxGap(0, false, true)).toBe(false) // fin de semana o festivo: no hace falta envio
    expect(isPoboxGap(1, true, true)).toBe(false)
  })

  it('dayTotals suma los nodos de la ciudad por dia', () => {
    const mk = (node_code: string, day: string, shipment_count: number) =>
      ({ city_id: 'c', city_name: 'C', node_id: node_code, node_code, panelist_name: null, day, shipment_count,
         pending_count: shipment_count, is_working_day: true, is_unavailable: false })
    const view = buildDayView([mk('N1', '2027-03-01', 2), mk('N2', '2027-03-01', 1), mk('N1', '2027-03-02', 0), mk('N2', '2027-03-02', 0)])
    const totals = dayTotals(view)
    expect(totals.get('2027-03-01')).toBe(3)
    expect(totals.get('2027-03-02')).toBe(0)
  })
})
