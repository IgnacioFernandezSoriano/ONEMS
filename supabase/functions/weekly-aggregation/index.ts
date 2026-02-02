// ============================================================================
// Edge Function: Weekly Aggregation ETL
// ============================================================================
// Esta función agrega datos semanales desde one_db a E2E DB
// Se ejecuta automáticamente cada lunes a las 2 AM via pg_cron

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ============================================================================
// Tipos
// ============================================================================

interface Shipment {
  id: string
  account_id: string
  carrier_name: string
  product_name: string
  origin_city_name: string
  destination_city_name: string
  sent_at: string
  received_at: string
  business_transit_days: number
  on_time_delivery: boolean
}

interface RouteStats {
  carrier_name: string
  product_name: string
  origin_city_name: string
  origin_region_name: string | null
  destination_city_name: string
  destination_region_name: string | null
  total_shipments: number
  compliant_shipments: number
  warning_shipments: number
  critical_shipments: number
  business_days: number[]
  warning_threshold: number
  critical_threshold: number
}

// ============================================================================
// Función Principal
// ============================================================================

serve(async (req) => {
  try {
    // Crear cliente de Supabase con service role
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // 1. Determinar semana a procesar
    const { weekStart, weekEnd, weekNumber, year } = getLastCompleteWeek()
    
    console.log(`[ETL] Processing week: ${weekStart} to ${weekEnd} (Week ${weekNumber}, ${year})`)

    // Registrar inicio en etl_log
    const { data: logEntry, error: logError } = await supabase
      .from('etl_log')
      .insert({
        week_start_date: weekStart,
        week_end_date: weekEnd,
        status: 'running',
      })
      .select()
      .single()

    if (logError) throw logError

    // 2. Obtener todas las cuentas activas
    const { data: accounts, error: accountsError } = await supabase
      .from('accounts')
      .select('id')

    if (accountsError) throw accountsError

    let totalRecordsProcessed = 0
    let totalRoutesCreated = 0

    // 3. Procesar cada cuenta
    for (const account of accounts || []) {
      const result = await processAccount(
        supabase,
        account.id,
        weekStart,
        weekEnd,
        weekNumber,
        year
      )
      totalRecordsProcessed += result.recordsProcessed
      totalRoutesCreated += result.routesCreated
    }

    // 4. Actualizar log con éxito
    await supabase
      .from('etl_log')
      .update({
        execution_end: new Date().toISOString(),
        status: 'success',
        records_processed: totalRecordsProcessed,
        routes_created: totalRoutesCreated,
      })
      .eq('id', logEntry.id)

    return new Response(
      JSON.stringify({
        success: true,
        week: `${weekStart} to ${weekEnd}`,
        weekNumber,
        year,
        recordsProcessed: totalRecordsProcessed,
        routesCreated: totalRoutesCreated,
      }),
      {
        headers: { 'Content-Type': 'application/json' },
        status: 200,
      }
    )
  } catch (error) {
    console.error('[ETL] Error:', error)

    return new Response(
      JSON.stringify({
        success: false,
        error: error.message,
      }),
      {
        headers: { 'Content-Type': 'application/json' },
        status: 500,
      }
    )
  }
})

// ============================================================================
// Funciones Auxiliares
// ============================================================================

function getLastCompleteWeek() {
  const today = new Date()
  
  // Retroceder al último domingo
  const lastSunday = new Date(today)
  lastSunday.setDate(today.getDate() - today.getDay())
  lastSunday.setHours(0, 0, 0, 0)
  
  // Semana anterior completa (lunes a domingo)
  const weekEnd = new Date(lastSunday)
  weekEnd.setDate(weekEnd.getDate() - 1) // Sábado
  weekEnd.setHours(23, 59, 59, 999)
  
  const weekStart = new Date(weekEnd)
  weekStart.setDate(weekStart.getDate() - 6) // Lunes
  weekStart.setHours(0, 0, 0, 0)
  
  // Calcular número de semana ISO
  const weekNumber = getISOWeek(weekStart)
  const year = weekStart.getFullYear()
  
  return {
    weekStart: weekStart.toISOString().split('T')[0],
    weekEnd: weekEnd.toISOString().split('T')[0],
    weekNumber,
    year,
  }
}

function getISOWeek(date: Date): number {
  const target = new Date(date.valueOf())
  const dayNr = (date.getDay() + 6) % 7
  target.setDate(target.getDate() - dayNr + 3)
  const firstThursday = target.valueOf()
  target.setMonth(0, 1)
  if (target.getDay() !== 4) {
    target.setMonth(0, 1 + ((4 - target.getDay()) + 7) % 7)
  }
  return 1 + Math.ceil((firstThursday - target.valueOf()) / 604800000)
}

async function processAccount(
  supabase: any,
  accountId: string,
  weekStart: string,
  weekEnd: string,
  weekNumber: number,
  year: number
) {
  console.log(`[ETL] Processing account: ${accountId}`)

  // 1. Obtener shipments de la semana
  const shipments = await fetchShipments(supabase, accountId, weekStart, weekEnd)
  
  if (shipments.length === 0) {
    console.log(`[ETL] No shipments for account ${accountId}`)
    return { recordsProcessed: 0, routesCreated: 0 }
  }

  // 2. Obtener mapas de ciudades y regiones
  const { cityRegionMap } = await fetchCityRegionMaps(supabase, accountId)

  // 3. Agregar por ruta
  const routeStatsMap = aggregateByRoute(shipments, cityRegionMap)

  // 4. Preparar registros para weekly_routes
  const weeklyRoutes = Array.from(routeStatsMap.values()).map((stats) => {
    const compliance_percentage = (stats.compliant_shipments / stats.total_shipments) * 100
    const avg_business_days = stats.business_days.reduce((a, b) => a + b, 0) / stats.business_days.length
    
    // Calcular percentiles
    const sorted = [...stats.business_days].sort((a, b) => a - b)
    const p50 = percentile(sorted, 0.50)
    const p75 = percentile(sorted, 0.75)
    const p85 = percentile(sorted, 0.85)
    const p90 = percentile(sorted, 0.90)
    const p95 = percentile(sorted, 0.95)
    
    // Determinar status
    let route_status = 'compliant'
    if (compliance_percentage <= stats.critical_threshold) {
      route_status = 'critical'
    } else if (compliance_percentage < stats.warning_threshold) {
      route_status = 'warning'
    }

    return {
      account_id: accountId,
      week_start_date: weekStart,
      week_end_date: weekEnd,
      week_number: weekNumber,
      year,
      carrier_name: stats.carrier_name,
      product_name: stats.product_name,
      origin_city_name: stats.origin_city_name,
      origin_region_name: stats.origin_region_name,
      destination_city_name: stats.destination_city_name,
      destination_region_name: stats.destination_region_name,
      total_shipments: stats.total_shipments,
      compliant_shipments: stats.compliant_shipments,
      warning_shipments: stats.warning_shipments,
      critical_shipments: stats.critical_shipments,
      compliance_percentage,
      avg_business_days,
      min_business_days: Math.min(...stats.business_days),
      max_business_days: Math.max(...stats.business_days),
      business_days_p50: p50,
      business_days_p75: p75,
      business_days_p85: p85,
      business_days_p90: p90,
      business_days_p95: p95,
      warning_threshold: stats.warning_threshold,
      critical_threshold: stats.critical_threshold,
      route_status,
    }
  })

  // 5. Insertar en weekly_routes
  const { error: routesError } = await supabase
    .from('weekly_routes')
    .upsert(weeklyRoutes, {
      onConflict: 'account_id,week_start_date,carrier_name,product_name,origin_city_name,destination_city_name'
    })

  if (routesError) throw routesError

  // 6. Agregar por carrier
  await aggregateCarriers(supabase, accountId, weekStart, weekEnd, weeklyRoutes)

  // 7. Agregar por producto
  await aggregateProducts(supabase, accountId, weekStart, weekEnd, weeklyRoutes)

  // 8. Agregar por ciudad (inbound/outbound)
  await aggregateCities(supabase, accountId, weekStart, weekEnd, weeklyRoutes)

  // 9. Agregar por región (inbound/outbound)
  await aggregateRegions(supabase, accountId, weekStart, weekEnd, weeklyRoutes)

  return {
    recordsProcessed: shipments.length,
    routesCreated: weeklyRoutes.length,
  }
}

async function fetchShipments(
  supabase: any,
  accountId: string,
  weekStart: string,
  weekEnd: string
): Promise<Shipment[]> {
  const allShipments: Shipment[] = []
  const pageSize = 1000
  let start = 0
  let hasMore = true

  while (hasMore) {
    const { data, error } = await supabase
      .from('one_db')
      .select('*')
      .eq('account_id', accountId)
      .gte('sent_at', weekStart)
      .lte('sent_at', weekEnd)
      .range(start, start + pageSize - 1)

    if (error) throw error

    if (data && data.length > 0) {
      allShipments.push(...data)
      hasMore = data.length === pageSize
      start += pageSize
    } else {
      hasMore = false
    }
  }

  return allShipments
}

async function fetchCityRegionMaps(supabase: any, accountId: string) {
  const { data: cities, error: citiesError } = await supabase
    .from('cities')
    .select('name, region_id')
    .eq('account_id', accountId)

  if (citiesError) throw citiesError

  const { data: regions, error: regionsError } = await supabase
    .from('regions')
    .select('id, name')
    .eq('account_id', accountId)

  if (regionsError) throw regionsError

  const regionMap = new Map(regions.map((r: any) => [r.id, r.name]))
  const cityRegionMap = new Map(
    cities.map((c: any) => [c.name, regionMap.get(c.region_id) || null])
  )

  return { cityRegionMap }
}

function aggregateByRoute(
  shipments: Shipment[],
  cityRegionMap: Map<string, string | null>
): Map<string, RouteStats> {
  const routeStatsMap = new Map<string, RouteStats>()

  for (const shipment of shipments) {
    const routeKey = `${shipment.carrier_name}|${shipment.product_name}|${shipment.origin_city_name}|${shipment.destination_city_name}`

    if (!routeStatsMap.has(routeKey)) {
      routeStatsMap.set(routeKey, {
        carrier_name: shipment.carrier_name,
        product_name: shipment.product_name,
        origin_city_name: shipment.origin_city_name,
        origin_region_name: cityRegionMap.get(shipment.origin_city_name) || null,
        destination_city_name: shipment.destination_city_name,
        destination_region_name: cityRegionMap.get(shipment.destination_city_name) || null,
        total_shipments: 0,
        compliant_shipments: 0,
        warning_shipments: 0,
        critical_shipments: 0,
        business_days: [],
        warning_threshold: 80,
        critical_threshold: 75,
      })
    }

    const stats = routeStatsMap.get(routeKey)!
    stats.total_shipments++
    stats.business_days.push(shipment.business_transit_days)

    if (shipment.on_time_delivery) {
      stats.compliant_shipments++
    }
  }

  // Calcular warning/critical shipments
  for (const stats of routeStatsMap.values()) {
    const compliance = (stats.compliant_shipments / stats.total_shipments) * 100
    if (compliance <= stats.critical_threshold) {
      stats.critical_shipments = stats.total_shipments - stats.compliant_shipments
    } else if (compliance < stats.warning_threshold) {
      stats.warning_shipments = stats.total_shipments - stats.compliant_shipments
    }
  }

  return routeStatsMap
}

async function aggregateCarriers(
  supabase: any,
  accountId: string,
  weekStart: string,
  weekEnd: string,
  weeklyRoutes: any[]
) {
  const carrierMap = new Map<string, any>()

  for (const route of weeklyRoutes) {
    if (!carrierMap.has(route.carrier_name)) {
      carrierMap.set(route.carrier_name, {
        account_id: accountId,
        week_start_date: weekStart,
        week_end_date: weekEnd,
        carrier_name: route.carrier_name,
        total_routes: 0,
        total_shipments: 0,
        compliant_shipments: 0,
        compliant_routes: 0,
        warning_routes: 0,
        critical_routes: 0,
        avg_business_days: 0,
        total_business_days: 0,
      })
    }

    const carrier = carrierMap.get(route.carrier_name)
    carrier.total_routes++
    carrier.total_shipments += route.total_shipments
    carrier.compliant_shipments += route.compliant_shipments
    carrier.total_business_days += route.avg_business_days * route.total_shipments

    if (route.route_status === 'compliant') carrier.compliant_routes++
    else if (route.route_status === 'warning') carrier.warning_routes++
    else if (route.route_status === 'critical') carrier.critical_routes++
  }

  const weeklyCarriers = Array.from(carrierMap.values()).map((c) => ({
    ...c,
    compliance_percentage: (c.compliant_shipments / c.total_shipments) * 100,
    avg_business_days: c.total_business_days / c.total_shipments,
    total_business_days: undefined,
  }))

  await supabase.from('weekly_carriers').upsert(weeklyCarriers, {
    onConflict: 'account_id,week_start_date,carrier_name',
  })
}

async function aggregateProducts(
  supabase: any,
  accountId: string,
  weekStart: string,
  weekEnd: string,
  weeklyRoutes: any[]
) {
  const productMap = new Map<string, any>()

  for (const route of weeklyRoutes) {
    if (!productMap.has(route.product_name)) {
      productMap.set(route.product_name, {
        account_id: accountId,
        week_start_date: weekStart,
        week_end_date: weekEnd,
        product_name: route.product_name,
        total_routes: 0,
        total_shipments: 0,
        compliant_shipments: 0,
        compliant_routes: 0,
        warning_routes: 0,
        critical_routes: 0,
        avg_business_days: 0,
        total_business_days: 0,
      })
    }

    const product = productMap.get(route.product_name)
    product.total_routes++
    product.total_shipments += route.total_shipments
    product.compliant_shipments += route.compliant_shipments
    product.total_business_days += route.avg_business_days * route.total_shipments

    if (route.route_status === 'compliant') product.compliant_routes++
    else if (route.route_status === 'warning') product.warning_routes++
    else if (route.route_status === 'critical') product.critical_routes++
  }

  const weeklyProducts = Array.from(productMap.values()).map((p) => ({
    ...p,
    compliance_percentage: (p.compliant_shipments / p.total_shipments) * 100,
    avg_business_days: p.total_business_days / p.total_shipments,
    total_business_days: undefined,
  }))

  await supabase.from('weekly_products').upsert(weeklyProducts, {
    onConflict: 'account_id,week_start_date,product_name',
  })
}

async function aggregateCities(
  supabase: any,
  accountId: string,
  weekStart: string,
  weekEnd: string,
  weeklyRoutes: any[]
) {
  const cityMap = new Map<string, any>()

  for (const route of weeklyRoutes) {
    // Inbound (destination)
    const inboundKey = `${route.destination_city_name}|inbound`
    if (!cityMap.has(inboundKey)) {
      cityMap.set(inboundKey, {
        account_id: accountId,
        week_start_date: weekStart,
        week_end_date: weekEnd,
        city_name: route.destination_city_name,
        region_name: route.destination_region_name,
        direction: 'inbound',
        total_routes: 0,
        total_shipments: 0,
        compliant_shipments: 0,
        compliant_routes: 0,
        warning_routes: 0,
        critical_routes: 0,
        avg_business_days: 0,
        total_business_days: 0,
      })
    }

    const inbound = cityMap.get(inboundKey)
    inbound.total_routes++
    inbound.total_shipments += route.total_shipments
    inbound.compliant_shipments += route.compliant_shipments
    inbound.total_business_days += route.avg_business_days * route.total_shipments

    if (route.route_status === 'compliant') inbound.compliant_routes++
    else if (route.route_status === 'warning') inbound.warning_routes++
    else if (route.route_status === 'critical') inbound.critical_routes++

    // Outbound (origin)
    const outboundKey = `${route.origin_city_name}|outbound`
    if (!cityMap.has(outboundKey)) {
      cityMap.set(outboundKey, {
        account_id: accountId,
        week_start_date: weekStart,
        week_end_date: weekEnd,
        city_name: route.origin_city_name,
        region_name: route.origin_region_name,
        direction: 'outbound',
        total_routes: 0,
        total_shipments: 0,
        compliant_shipments: 0,
        compliant_routes: 0,
        warning_routes: 0,
        critical_routes: 0,
        avg_business_days: 0,
        total_business_days: 0,
      })
    }

    const outbound = cityMap.get(outboundKey)
    outbound.total_routes++
    outbound.total_shipments += route.total_shipments
    outbound.compliant_shipments += route.compliant_shipments
    outbound.total_business_days += route.avg_business_days * route.total_shipments

    if (route.route_status === 'compliant') outbound.compliant_routes++
    else if (route.route_status === 'warning') outbound.warning_routes++
    else if (route.route_status === 'critical') outbound.critical_routes++
  }

  const weeklyCities = Array.from(cityMap.values()).map((c) => ({
    ...c,
    compliance_percentage: (c.compliant_shipments / c.total_shipments) * 100,
    avg_business_days: c.total_business_days / c.total_shipments,
    total_business_days: undefined,
  }))

  await supabase.from('weekly_cities').upsert(weeklyCities, {
    onConflict: 'account_id,week_start_date,city_name,direction',
  })
}

async function aggregateRegions(
  supabase: any,
  accountId: string,
  weekStart: string,
  weekEnd: string,
  weeklyRoutes: any[]
) {
  const regionMap = new Map<string, any>()

  for (const route of weeklyRoutes) {
    // Inbound (destination region)
    if (route.destination_region_name) {
      const inboundKey = `${route.destination_region_name}|inbound`
      if (!regionMap.has(inboundKey)) {
        regionMap.set(inboundKey, {
          account_id: accountId,
          week_start_date: weekStart,
          week_end_date: weekEnd,
          region_name: route.destination_region_name,
          direction: 'inbound',
          total_cities: new Set(),
          total_routes: 0,
          total_shipments: 0,
          compliant_shipments: 0,
          compliant_routes: 0,
          warning_routes: 0,
          critical_routes: 0,
          avg_business_days: 0,
          total_business_days: 0,
        })
      }

      const inbound = regionMap.get(inboundKey)
      inbound.total_cities.add(route.destination_city_name)
      inbound.total_routes++
      inbound.total_shipments += route.total_shipments
      inbound.compliant_shipments += route.compliant_shipments
      inbound.total_business_days += route.avg_business_days * route.total_shipments

      if (route.route_status === 'compliant') inbound.compliant_routes++
      else if (route.route_status === 'warning') inbound.warning_routes++
      else if (route.route_status === 'critical') inbound.critical_routes++
    }

    // Outbound (origin region)
    if (route.origin_region_name) {
      const outboundKey = `${route.origin_region_name}|outbound`
      if (!regionMap.has(outboundKey)) {
        regionMap.set(outboundKey, {
          account_id: accountId,
          week_start_date: weekStart,
          week_end_date: weekEnd,
          region_name: route.origin_region_name,
          direction: 'outbound',
          total_cities: new Set(),
          total_routes: 0,
          total_shipments: 0,
          compliant_shipments: 0,
          compliant_routes: 0,
          warning_routes: 0,
          critical_routes: 0,
          avg_business_days: 0,
          total_business_days: 0,
        })
      }

      const outbound = regionMap.get(outboundKey)
      outbound.total_cities.add(route.origin_city_name)
      outbound.total_routes++
      outbound.total_shipments += route.total_shipments
      outbound.compliant_shipments += route.compliant_shipments
      outbound.total_business_days += route.avg_business_days * route.total_shipments

      if (route.route_status === 'compliant') outbound.compliant_routes++
      else if (route.route_status === 'warning') outbound.warning_routes++
      else if (route.route_status === 'critical') outbound.critical_routes++
    }
  }

  const weeklyRegions = Array.from(regionMap.values()).map((r) => ({
    ...r,
    total_cities: r.total_cities.size,
    compliance_percentage: (r.compliant_shipments / r.total_shipments) * 100,
    avg_business_days: r.total_business_days / r.total_shipments,
    total_business_days: undefined,
  }))

  await supabase.from('weekly_regions').upsert(weeklyRegions, {
    onConflict: 'account_id,week_start_date,region_name,direction',
  })
}

function percentile(sortedArray: number[], p: number): number {
  const index = (sortedArray.length - 1) * p
  const lower = Math.floor(index)
  const upper = Math.ceil(index)
  const weight = index % 1

  if (lower === upper) {
    return sortedArray[lower]
  }

  return sortedArray[lower] * (1 - weight) + sortedArray[upper] * weight
}
