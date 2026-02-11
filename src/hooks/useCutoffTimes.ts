import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { useEffectiveAccountId } from '@/hooks/useEffectiveAccountId';

export interface CutoffTime {
  id: string;
  postal_center_id: string;
  postal_center_code: string;
  postal_center_name: string;
  cutoff_time: string;
  opening_hour: string;
  working_hours_end: string;
  working_days: string[];
  timezone: string;
}

export function useCutoffTimes() {
  const accountId = useEffectiveAccountId();
  const [cutoffs, setCutoffs] = useState<CutoffTime[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchCutoffs = async () => {
    if (!accountId) return;

    try {
      setLoading(true);
      const { data, error: fetchError } = await supabase
        .from('postal_centers')
        .select('id, code, name, cutoff_time, opening_hour, working_hours_end, working_days, timezone')
        .eq('account_id', accountId)
        .is('deleted_at', null)
        .order('code');

      if (fetchError) throw fetchError;

      const formatted: CutoffTime[] = (data || []).map(pc => ({
        id: pc.id,
        postal_center_id: pc.id,
        postal_center_code: pc.code,
        postal_center_name: pc.name,
        cutoff_time: pc.cutoff_time || '18:00:00',
        opening_hour: pc.opening_hour || '09:00:00',
        working_hours_end: pc.working_hours_end || '18:00:00',
        working_days: pc.working_days || ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
        timezone: pc.timezone || 'UTC',
      }));

      setCutoffs(formatted);
      setError(null);
    } catch (err: any) {
      setError(err.message);
      console.error('Error fetching cutoffs:', err);
    } finally {
      setLoading(false);
    }
  };

  const updateCutoff = async (postalCenterId: string, updates: Partial<CutoffTime>) => {
    try {
      const { error: updateError } = await supabase
        .from('postal_centers')
        .update({
          cutoff_time: updates.cutoff_time,
          opening_hour: updates.opening_hour,
          working_hours_end: updates.working_hours_end,
          working_days: updates.working_days,
          timezone: updates.timezone,
          updated_at: new Date().toISOString(),
        })
        .eq('id', postalCenterId)
        .eq('account_id', accountId);

      if (updateError) throw updateError;

      await fetchCutoffs();
    } catch (err: any) {
      setError(err.message);
      throw err;
    }
  };

  useEffect(() => {
    fetchCutoffs();
  }, [accountId]);

  return {
    cutoffs,
    loading,
    error,
    updateCutoff,
    refetch: fetchCutoffs,
  };
}
