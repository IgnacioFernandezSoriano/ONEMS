import {
  generateAllocationPlan,
  type CityDistributionMatrix,
  type SeasonalDistribution,
} from '../allocationPlanCalculator'
import type { City, Node } from '../types'
import { isoWeekOf, type ClQuota } from './quotaCalculator'

/**
 * Carrier Link quota generation with the SAME engine as the E2E allocation plan generator
 * (generateAllocationPlan: total, period, A/B/C city matrix, seasonal distribution, working days and
 * holidays). The only difference: there are no panelists. Each city with an active carrier reading point
 * becomes one synthetic node (node id = city id); its points' roles decide whether it may send and/or
 * receive. The per-shipment entries are then counted per route x ISO week.
 */

export type ClGeneratorPoint = { city_id: string; e2e_role: string; is_active?: boolean }
export type ClGeneratorCity = { id: string; classification?: string | null; name?: string }

const TS = '1970-01-01T00:00:00Z'

/** Synthetic nodes/cities for generateAllocationPlan, plus who may send (origin|both) and receive (destination|both). */
export function buildClGeneratorNodes(
  points: ClGeneratorPoint[],
  cities: ClGeneratorCity[],
): { nodes: Node[]; cities: City[]; originNodeIds: string[]; destinationNodeIds: string[] } {
  const known = new Map(cities.map(c => [c.id, c]))
  const origins = new Set<string>()
  const destinations = new Set<string>()
  for (const p of points) {
    if (p.is_active === false || !known.has(p.city_id)) continue
    if (p.e2e_role === 'origin' || p.e2e_role === 'both') origins.add(p.city_id)
    if (p.e2e_role === 'destination' || p.e2e_role === 'both') destinations.add(p.city_id)
  }
  const ids = [...new Set([...origins, ...destinations])].sort()
  const nodes: Node[] = ids.map(id => ({
    id, account_id: '', city_id: id, auto_id: id, status: 'active', created_at: TS, updated_at: TS,
  }))
  const outCities: City[] = ids.map(id => {
    const c = known.get(id)!
    const cls = c.classification
    return {
      id,
      account_id: '',
      region_id: '',
      // The name matters only for the allocation engine's own fallback when a city has no classification.
      name: c.name ?? id,
      code: id,
      classification: cls === 'A' || cls === 'B' || cls === 'C' ? cls : undefined,
      status: 'active',
      created_at: TS,
      updated_at: TS,
    }
  })
  return { nodes, cities: outCities, originNodeIds: [...origins].sort(), destinationNodeIds: [...destinations].sort() }
}

/** Deterministic PRNG (mulberry32): same plan input, same quotas. */
function seededRng(seed: number): () => number {
  let a = seed >>> 0
  return () => {
    a = (a + 0x6d2b79f5) >>> 0
    let t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

function toLocalDate(d: Date | string): Date {
  if (d instanceof Date) return new Date(d.getFullYear(), d.getMonth(), d.getDate())
  const [y, m, day] = d.split('-').map(Number)
  return new Date(y, m - 1, day)
}

/** Quotas route x ISO week (samples > 0 only), generated exactly like an E2E allocation plan. */
export function generateClQuotasLikeAllocation(params: {
  totalSamples: number
  /** yyyy-MM-dd or a Date (local calendar day). */
  startDate: Date | string
  endDate: Date | string
  cityDistributionMatrix: CityDistributionMatrix
  useSeasonalDistribution: boolean
  seasonalDistribution?: SeasonalDistribution
  /** Account non-working days (yyyy-MM-dd). */
  nonWorkingDays?: string[]
  /** Account working weekdays (0 = Sunday). Default Monday to Friday. */
  workingDows?: number[] | Set<number>
  points: ClGeneratorPoint[]
  cities: ClGeneratorCity[]
}): ClQuota[] {
  if (params.totalSamples <= 0) return []
  const g = buildClGeneratorNodes(params.points, params.cities)
  if (g.originNodeIds.length === 0 || g.destinationNodeIds.length === 0) return []

  const entries = generateAllocationPlan({
    totalSamples: params.totalSamples,
    startDate: toLocalDate(params.startDate),
    endDate: toLocalDate(params.endDate),
    cities: g.cities,
    nodes: g.nodes,
    cityDistributionMatrix: params.cityDistributionMatrix,
    useSeasonalDistribution: params.useSeasonalDistribution,
    seasonalDistribution: params.seasonalDistribution,
    maxSamplesPerWeek: 5,
    nonWorkingDays: params.nonWorkingDays,
    workingDows: params.workingDows ? new Set(params.workingDows) : undefined,
    originNodeIds: g.originNodeIds,
    destinationNodeIds: g.destinationNodeIds,
    rng: seededRng(1),
  })

  // Node id = city id, so each entry's nodes are its cities.
  const byKey = new Map<string, ClQuota>()
  for (const e of entries) {
    const { iso_year, iso_week } = isoWeekOf(e.fechaProgramada)
    const key = `${e.originNodeId}|${e.destinationNodeId}|${iso_year}|${iso_week}`
    const q = byKey.get(key)
    if (q) q.samples++
    else byKey.set(key, { origin_city_id: e.originNodeId, destination_city_id: e.destinationNodeId, iso_year, iso_week, samples: 1 })
  }
  return [...byKey.values()].sort((a, b) =>
    a.iso_year - b.iso_year || a.iso_week - b.iso_week ||
    a.origin_city_id.localeCompare(b.origin_city_id) || a.destination_city_id.localeCompare(b.destination_city_id))
}
