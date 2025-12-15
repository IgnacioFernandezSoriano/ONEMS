import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import type {
  CityEquityData,
  RegionEquityData,
  TerritoryEquityMetrics,
  TerritoryEquityFilters,
} from '@/types/reporting';

export function useTerritoryEquityData(
  accountId: string | undefined,
  filters?: TerritoryEquityFilters
) {
  const [cityData, setCityData] = useState<CityEquityData[]>([]);
  const [regionData, setRegionData] = useState<RegionEquityData[]>([]);
  const [metrics, setMetrics] = useState<TerritoryEquityMetrics | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    if (!accountId) {
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
            supabase.from('cities').select('*').eq('account_id', accountId),
            supabase.from('regions').select('*').eq('account_id', accountId),
            supabase.from('carriers').select('id, name').eq('account_id', accountId),
            supabase.from('products').select('id, description').eq('account_id', accountId),
            supabase.from('delivery_standards').select('*').eq('account_id', accountId),
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

        // Default thresholds (can be overridden by delivery_standards per route)
        const defaultWarningThreshold = 85;
        const defaultCriticalThreshold = 75;

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
        const productDescToIdMap = new Map(products.map((p) => [p.description, p.id]));

        // Standards map: "carrier_id|product_id|origin_id|dest_id" → standard
        const standardsMap = new Map(
          standards.map((s) => [
            `${s.carrier_id}|${s.product_id}|${s.origin_city_id}|${s.destination_city_id}`,
            s,
          ])
        );

        // 3. Load shipments with filters
        let query = supabase.from('one_db').select('*').eq('account_id', accountId);

        if (filters?.startDate) query = query.gte('sent_at', filters.startDate);
        if (filters?.endDate) query = query.lte('sent_at', filters.endDate);
        if (filters?.carrier) query = query.eq('carrier_name', filters.carrier);
        if (filters?.product) query = query.eq('product_name', filters.product);
        if (filters?.originCity) query = query.eq('origin_city_name', filters.originCity);
        if (filters?.destinationCity) query = query.eq('destination_city_name', filters.destinationCity);

        const { data: shipments, error: shipmentsError } = await query;
        if (shipmentsError) throw shipmentsError;

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
            inbound: { total: number; compliant: number };
            outbound: { total: number; compliant: number };
            standardsSum: number;
            standardsCount: number;
          }
        >();

        shipments.forEach((shipment) => {
          // Process as INBOUND (destination)
          const destCity = shipment.destination_city_name;
          if (!cityStatsMap.has(destCity)) {
            cityStatsMap.set(destCity, {
              inbound: { total: 0, compliant: 0 },
              outbound: { total: 0, compliant: 0 },
              standardsSum: 0,
              standardsCount: 0,
            });
          }

          const destStats = cityStatsMap.get(destCity)!;
          destStats.inbound.total++;
          if (shipment.on_time_delivery) destStats.inbound.compliant++;

          // Lookup standard for this route
          const carrierId = carrierNameToIdMap.get(shipment.carrier_name);
          const productId = productDescToIdMap.get(shipment.product_name);
          const originCityId = cityNameToIdMap.get(shipment.origin_city_name);
          const destCityId = cityNameToIdMap.get(shipment.destination_city_name);

          if (carrierId && productId && originCityId && destCityId) {
            const key = `${carrierId}|${productId}|${originCityId}|${destCityId}`;
            const standard = standardsMap.get(key);
            if (standard && standard.success_percentage) {
              destStats.standardsSum += standard.success_percentage;
              destStats.standardsCount++;
            }
          }

          // Process as OUTBOUND (origin)
          const originCity = shipment.origin_city_name;
          if (!cityStatsMap.has(originCity)) {
            cityStatsMap.set(originCity, {
              inbound: { total: 0, compliant: 0 },
              outbound: { total: 0, compliant: 0 },
              standardsSum: 0,
              standardsCount: 0,
            });
          }

          const originStats = cityStatsMap.get(originCity)!;
          originStats.outbound.total++;
          if (shipment.on_time_delivery) originStats.outbound.compliant++;
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

            const totalShipments = stats.inbound.total + stats.outbound.total;
            const compliantShipments = stats.inbound.compliant + stats.outbound.compliant;
            const actualPercentage = totalShipments > 0 ? (compliantShipments / totalShipments) * 100 : 0;

            // Calculate weighted average standard
            const standardPercentage =
              stats.standardsCount > 0 ? stats.standardsSum / stats.standardsCount : 95;

            const deviation = actualPercentage - standardPercentage;

            // Determine status
            let status: 'compliant' | 'warning' | 'critical' = 'compliant';
            if (actualPercentage < standardPercentage) {
              if (actualPercentage < defaultCriticalThreshold) {
                status = 'critical';
              } else if (actualPercentage < defaultWarningThreshold) {
                status = 'warning';
              }
            }

            const inboundPercentage =
              stats.inbound.total > 0 ? (stats.inbound.compliant / stats.inbound.total) * 100 : 0;
            const outboundPercentage =
              stats.outbound.total > 0 ? (stats.outbound.compliant / stats.outbound.total) * 100 : 0;
            const directionGap = Math.abs(inboundPercentage - outboundPercentage);

            return {
              cityId,
              cityName,
              regionId,
              regionName,
              classification,
              population,
              totalShipments,
              compliantShipments,
              standardPercentage,
              actualPercentage,
              deviation,
              status,
              inboundShipments: stats.inbound.total,
              inboundCompliant: stats.inbound.compliant,
              inboundPercentage,
              outboundShipments: stats.outbound.total,
              outboundCompliant: stats.outbound.compliant,
              outboundPercentage,
              directionGap,
              accountId,
            };
          })
          .filter((c): c is CityEquityData => c !== null);

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
          filteredCityData = filteredCityData.filter((c) => c.regionId === filters.region);
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
        }));
        const topWorstCities = sortedByDeviation
          .slice(-3)
          .reverse()
          .map((c) => ({
            cityName: c.cityName,
            actualPercentage: c.actualPercentage,
            deviation: c.deviation,
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
            underservedCities: number;
            inboundShipments: number;
            inboundCompliant: number;
            outboundShipments: number;
            outboundCompliant: number;
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
              underservedCities: 0,
              inboundShipments: 0,
              inboundCompliant: 0,
              outboundShipments: 0,
              outboundCompliant: 0,
            });
          }

          const regionStats = regionStatsMap.get(city.regionId)!;
          regionStats.cities.add(city.cityId);
          regionStats.totalPopulation += city.population || 0;
          regionStats.totalShipments += city.totalShipments;
          regionStats.compliantShipments += city.compliantShipments;
          regionStats.standardsSum += city.standardPercentage * city.totalShipments;
          regionStats.standardsCount += city.totalShipments;
          regionStats.inboundShipments += city.inboundShipments;
          regionStats.inboundCompliant += city.inboundCompliant;
          regionStats.outboundShipments += city.outboundShipments;
          regionStats.outboundCompliant += city.outboundCompliant;
          if (city.status === 'critical') regionStats.underservedCities++;
        });

        const regionEquityData: RegionEquityData[] = Array.from(regionStatsMap.entries()).map(
          ([regionId, stats]) => {
            const actualPercentage =
              stats.totalShipments > 0 ? (stats.compliantShipments / stats.totalShipments) * 100 : 0;
            const standardPercentage =
              stats.standardsCount > 0 ? stats.standardsSum / stats.standardsCount : 95;
            const deviation = actualPercentage - standardPercentage;

            let status: 'compliant' | 'warning' | 'critical' = 'compliant';
            if (actualPercentage < standardPercentage) {
              if (actualPercentage < defaultCriticalThreshold) {
                status = 'critical';
              } else if (actualPercentage < defaultWarningThreshold) {
                status = 'warning';
              }
            }

            const inboundPercentage = stats.inboundShipments > 0 
              ? (stats.inboundCompliant / stats.inboundShipments) * 100 
              : 0;
            const outboundPercentage = stats.outboundShipments > 0 
              ? (stats.outboundCompliant / stats.outboundShipments) * 100 
              : 0;
            const directionGap = Math.abs(inboundPercentage - outboundPercentage);

            return {
              regionId,
              regionName: stats.regionName,
              totalCities: stats.cities.size,
              totalPopulation: stats.totalPopulation,
              totalShipments: stats.totalShipments,
              compliantShipments: stats.compliantShipments,
              standardPercentage,
              actualPercentage,
              deviation,
              status,
              underservedCitiesCount: stats.underservedCities,
              inboundPercentage,
              outboundPercentage,
              directionGap,
              accountId: accountId!,
            };
          }
        );

        // 9. Set state
        setCityData(filteredCityData);
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
  }, [accountId, JSON.stringify(filters)]);

  return { cityData, regionData, metrics, loading, error };
}
