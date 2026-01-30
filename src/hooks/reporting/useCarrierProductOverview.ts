import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { adjustStartDateForFilter, adjustEndDateForFilter } from '@/lib/dateUtils';
import { useEffectiveAccountId } from '../useEffectiveAccountId';

interface CarrierProductData {
  carrier: string;
  product: string;
  routes: number;
  totalSamples: number;
  jkStandard: number;
  jkActual: number;
  deviation: number;
  onTimePercentage: number;
  problematicRoutes: number;
  status: 'compliant' | 'warning' | 'critical';
}

interface Filters {
  dateFrom?: string;
  dateTo?: string;
  routeType?: string;
  originCity?: string;
  destinationCity?: string;
  carrier?: string;
  product?: string;
}

export function useCarrierProductOverview(accountId: string | undefined, filters: Filters) {
  const effectiveAccountId = useEffectiveAccountId();
  const activeAccountId = effectiveAccountId || accountId;

  const [data, setData] = useState<CarrierProductData[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);
  const [globalWarningThreshold, setGlobalWarningThreshold] = useState<number>(80);
  const [globalCriticalThreshold, setGlobalCriticalThreshold] = useState<number>(75);

  useEffect(() => {
    if (!activeAccountId) {
      setLoading(false);
      return;
    }

    async function fetchData() {
      try {
        setLoading(true);

        // First, get delivery standards with related data
        const { data: standards, error: stdError } = await supabase
          .from('delivery_standards')
          .select(`
            *,
            origin_city:cities!delivery_standards_origin_city_id_fkey(id, name),
            destination_city:cities!delivery_standards_destination_city_id_fkey(id, name),
            carrier:carriers(id, name),
            product:products(id, code, description)
          `)
          .eq('account_id', activeAccountId);

        if (stdError) throw stdError;

        // Create standards map with correct field names
        const standardsMap = new Map<string, { jkStandard: number; successPercentage: number; warningThreshold: number; criticalThreshold: number }>();
        (standards || []).forEach(std => {
          const originCityName = std.origin_city?.name;
          const destCityName = std.destination_city?.name;
          const carrierName = std.carrier?.name;
          const productName = `${std.product?.code} - ${std.product?.description}`;
          
          if (!originCityName || !destCityName || !carrierName || !productName) {
            console.warn('[useCarrierProductOverview] Skipping standard with missing data:', std);
            return;
          }
          
          const routeKey = `${originCityName}-${destCityName}-${carrierName}-${productName}`;
          const jkStandard = std.time_unit === 'days' 
            ? std.standard_time 
            : std.standard_time / 24;
          
          const successPct = std.success_percentage || 95;
          const warningThreshold = std.threshold_type === 'relative'
            ? successPct - (successPct * (std.warning_threshold || 5) / 100)
            : successPct - (std.warning_threshold || 5);
          const criticalThreshold = std.threshold_type === 'relative'
            ? successPct - (successPct * (std.critical_threshold || 10) / 100)
            : successPct - (std.critical_threshold || 10);
          
          standardsMap.set(routeKey, {
            jkStandard: jkStandard || 0,
            successPercentage: successPct,
            warningThreshold: warningThreshold,
            criticalThreshold: criticalThreshold,
          });
        });

        console.log('[useCarrierProductOverview] Loaded standards:', standardsMap.size);

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
        console.log('[useCarrierProductOverview] Global thresholds:', { warning: warningThreshold, critical: criticalThreshold });

        // Build query for shipments with pagination
        const allShipments: any[] = []
        const pageSize = 1000
        let start = 0
        let hasMore = true

        while (hasMore) {
          let query = supabase
            .from('one_db')
            .select(`
              carrier_name, 
              product_name, 
              on_time_delivery, 
              business_transit_days,
              origin_city_name,
              destination_city_name
            `)
            .eq('account_id', activeAccountId)
            .range(start, start + pageSize - 1)

          if (filters.dateFrom && filters.dateFrom !== '') {
            query = query.gte('sent_at', adjustStartDateForFilter(filters.dateFrom))
          }
          if (filters.dateTo && filters.dateTo !== '') {
            query = query.lte('sent_at', adjustEndDateForFilter(filters.dateTo))
          }
          if (filters.originCity) {
            query = query.eq('origin_city_name', filters.originCity)
          }
          if (filters.destinationCity) {
            query = query.eq('destination_city_name', filters.destinationCity)
          }
          if (filters.carrier) {
            query = query.eq('carrier_name', filters.carrier)
          }
          if (filters.product) {
            query = query.eq('product_name', filters.product)
          }

          const { data, error: err } = await query

          if (err) throw err

          if (data && data.length > 0) {
            allShipments.push(...data)
            hasMore = data.length === pageSize
            start += pageSize
          } else {
            hasMore = false
          }
        }

        const shipments = allShipments

        // Group by carrier-product combination
        const grouped = new Map<string, {
          routes: Set<string>;
          onTimeCount: number;
          total: number;
          dayDistribution: Map<number, number>; // day -> count
          totalStandardDays: number;
          standardPercentageSum: number;
          standardPercentageCount: number;
          routePerformance: Map<string, { onTime: number; total: number }>;
        }>();

        (shipments || []).forEach(shipment => {
          const key = `${shipment.carrier_name}|${shipment.product_name}`;
          const routeKey = `${shipment.origin_city_name}-${shipment.destination_city_name}`;
          const standardKey = `${shipment.origin_city_name}-${shipment.destination_city_name}-${shipment.carrier_name}-${shipment.product_name}`;
          const standard = standardsMap.get(standardKey);
          
          if (!grouped.has(key)) {
            grouped.set(key, {
              routes: new Set(),
              onTimeCount: 0,
              total: 0,
              dayDistribution: new Map(),
              totalStandardDays: 0,
              standardPercentageSum: 0,
              standardPercentageCount: 0,
              routePerformance: new Map()
            });
          }
          
          const stats = grouped.get(key)!;
          stats.routes.add(routeKey);
          stats.onTimeCount += shipment.on_time_delivery ? 1 : 0;
          stats.total += 1;
          
          // Accumulate day distribution
          const transitDays = shipment.business_transit_days || 0;
          stats.dayDistribution.set(transitDays, (stats.dayDistribution.get(transitDays) || 0) + 1);
          
          stats.totalStandardDays += standard?.jkStandard || 0;
          if (standard?.successPercentage) {
            stats.standardPercentageSum += standard.successPercentage;
            stats.standardPercentageCount++;
          }
          
          // Track route performance
          if (!stats.routePerformance.has(routeKey)) {
            stats.routePerformance.set(routeKey, { onTime: 0, total: 0 });
          }
          const routeStats = stats.routePerformance.get(routeKey)!;
          routeStats.onTime += shipment.on_time_delivery ? 1 : 0;
          routeStats.total += 1;
        });

        // Calculate metrics for each carrier-product combination
        const result: CarrierProductData[] = [];
        grouped.forEach((stats, key) => {
          const [carrier, product] = key.split('|');
          const onTimePercentage = (stats.onTimeCount / stats.total) * 100;
          const jkStandard = stats.totalStandardDays / stats.total;
          
          // Calculate J+K Actual (days to reach STD %)
          const targetStdPercentage = stats.standardPercentageCount > 0 
            ? stats.standardPercentageSum / stats.standardPercentageCount 
            : 85;
          
          let jkActual = 0;
          const sortedDays = Array.from(stats.dayDistribution.keys()).sort((a, b) => a - b);
          let cumulativeSamples = 0;
          const targetSamples = (targetStdPercentage / 100) * stats.total;
          
          for (const day of sortedDays) {
            cumulativeSamples += stats.dayDistribution.get(day) || 0;
            if (cumulativeSamples >= targetSamples) {
              jkActual = day;
              break;
            }
          }
          
          const deviation = jkActual - jkStandard;
          
          // Count problematic routes (on-time < critical threshold)
          let problematicRoutes = 0;
          stats.routePerformance.forEach(routeStats => {
            const routeOnTime = (routeStats.onTime / routeStats.total) * 100;
            if (routeOnTime <= criticalThreshold) {
              problematicRoutes++;
            }
          });
          
          // Determine status based on thresholds
          let status: 'compliant' | 'warning' | 'critical';
          if (onTimePercentage >= warningThreshold) {
            status = 'compliant';
          } else if (onTimePercentage > criticalThreshold) {
            status = 'warning';
          } else {
            status = 'critical';
          }

          result.push({
            carrier,
            product,
            routes: stats.routes.size,
            totalSamples: stats.total,
            jkStandard,
            jkActual,
            deviation,
            onTimePercentage,
            problematicRoutes,
            status
          });
        });

        setData(result);
      } catch (err) {
        setError(err as Error);
      } finally {
        setLoading(false);
      }
    }

    fetchData();
  }, [activeAccountId, filters.dateFrom, filters.dateTo, filters.routeType, filters.originCity, filters.destinationCity, filters.carrier, filters.product]);

  return { data, loading, error, globalWarningThreshold, globalCriticalThreshold };
}
