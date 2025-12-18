import type { City, Node } from './types'

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
  maxSamplesPerWeek: number
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
    maxSamplesPerWeek,
  } = params

  const entries: AllocationEntry[] = []

  // PASO 1: Aplicar matriz A-B-C para obtener rutas ciudad-ciudad
  const cityRoutes = generateCityRoutes(totalSamples, cities, nodes, cityDistributionMatrix)

  // PASO 2: Para cada ruta ciudad-ciudad, distribuir temporalmente y por nodos
  for (const route of cityRoutes) {
    const routeEntries = generateEntriesForRoute(
      route,
      startDate,
      endDate,
      nodes,
      useSeasonalDistribution,
      seasonalDistribution,
      maxSamplesPerWeek
    )
    entries.push(...routeEntries)
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
  startDate: Date,
  endDate: Date,
  allNodes: Node[],
  useSeasonalDistribution: boolean,
  seasonalDistribution?: SeasonalDistribution,
  maxSamplesPerWeek: number = 10
): AllocationEntry[] {
  const entries: AllocationEntry[] = []

  // Obtener nodos de origen y destino
  const originNodes = allNodes.filter(n => n.status === 'active' && n.city_id === route.originCity.id)
  const destNodes = allNodes.filter(n => n.status === 'active' && n.city_id === route.destCity.id)

  if (originNodes.length === 0 || destNodes.length === 0) {
    console.warn(`No nodes available for route ${route.originCity.name}→${route.destCity.name}`)
    return []
  }

  // Calcular semanas en el período
  const weeks = getWeeksInPeriod(startDate, endDate)
  
  if (weeks.length === 0) return []

  // Distribuir muestras por semanas (aplicando estacionalidad si está habilitada)
  const samplesPerWeek = distributeSamplesAcrossWeeks(
    route.samples,
    weeks,
    useSeasonalDistribution,
    seasonalDistribution
  )

  // Para cada semana, crear asignaciones con balanceo bidireccional
  for (let i = 0; i < weeks.length; i++) {
    const week = weeks[i]
    const samples = samplesPerWeek[i]
    
    if (samples === 0) continue

    // Crear matriz de asignación balanceada
    const assignments = createBalancedAssignments(
      originNodes,
      destNodes,
      samples
    )

    // Generar entradas
    for (const assignment of assignments) {
      const date = getRandomDateInWeek(week.year, week.weekNumber)
      
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

/**
 * Obtener todas las semanas en un período
 */
function getWeeksInPeriod(startDate: Date, endDate: Date): Array<{ year: number; weekNumber: number }> {
  const weeks: Array<{ year: number; weekNumber: number }> = []
  const current = new Date(startDate)

  while (current <= endDate) {
    const weekNumber = getWeekNumber(current)
    const year = current.getFullYear()

    // Evitar duplicados
    if (weeks.length === 0 || weeks[weeks.length - 1].weekNumber !== weekNumber || weeks[weeks.length - 1].year !== year) {
      weeks.push({ year, weekNumber })
    }

    // Avanzar una semana
    current.setDate(current.getDate() + 7)
  }

  return weeks
}

/**
 * Distribuir muestras a lo largo de las semanas (con estacionalidad opcional)
 */
function distributeSamplesAcrossWeeks(
  totalSamples: number,
  weeks: Array<{ year: number; weekNumber: number }>,
  useSeasonalDistribution: boolean,
  seasonalDistribution?: SeasonalDistribution
): number[] {
  const samplesPerWeek: number[] = []

  if (!useSeasonalDistribution || !seasonalDistribution) {
    // Distribución uniforme
    const samplesPerWeekUniform = Math.floor(totalSamples / weeks.length)
    let remaining = totalSamples - samplesPerWeekUniform * weeks.length

    for (let i = 0; i < weeks.length; i++) {
      samplesPerWeek.push(samplesPerWeekUniform + (remaining > 0 ? 1 : 0))
      if (remaining > 0) remaining--
    }
  } else {
    // Distribución estacional
    const monthKeys: (keyof SeasonalDistribution)[] = [
      'jan', 'feb', 'mar', 'apr', 'may', 'jun',
      'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
    ]

    // Calcular factor estacional para cada semana
    const seasonalFactors: number[] = []
    for (const week of weeks) {
      const date = getFirstDayOfWeek(week.year, week.weekNumber)
      const month = date.getMonth()
      const monthKey = monthKeys[month]
      const factor = seasonalDistribution[monthKey] / 100
      seasonalFactors.push(factor)
    }

    // Normalizar factores
    const totalFactor = seasonalFactors.reduce((sum, f) => sum + f, 0)
    const normalizedFactors = seasonalFactors.map(f => f / totalFactor)

    // Distribuir muestras
    let assigned = 0
    for (let i = 0; i < weeks.length; i++) {
      const samples = Math.round(totalSamples * normalizedFactors[i])
      samplesPerWeek.push(samples)
      assigned += samples
    }

    // Ajustar diferencia
    const diff = totalSamples - assigned
    if (diff !== 0 && samplesPerWeek.length > 0) {
      samplesPerWeek[0] += diff
    }
  }

  return samplesPerWeek
}

/**
 * Obtener primer día de una semana ISO
 */
function getFirstDayOfWeek(year: number, weekNumber: number): Date {
  const jan4 = new Date(year, 0, 4)
  const jan4Day = jan4.getDay() || 7
  const firstMonday = new Date(jan4)
  firstMonday.setDate(jan4.getDate() - jan4Day + 1)
  firstMonday.setDate(firstMonday.getDate() + (weekNumber - 1) * 7)
  return firstMonday
}

/**
 * Obtener fecha aleatoria en una semana
 */
function getRandomDateInWeek(year: number, weekNumber: number): Date {
  const firstDay = getFirstDayOfWeek(year, weekNumber)
  const randomDay = Math.floor(Math.random() * 7)
  const date = new Date(firstDay)
  date.setDate(date.getDate() + randomDay)
  return date
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
