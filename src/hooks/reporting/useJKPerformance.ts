import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { adjustStartDateForFilter, adjustEndDateForFilter } from '@/lib/dateUtils';
import { useEffectiveAccountId } from '../useEffectiveAccountId';

export interface JKRouteData {
  routeKey: string;
  originCity: string;
  destinationCity: string;
  carrier: string;
  product: string;
  totalSamples: number;
  jkStandard: number; //  jkStandard: number;
  jkActual: number; // days to reach STD % target
  deviation: number; // actual - standard
  onTimePercentage: number;
  onTimeSamples: number;
  beforeStandardSamples: number; // samples delivered before standard
  afterStandardSamples: number; // samples delivered after standard
  distribution: Map<number, number>; // day -> count
  standardPercentage: number; // target percentage from delivery_standards (e.g., 85%)
  warningThreshold: number; // warning threshold percentage (e.g., 80%)
  criticalThreshold: number; // critical threshold percentage (e.g., 75%)
  status: 'compliant' | 'warning' | 'critical';
}

export interface JKCityData {
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
  regionName: string;
  direction: 'inbound' | 'outbound';
  cities: number;
  routes: number;
  totalSamples: number;
  jkStandard: number;
  jkActual: number;
  deviation: number;
  onTimePercentage: number;
  status: 'compliant' | 'warning' | 'critical';
}

export interface JKCarrierData {
  carrier: string;
  routes: number;
  totalSamples: number;
  jkStandard: number;
  jkActual: number;
  deviation: number;
  onTimePercentage: number;
  problematicRoutes: number;
  status: 'compliant' | 'warning' | 'critical';
  products: JKProductBreakdown[];
}

export interface JKProductData {
  product: string;
  routes: number;
  totalSamples: number;
  jkStandard: number;
  jkActual: number;
  deviation: number;
  onTimePercentage: number;
  problematicRoutes: number;
  status: 'compliant' | 'warning' | 'critical';
  carriers: JKCarrierBreakdown[];
}

export interface JKProductBreakdown {
  product: string;
  routes: number;
  totalSamples: number;
  jkStandard: number;
  jkActual: number;
  deviation: number;
  onTimePercentage: number;
  status: 'compliant' | 'warning' | 'critical';
}

export interface JKCarrierBreakdown {
  carrier: string;
  routes: number;
  totalSamples: number;
  jkStandard: number;
  jkActual: number;
  deviation: number;
  onTimePercentage: number;
  status: 'compliant' | 'warning' | 'critical';
}

export interface WeeklySample {
  week: string; // ISO week (YYYY-WW)
  weekStart: string; // Date
  weekEnd: string; // Date
  samples: number;
}

export interface JKMetrics {
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
  const activeAccountId = effectiveAccountId || accountId;

  const [routeData, setRouteData] = useState<JKRouteData[]>([]);
  const [cityData, setCityData] = useState<JKCityData[]>([]);
  const [regionData, setRegionData] = useState<JKRegionData[]>([]);
  const [carrierData, setCarrierData] = useState<JKCarrierData[]>([]);
  const [productData, setProductData] = useState<JKProductData[]>([]);
  const [weeklySamples, setWeeklySamples] = useState<WeeklySample[]>([]);
  const [metrics, setMetrics] = useState<JKMetrics>({
    totalSamples: 0,
    avgJKStandard: 0,
    avgJKActual: 0,
    onTimePercentage: 0,
    onTimeSamples: 0,
    problematicRoutes: 0,
  });
  const [maxDays, setMaxDays] = useState(0);
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

          if (filters?.startDate && filters.startDate !== '') query = query.gte('sent_at', adjustStartDateForFilter(filters.startDate))
          if (filters?.endDate && filters.endDate !== '') query = query.lte('sent_at', adjustEndDateForFilter(filters.endDate))
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
        const standardsMap = new Map<string, { jkStandard: number; successPercentage: number; warningThreshold: number; criticalThreshold: number }>();
        (standards || []).forEach(std => {
          const carrierName = carrierMap.get(std.carrier_id);
          const productName = productMap.get(std.product_id);
          const originName = cityMap.get(std.origin_city_id);
          const destName = cityMap.get(std.destination_city_id);

          if (carrierName && productName && originName && destName) {
            const key = `${carrierName}|${productName}|${originName}|${destName}`;
            const jkStandard = std.time_unit === 'days' 
              ? std.standard_time 
              : Math.round(std.standard_time / 24);
            // Calculate warning and critical thresholds
            const successPct = std.success_percentage || 95;
            const warningThreshold = std.threshold_type === 'relative' 
              ? successPct - (std.warning_threshold || 5)
              : (std.warning_threshold || 5);
            const criticalThreshold = std.threshold_type === 'relative'
              ? successPct - (std.critical_threshold || 10)
              : (std.critical_threshold || 10);
            
            standardsMap.set(key, {
              jkStandard: jkStandard || 0,
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
          samples: number[];
          onTimeSamples: number;
          jkStandard: number;
          distribution: Map<number, number>;
        }>();

        let calculatedMaxDays = 0;

        (shipments || []).forEach(shipment => {
          const key = `${shipment.carrier_name}|${shipment.product_name}|${shipment.origin_city_name}|${shipment.destination_city_name}`;
          const standard = standardsMap.get(key);
          const days = shipment.business_transit_days || 0;

          if (days > calculatedMaxDays) {
            calculatedMaxDays = days;
          }

          if (!routeMap.has(key)) {
            routeMap.set(key, {
              originCity: shipment.origin_city_name,
              destinationCity: shipment.destination_city_name,
              carrier: shipment.carrier_name,
              product: shipment.product_name,
              samples: [],
              onTimeSamples: 0,
              jkStandard: standard?.jkStandard || 0,
              distribution: new Map(),
            });
          }

          const route = routeMap.get(key)!;
          route.samples.push(days);
          
          // Update distribution
          const currentCount = route.distribution.get(days) || 0;
          route.distribution.set(days, currentCount + 1);

          // Check if on-time
          if (standard && days <= standard.jkStandard) {
            route.onTimeSamples++;
          }
        });

        setMaxDays(calculatedMaxDays);

        // 7. Build route data
        const routes: JKRouteData[] = Array.from(routeMap.entries()).map(([key, route]) => {
          const totalSamples = route.samples.length;
          const standard = standardsMap.get(key);
          
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
          
          const deviation = jkActual - route.jkStandard;
          const onTimePercentage = totalSamples > 0 
            ? (route.onTimeSamples / totalSamples) * 100 
            : 0;

          const routeWarningThreshold = standard?.warningThreshold || warningThreshold;
          const routeCriticalThreshold = standard?.criticalThreshold || criticalThreshold;
          
          let status: 'compliant' | 'warning' | 'critical' = 'compliant';
          if (onTimePercentage <= routeCriticalThreshold) {
            status = 'critical';
          } else if (onTimePercentage < routeWarningThreshold) {
            status = 'warning';
          }

          const beforeStandardSamples = route.samples.filter(d => d < route.jkStandard).length;
          const afterStandardSamples = route.samples.filter(d => d > route.jkStandard).length;
          
          return {
            routeKey: key,
            originCity: route.originCity,
            destinationCity: route.destinationCity,
            carrier: route.carrier,
            product: route.product,
            totalSamples,
            jkStandard: route.jkStandard,
            jkActual,
            deviation,
            onTimePercentage,
            onTimeSamples: route.onTimeSamples,
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

        routes.forEach(route => {
          // Inbound (destination city)
          if (!cityStatsMap.has(route.destinationCity)) {
            cityStatsMap.set(route.destinationCity, {
              inbound: { samples: [], onTimeSamples: 0, standardSum: 0, standardCount: 0, standardPercentageSum: 0, warningThresholdSum: 0, criticalThresholdSum: 0, thresholdCount: 0, routes: new Set() },
              outbound: { samples: [], onTimeSamples: 0, standardSum: 0, standardCount: 0, standardPercentageSum: 0, warningThresholdSum: 0, criticalThresholdSum: 0, thresholdCount: 0, routes: new Set() },
            });
          }
          const destStats = cityStatsMap.get(route.destinationCity)!;
          for (let i = 0; i < route.totalSamples; i++) {
            destStats.inbound.samples.push(route.jkActual);
          }
          destStats.inbound.onTimeSamples += route.onTimeSamples;
          destStats.inbound.standardSum += route.jkStandard * route.totalSamples;
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
            originStats.outbound.samples.push(route.jkActual);
          }
          originStats.outbound.onTimeSamples += route.onTimeSamples;
          originStats.outbound.standardSum += route.jkStandard * route.totalSamples;
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
            
            let status: 'compliant' | 'warning' | 'critical' = 'compliant';
            if (onTimePercentage <= cityCriticalThreshold) status = 'critical';
            else if (onTimePercentage < cityWarningThreshold) status = 'warning';

            cities.push({
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
            
            let status: 'compliant' | 'warning' | 'critical' = 'compliant';
            if (onTimePercentage <= cityCriticalThreshold) status = 'critical';
            else if (onTimePercentage < cityWarningThreshold) status = 'warning';

            cities.push({
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
            routes: Set<string>;
            cities: Set<string>;
          };
          outbound: {
            samples: number[];
            onTimeSamples: number;
            standardSum: number;
            standardCount: number;
            routes: Set<string>;
            cities: Set<string>;
          };
        }>();

        cities.forEach(city => {
          if (!regionStatsMap.has(city.regionName)) {
            regionStatsMap.set(city.regionName, {
              inbound: { samples: [], onTimeSamples: 0, standardSum: 0, standardCount: 0, routes: new Set(), cities: new Set() },
              outbound: { samples: [], onTimeSamples: 0, standardSum: 0, standardCount: 0, routes: new Set(), cities: new Set() },
            });
          }

          const regionStats = regionStatsMap.get(city.regionName)!;
          const directionStats = city.direction === 'inbound' ? regionStats.inbound : regionStats.outbound;
          
          for (let i = 0; i < city.totalSamples; i++) {
            directionStats.samples.push(city.jkActual);
          }
          directionStats.onTimeSamples += (city.onTimePercentage / 100) * city.totalSamples;
          directionStats.standardSum += city.jkStandard * city.totalSamples;
          directionStats.standardCount += city.totalSamples;
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
            
            let status: 'compliant' | 'warning' | 'critical' = 'compliant';
            if (onTimePercentage < 90) status = 'critical';
            else if (onTimePercentage < 95) status = 'warning';

            regions.push({
              regionName,
              direction: 'inbound',
              cities: stats.inbound.cities.size,
              routes: stats.inbound.routes.size,
              totalSamples: stats.inbound.samples.length,
              jkStandard,
              jkActual,
              deviation,
              onTimePercentage,
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
            
            let status: 'compliant' | 'warning' | 'critical' = 'compliant';
            if (onTimePercentage < 90) status = 'critical';
            else if (onTimePercentage < 95) status = 'warning';

            regions.push({
              regionName,
              direction: 'outbound',
              cities: stats.outbound.cities.size,
              routes: stats.outbound.routes.size,
              totalSamples: stats.outbound.samples.length,
              jkStandard,
              jkActual,
              deviation,
              onTimePercentage,
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
          problematicRoutes: number;
          products: Map<string, {
            routes: Set<string>;
            samples: number[];
            onTimeSamples: number;
            standardSum: number;
            standardCount: number;
          }>;
        }>();

        routes.forEach(route => {
          if (!carrierStatsMap.has(route.carrier)) {
            carrierStatsMap.set(route.carrier, {
              routes: new Set(),
              samples: [],
              onTimeSamples: 0,
              standardSum: 0,
              standardCount: 0,
              problematicRoutes: 0,
              products: new Map(),
            });
          }

          const carrierStats = carrierStatsMap.get(route.carrier)!;
          carrierStats.routes.add(route.routeKey);
          for (let i = 0; i < route.totalSamples; i++) {
            carrierStats.samples.push(route.jkActual);
          }
          carrierStats.onTimeSamples += route.onTimeSamples;
          carrierStats.standardSum += route.jkStandard * route.totalSamples;
          carrierStats.standardCount += route.totalSamples;
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
            });
          }
          const productStats = carrierStats.products.get(route.product)!;
          productStats.routes.add(route.routeKey);
          for (let i = 0; i < route.totalSamples; i++) {
            productStats.samples.push(route.jkActual);
          }
          productStats.onTimeSamples += route.onTimeSamples;
          productStats.standardSum += route.jkStandard * route.totalSamples;
          productStats.standardCount += route.totalSamples;
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
          
          let status: 'compliant' | 'warning' | 'critical' = 'compliant';
          if (onTimePercentage < 90) status = 'critical';
          else if (onTimePercentage < 95) status = 'warning';

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
            
            let pStatus: 'compliant' | 'warning' | 'critical' = 'compliant';
            if (pOnTimePercentage < 90) pStatus = 'critical';
            else if (pOnTimePercentage < 95) pStatus = 'warning';

            return {
              product,
              routes: pStats.routes.size,
              totalSamples: pStats.samples.length,
              jkStandard: pJkStandard,
              jkActual: pJkActual,
              deviation: pDeviation,
              onTimePercentage: pOnTimePercentage,
              status: pStatus,
            };
          });

          return {
            carrier,
            routes: stats.routes.size,
            totalSamples: stats.samples.length,
            jkStandard,
            jkActual,
            deviation,
            onTimePercentage,
            problematicRoutes: stats.problematicRoutes,
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
          problematicRoutes: number;
          carriers: Map<string, {
            routes: Set<string>;
            samples: number[];
            onTimeSamples: number;
            standardSum: number;
            standardCount: number;
          }>;
        }>();

        routes.forEach(route => {
          if (!productStatsMap.has(route.product)) {
            productStatsMap.set(route.product, {
              routes: new Set(),
              samples: [],
              onTimeSamples: 0,
              standardSum: 0,
              standardCount: 0,
              problematicRoutes: 0,
              carriers: new Map(),
            });
          }

          const productStats = productStatsMap.get(route.product)!;
          productStats.routes.add(route.routeKey);
          for (let i = 0; i < route.totalSamples; i++) {
            productStats.samples.push(route.jkActual);
          }
          productStats.onTimeSamples += route.onTimeSamples;
          productStats.standardSum += route.jkStandard * route.totalSamples;
          productStats.standardCount += route.totalSamples;
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
            });
          }
          const carrierStats = productStats.carriers.get(route.carrier)!;
          carrierStats.routes.add(route.routeKey);
          for (let i = 0; i < route.totalSamples; i++) {
            carrierStats.samples.push(route.jkActual);
          }
          carrierStats.onTimeSamples += route.onTimeSamples;
          carrierStats.standardSum += route.jkStandard * route.totalSamples;
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
          
          let status: 'compliant' | 'warning' | 'critical' = 'compliant';
          if (onTimePercentage < 90) status = 'critical';
          else if (onTimePercentage < 95) status = 'warning';

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
            
            let cStatus: 'compliant' | 'warning' | 'critical' = 'compliant';
            if (cOnTimePercentage < 90) cStatus = 'critical';
            else if (cOnTimePercentage < 95) cStatus = 'warning';

            return {
              carrier,
              routes: cStats.routes.size,
              totalSamples: cStats.samples.length,
              jkStandard: cJkStandard,
              jkActual: cJkActual,
              deviation: cDeviation,
              onTimePercentage: cOnTimePercentage,
              status: cStatus,
            };
          });

          return {
            product,
            routes: stats.routes.size,
            totalSamples: stats.samples.length,
            jkStandard,
            jkActual,
            deviation,
            onTimePercentage,
            problematicRoutes: stats.problematicRoutes,
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
        const weightedStandardSum = routes.reduce((sum, r) => sum + r.jkStandard * r.totalSamples, 0);
        const weightedActualSum = routes.reduce((sum, r) => sum + r.jkActual * r.totalSamples, 0);
        const problematicRoutes = routes.filter(r => r.onTimePercentage <= r.criticalThreshold).length;

        const globalMetrics: JKMetrics = {
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
  ]);

  return {
    routeData,
    cityData,
    regionData,
    carrierData,
    productData,
    weeklySamples,
    metrics,
    maxDays,
    globalWarningThreshold,
    globalCriticalThreshold,
    loading,
    error,
  };
}
