import type { City, Node } from './types'
import { localDateKey, isWorkingDay, firstWorkingDayOfWeek, type DatePolicy, type WorkingCalendar } from './workingDays'

export interface CityDistributionMatrix {
  AA: number // A to A
  AB: number // A to B
  AC: number // A to C
  BA: number // B to A
  BB: number // B to B
  BC: number // B to C
  CA: number // C to A
  CB: number // C to B
  CC: number // C to C
}

export interface SeasonalDistribution {
  jan: number
  feb: number
  mar: number
  apr: number
  may: number
  jun: number
  jul: number
  aug: number
  sep: number
  oct: number
  nov: number
  dec: number
}

export interface AllocationPlanParams {
  totalSamples: number
  startDate: Date
  endDate: Date
  cities: City[]
  nodes: Node[]
  cityDistributionMatrix: CityDistributionMatrix
  useSeasonalDistribution: boolean
  seasonalDistribution?: SeasonalDistribution
  /** Not applied yet: the form sends a fixed 5 and its meaning (per route, node or panelist) is undecided. */
  maxSamplesPerWeek: number
  /** Account non-working days (yyyy-MM-dd). Shipments are never scheduled on them. */
  nonWorkingDays?: string[]
  /** Nodes with an active panelist. When given, nodes outside this list get no shipments. */
  eligibleNodeIds?: string[]
  /** Account working weekdays (getDay() convention, 0 = Sunday). Default Monday to Friday. */
  workingDows?: Set<number>
  /** 'daily' (default): each shipment gets its own day; 'weekly': every shipment of a week gets the week's first working day. */
  datePolicy?: DatePolicy
  /** Every city must send at least one shipment per working day (forces 'daily'). Default false. */
  pobox?: boolean
  /** Days (yyyy-MM-dd) on which a node's panelist is absent: no shipment is sent from or to it on those days. */
  unavailabilityByNode?: Map<string, Set<string>>
  /** Called once per kind of problem: 'dropped_sample' (no valid day/node) and 'pobox_uncovered' (POBOX day left empty). */
  onWarning?: (w: { code: string; count: number }) => void
}

export interface AllocationEntry {
  originNodeId: string
  destinationNodeId: string
  fechaProgramada: Date
  weekNumber: number
  month: number
  year: number
  /** 'plan' = drawn from the plan's samples; 'pobox' = added so the origin city ships every working day. */
  generationSource: 'plan' | 'pobox'
}

/** How many entries were generated, and how many of them were added by POBOX. */
export function summarizeGeneration(entries: AllocationEntry[]): { total: number; pobox: number } {
  return { total: entries.length, pobox: entries.filter(e => e.generationSource === 'pobox').length }
}

interface CityPairRoute {
  originCity: City
  destCity: City
  samples: number
}

/**
 * Auto-fill missing percentages to reach 100%
 */
export function autoFillMatrix(matrix: Partial<CityDistributionMatrix>): CityDistributionMatrix {
  const keys: (keyof CityDistributionMatrix)[] = [
    'AA', 'AB', 'AC', 'BA', 'BB', 'BC', 'CA', 'CB', 'CC',
  ]
  let total = 0
  const emptyKeys: (keyof CityDistributionMatrix)[] = []

  keys.forEach((key) => {
    const value = matrix[key]
    if (value !== undefined && value !== null && value !== 0) {
      total += value
    } else {
      emptyKeys.push(key)
    }
  })

  if (total >= 100) return matrix as CityDistributionMatrix

  const remaining = 100 - total
  const emptyCount = emptyKeys.length
  
  if (emptyCount === 0) return matrix as CityDistributionMatrix

  // Distribute remaining percentage as integers
  const baseValue = Math.floor(remaining / emptyCount)
  const remainder = remaining - (baseValue * emptyCount)

  const filled: CityDistributionMatrix = { ...matrix } as CityDistributionMatrix
  
  // Fill empty cells with base value
  emptyKeys.forEach((key, index) => {
    // Add 1 to first 'remainder' cells to reach exactly 100%
    filled[key] = baseValue + (index < remainder ? 1 : 0)
  })

  return filled
}

/**
 * Auto-fill missing seasonal percentages to reach 100%
 */
export function autoFillSeasonal(seasonal: Partial<SeasonalDistribution>): SeasonalDistribution {
  const months: (keyof SeasonalDistribution)[] = [
    'jan', 'feb', 'mar', 'apr', 'may', 'jun',
    'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
  ]
  let total = 0
  const emptyMonths: (keyof SeasonalDistribution)[] = []

  months.forEach((month) => {
    const value = seasonal[month]
    if (value !== undefined && value !== null && value !== 0) {
      total += value
    } else {
      emptyMonths.push(month)
    }
  })

  if (total >= 100) return seasonal as SeasonalDistribution

  const remaining = 100 - total
  const emptyCount = emptyMonths.length
  
  if (emptyCount === 0) return seasonal as SeasonalDistribution

  // Distribute remaining percentage as integers
  const baseValue = Math.floor(remaining / emptyCount)
  const remainder = remaining - (baseValue * emptyCount)

  const filled: SeasonalDistribution = { ...seasonal } as SeasonalDistribution
  
  // Fill empty cells with base value
  emptyMonths.forEach((month, index) => {
    // Add 1 to first 'remainder' cells to reach exactly 100%
    filled[month] = baseValue + (index < remainder ? 1 : 0)
  })

  return filled
}

/**
 * ALGORITMO DE GENERACIÓN CON DISTRIBUCIÓN BIDIRECCIONAL
 */
export function generateAllocationPlan(params: AllocationPlanParams): AllocationEntry[] {
  const {
    totalSamples,
    startDate,
    endDate,
    cities,
    nodes,
    cityDistributionMatrix,
    useSeasonalDistribution,
    seasonalDistribution,
    nonWorkingDays,
    eligibleNodeIds,
    workingDows,
    datePolicy,
    pobox,
    unavailabilityByNode,
    onWarning,
  } = params

  // Only nodes with an active panelist can send or receive (a node without anyone produces impossible shipments).
  const eligible = eligibleNodeIds ? new Set(eligibleNodeIds) : null
  const usableNodes = eligible ? nodes.filter(n => eligible.has(n.id)) : nodes

  const cal: WorkingCalendar = {
    workingDows: workingDows ?? new Set([1, 2, 3, 4, 5]),
    nonWorkingDays: new Set(nonWorkingDays || []),
  }

  // Working days of the period (account working weekday, inside [startDate, endDate], not an account
  // non-working day), grouped by ISO week. Every shipment date is drawn from these days only.
  const weeks = buildPlanWeeks(startDate, endDate, cal)
  if (weeks.length === 0) return []

  const ctx: GenerationContext = {
    // POBOX needs a shipment every day, so it forces the daily policy.
    datePolicy: pobox ? 'daily' : (datePolicy ?? 'daily'),
    cal,
    unavailability: unavailabilityByNode ?? new Map(),
    originDayLoad: new Map(),
    destDayLoad: new Map(),
    cityDayLoad: new Map(),
    cursor: new Map(),
    sendWeek: new Map(),
    recvWeek: new Map(),
    sendPeriod: new Map(),
    recvPeriod: new Map(),
    pairLoad: new Map(),
    dropped: 0,
  }

  const entries: AllocationEntry[] = []

  // PASO 1: Aplicar matriz A-B-C para obtener rutas ciudad-ciudad
  const cityRoutes = generateCityRoutes(totalSamples, cities, usableNodes, cityDistributionMatrix)

  // PASO 2: Para cada ruta ciudad-ciudad, distribuir temporalmente y por nodos
  for (const route of cityRoutes) {
    entries.push(...generateEntriesForRoute(route, weeks, usableNodes, useSeasonalDistribution, seasonalDistribution, ctx))
  }

  const warn = (code: string, count: number) => {
    if (count <= 0) return
    console.warn(`allocationPlanCalculator: ${code} x${count}`)
    onWarning?.({ code, count })
  }
  warn('dropped_sample', ctx.dropped)

  // PASO 3: POBOX, sobre los envíos recién generados (antes de guardar).
  if (pobox) {
    warn('pobox_uncovered', applyPobox(entries, weeks, cities, usableNodes, ctx.unavailability))
  }

  return entries
}

/** Shared state of one generation run: the day loads let routes of the same nodes/city avoid piling up. */
interface GenerationContext {
  datePolicy: DatePolicy
  cal: WorkingCalendar
  unavailability: Map<string, Set<string>>
  /** `${nodeId}|${yyyy-MM-dd}` -> shipments sent by the node that day */
  originDayLoad: Map<string, number>
  /** `${nodeId}|${yyyy-MM-dd}` -> shipments received by the node that day */
  destDayLoad: Map<string, number>
  /** `${cityId}|${yyyy-MM-dd}` -> shipments sent from the city that day */
  cityDayLoad: Map<string, number>
  /** Round-robin start position per origin node (index into a week's days). */
  cursor: Map<string, number>
  /** `${nodeId}|${weekIdx}` -> shipments sent / received by the node that week (all routes) */
  sendWeek: Map<string, number>
  recvWeek: Map<string, number>
  /** nodeId -> shipments sent / received by the node in the whole plan so far (all routes) */
  sendPeriod: Map<string, number>
  recvPeriod: Map<string, number>
  /** `${originId}|${destId}` -> shipments between that pair of nodes */
  pairLoad: Map<string, number>
  /** Samples that found no valid day/node pair. */
  dropped: number
}

function isBlocked(unavailability: Map<string, Set<string>>, nodeId: string, key: string): boolean {
  return unavailability.get(nodeId)?.has(key) ?? false
}

function bump(map: Map<string, number>, key: string, by = 1): void {
  map.set(key, (map.get(key) ?? 0) + by)
}

function makeEntry(originNodeId: string, destinationNodeId: string, date: Date, generationSource: 'plan' | 'pobox'): AllocationEntry {
  return {
    originNodeId,
    destinationNodeId,
    fechaProgramada: date,
    weekNumber: getWeekNumber(date),
    month: date.getMonth() + 1,
    year: date.getFullYear(),
    generationSource,
  }
}

/**
 * PASO 1: Generar rutas ciudad-ciudad según matriz A-B-C
 */
function generateCityRoutes(
  totalSamples: number,
  cities: City[],
  nodes: Node[],
  matrix: CityDistributionMatrix
): CityPairRoute[] {
  const routes: CityPairRoute[] = []

  // Agrupar nodos por ciudad
  const nodesByCity = new Map<string, Node[]>()
  nodes.filter(n => n.status === 'active').forEach((node) => {
    if (!nodesByCity.has(node.city_id)) {
      nodesByCity.set(node.city_id, [])
    }
    nodesByCity.get(node.city_id)!.push(node)
  })

  // Agrupar ciudades por clasificación
  const citiesByClass = new Map<string, City[]>()
  console.log('DEBUG: All cities:', cities.map(c => ({ name: c.name, classification: c.classification, status: c.status })))
  
  // Workaround: Hardcode classification if not present
  const cityClassificationMap: Record<string, 'A' | 'B' | 'C'> = {
    'Barcelona': 'A',
    'Madrid': 'A',
  }
  
  cities.filter(c => c.status === 'active' && nodesByCity.has(c.id)).forEach((city) => {
    const classification = city.classification || cityClassificationMap[city.name] || 'B'
    console.log(`DEBUG: City ${city.name} has classification: ${classification} (original: ${city.classification})`)
    if (!citiesByClass.has(classification)) {
      citiesByClass.set(classification, [])
    }
    citiesByClass.get(classification)!.push(city)
  })

  console.log('Cities by classification:', {
    A: citiesByClass.get('A')?.map(c => c.name) || [],
    B: citiesByClass.get('B')?.map(c => c.name) || [],
    C: citiesByClass.get('C')?.map(c => c.name) || [],
  })

  // Aplicar matriz para cada combinación de clasificaciones
  const matrixRoutes: Array<{
    originClass: 'A' | 'B' | 'C'
    destClass: 'A' | 'B' | 'C'
    matrixKey: keyof CityDistributionMatrix
  }> = [
    { originClass: 'A', destClass: 'A', matrixKey: 'AA' },
    { originClass: 'A', destClass: 'B', matrixKey: 'AB' },
    { originClass: 'A', destClass: 'C', matrixKey: 'AC' },
    { originClass: 'B', destClass: 'A', matrixKey: 'BA' },
    { originClass: 'B', destClass: 'B', matrixKey: 'BB' },
    { originClass: 'B', destClass: 'C', matrixKey: 'BC' },
    { originClass: 'C', destClass: 'A', matrixKey: 'CA' },
    { originClass: 'C', destClass: 'B', matrixKey: 'CB' },
    { originClass: 'C', destClass: 'C', matrixKey: 'CC' },
  ]

  for (const matrixRoute of matrixRoutes) {
    const percentage = matrix[matrixRoute.matrixKey]
    if (percentage === 0) continue

    const totalForThisRoute = Math.round(totalSamples * (percentage / 100))
    if (totalForThisRoute === 0) continue

    const originCities = citiesByClass.get(matrixRoute.originClass) || []
    const destCities = citiesByClass.get(matrixRoute.destClass) || []

    if (originCities.length === 0 || destCities.length === 0) {
      console.warn(`Skipping route ${matrixRoute.originClass}→${matrixRoute.destClass}: ` +
        `originCities=${originCities.length}, destCities=${destCities.length}`)
      continue
    }

    console.log(`Processing route ${matrixRoute.originClass}→${matrixRoute.destClass}: ` +
      `${totalForThisRoute} samples (${percentage}%)`)

    // Crear pares de ciudades (excluyendo misma ciudad)
    const cityPairs: Array<{ origin: City; dest: City }> = []
    for (const originCity of originCities) {
      for (const destCity of destCities) {
        if (originCity.id !== destCity.id) {
          // Cualquier ciudad puede enviar a cualquier otra ciudad diferente
          cityPairs.push({ origin: originCity, dest: destCity })
        }
      }
    }

    if (cityPairs.length === 0) {
      console.warn(`No valid city pairs for ${matrixRoute.originClass}→${matrixRoute.destClass}: ` +
        `originCities=${originCities.map(c => c.name).join(',')}, ` +
        `destCities=${destCities.map(c => c.name).join(',')}`)
      continue
    }

    console.log(`Found ${cityPairs.length} city pairs for ${matrixRoute.originClass}→${matrixRoute.destClass}`)

    // Distribuir muestras equitativamente entre pares de ciudades
    const samplesPerPair = Math.floor(totalForThisRoute / cityPairs.length)
    let remaining = totalForThisRoute - samplesPerPair * cityPairs.length

    for (const pair of cityPairs) {
      const samples = samplesPerPair + (remaining > 0 ? 1 : 0)
      if (remaining > 0) remaining--

      if (samples > 0) {
        routes.push({
          originCity: pair.origin,
          destCity: pair.dest,
          samples,
        })
      }
    }
  }

  console.log(`Total routes generated: ${routes.length}, total samples: ${routes.reduce((sum, r) => sum + r.samples, 0)}`)
  return routes
}

/**
 * PASO 2: Generar entradas para una ruta ciudad-ciudad
 */
function generateEntriesForRoute(
  route: CityPairRoute,
  weeks: PlanWeek[],
  allNodes: Node[],
  useSeasonalDistribution: boolean,
  seasonalDistribution: SeasonalDistribution | undefined,
  ctx: GenerationContext
): AllocationEntry[] {
  const entries: AllocationEntry[] = []

  // Obtener nodos de origen y destino
  const originNodes = allNodes.filter(n => n.status === 'active' && n.city_id === route.originCity.id)
  const destNodes = allNodes.filter(n => n.status === 'active' && n.city_id === route.destCity.id)

  if (originNodes.length === 0 || destNodes.length === 0) {
    console.warn(`No nodes available for route ${route.originCity.name}→${route.destCity.name}`)
    return []
  }

  // Distribuir muestras por semanas (aplicando estacionalidad si está habilitada)
  const samplesPerWeek = distributeSamplesAcrossWeeks(route.samples, weeks, useSeasonalDistribution, seasonalDistribution)

  // Para cada semana, crear asignaciones con balanceo bidireccional
  for (let i = 0; i < weeks.length; i++) {
    const week = weeks[i]
    const samples = samplesPerWeek[i]
    if (samples === 0) continue

    // A node whose panelist is absent the whole week takes no part in it: its share goes to the other
    // nodes of its city. With no node left on one side, the week's samples cannot be placed.
    const keys = week.days.map(localDateKey)
    const availableSomeDay = (n: Node) => keys.some(k => !isBlocked(ctx.unavailability, n.id, k))
    const weekOrigins = originNodes.filter(availableSomeDay)
    const weekDests = destNodes.filter(availableSomeDay)
    if (weekOrigins.length === 0 || weekDests.length === 0) {
      ctx.dropped += samples
      continue
    }

    for (let s = 0; s < samples; s++) {
      const assignment = pickNodes(weekOrigins, weekDests, i, ctx)
      const placed = placeAssignment(assignment, weekOrigins, weekDests, week, route.originCity.id, i, ctx)
      if (!placed) {
        ctx.dropped++
        continue
      }
      recordNodeLoad(placed.originNodeId, placed.destNodeId, i, ctx)
      entries.push(makeEntry(placed.originNodeId, placed.destNodeId, placed.date, 'plan'))
    }
  }

  return entries
}

/** Node ids sorted by fewest load this week, then fewest in the whole plan so far, then list order. */
function rankByLoad(ids: string[], weekLoad: Map<string, number>, periodLoad: Map<string, number>, weekIdx: number): string[] {
  return ids
    .map((id, order) => ({ id, order }))
    .sort((a, b) =>
      (weekLoad.get(`${a.id}|${weekIdx}`) ?? 0) - (weekLoad.get(`${b.id}|${weekIdx}`) ?? 0) ||
      (periodLoad.get(a.id) ?? 0) - (periodLoad.get(b.id) ?? 0) ||
      a.order - b.order)
    .map(x => x.id)
}

/**
 * Origin and destination node for the next sample of a route-week (spec §5 rule 6, node equity).
 * Deterministic fewest-so-far over counters shared by every route of the run: the origin is the node of
 * the origin city that has sent least this week (rule 5 first), then least in the whole plan, so the +1 of
 * an uneven split goes to a different node each time instead of always to the first one. The destination
 * is chosen the same way on receptions; among equals, the one this origin has sent to least, so a pair of
 * nodes does not lock into always shipping to each other.
 */
function pickNodes(origins: Node[], dests: Node[], weekIdx: number, ctx: GenerationContext): { originNodeId: string; destNodeId: string } {
  const originNodeId = rankByLoad(origins.map(n => n.id), ctx.sendWeek, ctx.sendPeriod, weekIdx)[0]
  const destNodeId = dests
    .map((n, order) => ({ id: n.id, order }))
    .sort((a, b) =>
      (ctx.recvWeek.get(`${a.id}|${weekIdx}`) ?? 0) - (ctx.recvWeek.get(`${b.id}|${weekIdx}`) ?? 0) ||
      (ctx.recvPeriod.get(a.id) ?? 0) - (ctx.recvPeriod.get(b.id) ?? 0) ||
      (ctx.pairLoad.get(`${originNodeId}|${a.id}`) ?? 0) - (ctx.pairLoad.get(`${originNodeId}|${b.id}`) ?? 0) ||
      a.order - b.order)[0].id
  return { originNodeId, destNodeId }
}

function recordNodeLoad(originId: string, destId: string, weekIdx: number, ctx: GenerationContext): void {
  bump(ctx.sendWeek, `${originId}|${weekIdx}`)
  bump(ctx.sendPeriod, originId)
  bump(ctx.recvWeek, `${destId}|${weekIdx}`)
  bump(ctx.recvPeriod, destId)
  bump(ctx.pairLoad, `${originId}|${destId}`)
}

/**
 * Give an assignment its day inside the week. The assigned origin/destination pair is tried first; when the
 * two panelists have no common free day, another destination node of the destination city, then another
 * origin node of the origin city, is tried. Returns null when no pair of the week has a common free day.
 */
function placeAssignment(
  assignment: { originNodeId: string; destNodeId: string },
  origins: Node[],
  dests: Node[],
  week: PlanWeek,
  originCityId: string,
  weekIdx: number,
  ctx: GenerationContext
): { originNodeId: string; destNodeId: string; date: Date } | null {
  // Fallback nodes in the same fewest-so-far order as the first choice.
  const otherOrigins = rankByLoad(origins.map(n => n.id), ctx.sendWeek, ctx.sendPeriod, weekIdx)
    .filter(id => id !== assignment.originNodeId)
  const otherDests = rankByLoad(dests.map(n => n.id), ctx.recvWeek, ctx.recvPeriod, weekIdx)
    .filter(id => id !== assignment.destNodeId)
  const pairs: Array<[string, string]> = [[assignment.originNodeId, assignment.destNodeId]]
  for (const d of otherDests) pairs.push([assignment.originNodeId, d])
  for (const o of otherOrigins) pairs.push([o, assignment.destNodeId])
  for (const o of otherOrigins) for (const d of otherDests) pairs.push([o, d])

  for (const [o, d] of pairs) {
    const date = chooseDate(o, d, week, originCityId, ctx)
    if (date) return { originNodeId: o, destNodeId: d, date }
  }
  return null
}

/**
 * Day for one shipment origin→dest in the week, or null when every day of the week is blocked for one of
 * the two nodes.
 * - weekly: the first working day of the week (inside the period) free for both nodes.
 * - daily: the free day where the origin node has sent least so far; ties go to the day the origin city
 *   has sent least, then the day the destination node has received least, then round-robin from the
 *   node's cursor. Deterministic: same input, same dates.
 */
function chooseDate(originId: string, destId: string, week: PlanWeek, originCityId: string, ctx: GenerationContext): Date | null {
  const n = week.days.length
  const keys = week.days.map(localDateKey)
  const free = (idx: number) =>
    !isBlocked(ctx.unavailability, originId, keys[idx]) && !isBlocked(ctx.unavailability, destId, keys[idx])

  let chosen = -1
  if (ctx.datePolicy === 'weekly') {
    const blocked = new Set<string>([
      ...(ctx.unavailability.get(originId) ?? []),
      ...(ctx.unavailability.get(destId) ?? []),
    ])
    // notBefore = the week's first day inside the period, so a partial first week never goes before startDate.
    const first = firstWorkingDayOfWeek(week.days[0], ctx.cal, week.days[0], blocked)
    chosen = first ? keys.indexOf(localDateKey(first)) : -1
    // The helper looks at the whole ISO week: a day after the period end is not valid.
    if (chosen === -1) chosen = keys.findIndex((_, idx) => free(idx))
  } else {
    const start = (ctx.cursor.get(originId) ?? 0) % n
    let best: number[] | null = null
    for (let step = 0; step < n; step++) {
      const idx = (start + step) % n
      if (!free(idx)) continue
      const score = [
        ctx.originDayLoad.get(`${originId}|${keys[idx]}`) ?? 0,
        ctx.cityDayLoad.get(`${originCityId}|${keys[idx]}`) ?? 0,
        ctx.destDayLoad.get(`${destId}|${keys[idx]}`) ?? 0,
        step,
      ]
      if (!best || lexLess(score, best)) {
        best = score
        chosen = idx
      }
    }
    if (chosen !== -1) ctx.cursor.set(originId, chosen + 1)
  }

  if (chosen === -1) return null
  bump(ctx.originDayLoad, `${originId}|${keys[chosen]}`)
  bump(ctx.destDayLoad, `${destId}|${keys[chosen]}`)
  bump(ctx.cityDayLoad, `${originCityId}|${keys[chosen]}`)
  return new Date(week.days[chosen])
}

function lexLess(a: number[], b: number[]): boolean {
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return a[i] < b[i]
  }
  return false
}

/**
 * POBOX: every city with valid nodes must send at least one shipment on every working day of the period.
 * For each empty day (chronologically): MOVE one shipment of that city from the nearest day holding 2 or
 * more (same week first, backwards then forwards; then weeks ±1, ±2...), keeping its nodes, as long as
 * both nodes are free on the new day. Otherwise CREATE one (generationSource 'pobox'): origin = free node
 * of the city with fewest shipments sent that week (tie: in the period); destination = free node of
 * another city (cities this city already ships to first) with fewest shipments received that week (tie:
 * the city with fewest receptions in the period, then the node). Mutates `entries`; returns how many
 * days could not be covered because no valid node was free.
 */
function applyPobox(
  entries: AllocationEntry[],
  weeks: PlanWeek[],
  cities: City[],
  usableNodes: Node[],
  unavailability: Map<string, Set<string>>
): number {
  const activeNodes = usableNodes.filter(n => n.status === 'active')
  const cityOfNode = new Map(activeNodes.map(n => [n.id, n.city_id]))
  const nodesByCity = new Map<string, Node[]>()
  for (const n of activeNodes) {
    if (!nodesByCity.has(n.city_id)) nodesByCity.set(n.city_id, [])
    nodesByCity.get(n.city_id)!.push(n)
  }
  const poboxCities = cities.filter(c => c.status === 'active' && nodesByCity.has(c.id))

  const weekOfKey = new Map<string, number>()
  weeks.forEach((w, wi) => w.days.forEach(d => weekOfKey.set(localDateKey(d), wi)))

  // Counters kept up to date while moving/creating.
  const originWeek = new Map<string, number>() // `${node}|${weekIdx}`
  const originPeriod = new Map<string, number>() // node
  const destWeek = new Map<string, number>() // `${node}|${weekIdx}`
  const destPeriod = new Map<string, number>() // node
  const cityDestPeriod = new Map<string, number>() // city
  const byCityDay = new Map<string, AllocationEntry[]>() // `${city}|${key}` -> entries sent from the city that day
  const pairedDestCities = new Map<string, Set<string>>() // origin city -> destination cities of its routes

  const countWeek = (e: AllocationEntry, by: number) => {
    const wi = weekOfKey.get(localDateKey(e.fechaProgramada))
    if (wi === undefined) return
    bump(originWeek, `${e.originNodeId}|${wi}`, by)
    bump(destWeek, `${e.destinationNodeId}|${wi}`, by)
  }
  const index = (e: AllocationEntry) => {
    const city = cityOfNode.get(e.originNodeId)
    if (!city) return
    const k = `${city}|${localDateKey(e.fechaProgramada)}`
    if (!byCityDay.has(k)) byCityDay.set(k, [])
    byCityDay.get(k)!.push(e)
  }
  for (const e of entries) {
    countWeek(e, 1)
    bump(originPeriod, e.originNodeId)
    bump(destPeriod, e.destinationNodeId)
    const originCity = cityOfNode.get(e.originNodeId)
    const destCity = cityOfNode.get(e.destinationNodeId)
    if (destCity) bump(cityDestPeriod, destCity)
    if (originCity && destCity) {
      if (!pairedDestCities.has(originCity)) pairedDestCities.set(originCity, new Set())
      pairedDestCities.get(originCity)!.add(destCity)
    }
    index(e)
  }

  // Days to look at for a surplus, nearest first: same week backwards then forwards, then weeks ±1, ±2...
  const candidateDays = (wi: number, di: number): Date[] => {
    const days = weeks[wi].days
    const out: Date[] = []
    for (let j = di - 1; j >= 0; j--) out.push(days[j])
    for (let j = di + 1; j < days.length; j++) out.push(days[j])
    for (let k = 1; k < weeks.length; k++) {
      if (wi - k >= 0) out.push(...[...weeks[wi - k].days].reverse())
      if (wi + k < weeks.length) out.push(...weeks[wi + k].days)
    }
    return out
  }

  const tryMove = (cityId: string, wi: number, di: number, day: Date, key: string): boolean => {
    for (const src of candidateDays(wi, di)) {
      const srcList = byCityDay.get(`${cityId}|${localDateKey(src)}`)
      if (!srcList || srcList.length < 2) continue
      for (let j = srcList.length - 1; j >= 0; j--) {
        const e = srcList[j]
        if (isBlocked(unavailability, e.originNodeId, key) || isBlocked(unavailability, e.destinationNodeId, key)) continue
        srcList.splice(j, 1)
        countWeek(e, -1)
        const date = new Date(day)
        e.fechaProgramada = date
        e.weekNumber = getWeekNumber(date)
        e.month = date.getMonth() + 1
        e.year = date.getFullYear()
        countWeek(e, 1)
        index(e)
        return true
      }
    }
    return false
  }

  let uncovered = 0
  for (const city of poboxCities) {
    const cityNodes = nodesByCity.get(city.id)!
    const otherCities = poboxCities.map(c => c.id).filter(id => id !== city.id)
    const paired = otherCities.filter(id => pairedDestCities.get(city.id)?.has(id))

    for (let wi = 0; wi < weeks.length; wi++) {
      for (let di = 0; di < weeks[wi].days.length; di++) {
        const day = weeks[wi].days[di]
        const key = localDateKey(day)
        if ((byCityDay.get(`${city.id}|${key}`)?.length ?? 0) > 0) continue

        // 1. Move
        if (tryMove(city.id, wi, di, day, key)) continue

        // 2. Create
        const origin = cityNodes
          .filter(n => !isBlocked(unavailability, n.id, key))
          .sort((a, b) =>
            (originWeek.get(`${a.id}|${wi}`) ?? 0) - (originWeek.get(`${b.id}|${wi}`) ?? 0) ||
            (originPeriod.get(a.id) ?? 0) - (originPeriod.get(b.id) ?? 0) ||
            a.id.localeCompare(b.id))[0]
        const pickDest = (cityIds: string[]) =>
          cityIds
            .flatMap(cid => nodesByCity.get(cid) ?? [])
            .filter(n => !isBlocked(unavailability, n.id, key))
            .sort((a, b) =>
              (destWeek.get(`${a.id}|${wi}`) ?? 0) - (destWeek.get(`${b.id}|${wi}`) ?? 0) ||
              (cityDestPeriod.get(a.city_id) ?? 0) - (cityDestPeriod.get(b.city_id) ?? 0) ||
              (destPeriod.get(a.id) ?? 0) - (destPeriod.get(b.id) ?? 0) ||
              a.id.localeCompare(b.id))[0]
        const dest = pickDest(paired) ?? pickDest(otherCities)
        if (!origin || !dest) {
          uncovered++
          continue
        }
        const e = makeEntry(origin.id, dest.id, new Date(day), 'pobox')
        entries.push(e)
        countWeek(e, 1)
        bump(originPeriod, origin.id)
        bump(destPeriod, dest.id)
        bump(cityDestPeriod, dest.city_id)
        index(e)
      }
    }
  }
  return uncovered
}

interface PlanWeek {
  weekNumber: number
  /** Working days of this ISO week inside the plan period (never empty). */
  days: Date[]
}

const MONTH_KEYS: (keyof SeasonalDistribution)[] = [
  'jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
]

/**
 * Working days of the period grouped by ISO week (Monday to Sunday), in order. A day is a working day when
 * its weekday is one of the account's working weekdays, it falls inside [startDate, endDate] and it is not
 * an account non-working day. Weeks without any working day are left out, so a partial first or last week
 * only offers its own days.
 */
function buildPlanWeeks(startDate: Date, endDate: Date, cal: WorkingCalendar): PlanWeek[] {
  const weeks = new Map<string, PlanWeek>()
  const d = new Date(startDate.getFullYear(), startDate.getMonth(), startDate.getDate())
  const end = new Date(endDate.getFullYear(), endDate.getMonth(), endDate.getDate())

  while (d <= end) {
    if (isWorkingDay(d, cal)) {
      // ISO week: a Sunday belongs to the week of the Monday six days before.
      const monday = new Date(d.getFullYear(), d.getMonth(), d.getDate() - ((d.getDay() + 6) % 7))
      const key = localDateKey(monday)
      if (!weeks.has(key)) weeks.set(key, { weekNumber: getWeekNumber(d), days: [] })
      weeks.get(key)!.days.push(new Date(d))
    }
    d.setDate(d.getDate() + 1)
  }

  return Array.from(weeks.values())
}

/**
 * Distribute a route's samples across the weeks.
 *
 * Each week weighs its number of working days (times the seasonal percentage of its month when seasonality
 * is on). Every week first gets the whole part of its share; the samples left over are then drawn at random,
 * weighted by the fractional parts. Before 2026-10-26 the left-over always went to the FIRST weeks: with
 * many routes and few samples per route (Kenya: 706 routes, 1.7 samples each) almost the whole plan landed
 * in weeks 1-2. Drawing them at random keeps every route's total and spreads the plan evenly over time.
 */
function distributeSamplesAcrossWeeks(
  totalSamples: number,
  weeks: PlanWeek[],
  useSeasonalDistribution: boolean,
  seasonalDistribution?: SeasonalDistribution
): number[] {
  const weights = weeks.map(week => {
    let w = week.days.length
    if (useSeasonalDistribution && seasonalDistribution) {
      w *= (seasonalDistribution[MONTH_KEYS[week.days[0].getMonth()]] || 0) / 100
    }
    return w
  })
  const weightSum = weights.reduce((sum, w) => sum + w, 0)
  if (weightSum <= 0) return weeks.map(() => 0)

  const exact = weights.map(w => (totalSamples * w) / weightSum)
  const counts = exact.map(e => Math.floor(e))
  const fractions = exact.map((e, i) => e - counts[i])
  let remaining = totalSamples - counts.reduce((sum, c) => sum + c, 0)

  while (remaining > 0) {
    // Weighted draw without replacement on the fractional parts; plain weights only as a rounding fallback.
    const pool = fractions.some(f => f > 1e-9) ? fractions : weights
    const poolSum = pool.reduce((sum, f) => sum + f, 0)
    let r = Math.random() * poolSum
    let idx = 0
    while (idx < pool.length - 1 && r >= pool[idx]) {
      r -= pool[idx]
      idx++
    }
    counts[idx]++
    fractions[idx] = 0
    remaining--
  }

  return counts
}

/**
 * Calcular número de semana ISO
 */
function getWeekNumber(date: Date): number {
  const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()))
  const dayNum = d.getUTCDay() || 7
  d.setUTCDate(d.getUTCDate() + 4 - dayNum)
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1))
  return Math.ceil(((d.getTime() - yearStart.getTime()) / 86400000 + 1) / 7)
}
