import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import type { Reader, ReaderFormData } from '@/lib/types_postal_centers';

export interface MobileReaderSummary {
  reader_id: string;
  reader_code: string;
  reader_name: string;
  reader_type: 'Entry' | 'Exit' | 'Mixed';
  current_center_id: string | null;
  current_center_name: string | null;
  assigned_since: string | null;
  total_assignments: number;
  is_mobile: boolean;
}

export function useMobileReaders(accountId: string | undefined) {
  const [readers, setReaders] = useState<MobileReaderSummary[]>([]);
  const [allReaders, setAllReaders] = useState<Reader[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchMobileReaders = async () => {
    if (!accountId) {
      setReaders([]);
      setLoading(false);
      return;
    }

    try {
      setLoading(true);

      // Fetch summary using RPC function
      const { data: summaryData, error: summaryError } = await supabase
        .rpc('get_mobile_readers_summary', { p_account_id: accountId });

      if (summaryError) throw summaryError;

      setReaders(summaryData || []);

      // Also fetch full reader details
      const { data: readersData, error: readersError } = await supabase
        .from('readers')
        .select('*')
        .eq('account_id', accountId)
        .eq('is_active', true)
        .order('name');

      if (readersError) throw readersError;

      setAllReaders(readersData || []);
      setError(null);
    } catch (err: any) {
      setError(err.message);
      console.error('Error fetching mobile readers:', err);
    } finally {
      setLoading(false);
    }
  };

  const createMobileReader = async (data: ReaderFormData) => {
    if (!accountId) throw new Error('No account ID provided');

    try {
      const { data: newReader, error: createError } = await supabase
        .from('readers')
        .insert({
          account_id: accountId,
          reader_id: data.reader_id,
          name: data.name,
          description: data.description,
          type: data.type,
          postal_center_id: data.postal_center_id, // Can be NULL for mobile readers
          mixed_reader_gap_minutes: data.mixed_reader_gap_minutes,
          is_active: data.is_active,
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .select()
        .single();

      if (createError) throw createError;

      await fetchMobileReaders();
      return { success: true, data: newReader };
    } catch (err: any) {
      setError(err.message);
      return { success: false, error: err.message };
    }
  };

  const updateReader = async (readerId: string, data: Partial<ReaderFormData>) => {
    try {
      const { error: updateError } = await supabase
        .from('readers')
        .update({
          ...data,
          updated_at: new Date().toISOString(),
        })
        .eq('id', readerId);

      if (updateError) throw updateError;

      await fetchMobileReaders();
      return { success: true };
    } catch (err: any) {
      setError(err.message);
      return { success: false, error: err.message };
    }
  };

  const deleteReader = async (readerId: string) => {
    try {
      // Soft delete by setting is_active to false
      const { error: deleteError } = await supabase
        .from('readers')
        .update({
          is_active: false,
          updated_at: new Date().toISOString(),
        })
        .eq('id', readerId);

      if (deleteError) throw deleteError;

      await fetchMobileReaders();
      return { success: true };
    } catch (err: any) {
      setError(err.message);
      return { success: false, error: err.message };
    }
  };

  const getReaderById = (readerId: string): Reader | undefined => {
    return allReaders.find((r) => r.id === readerId);
  };

  useEffect(() => {
    fetchMobileReaders();
  }, [accountId]);

  return {
    readers,
    allReaders,
    loading,
    error,
    createMobileReader,
    updateReader,
    deleteReader,
    getReaderById,
    refetch: fetchMobileReaders,
  };
}
