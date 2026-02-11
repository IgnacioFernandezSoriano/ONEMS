import { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';
import { useEffectiveAccountId } from './useEffectiveAccountId';
import { useTranslation } from './useTranslation';

export interface CompleteJourney {
  id: string;
  account_id: string;
  tag_id: string;
  total_segments: number;
  operational_segments: number;
  distribution_segments: number;
  journey_start_timestamp: string;
  journey_end_timestamp: string;
  centers_visited: string[];
  center_ids_visited: string[];
  total_actual_time_minutes: number;
  total_adjusted_time_minutes: number;
  total_operational_time_minutes: number;
  total_distribution_time_minutes: number;
  total_pre_operational_wait_minutes?: number;
  overall_sla_compliance: 'on_time' | 'warning' | 'critical' | 'violated' | 'no_sla' | 'mixed';
  segments_on_time: number;
  segments_warning: number;
  segments_critical: number;
  segments_violated: number;
  segments_no_sla: number;
  is_complete: boolean;
  has_gaps: boolean;
  created_at: string;
  updated_at: string;
}

export interface CompleteJourneysFilters {
  search?: string;
  sla_compliance?: string;
  min_segments?: number;
  max_segments?: number;
  date_from?: string;
  date_to?: string;
}

export const useCompleteJourneys = (accountId: string | undefined) => {
  const effectiveAccountId = useEffectiveAccountId();
  const activeAccountId = effectiveAccountId || accountId;
  const { t } = useTranslation();

  const [journeys, setJourneys] = useState<CompleteJourney[]>([]);
  const [filteredJourneys, setFilteredJourneys] = useState<CompleteJourney[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [isAssembling, setIsAssembling] = useState(false);

  const fetchJourneys = async () => {
    console.log('[useCompleteJourneys] fetchJourneys called with activeAccountId:', activeAccountId);

    if (!activeAccountId) {
      console.log('[useCompleteJourneys] No accountId provided, skipping fetch');
      setLoading(false);
      return;
    }

    try {
      setLoading(true);
      setError(null);

      console.log(
        '[useCompleteJourneys] Fetching from journeys table with accountId:',
        activeAccountId
      );

      // Paginate to handle Supabase 1000-record limit
      const allJourneys: CompleteJourney[] = [];
      const pageSize = 1000;
      let start = 0;
      let hasMore = true;

      while (hasMore) {
        const { data, error: fetchError } = await supabase
          .from('journeys')
          .select('*')
          .eq('account_id', activeAccountId)
          .order('journey_start_timestamp', { ascending: false })
          .range(start, start + pageSize - 1);

        if (fetchError) throw fetchError;

        if (data && data.length > 0) {
          allJourneys.push(...data);
          hasMore = data.length === pageSize;
          start += pageSize;
        } else {
          hasMore = false;
        }
      }

      console.log('[useCompleteJourneys] Query result:', {
        dataCount: allJourneys.length,
        sampleData: allJourneys[0] || null,
      });

      setJourneys(allJourneys);
      setFilteredJourneys(allJourneys);
    } catch (err: any) {
      setError(err.message);
      console.error('Error fetching complete journeys:', err);
    } finally {
      setLoading(false);
    }
  };

  const applyFilters = (filters: CompleteJourneysFilters) => {
    console.log('[useCompleteJourneys] Applying filters:', filters);

    let filtered = [...journeys];

    // Search filter (tag_id or centers visited)
    if (filters.search) {
      const searchLower = filters.search.toLowerCase();
      filtered = filtered.filter(
        (journey) =>
          journey.tag_id.toLowerCase().includes(searchLower) ||
          journey.centers_visited.some((center) => center.toLowerCase().includes(searchLower))
      );
    }

    // SLA compliance filter
    if (filters.sla_compliance) {
      filtered = filtered.filter((journey) => journey.overall_sla_compliance === filters.sla_compliance);
    }

    // Segment count filters
    if (filters.min_segments !== undefined) {
      filtered = filtered.filter((journey) => journey.total_segments >= filters.min_segments!);
    }

    if (filters.max_segments !== undefined) {
      filtered = filtered.filter((journey) => journey.total_segments <= filters.max_segments!);
    }

    // Date range filter (journey start timestamp)
    if (filters.date_from) {
      filtered = filtered.filter(
        (journey) => new Date(journey.journey_start_timestamp) >= new Date(filters.date_from!)
      );
    }

    if (filters.date_to) {
      const dateTo = new Date(filters.date_to!);
      dateTo.setHours(23, 59, 59, 999); // Include the entire day
      filtered = filtered.filter((journey) => new Date(journey.journey_start_timestamp) <= dateTo);
    }

    console.log('[useCompleteJourneys] Filtered results:', {
      originalCount: journeys.length,
      filteredCount: filtered.length,
    });

    setFilteredJourneys(filtered);
  };

  const exportToCSV = (journeysToExport: CompleteJourney[]) => {
    console.log('[useCompleteJourneys] Exporting to CSV:', journeysToExport.length);

    // CSV headers
    const headers = [
      'Tag ID',
      'Total Segments',
      'Operational',
      'Distribution',
      'Start Time',
      'End Time',
      'Centers Visited',
      'Total Time (min)',
      'Operational Time (min)',
      'Distribution Time (min)',
      'Pre-Op Wait (min)',
      'Overall Compliance',
      'On Time',
      'Warning',
      'Critical',
      'Violated',
      'No SLA',
      'Complete',
      'Has Gaps',
    ];

    // CSV rows
    const rows = journeysToExport.map((journey) => [
      journey.tag_id,
      journey.total_segments,
      journey.operational_segments,
      journey.distribution_segments,
      new Date(journey.journey_start_timestamp).toLocaleString(),
      new Date(journey.journey_end_timestamp).toLocaleString(),
      journey.centers_visited.join(' → '),
      journey.total_adjusted_time_minutes,
      journey.total_operational_time_minutes,
      journey.total_distribution_time_minutes,
      journey.total_pre_operational_wait_minutes || '',
      journey.overall_sla_compliance,
      journey.segments_on_time,
      journey.segments_warning,
      journey.segments_critical,
      journey.segments_violated,
      journey.segments_no_sla,
      journey.is_complete ? 'Yes' : 'No',
      journey.has_gaps ? 'Yes' : 'No',
    ]);

    // Combine headers and rows
    const csvContent = [headers, ...rows].map((row) => row.join(',')).join('\n');

    // Create and download file
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const link = document.createElement('a');
    const url = URL.createObjectURL(blob);
    link.setAttribute('href', url);
    link.setAttribute('download', `complete_journeys_${new Date().toISOString()}.csv`);
    link.style.visibility = 'hidden';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);

    console.log('[useCompleteJourneys] CSV export completed');
  };

  const runAssembly = async () => {
    console.log('[useCompleteJourneys] Running journey assembly');

    if (!activeAccountId) {
      alert(t('complete_journeys.error_no_account'));
      return;
    }

    setIsAssembling(true);

    try {
      // Call the assembly function
      const { data, error: rpcError } = await supabase.rpc('assemble_journeys', {
        p_account_id: activeAccountId,
      });

      if (rpcError) throw rpcError;

      console.log('[useCompleteJourneys] Assembly result:', data);

      // Show success message
      if (data && data.length > 0) {
        const result = data[0];
        alert(
          t('complete_journeys.assembly_success', {
            created: result.journeys_created || 0,
            updated: result.journeys_updated || 0,
            time: result.execution_time_ms || 0,
          })
        );
      } else {
        alert(t('complete_journeys.assembly_no_data'));
      }

      // Reload journeys
      await fetchJourneys();
    } catch (err: any) {
      console.error('Error running assembly:', err);
      alert(t('complete_journeys.assembly_error', { message: err.message }));
    } finally {
      setIsAssembling(false);
    }
  };

  useEffect(() => {
    fetchJourneys();
  }, [activeAccountId]);

  return {
    journeys,
    filteredJourneys,
    loading,
    error,
    refetch: fetchJourneys,
    applyFilters,
    exportToCSV,
    runAssembly,
    isAssembling,
  };
};
