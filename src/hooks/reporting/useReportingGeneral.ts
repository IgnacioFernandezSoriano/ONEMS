import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import type { GeneralPerformanceData } from '@/types/reporting';
import { adjustStartDateForFilter, adjustEndDateForFilter } from '@/lib/dateUtils';
import { useEffectiveAccountId } from '../useEffectiveAccountId';

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
        
        // Build query with filters
        let query = supabase
          .from('one_db')
          .select('*')
          .eq('account_id', activeAccountId);

        if (filters?.originCity) {
          query = query.eq('origin_city_name', filters.originCity);
        }
        if (filters?.destinationCity) {
          query = query.eq('destination_city_name', filters.destinationCity);
        }
        if (filters?.carrier) {
          query = query.eq('carrier_name', filters.carrier);
        }
        if (filters?.product) {
          query = query.eq('product_name', filters.product);
        }
        if (filters?.dateFrom && filters.dateFrom !== '') {
          query = query.gte('sent_at', adjustStartDateForFilter(filters.dateFrom));
        }
        if (filters?.dateTo && filters.dateTo !== '') {
          query = query.lte('sent_at', adjustEndDateForFilter(filters.dateTo));
        }

        const { data: shipments, error: err } = await query;

        if (err) throw err;

        // Group by week and calculate metrics
        const weeklyData = new Map<string, {
          compliant: number;
          total: number;
          totalDays: number;
        }>();

        (shipments || []).forEach(shipment => {
          const sentDate = new Date(shipment.sent_at);
          const weekStart = new Date(sentDate);
          weekStart.setDate(sentDate.getDate() - sentDate.getDay());
          const weekKey = weekStart.toISOString().split('T')[0];

          const existing = weeklyData.get(weekKey) || { compliant: 0, total: 0, totalDays: 0 };
          weeklyData.set(weekKey, {
            compliant: existing.compliant + (shipment.on_time_delivery ? 1 : 0),
            total: existing.total + 1,
            totalDays: existing.totalDays + (shipment.business_transit_days || 0)
          });
        });

        // Convert to array and sort
        const mapped: GeneralPerformanceData[] = Array.from(weeklyData.entries())
          .map(([weekKey, stats]) => ({
            period: new Date(weekKey),
            compliancePercentage: (stats.compliant / stats.total) * 100,
            avgBusinessDays: stats.totalDays / stats.total,
            totalShipments: stats.total
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
  }, [activeAccountId, filters?.originCity, filters?.destinationCity, filters?.carrier, filters?.product, filters?.dateFrom, filters?.dateTo]);

  return { data, loading, error };
}
