import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
// Removed dateUtils import - using same filtering as ONE DB
import { calculateJKActualFromDays } from '@/lib/jkCalculations';
import type {
  CityEquityData,
  RegionEquityData,
  TerritoryEquityMetrics,
  TerritoryEquityFilters,
} from '@/types/reporting';
import { useEffectiveAccountId } from '../useEffectiveAccountId';
import { useFilterScenario } from './useFilterScenario';

// ============================================================================
// ROUTE-LEVEL DATA STRUCTURE
// ============================================================================

interface RouteStats {
  originCityId: string;
  originCityName: string;
  originRegionId: string;
  originRegionName: string | null;
  originClassification: 'capital' | 'major' | 'minor' | null;
  originPopulation: number | null;
  originLatitude: number | null;
  originLongitude: number | null;
  
  destinationCityId: string;
  destinationCityName: string;
  destinationRegionId: string;
  destinationRegionName: string | null;
  destinationClassification: 'capital' | 'major' | 'minor' | null;
  destinationPopulation: number | null;
  destinationLatitude: number | null;
  destinationLongitude: number | null;
  
  totalShipments: number;
  compliantShipments: number;
  standardsSum: number;
  standardsCount: number;
  standardDaysSum: number;
  standardDaysCount: number;
  actualDaysArray: number[];
  
  // Thresholds (weighted by shipments)
  warningThresholdsSum: number;
  criticalThresholdsSum: number;
  thresholdsCount: number;
  
  carrierProduct: Map<string, {
    carrier: string;
    product: string;
    total: number;
    compliant: number;
    standardsSum: number;
    standardsCount: number;
    standardDaysSum: number;
    standardDaysCount: number;
    actualDaysArray: number[];
  }>;
  
  accountId: string;
}

export function useTerritoryEquityData(
  accountId: string | undefined,
  filters?: TerritoryEquityFilters
) {
  const effectiveAccountId = useEffectiveAccountId();
  const activeAccountId = effectiveAccountId || accountId;

  const [cityData, setCityData] = useState<CityEquityData[]>([]);
  const [regionData, setRegionData] = useState<RegionEquityData[]>([]);
  const [metrics, setMetrics] = useState<TerritoryEquityMetrics | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);
  const [globalWarningThreshold, setGlobalWarningThreshold] = useState<number>(80);
  const [globalCriticalThreshold, setGlobalCriticalThreshold] = useState<number>(75);

  // Detect filter scenario
  const scenarioInfo = useFilterScenario(filters || {});

  useEffect(() => {
    if (!activeAccountId) {
      setLoading(false);
      return;
    }

    async function fetchData() {
      try {
        setLoading(true);
        setError(null);

        // 1. Load lookup tables
        const [citiesRes, regionsRes, carriersRes, productsRes, standardsRes] =
          await Promise.all([
            supabase.from('cities').select('*').eq('account_id', activeAccountId),
            supabase.from('regions').select('*').eq('account_id', activeAccountId),
            supabase.from('carriers').select('id, name').eq('account_id', activeAccountId),
            supabase.from('products').select('id, code, description').eq('account_id', activeAccountId),
            supabase.from('delivery_standards').select('*').eq('account_id', activeAccountId),
          ]);

        if (citiesRes.error) throw citiesRes.error;
        if (regionsRes.error) throw regionsRes.error;
        if (carriersRes.error) throw carriersRes.error;
        if (productsRes.error) throw productsRes.error;
        if (standardsRes.error) throw standardsRes.error;

        const cities = citiesRes.data || [];
        const regions = regionsRes.data || [];
        const carriers = carriersRes.data || [];
        const products = productsRes.data || [];
        const standards = standardsRes.data || [];

        // 2. Create lookup maps
        const cityMap = new Map(
          cities.map((c) => [
            c.name,
            {
              ...c,
              region_name: regions.find((r) => r.id === c.region_id)?.name || null,
            },
          ])
        );

        const cityNameToIdMap = new Map(cities.map((c) => [c.name, c.id]));
        const cityIdToDataMap = new Map(cities.map((c) => [c.id, c]));
        const regionMap = new Map(regions.map((r) => [r.id, r]));
        const carrierNameToIdMap = new Map(carriers.map((c) => [c.name, c.id]));
        const productDescToIdMap = new Map(products.map((p) => [`${p.code} - ${p.description}`, p.id]));

        // Standards map: "carrier_id|product_id|origin_id|dest_id" → standard
        const standardsMap = new Map(
          standards.map((s) => [
            `${s.carrier_id}|${s.product_id}|${s.origin_city_id}|${s.destination_city_id}`,
            s,
          ])
        );

        // Calculate global thresholds (average of all standards)
        let warningThreshold = 80;
        let criticalThreshold = 75;
        if (standards.length > 0) {
          const thresholds = standards.map((s: any) => {
            const successPct = s.success_percentage || 95;
            const warnThresh = s.threshold_type === 'relative'
              ? successPct - (successPct * (s.warning_threshold || 5) / 100)
              : (s.warning_threshold || 85);
            const critThresh = s.threshold_type === 'relative'
              ? successPct - (successPct * (s.critical_threshold || 10) / 100)
              : (s.critical_threshold || 75);
            return { warning: warnThresh, critical: critThresh };
          });
          warningThreshold = thresholds.reduce((sum, t) => sum + t.warning, 0) / thresholds.length;
          criticalThreshold = thresholds.reduce((sum, t) => sum + t.critical, 0) / thresholds.length;
        }
        setGlobalWarningThreshold(warningThreshold);
        setGlobalCriticalThreshold(criticalThreshold);

        // 3. Build shipments query with filters
        let shipmentsQuery = supabase
          .from('one_db')
          .select(`
            id,
            tag_id,
            carrier_name,
            product_name,
            origin_city_name,
            destination_city_name,
            sent_at,
            received_at,
            business_transit_days,
            on_time_delivery
          `)
          .eq('account_id', activeAccountId);

        // Use same date filtering as ONE DB (no time adjustment)
        if (filters?.startDate) {
          shipmentsQuery = shipmentsQuery.gte('sent_at', filters.startDate);
        }
        if (filters?.endDate) {
          shipmentsQuery = shipmentsQuery.lte('sent_at', filters.endDate);
        }

        // Apply origin/destination filters
        if (filters?.originCity) {
          shipmentsQuery = shipmentsQuery.eq('origin_city_name', filters.originCity);
        }
        if (filters?.destinationCity) {
          shipmentsQuery = shipmentsQuery.eq('destination_city_name', filters.destinationCity);
        }

        // Apply carrier/product filters
        if (filters?.carrier) {
          shipmentsQuery = shipmentsQuery.eq('carrier_name', filters.carrier);
        }
        if (filters?.product) {
          shipmentsQuery = shipmentsQuery.eq('product_name', filters.product);
        }

        const shipmentsRes = await shipmentsQuery;
        if (shipmentsRes.error) throw shipmentsRes.error;
        const shipments = shipmentsRes.data || [];

        // ====================================================================
        // ROUTE-LEVEL AGGREGATION
        // ====================================================================
        
        const routeStatsMap = new Map<string, RouteStats>();

        shipments.forEach((shipment) => {
          const originCityId = cityNameToIdMap.get(shipment.origin_city_name);
          const destCityId = cityNameToIdMap.get(shipment.destination_city_name);
          
          if (!originCityId || !destCityId) return; // Skip if city not found
          
          const routeKey = `${originCityId}|${destCityId}`;
          
          // Initialize route if not exists
          if (!routeStatsMap.has(routeKey)) {
            const originCity = cityIdToDataMap.get(originCityId);
            const destCity = cityIdToDataMap.get(destCityId);
            const originRegion = originCity ? regionMap.get(originCity.region_id) : null;
            const destRegion = destCity ? regionMap.get(destCity.region_id) : null;
            
            routeStatsMap.set(routeKey, {
              originCityId,
              originCityName: shipment.origin_city_name,
              originRegionId: originCity?.region_id || '',
              originRegionName: originRegion?.name || null,
              originClassification: originCity?.classification || null,
              originPopulation: originCity?.population || null,
              originLatitude: originCity?.latitude || null,
              originLongitude: originCity?.longitude || null,
              
              destinationCityId: destCityId,
              destinationCityName: shipment.destination_city_name,
              destinationRegionId: destCity?.region_id || '',
              destinationRegionName: destRegion?.name || null,
              destinationClassification: destCity?.classification || null,
              destinationPopulation: destCity?.population || null,
              destinationLatitude: destCity?.latitude || null,
              destinationLongitude: destCity?.longitude || null,
              
              totalShipments: 0,
              compliantShipments: 0,
              standardsSum: 0,
              standardsCount: 0,
              standardDaysSum: 0,
              standardDaysCount: 0,
              actualDaysArray: [],
              
              warningThresholdsSum: 0,
              criticalThresholdsSum: 0,
              thresholdsCount: 0,
              
              carrierProduct: new Map(),
              accountId: activeAccountId || '',
            });
          }
          
          const routeStats = routeStatsMap.get(routeKey)!;
          
          // Aggregate route-level metrics
          routeStats.totalShipments++;
          if (shipment.on_time_delivery) routeStats.compliantShipments++;
          
          // Track actual business days
          if (shipment.business_transit_days != null) {
            routeStats.actualDaysArray.push(shipment.business_transit_days);
          }
          
          // Track carrier/product breakdown for this route
          const cpKey = `${shipment.carrier_name}|${shipment.product_name}`;
          if (!routeStats.carrierProduct.has(cpKey)) {
            routeStats.carrierProduct.set(cpKey, {
              carrier: shipment.carrier_name,
              product: shipment.product_name,
              total: 0,
              compliant: 0,
              standardsSum: 0,
              standardsCount: 0,
              standardDaysSum: 0,
              standardDaysCount: 0,
              actualDaysArray: [],
            });
          }
          
          const cpStats = routeStats.carrierProduct.get(cpKey)!;
          cpStats.total++;
          if (shipment.on_time_delivery) cpStats.compliant++;
          
          // Track actual days for carrier/product
          if (shipment.business_transit_days != null) {
            cpStats.actualDaysArray.push(shipment.business_transit_days);
          }
          
          // Add standard for this carrier/product on this route
          const carrierId = carrierNameToIdMap.get(shipment.carrier_name);
          const productId = productDescToIdMap.get(shipment.product_name);
          
          if (carrierId && productId && originCityId && destCityId) {
            const standardKey = `${carrierId}|${productId}|${originCityId}|${destCityId}`;
            const standard = standardsMap.get(standardKey);
            
            if (standard) {
              // Add to route-level standards
              if (standard.success_percentage) {
                routeStats.standardsSum += standard.success_percentage;
                routeStats.standardsCount++;
              }
              
              // Calculate and add thresholds
              const successPct = standard.success_percentage || 95;
              const warnThresh = standard.threshold_type === 'relative'
                ? successPct - (successPct * (standard.warning_threshold || 5) / 100)
                : (standard.warning_threshold || 85);
              const critThresh = standard.threshold_type === 'relative'
                ? successPct - (successPct * (standard.critical_threshold || 10) / 100)
                : (standard.critical_threshold || 75);
              
              routeStats.warningThresholdsSum += warnThresh;
              routeStats.criticalThresholdsSum += critThresh;
              routeStats.thresholdsCount++;
              
              // Convert standard_time to days
              if (standard.standard_time != null) {
                const allowedDays = standard.time_unit === 'days' 
                  ? standard.standard_time 
                  : (standard.standard_time / 24);
                routeStats.standardDaysSum += allowedDays;
                routeStats.standardDaysCount++;
              }
              
              // Add to carrier/product standards
              if (standard.success_percentage) {
                cpStats.standardsSum += standard.success_percentage;
                cpStats.standardsCount++;
              }
              
              if (standard.standard_time != null) {
                const allowedDays = standard.time_unit === 'days' 
                  ? standard.standard_time 
                  : (standard.standard_time / 24);
                cpStats.standardDaysSum += allowedDays;
                cpStats.standardDaysCount++;
              }
            }
          }
        });

        // Convert to array
        const routeDataArray = Array.from(routeStatsMap.values());

        // ====================================================================
        // GROUP ROUTES FOR DISPLAY BASED ON SCENARIO
        // ====================================================================
        
        const groupedCityData = groupRoutesForDisplay(
          routeDataArray,
          scenarioInfo,
          filters,
          warningThreshold,
          criticalThreshold
        );

        setCityData(groupedCityData);

        // ====================================================================
        // REGIONAL ANALYSIS (aggregate routes by region)
        // ====================================================================
        
        const regionalData = aggregateRoutesByRegion(
          routeDataArray,
          scenarioInfo,
          filters,
          warningThreshold,
          criticalThreshold
        );

        setRegionData(regionalData);

        // ====================================================================
        // GLOBAL METRICS
        // ====================================================================
        
        const globalMetrics = calculateGlobalMetrics(
          routeDataArray,
          warningThreshold,
          criticalThreshold
        );

        setMetrics(globalMetrics);

      } catch (err) {
        console.error('Error fetching territory equity data:', err);
        setError(err instanceof Error ? err : new Error('Unknown error'));
      } finally {
        setLoading(false);
      }
    }

    fetchData();
  }, [
    activeAccountId,
    filters?.startDate,
    filters?.endDate,
    filters?.originCity,
    filters?.destinationCity,
    filters?.carrier,
    filters?.product,
  ]);

  return {
    cityData,
    regionData,
    metrics,
    loading,
    error,
    scenarioInfo,
    globalWarningThreshold,
    globalCriticalThreshold,
  };
}

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * Group route-level data for display based on filter scenario
 */
function groupRoutesForDisplay(
  routes: RouteStats[],
  scenarioInfo: any,
  filters: TerritoryEquityFilters | undefined,
  warningThreshold: number,
  criticalThreshold: number
): CityEquityData[] {
  const result: CityEquityData[] = [];

  if (scenarioInfo.scenario === 'route') {
    // ROUTE SCENARIO: Single route, show as city group with inbound/outbound
    // Both rows show the same route metrics
    if (routes.length > 0) {
      const route = routes[0];
      
      // Calculate metrics for this route
      const actualPercentage = route.totalShipments > 0
        ? (route.compliantShipments / route.totalShipments) * 100
        : 0;
      
      const standardPercentage = route.standardsCount > 0
        ? route.standardsSum / route.standardsCount
        : 0;
      
      const standardDays = route.standardDaysCount > 0
        ? route.standardDaysSum / route.standardDaysCount
        : 0;
      
      const actualDays = route.actualDaysArray.length > 0
        ? route.actualDaysArray.reduce((sum, d) => sum + d, 0) / route.actualDaysArray.length
        : 0;
      
      const deviation = actualPercentage - standardPercentage;
      
      // Calculate weighted thresholds for this route
      const routeWarningThreshold = route.thresholdsCount > 0
        ? route.warningThresholdsSum / route.thresholdsCount
        : warningThreshold;
      const routeCriticalThreshold = route.thresholdsCount > 0
        ? route.criticalThresholdsSum / route.thresholdsCount
        : criticalThreshold;
      
      const status: 'compliant' | 'warning' | 'critical' =
        actualPercentage >= routeWarningThreshold ? 'compliant' :
        actualPercentage >= routeCriticalThreshold ? 'warning' : 'critical';
      
      // Carrier/product breakdown
      const carrierProductBreakdown = Array.from(route.carrierProduct.values()).map(cp => {
        const cpActualPct = cp.total > 0 ? (cp.compliant / cp.total) * 100 : 0;
        const cpStandardPct = cp.standardsCount > 0 ? cp.standardsSum / cp.standardsCount : 0;
        const cpStandardDays = cp.standardDaysCount > 0 ? cp.standardDaysSum / cp.standardDaysCount : 0;
        const cpActualDays = cp.actualDaysArray.length > 0
          ? cp.actualDaysArray.reduce((sum, d) => sum + d, 0) / cp.actualDaysArray.length
          : 0;
        
        return {
          carrier: cp.carrier,
          product: cp.product,
          totalShipments: cp.total,
          compliantShipments: cp.compliant,
          actualPercentage: cpActualPct,
          standardPercentage: cpStandardPct,
          standardDays: cpStandardDays,
          actualDays: cpActualDays,
          deviation: cpActualPct - cpStandardPct,
          inboundPercentage: cpActualPct, // Same as overall in route scenario
          outboundPercentage: cpActualPct,
        };
      });
      
      // Create destination city row (Inbound perspective)
      result.push({
        cityId: route.destinationCityId,
        cityName: route.destinationCityName,
        regionId: route.destinationRegionId,
        regionName: route.destinationRegionName,
        classification: route.destinationClassification,
        population: route.destinationPopulation,
        latitude: route.destinationLatitude,
        longitude: route.destinationLongitude,
        
        totalShipments: route.totalShipments,
        compliantShipments: route.compliantShipments,
        standardPercentage,
        standardDays,
        actualDays,
        actualPercentage,
        deviation,
        status,
      aggregatedWarningThreshold: 80,
      aggregatedCriticalThreshold: 75,
        
        inboundShipments: route.totalShipments,
        inboundCompliant: route.compliantShipments,
        inboundPercentage: actualPercentage,
        inboundStandardPercentage: standardPercentage,
        inboundStandardDays: standardDays,
        inboundActualDays: actualDays,
        inboundDeviation: deviation,
        
        outboundShipments: 0,
        outboundCompliant: 0,
        outboundPercentage: 0,
        outboundStandardPercentage: 0,
        outboundStandardDays: 0,
        outboundActualDays: 0,
        outboundDeviation: 0,
        
        directionGap: 0,
        carrierProductBreakdown,
        accountId: route.accountId,
      });
      
      // Create origin city row (Outbound perspective)
      result.push({
        cityId: route.originCityId,
        cityName: route.originCityName,
        regionId: route.originRegionId,
        regionName: route.originRegionName,
        classification: route.originClassification,
        population: route.originPopulation,
        latitude: route.originLatitude,
        longitude: route.originLongitude,
        
        totalShipments: route.totalShipments,
        compliantShipments: route.compliantShipments,
        standardPercentage,
        standardDays,
        actualDays,
        actualPercentage,
        deviation,
        status,
      aggregatedWarningThreshold: 80,
      aggregatedCriticalThreshold: 75,
        
        inboundShipments: 0,
        inboundCompliant: 0,
        inboundPercentage: 0,
        inboundStandardPercentage: 0,
        inboundStandardDays: 0,
        inboundActualDays: 0,
        inboundDeviation: 0,
        
        outboundShipments: route.totalShipments,
        outboundCompliant: route.compliantShipments,
        outboundPercentage: actualPercentage,
        outboundStandardPercentage: standardPercentage,
        outboundStandardDays: standardDays,
        outboundActualDays: actualDays,
        outboundDeviation: deviation,
        
        directionGap: 0,
        carrierProductBreakdown,
        accountId: route.accountId,
      });
    }
  } else if (scenarioInfo.scenario === 'origin') {
    // ORIGIN SCENARIO: Group by destination city
    // For each destination, show Inbound (from filtered origin) and Outbound (from filtered origin)
    
    const destinationGroups = new Map<string, RouteStats[]>();
    
    routes.forEach(route => {
      if (!destinationGroups.has(route.destinationCityId)) {
        destinationGroups.set(route.destinationCityId, []);
      }
      destinationGroups.get(route.destinationCityId)!.push(route);
    });
    
    destinationGroups.forEach((routesForDest, destCityId) => {
      // Aggregate all routes to this destination
      const aggregated = aggregateRoutes(routesForDest);
      
      const actualPercentage = aggregated.totalShipments > 0
        ? (aggregated.compliantShipments / aggregated.totalShipments) * 100
        : 0;
      
      const standardPercentage = aggregated.standardsCount > 0
        ? aggregated.standardsSum / aggregated.standardsCount
        : 0;
      
      const standardDays = aggregated.standardDaysCount > 0
        ? aggregated.standardDaysSum / aggregated.standardDaysCount
        : 0;
      
      const actualDays = aggregated.actualDaysArray.length > 0
        ? aggregated.actualDaysArray.reduce((sum, d) => sum + d, 0) / aggregated.actualDaysArray.length
        : 0;
      
      const deviation = actualPercentage - standardPercentage;
      
      // Calculate weighted thresholds from aggregated routes
      const cityWarningThreshold = aggregated.thresholdsCount > 0
        ? aggregated.warningThresholdsSum / aggregated.thresholdsCount
        : warningThreshold;
      const cityCriticalThreshold = aggregated.thresholdsCount > 0
        ? aggregated.criticalThresholdsSum / aggregated.thresholdsCount
        : criticalThreshold;
      
      const status: 'compliant' | 'warning' | 'critical' =
        actualPercentage >= cityWarningThreshold ? 'compliant' :
        actualPercentage >= cityCriticalThreshold ? 'warning' : 'critical';
      
      const carrierProductBreakdown = buildCarrierProductBreakdown(aggregated.carrierProduct);
      
      const firstRoute = routesForDest[0];
      
      // Inbound row (destination perspective)
      result.push({
        cityId: firstRoute.destinationCityId,
        cityName: firstRoute.destinationCityName,
        regionId: firstRoute.destinationRegionId,
        regionName: firstRoute.destinationRegionName,
        classification: firstRoute.destinationClassification,
        population: firstRoute.destinationPopulation,
        latitude: firstRoute.destinationLatitude,
        longitude: firstRoute.destinationLongitude,
        
        totalShipments: aggregated.totalShipments,
        compliantShipments: aggregated.compliantShipments,
        standardPercentage,
        standardDays,
        actualDays,
        actualPercentage,
        deviation,
        status,
      aggregatedWarningThreshold: 80,
      aggregatedCriticalThreshold: 75,
        
        inboundShipments: aggregated.totalShipments,
        inboundCompliant: aggregated.compliantShipments,
        inboundPercentage: actualPercentage,
        inboundStandardPercentage: standardPercentage,
        inboundStandardDays: standardDays,
        inboundActualDays: actualDays,
        inboundDeviation: deviation,
        
        outboundShipments: 0,
        outboundCompliant: 0,
        outboundPercentage: 0,
        outboundStandardPercentage: 0,
        outboundStandardDays: 0,
        outboundActualDays: 0,
        outboundDeviation: 0,
        
        directionGap: 0,
        carrierProductBreakdown,
        accountId: firstRoute.accountId,
      });
      
      // Outbound row (origin perspective - same data, different label)
      result.push({
        cityId: firstRoute.originCityId,
        cityName: firstRoute.originCityName,
        regionId: firstRoute.originRegionId,
        regionName: firstRoute.originRegionName,
        classification: firstRoute.originClassification,
        population: firstRoute.originPopulation,
        latitude: firstRoute.originLatitude,
        longitude: firstRoute.originLongitude,
        
        totalShipments: aggregated.totalShipments,
        compliantShipments: aggregated.compliantShipments,
        standardPercentage,
        standardDays,
        actualDays,
        actualPercentage,
        deviation,
        status,
      aggregatedWarningThreshold: 80,
      aggregatedCriticalThreshold: 75,
        
        inboundShipments: 0,
        inboundCompliant: 0,
        inboundPercentage: 0,
        inboundStandardPercentage: 0,
        inboundStandardDays: 0,
        inboundActualDays: 0,
        inboundDeviation: 0,
        
        outboundShipments: aggregated.totalShipments,
        outboundCompliant: aggregated.compliantShipments,
        outboundPercentage: actualPercentage,
        outboundStandardPercentage: standardPercentage,
        outboundStandardDays: standardDays,
        outboundActualDays: actualDays,
        outboundDeviation: deviation,
        
        directionGap: 0,
        carrierProductBreakdown,
        accountId: firstRoute.accountId,
      });
    });
  } else if (scenarioInfo.scenario === 'destination') {
    // DESTINATION SCENARIO: Group by origin city
    // For each origin, show Inbound (to filtered destination) and Outbound (to filtered destination)
    
    const originGroups = new Map<string, RouteStats[]>();
    
    routes.forEach(route => {
      if (!originGroups.has(route.originCityId)) {
        originGroups.set(route.originCityId, []);
      }
      originGroups.get(route.originCityId)!.push(route);
    });
    
    originGroups.forEach((routesFromOrigin, originCityId) => {
      // Aggregate all routes from this origin
      const aggregated = aggregateRoutes(routesFromOrigin);
      
      const actualPercentage = aggregated.totalShipments > 0
        ? (aggregated.compliantShipments / aggregated.totalShipments) * 100
        : 0;
      
      const standardPercentage = aggregated.standardsCount > 0
        ? aggregated.standardsSum / aggregated.standardsCount
        : 0;
      
      const standardDays = aggregated.standardDaysCount > 0
        ? aggregated.standardDaysSum / aggregated.standardDaysCount
        : 0;
      
      const actualDays = aggregated.actualDaysArray.length > 0
        ? aggregated.actualDaysArray.reduce((sum, d) => sum + d, 0) / aggregated.actualDaysArray.length
        : 0;
      
      const deviation = actualPercentage - standardPercentage;
      
      // Calculate weighted thresholds from aggregated routes
      const cityWarningThreshold = aggregated.thresholdsCount > 0
        ? aggregated.warningThresholdsSum / aggregated.thresholdsCount
        : warningThreshold;
      const cityCriticalThreshold = aggregated.thresholdsCount > 0
        ? aggregated.criticalThresholdsSum / aggregated.thresholdsCount
        : criticalThreshold;
      
      const status: 'compliant' | 'warning' | 'critical' =
        actualPercentage >= cityWarningThreshold ? 'compliant' :
        actualPercentage >= cityCriticalThreshold ? 'warning' : 'critical';
      
      const carrierProductBreakdown = buildCarrierProductBreakdown(aggregated.carrierProduct);
      
      const firstRoute = routesFromOrigin[0];
      
      // Inbound row (destination perspective - same data, different label)
      result.push({
        cityId: firstRoute.destinationCityId,
        cityName: firstRoute.destinationCityName,
        regionId: firstRoute.destinationRegionId,
        regionName: firstRoute.destinationRegionName,
        classification: firstRoute.destinationClassification,
        population: firstRoute.destinationPopulation,
        latitude: firstRoute.destinationLatitude,
        longitude: firstRoute.destinationLongitude,
        
        totalShipments: aggregated.totalShipments,
        compliantShipments: aggregated.compliantShipments,
        standardPercentage,
        standardDays,
        actualDays,
        actualPercentage,
        deviation,
        status,
      aggregatedWarningThreshold: 80,
      aggregatedCriticalThreshold: 75,
        
        inboundShipments: aggregated.totalShipments,
        inboundCompliant: aggregated.compliantShipments,
        inboundPercentage: actualPercentage,
        inboundStandardPercentage: standardPercentage,
        inboundStandardDays: standardDays,
        inboundActualDays: actualDays,
        inboundDeviation: deviation,
        
        outboundShipments: 0,
        outboundCompliant: 0,
        outboundPercentage: 0,
        outboundStandardPercentage: 0,
        outboundStandardDays: 0,
        outboundActualDays: 0,
        outboundDeviation: 0,
        
        directionGap: 0,
        carrierProductBreakdown,
        accountId: firstRoute.accountId,
      });
      
      // Outbound row (origin perspective)
      result.push({
        cityId: firstRoute.originCityId,
        cityName: firstRoute.originCityName,
        regionId: firstRoute.originRegionId,
        regionName: firstRoute.originRegionName,
        classification: firstRoute.originClassification,
        population: firstRoute.originPopulation,
        latitude: firstRoute.originLatitude,
        longitude: firstRoute.originLongitude,
        
        totalShipments: aggregated.totalShipments,
        compliantShipments: aggregated.compliantShipments,
        standardPercentage,
        standardDays,
        actualDays,
        actualPercentage,
        deviation,
        status,
      aggregatedWarningThreshold: 80,
      aggregatedCriticalThreshold: 75,
        
        inboundShipments: 0,
        inboundCompliant: 0,
        inboundPercentage: 0,
        inboundStandardPercentage: 0,
        inboundStandardDays: 0,
        inboundActualDays: 0,
        inboundDeviation: 0,
        
        outboundShipments: aggregated.totalShipments,
        outboundCompliant: aggregated.compliantShipments,
        outboundPercentage: actualPercentage,
        outboundStandardPercentage: standardPercentage,
        outboundStandardDays: standardDays,
        outboundActualDays: actualDays,
        outboundDeviation: deviation,
        
        directionGap: 0,
        carrierProductBreakdown,
        accountId: firstRoute.accountId,
      });
    });
  } else {
    // GENERAL SCENARIO: Group by city (all routes)
    // For each city, aggregate inbound and outbound separately
    
    const cityInboundMap = new Map<string, RouteStats[]>();
    const cityOutboundMap = new Map<string, RouteStats[]>();
    
    routes.forEach(route => {
      // Track as inbound for destination city
      if (!cityInboundMap.has(route.destinationCityId)) {
        cityInboundMap.set(route.destinationCityId, []);
      }
      cityInboundMap.get(route.destinationCityId)!.push(route);
      
      // Track as outbound for origin city
      if (!cityOutboundMap.has(route.originCityId)) {
        cityOutboundMap.set(route.originCityId, []);
      }
      cityOutboundMap.get(route.originCityId)!.push(route);
    });
    
    // Get all unique cities
    const allCityIds = new Set([
      ...cityInboundMap.keys(),
      ...cityOutboundMap.keys(),
    ]);
    
    allCityIds.forEach(cityId => {
      const inboundRoutes = cityInboundMap.get(cityId) || [];
      const outboundRoutes = cityOutboundMap.get(cityId) || [];
      
      const inboundAgg = aggregateRoutes(inboundRoutes);
      const outboundAgg = aggregateRoutes(outboundRoutes);
      
      // Calculate inbound metrics
      const inboundPercentage = inboundAgg.totalShipments > 0
        ? (inboundAgg.compliantShipments / inboundAgg.totalShipments) * 100
        : 0;
      const inboundStandardPct = inboundAgg.standardsCount > 0
        ? inboundAgg.standardsSum / inboundAgg.standardsCount
        : 0;
      const inboundStandardDays = inboundAgg.standardDaysCount > 0
        ? inboundAgg.standardDaysSum / inboundAgg.standardDaysCount
        : 0;
      const inboundActualDays = inboundAgg.actualDaysArray.length > 0
        ? inboundAgg.actualDaysArray.reduce((sum, d) => sum + d, 0) / inboundAgg.actualDaysArray.length
        : 0;
      const inboundDeviation = inboundPercentage - inboundStandardPct;
      
      // Calculate outbound metrics
      const outboundPercentage = outboundAgg.totalShipments > 0
        ? (outboundAgg.compliantShipments / outboundAgg.totalShipments) * 100
        : 0;
      const outboundStandardPct = outboundAgg.standardsCount > 0
        ? outboundAgg.standardsSum / outboundAgg.standardsCount
        : 0;
      const outboundStandardDays = outboundAgg.standardDaysCount > 0
        ? outboundAgg.standardDaysSum / outboundAgg.standardDaysCount
        : 0;
      const outboundActualDays = outboundAgg.actualDaysArray.length > 0
        ? outboundAgg.actualDaysArray.reduce((sum, d) => sum + d, 0) / outboundAgg.actualDaysArray.length
        : 0;
      const outboundDeviation = outboundPercentage - outboundStandardPct;
      
      // Overall metrics (combined)
      const totalShipments = inboundAgg.totalShipments + outboundAgg.totalShipments;
      const compliantShipments = inboundAgg.compliantShipments + outboundAgg.compliantShipments;
      const actualPercentage = totalShipments > 0
        ? (compliantShipments / totalShipments) * 100
        : 0;
      
      const standardPercentage = (inboundStandardPct + outboundStandardPct) / 2;
      const standardDays = (inboundStandardDays + outboundStandardDays) / 2;
      const actualDays = (inboundActualDays + outboundActualDays) / 2;
      const deviation = actualPercentage - standardPercentage;
      
      // Calculate weighted thresholds from combined inbound + outbound
      const totalThresholdsCount = inboundAgg.thresholdsCount + outboundAgg.thresholdsCount;
      const cityWarningThreshold = totalThresholdsCount > 0
        ? (inboundAgg.warningThresholdsSum + outboundAgg.warningThresholdsSum) / totalThresholdsCount
        : warningThreshold;
      const cityCriticalThreshold = totalThresholdsCount > 0
        ? (inboundAgg.criticalThresholdsSum + outboundAgg.criticalThresholdsSum) / totalThresholdsCount
        : criticalThreshold;
      
      const status: 'compliant' | 'warning' | 'critical' =
        actualPercentage >= cityWarningThreshold ? 'compliant' :
        actualPercentage >= cityCriticalThreshold ? 'warning' : 'critical';
      
      const directionGap = inboundPercentage - outboundPercentage;
      
      // Merge carrier/product breakdowns
      const mergedCPMap = new Map(inboundAgg.carrierProduct);
      outboundAgg.carrierProduct.forEach((cpData, key) => {
        if (mergedCPMap.has(key)) {
          const existing = mergedCPMap.get(key)!;
          existing.total += cpData.total;
          existing.compliant += cpData.compliant;
          existing.standardsSum += cpData.standardsSum;
          existing.standardsCount += cpData.standardsCount;
          existing.standardDaysSum += cpData.standardDaysSum;
          existing.standardDaysCount += cpData.standardDaysCount;
          existing.actualDaysArray.push(...cpData.actualDaysArray);
        } else {
          mergedCPMap.set(key, cpData);
        }
      });
      
      const carrierProductBreakdown = buildCarrierProductBreakdown(mergedCPMap);
      
      const firstRoute = inboundRoutes[0] || outboundRoutes[0];
      const cityInfo = inboundRoutes[0] ? {
        cityId: firstRoute.destinationCityId,
        cityName: firstRoute.destinationCityName,
        regionId: firstRoute.destinationRegionId,
        regionName: firstRoute.destinationRegionName,
        classification: firstRoute.destinationClassification,
        population: firstRoute.destinationPopulation,
        latitude: firstRoute.destinationLatitude,
        longitude: firstRoute.destinationLongitude,
      } : {
        cityId: firstRoute.originCityId,
        cityName: firstRoute.originCityName,
        regionId: firstRoute.originRegionId,
        regionName: firstRoute.originRegionName,
        classification: firstRoute.originClassification,
        population: firstRoute.originPopulation,
        latitude: firstRoute.originLatitude,
        longitude: firstRoute.originLongitude,
      };
      
      result.push({
        ...cityInfo,
        
        totalShipments,
        compliantShipments,
        standardPercentage,
        standardDays,
        actualDays,
        actualPercentage,
        deviation,
        status,
      aggregatedWarningThreshold: 80,
      aggregatedCriticalThreshold: 75,
        
        inboundShipments: inboundAgg.totalShipments,
        inboundCompliant: inboundAgg.compliantShipments,
        inboundPercentage,
        inboundStandardPercentage: inboundStandardPct,
        inboundStandardDays,
        inboundActualDays,
        inboundDeviation,
        
        outboundShipments: outboundAgg.totalShipments,
        outboundCompliant: outboundAgg.compliantShipments,
        outboundPercentage,
        outboundStandardPercentage: outboundStandardPct,
        outboundStandardDays,
        outboundActualDays,
        outboundDeviation,
        
        directionGap,
        carrierProductBreakdown,
        accountId: firstRoute.accountId,
      });
    });
  }

  // Filter out empty rows (TOTAL=0 and J+K STD=0)
  return result.filter(city => {
    return city.totalShipments > 0 || city.standardDays > 0;
  });
}

/**
 * Aggregate multiple routes into a single aggregated result
 */
function aggregateRoutes(routes: RouteStats[]) {
  const result = {
    totalShipments: 0,
    compliantShipments: 0,
    standardsSum: 0,
    standardsCount: 0,
    standardDaysSum: 0,
    standardDaysCount: 0,
    actualDaysArray: [] as number[],
    warningThresholdsSum: 0,
    criticalThresholdsSum: 0,
    thresholdsCount: 0,
    carrierProduct: new Map<string, {
      carrier: string;
      product: string;
      total: number;
      compliant: number;
      standardsSum: number;
      standardsCount: number;
      standardDaysSum: number;
      standardDaysCount: number;
      actualDaysArray: number[];
    }>(),
  };
  
  routes.forEach(route => {
    result.totalShipments += route.totalShipments;
    result.compliantShipments += route.compliantShipments;
    result.standardsSum += route.standardsSum;
    result.standardsCount += route.standardsCount;
    result.standardDaysSum += route.standardDaysSum;
    result.standardDaysCount += route.standardDaysCount;
    result.actualDaysArray.push(...route.actualDaysArray);
    result.warningThresholdsSum += route.warningThresholdsSum;
    result.criticalThresholdsSum += route.criticalThresholdsSum;
    result.thresholdsCount += route.thresholdsCount;
    
    // Merge carrier/product data
    route.carrierProduct.forEach((cpData, key) => {
      if (!result.carrierProduct.has(key)) {
        result.carrierProduct.set(key, {
          carrier: cpData.carrier,
          product: cpData.product,
          total: 0,
          compliant: 0,
          standardsSum: 0,
          standardsCount: 0,
          standardDaysSum: 0,
          standardDaysCount: 0,
          actualDaysArray: [],
        });
      }
      
      const cp = result.carrierProduct.get(key)!;
      cp.total += cpData.total;
      cp.compliant += cpData.compliant;
      cp.standardsSum += cpData.standardsSum;
      cp.standardsCount += cpData.standardsCount;
      cp.standardDaysSum += cpData.standardDaysSum;
      cp.standardDaysCount += cpData.standardDaysCount;
      cp.actualDaysArray.push(...cpData.actualDaysArray);
    });
  });
  
  return result;
}

/**
 * Build carrier/product breakdown array from aggregated map
 */
function buildCarrierProductBreakdown(
  cpMap: Map<string, {
    carrier: string;
    product: string;
    total: number;
    compliant: number;
    standardsSum: number;
    standardsCount: number;
    standardDaysSum: number;
    standardDaysCount: number;
    actualDaysArray: number[];
  }>
) {
  return Array.from(cpMap.values()).map(cp => {
    const cpActualPct = cp.total > 0 ? (cp.compliant / cp.total) * 100 : 0;
    const cpStandardPct = cp.standardsCount > 0 ? cp.standardsSum / cp.standardsCount : 0;
    const cpStandardDays = cp.standardDaysCount > 0 ? cp.standardDaysSum / cp.standardDaysCount : 0;
    const cpActualDays = cp.actualDaysArray.length > 0
      ? cp.actualDaysArray.reduce((sum, d) => sum + d, 0) / cp.actualDaysArray.length
      : 0;
    
    return {
      carrier: cp.carrier,
      product: cp.product,
      totalShipments: cp.total,
      compliantShipments: cp.compliant,
      actualPercentage: cpActualPct,
      standardPercentage: cpStandardPct,
      standardDays: cpStandardDays,
      actualDays: cpActualDays,
      deviation: cpActualPct - cpStandardPct,
      inboundPercentage: cpActualPct,
      outboundPercentage: cpActualPct,
    };
  });
}

/**
 * Aggregate routes by region
 */
function aggregateRoutesByRegion(
  routes: RouteStats[],
  scenarioInfo: any,
  filters: TerritoryEquityFilters | undefined,
  warningThreshold: number,
  criticalThreshold: number
): RegionEquityData[] {
  const regionStatsMap = new Map<string, {
    regionName: string;
    cities: Set<string>;
    totalPopulation: number;
    totalShipments: number;
    compliantShipments: number;
    standardsSum: number;
    standardsCount: number;
    standardDaysSum: number;
    standardDaysCount: number;
    actualDaysArray: number[];
    underservedCities: number;
    inboundShipments: number;
    inboundCompliant: number;
    inboundStandardsSum: number;
    inboundStandardsCount: number;
    inboundStandardDaysSum: number;
    inboundStandardDaysCount: number;
    inboundActualDaysArray: number[];
    outboundShipments: number;
    outboundCompliant: number;
    outboundStandardsSum: number;
    outboundStandardsCount: number;
    outboundStandardDaysSum: number;
    outboundStandardDaysCount: number;
    outboundActualDaysArray: number[];
  }>();

  // Determine which direction to aggregate based on scenario
  const aggregateInbound = scenarioInfo.scenario !== 'destination';
  const aggregateOutbound = scenarioInfo.scenario !== 'origin';

  routes.forEach(route => {
    // Aggregate as inbound (by destination region)
    if (aggregateInbound) {
      const regionId = route.destinationRegionId;
      const regionName = route.destinationRegionName || 'Unknown';
      
      if (!regionStatsMap.has(regionId)) {
        regionStatsMap.set(regionId, {
          regionName,
          cities: new Set(),
          totalPopulation: 0,
          totalShipments: 0,
          compliantShipments: 0,
          standardsSum: 0,
          standardsCount: 0,
          standardDaysSum: 0,
          standardDaysCount: 0,
          actualDaysArray: [],
          underservedCities: 0,
          inboundShipments: 0,
          inboundCompliant: 0,
          inboundStandardsSum: 0,
          inboundStandardsCount: 0,
          inboundStandardDaysSum: 0,
          inboundStandardDaysCount: 0,
          inboundActualDaysArray: [],
          outboundShipments: 0,
          outboundCompliant: 0,
          outboundStandardsSum: 0,
          outboundStandardsCount: 0,
          outboundStandardDaysSum: 0,
          outboundStandardDaysCount: 0,
          outboundActualDaysArray: [],
        });
      }
      
      const regionStats = regionStatsMap.get(regionId)!;
      regionStats.cities.add(route.destinationCityId);
      regionStats.totalPopulation += route.destinationPopulation || 0;
      regionStats.inboundShipments += route.totalShipments;
      regionStats.inboundCompliant += route.compliantShipments;
      regionStats.inboundStandardsSum += route.standardsSum;
      regionStats.inboundStandardsCount += route.standardsCount;
      regionStats.inboundStandardDaysSum += route.standardDaysSum;
      regionStats.inboundStandardDaysCount += route.standardDaysCount;
      regionStats.inboundActualDaysArray.push(...route.actualDaysArray);
    }
    
    // Aggregate as outbound (by origin region)
    if (aggregateOutbound) {
      const regionId = route.originRegionId;
      const regionName = route.originRegionName || 'Unknown';
      
      if (!regionStatsMap.has(regionId)) {
        regionStatsMap.set(regionId, {
          regionName,
          cities: new Set(),
          totalPopulation: 0,
          totalShipments: 0,
          compliantShipments: 0,
          standardsSum: 0,
          standardsCount: 0,
          standardDaysSum: 0,
          standardDaysCount: 0,
          actualDaysArray: [],
          underservedCities: 0,
          inboundShipments: 0,
          inboundCompliant: 0,
          inboundStandardsSum: 0,
          inboundStandardsCount: 0,
          inboundStandardDaysSum: 0,
          inboundStandardDaysCount: 0,
          inboundActualDaysArray: [],
          outboundShipments: 0,
          outboundCompliant: 0,
          outboundStandardsSum: 0,
          outboundStandardsCount: 0,
          outboundStandardDaysSum: 0,
          outboundStandardDaysCount: 0,
          outboundActualDaysArray: [],
        });
      }
      
      const regionStats = regionStatsMap.get(regionId)!;
      regionStats.cities.add(route.originCityId);
      regionStats.totalPopulation += route.originPopulation || 0;
      regionStats.outboundShipments += route.totalShipments;
      regionStats.outboundCompliant += route.compliantShipments;
      regionStats.outboundStandardsSum += route.standardsSum;
      regionStats.outboundStandardsCount += route.standardsCount;
      regionStats.outboundStandardDaysSum += route.standardDaysSum;
      regionStats.outboundStandardDaysCount += route.standardDaysCount;
      regionStats.outboundActualDaysArray.push(...route.actualDaysArray);
    }
  });

  // Convert to RegionEquityData array
  const result: RegionEquityData[] = [];
  
  regionStatsMap.forEach((stats, regionId) => {
    // Calculate inbound metrics
    const inboundPercentage = stats.inboundShipments > 0
      ? (stats.inboundCompliant / stats.inboundShipments) * 100
      : 0;
    const inboundStandardPct = stats.inboundStandardsCount > 0
      ? stats.inboundStandardsSum / stats.inboundStandardsCount
      : 0;
    const inboundStandardDays = stats.inboundStandardDaysCount > 0
      ? stats.inboundStandardDaysSum / stats.inboundStandardDaysCount
      : 0;
    const inboundActualDays = stats.inboundActualDaysArray.length > 0
      ? stats.inboundActualDaysArray.reduce((sum, d) => sum + d, 0) / stats.inboundActualDaysArray.length
      : 0;
    const inboundDeviation = inboundPercentage - inboundStandardPct;
    
    // Calculate outbound metrics
    const outboundPercentage = stats.outboundShipments > 0
      ? (stats.outboundCompliant / stats.outboundShipments) * 100
      : 0;
    const outboundStandardPct = stats.outboundStandardsCount > 0
      ? stats.outboundStandardsSum / stats.outboundStandardsCount
      : 0;
    const outboundStandardDays = stats.outboundStandardDaysCount > 0
      ? stats.outboundStandardDaysSum / stats.outboundStandardDaysCount
      : 0;
    const outboundActualDays = stats.outboundActualDaysArray.length > 0
      ? stats.outboundActualDaysArray.reduce((sum, d) => sum + d, 0) / stats.outboundActualDaysArray.length
      : 0;
    const outboundDeviation = outboundPercentage - outboundStandardPct;
    
    // Overall metrics
    const totalShipments = stats.inboundShipments + stats.outboundShipments;
    const compliantShipments = stats.inboundCompliant + stats.outboundCompliant;
    const actualPercentage = totalShipments > 0
      ? (compliantShipments / totalShipments) * 100
      : 0;
    
    const standardPercentage = (inboundStandardPct + outboundStandardPct) / 2;
    const standardDays = (inboundStandardDays + outboundStandardDays) / 2;
    const actualDays = (inboundActualDays + outboundActualDays) / 2;
    const deviation = actualPercentage - standardPercentage;
    
    const status: 'compliant' | 'warning' | 'critical' =
      actualPercentage >= warningThreshold ? 'compliant' :
      actualPercentage >= criticalThreshold ? 'warning' : 'critical';
    
    result.push({
      regionId,
      regionName: stats.regionName,
      totalCities: stats.cities.size,
      totalPopulation: stats.totalPopulation,
      totalShipments,
      compliantShipments,
      standardPercentage,
      standardDays,
      actualDays,
      actualPercentage,
      deviation,
      status,
      aggregatedWarningThreshold: 80,
      aggregatedCriticalThreshold: 75,
      underservedCitiesCount: stats.underservedCities,
      
      inboundShipments: stats.inboundShipments,
      inboundCompliant: stats.inboundCompliant,
      inboundPercentage,
      inboundStandardPercentage: inboundStandardPct,
      inboundStandardDays,
      inboundActualDays,
      inboundDeviation,
      
      outboundShipments: stats.outboundShipments,
      outboundCompliant: stats.outboundCompliant,
      outboundPercentage,
      outboundStandardPercentage: outboundStandardPct,
      outboundStandardDays,
      outboundActualDays,
      outboundDeviation,
      
      directionGap: inboundPercentage - outboundPercentage,
      accountId: routes[0]?.accountId || '',
    });
  });

  return result;
}

/**
 * Calculate global metrics from route data
 */
function calculateGlobalMetrics(
  routes: RouteStats[],
  warningThreshold: number,
  criticalThreshold: number
): TerritoryEquityMetrics {
  // Aggregate all routes
  const aggregated = aggregateRoutes(routes);
  
  const totalShipments = aggregated.totalShipments;
  const compliantShipments = aggregated.compliantShipments;
  const actualPercentage = totalShipments > 0
    ? (compliantShipments / totalShipments) * 100
    : 0;
  
  const standardPercentage = aggregated.standardsCount > 0
    ? aggregated.standardsSum / aggregated.standardsCount
    : 0;
  
  const standardDays = aggregated.standardDaysCount > 0
    ? aggregated.standardDaysSum / aggregated.standardDaysCount
    : 0;
  
  const actualDays = aggregated.actualDaysArray.length > 0
    ? aggregated.actualDaysArray.reduce((sum, d) => sum + d, 0) / aggregated.actualDaysArray.length
    : 0;
  
  const deviation = actualPercentage - standardPercentage;
  
  // Calculate J+K Actual using the formula
  const jkActual = calculateJKActualFromDays(
    aggregated.actualDaysArray,
    standardPercentage,
    standardDays
  );
  
  return {
    serviceEquityIndex: 0, // Will be calculated from city data
    populationWeightedCompliance: 0, // Will be calculated from city data
    underservedCitiesCount: 0, // Will be calculated from city data
    citizensAffected: 0, // Will be calculated from city data
    topBestCities: [],
    topWorstCities: [],
    topBestRegions: [],
    topWorstRegions: [],
    totalCities: 0, // Will be calculated from city data
    totalPopulation: 0, // Will be calculated from city data
    totalRegions: 0, // Will be calculated from region data
  };
}
