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

export function useTerritoryEquityDataV2(
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

        // Global thresholds (fallback when SLA doesn't specify)
        const defaultWarningThreshold = globalWarningThreshold;
        const defaultCriticalThreshold = globalCriticalThreshold;

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
            // Distinguish between absolute and relative thresholds
            const warnThresh = s.threshold_type === 'absolute'
              ? (s.warning_threshold || 80)  // Absolute: use value directly
              : successPct - (s.warning_threshold || 5);  // Relative: subtract offset from STD%
            const critThresh = s.threshold_type === 'absolute'
              ? (s.critical_threshold || 75)  // Absolute: use value directly
              : successPct - (s.critical_threshold || 10);  // Relative: subtract offset from STD%
            return { warning: warnThresh, critical: critThresh };
          });
          warningThreshold = thresholds.reduce((sum, t) => sum + t.warning, 0) / thresholds.length;
          criticalThreshold = thresholds.reduce((sum, t) => sum + t.critical, 0) / thresholds.length;
        }
        setGlobalWarningThreshold(warningThreshold);
        setGlobalCriticalThreshold(criticalThreshold);
        console.log('[useTerritoryEquityData] Global thresholds:', { warning: warningThreshold, critical: criticalThreshold });

        // 3. Load shipments with filters and pagination
        const allShipments: any[] = []
        const pageSize = 1000
        let start = 0
        let hasMore = true

        while (hasMore) {
          let query = supabase.from('one_db').select('*').eq('account_id', activeAccountId).range(start, start + pageSize - 1)

          // Use same date filtering as ONE DB (no time adjustment)
          if (filters?.startDate && filters.startDate !== '') query = query.gte('sent_at', filters.startDate)
          if (filters?.endDate && filters.endDate !== '') query = query.lte('sent_at', filters.endDate)
          if (filters?.carrier) query = query.eq('carrier_name', filters.carrier)
          if (filters?.product) query = query.eq('product_name', filters.product)
          if (filters?.originCity) query = query.eq('origin_city_name', filters.originCity)
          if (filters?.destinationCity) query = query.eq('destination_city_name', filters.destinationCity)

          const { data, error: shipmentsError } = await query
          if (shipmentsError) throw shipmentsError

          if (data && data.length > 0) {
            allShipments.push(...data)
            hasMore = data.length === pageSize
            start += pageSize
          } else {
            hasMore = false
          }
        }

        const shipments = allShipments

        if (!shipments || shipments.length === 0) {
          setCityData([]);
          setRegionData([]);
          setMetrics({
            serviceEquityIndex: 0,
            populationWeightedCompliance: 0,
            underservedCitiesCount: 0,
            citizensAffected: 0,
            topBestCities: [],
            topWorstCities: [],
            totalCities: 0,
            totalPopulation: 0,
            totalRegions: 0,
          });
          return;
        }

        // 4. Aggregate by city (inbound/outbound)
        const cityStatsMap = new Map<
          string,
          {
            inbound: {
              total: number;
              compliant: number;
              standardsSum: number;
              standardsCount: number;
              standardDaysSum: number;
              standardDaysCount: number;
              actualDaysArray: number[];
              warningThresholdSum: number;
              warningThresholdCount: number;
              criticalThresholdSum: number;
              criticalThresholdCount: number;
            };
            outbound: {
              total: number;
              compliant: number;
              standardsSum: number;
              standardsCount: number;
              standardDaysSum: number;
              standardDaysCount: number;
              actualDaysArray: number[];
              warningThresholdSum: number;
              warningThresholdCount: number;
              criticalThresholdSum: number;
              criticalThresholdCount: number;
            };
            standardsSum: number;
            standardsCount: number;
            standardDaysSum: number;
            standardDaysCount: number;
            actualDaysArray: number[];
            warningThresholdSum: number;
            warningThresholdCount: number;
            criticalThresholdSum: number;
            criticalThresholdCount: number;
            carrierProduct: Map<string, { 
              carrier: string; 
              product: string; 
              total: number; 
              compliant: number;
              inbound: { total: number; compliant: number };
              outbound: { total: number; compliant: number };
              standardsSum: number;
              standardsCount: number;
              standardDaysSum: number;
              standardDaysCount: number;
              actualDaysArray: number[];
            }>;
          }
        >();

        shipments.forEach((shipment) => {
          // Process as INBOUND (destination)
          const destCity = shipment.destination_city_name;
          if (!cityStatsMap.has(destCity)) {
            cityStatsMap.set(destCity, {
              inbound: { 
                total: 0, 
                compliant: 0,
                standardsSum: 0,
                standardsCount: 0,
                standardDaysSum: 0,
                standardDaysCount: 0,
                actualDaysArray: [],
                warningThresholdSum: 0,
                warningThresholdCount: 0,
                criticalThresholdSum: 0,
                criticalThresholdCount: 0,
              },
              outbound: { 
                total: 0, 
                compliant: 0,
                standardsSum: 0,
                standardsCount: 0,
                standardDaysSum: 0,
                standardDaysCount: 0,
                actualDaysArray: [],
                warningThresholdSum: 0,
                warningThresholdCount: 0,
                criticalThresholdSum: 0,
                criticalThresholdCount: 0,
              },
              standardsSum: 0,
              standardsCount: 0,
              standardDaysSum: 0,
              standardDaysCount: 0,
              actualDaysArray: [],
              warningThresholdSum: 0,
              warningThresholdCount: 0,
              criticalThresholdSum: 0,
              criticalThresholdCount: 0,
              carrierProduct: new Map(),
            });
          }

          const destStats = cityStatsMap.get(destCity)!;
          destStats.inbound.total++;
          if (shipment.on_time_delivery) destStats.inbound.compliant++;
          
          // Track carrier/product breakdown for destination
          const cpKey = `${shipment.carrier_name}|${shipment.product_name}`;
          if (!destStats.carrierProduct.has(cpKey)) {
            destStats.carrierProduct.set(cpKey, {
              carrier: shipment.carrier_name,
              product: shipment.product_name,
              total: 0,
              compliant: 0,
              inbound: { total: 0, compliant: 0 },
              outbound: { total: 0, compliant: 0 },
              standardsSum: 0,
              standardsCount: 0,
              standardDaysSum: 0,
              standardDaysCount: 0,
              actualDaysArray: [],
            });
          }
          const cpStats = destStats.carrierProduct.get(cpKey)!;
          cpStats.total++;
          cpStats.inbound.total++;
          if (shipment.on_time_delivery) {
            cpStats.compliant++;
            cpStats.inbound.compliant++;
          }
          
          // Lookup IDs for standard
          const carrierId = carrierNameToIdMap.get(shipment.carrier_name);
          const productId = productDescToIdMap.get(shipment.product_name);
          const originCityId = cityNameToIdMap.get(shipment.origin_city_name);
          const destCityId = cityNameToIdMap.get(shipment.destination_city_name);
          
          // Add standard for this carrier/product
          if (carrierId && productId && originCityId && destCityId) {
            const key = `${carrierId}|${productId}|${originCityId}|${destCityId}`;
            const standard = standardsMap.get(key);
            if (standard) {
              if (standard.success_percentage) {
                cpStats.standardsSum += standard.success_percentage;
                cpStats.standardsCount++;
              }
              // Convert standard_time to days based on time_unit
              if (standard.standard_time != null) {
                const allowedDays = standard.time_unit === 'days' 
                  ? standard.standard_time 
                  : (standard.standard_time / 24);
                cpStats.standardDaysSum += allowedDays;
                cpStats.standardDaysCount++;
              }
            }
          }
          
          // Track actual business days for this shipment
          if (shipment.business_transit_days != null) {
            cpStats.actualDaysArray.push(shipment.business_transit_days);
          }

          // Also add to city-level standard (overall + inbound-specific)
          if (carrierId && productId && originCityId && destCityId) {
            const key = `${carrierId}|${productId}|${originCityId}|${destCityId}`;
            const standard = standardsMap.get(key);
            if (standard) {
              if (standard.success_percentage) {
                destStats.standardsSum += standard.success_percentage;
                destStats.standardsCount++;
                destStats.inbound.standardsSum += standard.success_percentage;
                destStats.inbound.standardsCount++;
              }
              // Convert standard_time to days based on time_unit
              if (standard.standard_time != null) {
                const allowedDays = standard.time_unit === 'days' 
                  ? standard.standard_time 
                  : (standard.standard_time / 24);
                destStats.standardDaysSum += allowedDays;
                destStats.standardDaysCount++;
                destStats.inbound.standardDaysSum += allowedDays;
                destStats.inbound.standardDaysCount++;
              }
              // Distinguish between absolute and relative thresholds
              const successPct = standard.success_percentage || 95;
              const warnThresh = standard.threshold_type === 'absolute'
                ? (standard.warning_threshold || 80)  // Absolute: use value directly
                : successPct - (standard.warning_threshold || 5);  // Relative: subtract offset from STD%
              const critThresh = standard.threshold_type === 'absolute'
                ? (standard.critical_threshold || 75)  // Absolute: use value directly
                : successPct - (standard.critical_threshold || 10);  // Relative: subtract offset from STD%
              destStats.warningThresholdSum += warnThresh;
              destStats.warningThresholdCount++;
              destStats.criticalThresholdSum += critThresh;
              destStats.criticalThresholdCount++;
              destStats.inbound.warningThresholdSum += warnThresh;
              destStats.inbound.warningThresholdCount++;
              destStats.inbound.criticalThresholdSum += critThresh;
              destStats.inbound.criticalThresholdCount++;
            }
          }
          
          // Track actual business days at city level (overall + inbound-specific)
          if (shipment.business_transit_days != null) {
            destStats.actualDaysArray.push(shipment.business_transit_days);
            destStats.inbound.actualDaysArray.push(shipment.business_transit_days);
          }

          // Process as OUTBOUND (origin)
          const originCity = shipment.origin_city_name;
          if (!cityStatsMap.has(originCity)) {
            cityStatsMap.set(originCity, {
              inbound: { 
                total: 0, 
                compliant: 0,
                standardsSum: 0,
                standardsCount: 0,
                standardDaysSum: 0,
                standardDaysCount: 0,
                actualDaysArray: [],
                warningThresholdSum: 0,
                warningThresholdCount: 0,
                criticalThresholdSum: 0,
                criticalThresholdCount: 0,
              },
              outbound: { 
                total: 0, 
                compliant: 0,
                standardsSum: 0,
                standardsCount: 0,
                standardDaysSum: 0,
                standardDaysCount: 0,
                actualDaysArray: [],
                warningThresholdSum: 0,
                warningThresholdCount: 0,
                criticalThresholdSum: 0,
                criticalThresholdCount: 0,
              },
              standardsSum: 0,
              standardsCount: 0,
              standardDaysSum: 0,
              standardDaysCount: 0,
              actualDaysArray: [],
              warningThresholdSum: 0,
              warningThresholdCount: 0,
              criticalThresholdSum: 0,
              criticalThresholdCount: 0,
              carrierProduct: new Map(),
            });
          }

          const originStats = cityStatsMap.get(originCity)!;
          originStats.outbound.total++;
          if (shipment.on_time_delivery) originStats.outbound.compliant++;
          
          // Track carrier/product breakdown for origin
          const cpKeyOrigin = `${shipment.carrier_name}|${shipment.product_name}`;
          if (!originStats.carrierProduct.has(cpKeyOrigin)) {
            originStats.carrierProduct.set(cpKeyOrigin, {
              carrier: shipment.carrier_name,
              product: shipment.product_name,
              total: 0,
              compliant: 0,
              inbound: { total: 0, compliant: 0 },
              outbound: { total: 0, compliant: 0 },
              standardsSum: 0,
              standardsCount: 0,
              standardDaysSum: 0,
              standardDaysCount: 0,
              actualDaysArray: [],
            });
          }
          const cpStatsOrigin = originStats.carrierProduct.get(cpKeyOrigin)!;
          cpStatsOrigin.total++;
          cpStatsOrigin.outbound.total++;
          if (shipment.on_time_delivery) {
            cpStatsOrigin.compliant++;
            cpStatsOrigin.outbound.compliant++;
          }
          
          // Add standard for this carrier/product (outbound)
          const carrierIdOut = carrierNameToIdMap.get(shipment.carrier_name);
          const productIdOut = productDescToIdMap.get(shipment.product_name);
          const originCityIdOut = cityNameToIdMap.get(shipment.origin_city_name);
          const destCityIdOut = cityNameToIdMap.get(shipment.destination_city_name);
          
          if (carrierIdOut && productIdOut && originCityIdOut && destCityIdOut) {
            const keyOut = `${carrierIdOut}|${productIdOut}|${originCityIdOut}|${destCityIdOut}`;
            const standardOut = standardsMap.get(keyOut);
            if (standardOut) {
              if (standardOut.success_percentage) {
                cpStatsOrigin.standardsSum += standardOut.success_percentage;
                cpStatsOrigin.standardsCount++;
              }
              // Convert standard_time to days based on time_unit
              if (standardOut.standard_time != null) {
                const allowedDays = standardOut.time_unit === 'days' 
                  ? standardOut.standard_time 
                  : (standardOut.standard_time / 24);
                cpStatsOrigin.standardDaysSum += allowedDays;
                cpStatsOrigin.standardDaysCount++;
              }
            }
          }
          
          // Also add outbound standards to origin city
          if (carrierIdOut && productIdOut && originCityIdOut && destCityIdOut) {
            const keyOut = `${carrierIdOut}|${productIdOut}|${originCityIdOut}|${destCityIdOut}`;
            const standardOut = standardsMap.get(keyOut);
            if (standardOut) {
              if (standardOut.success_percentage) {
                originStats.outbound.standardsSum += standardOut.success_percentage;
                originStats.outbound.standardsCount++;
              }
              if (standardOut.standard_time != null) {
                const allowedDays = standardOut.time_unit === 'days' 
                  ? standardOut.standard_time 
                  : (standardOut.standard_time / 24);
                originStats.outbound.standardDaysSum += allowedDays;
                originStats.outbound.standardDaysCount++;
              }
              // Distinguish between absolute and relative thresholds
              const successPctOut = standardOut.success_percentage || 95;
              const warnThreshOut = standardOut.threshold_type === 'absolute'
                ? (standardOut.warning_threshold || 80)  // Absolute: use value directly
                : successPctOut - (standardOut.warning_threshold || 5);  // Relative: subtract offset from STD%
              const critThreshOut = standardOut.threshold_type === 'absolute'
                ? (standardOut.critical_threshold || 75)  // Absolute: use value directly
                : successPctOut - (standardOut.critical_threshold || 10);  // Relative: subtract offset from STD%
              originStats.outbound.warningThresholdSum += warnThreshOut;
              originStats.outbound.warningThresholdCount++;
              originStats.outbound.criticalThresholdSum += critThreshOut;
              originStats.outbound.criticalThresholdCount++;
            }
          }
          
          // Track actual business days for outbound shipment (overall + outbound-specific)
          if (shipment.business_transit_days != null) {
            cpStatsOrigin.actualDaysArray.push(shipment.business_transit_days);
            originStats.actualDaysArray.push(shipment.business_transit_days);
            originStats.outbound.actualDaysArray.push(shipment.business_transit_days);
          }
        });

        // 5. Build CityEquityData array
        const cityEquityData: CityEquityData[] = Array.from(cityStatsMap.entries())
          .map(([cityName, stats]) => {
            const city = cityMap.get(cityName);
            if (!city) return null;

            const cityId = city.id;
            const regionId = city.region_id;
            const regionName = city.region_name;
            const classification = city.classification || null;
            const population = city.population || null;
            const latitude = city.latitude || null;
            const longitude = city.longitude || null;

            // Determine which direction to use based on scenario
            let totalShipments: number;
            let compliantShipments: number;
            let actualPercentage: number;
            let standardPercentage: number;
            let standardDays: number;
            let actualDays: number;
            let deviation: number;

            if (scenarioInfo.isOriginView) {
              // Origin view: show INBOUND data (city as destination)
              totalShipments = stats.inbound.total;
              compliantShipments = stats.inbound.compliant;
              actualPercentage = totalShipments > 0 ? (compliantShipments / totalShipments) * 100 : 0;
              standardPercentage = stats.inbound.standardsCount > 0 ? stats.inbound.standardsSum / stats.inbound.standardsCount : 95;
              standardDays = stats.inbound.standardDaysCount > 0 ? stats.inbound.standardDaysSum / stats.inbound.standardDaysCount : 0;
              actualDays = calculateJKActualFromDays(
                stats.inbound.actualDaysArray,
                standardPercentage,
                standardDays
              );
              deviation = actualPercentage - standardPercentage;
            } else if (scenarioInfo.isDestinationView) {
              // Destination view: show OUTBOUND data (city as origin)
              totalShipments = stats.outbound.total;
              compliantShipments = stats.outbound.compliant;
              actualPercentage = totalShipments > 0 ? (compliantShipments / totalShipments) * 100 : 0;
              standardPercentage = stats.outbound.standardsCount > 0 ? stats.outbound.standardsSum / stats.outbound.standardsCount : 95;
              standardDays = stats.outbound.standardDaysCount > 0 ? stats.outbound.standardDaysSum / stats.outbound.standardDaysCount : 0;
              actualDays = calculateJKActualFromDays(
                stats.outbound.actualDaysArray,
                standardPercentage,
                standardDays
              );
              deviation = actualPercentage - standardPercentage;
            } else {
              // General view or route view: show OUTBOUND data (default)
              totalShipments = stats.outbound.total;
              compliantShipments = stats.outbound.compliant;
              actualPercentage = totalShipments > 0 ? (compliantShipments / totalShipments) * 100 : 0;
              standardPercentage = stats.outbound.standardsCount > 0 ? stats.outbound.standardsSum / stats.outbound.standardsCount : 95;
              standardDays = stats.outbound.standardDaysCount > 0 ? stats.outbound.standardDaysSum / stats.outbound.standardDaysCount : 0;
              actualDays = calculateJKActualFromDays(
                stats.outbound.actualDaysArray,
                standardPercentage,
                standardDays
              );
              deviation = actualPercentage - standardPercentage;
            }

            // Calculate aggregated thresholds (weighted average)
            const aggregatedWarningThreshold = stats.warningThresholdCount > 0
              ? stats.warningThresholdSum / stats.warningThresholdCount
              : defaultWarningThreshold;
            const aggregatedCriticalThreshold = stats.criticalThresholdCount > 0
              ? stats.criticalThresholdSum / stats.criticalThresholdCount
              : defaultCriticalThreshold;

            // Determine status using same logic as E2E module
            const status: 'compliant' | 'warning' | 'critical' =
              actualPercentage >= aggregatedWarningThreshold ? 'compliant' :
              actualPercentage >= aggregatedCriticalThreshold ? 'warning' : 'critical';

            // Inbound metrics
            const inboundPercentage =
              stats.inbound.total > 0 ? (stats.inbound.compliant / stats.inbound.total) * 100 : 0;
            const inboundStandardPercentage =
              stats.inbound.standardsCount > 0 ? stats.inbound.standardsSum / stats.inbound.standardsCount : 95;
            const inboundStandardDays =
              stats.inbound.standardDaysCount > 0 ? stats.inbound.standardDaysSum / stats.inbound.standardDaysCount : 0;
            const inboundActualDays = calculateJKActualFromDays(
              stats.inbound.actualDaysArray,
              inboundStandardPercentage,
              inboundStandardDays
            );
            const inboundDeviation = inboundPercentage - inboundStandardPercentage;
            
            // Outbound metrics
            const outboundPercentage =
              stats.outbound.total > 0 ? (stats.outbound.compliant / stats.outbound.total) * 100 : 0;
            const outboundStandardPercentage =
              stats.outbound.standardsCount > 0 ? stats.outbound.standardsSum / stats.outbound.standardsCount : 95;
            const outboundStandardDays =
              stats.outbound.standardDaysCount > 0 ? stats.outbound.standardDaysSum / stats.outbound.standardDaysCount : 0;
            const outboundActualDays = calculateJKActualFromDays(
              stats.outbound.actualDaysArray,
              outboundStandardPercentage,
              outboundStandardDays
            );
            const outboundDeviation = outboundPercentage - outboundStandardPercentage;
            
            const directionGap = Math.abs(inboundPercentage - outboundPercentage);

            // Build carrier/product breakdown
            const carrierProductBreakdown = Array.from(stats.carrierProduct.values()).map(cp => {
              const cpActualPercentage = cp.total > 0 ? (cp.compliant / cp.total) * 100 : 0;
              const cpStandardPercentage = cp.standardsCount > 0 ? cp.standardsSum / cp.standardsCount : 95;
              const cpStandardDays = cp.standardDaysCount > 0 ? cp.standardDaysSum / cp.standardDaysCount : 0;
              const cpActualDays = calculateJKActualFromDays(
                cp.actualDaysArray,
                cpStandardPercentage,
                cpStandardDays
              );
              const cpInboundPercentage = cp.inbound.total > 0 ? (cp.inbound.compliant / cp.inbound.total) * 100 : 0;
              const cpOutboundPercentage = cp.outbound.total > 0 ? (cp.outbound.compliant / cp.outbound.total) * 100 : 0;
              
              return {
                carrier: cp.carrier,
                product: cp.product,
                totalShipments: cp.total,
                compliantShipments: cp.compliant,
                actualPercentage: cpActualPercentage,
                standardPercentage: cpStandardPercentage,
                standardDays: cpStandardDays,
                actualDays: cpActualDays,
                deviation: cpActualPercentage - cpStandardPercentage,
                inboundPercentage: cpInboundPercentage,
                outboundPercentage: cpOutboundPercentage,
              };
            }).sort((a, b) => b.totalShipments - a.totalShipments);

            return {
              cityId,
              cityName,
              regionId,
              regionName,
              classification,
              population,
              latitude,
              longitude,
              totalShipments,
              compliantShipments,
              standardPercentage,
              standardDays,
              actualDays,
              actualPercentage,
              deviation,
              status,
              aggregatedWarningThreshold,
              aggregatedCriticalThreshold,
              inboundShipments: stats.inbound.total,
              inboundCompliant: stats.inbound.compliant,
              inboundPercentage,
              inboundStandardPercentage,
              inboundStandardDays,
              inboundActualDays,
              inboundDeviation,
              outboundShipments: stats.outbound.total,
              outboundCompliant: stats.outbound.compliant,
              outboundPercentage,
              outboundStandardPercentage,
              outboundStandardDays,
              outboundActualDays,
              outboundDeviation,
              directionGap,
              carrierProductBreakdown,
              accountId,
            };
          })
          .filter((c) => c !== null) as CityEquityData[];

        // 6. Apply filters (Direction, Equity Status, Region)
        let filteredCityData = cityEquityData;

        if (filters?.direction && filters.direction !== 'both') {
          // This filter affects which shipments are counted, not which cities are shown
          // For simplicity, we'll keep all cities but note this in UI
        }

        if (filters?.equityStatus && filters.equityStatus.length > 0) {
          filteredCityData = filteredCityData.filter((c) => filters.equityStatus!.includes(c.status));
        }

        if (filters?.region) {
          filteredCityData = filteredCityData.filter((c) => c.regionName === filters.region);
        }

        // Filter cities based on scenario to exclude origin/destination city from metrics
        if (scenarioInfo.isRouteView && filters?.originCity && filters?.destinationCity) {
          // For route view, only show the two cities involved in the route
          filteredCityData = filteredCityData.filter((c) => 
            c.cityName === filters.originCity || c.cityName === filters.destinationCity
          );
        } else if (scenarioInfo.isOriginView && filters?.originCity) {
          // Exclude origin city, show only destinations
          filteredCityData = filteredCityData.filter((c) => c.cityName !== filters.originCity);
        } else if (scenarioInfo.isDestinationView && filters?.destinationCity) {
          // Exclude destination city, show only origins
          filteredCityData = filteredCityData.filter((c) => c.cityName !== filters.destinationCity);
        }

        // 7. Calculate metrics
        const totalCities = filteredCityData.length;
        const totalPopulation = filteredCityData.reduce((sum, c) => sum + (c.population || 0), 0);
        const totalRegions = new Set(filteredCityData.map((c) => c.regionId)).size;

        const underservedCitiesCount = filteredCityData.filter((c) => c.status === 'critical').length;
        const citizensAffected = filteredCityData
          .filter((c) => c.status === 'critical')
          .reduce((sum, c) => sum + (c.population || 0), 0);

        // Service Equity Index (population-weighted std dev)
        const weightedMean =
          totalPopulation > 0
            ? filteredCityData.reduce((sum, c) => {
                const weight = (c.population || 0) / totalPopulation;
                return sum + c.actualPercentage * weight;
              }, 0)
            : 0;

        const weightedVariance =
          totalPopulation > 0
            ? filteredCityData.reduce((sum, c) => {
                const weight = (c.population || 0) / totalPopulation;
                return sum + Math.pow(c.actualPercentage - weightedMean, 2) * weight;
              }, 0)
            : 0;

        const weightedStdDev = Math.sqrt(weightedVariance);
        const serviceEquityIndex = Math.max(0, Math.min(100, 100 - weightedStdDev * 10));

        // Population-Weighted Compliance
        const populationWeightedCompliance =
          totalPopulation > 0
            ? filteredCityData.reduce((sum, c) => {
                const weight = (c.population || 0) / totalPopulation;
                return sum + c.actualPercentage * weight;
              }, 0)
            : 0;

        // Top 3 Best/Worst Cities
        const sortedByDeviation = [...filteredCityData].sort((a, b) => b.deviation - a.deviation);
        const topBestCities = sortedByDeviation.slice(0, 3).map((c) => ({
          cityName: c.cityName,
          actualPercentage: c.actualPercentage,
          deviation: c.deviation,
          standardPercentage: c.standardPercentage,
          standardDays: c.standardDays,
          actualDays: c.actualDays,
          inboundPercentage: c.inboundPercentage,
          outboundPercentage: c.outboundPercentage,
        }));
        const topWorstCities = sortedByDeviation
          .slice(-3)
          .reverse()
          .map((c) => ({
            cityName: c.cityName,
            actualPercentage: c.actualPercentage,
            deviation: c.deviation,
            standardPercentage: c.standardPercentage,
            standardDays: c.standardDays,
            actualDays: c.actualDays,
            inboundPercentage: c.inboundPercentage,
            outboundPercentage: c.outboundPercentage,
            status: c.status,
          }));

        // 8. Aggregate by region
        const regionStatsMap = new Map<
          string,
          {
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
            warningThresholdSum: number;
            warningThresholdCount: number;
            criticalThresholdSum: number;
            criticalThresholdCount: number;
            underservedCities: number;
            inboundShipments: number;
            inboundCompliant: number;
            inboundStandardsSum: number;
            inboundStandardsCount: number;
            inboundStandardDaysSum: number;
            inboundStandardDaysCount: number;
            inboundActualDaysArray: number[];
            inboundWarningThresholdSum: number;
            inboundWarningThresholdCount: number;
            inboundCriticalThresholdSum: number;
            inboundCriticalThresholdCount: number;
            outboundShipments: number;
            outboundCompliant: number;
            outboundStandardsSum: number;
            outboundStandardsCount: number;
            outboundStandardDaysSum: number;
            outboundStandardDaysCount: number;
            outboundActualDaysArray: number[];
            outboundWarningThresholdSum: number;
            outboundWarningThresholdCount: number;
            outboundCriticalThresholdSum: number;
            outboundCriticalThresholdCount: number;
            carrierProduct: Map<string, { 
              carrier: string; 
              product: string; 
              total: number; 
              compliant: number;
              inbound: { total: number; compliant: number };
              outbound: { total: number; compliant: number };
              standardsSum: number;
              standardsCount: number;
              standardDaysSum: number;
              standardDaysCount: number;
              actualDaysArray: number[];
            }>;
          }
        >();

        filteredCityData.forEach((city) => {
          if (!regionStatsMap.has(city.regionId)) {
            regionStatsMap.set(city.regionId, {
              regionName: city.regionName || 'Unknown',
              cities: new Set(),
              totalPopulation: 0,
              totalShipments: 0,
              compliantShipments: 0,
              standardsSum: 0,
              standardsCount: 0,
              standardDaysSum: 0,
              standardDaysCount: 0,
              actualDaysArray: [],
              warningThresholdSum: 0,
              warningThresholdCount: 0,
              criticalThresholdSum: 0,
              criticalThresholdCount: 0,
              underservedCities: 0,
              inboundShipments: 0,
              inboundCompliant: 0,
              inboundStandardsSum: 0,
              inboundStandardsCount: 0,
              inboundStandardDaysSum: 0,
              inboundStandardDaysCount: 0,
              inboundActualDaysArray: [],
              inboundWarningThresholdSum: 0,
              inboundWarningThresholdCount: 0,
              inboundCriticalThresholdSum: 0,
              inboundCriticalThresholdCount: 0,
              outboundShipments: 0,
              outboundCompliant: 0,
              outboundStandardsSum: 0,
              outboundStandardsCount: 0,
              outboundStandardDaysSum: 0,
              outboundStandardDaysCount: 0,
              outboundActualDaysArray: [],
              outboundWarningThresholdSum: 0,
              outboundWarningThresholdCount: 0,
              outboundCriticalThresholdSum: 0,
              outboundCriticalThresholdCount: 0,
              carrierProduct: new Map(),
            });
          }

          const regionStats = regionStatsMap.get(city.regionId)!;
          regionStats.cities.add(city.cityId);
          regionStats.totalPopulation += city.population || 0;
          regionStats.totalShipments += city.totalShipments;
          regionStats.compliantShipments += city.compliantShipments;
          regionStats.standardsSum += city.standardPercentage * city.totalShipments;
          regionStats.standardsCount += city.totalShipments;
          regionStats.standardDaysSum += city.standardDays * city.totalShipments;
          regionStats.standardDaysCount += city.totalShipments;
          // Accumulate thresholds (weighted by total shipments)
          regionStats.warningThresholdSum += city.aggregatedWarningThreshold * city.totalShipments;
          regionStats.warningThresholdCount += city.totalShipments;
          regionStats.criticalThresholdSum += city.aggregatedCriticalThreshold * city.totalShipments;
          regionStats.criticalThresholdCount += city.totalShipments;
          // Replicate actualDays for weighted aggregation
          for (let i = 0; i < city.totalShipments; i++) {
            regionStats.actualDaysArray.push(city.actualDays);
          }
          regionStats.inboundShipments += city.inboundShipments;
          regionStats.inboundCompliant += city.inboundCompliant;
          regionStats.inboundStandardsSum += city.inboundStandardPercentage * city.inboundShipments;
          regionStats.inboundStandardsCount += city.inboundShipments;
          regionStats.inboundStandardDaysSum += city.inboundStandardDays * city.inboundShipments;
          regionStats.inboundStandardDaysCount += city.inboundShipments;
          for (let i = 0; i < city.inboundShipments; i++) {
            regionStats.inboundActualDaysArray.push(city.inboundActualDays);
          }
          regionStats.outboundShipments += city.outboundShipments;
          regionStats.outboundCompliant += city.outboundCompliant;
          regionStats.outboundStandardsSum += city.outboundStandardPercentage * city.outboundShipments;
          regionStats.outboundStandardsCount += city.outboundShipments;
          regionStats.outboundStandardDaysSum += city.outboundStandardDays * city.outboundShipments;
          regionStats.outboundStandardDaysCount += city.outboundShipments;
          for (let i = 0; i < city.outboundShipments; i++) {
            regionStats.outboundActualDaysArray.push(city.outboundActualDays);
          }
          if (city.status === 'critical') regionStats.underservedCities++;
          
          // Aggregate carrier/product breakdown
          if (city.carrierProductBreakdown) {
            city.carrierProductBreakdown.forEach(cp => {
              const cpKey = `${cp.carrier}|${cp.product}`;
              if (!regionStats.carrierProduct.has(cpKey)) {
                regionStats.carrierProduct.set(cpKey, {
                  carrier: cp.carrier,
                  product: cp.product,
                  total: 0,
                  compliant: 0,
                  inbound: { total: 0, compliant: 0 },
                  outbound: { total: 0, compliant: 0 },
                  standardsSum: 0,
                  standardsCount: 0,
                  standardDaysSum: 0,
                  standardDaysCount: 0,
                  actualDaysArray: [],
            });
              }
              const cpStats = regionStats.carrierProduct.get(cpKey)!;
              cpStats.total += cp.totalShipments;
              cpStats.compliant += cp.compliantShipments;
              cpStats.inbound.total += cp.totalShipments * (cp.inboundPercentage / 100);
              cpStats.inbound.compliant += cp.compliantShipments * (cp.inboundPercentage / 100);
              cpStats.outbound.total += cp.totalShipments * (cp.outboundPercentage / 100);
              cpStats.outbound.compliant += cp.compliantShipments * (cp.outboundPercentage / 100);
              cpStats.standardsSum += cp.standardPercentage;
              cpStats.standardsCount++;
              cpStats.standardDaysSum += cp.standardDays;
              cpStats.standardDaysCount++;
              for (let i = 0; i < cp.totalShipments; i++) {
                cpStats.actualDaysArray.push(cp.actualDays);
              }
            });
          }
        });

        const regionEquityData: RegionEquityData[] = Array.from(regionStatsMap.entries()).map(
          ([regionId, stats]) => {
            const actualPercentage =
              stats.totalShipments > 0 ? (stats.compliantShipments / stats.totalShipments) * 100 : 0;
            const standardPercentage =
              stats.standardsCount > 0 ? stats.standardsSum / stats.standardsCount : 95;
            const standardDays =
              stats.standardDaysCount > 0 ? stats.standardDaysSum / stats.standardDaysCount : 0;
            const actualDays = calculateJKActualFromDays(
              stats.actualDaysArray,
              standardPercentage,
              standardDays
            );
            const deviation = actualPercentage - standardPercentage;

            // Calculate aggregated thresholds (weighted average)
            const aggregatedWarningThreshold = stats.warningThresholdCount > 0
              ? stats.warningThresholdSum / stats.warningThresholdCount
              : defaultWarningThreshold;
            const aggregatedCriticalThreshold = stats.criticalThresholdCount > 0
              ? stats.criticalThresholdSum / stats.criticalThresholdCount
              : defaultCriticalThreshold;

            // Determine status using same logic as E2E module
            const status: 'compliant' | 'warning' | 'critical' =
              actualPercentage >= aggregatedWarningThreshold ? 'compliant' :
              actualPercentage >= aggregatedCriticalThreshold ? 'warning' : 'critical';

            // Inbound metrics
            const inboundPercentage = stats.inboundShipments > 0 
              ? (stats.inboundCompliant / stats.inboundShipments) * 100 
              : 0;
            const inboundStandardPercentage = stats.inboundStandardsCount > 0
              ? stats.inboundStandardsSum / stats.inboundStandardsCount
              : 95;
            const inboundStandardDays = stats.inboundStandardDaysCount > 0
              ? stats.inboundStandardDaysSum / stats.inboundStandardDaysCount
              : 0;
            const inboundActualDays = calculateJKActualFromDays(
              stats.inboundActualDaysArray,
              inboundStandardPercentage,
              inboundStandardDays
            );
            const inboundDeviation = inboundPercentage - inboundStandardPercentage;
            
            // Outbound metrics
            const outboundPercentage = stats.outboundShipments > 0 
              ? (stats.outboundCompliant / stats.outboundShipments) * 100 
              : 0;
            const outboundStandardPercentage = stats.outboundStandardsCount > 0
              ? stats.outboundStandardsSum / stats.outboundStandardsCount
              : 95;
            const outboundStandardDays = stats.outboundStandardDaysCount > 0
              ? stats.outboundStandardDaysSum / stats.outboundStandardDaysCount
              : 0;
            const outboundActualDays = calculateJKActualFromDays(
              stats.outboundActualDaysArray,
              outboundStandardPercentage,
              outboundStandardDays
            );
            const outboundDeviation = outboundPercentage - outboundStandardPercentage;
            
            const directionGap = Math.abs(inboundPercentage - outboundPercentage);

            // Build carrier/product breakdown
            const carrierProductBreakdown = Array.from(stats.carrierProduct.values()).map(cp => {
              const cpActualPercentage = cp.total > 0 ? (cp.compliant / cp.total) * 100 : 0;
              const cpStandardPercentage = cp.standardsCount > 0 ? cp.standardsSum / cp.standardsCount : 95;
              const cpStandardDays = cp.standardDaysCount > 0 ? cp.standardDaysSum / cp.standardDaysCount : 0;
              const cpActualDays = calculateJKActualFromDays(
                cp.actualDaysArray,
                cpStandardPercentage,
                cpStandardDays
              );
              const cpInboundPercentage = cp.inbound.total > 0 ? (cp.inbound.compliant / cp.inbound.total) * 100 : 0;
              const cpOutboundPercentage = cp.outbound.total > 0 ? (cp.outbound.compliant / cp.outbound.total) * 100 : 0;
              
              return {
                carrier: cp.carrier,
                product: cp.product,
                totalShipments: cp.total,
                compliantShipments: cp.compliant,
                actualPercentage: cpActualPercentage,
                standardPercentage: cpStandardPercentage,
                standardDays: cpStandardDays,
                actualDays: cpActualDays,
                deviation: cpActualPercentage - cpStandardPercentage,
                inboundPercentage: cpInboundPercentage,
                outboundPercentage: cpOutboundPercentage,
              };
            }).sort((a, b) => b.totalShipments - a.totalShipments);

            return {
              regionId,
              regionName: stats.regionName,
              totalCities: stats.cities.size,
              totalPopulation: stats.totalPopulation,
              totalShipments: stats.totalShipments,
              compliantShipments: stats.compliantShipments,
              standardPercentage,
              standardDays,
              actualDays,
              actualPercentage,
              deviation,
              status,
              aggregatedWarningThreshold,
              aggregatedCriticalThreshold,
              underservedCitiesCount: stats.underservedCities,
              inboundShipments: stats.inboundShipments,
              inboundCompliant: stats.inboundCompliant,
              inboundPercentage,
              inboundStandardPercentage,
              inboundStandardDays,
              inboundActualDays,
              inboundDeviation,
              outboundShipments: stats.outboundShipments,
              outboundCompliant: stats.outboundCompliant,
              outboundPercentage,
              outboundStandardPercentage,
              outboundStandardDays,
              outboundActualDays,
              outboundDeviation,
              directionGap,
              carrierProductBreakdown,
              accountId: accountId!,
            };
          }
        );

        // 9. Set state
        setCityData(filteredCityData);
        
        // RegionData is NOT filtered - treemap always shows all regions
        setRegionData(regionEquityData);
        setMetrics({
          serviceEquityIndex,
          populationWeightedCompliance,
          underservedCitiesCount,
          citizensAffected,
          topBestCities,
          topWorstCities,
          totalCities,
          totalPopulation,
          totalRegions,
        });
      } catch (err) {
        console.error('Error fetching territory equity data:', err);
        setError(err as Error);
      } finally {
        setLoading(false);
      }
    }

    fetchData();
  }, [activeAccountId, JSON.stringify(filters)]);

  // Generate scenario description
  const getScenarioDescription = () => {
    // Check for region filter first
    if (filters?.region && filters.region.trim() !== '') {
      // When region is filtered, show origin regions sending to that region
      return `Showing origin regions with shipments to ${filters.region} region`;
    }
    
    // Then check city filters
    if (scenarioInfo.isRouteView) {
      return `Showing route from ${scenarioInfo.originCityName} to ${scenarioInfo.destinationCityName}`;
    } else if (scenarioInfo.isOriginView) {
      return `Showing destination cities receiving shipments from ${scenarioInfo.originCityName}`;
    } else if (scenarioInfo.isDestinationView) {
      return `Showing origin cities with shipments to ${scenarioInfo.destinationCityName}`;
    } else {
      return 'Showing origin cities with outbound shipments to all destinations';
    }
  };

  return { 
    cityData, 
    regionData, 
    metrics, 
    loading, 
    error, 
    globalWarningThreshold, 
    globalCriticalThreshold,
    scenarioDescription: getScenarioDescription(),
    scenarioInfo
  };
}
