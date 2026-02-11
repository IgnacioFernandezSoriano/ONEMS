import { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';
import { useEffectiveAccountId } from './useEffectiveAccountId';
import { useTranslation } from './useTranslation';

export interface JourneySegment {
  id: string;
  account_id: string;
  tag_id: string;
  segment_type: 'operational' | 'distribution';
  postal_center_id?: string;
  from_postal_center_id?: string;
  to_postal_center_id?: string;
  entry_event_id: string;
  exit_event_id: string;
  entry_timestamp: string;
  exit_timestamp: string;
  entry_analysis_datetime: string;
  exit_analysis_datetime: string;
  actual_time_minutes: number;
  adjusted_time_minutes: number;
  pre_operational_wait_minutes?: number;
  sla_id?: string;
  expected_time_minutes?: number;
  sla_compliance: 'on_time' | 'warning' | 'critical' | 'violated' | 'no_sla';
  postal_center_code_snapshot?: string;
  postal_center_name_snapshot?: string;
  from_postal_center_code_snapshot?: string;
  from_postal_center_name_snapshot?: string;
  to_postal_center_code_snapshot?: string;
  to_postal_center_name_snapshot?: string;
  created_at: string;
}

export interface JourneySegmentsFilters {
  search?: string;
  segment_type?: 'operational' | 'distribution' | null;
  postal_center_id?: string;
  from_postal_center_id?: string;
  to_postal_center_id?: string;
  sla_compliance?: string;
  date_from?: string;
  date_to?: string;
}

export const useJourneySegments = (accountId: string | undefined) => {
  const effectiveAccountId = useEffectiveAccountId();
  const activeAccountId = effectiveAccountId || accountId;
  const { t } = useTranslation();

  const [segments, setSegments] = useState<JourneySegment[]>([]);
  const [filteredSegments, setFilteredSegments] = useState<JourneySegment[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [isReconstructing, setIsReconstructing] = useState(false);

  const fetchSegments = async () => {
    console.log('[useJourneySegments] fetchSegments called with activeAccountId:', activeAccountId);

    if (!activeAccountId) {
      console.log('[useJourneySegments] No accountId provided, skipping fetch');
      setLoading(false);
      return;
    }

    try {
      setLoading(true);
      setError(null);

      console.log(
        '[useJourneySegments] Fetching from journey_segments table with accountId:',
        activeAccountId
      );

      // Paginate to handle Supabase 1000-record limit
      const allSegments: JourneySegment[] = [];
      const pageSize = 1000;
      let start = 0;
      let hasMore = true;

      while (hasMore) {
        const { data, error: fetchError } = await supabase
          .from('journey_segments')
          .select('*')
          .eq('account_id', activeAccountId)
          .order('created_at', { ascending: false })
          .range(start, start + pageSize - 1);

        if (fetchError) throw fetchError;

        if (data && data.length > 0) {
          allSegments.push(...data);
          hasMore = data.length === pageSize;
          start += pageSize;
        } else {
          hasMore = false;
        }
      }

      console.log('[useJourneySegments] Query result:', {
        dataCount: allSegments.length,
        sampleData: allSegments[0] || null,
      });

      setSegments(allSegments);
      setFilteredSegments(allSegments);
    } catch (err: any) {
      setError(err.message);
      console.error('Error fetching journey segments:', err);
    } finally {
      setLoading(false);
    }
  };

  const applyFilters = (filters: JourneySegmentsFilters) => {
    console.log('[useJourneySegments] Applying filters:', filters);

    let filtered = [...segments];

    // Search filter (tag_id or postal center names)
    if (filters.search) {
      const searchLower = filters.search.toLowerCase();
      filtered = filtered.filter(
        (segment) =>
          segment.tag_id.toLowerCase().includes(searchLower) ||
          segment.postal_center_name_snapshot?.toLowerCase().includes(searchLower) ||
          segment.from_postal_center_name_snapshot?.toLowerCase().includes(searchLower) ||
          segment.to_postal_center_name_snapshot?.toLowerCase().includes(searchLower)
      );
    }

    // Segment type filter
    if (filters.segment_type) {
      filtered = filtered.filter((segment) => segment.segment_type === filters.segment_type);
    }

    // Postal center filter (for operational segments)
    if (filters.postal_center_id) {
      filtered = filtered.filter(
        (segment) => segment.postal_center_id === filters.postal_center_id
      );
    }

    // From postal center filter (for distribution segments)
    if (filters.from_postal_center_id) {
      filtered = filtered.filter(
        (segment) => segment.from_postal_center_id === filters.from_postal_center_id
      );
    }

    // To postal center filter (for distribution segments)
    if (filters.to_postal_center_id) {
      filtered = filtered.filter(
        (segment) => segment.to_postal_center_id === filters.to_postal_center_id
      );
    }

    // SLA compliance filter
    if (filters.sla_compliance) {
      filtered = filtered.filter((segment) => segment.sla_compliance === filters.sla_compliance);
    }

    // Date range filter (entry timestamp)
    if (filters.date_from) {
      filtered = filtered.filter(
        (segment) => new Date(segment.entry_timestamp) >= new Date(filters.date_from!)
      );
    }

    if (filters.date_to) {
      const dateTo = new Date(filters.date_to!);
      dateTo.setHours(23, 59, 59, 999); // Include the entire day
      filtered = filtered.filter((segment) => new Date(segment.entry_timestamp) <= dateTo);
    }

    console.log('[useJourneySegments] Filtered results:', {
      originalCount: segments.length,
      filteredCount: filtered.length,
    });

    setFilteredSegments(filtered);
  };

  const exportToCSV = (segmentsToExport: JourneySegment[]) => {
    console.log('[useJourneySegments] Exporting to CSV:', segmentsToExport.length);

    // CSV headers
    const headers = [
      'Tag ID',
      'Segment Type',
      'Postal Center',
      'From Center',
      'To Center',
      'Entry Time',
      'Exit Time',
      'Actual Time (min)',
      'Adjusted Time (min)',
      'Pre-Op Wait (min)',
      'Expected Time (min)',
      'SLA Compliance',
      'Created At',
    ];

    // CSV rows
    const rows = segmentsToExport.map((segment) => [
      segment.tag_id,
      segment.segment_type,
      segment.postal_center_name_snapshot || '',
      segment.from_postal_center_name_snapshot || '',
      segment.to_postal_center_name_snapshot || '',
      new Date(segment.entry_timestamp).toLocaleString(),
      new Date(segment.exit_timestamp).toLocaleString(),
      segment.actual_time_minutes,
      segment.adjusted_time_minutes,
      segment.pre_operational_wait_minutes || '',
      segment.expected_time_minutes || '',
      segment.sla_compliance,
      new Date(segment.created_at).toLocaleString(),
    ]);

    // Combine headers and rows
    const csvContent = [headers, ...rows].map((row) => row.join(',')).join('\n');

    // Create and download file
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const link = document.createElement('a');
    const url = URL.createObjectURL(blob);
    link.setAttribute('href', url);
    link.setAttribute('download', `journey_segments_${new Date().toISOString()}.csv`);
    link.style.visibility = 'hidden';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);

    console.log('[useJourneySegments] CSV export completed');
  };

  const runReconstruction = async () => {
    console.log('[useJourneySegments] Running journey reconstruction');

    if (!activeAccountId) {
      alert(t('journey_segments.error_no_account'));
      return;
    }

    setIsReconstructing(true);

    try {
      // Call the reconstruction function - it returns a table, so we need to handle it correctly
      const { data, error: rpcError } = await supabase
        .rpc('reconstruct_journeys', {
          p_account_id: activeAccountId,
        })
        .select();

      if (rpcError) throw rpcError;

      console.log('[useJourneySegments] Reconstruction result:', data);

      // Show success message
      if (data && data.length > 0) {
        const result = data[0];
        alert(
          t('journey_segments.reconstruction_success', {
            segments: result.segments_created || 0,
            events: result.events_processed || 0,
            time: result.execution_time_ms || 0,
          })
        );
      } else {
        alert(t('journey_segments.reconstruction_no_data'));
      }

      // Reload segments
      await fetchSegments();
    } catch (err: any) {
      console.error('Error running reconstruction:', err);
      alert(t('journey_segments.reconstruction_error', { message: err.message }));
    } finally {
      setIsReconstructing(false);
    }
  };

  useEffect(() => {
    fetchSegments();
  }, [activeAccountId]);

  return {
    segments,
    filteredSegments,
    loading,
    error,
    refetch: fetchSegments,
    applyFilters,
    exportToCSV,
    runReconstruction,
    isReconstructing,
  };
};
