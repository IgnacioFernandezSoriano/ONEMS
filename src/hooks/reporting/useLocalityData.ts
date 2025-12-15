import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import type { LocalityData } from '@/types/reporting';

export function useLocalityData(accountId: string | undefined) {
  const [data, setData] = useState<LocalityData[]>([]);
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
        const { data: localities, error: err } = await supabase
          .from('v_reporting_by_locality')
          .select('*')
          .eq('account_id', accountId)
          .order('total_shipments', { ascending: false });

        if (err) throw err;

        setData(localities || []);
      } catch (err) {
        setError(err as Error);
      } finally {
        setLoading(false);
      }
    }

    fetchData();
  }, [accountId]);

  return { data, loading, error };
}
