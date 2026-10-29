import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import type { GeneralPerformanceData } from '@/types/reporting';
import { useAccount } from '@/contexts/AccountContext';
import { startOfDayInTz, endOfDayInTz } from '@/lib/dateUtils';
import { useEffectiveAccountId } from '../useEffectiveAccountId';
import { shipmentHours } from '@/lib/transitMeasure';

interface Filters {
  originCity?: string;
  destinationCity?: string;
  carrier?: string;
  product?: string;
  dateFrom?: string;
  dateTo?: string;
}

export function useReportingGeneral(accountId: string | undefined, filters?: Filters) {
  const effectiveAccountId = useEffectiveAccountId();
  const { accountTimezone } = useAccount();
  // Use effectiveAccountId if available, otherwise fall back to passed accountId
  const activeAccountId = effectiveAccountId || accountId;

  const [data, setData] = useState<GeneralPerformanceData[]>([]);
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
        
        // Build query with filters and pagination
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

          if (filters?.originCity) {
            query = query.eq('origin_city_name', filters.originCity)
          }
          if (filters?.destinationCity) {
            query = query.eq('destination_city_name', filters.destinationCity)
          }
          if (filters?.carrier) {
            query = query.eq('carrier_name', filters.carrier)
          }
          if (filters?.product) {
            query = query.eq('product_name', filters.product)
          }
          // Use same date filtering as ONE DB (no time adjustment)
          if (filters?.dateFrom && filters.dateFrom !== '') {
            query = query.gte('sent_at', startOfDayInTz(filters.dateFrom.slice(0, 10), accountTimezone))
          }
          if (filters?.dateTo && filters.dateTo !== '') {
            query = query.lte('sent_at', endOfDayInTz(filters.dateTo.slice(0, 10), accountTimezone))
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

        // Group by week and calculate metrics
        const weeklyData = new Map<string, {
          compliant: number;
          evaluated: number;
          total: number;
          totalHours: number;
          timedCount: number;
        }>();

        (shipments || []).forEach(shipment => {
          const sentDate = new Date(shipment.sent_at);
          const weekStart = new Date(sentDate);
          weekStart.setDate(sentDate.getDate() - sentDate.getDay());
          const weekKey = weekStart.toISOString().split('T')[0];

          const hours = shipmentHours(shipment);
          const existing = weeklyData.get(weekKey) || { compliant: 0, evaluated: 0, total: 0, totalHours: 0, timedCount: 0 };
          // on_time_delivery nulo no cuenta ni como a tiempo ni como tarde
          const evaluated = typeof shipment.on_time_delivery === 'boolean';
          weeklyData.set(weekKey, {
            compliant: existing.compliant + (shipment.on_time_delivery === true ? 1 : 0),
            evaluated: existing.evaluated + (evaluated ? 1 : 0),
            total: existing.total + 1,
            totalHours: existing.totalHours + (hours ?? 0),
            timedCount: existing.timedCount + (hours === null ? 0 : 1)
          });
        });

        // Convert to array and sort
        const mapped: GeneralPerformanceData[] = Array.from(weeklyData.entries())
          .map(([weekKey, stats]) => ({
            period: new Date(weekKey),
            compliancePercentage: stats.evaluated > 0 ? (stats.compliant / stats.evaluated) * 100 : 0,
            avgBusinessHours: stats.timedCount > 0 ? stats.totalHours / stats.timedCount : null,
            totalShipments: stats.total,
            compliantCount: stats.compliant,
            evaluatedCount: stats.evaluated,
            timedCount: stats.timedCount
          }))
          .sort((a, b) => a.period.getTime() - b.period.getTime())
          .slice(-12); // Last 12 weeks

        setData(mapped);
      } catch (err) {
        setError(err as Error);
      } finally {
        setLoading(false);
      }
    }

    fetchData();
  }, [activeAccountId, filters?.originCity, filters?.destinationCity, filters?.carrier, filters?.product, filters?.dateFrom, filters?.dateTo, accountTimezone]);

  return { data, loading, error };
}
