import { describe, it, expect } from 'vitest'
import { filterSamples, transitLabel, planWeekKeys } from '../carrierLink/sampleView'

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
  it('ruta con destino vacío = cualquier destino', () =>
    expect(filterSamples(rows, { ...none, route: 'a>' })).toHaveLength(3))
})

describe('transitLabel', () => {
  it('días con un decimal y horas enteras', () =>
    expect(transitLabel('2026-11-03T09:12:00Z', '2026-11-06T14:30:00Z')).toEqual({ days: 3.2, hours: 77 }))
})

describe('planWeekKeys', () => {
  it('cruza fin de año con año ISO correcto', () => {
    const w = planWeekKeys('2026-12-21', '2027-01-10')
    expect(w).toEqual(['2026-W52', '2026-W53', '2027-W01'])
  })
})
