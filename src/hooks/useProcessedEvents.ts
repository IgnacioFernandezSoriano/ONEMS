import { useState, useEffect, useMemo } from 'react';
import { supabase } from '../lib/supabase';
import { useEffectiveAccountId } from './useEffectiveAccountId';

export interface ProcessedEvent {
  id: string;
  account_id: string;
  tag_id: string;
  entry_reader_id: string;
  exit_reader_id: string | null;
  entry_time: string;
  exit_time: string | null;
  transit_minutes: number | null;
  adjusted_minutes: number | null;
  postal_center_id: string;
  reader_type: 'entry' | 'exit' | 'mixed';
  created_at: string;
  // Joined data
  postal_center_name?: string;
  postal_center_code?: string;
  entry_reader_name?: string;
  exit_reader_name?: string;
}

export interface ProcessedEventsFilters {
  search?: string;
  postal_center_id?: string;
  reader_type?: 'entry' | 'exit' | 'mixed' | null;
  date_from?: string;
  date_to?: string;
}

export const useProcessedEvents = (accountId: string | undefined) => {
  const effectiveAccountId = useEffectiveAccountId();
  const activeAccountId = effectiveAccountId || accountId;

  const [records, setRecords] = useState<ProcessedEvent[]>([]);
  const [filteredRecords, setFilteredRecords] = useState<ProcessedEvent[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchRecords = async () => {
    console.log('[useProcessedEvents] fetchRecords called with activeAccountId:', activeAccountId);

    if (!activeAccountId) {
      console.log('[useProcessedEvents] No accountId provided, skipping fetch');
      setLoading(false);
      return;
    }

    try {
      setLoading(true);
      setError(null);

      console.log('[useProcessedEvents] Fetching from processed_events table with accountId:', activeAccountId);

      // Paginate to handle Supabase 1000-record limit
      const allRecords: ProcessedEvent[] = [];
      const pageSize = 1000;
      let start = 0;
      let hasMore = true;

      while (hasMore) {
        const { data, error: fetchError } = await supabase
          .from('processed_events')
          .select(`
            *,
            postal_centers!postal_center_id (
              name,
              code
            )
          `)
          .eq('account_id', activeAccountId)
          .order('entry_time', { ascending: false })
          .range(start, start + pageSize - 1);

        if (fetchError) throw fetchError;

        if (data && data.length > 0) {
          // Transform data to include joined fields
          const transformedData = data.map((record: any) => ({
            ...record,
            postal_center_name: record.postal_centers?.name || 'Unknown',
            postal_center_code: record.postal_centers?.code || 'N/A',
          }));

          allRecords.push(...transformedData);
          hasMore = data.length === pageSize;
          start += pageSize;
        } else {
          hasMore = false;
        }
      }

      console.log('[useProcessedEvents] Query result:', {
        dataCount: allRecords.length,
        sampleData: allRecords[0] || null,
      });

      setRecords(allRecords);
      setFilteredRecords(allRecords);
    } catch (err: any) {
      setError(err.message);
      console.error('Error fetching processed events:', err);
    } finally {
      setLoading(false);
    }
  };

  const applyFilters = (filters: ProcessedEventsFilters) => {
    let filtered = [...records];

    // Search filter (tag_id, reader_id, postal_center)
    if (filters.search) {
      const searchLower = filters.search.toLowerCase();
      filtered = filtered.filter(
        (r) =>
          r.tag_id.toLowerCase().includes(searchLower) ||
          r.entry_reader_id.toLowerCase().includes(searchLower) ||
          (r.exit_reader_id && r.exit_reader_id.toLowerCase().includes(searchLower)) ||
          (r.postal_center_name && r.postal_center_name.toLowerCase().includes(searchLower)) ||
          (r.postal_center_code && r.postal_center_code.toLowerCase().includes(searchLower))
      );
    }

    // Postal center filter
    if (filters.postal_center_id) {
      filtered = filtered.filter((r) => r.postal_center_id === filters.postal_center_id);
    }

    // Reader type filter
    if (filters.reader_type) {
      filtered = filtered.filter((r) => r.reader_type === filters.reader_type);
    }

    // Date range filter (entry_time)
    if (filters.date_from) {
      filtered = filtered.filter((r) => r.entry_time >= filters.date_from!);
    }

    if (filters.date_to) {
      // Add 1 day to include the entire end date
      const endDate = new Date(filters.date_to);
      endDate.setDate(endDate.getDate() + 1);
      const endDateStr = endDate.toISOString().split('T')[0];
      filtered = filtered.filter((r) => r.entry_time < endDateStr);
    }

    setFilteredRecords(filtered);
  };

  const exportToCSV = (recordsToExport: ProcessedEvent[]) => {
    if (recordsToExport.length === 0) {
      alert('No records to export');
      return;
    }

    // Define CSV headers
    const headers = [
      'ID',
      'Tag ID',
      'Postal Center',
      'Entry Reader',
      'Exit Reader',
      'Entry Time',
      'Exit Time',
      'Transit Minutes',
      'Adjusted Minutes',
      'Reader Type',
      'Created At',
    ];

    // Convert records to CSV rows
    const rows = recordsToExport.map((record) => [
      record.id,
      record.tag_id,
      record.postal_center_name || 'N/A',
      record.entry_reader_id,
      record.exit_reader_id || 'N/A',
      record.entry_time,
      record.exit_time || 'N/A',
      record.transit_minutes?.toString() || 'N/A',
      record.adjusted_minutes?.toString() || 'N/A',
      record.reader_type,
      record.created_at,
    ]);

    // Combine headers and rows
    const csvContent = [headers, ...rows].map((row) => row.join(',')).join('\n');

    // Create and download file
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const link = document.createElement('a');
    const url = URL.createObjectURL(blob);
    link.setAttribute('href', url);
    link.setAttribute('download', `processed_events_${new Date().toISOString().split('T')[0]}.csv`);
    link.style.visibility = 'hidden';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  useEffect(() => {
    fetchRecords();
  }, [activeAccountId]);

  return {
    records,
    filteredRecords,
    loading,
    error,
    refetch: fetchRecords,
    applyFilters,
    exportToCSV,
  };
};
