import { describe, it, expect } from 'vitest'
import { isoWeekOf, buildClRoutes, generateClQuotas, type ClRoute } from '../carrierLink/quotaCalculator'

const sum = (q: { samples: number }[]) => q.reduce((a, x) => a + x.samples, 0)
const routes3: ClRoute[] = [
  { origin_city_id: 'A', destination_city_id: 'B' },
  { origin_city_id: 'A', destination_city_id: 'C' },
  { origin_city_id: 'B', destination_city_id: 'C' },
]

describe('isoWeekOf', () => {
  it('handles year boundaries', () => {
    expect(isoWeekOf(new Date('2026-12-31T12:00:00'))).toEqual({ iso_year: 2026, iso_week: 53 })
    expect(isoWeekOf(new Date('2027-01-04T12:00:00'))).toEqual({ iso_year: 2027, iso_week: 1 })
  })
})

describe('buildClRoutes', () => {
  it('builds origin x destination pairs, never within a city', () => {
    const r = buildClRoutes([
      { city_id: 'NY', e2e_role: 'origin' },
      { city_id: 'BAL', e2e_role: 'both' },
      { city_id: 'PHL', e2e_role: 'destination' },
      { city_id: 'X', e2e_role: 'none' },
    ])
    expect(r.map(x => `${x.origin_city_id}>${x.destination_city_id}`)).toEqual(['BAL>PHL', 'NY>BAL', 'NY>PHL'])
    expect(r.some(x => x.origin_city_id === x.destination_city_id)).toBe(false)
  })
})

describe('generateClQuotas', () => {
  it('splits evenly across 2 weeks and 3 routes', () => {
    const q = generateClQuotas({ totalSamples: 18, startDate: '2026-11-02', endDate: '2026-11-15', routes: routes3 })
    expect(sum(q)).toBe(18)
    expect([...new Set(q.map(x => `${x.iso_year}-W${x.iso_week}`))]).toEqual(['2026-W45', '2026-W46'])
    expect(q.every(x => x.samples === 3)).toBe(true)
  })
  it('small total: exact sum, none negative', () => {
    const q = generateClQuotas({ totalSamples: 5, startDate: '2026-11-02', endDate: '2026-11-27', routes: routes3 })
    expect(sum(q)).toBe(5)
    expect(q.every(x => x.samples > 0)).toBe(true)
  })
  it('year boundary has W53 and W01 once each', () => {
    const q = generateClQuotas({ totalSamples: 60, startDate: '2026-12-21', endDate: '2027-01-10', routes: routes3 })
    const weeks = q.filter(x => x.origin_city_id === 'A' && x.destination_city_id === 'B').map(x => `${x.iso_year}-W${x.iso_week}`)
    expect(weeks.filter(w => w === '2026-W53')).toHaveLength(1)
    expect(weeks.filter(w => w === '2027-W1')).toHaveLength(1)
  })
  it('is deterministic', () => {
    const p = { totalSamples: 7, startDate: '2026-11-02', endDate: '2026-12-13', routes: routes3 }
    expect(generateClQuotas(p)).toEqual(generateClQuotas(p))
  })
  it('weight 2 gets double (+-1)', () => {
    const q = generateClQuotas({
      totalSamples: 40, startDate: '2026-11-02', endDate: '2026-11-08',
      routes: [{ ...routes3[0], weight: 2 }, routes3[1]],
    })
    const a = q.find(x => x.destination_city_id === 'B')!.samples
    const b = q.find(x => x.destination_city_id === 'C')!.samples
    expect(sum(q)).toBe(40)
    expect(Math.abs(a - 2 * b)).toBeLessThanOrEqual(1)
  })
  it('rotates leftovers so every route gets samples over the plan', () => {
    const q = generateClQuotas({ totalSamples: 5, startDate: '2026-11-02', endDate: '2026-11-29', routes: routes3 })
    expect(sum(q)).toBe(5)
    for (const r of routes3) {
      expect(q.some(x => x.origin_city_id === r.origin_city_id && x.destination_city_id === r.destination_city_id)).toBe(true)
    }
  })
  it('negative weight gets 0 and the sum stays exact', () => {
    const q = generateClQuotas({
      totalSamples: 10, startDate: '2026-11-02', endDate: '2026-11-08',
      routes: [{ ...routes3[0], weight: -1 }, routes3[1], routes3[2]],
    })
    expect(sum(q)).toBe(10)
    expect(q.some(x => x.destination_city_id === 'B' && x.origin_city_id === 'A')).toBe(false)
  })
  it('all weights <= 0 falls back to equal weights without losing the total', () => {
    const q = generateClQuotas({
      totalSamples: 18, startDate: '2026-11-02', endDate: '2026-11-15',
      routes: routes3.map(r => ({ ...r, weight: 0 })),
    })
    expect(sum(q)).toBe(18)
    expect(q.every(x => x.samples === 3)).toBe(true)
  })
  it('no routes -> []', () => {
    expect(generateClQuotas({ totalSamples: 10, startDate: '2026-11-02', endDate: '2026-11-15', routes: [] })).toEqual([])
  })
})

describe('generateClQuotas at real scale', () => {
  it('15000 samples, 870 routes, one year', () => {
    const cities = Array.from({ length: 30 }, (_, i) => `C${String(i).padStart(2, '0')}`)
    const routes = buildClRoutes(cities.map(c => ({ city_id: c, e2e_role: 'both' as const })))
    expect(routes).toHaveLength(870)
    const t0 = performance.now()
    const q = generateClQuotas({ totalSamples: 15000, startDate: '2027-01-01', endDate: '2027-12-31', routes })
    const ms = performance.now() - t0
    expect(ms).toBeLessThan(1000)
    expect(sum(q)).toBe(15000)
    expect(q.every(x => x.samples > 0)).toBe(true)
    expect(q.length).toBeLessThan(45300)
    const covered = new Set(q.map(x => `${x.origin_city_id}>${x.destination_city_id}`))
    expect(covered.size).toBe(870)
  })
})
