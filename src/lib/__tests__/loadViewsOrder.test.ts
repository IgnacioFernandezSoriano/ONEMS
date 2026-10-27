import { describe, expect, it } from 'vitest'
import { compareNatural, orderWeekNumbers } from '../loadViews'

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
