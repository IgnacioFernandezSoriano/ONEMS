import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { useAccount } from '@/contexts/AccountContext';
import { startOfDayInTz, endOfDayInTz } from '@/lib/dateUtils';
import { useEffectiveAccountId } from '../useEffectiveAccountId';
import type { TimeUnit } from '@/lib/accountTime';
import { commonUnit, convertUnit, measureOf, measureUnit } from '@/lib/transitMeasure';

export interface JKRouteData {
  routeKey: string;
  unit: TimeUnit; // unidad del estandar de la ruta; samples/distribution/jkActual/jkStandard/deviation estan en ella
  origin: string;
  destination: string;
  originCity: string;
  destinationCity: string;
  carrier: string;
  product: string;
  totalSamples: number;
  totalShipments: number;
  jkStandard: number; //  jkStandard: number;
  standardDays: number;
  jkActual: number; // days to reach STD % target
  actualDays: number;
  actualPercentage: number;
  deviation: number; // actual - standard
  onTimePercentage: number;
  onTimeSamples: number;
  beforeStandardSamples: number; // samples delivered before standard
  afterStandardSamples: number; // samples delivered after standard
  distribution: Map<number, number>; // bucket (horas redondeadas o dias) -> count
  standardPercentage: number; // target percentage from delivery_standards (e.g., 85%)
  warningThreshold: number; // warning threshold percentage (e.g., 80%)
  criticalThreshold: number; // critical threshold percentage (e.g., 75%)
  status: 'compliant' | 'warning' | 'critical';
}

export interface JKCityData {
  unit: TimeUnit; // unidad de jkStandard/jkActual/deviation (horas si el grupo mezcla unidades)
  cityName: string;
  direction: 'inbound' | 'outbound';
  regionName: string;
  routes: number;
  totalSamples: number;
  jkStandard: number;
  jkActual: number;
  deviation: number;
  onTimePercentage: number;
  standardPercentage: number;
  warningThreshold: number;
  criticalThreshold: number;
  status: 'compliant' | 'warning' | 'critical';
}

export interface JKRegionData {
  unit: TimeUnit; // unidad de jkStandard/jkActual/deviation (horas si el grupo mezcla unidades)
  regionName: string;
  direction: 'inbound' | 'outbound';
  cities: number;
  routes: number;
  totalSamples: number;
  jkStandard: number;
  jkActual: number;
  deviation: number;
  onTimePercentage: number;
  standardPercentage: number;
  warningThreshold: number;
  criticalThreshold: number;
  status: 'compliant' | 'warning' | 'critical';
}

export interface JKCarrierData {
  unit: TimeUnit; // unidad de jkStandard/jkActual/deviation (horas si el grupo mezcla unidades)
  carrier: string;
  routes: number;
  totalSamples: number;
  jkStandard: number;
  jkActual: number;
  deviation: number;
  onTimePercentage: number;
  problematicRoutes: number;
  standardPercentage: number;
  warningThreshold: number;
  criticalThreshold: number;
  status: 'compliant' | 'warning' | 'critical';
  products: JKProductBreakdown[];
}

export interface JKProductData {
  unit: TimeUnit; // unidad de jkStandard/jkActual/deviation (horas si el grupo mezcla unidades)
  product: string;
  routes: number;
  totalSamples: number;
  jkStandard: number;
  jkActual: number;
  deviation: number;
  onTimePercentage: number;
  problematicRoutes: number;
  standardPercentage: number;
  warningThreshold: number;
  criticalThreshold: number;
  status: 'compliant' | 'warning' | 'critical';
  carriers: JKCarrierBreakdown[];
}

export interface JKProductBreakdown {
  unit: TimeUnit; // unidad de jkStandard/jkActual/deviation (horas si el grupo mezcla unidades)
  product: string;
  routes: number;
  totalSamples: number;
  jkStandard: number;
  jkActual: number;
  deviation: number;
  onTimePercentage: number;
  standardPercentage: number;
  warningThreshold: number;
  criticalThreshold: number;
  status: 'compliant' | 'warning' | 'critical';
}

export interface JKCarrierBreakdown {
  unit: TimeUnit; // unidad de jkStandard/jkActual/deviation (horas si el grupo mezcla unidades)
  carrier: string;
  routes: number;
  totalSamples: number;
  jkStandard: number;
  jkActual: number;
  deviation: number;
  onTimePercentage: number;
  standardPercentage: number;
  warningThreshold: number;
  criticalThreshold: number;
  status: 'compliant' | 'warning' | 'critical';
}

export interface WeeklySample {
  week: string; // ISO week (YYYY-WW)
  weekStart: string; // Date
  weekEnd: string; // Date
  samples: number;
}

export interface JKMetrics {
  unit: TimeUnit; // unidad de jkStandard/jkActual/deviation (horas si el grupo mezcla unidades)
  totalSamples: number;
  avgJKStandard: number;
  avgJKActual: number;
  onTimePercentage: number;
  onTimeSamples: number;
  problematicRoutes: number;
}

interface Filters {
  startDate?: string;
  endDate?: string;
  originCity?: string;
  destinationCity?: string;
  carrier?: string;
  product?: string;
  region?: string;
}

export function useJKPerformance(accountId: string | undefined, filters?: Filters) {
  const effectiveAccountId = useEffectiveAccountId();
  const { accountTimezone } = useAccount();
  const activeAccountId = effectiveAccountId || accountId;

  const [routeData, setRouteData] = useState<JKRouteData[]>([]);
  const [cityData, setCityData] = useState<JKCityData[]>([]);
  const [regionData, setRegionData] = useState<JKRegionData[]>([]);
  const [carrierData, setCarrierData] = useState<JKCarrierData[]>([]);
  const [productData, setProductData] = useState<JKProductData[]>([]);
  const [weeklySamples, setWeeklySamples] = useState<WeeklySample[]>([]);
  const [metrics, setMetrics] = useState<JKMetrics>({
    unit: 'hours',
    totalSamples: 0,
    avgJKStandard: 0,
    avgJKActual: 0,
    onTimePercentage: 0,
    onTimeSamples: 0,
    problematicRoutes: 0,
  });
  // Maximo observado por unidad: cada grafica de distribucion escala con la suya
  const [maxMeasure, setMaxMeasure] = useState<{ hours: number; days: number }>({ hours: 0, days: 0 });
  const [globalWarningThreshold, setGlobalWarningThreshold] = useState(80);
  const [globalCriticalThreshold, setGlobalCriticalThreshold] = useState(75);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    if (!activeAccountId) {
      setLoading(false);
      return;
    }

    async function fetchData() {
      try {
        setLoading(true);

        // 1. Load shipments with filters and pagination
        const allShipments: any[] = []
        const pageSize = 1000
        let start = 0
        let hasMore = true

        while (hasMore) {
          let query = supabase
            .from('one_db')
            .select('*')
            .eq('account_id', activeAccountId)
            .range(start, start + pageSize - 1)

          // Use same date filtering as ONE DB (no time adjustment)
          if (filters?.startDate && filters.startDate !== '') query = query.gte('sent_at', startOfDayInTz(filters.startDate.slice(0, 10), accountTimezone))
          if (filters?.endDate && filters.endDate !== '') query = query.lte('sent_at', endOfDayInTz(filters.endDate.slice(0, 10), accountTimezone))
          if (filters?.originCity) query = query.eq('origin_city_name', filters.originCity)
          if (filters?.destinationCity) query = query.eq('destination_city_name', filters.destinationCity)
          if (filters?.carrier) query = query.eq('carrier_name', filters.carrier)
          if (filters?.product) query = query.eq('product_name', filters.product)

          const { data, error: shipmentsErr } = await query
          if (shipmentsErr) throw shipmentsErr

          if (data && data.length > 0) {
            allShipments.push(...data)
            hasMore = data.length === pageSize
            start += pageSize
          } else {
            hasMore = false
          }
        }

        const shipments = allShipments

        // 2. Load delivery standards
        const { data: standards, error: stdErr } = await supabase
          .from('delivery_standards')
          .select('*')
          .eq('account_id', activeAccountId);
        if (stdErr) throw stdErr;

        // 3. Load lookup tables
        const [carriersRes, productsRes, citiesRes, regionsRes] = await Promise.all([
          supabase.from('carriers').select('id, name').eq('account_id', activeAccountId),
          supabase.from('products').select('id, code, description').eq('account_id', activeAccountId),
          supabase.from('cities').select('id, name, region_id').eq('account_id', activeAccountId),
          supabase.from('regions').select('id, name').eq('account_id', activeAccountId),
        ]);

        if (carriersRes.error) throw carriersRes.error;
        if (productsRes.error) throw productsRes.error;
        if (citiesRes.error) throw citiesRes.error;
        if (regionsRes.error) throw regionsRes.error;

        // 4. Create lookup maps
        const carrierMap = new Map(carriersRes.data?.map(c => [c.id, c.name]) || []);
        const productMap = new Map(productsRes.data?.map(p => [p.id, `${p.code} - ${p.description}`]) || []);
        const cityMap = new Map(citiesRes.data?.map(c => [c.id, c.name]) || []);
        const cityRegionMap = new Map(citiesRes.data?.map(c => [c.name, c.region_id]) || []);
        const regionMap = new Map(regionsRes.data?.map(r => [r.id, r.name]) || []);

        // 5. Create standards map (key: carrier|product|origin|destination)
        const standardsMap = new Map<string, { jkStandard: number; unit: TimeUnit; successPercentage: number; warningThreshold: number; criticalThreshold: number }>();
        (standards || []).forEach(std => {
          const carrierName = carrierMap.get(std.carrier_id);
          const productName = productMap.get(std.product_id);
          const originName = cityMap.get(std.origin_city_id);
          const destName = cityMap.get(std.destination_city_id);

          if (carrierName && productName && originName && destName) {
            const key = `${carrierName}|${productName}|${originName}|${destName}`;
            // El estandar se queda en su unidad (nunca se convierte a dias)
            const unit = measureUnit(std);
            const jkStandard = Number(std.standard_time);
            // Calculate warning and critical thresholds
            const successPct = std.success_percentage || 95;
            const warningThreshold = std.threshold_type === 'relative' 
              ? successPct - (successPct * (std.warning_threshold || 5) / 100)
              : successPct - (std.warning_threshold || 5);
            const criticalThreshold = std.threshold_type === 'relative'
              ? successPct - (successPct * (std.critical_threshold || 10) / 100)
              : successPct - (std.critical_threshold || 10);
            
            standardsMap.set(key, {
              jkStandard: jkStandard || 0,
              unit,
              successPercentage: successPct,
              warningThreshold: warningThreshold,
              criticalThreshold: criticalThreshold,
            });
          }
        });

        // Calculate global thresholds (average of all standards)
        let warningThreshold = 80;
        let criticalThreshold = 75;
        if (standardsMap.size > 0) {
          const thresholds = Array.from(standardsMap.values());
          warningThreshold = thresholds.reduce((sum, s) => sum + s.warningThreshold, 0) / thresholds.length;
          criticalThreshold = thresholds.reduce((sum, s) => sum + s.criticalThreshold, 0) / thresholds.length;
        }
        setGlobalWarningThreshold(warningThreshold);
        setGlobalCriticalThreshold(criticalThreshold);
        
        console.log('[useJKPerformance] Loaded standards:', standardsMap.size, 'Global thresholds:', { warning: warningThreshold, critical: criticalThreshold });

        // 6. Group shipments by route
        const routeMap = new Map<string, {
          originCity: string;
          destinationCity: string;
          carrier: string;
          product: string;
          unit: TimeUnit;
          samples: number[];
          onTimeSamples: number;
          standardDaysArray: number[];
          distribution: Map<number, number>;
        }>();

        const calculatedMax = { hours: 0, days: 0 };

        (shipments || []).forEach(shipment => {
          const key = `${shipment.carrier_name}|${shipment.product_name}|${shipment.origin_city_name}|${shipment.destination_city_name}`;
          const standard = standardsMap.get(key);
          const rowUnit: TimeUnit = standard?.unit ?? 'hours';
          const measure = measureOf(shipment, rowUnit); // medida en la unidad de la ruta
          // Sin medida (no entregado / sin calcular): no cuenta ni como a tiempo ni como tarde
          if (measure === null) return;

          if (measure > calculatedMax[rowUnit]) {
            calculatedMax[rowUnit] = measure;
          }

          if (!routeMap.has(key)) {
            routeMap.set(key, {
              originCity: shipment.origin_city_name,
              destinationCity: shipment.destination_city_name,
              carrier: shipment.carrier_name,
              product: shipment.product_name,
              unit: rowUnit,
              samples: [],
              onTimeSamples: 0,
              standardDaysArray: [],
              distribution: new Map(),
            });
          }

          const route = routeMap.get(key)!;
          route.samples.push(measure);
          
          // Collect standard_time for J+K calculation (same logic as useTerritoryEquityDataV2)
          if (standard?.jkStandard != null) {
            route.standardDaysArray.push(standard.jkStandard);
          }
          
          // Update distribution
          // Cubetas de 1 h: un envio de 48.4 h cae en la cubeta 48 aunque a tiempo lo cuenta como tarde (inherente)
          const bucket = rowUnit === 'hours' ? Math.round(measure) : measure;
          const currentCount = route.distribution.get(bucket) || 0;
          route.distribution.set(bucket, currentCount + 1);
        });

        // Maximo en cubetas enteras (techo) para que la grafica llegue a la ultima cubeta
        setMaxMeasure({ hours: Math.ceil(calculatedMax.hours), days: Math.ceil(calculatedMax.days) });

        // 7. Build route data
        const routes: JKRouteData[] = Array.from(routeMap.entries()).map(([key, route]) => {
          const totalSamples = route.samples.length;
          const standard = standardsMap.get(key);
          
          // Calculate jkStandard as average of standardDaysArray (same as useTerritoryEquityDataV2)
          const jkStandard = route.standardDaysArray.length > 0
            ? route.standardDaysArray.reduce((sum, d) => sum + d, 0) / route.standardDaysArray.length
            : 0;
          
          // Calculate J+K Actual (days to reach STD %)
          const targetStdPercentage = standard?.successPercentage || 85;
          let jkActual = 0;
          if (totalSamples > 0 && route.distribution.size > 0) {
            const sortedDays = Array.from(route.distribution.entries())
              .sort((a, b) => a[0] - b[0]); // Sort by day ascending
            
            let cumulativeSamples = 0;
            const targetSamples = (totalSamples * targetStdPercentage) / 100;
            
            for (const [day, count] of sortedDays) {
              cumulativeSamples += count;
              if (cumulativeSamples >= targetSamples) {
                jkActual = day;
                break;
              }
            }
          }
          
          // Recalculate onTimeSamples based on calculated jkStandard
          const onTimeSamples = jkStandard > 0 
            ? route.samples.filter(d => d <= jkStandard).length 
            : 0;
          
          const deviation = jkActual - jkStandard;
          const onTimePercentage = totalSamples > 0 
            ? (onTimeSamples / totalSamples) * 100 
            : 0;

          const routeWarningThreshold = standard?.warningThreshold || warningThreshold;
          const routeCriticalThreshold = standard?.criticalThreshold || criticalThreshold;
          
          const status: 'compliant' | 'warning' | 'critical' =
            onTimePercentage >= routeWarningThreshold ? 'compliant' :
            onTimePercentage >= routeCriticalThreshold ? 'warning' : 'critical';

          const beforeStandardSamples = route.samples.filter(d => d < jkStandard).length;
          const afterStandardSamples = route.samples.filter(d => d > jkStandard).length;
          
          return {
            routeKey: key,
            unit: route.unit,
            origin: route.originCity,
            destination: route.destinationCity,
            originCity: route.originCity,
            destinationCity: route.destinationCity,
            carrier: route.carrier,
            product: route.product,
            totalSamples,
            totalShipments: totalSamples,
            jkStandard,
            standardDays: jkStandard,
            jkActual,
            actualDays: jkActual,
            actualPercentage: onTimePercentage,
            deviation,
            onTimePercentage,
            onTimeSamples,
            beforeStandardSamples,
            afterStandardSamples,
            distribution: route.distribution,
            standardPercentage: standard?.successPercentage || 85,
            warningThreshold: routeWarningThreshold,
            criticalThreshold: routeCriticalThreshold,
            status,
          };
        });

        // 8. Build city data (2 rows per city: inbound + outbound)
        const cityStatsMap = new Map<string, {
          inbound: {
            samples: number[];
            onTimeSamples: number;
            standardSum: number;
            standardCount: number;
            standardPercentageSum: number;
            warningThresholdSum: number;
            criticalThresholdSum: number;
            thresholdCount: number;
            routes: Set<string>;
          };
          outbound: {
            samples: number[];
            onTimeSamples: number;
            standardSum: number;
            standardCount: number;
            standardPercentageSum: number;
            warningThresholdSum: number;
            criticalThresholdSum: number;
            thresholdCount: number;
            routes: Set<string>;
          };
        }>();

        // Unidad de cada fila (ciudad+sentido): la de sus rutas, horas si mezclan
        const cityUnits = new Map<string, Set<TimeUnit>>();
        routes.forEach(route => {
          for (const k of [`in|${route.destinationCity}`, `out|${route.originCity}`]) {
            if (!cityUnits.has(k)) cityUnits.set(k, new Set());
            cityUnits.get(k)!.add(route.unit);
          }
        });
        const cityUnitOf = (dir: 'in' | 'out', city: string): TimeUnit => commonUnit(cityUnits.get(`${dir}|${city}`) || []);

        routes.forEach(route => {
          const inUnit = cityUnitOf('in', route.destinationCity);
          const outUnit = cityUnitOf('out', route.originCity);
          // Inbound (destination city)
          if (!cityStatsMap.has(route.destinationCity)) {
            cityStatsMap.set(route.destinationCity, {
              inbound: { samples: [], onTimeSamples: 0, standardSum: 0, standardCount: 0, standardPercentageSum: 0, warningThresholdSum: 0, criticalThresholdSum: 0, thresholdCount: 0, routes: new Set() },
              outbound: { samples: [], onTimeSamples: 0, standardSum: 0, standardCount: 0, standardPercentageSum: 0, warningThresholdSum: 0, criticalThresholdSum: 0, thresholdCount: 0, routes: new Set() },
            });
          }
          const destStats = cityStatsMap.get(route.destinationCity)!;
          for (let i = 0; i < route.totalSamples; i++) {
            destStats.inbound.samples.push(convertUnit(route.jkActual, route.unit, inUnit));
          }
          destStats.inbound.onTimeSamples += route.onTimeSamples;
          destStats.inbound.standardSum += convertUnit(route.jkStandard, route.unit, inUnit) * route.totalSamples;
          destStats.inbound.standardCount += route.totalSamples;
          destStats.inbound.standardPercentageSum += route.standardPercentage * route.totalSamples;
          destStats.inbound.warningThresholdSum += route.warningThreshold * route.totalSamples;
          destStats.inbound.criticalThresholdSum += route.criticalThreshold * route.totalSamples;
          destStats.inbound.thresholdCount += route.totalSamples;
          destStats.inbound.routes.add(route.routeKey);

          // Outbound (origin city)
          if (!cityStatsMap.has(route.originCity)) {
            cityStatsMap.set(route.originCity, {
              inbound: { samples: [], onTimeSamples: 0, standardSum: 0, standardCount: 0, standardPercentageSum: 0, warningThresholdSum: 0, criticalThresholdSum: 0, thresholdCount: 0, routes: new Set() },
              outbound: { samples: [], onTimeSamples: 0, standardSum: 0, standardCount: 0, standardPercentageSum: 0, warningThresholdSum: 0, criticalThresholdSum: 0, thresholdCount: 0, routes: new Set() },
            });
          }
          const originStats = cityStatsMap.get(route.originCity)!;
          for (let i = 0; i < route.totalSamples; i++) {
            originStats.outbound.samples.push(convertUnit(route.jkActual, route.unit, outUnit));
          }
          originStats.outbound.onTimeSamples += route.onTimeSamples;
          originStats.outbound.standardSum += convertUnit(route.jkStandard, route.unit, outUnit) * route.totalSamples;
          originStats.outbound.standardCount += route.totalSamples;
          originStats.outbound.standardPercentageSum += route.standardPercentage * route.totalSamples;
          originStats.outbound.warningThresholdSum += route.warningThreshold * route.totalSamples;
          originStats.outbound.criticalThresholdSum += route.criticalThreshold * route.totalSamples;
          originStats.outbound.thresholdCount += route.totalSamples;
          originStats.outbound.routes.add(route.routeKey);
        });

        const cities: JKCityData[] = [];
        cityStatsMap.forEach((stats, cityName) => {
          const regionId = cityRegionMap.get(cityName);
          const regionName = regionId ? regionMap.get(regionId) || 'Unknown' : 'Unknown';

          // Inbound row
          if (stats.inbound.samples.length > 0) {
            const jkActual = stats.inbound.samples.reduce((sum, d) => sum + d, 0) / stats.inbound.samples.length;
            const jkStandard = stats.inbound.standardCount > 0 
              ? stats.inbound.standardSum / stats.inbound.standardCount 
              : 0;
            const deviation = jkActual - jkStandard;
            const onTimePercentage = stats.inbound.samples.length > 0 
              ? (stats.inbound.onTimeSamples / stats.inbound.samples.length) * 100 
              : 0;
            
            const standardPercentage = stats.inbound.thresholdCount > 0
              ? stats.inbound.standardPercentageSum / stats.inbound.thresholdCount
              : 85;
            const cityWarningThreshold = stats.inbound.thresholdCount > 0
              ? stats.inbound.warningThresholdSum / stats.inbound.thresholdCount
              : 80;
            const cityCriticalThreshold = stats.inbound.thresholdCount > 0
              ? stats.inbound.criticalThresholdSum / stats.inbound.thresholdCount
              : 75;
            
            const status: 'compliant' | 'warning' | 'critical' =
              onTimePercentage >= cityWarningThreshold ? 'compliant' :
              onTimePercentage >= cityCriticalThreshold ? 'warning' : 'critical';

            cities.push({
              unit: cityUnitOf('in', cityName),
              cityName,
              direction: 'inbound',
              regionName,
              routes: stats.inbound.routes.size,
              totalSamples: stats.inbound.samples.length,
              jkStandard,
              jkActual,
              deviation,
              onTimePercentage,
              standardPercentage,
              warningThreshold: cityWarningThreshold,
              criticalThreshold: cityCriticalThreshold,
              status,
            });
          }

          // Outbound row
          if (stats.outbound.samples.length > 0) {
            const jkActual = stats.outbound.samples.reduce((sum, d) => sum + d, 0) / stats.outbound.samples.length;
            const jkStandard = stats.outbound.standardCount > 0 
              ? stats.outbound.standardSum / stats.outbound.standardCount 
              : 0;
            const deviation = jkActual - jkStandard;
            const onTimePercentage = stats.outbound.samples.length > 0 
              ? (stats.outbound.onTimeSamples / stats.outbound.samples.length) * 100 
              : 0;
            
            const standardPercentage = stats.outbound.thresholdCount > 0
              ? stats.outbound.standardPercentageSum / stats.outbound.thresholdCount
              : 85;
            const cityWarningThreshold = stats.outbound.thresholdCount > 0
              ? stats.outbound.warningThresholdSum / stats.outbound.thresholdCount
              : 80;
            const cityCriticalThreshold = stats.outbound.thresholdCount > 0
              ? stats.outbound.criticalThresholdSum / stats.outbound.thresholdCount
              : 75;
            
            const status: 'compliant' | 'warning' | 'critical' =
              onTimePercentage >= cityWarningThreshold ? 'compliant' :
              onTimePercentage >= cityCriticalThreshold ? 'warning' : 'critical';

            cities.push({
              unit: cityUnitOf('out', cityName),
              cityName,
              direction: 'outbound',
              regionName,
              routes: stats.outbound.routes.size,
              totalSamples: stats.outbound.samples.length,
              jkStandard,
              jkActual,
              deviation,
              onTimePercentage,
              standardPercentage,
              warningThreshold: cityWarningThreshold,
              criticalThreshold: cityCriticalThreshold,
              status,
            });
          }
        });

        // 9. Build region data (aggregate from cities)
        const regionStatsMap = new Map<string, {
          inbound: {
            samples: number[];
            onTimeSamples: number;
            standardSum: number;
            standardCount: number;
            standardPercentageSum: number;
            warningThresholdSum: number;
            criticalThresholdSum: number;
            thresholdCount: number;
            routes: Set<string>;
            cities: Set<string>;
          };
          outbound: {
            samples: number[];
            onTimeSamples: number;
            standardSum: number;
            standardCount: number;
            standardPercentageSum: number;
            warningThresholdSum: number;
            criticalThresholdSum: number;
            thresholdCount: number;
            routes: Set<string>;
            cities: Set<string>;
          };
        }>();

        const regionUnits = new Map<string, Set<TimeUnit>>();
        cities.forEach(city => {
          const k = `${city.direction}|${city.regionName}`;
          if (!regionUnits.has(k)) regionUnits.set(k, new Set());
          regionUnits.get(k)!.add(city.unit);
        });
        const regionUnitOf = (dir: 'inbound' | 'outbound', region: string): TimeUnit => commonUnit(regionUnits.get(`${dir}|${region}`) || []);

        cities.forEach(city => {
          const rUnit = regionUnitOf(city.direction, city.regionName);
          if (!regionStatsMap.has(city.regionName)) {
            regionStatsMap.set(city.regionName, {
              inbound: { samples: [], onTimeSamples: 0, standardSum: 0, standardCount: 0, standardPercentageSum: 0, warningThresholdSum: 0, criticalThresholdSum: 0, thresholdCount: 0, routes: new Set(), cities: new Set() },
              outbound: { samples: [], onTimeSamples: 0, standardSum: 0, standardCount: 0, standardPercentageSum: 0, warningThresholdSum: 0, criticalThresholdSum: 0, thresholdCount: 0, routes: new Set(), cities: new Set() },
            });
          }

          const regionStats = regionStatsMap.get(city.regionName)!;
          const directionStats = city.direction === 'inbound' ? regionStats.inbound : regionStats.outbound;
          
          for (let i = 0; i < city.totalSamples; i++) {
            directionStats.samples.push(convertUnit(city.jkActual, city.unit, rUnit));
          }
          directionStats.onTimeSamples += (city.onTimePercentage / 100) * city.totalSamples;
          directionStats.standardSum += convertUnit(city.jkStandard, city.unit, rUnit) * city.totalSamples;
          directionStats.standardCount += city.totalSamples;
          directionStats.standardPercentageSum += city.standardPercentage * city.totalSamples;
          directionStats.warningThresholdSum += city.warningThreshold * city.totalSamples;
          directionStats.criticalThresholdSum += city.criticalThreshold * city.totalSamples;
          directionStats.thresholdCount += city.totalSamples;
          directionStats.cities.add(city.cityName);
        });

        const regions: JKRegionData[] = [];
        regionStatsMap.forEach((stats, regionName) => {
          // Inbound row
          if (stats.inbound.samples.length > 0) {
            const jkActual = stats.inbound.samples.reduce((sum, d) => sum + d, 0) / stats.inbound.samples.length;
            const jkStandard = stats.inbound.standardCount > 0 
              ? stats.inbound.standardSum / stats.inbound.standardCount 
              : 0;
            const deviation = jkActual - jkStandard;
            const onTimePercentage = stats.inbound.samples.length > 0 
              ? (stats.inbound.onTimeSamples / stats.inbound.samples.length) * 100 
              : 0;
            
            const standardPercentage = stats.inbound.thresholdCount > 0
              ? stats.inbound.standardPercentageSum / stats.inbound.thresholdCount
              : 85;
            const regionWarningThreshold = stats.inbound.thresholdCount > 0
              ? stats.inbound.warningThresholdSum / stats.inbound.thresholdCount
              : 80;
            const regionCriticalThreshold = stats.inbound.thresholdCount > 0
              ? stats.inbound.criticalThresholdSum / stats.inbound.thresholdCount
              : 75;
            
            const status: 'compliant' | 'warning' | 'critical' =
              onTimePercentage >= regionWarningThreshold ? 'compliant' :
              onTimePercentage >= regionCriticalThreshold ? 'warning' : 'critical';

            regions.push({
              unit: regionUnitOf('inbound', regionName),
              regionName,
              direction: 'inbound',
              cities: stats.inbound.cities.size,
              routes: stats.inbound.routes.size,
              totalSamples: stats.inbound.samples.length,
              jkStandard,
              jkActual,
              deviation,
              onTimePercentage,
              standardPercentage,
              warningThreshold: regionWarningThreshold,
              criticalThreshold: regionCriticalThreshold,
              status,
            });
          }

          // Outbound row
          if (stats.outbound.samples.length > 0) {
            const jkActual = stats.outbound.samples.reduce((sum, d) => sum + d, 0) / stats.outbound.samples.length;
            const jkStandard = stats.outbound.standardCount > 0 
              ? stats.outbound.standardSum / stats.outbound.standardCount 
              : 0;
            const deviation = jkActual - jkStandard;
            const onTimePercentage = stats.outbound.samples.length > 0 
              ? (stats.outbound.onTimeSamples / stats.outbound.samples.length) * 100 
              : 0;
            
            const standardPercentage = stats.outbound.thresholdCount > 0
              ? stats.outbound.standardPercentageSum / stats.outbound.thresholdCount
              : 85;
            const regionWarningThreshold = stats.outbound.thresholdCount > 0
              ? stats.outbound.warningThresholdSum / stats.outbound.thresholdCount
              : 80;
            const regionCriticalThreshold = stats.outbound.thresholdCount > 0
              ? stats.outbound.criticalThresholdSum / stats.outbound.thresholdCount
              : 75;
            
            const status: 'compliant' | 'warning' | 'critical' =
              onTimePercentage >= regionWarningThreshold ? 'compliant' :
              onTimePercentage >= regionCriticalThreshold ? 'warning' : 'critical';

            regions.push({
              unit: regionUnitOf('outbound', regionName),
              regionName,
              direction: 'outbound',
              cities: stats.outbound.cities.size,
              routes: stats.outbound.routes.size,
              totalSamples: stats.outbound.samples.length,
              jkStandard,
              jkActual,
              deviation,
              onTimePercentage,
              standardPercentage,
              warningThreshold: regionWarningThreshold,
              criticalThreshold: regionCriticalThreshold,
              status,
            });
          }
        });

        // 10. Build carrier data
        const carrierStatsMap = new Map<string, {
          routes: Set<string>;
          samples: number[];
          onTimeSamples: number;
          standardSum: number;
          standardCount: number;
          standardPercentageSum: number;
          warningThresholdSum: number;
          criticalThresholdSum: number;
          thresholdCount: number;
          problematicRoutes: number;
          products: Map<string, {
            routes: Set<string>;
            samples: number[];
            onTimeSamples: number;
            standardSum: number;
            standardCount: number;
            standardPercentageSum: number;
            warningThresholdSum: number;
            criticalThresholdSum: number;
            thresholdCount: number;
          }>;
        }>();

        const carrierUnits = new Map<string, Set<TimeUnit>>();
        routes.forEach(route => {
          for (const k of [`c|${route.carrier}`, `cp|${route.carrier}|${route.product}`, `p|${route.product}`, `pc|${route.product}|${route.carrier}`]) {
            if (!carrierUnits.has(k)) carrierUnits.set(k, new Set());
            carrierUnits.get(k)!.add(route.unit);
          }
        });
        const groupUnitOf = (k: string): TimeUnit => commonUnit(carrierUnits.get(k) || []);

        routes.forEach(route => {
          const cUnit = groupUnitOf(`c|${route.carrier}`);
          const cpUnit = groupUnitOf(`cp|${route.carrier}|${route.product}`);
          if (!carrierStatsMap.has(route.carrier)) {
            carrierStatsMap.set(route.carrier, {
              routes: new Set(),
              samples: [],
              onTimeSamples: 0,
              standardSum: 0,
              standardCount: 0,
              standardPercentageSum: 0,
              warningThresholdSum: 0,
              criticalThresholdSum: 0,
              thresholdCount: 0,
              problematicRoutes: 0,
              products: new Map(),
            });
          }

          const carrierStats = carrierStatsMap.get(route.carrier)!;
          carrierStats.routes.add(route.routeKey);
          for (let i = 0; i < route.totalSamples; i++) {
            carrierStats.samples.push(convertUnit(route.jkActual, route.unit, cUnit));
          }
          carrierStats.onTimeSamples += route.onTimeSamples;
          carrierStats.standardSum += convertUnit(route.jkStandard, route.unit, cUnit) * route.totalSamples;
          carrierStats.standardCount += route.totalSamples;
          carrierStats.standardPercentageSum += route.standardPercentage * route.totalSamples;
          carrierStats.warningThresholdSum += route.warningThreshold * route.totalSamples;
          carrierStats.criticalThresholdSum += route.criticalThreshold * route.totalSamples;
          carrierStats.thresholdCount += route.totalSamples;
          if (route.onTimePercentage <= route.criticalThreshold) {
            carrierStats.problematicRoutes++;
          }

          // Product breakdown
          if (!carrierStats.products.has(route.product)) {
            carrierStats.products.set(route.product, {
              routes: new Set(),
              samples: [],
              onTimeSamples: 0,
              standardSum: 0,
              standardCount: 0,
              standardPercentageSum: 0,
              warningThresholdSum: 0,
              criticalThresholdSum: 0,
              thresholdCount: 0,
            });
          }
          const productStats = carrierStats.products.get(route.product)!;
          productStats.routes.add(route.routeKey);
          for (let i = 0; i < route.totalSamples; i++) {
            productStats.samples.push(convertUnit(route.jkActual, route.unit, cpUnit));
          }
          productStats.onTimeSamples += route.onTimeSamples;
          productStats.standardSum += convertUnit(route.jkStandard, route.unit, cpUnit) * route.totalSamples;
          productStats.standardCount += route.totalSamples;
          productStats.standardPercentageSum += route.standardPercentage * route.totalSamples;
          productStats.warningThresholdSum += route.warningThreshold * route.totalSamples;
          productStats.criticalThresholdSum += route.criticalThreshold * route.totalSamples;
          productStats.thresholdCount += route.totalSamples;
        });

        const carriers: JKCarrierData[] = Array.from(carrierStatsMap.entries()).map(([carrier, stats]) => {
          const jkActual = stats.samples.length > 0 
            ? stats.samples.reduce((sum, d) => sum + d, 0) / stats.samples.length 
            : 0;
          const jkStandard = stats.standardCount > 0 
            ? stats.standardSum / stats.standardCount 
            : 0;
          const deviation = jkActual - jkStandard;
          const onTimePercentage = stats.samples.length > 0 
            ? (stats.onTimeSamples / stats.samples.length) * 100 
            : 0;
          
          const standardPercentage = stats.thresholdCount > 0
            ? stats.standardPercentageSum / stats.thresholdCount
            : 85;
          const carrierWarningThreshold = stats.thresholdCount > 0
            ? stats.warningThresholdSum / stats.thresholdCount
            : 80;
          const carrierCriticalThreshold = stats.thresholdCount > 0
            ? stats.criticalThresholdSum / stats.thresholdCount
            : 75;
          
          const status: 'compliant' | 'warning' | 'critical' =
            onTimePercentage >= carrierWarningThreshold ? 'compliant' :
            onTimePercentage >= carrierCriticalThreshold ? 'warning' : 'critical';

          const products: JKProductBreakdown[] = Array.from(stats.products.entries()).map(([product, pStats]) => {
            const pJkActual = pStats.samples.length > 0 
              ? pStats.samples.reduce((sum, d) => sum + d, 0) / pStats.samples.length 
              : 0;
            const pJkStandard = pStats.standardCount > 0 
              ? pStats.standardSum / pStats.standardCount 
              : 0;
            const pDeviation = pJkActual - pJkStandard;
            const pOnTimePercentage = pStats.samples.length > 0 
              ? (pStats.onTimeSamples / pStats.samples.length) * 100 
              : 0;
            
            const pStandardPercentage = pStats.thresholdCount > 0
              ? pStats.standardPercentageSum / pStats.thresholdCount
              : 85;
            const pWarningThreshold = pStats.thresholdCount > 0
              ? pStats.warningThresholdSum / pStats.thresholdCount
              : 80;
            const pCriticalThreshold = pStats.thresholdCount > 0
              ? pStats.criticalThresholdSum / pStats.thresholdCount
              : 75;
            
            let pStatus: 'compliant' | 'warning' | 'critical' = 'compliant';
            if (pOnTimePercentage <= pCriticalThreshold) pStatus = 'critical';
            else if (pOnTimePercentage < pWarningThreshold) pStatus = 'warning';

            return {
              unit: groupUnitOf(`cp|${carrier}|${product}`),
              product,
              routes: pStats.routes.size,
              totalSamples: pStats.samples.length,
              jkStandard: pJkStandard,
              jkActual: pJkActual,
              deviation: pDeviation,
              onTimePercentage: pOnTimePercentage,
              standardPercentage: pStandardPercentage,
              warningThreshold: pWarningThreshold,
              criticalThreshold: pCriticalThreshold,
              status: pStatus,
            };
          });

          return {
            unit: groupUnitOf(`c|${carrier}`),
            carrier,
            routes: stats.routes.size,
            totalSamples: stats.samples.length,
            jkStandard,
            jkActual,
            deviation,
            onTimePercentage,
            problematicRoutes: stats.problematicRoutes,
            standardPercentage,
            warningThreshold: carrierWarningThreshold,
            criticalThreshold: carrierCriticalThreshold,
            status,
            products,
          };
        });

        // 11. Build product data
        const productStatsMap = new Map<string, {
          routes: Set<string>;
          samples: number[];
          onTimeSamples: number;
          standardSum: number;
          standardCount: number;
          standardPercentageSum: number;
          warningThresholdSum: number;
          criticalThresholdSum: number;
          thresholdCount: number;
          problematicRoutes: number;
          carriers: Map<string, {
            routes: Set<string>;
            samples: number[];
            onTimeSamples: number;
            standardSum: number;
            standardCount: number;
            standardPercentageSum: number;
            warningThresholdSum: number;
            criticalThresholdSum: number;
            thresholdCount: number;
          }>;
        }>();

        routes.forEach(route => {
          const pUnit = groupUnitOf(`p|${route.product}`);
          const pcUnit = groupUnitOf(`pc|${route.product}|${route.carrier}`);
          if (!productStatsMap.has(route.product)) {
            productStatsMap.set(route.product, {
              routes: new Set(),
              samples: [],
              onTimeSamples: 0,
              standardSum: 0,
              standardCount: 0,
              standardPercentageSum: 0,
              warningThresholdSum: 0,
              criticalThresholdSum: 0,
              thresholdCount: 0,
              problematicRoutes: 0,
              carriers: new Map(),
            });
          }

          const productStats = productStatsMap.get(route.product)!;
          productStats.routes.add(route.routeKey);
          for (let i = 0; i < route.totalSamples; i++) {
            productStats.samples.push(convertUnit(route.jkActual, route.unit, pUnit));
          }
          productStats.onTimeSamples += route.onTimeSamples;
          productStats.standardSum += convertUnit(route.jkStandard, route.unit, pUnit) * route.totalSamples;
          productStats.standardCount += route.totalSamples;
          productStats.standardPercentageSum += route.standardPercentage * route.totalSamples;
          productStats.warningThresholdSum += route.warningThreshold * route.totalSamples;
          productStats.criticalThresholdSum += route.criticalThreshold * route.totalSamples;
          productStats.thresholdCount += route.totalSamples;
          if (route.onTimePercentage <= route.criticalThreshold) {
            productStats.problematicRoutes++;
          }

          // Carrier breakdown
          if (!productStats.carriers.has(route.carrier)) {
            productStats.carriers.set(route.carrier, {
              routes: new Set(),
              samples: [],
              onTimeSamples: 0,
              standardSum: 0,
              standardCount: 0,
              standardPercentageSum: 0,
              warningThresholdSum: 0,
              criticalThresholdSum: 0,
              thresholdCount: 0,
            });
          }
          const carrierStats = productStats.carriers.get(route.carrier)!;
          carrierStats.routes.add(route.routeKey);
          for (let i = 0; i < route.totalSamples; i++) {
            carrierStats.samples.push(convertUnit(route.jkActual, route.unit, pcUnit));
          }
          carrierStats.onTimeSamples += route.onTimeSamples;
          carrierStats.standardSum += convertUnit(route.jkStandard, route.unit, pcUnit) * route.totalSamples;
          carrierStats.standardCount += route.totalSamples;
        });

        const products: JKProductData[] = Array.from(productStatsMap.entries()).map(([product, stats]) => {
          const jkActual = stats.samples.length > 0 
            ? stats.samples.reduce((sum, d) => sum + d, 0) / stats.samples.length 
            : 0;
          const jkStandard = stats.standardCount > 0 
            ? stats.standardSum / stats.standardCount 
            : 0;
          const deviation = jkActual - jkStandard;
          const onTimePercentage = stats.samples.length > 0 
            ? (stats.onTimeSamples / stats.samples.length) * 100 
            : 0;
          
          const standardPercentage = stats.thresholdCount > 0
            ? stats.standardPercentageSum / stats.thresholdCount
            : 85;
          const productWarningThreshold = stats.thresholdCount > 0
            ? stats.warningThresholdSum / stats.thresholdCount
            : 80;
          const productCriticalThreshold = stats.thresholdCount > 0
            ? stats.criticalThresholdSum / stats.thresholdCount
            : 75;
          
          const status: 'compliant' | 'warning' | 'critical' =
            onTimePercentage >= productWarningThreshold ? 'compliant' :
            onTimePercentage >= productCriticalThreshold ? 'warning' : 'critical';

          const carriers: JKCarrierBreakdown[] = Array.from(stats.carriers.entries()).map(([carrier, cStats]) => {
            const cJkActual = cStats.samples.length > 0 
              ? cStats.samples.reduce((sum, d) => sum + d, 0) / cStats.samples.length 
              : 0;
            const cJkStandard = cStats.standardCount > 0 
              ? cStats.standardSum / cStats.standardCount 
              : 0;
            const cDeviation = cJkActual - cJkStandard;
            const cOnTimePercentage = cStats.samples.length > 0 
              ? (cStats.onTimeSamples / cStats.samples.length) * 100 
              : 0;
            
            const cStandardPercentage = cStats.thresholdCount > 0
              ? cStats.standardPercentageSum / cStats.thresholdCount
              : 85;
            const cWarningThreshold = cStats.thresholdCount > 0
              ? cStats.warningThresholdSum / cStats.thresholdCount
              : 80;
            const cCriticalThreshold = cStats.thresholdCount > 0
              ? cStats.criticalThresholdSum / cStats.thresholdCount
              : 75;
            
            let cStatus: 'compliant' | 'warning' | 'critical' = 'compliant';
            if (cOnTimePercentage <= cCriticalThreshold) cStatus = 'critical';
            else if (cOnTimePercentage < cWarningThreshold) cStatus = 'warning';

            return {
              unit: groupUnitOf(`pc|${product}|${carrier}`),
              carrier,
              routes: cStats.routes.size,
              totalSamples: cStats.samples.length,
              jkStandard: cJkStandard,
              jkActual: cJkActual,
              deviation: cDeviation,
              onTimePercentage: cOnTimePercentage,
              standardPercentage: cStandardPercentage,
              warningThreshold: cWarningThreshold,
              criticalThreshold: cCriticalThreshold,
              status: cStatus,
            };
          });

          return {
            unit: groupUnitOf(`p|${product}`),
            product,
            routes: stats.routes.size,
            totalSamples: stats.samples.length,
            jkStandard,
            jkActual,
            deviation,
            onTimePercentage,
            problematicRoutes: stats.problematicRoutes,
            standardPercentage,
            warningThreshold: productWarningThreshold,
            criticalThreshold: productCriticalThreshold,
            status,
            carriers,
          };
        });

        // 12. Calculate weekly samples
        const weeklyMap = new Map<string, { start: Date; end: Date; count: number }>();
        (shipments || []).forEach(shipment => {
          if (!shipment.sent_at) return;
          const date = new Date(shipment.sent_at);
          const weekStart = new Date(date);
          weekStart.setDate(date.getDate() - date.getDay()); // Start of week (Sunday)
          weekStart.setHours(0, 0, 0, 0);
          
          const weekEnd = new Date(weekStart);
          weekEnd.setDate(weekStart.getDate() + 6); // End of week (Saturday)
          weekEnd.setHours(23, 59, 59, 999);

          const weekKey = `${weekStart.getFullYear()}-W${String(Math.ceil((weekStart.getDate() + weekStart.getDay()) / 7)).padStart(2, '0')}`;
          
          if (!weeklyMap.has(weekKey)) {
            weeklyMap.set(weekKey, { start: weekStart, end: weekEnd, count: 0 });
          }
          weeklyMap.get(weekKey)!.count++;
        });

        const weekly: WeeklySample[] = Array.from(weeklyMap.entries())
          .map(([week, data]) => ({
            week,
            weekStart: data.start.toISOString().split('T')[0],
            weekEnd: data.end.toISOString().split('T')[0],
            samples: data.count,
          }))
          .sort((a, b) => a.week.localeCompare(b.week));

        // 13. Calculate global metrics
        const totalSamples = routes.reduce((sum, r) => sum + r.totalSamples, 0);
        const totalOnTimeSamples = routes.reduce((sum, r) => sum + r.onTimeSamples, 0);
        const metricsUnit = commonUnit(routes.map(r => r.unit));
        const weightedStandardSum = routes.reduce((sum, r) => sum + convertUnit(r.jkStandard, r.unit, metricsUnit) * r.totalSamples, 0);
        const weightedActualSum = routes.reduce((sum, r) => sum + convertUnit(r.jkActual, r.unit, metricsUnit) * r.totalSamples, 0);
        const problematicRoutes = routes.filter(r => r.onTimePercentage <= r.criticalThreshold).length;

        const globalMetrics: JKMetrics = {
          unit: metricsUnit,
          totalSamples,
          avgJKStandard: totalSamples > 0 ? weightedStandardSum / totalSamples : 0,
          avgJKActual: totalSamples > 0 ? weightedActualSum / totalSamples : 0,
          onTimePercentage: totalSamples > 0 ? (totalOnTimeSamples / totalSamples) * 100 : 0,
          onTimeSamples: totalOnTimeSamples,
          problematicRoutes,
        };

        // 14. Set state
        setRouteData(routes);
        setCityData(cities);
        setRegionData(regions);
        setCarrierData(carriers);
        setProductData(products);
        setWeeklySamples(weekly);
        setMetrics(globalMetrics);
      } catch (err) {
        setError(err as Error);
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
    filters?.region,
    accountTimezone,
  ]);

  return {
    routeData,
    cityData,
    regionData,
    carrierData,
    productData,
    weeklySamples,
    metrics,
    maxMeasure,
    globalWarningThreshold,
    globalCriticalThreshold,
    loading,
    error,
  };
}
