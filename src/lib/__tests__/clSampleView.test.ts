import { describe, it, expect } from 'vitest'
import { filterSamples, transitLabel, planWeekKeys, clampPage } from '../carrierLink/sampleView'

const rows = [
  { id: 1, quota_week: '2026-W45', route_key: 'a>b', possible_misrouting: false },
  { id: 2, quota_week: '2026-W45', route_key: 'a>c', possible_misrouting: true },
  { id: 3, quota_week: '2026-W46', route_key: 'a>b', possible_misrouting: true },
]
const none = { week: null, route: null, misroutedOnly: false }

describe('filterSamples', () => {
  it('sin filtros devuelve todo', () => expect(filterSamples(rows, none)).toHaveLength(3))
  it('misroutedOnly deja solo las marcadas', () =>
    expect(filterSamples(rows, { ...none, misroutedOnly: true }).map((r) => r.id)).toEqual([2, 3]))
  it('semana y ruta combinadas', () =>
    expect(filterSamples(rows, { ...none, week: '2026-W45', route: 'a>b' }).map((r) => r.id)).toEqual([1]))
  it('ruta con destino vacÃ­o = cualquier destino', () =>
    expect(filterSamples(rows, { ...none, route: 'a>' })).toHaveLength(3))
})

describe('transitLabel', () => {
  it('dÃ­as con un decimal y horas enteras', () =>
    expect(transitLabel('2026-11-03T09:12:00Z', '2026-11-06T14:30:00Z')).toEqual({ days: 3.2, hours: 77 }))
})

describe('planWeekKeys', () => {
  it('cruza fin de aÃ±o con aÃ±o ISO correcto', () => {
    const w = planWeekKeys('2026-12-21', '2027-01-10')
    expect(w).toEqual(['2026-W52', '2026-W53', '2027-W01'])
  })
})

describe('clampPage', () => {
  it('deja una página válida', () => expect(clampPage(2, 150, 50)).toBe(2))
  it('fuera de rango pasa a la última', () => expect(clampPage(5, 120, 50)).toBe(2))
  it('sin resultados vuelve a 0', () => expect(clampPage(3, 0, 50)).toBe(0))
  it('total exacto múltiplo de página', () => expect(clampPage(3, 150, 50)).toBe(2))
})
