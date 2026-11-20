import { buildPlanWeeks, distributeSamplesAcrossWeeks } from '../allocationPlanCalculator'

export type ClRoute = { origin_city_id: string; destination_city_id: string; weight?: number }

/** Exact shape expected by the RPC cl_plan_set_quotas. */
export type ClQuota = {
  origin_city_id: string
  destination_city_id: string
  iso_year: number
  iso_week: number
  samples: number
}

type E2eRole = 'origin' | 'destination' | 'both' | 'none'

/** ISO 8601 year and week of a date (local calendar components). */
export function isoWeekOf(d: Date): { iso_year: number; iso_week: number } {
  const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()))
  const dayNum = t.getUTCDay() || 7
  t.setUTCDate(t.getUTCDate() + 4 - dayNum) // Thursday of the ISO week
  const iso_year = t.getUTCFullYear()
  const yearStart = Date.UTC(iso_year, 0, 1)
  const iso_week = Math.ceil(((t.getTime() - yearStart) / 86400000 + 1) / 7)
  return { iso_year, iso_week }
}

/** All origin x destination city pairs (never within one city), sorted by (origin, destination). */
export function buildClRoutes(points: { city_id: string; e2e_role: E2eRole }[]): ClRoute[] {
  const origins = new Set<string>()
  const destinations = new Set<string>()
  for (const p of points) {
    if (p.e2e_role === 'origin' || p.e2e_role === 'both') origins.add(p.city_id)
    if (p.e2e_role === 'destination' || p.e2e_role === 'both') destinations.add(p.city_id)
  }
  const routes: ClRoute[] = []
  for (const o of [...origins].sort()) {
    for (const dest of [...destinations].sort()) {
      if (o !== dest) routes.push({ origin_city_id: o, destination_city_id: dest })
    }
  }
  return routes
}

function parseLocalDate(s: string): Date {
  const [y, m, d] = s.split('-').map(Number)
  return new Date(y, m - 1, d)
}

/** Split `total` by weights using largest remainders; ties go to the route nearest after `start` (cyclic). Also returns how many leftovers were handed out. */
function splitByWeight(total: number, weights: number[], start = 0): { counts: number[]; extras: number } {
  const n = weights.length
  const sum = weights.reduce((a, b) => a + b, 0)
  if (sum <= 0 || total <= 0) return { counts: weights.map(() => 0), extras: 0 }
  const exact = weights.map(w => (total * w) / sum)
  const counts = exact.map(Math.floor)
  let remaining = total - counts.reduce((a, b) => a + b, 0)
  const extras = remaining
  const order = exact
    .map((e, i) => ({ i, frac: e - counts[i] }))
    .sort((a, b) => b.frac - a.frac || ((a.i - start + n) % n) - ((b.i - start + n) % n))
  for (let k = 0; remaining > 0 && order.length > 0; k = (k + 1) % order.length, remaining--) {
    counts[order[k].i]++
  }
  return { counts, extras }
}

/** Spread a plan total over ISO weeks (by working days) and, within each week, over routes by weight. */
export function generateClQuotas(p: {
  totalSamples: number
  startDate: string
  endDate: string
  routes: ClRoute[]
  nonWorkingDays?: string[]
  workingDows?: number[]
}): ClQuota[] {
  if (p.routes.length === 0 || p.totalSamples <= 0) return []
  const cal = {
    workingDows: new Set(p.workingDows ?? [1, 2, 3, 4, 5]),
    nonWorkingDays: new Set(p.nonWorkingDays ?? []),
  }
  const weeks = buildPlanWeeks(parseLocalDate(p.startDate), parseLocalDate(p.endDate), cal)
  if (weeks.length === 0) return []

  const perWeek = distributeSamplesAcrossWeeks(p.totalSamples, weeks, false, undefined, () => 0.5)
  const rawWeights = p.routes.map(r => {
    const w = r.weight ?? 1
    return Number.isNaN(w) ? 0 : Math.max(0, w)
  })
  // All weights <= 0 must not lose the total: fall back to equal weights.
  const weights = rawWeights.some(w => w > 0) ? rawWeights : rawWeights.map(() => 1)
  const quotas: ClQuota[] = []
  let cursor = 0
  weeks.forEach((week, wi) => {
    const { iso_year, iso_week } = isoWeekOf(week.days[0])
    const { counts: perRoute, extras } = splitByWeight(perWeek[wi], weights, cursor)
    cursor = (cursor + extras) % weights.length // leftovers keep rotating across weeks
    p.routes.forEach((r, ri) => {
      if (perRoute[ri] > 0) {
        quotas.push({
          origin_city_id: r.origin_city_id,
          destination_city_id: r.destination_city_id,
          iso_year,
          iso_week,
          samples: perRoute[ri],
        })
      }
    })
  })
  return quotas
}
