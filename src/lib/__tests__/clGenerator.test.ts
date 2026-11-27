import { describe, it, expect, vi, beforeAll, afterAll } from 'vitest'
import { generateAllocationPlan, type CityDistributionMatrix, type SeasonalDistribution } from '../allocationPlanCalculator'
import { buildClGeneratorNodes, generateClQuotasLikeAllocation, type ClGeneratorPoint } from '../carrierLink/clGenerator'
import type { ClQuota } from '../carrierLink/quotaCalculator'

const MATRIX: CityDistributionMatrix = { AA: 15, AB: 20, AC: 5, BA: 20, BB: 15, BC: 5, CA: 10, CB: 5, CC: 5 }
const NO_SEASON: SeasonalDistribution = { jan: 0, feb: 0, mar: 0, apr: 0, may: 0, jun: 0, jul: 0, aug: 0, sep: 0, oct: 0, nov: 0, dec: 0 }

const CITIES = [
  { id: 'a1', classification: 'A' as const },
  { id: 'a2', classification: 'A' as const },
  { id: 'b1', classification: 'B' as const },
  { id: 'b2', classification: 'B' as const },
  { id: 'c1', classification: 'C' as const },
  { id: 'c2', classification: 'C' as const },
]
const both = (city_id: string): ClGeneratorPoint => ({ city_id, e2e_role: 'both' })
const ALL_BOTH = CITIES.map(c => both(c.id))

const sum = (qs: ClQuota[]) => qs.reduce((s, q) => s + q.samples, 0)
const routeTotals = (qs: ClQuota[]) => {
  const m = new Map<string, number>()
  for (const q of qs) m.set(`${q.origin_city_id}>${q.destination_city_id}`, (m.get(`${q.origin_city_id}>${q.destination_city_id}`) ?? 0) + q.samples)
  return m
}

const base = {
  totalSamples: 1000,
  startDate: '2027-01-04',
  endDate: '2027-06-30',
  cityDistributionMatrix: MATRIX,
  useSeasonalDistribution: false,
  points: ALL_BOTH,
  cities: CITIES,
}

describe('Carrier Link generator = allocation plan generator without panelists', () => {
  beforeAll(() => {
    // generateAllocationPlan logs every matrix cell; keep the output readable.
    vi.spyOn(console, 'log').mockImplementation(() => {})
    vi.spyOn(console, 'warn').mockImplementation(() => {})
  })
  afterAll(() => vi.restoreAllMocks())

  it('buildClGeneratorNodes: one node per city with an active point, origin/destination sets by role', () => {
    const g = buildClGeneratorNodes(
      [
        { city_id: 'a1', e2e_role: 'origin' },
        { city_id: 'a1', e2e_role: 'origin' },
        { city_id: 'b1', e2e_role: 'destination' },
        { city_id: 'c1', e2e_role: 'both' },
        { city_id: 'c2', e2e_role: 'both', is_active: false },
        { city_id: 'a2', e2e_role: 'none' },
        { city_id: 'zz', e2e_role: 'both' }, // not an account city
      ],
      CITIES,
    )
    expect(g.nodes.map(n => n.id).sort()).toEqual(['a1', 'b1', 'c1'])
    expect(g.nodes.every(n => n.city_id === n.id && n.status === 'active')).toBe(true)
    expect(g.cities.map(c => c.id).sort()).toEqual(['a1', 'b1', 'c1'])
    expect(g.cities.find(c => c.id === 'c1')?.classification).toBe('C')
    expect(g.originNodeIds.sort()).toEqual(['a1', 'c1'])
    expect(g.destinationNodeIds.sort()).toEqual(['b1', 'c1'])
  })

  it('same per-route totals as generateAllocationPlan with the same matrix/total', () => {
    const quotas = generateClQuotasLikeAllocation(base)
    const g = buildClGeneratorNodes(ALL_BOTH, CITIES)
    const entries = generateAllocationPlan({
      totalSamples: 1000,
      startDate: new Date(2027, 0, 4),
      endDate: new Date(2027, 5, 30),
      cities: g.cities,
      nodes: g.nodes,
      cityDistributionMatrix: MATRIX,
      useSeasonalDistribution: false,
      maxSamplesPerWeek: 5,
    })
    const expected = new Map<string, number>()
    for (const e of entries) expected.set(`${e.originNodeId}>${e.destinationNodeId}`, (expected.get(`${e.originNodeId}>${e.destinationNodeId}`) ?? 0) + 1)
    expect(routeTotals(quotas)).toEqual(expected)
    expect(sum(quotas)).toBe(entries.length)
  })

  it('sum is exact: every sample of the total is placed when every class has cities', () => {
    const quotas = generateClQuotasLikeAllocation(base)
    expect(sum(quotas)).toBe(1000)
    expect(quotas.every(q => Number.isInteger(q.samples) && q.samples > 0)).toBe(true)
    // one row per (route, week)
    const keys = quotas.map(q => `${q.origin_city_id}|${q.destination_city_id}|${q.iso_year}|${q.iso_week}`)
    expect(new Set(keys).size).toBe(keys.length)
  })

  it('never a route within one city', () => {
    const quotas = generateClQuotasLikeAllocation(base)
    expect(quotas.length).toBeGreaterThan(0)
    expect(quotas.some(q => q.origin_city_id === q.destination_city_id)).toBe(false)
  })

  it('destination-only city never sends; origin-only city never receives', () => {
    const points: ClGeneratorPoint[] = [
      { city_id: 'a1', e2e_role: 'origin' },
      { city_id: 'a2', e2e_role: 'both' },
      { city_id: 'b1', e2e_role: 'destination' },
      { city_id: 'b2', e2e_role: 'both' },
      { city_id: 'c1', e2e_role: 'both' },
      { city_id: 'c2', e2e_role: 'destination' },
    ]
    const quotas = generateClQuotasLikeAllocation({ ...base, points })
    expect(quotas.length).toBeGreaterThan(0)
    expect(quotas.some(q => q.destination_city_id === 'a1')).toBe(false)
    expect(quotas.some(q => q.origin_city_id === 'b1' || q.origin_city_id === 'c2')).toBe(false)
    expect(quotas.some(q => q.origin_city_id === 'a1')).toBe(true)
    expect(quotas.some(q => q.destination_city_id === 'b1')).toBe(true)
  })

  it('seasonal: a 0% month gets no samples', () => {
    const quotas = generateClQuotasLikeAllocation({
      ...base,
      startDate: '2027-01-04',
      endDate: '2027-03-31',
      useSeasonalDistribution: true,
      seasonalDistribution: { ...NO_SEASON, jan: 50, feb: 0, mar: 50 },
    })
    // 2027-02-01 is a Monday: ISO weeks 5..8 of 2027 are all February.
    expect(quotas.filter(q => q.iso_year === 2027 && q.iso_week >= 5 && q.iso_week <= 8)).toEqual([])
    expect(sum(quotas)).toBe(1000)
  })

  it('ISO year boundary: 2026-W53 and 2027-W01', () => {
    const quotas = generateClQuotasLikeAllocation({ ...base, totalSamples: 100, startDate: '2026-12-28', endDate: '2027-01-08' })
    const weeks = new Set(quotas.map(q => `${q.iso_year}-W${q.iso_week}`))
    expect([...weeks].sort()).toEqual(['2026-W53', '2027-W1'])
    expect(sum(quotas)).toBe(100)
  })

  it('working calendar: holidays and working weekdays are respected (whole week off -> no quota)', () => {
    const quotas = generateClQuotasLikeAllocation({
      ...base,
      totalSamples: 100,
      startDate: '2027-03-01',
      endDate: '2027-03-19',
      // week of 2027-03-08 (ISO W10): every working day is a holiday
      nonWorkingDays: ['2027-03-08', '2027-03-09', '2027-03-10', '2027-03-11', '2027-03-12'],
      workingDows: [1, 2, 3, 4, 5],
    })
    expect(quotas.some(q => q.iso_week === 10)).toBe(false)
    expect(sum(quotas)).toBe(100)
  })

  it('deterministic: same input, same quotas', () => {
    expect(generateClQuotasLikeAllocation(base)).toEqual(generateClQuotasLikeAllocation(base))
  })

  it('no origin or no destination city -> no quotas', () => {
    expect(generateClQuotasLikeAllocation({ ...base, points: [{ city_id: 'a1', e2e_role: 'origin' }, { city_id: 'b1', e2e_role: 'origin' }] })).toEqual([])
    expect(generateClQuotasLikeAllocation({ ...base, points: [] })).toEqual([])
  })

  it('scale: 15,000 samples, 30 cities, one year < 2000 ms', () => {
    const cities = Array.from({ length: 30 }, (_, i) => ({ id: `city${String(i).padStart(2, '0')}`, classification: (['A', 'B', 'C'] as const)[i % 3] }))
    const t0 = performance.now()
    const quotas = generateClQuotasLikeAllocation({
      ...base,
      totalSamples: 15000,
      startDate: '2027-01-01',
      endDate: '2027-12-31',
      useSeasonalDistribution: true,
      seasonalDistribution: { jan: 8, feb: 8, mar: 8, apr: 8, may: 8, jun: 8, jul: 8, aug: 8, sep: 9, oct: 9, nov: 9, dec: 9 },
      points: cities.map(c => both(c.id)),
      cities,
    })
    const ms = performance.now() - t0
    expect(sum(quotas)).toBe(15000)
    expect(new Set(quotas.map(q => `${q.origin_city_id}>${q.destination_city_id}`)).size).toBe(870)
    expect(ms).toBeLessThan(2000)
  })
})
