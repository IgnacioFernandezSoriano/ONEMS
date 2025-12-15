import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';

export interface JKDataPoint {
  originCity: string;
  destinationCity: string;
  carrier: string;
  product: string;
  standard: number; // J+K standard from delivery_standards (allowed_days)
  distribution: Map<number, number>; // day -> count
  totalShipments: number;
}

interface Filters {
  originCity?: string;
  destinationCity?: string;
  carrier?: string;
  product?: string;
}

export function useJKAnalysis(accountId: string | undefined, filters?: Filters) {
  const [data, setData] = useState<JKDataPoint[]>([]);
  const [maxDays, setMaxDays] = useState(0);
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

        // Build query with filters
        let query = supabase
          .from('one_db')
          .select('*')
          .eq('account_id', accountId);

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

        const { data: shipments, error: err } = await query;

        if (err) throw err;

        // Get delivery standards
        const { data: standards } = await supabase
          .from('delivery_standards')
          .select('*')
          .eq('account_id', accountId);

        // FIX: Use allowed_days instead of max_business_days for J+K standard
        const standardsMap = new Map<string, number>();
        (standards || []).forEach(std => {
          const key = `${std.origin_city_name}|${std.destination_city_name}|${std.carrier_name}|${std.product_name}`;
          standardsMap.set(key, std.allowed_days); // CORRECTED: was max_business_days
        });

        // Group by origin-destination-carrier-product
        const groupedData = new Map<string, {
          originCity: string;
          destinationCity: string;
          carrier: string;
          product: string;
          distribution: Map<number, number>;
        }>();

        let calculatedMaxDays = 0;

        (shipments || []).forEach(shipment => {
          const key = `${shipment.origin_city_name}|${shipment.destination_city_name}|${shipment.carrier_name}|${shipment.product_name}`;
          const days = shipment.business_transit_days || 0;
          
          if (days > calculatedMaxDays) {
            calculatedMaxDays = days;
          }

          if (!groupedData.has(key)) {
            groupedData.set(key, {
              originCity: shipment.origin_city_name,
              destinationCity: shipment.destination_city_name,
              carrier: shipment.carrier_name,
              product: shipment.product_name,
              distribution: new Map()
            });
          }

          const group = groupedData.get(key)!;
          const currentCount = group.distribution.get(days) || 0;
          group.distribution.set(days, currentCount + 1);
        });

        // Convert to array with standards
        const result: JKDataPoint[] = Array.from(groupedData.entries()).map(([key, group]) => {
          const standard = standardsMap.get(key) || 0;
          const totalShipments = Array.from(group.distribution.values()).reduce((sum, count) => sum + count, 0);

          return {
            originCity: group.originCity,
            destinationCity: group.destinationCity,
            carrier: group.carrier,
            product: group.product,
            standard,
            distribution: group.distribution,
            totalShipments
          };
        });

        setData(result);
        setMaxDays(calculatedMaxDays);
      } catch (err) {
        setError(err as Error);
      } finally {
        setLoading(false);
      }
    }

    fetchData();
  }, [accountId, filters?.originCity, filters?.destinationCity, filters?.carrier, filters?.product]);

  return { data, maxDays, loading, error };
}
