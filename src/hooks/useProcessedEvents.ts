import { useState, useEffect, useMemo } from 'react';
import { supabase } from '../lib/supabase';
import { useEffectiveAccountId } from './useEffectiveAccountId';

export interface ProcessedEvent {
  id: number;
  account_id: string;
  tag_id: string;
  reader_id: string;
  postal_center_id: string;
  event_type: 'entry' | 'exit';
  timestamp: string;
  analysis_datetime: string;
  postal_center_code_snapshot: string;
  postal_center_name_snapshot: string;
  reader_id_snapshot: string;
  reader_type_snapshot: string;
  is_consolidated: boolean;
  raw_event_count: number;
  created_at: string;
  processed_at: string | null;
  // Joined data
  postal_center_name?: string;
  postal_center_code?: string;
}

export interface ProcessedEventsFilters {
  search?: string;
  postal_center_id?: string;
  event_type?: 'entry' | 'exit' | null;
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
          .order('timestamp', { ascending: false })
          .range(start, start + pageSize - 1);

        if (fetchError) throw fetchError;

        if (data && data.length > 0) {
          // Transform data to include joined fields
          const transformedData = data.map((record: any) => ({
            ...record,
            postal_center_name: record.postal_centers?.name || record.postal_center_name_snapshot || 'Unknown',
            postal_center_code: record.postal_centers?.code || record.postal_center_code_snapshot || 'N/A',
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
          r.reader_id_snapshot.toLowerCase().includes(searchLower) ||
          (r.postal_center_name_snapshot && r.postal_center_name_snapshot.toLowerCase().includes(searchLower)) ||
          (r.postal_center_code_snapshot && r.postal_center_code_snapshot.toLowerCase().includes(searchLower))
      );
    }

    // Postal center filter
    if (filters.postal_center_id) {
      filtered = filtered.filter((r) => r.postal_center_id === filters.postal_center_id);
    }

    // Event type filter
    if (filters.event_type) {
      filtered = filtered.filter((r) => r.event_type === filters.event_type);
    }

    // Date range filter (timestamp)
    if (filters.date_from) {
      filtered = filtered.filter((r) => r.timestamp >= filters.date_from!);
    }

    if (filters.date_to) {
      // Add 1 day to include the entire end date
      const endDate = new Date(filters.date_to);
      endDate.setDate(endDate.getDate() + 1);
      const endDateStr = endDate.toISOString().split('T')[0];
      filtered = filtered.filter((r) => r.timestamp < endDateStr);
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
      'Reader ID',
      'Event Type',
      'Timestamp',
      'Analysis DateTime',
      'Reader Type',
      'Is Consolidated',
      'Raw Event Count',
      'Created At',
    ];

    // Convert records to CSV rows
    const rows = recordsToExport.map((record) => [
      record.id.toString(),
      record.tag_id,
      record.postal_center_name_snapshot || 'N/A',
      record.reader_id_snapshot,
      record.event_type,
      record.timestamp,
      record.analysis_datetime,
      record.reader_type_snapshot,
      record.is_consolidated ? 'Yes' : 'No',
      record.raw_event_count.toString(),
      record.created_at,
    ]);

    // Combine headers and rows
    const csvContent = [headers, ...rows].map((row) => row.join(',')).join('\n');

    // Create and download file
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const link = document.createElement('a');
    const url = URL.createObjectURL(blob);
    link.setAttribute('href', url);
    link.setAttribute('download', `diagnosis_db_${new Date().toISOString().split('T')[0]}.csv`);
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
