import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { useEffectiveAccountId } from '@/hooks/useEffectiveAccountId';

// Existing table structure: id, account_id, postal_center_id, date, reason, type, created_at, created_by
export interface NonWorkingDay {
  id: number;
  account_id: string;
  postal_center_id: string | null;
  date: string;
  reason: string;
  type: string;
  created_at: string;
  created_by: string | null;
}

export function useNonWorkingDays() {
  const accountId = useEffectiveAccountId();
  const [nonWorkingDays, setNonWorkingDays] = useState<NonWorkingDay[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchNonWorkingDays = async () => {
    if (!accountId) return;

    try {
      setLoading(true);
      const { data, error: fetchError } = await supabase
        .from('non_working_days')
        .select('*')
        .eq('account_id', accountId)
        .order('date', { ascending: false });

      if (fetchError) throw fetchError;

      setNonWorkingDays(data || []);
      setError(null);
    } catch (err: any) {
      setError(err.message);
      console.error('Error fetching non-working days:', err);
    } finally {
      setLoading(false);
    }
  };

  const createNonWorkingDay = async (data: Partial<NonWorkingDay>) => {
    if (!accountId) return;

    try {
      const { error: insertError } = await supabase
        .from('non_working_days')
        .insert({
          ...data,
          account_id: accountId,
        });

      if (insertError) throw insertError;

      await fetchNonWorkingDays();
    } catch (err: any) {
      setError(err.message);
      throw err;
    }
  };

  const updateNonWorkingDay = async (id: number, data: Partial<NonWorkingDay>) => {
    try {
      const { error: updateError } = await supabase
        .from('non_working_days')
        .update(data)
        .eq('id', id);

      if (updateError) throw updateError;

      await fetchNonWorkingDays();
    } catch (err: any) {
      setError(err.message);
      throw err;
    }
  };

  const deleteNonWorkingDay = async (id: number) => {
    try {
      const { error: deleteError } = await supabase
        .from('non_working_days')
        .delete()
        .eq('id', id);

      if (deleteError) throw deleteError;

      await fetchNonWorkingDays();
    } catch (err: any) {
      setError(err.message);
      throw err;
    }
  };

  useEffect(() => {
    fetchNonWorkingDays();
  }, [accountId]);

  return {
    nonWorkingDays,
    loading,
    error,
    createNonWorkingDay,
    updateNonWorkingDay,
    deleteNonWorkingDay,
    refetch: fetchNonWorkingDays,
  };
}
