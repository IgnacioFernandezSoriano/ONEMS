import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { useEffectiveAccountId } from '@/hooks/useEffectiveAccountId';

export interface CutoffTime {
  id: number;
  account_id: string;
  postal_center_id: string;
  postal_center_code?: string;
  cutoff_time: string;
  timezone: string;
  working_hours_start: string;
  working_hours_end: string;
  working_days: number[];
  is_active: boolean;
  created_at: string;
  updated_at: string;
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
        .from('postal_center_cutoffs')
        .select(`
          *,
          postal_centers!postal_center_cutoffs_postal_center_id_fkey (
            code
          )
        `)
        .eq('account_id', accountId)
        .order('created_at', { ascending: false });

      if (fetchError) throw fetchError;

      const formatted = data?.map((item: any) => ({
        ...item,
        postal_center_code: item.postal_centers?.code,
      })) || [];

      setCutoffs(formatted);
      setError(null);
    } catch (err: any) {
      setError(err.message);
      console.error('Error fetching cutoffs:', err);
    } finally {
      setLoading(false);
    }
  };

  const createCutoff = async (data: Partial<CutoffTime>) => {
    if (!accountId) return;

    try {
      const { error: insertError } = await supabase
        .from('postal_center_cutoffs')
        .insert({
          ...data,
          account_id: accountId,
        });

      if (insertError) throw insertError;

      await fetchCutoffs();
    } catch (err: any) {
      setError(err.message);
      throw err;
    }
  };

  const updateCutoff = async (id: number, data: Partial<CutoffTime>) => {
    try {
      const { error: updateError } = await supabase
        .from('postal_center_cutoffs')
        .update({
          ...data,
          updated_at: new Date().toISOString(),
        })
        .eq('id', id);

      if (updateError) throw updateError;

      await fetchCutoffs();
    } catch (err: any) {
      setError(err.message);
      throw err;
    }
  };

  const deleteCutoff = async (id: number) => {
    try {
      const { error: deleteError } = await supabase
        .from('postal_center_cutoffs')
        .delete()
        .eq('id', id);

      if (deleteError) throw deleteError;

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
    createCutoff,
    updateCutoff,
    deleteCutoff,
    refetch: fetchCutoffs,
  };
}
