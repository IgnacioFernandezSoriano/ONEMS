import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import type { ShipmentTracking } from '@/types/reporting';

export function useShipmentTracking(accountId: string | undefined, tagId?: string) {
  const [data, setData] = useState<ShipmentTracking[]>([]);
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
        let query = supabase
          .from('v_reporting_individual_tracking')
          .select('*')
          .eq('account_id', accountId)
          .order('sent_at', { ascending: false });

        if (tagId) {
          query = query.eq('tag_id', tagId);
        } else {
          query = query.limit(50);
        }

        const { data: tracking, error: err } = await query;

        if (err) throw err;

        const mapped = (tracking || []).map(row => ({
          id: row.id,
          tagId: row.tag_id,
          planName: row.plan_name,
          carrierName: row.carrier_name,
          productName: row.product_name,
          originCityName: row.origin_city_name,
          destinationCityName: row.destination_city_name,
          sentAt: new Date(row.sent_at),
          receivedAt: new Date(row.received_at),
          expectedDeliveryAt: new Date(row.expected_delivery_at),
          totalTransitDays: row.total_transit_days,
          businessTransitDays: row.business_transit_days,
          onTimeDelivery: row.on_time_delivery,
          delayHours: parseFloat(row.delay_hours || '0'),
          standardDeliveryHours: row.standard_delivery_hours,
          timeUnit: row.time_unit
        }));

        setData(mapped);
      } catch (err) {
        setError(err as Error);
      } finally {
        setLoading(false);
      }
    }

    fetchData();
  }, [accountId, tagId]);

  return { data, loading, error };
}
