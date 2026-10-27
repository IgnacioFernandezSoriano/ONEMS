import { describe, it, expect, vi, beforeAll, afterAll } from 'vitest'
import {
  generateAllocationPlan,
  summarizeGeneration,
  autoFillMatrix,
  type AllocationPlanParams,
  type AllocationEntry,
} from '../allocationPlanCalculator'
import { localDateKey } from '../workingDays'
import type { City, Node } from '../types'

const TS = '2026-01-01T00:00:00Z'

const city = (id: string, classification: 'A' | 'B' | 'C'): City => ({
  id,
  account_id: 'acc',
  region_id: 'r',
  name: `City ${id}`,
  code: id,
  classification,
  status: 'active',
  created_at: TS,
  updated_at: TS,
})

const node = (id: string, cityId: string): Node => ({
  id,
  account_id: 'acc',
  city_id: cityId,
  auto_id: id,
  status: 'active',
  created_at: TS,
  updated_at: TS,
})

const CITIES = [city('A', 'A'), city('B', 'B')]
const NODES = [node('A1', 'A'), node('A2', 'A'), node('B1', 'B'), node('B2', 'B')]
const A_NODES = new Set(['A1', 'A2'])

const base = (over: Partial<AllocationPlanParams> = {}): AllocationPlanParams => ({
  totalSamples: 20,
  startDate: new Date(2027, 2, 1),
  endDate: new Date(2027, 2, 12),
  cities: CITIES,
  nodes: NODES,
  // AB = 100: the rest of the matrix is 0 (autoFillMatrix leaves it untouched once the total is 100).
  cityDistributionMatrix: autoFillMatrix({ AB: 100, AA: 0, AC: 0, BA: 0, BB: 0, BC: 0, CA: 0, CB: 0, CC: 0 }),
  useSeasonalDistribution: false,
  maxSamplesPerWeek: 5,
  ...over,
})

const keyOf = (e: AllocationEntry) => localDateKey(e.fechaProgramada)
const days = (from: number, to: number) =>
  Array.from({ length: to - from + 1 }, (_, i) => localDateKey(new Date(2027, 2, from + i)))
const WEEK1 = days(1, 5)
const WEEK2 = days(8, 12)

describe('generateAllocationPlan', () => {
  // generateCityRoutes logs a lot; keep the test output readable.
  beforeAll(() => {
    vi.spyOn(console, 'log').mockImplementation(() => {})
    vi.spyOn(console, 'warn').mockImplementation(() => {})
  })
  afterAll(() => {
    vi.restoreAllMocks()
  })

  it('(g) sin parametros nuevos: 20 envios, todos de lunes a viernes, origen plan', () => {
    const entries = generateAllocationPlan(base())
    expect(entries).toHaveLength(20)
    for (const e of entries) {
      const dow = e.fechaProgramada.getDay()
      expect(dow).toBeGreaterThanOrEqual(1)
      expect(dow).toBeLessThanOrEqual(5)
      expect(e.generationSource).toBe('plan')
    }
    expect(summarizeGeneration(entries)).toEqual({ total: 20, pobox: 0 })
  })

  it('(a) todas las fechas L-V y ninguna en un dia no laborable', () => {
    const entries = generateAllocationPlan(base({ nonWorkingDays: ['2027-03-08'] }))
    expect(entries).toHaveLength(20)
    for (const e of entries) {
      const dow = e.fechaProgramada.getDay()
      expect(dow >= 1 && dow <= 5).toBe(true)
      expect(keyOf(e)).not.toBe('2027-03-08')
    }
  })

  it('(b) con semana domingo-jueves no hay viernes ni sabados', () => {
    const entries = generateAllocationPlan(base({ workingDows: new Set([0, 1, 2, 3, 4]) }))
    expect(entries).toHaveLength(20)
    for (const e of entries) {
      const dow = e.fechaProgramada.getDay()
      expect(dow).not.toBe(5)
      expect(dow).not.toBe(6)
    }
  })

  it("(c) politica 'weekly': solo dos fechas, 2027-03-01 y 2027-03-09 (el 8 no laborable)", () => {
    const entries = generateAllocationPlan(base({ datePolicy: 'weekly', nonWorkingDays: ['2027-03-08'] }))
    expect(entries).toHaveLength(20)
    const distinct = [...new Set(entries.map(keyOf))].sort()
    expect(distinct).toEqual(['2027-03-01', '2027-03-09'])
  })

  it("(d) politica 'daily': por nodo origen y semana, max - min <= 1 envios por dia", () => {
    const entries = generateAllocationPlan(base({ datePolicy: 'daily' }))
    expect(entries).toHaveLength(20)
    for (const nodeId of ['A1', 'A2']) {
      for (const week of [WEEK1, WEEK2]) {
        const counts = week.map(d => entries.filter(e => e.originNodeId === nodeId && keyOf(e) === d).length)
        expect(Math.max(...counts) - Math.min(...counts)).toBeLessThanOrEqual(1)
      }
    }
  })

  it('(e) nodo A1 ausente toda la semana 1: ningun envio de A1 en la semana 1', () => {
    const entries = generateAllocationPlan(base({ unavailabilityByNode: new Map([['A1', new Set(WEEK1)]]) }))
    expect(entries).toHaveLength(20)
    const a1Week1 = entries.filter(e => e.originNodeId === 'A1' && WEEK1.includes(keyOf(e)))
    expect(a1Week1).toHaveLength(0)
  })

  it('(f) POBOX con 2 muestras: cada dia laborable tiene envio de la ciudad A', () => {
    const warnings: Array<{ code: string; count: number }> = []
    const entries = generateAllocationPlan(base({ pobox: true, totalSamples: 2, onWarning: w => warnings.push(w) }))
    for (const d of [...WEEK1, ...WEEK2]) {
      expect(entries.some(e => A_NODES.has(e.originNodeId) && keyOf(e) === d)).toBe(true)
    }
    expect(summarizeGeneration(entries).pobox).toBe(entries.length - 2)
    expect(entries.filter(e => e.generationSource === 'pobox').every(e => e.originNodeId !== e.destinationNodeId)).toBe(true)
    expect(warnings).toEqual([])
  })

  it('(h) nodo destino B1 ausente un dia: ningun envio a B1 ese dia', () => {
    const entries = generateAllocationPlan(base({ unavailabilityByNode: new Map([['B1', new Set(['2027-03-03'])]]) }))
    expect(entries).toHaveLength(20)
    expect(entries.filter(e => e.destinationNodeId === 'B1' && keyOf(e) === '2027-03-03')).toHaveLength(0)
  })

  it('sin ningun nodo origen disponible en la semana: las muestras se descartan y se avisa', () => {
    const warnings: Array<{ code: string; count: number }> = []
    const entries = generateAllocationPlan(base({
      unavailabilityByNode: new Map([['A1', new Set(WEEK1)], ['A2', new Set(WEEK1)]]),
      onWarning: w => warnings.push(w),
    }))
    expect(entries).toHaveLength(10)
    expect(entries.every(e => WEEK2.includes(keyOf(e)))).toBe(true)
    expect(warnings).toEqual([{ code: 'dropped_sample', count: 10 }])
  })
})
