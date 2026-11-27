import { describe, it, expect, vi, afterEach } from 'vitest'
import { generateAllocationPlan, type AllocationPlanParams, type AllocationEntry } from '../allocationPlanCalculator'
import { localDateKey } from '../workingDays'
import type { City, Node } from '../types'

// Golden-output regression: the allocation plan generator must produce exactly the same entries for the
// same inputs and the same random sequence. The fingerprint below was captured BEFORE the optional
// Carrier Link parameters (rng, originNodeIds, destinationNodeIds) were added.

const TS = '2026-01-01T00:00:00Z'
const city = (id: string, classification: 'A' | 'B' | 'C'): City => ({
  id, account_id: 'acc', region_id: 'r', name: `City ${id}`, code: id, classification,
  status: 'active', created_at: TS, updated_at: TS,
})
const node = (id: string, cityId: string): Node => ({
  id, account_id: 'acc', city_id: cityId, auto_id: id, status: 'active', created_at: TS, updated_at: TS,
})

/** Deterministic PRNG (mulberry32). */
function seeded(seed: number): () => number {
  let a = seed >>> 0
  return () => {
    a = (a + 0x6d2b79f5) >>> 0
    let t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

const CITIES = [city('A1c', 'A'), city('A2c', 'A'), city('B1c', 'B'), city('B2c', 'B'), city('B3c', 'B'), city('C1c', 'C')]
const NODES = [
  node('n1', 'A1c'), node('n2', 'A1c'), node('n3', 'A2c'), node('n4', 'B1c'),
  node('n5', 'B2c'), node('n6', 'B2c'), node('n7', 'B3c'), node('n8', 'C1c'),
]

const params = (): AllocationPlanParams => ({
  totalSamples: 137,
  startDate: new Date(2027, 0, 4),
  endDate: new Date(2027, 3, 30),
  cities: CITIES,
  nodes: NODES,
  cityDistributionMatrix: { AA: 15, AB: 20, AC: 5, BA: 20, BB: 15, BC: 5, CA: 10, CB: 5, CC: 5 },
  useSeasonalDistribution: true,
  seasonalDistribution: { jan: 10, feb: 40, mar: 20, apr: 30, may: 0, jun: 0, jul: 0, aug: 0, sep: 0, oct: 0, nov: 0, dec: 0 },
  maxSamplesPerWeek: 5,
  nonWorkingDays: ['2027-02-15', '2027-03-19'],
})

function fingerprint(entries: AllocationEntry[]): string {
  const s = entries
    .map(e => `${e.originNodeId}>${e.destinationNodeId}@${localDateKey(e.fechaProgramada)}#${e.weekNumber}/${e.month}/${e.year}/${e.generationSource}`)
    .join('\n')
  // FNV-1a 32-bit
  let h = 0x811c9dc5
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i)
    h = Math.imul(h, 0x01000193) >>> 0
  }
  return `${entries.length}:${h.toString(16)}`
}

describe('generateAllocationPlan regression (golden output)', () => {
  afterEach(() => vi.restoreAllMocks())

  it('same inputs + same Math.random sequence -> same entries as before the Carrier Link changes', () => {
    vi.spyOn(console, 'log').mockImplementation(() => {})
    vi.spyOn(console, 'warn').mockImplementation(() => {})
    vi.spyOn(Math, 'random').mockImplementation(seeded(42))
    expect(fingerprint(generateAllocationPlan(params()))).toBe('131:f12dc335')
  })

  it('an explicit rng gives the same entries as Math.random with the same sequence', () => {
    vi.spyOn(console, 'log').mockImplementation(() => {})
    vi.spyOn(console, 'warn').mockImplementation(() => {})
    expect(fingerprint(generateAllocationPlan({ ...params(), rng: seeded(42) }))).toBe('131:f12dc335')
  })

  it('origin/destination restrictions that allow every node change nothing', () => {
    vi.spyOn(console, 'log').mockImplementation(() => {})
    vi.spyOn(console, 'warn').mockImplementation(() => {})
    const all = NODES.map(n => n.id)
    expect(fingerprint(generateAllocationPlan({
      ...params(), rng: seeded(42), originNodeIds: all, destinationNodeIds: all,
    }))).toBe('131:f12dc335')
  })
})
