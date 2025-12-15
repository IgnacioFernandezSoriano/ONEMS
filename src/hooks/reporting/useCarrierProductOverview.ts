import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';

interface CarrierProductData {
  carrier: string;
  product: string;
  compliancePercentage: number;
  avgBusinessDays: number;
  totalShipments: number;
  trend: 'up' | 'down' | 'stable';
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

        // Build query for current period
        let query = supabase
          .from('one_db')
          .select('carrier_name, product_name, on_time_delivery, business_transit_days')
          .eq('account_id', accountId);

        if (filters.dateFrom) {
          query = query.gte('sent_at', filters.dateFrom);
        }
        if (filters.dateTo) {
          query = query.lte('sent_at', filters.dateTo);
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

        // Group by carrier and product
        const grouped = new Map<string, {
          compliant: number;
          total: number;
          totalDays: number;
        }>();

        (shipments || []).forEach(shipment => {
          const key = `${shipment.carrier_name}|${shipment.product_name}`;
          const existing = grouped.get(key) || { compliant: 0, total: 0, totalDays: 0 };
          
          grouped.set(key, {
            compliant: existing.compliant + (shipment.on_time_delivery ? 1 : 0),
            total: existing.total + 1,
            totalDays: existing.totalDays + (shipment.business_transit_days || 0)
          });
        });

        // Calculate metrics for each carrier-product combination
        const result: CarrierProductData[] = [];
        grouped.forEach((stats, key) => {
          const [carrier, product] = key.split('|');
          const compliancePercentage = (stats.compliant / stats.total) * 100;
          const avgBusinessDays = stats.totalDays / stats.total;

          result.push({
            carrier,
            product,
            compliancePercentage,
            avgBusinessDays,
            totalShipments: stats.total,
            trend: 'stable' // TODO: Calculate trend by comparing with previous period
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
