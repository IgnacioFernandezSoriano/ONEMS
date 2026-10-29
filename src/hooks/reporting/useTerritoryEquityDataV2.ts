import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { useAccount } from '@/contexts/AccountContext';
import { startOfDayInTz, endOfDayInTz } from '@/lib/dateUtils';
import { calculateJKActualFromDays } from '@/lib/jkCalculations';
import type {
  CityEquityData,
  RegionEquityData,
  TerritoryEquityMetrics,
  TerritoryEquityFilters,
} from '@/types/reporting';
import { useEffectiveAccountId } from '../useEffectiveAccountId';
import { useFilterScenario } from './useFilterScenario';
import type { TimeUnit } from '@/lib/accountTime';
import { buildStandardsIndex, commonUnit, convertUnit, measureHours, measureOf, measureUnit, routeKey, uniqueStandards } from '@/lib/transitMeasure';

// Acumulador de J+K de un grupo (ciudad, region, transportista...): estandares y medidas se
// guardan en horas (dias*24 si la ruta mide en dias) junto con las unidades vistas; al cerrar
// el grupo se expresan en su unidad comun (la de sus rutas, u horas si mezclan).
interface JKAcc {
  standardHoursSum: number;
  standardHoursCount: number;
  actualHoursArray: number[];
  units: Set<TimeUnit>;
}

function groupJK(
  acc: JKAcc,
  standardPercentage: number
): { unit: TimeUnit; jkStandard: number; jkActual: number } {
  const unit = commonUnit(acc.units);
  const jkStandard = acc.standardHoursCount > 0
    ? convertUnit(acc.standardHoursSum / acc.standardHoursCount, 'hours', unit)
    : 0;
  const measures = acc.actualHoursArray.map(h => convertUnit(h, 'hours', unit));
  const jkActual = calculateJKActualFromDays(measures, standardPercentage, jkStandard);
  return { unit, jkStandard, jkActual };
}

export function useTerritoryEquityDataV2(
  accountId: string | undefined,
  filters?: TerritoryEquityFilters
) {
  const effectiveAccountId = useEffectiveAccountId();
  const { accountTimezone } = useAccount();
  const activeAccountId = effectiveAccountId || accountId;

  const [cityData, setCityData] = useState<CityEquityData[]>([]);
  const [regionData, setRegionData] = useState<RegionEquityData[]>([]);
  const [metrics, setMetrics] = useState<TerritoryEquityMetrics | null>(null);
  const [routeData, setRouteData] = useState<any[]>([]);
  const [trendData, setTrendData] = useState<Array<{ date: string; avgHours: number; compliancePercent: number; standardHours: number; standardPercent: number }>>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);
  const [globalWarningThreshold, setGlobalWarningThreshold] = useState<number>(80);
  const [globalCriticalThreshold, setGlobalCriticalThreshold] = useState<number>(75);
  const [populationWeightedCitizensAffected, setPopulationWeightedCitizensAffected] = useState<number>(0);
  const [allShipments, setAllShipments] = useState<any[]>([]);

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

        const regionMap = new Map(regions.map((r) => [r.id, r]));

        // Indice de estandares por nombre de ruta (carrier|product|origin|destination, nombres sin
        // espacios sobrantes; producto por description, "code - description" y codigo)
        const cityIdToName = new Map(cities.map((c) => [c.id, c.name]));
        const carrierIdToName = new Map(carriers.map((c) => [c.id, c.name]));
        const productById = new Map(products.map((p) => [p.id, p]));
        const standardsMap = buildStandardsIndex(
          standards,
          (s: any) => ({
            carrier: carrierIdToName.get(s.carrier_id),
            productCode: productById.get(s.product_id)?.code,
            productDescription: productById.get(s.product_id)?.description,
            origin: cityIdToName.get(s.origin_city_id),
            destination: cityIdToName.get(s.destination_city_id),
          }),
          (s: any) => s,
        );
        
        console.log('[DEBUG] Standards map:', {
          size: uniqueStandards(standardsMap).length,
          sampleKeys: Array.from(standardsMap.keys()).slice(0, 3),
          sampleValues: Array.from(standardsMap.values()).slice(0, 1),
        });

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
        const shipmentsData: any[] = []
        const pageSize = 1000
        let start = 0
        let hasMore = true

        while (hasMore) {
          let query = supabase.from('one_db').select('*').eq('account_id', activeAccountId).range(start, start + pageSize - 1)

          // Use same date filtering as ONE DB (no time adjustment)
          if (filters?.startDate && filters.startDate !== '') query = query.gte('sent_at', startOfDayInTz(filters.startDate.slice(0, 10), accountTimezone))
          if (filters?.endDate && filters.endDate !== '') query = query.lte('sent_at', endOfDayInTz(filters.endDate.slice(0, 10), accountTimezone))
          if (filters?.carrier) query = query.eq('carrier_name', filters.carrier)
          if (filters?.product) query = query.eq('product_name', filters.product)
          if (filters?.originCity) query = query.eq('origin_city_name', filters.originCity)
          if (filters?.destinationCity) query = query.eq('destination_city_name', filters.destinationCity)

          const { data, error: shipmentsError } = await query
          if (shipmentsError) throw shipmentsError

          if (data && data.length > 0) {
            shipmentsData.push(...data)
            hasMore = data.length === pageSize
            start += pageSize
          } else {
            hasMore = false
          }
        }

        setAllShipments(shipmentsData);
        const shipments = shipmentsData;

        // equityStatus filter is now handled in Product Analysis tab

        if (!shipments || shipments.length === 0) {
          setCityData([]);
          setRegionData([]);
          setRouteData([]);
          setTrendData([]);
          setPopulationWeightedCitizensAffected(0);
          setMetrics({
            serviceEquityIndex: 0,
            populationWeightedCompliance: 0,
            sampleWeightedCompliance: 0,
            underservedCitiesCount: 0,
            citizensAffected: 0,
            topBestCities: [],
            topWorstCities: [],
            topBestRegions: [],
            topWorstRegions: [],
            totalCities: 0,
            totalPopulation: 0,
            totalSamples: 0,
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
              standardHoursSum: number;
              standardHoursCount: number;
              actualHoursArray: number[];
              units: Set<TimeUnit>;
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
              standardHoursSum: number;
              standardHoursCount: number;
              actualHoursArray: number[];
              units: Set<TimeUnit>;
              warningThresholdSum: number;
              warningThresholdCount: number;
              criticalThresholdSum: number;
              criticalThresholdCount: number;
            };
            standardsSum: number;
            standardsCount: number;
            standardHoursSum: number;
            standardHoursCount: number;
            actualHoursArray: number[];
            units: Set<TimeUnit>;
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
              standardHoursSum: number;
              standardHoursCount: number;
              actualHoursArray: number[];
              units: Set<TimeUnit>;
            }>;
          }
        >();

        // Estandar de la ruta de un envio (carrier|product|origen|destino por ids)
        const standardOfShipment = (shipment: any) =>
          standardsMap.get(routeKey(shipment.carrier_name, shipment.product_name, shipment.origin_city_name, shipment.destination_city_name));

        shipments.forEach((shipment) => {
          // Medida segun la unidad del estandar de la ruta (en horas para acumular); null = sin medida
          const routeStandard = standardOfShipment(shipment);
          const routeUnit: TimeUnit = measureUnit(routeStandard);
          const shipmentMeasureHours = measureHours(shipment, routeUnit);
          const routeStandardHours = routeStandard?.standard_time != null
            ? convertUnit(Number(routeStandard.standard_time), routeUnit, 'hours')
            : null;

          // Process as INBOUND (destination)
          const destCity = shipment.destination_city_name;
          if (!cityStatsMap.has(destCity)) {
            cityStatsMap.set(destCity, {
              inbound: { 
                total: 0, 
                compliant: 0,
                standardsSum: 0,
                standardsCount: 0,
                standardHoursSum: 0,
                standardHoursCount: 0,
                actualHoursArray: [],
                units: new Set<TimeUnit>(),
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
                standardHoursSum: 0,
                standardHoursCount: 0,
                actualHoursArray: [],
                units: new Set<TimeUnit>(),
                warningThresholdSum: 0,
                warningThresholdCount: 0,
                criticalThresholdSum: 0,
                criticalThresholdCount: 0,
              },
              standardsSum: 0,
              standardsCount: 0,
              standardHoursSum: 0,
              standardHoursCount: 0,
              actualHoursArray: [],
              units: new Set<TimeUnit>(),
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
              standardHoursSum: 0,
              standardHoursCount: 0,
              actualHoursArray: [],
              units: new Set<TimeUnit>(),
            });
          }
          const cpStats = destStats.carrierProduct.get(cpKey)!;
          cpStats.total++;
          cpStats.inbound.total++;
          if (shipment.on_time_delivery) {
            cpStats.compliant++;
            cpStats.inbound.compliant++;
          }
          
          // Add standard for this carrier/product
          {
            const standard = routeStandard;
            if (standard) {
              if (standard.success_percentage) {
                cpStats.standardsSum += standard.success_percentage;
                cpStats.standardsCount++;
              }
              // Estandar en su unidad, acumulado en horas (nunca se pasa a dias)
              if (routeStandardHours != null) {
                cpStats.standardHoursSum += routeStandardHours;
                cpStats.standardHoursCount++;
                cpStats.units.add(routeUnit);
              }
            }
          }
          
          // Medida del envio en la unidad de la ruta (los nulos no cuentan)
          if (shipmentMeasureHours != null) {
            cpStats.actualHoursArray.push(shipmentMeasureHours);
            if (routeStandard) cpStats.units.add(routeUnit);
          }

          // Also add to city-level standard (overall + inbound-specific)
          {
            const standard = routeStandard;
            if (standard) {
              if (standard.success_percentage) {
                destStats.standardsSum += standard.success_percentage;
                destStats.standardsCount++;
                destStats.inbound.standardsSum += standard.success_percentage;
                destStats.inbound.standardsCount++;
              }
              if (routeStandardHours != null) {
                destStats.standardHoursSum += routeStandardHours;
                destStats.standardHoursCount++;
                destStats.units.add(routeUnit);
                destStats.inbound.standardHoursSum += routeStandardHours;
                destStats.inbound.standardHoursCount++;
                destStats.inbound.units.add(routeUnit);
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
          
          // Medida a nivel ciudad (global + entrada)
          if (shipmentMeasureHours != null) {
            destStats.actualHoursArray.push(shipmentMeasureHours);
            destStats.inbound.actualHoursArray.push(shipmentMeasureHours);
            // La unidad solo la fija una ruta con estandar (sin estandar no fuerza horas)
            if (routeStandard) {
              destStats.units.add(routeUnit);
              destStats.inbound.units.add(routeUnit);
            }
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
                standardHoursSum: 0,
                standardHoursCount: 0,
                actualHoursArray: [],
                units: new Set<TimeUnit>(),
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
                standardHoursSum: 0,
                standardHoursCount: 0,
                actualHoursArray: [],
                units: new Set<TimeUnit>(),
                warningThresholdSum: 0,
                warningThresholdCount: 0,
                criticalThresholdSum: 0,
                criticalThresholdCount: 0,
              },
              standardsSum: 0,
              standardsCount: 0,
              standardHoursSum: 0,
              standardHoursCount: 0,
              actualHoursArray: [],
              units: new Set<TimeUnit>(),
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
              standardHoursSum: 0,
              standardHoursCount: 0,
              actualHoursArray: [],
              units: new Set<TimeUnit>(),
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
          {
            const standardOut = routeStandard;
            if (standardOut) {
              if (standardOut.success_percentage) {
                cpStatsOrigin.standardsSum += standardOut.success_percentage;
                cpStatsOrigin.standardsCount++;
              }
              if (routeStandardHours != null) {
                cpStatsOrigin.standardHoursSum += routeStandardHours;
                cpStatsOrigin.standardHoursCount++;
                cpStatsOrigin.units.add(routeUnit);
              }
            }
          }
          
          // Also add outbound standards to origin city
          {
            const standardOut = routeStandard;
            if (standardOut) {
              if (standardOut.success_percentage) {
                originStats.outbound.standardsSum += standardOut.success_percentage;
                originStats.outbound.standardsCount++;
              }
              if (routeStandardHours != null) {
                originStats.outbound.standardHoursSum += routeStandardHours;
                originStats.outbound.standardHoursCount++;
                originStats.outbound.units.add(routeUnit);
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
          
          // Medida del envio de salida (global + salida)
          if (shipmentMeasureHours != null) {
            cpStatsOrigin.actualHoursArray.push(shipmentMeasureHours);
            originStats.actualHoursArray.push(shipmentMeasureHours);
            originStats.outbound.actualHoursArray.push(shipmentMeasureHours);
            if (routeStandard) {
              cpStatsOrigin.units.add(routeUnit);
              originStats.units.add(routeUnit);
              originStats.outbound.units.add(routeUnit);
            }
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
            // Origin view: INBOUND (city as destination); destination/general/route view: OUTBOUND
            const dir = scenarioInfo.isOriginView ? stats.inbound : stats.outbound;
            const totalShipments = dir.total;
            const compliantShipments = dir.compliant;
            const actualPercentage = totalShipments > 0 ? (compliantShipments / totalShipments) * 100 : 0;
            const standardPercentage = dir.standardsCount > 0 ? dir.standardsSum / dir.standardsCount : 95;
            // J+K estandar/real en `unit` (la del estandar de sus rutas; horas si mezclan)
            const { unit, jkStandard: standardDays, jkActual: actualDays } = groupJK(dir, standardPercentage);
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
            const inboundPercentage =
              stats.inbound.total > 0 ? (stats.inbound.compliant / stats.inbound.total) * 100 : 0;
            const inboundStandardPercentage =
              stats.inbound.standardsCount > 0 ? stats.inbound.standardsSum / stats.inbound.standardsCount : 95;
            const {
              unit: inboundUnit,
              jkStandard: inboundStandardDays,
              jkActual: inboundActualDays,
            } = groupJK(stats.inbound, inboundStandardPercentage);
            const inboundDeviation = inboundPercentage - inboundStandardPercentage;
            
            // Outbound metrics
            const outboundPercentage =
              stats.outbound.total > 0 ? (stats.outbound.compliant / stats.outbound.total) * 100 : 0;
            const outboundStandardPercentage =
              stats.outbound.standardsCount > 0 ? stats.outbound.standardsSum / stats.outbound.standardsCount : 95;
            const {
              unit: outboundUnit,
              jkStandard: outboundStandardDays,
              jkActual: outboundActualDays,
            } = groupJK(stats.outbound, outboundStandardPercentage);
            const outboundDeviation = outboundPercentage - outboundStandardPercentage;
            
            const directionGap = Math.abs(inboundPercentage - outboundPercentage);

            // Build carrier/product breakdown
            const carrierProductBreakdown = Array.from(stats.carrierProduct.values()).map(cp => {
              const cpActualPercentage = cp.total > 0 ? (cp.compliant / cp.total) * 100 : 0;
              const cpStandardPercentage = cp.standardsCount > 0 ? cp.standardsSum / cp.standardsCount : 95;
              const {
                unit: cpUnit,
                jkStandard: cpStandardDays,
                jkActual: cpActualDays,
              } = groupJK(cp, cpStandardPercentage);
              const cpInboundPercentage = cp.inbound.total > 0 ? (cp.inbound.compliant / cp.inbound.total) * 100 : 0;
              const cpOutboundPercentage = cp.outbound.total > 0 ? (cp.outbound.compliant / cp.outbound.total) * 100 : 0;
              
              return {
                carrier: cp.carrier,
                product: cp.product,
                totalShipments: cp.total,
                compliantShipments: cp.compliant,
                actualPercentage: cpActualPercentage,
                standardPercentage: cpStandardPercentage,
                unit: cpUnit,
                standardDays: cpStandardDays,
                actualDays: cpActualDays,
                deviation: cpActualPercentage - cpStandardPercentage,
                inboundShipments: cp.inbound.total,
                inboundPercentage: cpInboundPercentage,
                outboundShipments: cp.outbound.total,
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
              unit,
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
              inboundUnit,
              inboundStandardDays,
              inboundActualDays,
              inboundDeviation,
              outboundShipments: stats.outbound.total,
              outboundCompliant: stats.outbound.compliant,
              outboundPercentage,
              outboundStandardPercentage,
              outboundUnit,
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

        // equityStatus filter is now applied at route level before aggregation
        
        if (filters?.region) {
          filteredCityData = filteredCityData.filter((c) => c.regionName === filters.region);
        }

        // Filter cities based on scenario to exclude origin/destination city from metrics
        if (scenarioInfo.isRouteView && filters?.originCity && filters?.destinationCity) {
          // For route view, only show the origin city (not destination)
          filteredCityData = filteredCityData.filter((c) => 
            c.cityName === filters.originCity
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

        // Underserved Cities: DESTINATION cities with critical routes
        // Process shipments to detect critical routes
        const criticalDestinationCities = new Set<string>();
        
        // Group shipments by destination city, carrier, product
        const destinationRouteMap = new Map<string, { total: number; compliant: number; standardPercentage: number }>();
        
        console.log('[UNDERSERVED DEBUG] Total shipments:', shipments.length);
        console.log('[UNDERSERVED DEBUG] Global critical threshold:', globalCriticalThreshold);
        
        shipments.forEach((shipment: any) => {
          const originCity = shipment.origin_city_name;
          const destCity = shipment.destination_city_name;
          const carrier = shipment.carrier_name;
          const product = shipment.product_name;
          const key = `${originCity}|${destCity}|${carrier}|${product}`;
          
          if (!destinationRouteMap.has(key)) {
            // Get standard for this route
            let standardPercentage = 95; // default
            const standard = standardOfShipment(shipment);
            if (standard?.success_percentage) {
              standardPercentage = standard.success_percentage;
            }
            
            destinationRouteMap.set(key, {
              total: 0,
              compliant: 0,
              standardPercentage
            });
          }
          
          const routeStats = destinationRouteMap.get(key)!;
          routeStats.total++;
          if (shipment.on_time_delivery) {
            routeStats.compliant++;
          }
        });
        
        // Check each route for critical status
        console.log('[UNDERSERVED DEBUG] Total routes in map:', destinationRouteMap.size);
        destinationRouteMap.forEach((stats, key) => {
          const [originCity, destCity, carrier, product] = key.split('|');
          const inboundPercentage = (stats.compliant / stats.total) * 100;
          // Use relative threshold: 10 percentage points below standard
          const relativeThreshold = 10;
          const criticalThreshold = stats.standardPercentage - relativeThreshold;
          
          console.log(`[UNDERSERVED DEBUG] Route: ${key}`);
          console.log(`  - Total: ${stats.total}, Compliant: ${stats.compliant}`);
          console.log(`  - Inbound %: ${inboundPercentage.toFixed(2)}%`);
          console.log(`  - Standard %: ${stats.standardPercentage}%`);
          console.log(`  - Critical threshold: ${criticalThreshold}%`);
          console.log(`  - Is critical: ${inboundPercentage < criticalThreshold}`);
          
          if (inboundPercentage < criticalThreshold) {
            criticalDestinationCities.add(destCity);
            console.log(`  - ✓ Added ${destCity} to critical cities`);
          }
        });
        
        console.log('[UNDERSERVED DEBUG] Critical destination cities:', Array.from(criticalDestinationCities));
        
        // Get city data for critical cities
        const underservedCities = cityEquityData.filter(c => 
          criticalDestinationCities.has(c.cityName)
        );
        const underservedCitiesCount = underservedCities.length;

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

        // Population-Weighted Compliance (with directional logic)
        // Determine which cities and metrics to use based on scenario
        let relevantCitiesForPopWeight = filteredCityData;
        let useInboundMetric = false;
        let useOutboundMetric = false;
        let citizensAffectedCities = filteredCityData;
        
        if (scenarioInfo.isOriginView) {
          // Origin view: filteredCityData contains DESTINATION cities
          // Use their inboundPercentage (shipments arriving FROM the origin)
          // Citizens affected = population of DESTINATION cities (from cityMap)
          useInboundMetric = true;
          citizensAffectedCities = filteredCityData;
        } else if (scenarioInfo.isDestinationView) {
          // Destination view: analyze DESTINATION city (has inbound metrics)
          useInboundMetric = true;
          
          // Get destination city from cityEquityData for metrics
          const destinationCityName = filters?.destinationCity;
          const destinationCityFromEquity = cityEquityData.find(c => c.cityName === destinationCityName);
          
          if (destinationCityFromEquity) {
            relevantCitiesForPopWeight = [destinationCityFromEquity];
          } else {
            relevantCitiesForPopWeight = [];
          }
        } else if (scenarioInfo.isRouteView) {
          // Route: weight by ORIGIN city (outbound metric)
          // Citizens affected = population of ORIGIN city
          relevantCitiesForPopWeight = cityEquityData.filter(c => c.cityName === filters?.originCity);
          useOutboundMetric = true;
          citizensAffectedCities = cityEquityData.filter(c => c.cityName === filters?.originCity);
        }
        
        // Calculate Citizens Affected: Get unique destination cities from shipments and sum their populations from cityMap
        const destinationCityNames = new Set<string>();
        shipments.forEach((s: any) => {
          if (s.destination_city_name) {
            destinationCityNames.add(s.destination_city_name);
          }
        });
        
        const destinationCitiesPopulation = Array.from(destinationCityNames)
          .map(cityName => cityMap.get(cityName)?.population || 0)
          .reduce((sum, pop) => sum + pop, 0);
        
        citizensAffectedCities = Array.from(destinationCityNames)
          .map(cityName => {
            const city = cityMap.get(cityName);
            if (!city) return null;
            return {
              cityId: city.id,
              cityName: city.name,
              population: city.population || 0,
            };
          })
          .filter((c): c is { cityId: string; cityName: string; population: number } => c !== null)
          .map(c => ({
            ...c,
            regionId: '',
            regionName: '',
            classification: null,
            latitude: null,
            longitude: null,
            totalShipments: 0,
            compliantShipments: 0,
            standardPercentage: 0,
            standardDays: 0,
            actualDays: 0,
            actualPercentage: 0,
            deviation: 0,
            status: 'compliant' as const,
            aggregatedWarningThreshold: 80,
            aggregatedCriticalThreshold: 75,
            inboundShipments: 0,
            inboundCompliant: 0,
            inboundPercentage: 0,
            inboundStandardPercentage: 0,
            inboundStandardDays: 0,
            inboundActualDays: 0,
            inboundDeviation: 0,
            outboundShipments: 0,
            outboundCompliant: 0,
            outboundPercentage: 0,
            outboundStandardPercentage: 0,
            outboundStandardDays: 0,
            outboundActualDays: 0,
            outboundDeviation: 0,
            directionGap: 0,
            carrierProductBreakdown: [],
            accountId: '',
          }));
        
        const popWeightTotalPopulation = relevantCitiesForPopWeight.reduce((sum, c) => sum + (c.population || 0), 0);
        
        // First: Calculate sample-weighted compliance per city
        const citiesWithSampleWeightedCompliance = relevantCitiesForPopWeight.map(c => {
          // Use appropriate metric based on scenario
          let complianceValue = c.actualPercentage;
          if (useInboundMetric) {
            complianceValue = c.inboundPercentage;
          } else if (useOutboundMetric) {
            complianceValue = c.outboundPercentage;
          }
          return {
            ...c,
            complianceValue,
            population: c.population || 0,
            totalShipments: c.totalShipments || 0,
          };
        });
        
        // Second: Apply population weighting
        const populationWeightedCompliance =
          popWeightTotalPopulation > 0
            ? citiesWithSampleWeightedCompliance.reduce((sum, c) => {
                const popWeight = c.population / popWeightTotalPopulation;
                return sum + c.complianceValue * popWeight;
              }, 0)
            : 0;
        
        // Citizens Affected for Population-Weighted Compliance card
        console.log('[CITIZENS DEBUG] Final citizensAffectedCities before reduce:', citizensAffectedCities.map(c => ({ name: c.cityName, pop: c.population })));
        const populationWeightedCitizensAffected = citizensAffectedCities.reduce((sum, c) => sum + (c.population || 0), 0);
        console.log('[CITIZENS DEBUG] populationWeightedCitizensAffected:', populationWeightedCitizensAffected);
        
        // Citizens Affected for Underserved Cities card (separate calculation)
        const underservedCitizensAffected = underservedCities.reduce((sum, c) => sum + (c.population || 0), 0);

        // Sample-Weighted Compliance (weighted by number of shipments)
        const totalSamples = filteredCityData.reduce((sum, c) => sum + c.totalShipments, 0);
        const sampleWeightedCompliance =
          totalSamples > 0
            ? filteredCityData.reduce((sum, c) => {
                const weight = c.totalShipments / totalSamples;
                return sum + c.actualPercentage * weight;
              }, 0)
            : 0;

        // Top 3 Best/Worst Cities
        // Use appropriate metrics based on scenario
        const sortedByDeviation = [...filteredCityData].map(c => {
          const relevantPercentage = scenarioInfo.isOriginView
            ? c.inboundPercentage
            : scenarioInfo.isDestinationView
            ? c.outboundPercentage
            : c.outboundPercentage;
          const relevantStandardPercentage = scenarioInfo.isOriginView
            ? c.inboundStandardPercentage
            : scenarioInfo.isDestinationView
            ? c.outboundStandardPercentage
            : c.outboundStandardPercentage;
          const relevantStandardDays = scenarioInfo.isOriginView
            ? c.inboundStandardDays
            : scenarioInfo.isDestinationView
            ? c.outboundStandardDays
            : c.outboundStandardDays;
          const relevantActualDays = scenarioInfo.isOriginView
            ? c.inboundActualDays
            : scenarioInfo.isDestinationView
            ? c.outboundActualDays
            : c.outboundActualDays;
          const relevantUnit: TimeUnit = (scenarioInfo.isOriginView ? c.inboundUnit : c.outboundUnit) ?? 'hours';
          const relevantDeviation = relevantPercentage - relevantStandardPercentage;
          
          return {
            ...c,
            relevantPercentage,
            relevantStandardPercentage,
            relevantStandardDays,
            relevantActualDays,
            relevantUnit,
            relevantDeviation,
          };
        }).sort((a, b) => b.relevantDeviation - a.relevantDeviation);
        
        const topBestCities = sortedByDeviation.slice(0, 3).map((c) => ({
          cityName: c.cityName,
          actualPercentage: c.relevantPercentage,
          deviation: c.relevantDeviation,
          standardPercentage: c.relevantStandardPercentage,
          unit: c.relevantUnit,
          standardDays: c.relevantStandardDays,
          actualDays: c.relevantActualDays,
          inboundPercentage: c.inboundPercentage,
          outboundPercentage: c.outboundPercentage,
        }));
        const topWorstCities = sortedByDeviation
          .slice(-3)
          .reverse()
          .map((c) => ({
            cityName: c.cityName,
            actualPercentage: c.relevantPercentage,
            deviation: c.relevantDeviation,
            standardPercentage: c.relevantStandardPercentage,
            unit: c.relevantUnit,
            standardDays: c.relevantStandardDays,
            actualDays: c.relevantActualDays,
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
            standardHoursSum: number;
            standardHoursCount: number;
            actualHoursArray: number[];
            units: Set<TimeUnit>;
            warningThresholdSum: number;
            warningThresholdCount: number;
            criticalThresholdSum: number;
            criticalThresholdCount: number;
            underservedCities: number;
            inboundShipments: number;
            inboundCompliant: number;
            inboundStandardsSum: number;
            inboundStandardsCount: number;
            inboundStandardHoursSum: number;
            inboundStandardHoursCount: number;
            inboundActualHoursArray: number[];
            inboundUnits: Set<TimeUnit>;
            inboundWarningThresholdSum: number;
            inboundWarningThresholdCount: number;
            inboundCriticalThresholdSum: number;
            inboundCriticalThresholdCount: number;
            outboundShipments: number;
            outboundCompliant: number;
            outboundStandardsSum: number;
            outboundStandardsCount: number;
            outboundStandardHoursSum: number;
            outboundStandardHoursCount: number;
            outboundActualHoursArray: number[];
            outboundUnits: Set<TimeUnit>;
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
              standardHoursSum: number;
              standardHoursCount: number;
              actualHoursArray: number[];
              units: Set<TimeUnit>;
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
              standardHoursSum: 0,
              standardHoursCount: 0,
              actualHoursArray: [],
              units: new Set<TimeUnit>(),
              warningThresholdSum: 0,
              warningThresholdCount: 0,
              criticalThresholdSum: 0,
              criticalThresholdCount: 0,
              underservedCities: 0,
              inboundShipments: 0,
              inboundCompliant: 0,
              inboundStandardsSum: 0,
              inboundStandardsCount: 0,
              inboundStandardHoursSum: 0,
              inboundStandardHoursCount: 0,
              inboundActualHoursArray: [],
              inboundUnits: new Set<TimeUnit>(),
              inboundWarningThresholdSum: 0,
              inboundWarningThresholdCount: 0,
              inboundCriticalThresholdSum: 0,
              inboundCriticalThresholdCount: 0,
              outboundShipments: 0,
              outboundCompliant: 0,
              outboundStandardsSum: 0,
              outboundStandardsCount: 0,
              outboundStandardHoursSum: 0,
              outboundStandardHoursCount: 0,
              outboundActualHoursArray: [],
              outboundUnits: new Set<TimeUnit>(),
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
          // J+K de la ciudad (en su unidad) acumulado en horas, ponderado por envios
          const cityUnit: TimeUnit = city.unit ?? 'hours';
          const cityInUnit: TimeUnit = city.inboundUnit ?? 'hours';
          const cityOutUnit: TimeUnit = city.outboundUnit ?? 'hours';
          regionStats.standardHoursSum += convertUnit(city.standardDays, cityUnit, 'hours') * city.totalShipments;
          regionStats.standardHoursCount += city.totalShipments;
          if (city.totalShipments > 0) regionStats.units.add(cityUnit);
          // Accumulate thresholds (weighted by total shipments)
          regionStats.warningThresholdSum += city.aggregatedWarningThreshold * city.totalShipments;
          regionStats.warningThresholdCount += city.totalShipments;
          regionStats.criticalThresholdSum += city.aggregatedCriticalThreshold * city.totalShipments;
          regionStats.criticalThresholdCount += city.totalShipments;
          // Replicate actualDays for weighted aggregation
          for (let i = 0; i < city.totalShipments; i++) {
            regionStats.actualHoursArray.push(convertUnit(city.actualDays, cityUnit, 'hours'));
          }
          regionStats.inboundShipments += city.inboundShipments;
          regionStats.inboundCompliant += city.inboundCompliant;
          regionStats.inboundStandardsSum += city.inboundStandardPercentage * city.inboundShipments;
          regionStats.inboundStandardsCount += city.inboundShipments;
          regionStats.inboundStandardHoursSum += convertUnit(city.inboundStandardDays, cityInUnit, 'hours') * city.inboundShipments;
          regionStats.inboundStandardHoursCount += city.inboundShipments;
          if (city.inboundShipments > 0) regionStats.inboundUnits.add(cityInUnit);
          for (let i = 0; i < city.inboundShipments; i++) {
            regionStats.inboundActualHoursArray.push(convertUnit(city.inboundActualDays, cityInUnit, 'hours'));
          }
          regionStats.outboundShipments += city.outboundShipments;
          regionStats.outboundCompliant += city.outboundCompliant;
          regionStats.outboundStandardsSum += city.outboundStandardPercentage * city.outboundShipments;
          regionStats.outboundStandardsCount += city.outboundShipments;
          regionStats.outboundStandardHoursSum += convertUnit(city.outboundStandardDays, cityOutUnit, 'hours') * city.outboundShipments;
          regionStats.outboundStandardHoursCount += city.outboundShipments;
          if (city.outboundShipments > 0) regionStats.outboundUnits.add(cityOutUnit);
          for (let i = 0; i < city.outboundShipments; i++) {
            regionStats.outboundActualHoursArray.push(convertUnit(city.outboundActualDays, cityOutUnit, 'hours'));
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
                  standardHoursSum: 0,
                  standardHoursCount: 0,
                  actualHoursArray: [],
                  units: new Set<TimeUnit>(),
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
              const cpUnit: TimeUnit = cp.unit ?? 'hours';
              cpStats.standardHoursSum += convertUnit(cp.standardDays, cpUnit, 'hours');
              cpStats.standardHoursCount++;
              cpStats.units.add(cpUnit);
              for (let i = 0; i < cp.totalShipments; i++) {
                cpStats.actualHoursArray.push(convertUnit(cp.actualDays, cpUnit, 'hours'));
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
            const { unit, jkStandard: standardDays, jkActual: actualDays } = groupJK(stats, standardPercentage);
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
            const {
              unit: inboundUnit,
              jkStandard: inboundStandardDays,
              jkActual: inboundActualDays,
            } = groupJK({
              standardHoursSum: stats.inboundStandardHoursSum,
              standardHoursCount: stats.inboundStandardHoursCount,
              actualHoursArray: stats.inboundActualHoursArray,
              units: stats.inboundUnits,
            }, inboundStandardPercentage);
            const inboundDeviation = inboundPercentage - inboundStandardPercentage;
            
            // Outbound metrics
            const outboundPercentage = stats.outboundShipments > 0 
              ? (stats.outboundCompliant / stats.outboundShipments) * 100 
              : 0;
            const outboundStandardPercentage = stats.outboundStandardsCount > 0
              ? stats.outboundStandardsSum / stats.outboundStandardsCount
              : 95;
            const {
              unit: outboundUnit,
              jkStandard: outboundStandardDays,
              jkActual: outboundActualDays,
            } = groupJK({
              standardHoursSum: stats.outboundStandardHoursSum,
              standardHoursCount: stats.outboundStandardHoursCount,
              actualHoursArray: stats.outboundActualHoursArray,
              units: stats.outboundUnits,
            }, outboundStandardPercentage);
            const outboundDeviation = outboundPercentage - outboundStandardPercentage;
            
            const directionGap = Math.abs(inboundPercentage - outboundPercentage);

            // Build carrier/product breakdown
            const carrierProductBreakdown = Array.from(stats.carrierProduct.values()).map(cp => {
              const cpActualPercentage = cp.total > 0 ? (cp.compliant / cp.total) * 100 : 0;
              const cpStandardPercentage = cp.standardsCount > 0 ? cp.standardsSum / cp.standardsCount : 95;
              const {
                unit: cpUnit,
                jkStandard: cpStandardDays,
                jkActual: cpActualDays,
              } = groupJK(cp, cpStandardPercentage);
              const cpInboundPercentage = cp.inbound.total > 0 ? (cp.inbound.compliant / cp.inbound.total) * 100 : 0;
              const cpOutboundPercentage = cp.outbound.total > 0 ? (cp.outbound.compliant / cp.outbound.total) * 100 : 0;
              
              return {
                carrier: cp.carrier,
                product: cp.product,
                totalShipments: cp.total,
                compliantShipments: cp.compliant,
                actualPercentage: cpActualPercentage,
                standardPercentage: cpStandardPercentage,
                unit: cpUnit,
                standardDays: cpStandardDays,
                actualDays: cpActualDays,
                deviation: cpActualPercentage - cpStandardPercentage,
                inboundShipments: cp.inbound.total,
                inboundPercentage: cpInboundPercentage,
                outboundShipments: cp.outbound.total,
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
              unit,
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
              inboundUnit,
              inboundStandardDays,
              inboundActualDays,
              inboundDeviation,
              outboundShipments: stats.outboundShipments,
              outboundCompliant: stats.outboundCompliant,
              outboundPercentage,
              outboundStandardPercentage,
              outboundUnit,
              outboundStandardDays,
              outboundActualDays,
              outboundDeviation,
              directionGap,
              carrierProductBreakdown,
              accountId: accountId!,
            };
          }
        );

        // Top 3 Best/Worst Regions
        const sortedRegionsByDeviation = [...regionEquityData].sort((a, b) => b.deviation - a.deviation);
        const topBestRegions = sortedRegionsByDeviation.slice(0, 3).map((r) => ({
          regionName: r.regionName,
          actualPercentage: r.actualPercentage,
          deviation: r.deviation,
          standardPercentage: r.standardPercentage,
          unit: r.unit,
          standardDays: r.standardDays,
          actualDays: r.actualDays,
          inboundPercentage: r.inboundPercentage,
          outboundPercentage: r.outboundPercentage,
        }));
        const topWorstRegions = sortedRegionsByDeviation
          .slice(-3)
          .reverse()
          .map((r) => ({
            regionName: r.regionName,
            actualPercentage: r.actualPercentage,
            deviation: r.deviation,
            standardPercentage: r.standardPercentage,
            unit: r.unit,
            standardDays: r.standardDays,
            actualDays: r.actualDays,
            inboundPercentage: r.inboundPercentage,
            outboundPercentage: r.outboundPercentage,
            status: r.status,
          }));

        // 9. Build route-level data for Product Analysis
        // Cada ruta mide en la unidad de su estandar (dias -> dias laborables; horas o sin estandar -> horas)
        type RouteAcc = {
          origin: string;
          destination: string;
          carrier: string;
          product: string;
          unit: TimeUnit;
          total: number;
          compliant: number;
          standardPercentage: number;  // Single value, not averaged
          measureArray: number[];  // medidas en `unit` (sin nulos)
          standardArray: number[];  // estandar en `unit`
          distribution: Map<number, number>;  // cubeta (1 h o 1 dia) -> count for distribution charts
        };
        const routeMap = new Map<string, RouteAcc>();

        shipments.forEach(s => {
          const rKey = `${s.origin_city_name}|${s.destination_city_name}|${s.carrier_name}|${s.product_name}`;
          const standard = standardOfShipment(s);
          if (!routeMap.has(rKey)) {
            routeMap.set(rKey, {
              origin: s.origin_city_name,
              destination: s.destination_city_name,
              carrier: s.carrier_name,
              product: s.product_name,
              unit: measureUnit(standard),
              total: 0,
              compliant: 0,
              // default 95 (same as Underserved Cities)
              standardPercentage: standard?.success_percentage || 95,
              measureArray: [],
              standardArray: [],
              distribution: new Map<number, number>(),
            });
          }
          const route = routeMap.get(rKey)!;
          route.total++;
          if (s.on_time_delivery) route.compliant++;

          // Estandar en su propia unidad (nunca convertido a dias)
          if (standard?.standard_time != null) {
            route.standardArray.push(Number(standard.standard_time));
          }
          const measure = measureOf(s, route.unit);
          if (measure != null) {
            route.measureArray.push(measure);
            // Cubetas de 1 h (horas redondeadas) o de 1 dia
            const bucket = Math.round(measure);
            route.distribution.set(bucket, (route.distribution.get(bucket) || 0) + 1);
          }
        });

        console.log('[routeData] Sample route:', Array.from(routeMap.values())[0]);
        const routeData = Array.from(routeMap.values()).map(r => {
          const standardPercentage = r.standardPercentage;  // Use the single value calculated at route creation
          const actualPercentage = r.total > 0 ? (r.compliant / r.total) * 100 : 0;
          const deviation = actualPercentage - standardPercentage;
          const jkStandard = r.standardArray.length > 0
            ? r.standardArray.reduce((sum, d) => sum + d, 0) / r.standardArray.length
            : 0;
          const jkActual = calculateJKActualFromDays(
            r.measureArray,
            standardPercentage,
            jkStandard
          );

          // Calculate status using global SLA thresholds
          let status: 'compliant' | 'warning' | 'critical';
          if (actualPercentage >= defaultWarningThreshold) {
            status = 'compliant';
          } else if (actualPercentage >= defaultCriticalThreshold) {
            status = 'warning';
          } else {
            status = 'critical';
          }

          return {
            origin: r.origin,
            destination: r.destination,
            carrier: r.carrier,
            product: r.product,
            unit: r.unit,  // unidad de jkStandard/jkActual/distribution
            totalShipments: r.total,
            standardPercentage,
            actualPercentage,
            deviation,
            jkStandard,
            jkActual,
            // Alias (mismo valor, en `unit`) para componentes compartidos con J+K Performance
            standardDays: jkStandard,
            actualDays: jkActual,
            status,
            distribution: r.distribution,
          };
        });

        // 9.5. Build aggregated J+K metrics for carriers and products
        // Medidas y estandares en horas + unidades vistas; se expresan en la unidad comun del grupo
        type AggJK = JKAcc & {
          standardPercentageSum: number;
          standardPercentageCount: number;
          totalShipments: number;
          compliantShipments: number;
        };
        const newAgg = (): AggJK => ({
          standardHoursSum: 0,
          standardHoursCount: 0,
          actualHoursArray: [],
          units: new Set<TimeUnit>(),
          standardPercentageSum: 0,
          standardPercentageCount: 0,
          totalShipments: 0,
          compliantShipments: 0,
        });
        const addRouteToAgg = (agg: AggJK, r: RouteAcc) => {
          r.measureArray.forEach(m => agg.actualHoursArray.push(convertUnit(m, r.unit, 'hours')));
          r.standardArray.forEach(st => {
            agg.standardHoursSum += convertUnit(st, r.unit, 'hours');
            agg.standardHoursCount++;
          });
          if (r.measureArray.length > 0 || r.standardArray.length > 0) agg.units.add(r.unit);
          agg.standardPercentageSum += r.standardPercentage;
          agg.standardPercentageCount++;
          agg.totalShipments += r.total;
          agg.compliantShipments += r.compliant;
        };

        const carrierAggregateMap = new Map<string, AggJK>();
        const productAggregateMap = new Map<string, AggJK>();

        // Collect all transit measures for each carrier and product
        Array.from(routeMap.values()).forEach(r => {
          const productKey = `${r.carrier}|${r.product}`;
          if (!carrierAggregateMap.has(r.carrier)) carrierAggregateMap.set(r.carrier, newAgg());
          addRouteToAgg(carrierAggregateMap.get(r.carrier)!, r);
          if (!productAggregateMap.has(productKey)) productAggregateMap.set(productKey, newAgg());
          addRouteToAgg(productAggregateMap.get(productKey)!, r);
        });

        // Calculate aggregated J+K for carriers and products
        type AggMetrics = {
          unit: TimeUnit;
          jkStandard: number;
          jkActual: number;
          standardPercentage: number;
          actualPercentage: number;
          deviation: number;
          status: 'compliant' | 'warning' | 'critical';
        };
        const finishAgg = (agg: AggJK): AggMetrics => {
          const avgStandardPercentage = agg.standardPercentageCount > 0
            ? agg.standardPercentageSum / agg.standardPercentageCount
            : 95;
          const { unit, jkStandard, jkActual } = groupJK(agg, avgStandardPercentage);
          const actualPercentage = agg.totalShipments > 0
            ? (agg.compliantShipments / agg.totalShipments) * 100
            : 0;
          const deviation = actualPercentage - avgStandardPercentage;

          // Calculate status using global SLA thresholds
          let status: 'compliant' | 'warning' | 'critical';
          if (actualPercentage >= defaultWarningThreshold) {
            status = 'compliant';
          } else if (actualPercentage >= defaultCriticalThreshold) {
            status = 'warning';
          } else {
            status = 'critical';
          }
          return { unit, jkStandard, jkActual, standardPercentage: avgStandardPercentage, actualPercentage, deviation, status };
        };
        const carrierJK = new Map<string, AggMetrics>();
        carrierAggregateMap.forEach((agg, carrier) => carrierJK.set(carrier, finishAgg(agg)));
        const productJK = new Map<string, AggMetrics>();
        productAggregateMap.forEach((agg, productKey) => productJK.set(productKey, finishAgg(agg)));

        // Extend routeData to include aggregated metrics
        const routeDataWithAggregates = routeData.map(r => {
          const carrierMetrics = carrierJK.get(r.carrier);
          const productMetrics = productJK.get(`${r.carrier}|${r.product}`);
          return {
            ...r,
            carrierUnit: carrierMetrics?.unit || 'hours',
            carrierJkStandard: carrierMetrics?.jkStandard || 0,
            carrierJkActual: carrierMetrics?.jkActual || 0,
            carrierStandardPercentage: carrierMetrics?.standardPercentage || 0,
            carrierActualPercentage: carrierMetrics?.actualPercentage || 0,
            carrierDeviation: carrierMetrics?.deviation || 0,
            carrierStatus: carrierMetrics?.status || 'compliant',
            productUnit: productMetrics?.unit || 'hours',
            productJkStandard: productMetrics?.jkStandard || 0,
            productJkActual: productMetrics?.jkActual || 0,
            productStandardPercentage: productMetrics?.standardPercentage || 0,
            productActualPercentage: productMetrics?.actualPercentage || 0,
            productDeviation: productMetrics?.deviation || 0,
            productStatus: productMetrics?.status || 'compliant',
          };
        });

        // 10. Calculate trend data (daily aggregation) - tiempos en horas (dias*24 si la ruta mide en dias)
        const trendMap = new Map<string, {
          totalHours: number;
          measuredCount: number;
          count: number;
          compliant: number;
          standardHoursSum: number;
          standardHoursCount: number;
          standardPercentSum: number;
          standardPercentCount: number;
        }>();

        shipments.forEach(s => {
          if (!s.sent_at) return;
          const date = new Date(s.sent_at);
          const dateKey = date.toISOString().split('T')[0]; // YYYY-MM-DD
          if (!trendMap.has(dateKey)) {
            trendMap.set(dateKey, {
              totalHours: 0,
              measuredCount: 0,
              count: 0,
              compliant: 0,
              standardHoursSum: 0,
              standardHoursCount: 0,
              standardPercentSum: 0,
              standardPercentCount: 0,
            });
          }
          const trend = trendMap.get(dateKey)!;
          trend.count++;
          if (s.on_time_delivery) {
            trend.compliant++;
          }

          // Find standard for this shipment
          const standard = standardOfShipment(s);
          const unit = measureUnit(standard);
          const hours = measureHours(s, unit);
          if (hours != null) {
            trend.totalHours += hours;
            trend.measuredCount++;
          }

          if (standard) {
            if (standard.standard_time != null) {
              trend.standardHoursSum += convertUnit(Number(standard.standard_time), unit, 'hours');
              trend.standardHoursCount++;
            }
            const successPct = standard.success_percentage || 85;
            trend.standardPercentSum += successPct;
            trend.standardPercentCount++;
          }
        });

        const trendDataArray = Array.from(trendMap.entries())
          .map(([dateKey, data]) => ({
            date: dateKey,
            avgHours: data.measuredCount > 0 ? data.totalHours / data.measuredCount : 0,
            compliancePercent: data.count > 0 ? (data.compliant / data.count) * 100 : 0,
            standardHours: data.standardHoursCount > 0 ? data.standardHoursSum / data.standardHoursCount : 0,
            standardPercent: data.standardPercentCount > 0 ? data.standardPercentSum / data.standardPercentCount : 85,
          }))
          .sort((a, b) => a.date.localeCompare(b.date));

        // 11. Set state
        setCityData(filteredCityData);
        setRouteData(routeDataWithAggregates);
        setTrendData(trendDataArray);
        setPopulationWeightedCitizensAffected(populationWeightedCitizensAffected);
        
        // RegionData is NOT filtered - treemap always shows all regions
        setRegionData(regionEquityData);
        setMetrics({
          serviceEquityIndex,
          populationWeightedCompliance,
          sampleWeightedCompliance,
          underservedCitiesCount,
          citizensAffected: underservedCitizensAffected,
          topBestCities,
          topWorstCities,
          topBestRegions,
          topWorstRegions,
          totalCities,
          totalPopulation: populationWeightedCitizensAffected, // Use destination cities population for display
          totalSamples,
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
  }, [activeAccountId, JSON.stringify(filters), accountTimezone]);

  // Generate scenario description
  const getScenarioDescription = () => {
    // Check for region filter first
    if (filters?.region && filters.region.trim() !== '') {
      // When region is filtered, show origin regions sending to that region
      return `Showing origin regions with shipments to ${filters.region} region`;
    }
    
    // Then check city filters
    if (scenarioInfo.isRouteView) {
      return `Showing route from ${scenarioInfo.originCityName} to ${scenarioInfo.destinationCityName} (Outbound from ${scenarioInfo.originCityName} to ${scenarioInfo.destinationCityName})`;
    } else if (scenarioInfo.isOriginView) {
      return `Showing destination cities receiving shipments from ${scenarioInfo.originCityName} (Inbound to destination cities from ${scenarioInfo.originCityName})`;
    } else if (scenarioInfo.isDestinationView) {
      return `Showing origin cities with shipments to ${scenarioInfo.destinationCityName} (Outbound from origin cities to ${scenarioInfo.destinationCityName})`;
    } else {
      return 'Showing all cities with shipments (Outbound from all cities)';
    }
  };

  return { 
    cityData, 
    regionData, 
    metrics, 
    routeData,
    trendData,
    shipments: allShipments,
    loading, 
    error, 
    globalWarningThreshold, 
    globalCriticalThreshold,
    scenarioDescription: getScenarioDescription(),
    scenarioInfo,
    populationWeightedCitizensAffected
  };
}
