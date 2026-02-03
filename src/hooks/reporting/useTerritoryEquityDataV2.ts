import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { adjustStartDateForFilter, adjustEndDateForFilter } from '@/lib/dateUtils';
import { 
  loadBaseData, 
  calculateRouteMetrics, 
  aggregateInbound, 
  aggregateOutbound,
  aggregateCity,
  aggregateRegion,
  type BaseSample,
  type RouteMetrics
} from '@/lib/e2eCalculations';
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

        // 1. Load base data from ONE DB + SLA standards
        const baseSamples = await loadBaseData(activeAccountId, filters);

        // 2. Group by route and calculate route-level metrics
        const routeMap = new Map<string, BaseSample[]>();
        
        for (const sample of baseSamples) {
          const routeKey = `${sample.originCityId}-${sample.destinationCityId}-${sample.carrierId}-${sample.productId}`;
          if (!routeMap.has(routeKey)) {
            routeMap.set(routeKey, []);
          }
          routeMap.get(routeKey)!.push(sample);
        }

        const routeMetrics: RouteMetrics[] = [];
        for (const [routeKey, samples] of routeMap.entries()) {
          const metrics = calculateRouteMetrics(samples);
          routeMetrics.push(metrics);
        }

        // 3. Load topology data
        const [citiesRes, regionsRes] = await Promise.all([
          supabase.from('cities').select('*').eq('account_id', activeAccountId),
          supabase.from('regions').select('*').eq('account_id', activeAccountId),
        ]);

        if (citiesRes.error) throw citiesRes.error;
        if (regionsRes.error) throw regionsRes.error;

        const cities = citiesRes.data || [];
        const regions = regionsRes.data || [];

        // 4. Build city-level data with inbound/outbound aggregation
        const cityDataMap = new Map<string, CityEquityData>();

        for (const city of cities) {
          const inboundMetrics = aggregateInbound(routeMetrics, city.id);
          const outboundMetrics = aggregateOutbound(routeMetrics, city.id);
          const combinedMetrics = aggregateCity(inboundMetrics, outboundMetrics);

          cityDataMap.set(city.id, {
            cityId: city.id,
            cityName: city.name,
            regionId: city.region_id,
            regionName: regions.find(r => r.id === city.region_id)?.name || null,
            classification: city.classification,
            population: city.population,
            latitude: city.latitude,
            longitude: city.longitude,
            actualPercentage: combinedMetrics.actualPercentage,
            standardPercentage: combinedMetrics.standardPercentage,
            actualDays: combinedMetrics.jkActual,
            standardDays: combinedMetrics.standardDays,
            totalShipments: combinedMetrics.totalSamples,
            status: combinedMetrics.status,
            compliantShipments: combinedMetrics.compliantSamples,
            inboundShipments: inboundMetrics.totalSamples,
            inboundCompliant: inboundMetrics.compliantSamples,
            inboundPercentage: inboundMetrics.actualPercentage,
            inboundStandardPercentage: inboundMetrics.standardPercentage,
            inboundStandardDays: inboundMetrics.standardDays,
            inboundActualDays: inboundMetrics.jkActual,
            inboundDeviation: inboundMetrics.deviation,
            outboundShipments: outboundMetrics.totalSamples,
            outboundCompliant: outboundMetrics.compliantSamples,
            outboundPercentage: outboundMetrics.actualPercentage,
            outboundStandardPercentage: outboundMetrics.standardPercentage,
            outboundStandardDays: outboundMetrics.standardDays,
            outboundActualDays: outboundMetrics.jkActual,
            outboundDeviation: outboundMetrics.deviation,
          });
        }

        // 5. Build region-level data
        const regionDataMap = new Map<string, RegionEquityData>();

        for (const region of regions) {
          const regionCities = Array.from(cityDataMap.values()).filter(
            c => c.regionId === region.id
          );
          
          const regionMetrics = aggregateRegion(
            regionCities.map(c => ({
              totalSamples: c.totalShipments,
              compliantSamples: c.compliantShipments,
              actualPercentage: c.actualPercentage,
              actualDays: c.actualDays,
              jkActual: c.actualDays,
              standardPercentage: c.standardPercentage,
              standardDays: c.standardDays,
              deviation: c.deviation,
              status: c.status,
            }))
          );

          regionDataMap.set(region.id, {
            regionId: region.id,
            regionName: region.name,
            actualPercentage: regionMetrics.actualPercentage,
            standardPercentage: regionMetrics.standardPercentage,
            actualDays: regionMetrics.jkActual,
            standardDays: regionMetrics.standardDays,
            deviation: regionMetrics.deviation,
            compliantShipments: regionMetrics.compliantSamples,
            totalShipments: regionMetrics.totalSamples,
            status: combinedMetrics.status,
            cities: regionCities,
          });
        }

        // 6. Calculate global metrics
        const allCities = Array.from(cityDataMap.values());
        const globalMetrics = aggregateRegion(
          allCities.map(c => ({
            totalSamples: c.totalShipments,
            compliantSamples: c.compliantShipments,
            actualPercentage: c.actualPercentage,
            actualDays: c.actualDays,
            jkActual: c.actualDays,
            standardPercentage: c.standardPercentage,
            standardDays: c.standardDays,
            deviation: c.deviation,
            status: c.status,
          }))
        );

        setMetrics({
          compliantShipments: globalMetrics.compliantSamples,
          actualPercentage: globalMetrics.actualPercentage,
          standardPercentage: globalMetrics.standardPercentage,
          actualDays: globalMetrics.jkActual,
          standardDays: globalMetrics.standardDays,
          deviation: globalMetrics.deviation,
        });

        setCityData(allCities);
        setRegionData(Array.from(regionDataMap.values()));

      } catch (err: any) {
        console.error('[useTerritoryEquityDataV2] Error:', err);
        setError(err);
      } finally {
        setLoading(false);
      }
    }

    fetchData();
  }, [activeAccountId, filters]);

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
