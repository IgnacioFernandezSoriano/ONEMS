import type { City, Node } from './types'
import { localDateKey } from './workingDays'

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
}

export interface AllocationEntry {
  originNodeId: string
  destinationNodeId: string
  fechaProgramada: Date
  weekNumber: number
  month: number
  year: number
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
  } = params

  // Only nodes with an active panelist can send or receive (a node without anyone produces impossible shipments).
  const eligible = eligibleNodeIds ? new Set(eligibleNodeIds) : null
  const usableNodes = eligible ? nodes.filter(n => eligible.has(n.id)) : nodes

  // Working days of the period (Mon-Fri, inside [startDate, endDate], not an account non-working day),
  // grouped by ISO week. Every shipment date is drawn from these days only.
  const weeks = buildPlanWeeks(startDate, endDate, new Set(nonWorkingDays || []))
  if (weeks.length === 0) return []

  const entries: AllocationEntry[] = []

  // PASO 1: Aplicar matriz A-B-C para obtener rutas ciudad-ciudad
  const cityRoutes = generateCityRoutes(totalSamples, cities, usableNodes, cityDistributionMatrix)

  // PASO 2: Para cada ruta ciudad-ciudad, distribuir temporalmente y por nodos
  for (const route of cityRoutes) {
    entries.push(...generateEntriesForRoute(route, weeks, usableNodes, useSeasonalDistribution, seasonalDistribution))
  }

  return entries
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
  seasonalDistribution?: SeasonalDistribution
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

    const assignments = createBalancedAssignments(originNodes, destNodes, samples)

    for (const assignment of assignments) {
      const date = week.days[Math.floor(Math.random() * week.days.length)]
      entries.push({
        originNodeId: assignment.originNodeId,
        destinationNodeId: assignment.destNodeId,
        fechaProgramada: date,
        weekNumber: week.weekNumber,
        month: date.getMonth() + 1,
        year: date.getFullYear(),
      })
    }
  }

  return entries
}

/**
 * Crear asignaciones balanceadas: cada nodo origen envía ~igual, cada nodo destino recibe ~igual
 */
function createBalancedAssignments(
  originNodes: Node[],
  destNodes: Node[],
  totalSamples: number
): Array<{ originNodeId: string; destNodeId: string }> {
  const assignments: Array<{ originNodeId: string; destNodeId: string }> = []

  const numOrigins = originNodes.length
  const numDests = destNodes.length

  // Calcular cuánto debe enviar cada origen y recibir cada destino
  const samplesPerOrigin = totalSamples / numOrigins
  const samplesPerDest = totalSamples / numDests

  // Crear matriz de asignación
  const matrix: number[][] = []
  for (let i = 0; i < numOrigins; i++) {
    matrix[i] = []
    for (let j = 0; j < numDests; j++) {
      matrix[i][j] = 0
    }
  }

  // Algoritmo de distribución balanceada con rotación
  let remaining = totalSamples
  const originSent = new Array(numOrigins).fill(0)
  const destReceived = new Array(numDests).fill(0)
  
  let currentOrigin = 0
  let currentDest = 0

  while (remaining > 0) {
    // Rotar entre orígenes y destinos para distribuir uniformemente
    matrix[currentOrigin][currentDest]++
    originSent[currentOrigin]++
    destReceived[currentDest]++
    remaining--
    
    // Avanzar al siguiente destino
    currentDest = (currentDest + 1) % numDests
    
    // Si completamos un ciclo de destinos, avanzar al siguiente origen
    if (currentDest === 0) {
      currentOrigin = (currentOrigin + 1) % numOrigins
    }
  }

  // Convertir matriz a lista de asignaciones
  for (let i = 0; i < numOrigins; i++) {
    for (let j = 0; j < numDests; j++) {
      for (let k = 0; k < matrix[i][j]; k++) {
        assignments.push({
          originNodeId: originNodes[i].id,
          destNodeId: destNodes[j].id,
        })
      }
    }
  }

  return assignments
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
 * Working days of the period grouped by ISO week, in order. A day is a working day when it is Monday to
 * Friday, falls inside [startDate, endDate] and is not an account non-working day. Weeks without any
 * working day are left out, so a partial first or last week only offers its own days.
 */
function buildPlanWeeks(startDate: Date, endDate: Date, nonWorkingDays: Set<string>): PlanWeek[] {
  const weeks = new Map<string, PlanWeek>()
  const d = new Date(startDate.getFullYear(), startDate.getMonth(), startDate.getDate())
  const end = new Date(endDate.getFullYear(), endDate.getMonth(), endDate.getDate())

  while (d <= end) {
    const dow = d.getDay()
    if (dow !== 0 && dow !== 6 && !nonWorkingDays.has(localDateKey(d))) {
      const monday = new Date(d)
      monday.setDate(d.getDate() - (dow - 1))
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
