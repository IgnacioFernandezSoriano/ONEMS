import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { adjustStartDateForFilter, adjustEndDateForFilter } from '@/lib/dateUtils';

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
  const [data, setData] = useState<CarrierProductData[]>([]);
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

        // First, get delivery standards
        const { data: standards, error: stdError } = await supabase
          .from('delivery_standards')
          .select('*')
          .eq('account_id', accountId);

        if (stdError) throw stdError;

        // Create standards map
        const standardsMap = new Map<string, { jkStandard: number; successPercentage: number }>();
        (standards || []).forEach(std => {
          const routeKey = `${std.origin_city_name}-${std.destination_city_name}-${std.carrier_name}-${std.product_name}`;
          const jkStandard = std.time_unit === 'days' 
            ? std.delivery_time 
            : std.delivery_time / 24;
          
          standardsMap.set(routeKey, {
            jkStandard: jkStandard || 0,
            successPercentage: std.success_percentage || 95
          });
        });

        // Build query for shipments
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
          .eq('account_id', accountId);

        if (filters.dateFrom && filters.dateFrom !== '') {
          query = query.gte('sent_at', adjustStartDateForFilter(filters.dateFrom));
        }
        if (filters.dateTo && filters.dateTo !== '') {
          query = query.lte('sent_at', adjustEndDateForFilter(filters.dateTo));
        }
        if (filters.originCity) {
          query = query.eq('origin_city_name', filters.originCity);
        }
        if (filters.destinationCity) {
          query = query.eq('destination_city_name', filters.destinationCity);
        }
        if (filters.carrier) {
          query = query.eq('carrier_name', filters.carrier);
        }
        if (filters.product) {
          query = query.eq('product_name', filters.product);
        }

        const { data: shipments, error: err } = await query;

        if (err) throw err;

        // Group by carrier-product combination
        const grouped = new Map<string, {
          routes: Set<string>;
          onTimeCount: number;
          total: number;
          totalActualDays: number;
          totalStandardDays: number;
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
              totalActualDays: 0,
              totalStandardDays: 0,
              routePerformance: new Map()
            });
          }
          
          const stats = grouped.get(key)!;
          stats.routes.add(routeKey);
          stats.onTimeCount += shipment.on_time_delivery ? 1 : 0;
          stats.total += 1;
          stats.totalActualDays += shipment.business_transit_days || 0;
          stats.totalStandardDays += standard?.jkStandard || 0;
          
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
          const jkActual = stats.totalActualDays / stats.total;
          const jkStandard = stats.totalStandardDays / stats.total;
          const deviation = jkActual - jkStandard;
          
          // Count problematic routes (on-time < 90%)
          let problematicRoutes = 0;
          stats.routePerformance.forEach(routeStats => {
            const routeOnTime = (routeStats.onTime / routeStats.total) * 100;
            if (routeOnTime < 90) {
              problematicRoutes++;
            }
          });
          
          // Determine status
          let status: 'compliant' | 'warning' | 'critical';
          if (onTimePercentage >= 95) {
            status = 'compliant';
          } else if (onTimePercentage >= 90) {
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
  }, [accountId, filters.dateFrom, filters.dateTo, filters.routeType, filters.originCity, filters.destinationCity, filters.carrier, filters.product]);

  return { data, loading, error };
}
