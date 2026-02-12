import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';

export interface ReaderLocationHistory {
  id: string;
  postal_center_id: string;
  postal_center_code: string;
  postal_center_name: string;
  assigned_at: string;
  unassigned_at: string | null;
  duration_days: number;
  is_current: boolean;
  notes: string | null;
}

export function useReaderLocationHistory(readerId: string | null) {
  const [history, setHistory] = useState<ReaderLocationHistory[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchHistory = async () => {
    if (!readerId) {
      setHistory([]);
      setLoading(false);
      return;
    }

    try {
      setLoading(true);
      const { data, error: fetchError } = await supabase
        .rpc('get_reader_location_history', { p_reader_id: readerId });

      if (fetchError) throw fetchError;

      setHistory(data || []);
      setError(null);
    } catch (err: any) {
      setError(err.message);
      console.error('Error fetching reader location history:', err);
    } finally {
      setLoading(false);
    }
  };

  const assignToCenter = async (
    postalCenterId: string,
    assignedAt?: string,
    unassignedAt?: string | null,
    notes?: string | null
  ) => {
    if (!readerId) throw new Error('No reader selected');

    try {
      const { data, error: assignError } = await supabase.rpc('assign_reader_to_center', {
        p_reader_id: readerId,
        p_postal_center_id: postalCenterId,
        p_assigned_at: assignedAt || new Date().toISOString(),
        p_unassigned_at: unassignedAt,
        p_notes: notes,
      });

      if (assignError) throw assignError;

      await fetchHistory();
      return { success: true, data };
    } catch (err: any) {
      setError(err.message);
      return { success: false, error: err.message };
    }
  };

  const unassignFromCenter = async (unassignedAt?: string) => {
    if (!readerId) throw new Error('No reader selected');

    try {
      const { error: unassignError } = await supabase.rpc('unassign_reader_from_center', {
        p_reader_id: readerId,
        p_unassigned_at: unassignedAt || new Date().toISOString(),
      });

      if (unassignError) throw unassignError;

      await fetchHistory();
      return { success: true };
    } catch (err: any) {
      setError(err.message);
      return { success: false, error: err.message };
    }
  };

  const updateHistoryEntry = async (
    historyId: string,
    updates: {
      assigned_at?: string;
      unassigned_at?: string | null;
      notes?: string | null;
    }
  ) => {
    try {
      const { error: updateError } = await supabase
        .from('reader_location_history')
        .update({
          ...updates,
          updated_at: new Date().toISOString(),
        })
        .eq('id', historyId);

      if (updateError) throw updateError;

      await fetchHistory();
      return { success: true };
    } catch (err: any) {
      setError(err.message);
      return { success: false, error: err.message };
    }
  };

  useEffect(() => {
    fetchHistory();
  }, [readerId]);

  return {
    history,
    loading,
    error,
    assignToCenter,
    unassignFromCenter,
    updateHistoryEntry,
    refetch: fetchHistory,
  };
}
