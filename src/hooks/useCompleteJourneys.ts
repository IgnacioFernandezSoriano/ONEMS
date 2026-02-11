import { useState, useEffect, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { useEffectiveAccountId } from './useEffectiveAccountId';

// Interface matching existing journeys table schema
export interface CompleteJourney {
  id: number;
  account_id: string;
  tag_id: string;
  origin_city_id: string | null;
  destination_city_id: string | null;
  origin_city_name: string | null;
  destination_city_name: string | null;
  route_path: any; // JSONB array of route segments
  total_centers_visited: number;
  total_actual_time_minutes: number | null;
  total_adjusted_time_minutes: number | null;
  total_operational_time_minutes: number | null;
  total_distribution_time_minutes: number | null;
  total_pre_operational_wait_minutes: number | null;
  journey_status: 'in_progress' | 'completed' | 'anomalous' | 'stuck';
  is_missroute: boolean;
  missroute_reason: string | null;
  first_event_timestamp: string | null;
  last_event_timestamp: string | null;
  total_sla_violations: number;
  total_segments: number;
  on_time_segments: number;
  created_at: string;
  updated_at: string;
}

export interface CompleteJourneysFilters {
  search?: string;
  journey_status?: string;
  min_segments?: number;
  max_segments?: number;
  date_from?: string;
  date_to?: string;
}

export function useCompleteJourneys() {
  const selectedAccount = useEffectiveAccountId();
  const [journeys, setJourneys] = useState<CompleteJourney[]>([]);
  const [filteredJourneys, setFilteredJourneys] = useState<CompleteJourney[]>([]);
  const [filters, setFilters] = useState<CompleteJourneysFilters>({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [isAssembling, setIsAssembling] = useState(false);

  // Fetch journeys
  const fetchJourneys = useCallback(async () => {
    if (!selectedAccount) {
      setJourneys([]);
      setFilteredJourneys([]);
      setLoading(false);
      return;
    }

    try {
      setLoading(true);
      setError(null);

      const { data, error: fetchError } = await supabase
        .from('journeys')
        .select('*')
        .eq('account_id', selectedAccount)
        .order('first_event_timestamp', { ascending: false });

      if (fetchError) throw fetchError;

      setJourneys(data || []);
      setFilteredJourneys(data || []);
    } catch (err: any) {
      console.error('Error fetching journeys:', err);
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }, [selectedAccount]);

  // Run assembly function
  const runAssembly = useCallback(async () => {
    if (!selectedAccount) {
      setError('No account selected');
      return;
    }

    try {
      setIsAssembling(true);
      setError(null);

      const { data, error: rpcError } = await supabase.rpc('assemble_journeys', {
        p_account_id: selectedAccount,
      });

      if (rpcError) throw rpcError;

      if (data && data.length > 0) {
        const result = data[0];
        console.log('Assembly completed:', result);
        
        // Refresh journeys after assembly
        await fetchJourneys();
        
        return {
          success: true,
          message: `Assembly completed: ${result.journeys_created} created, ${result.journeys_updated} updated in ${result.execution_time_ms}ms`,
        };
      } else {
        throw new Error('No data returned from assembly');
      }
    } catch (err: any) {
      console.error('Error running assembly:', err);
      setError(err.message);
      return {
        success: false,
        message: `Assembly error: ${err.message}`,
      };
    } finally {
      setIsAssembling(false);
    }
  }, [selectedAccount, fetchJourneys]);

  // Apply filters
  useEffect(() => {
    let filtered = [...journeys];

    // Search filter (tag_id or center names)
    if (filters.search) {
      const searchLower = filters.search.toLowerCase();
      filtered = filtered.filter((journey) =>
        journey.tag_id.toLowerCase().includes(searchLower) ||
        journey.origin_city_name?.toLowerCase().includes(searchLower) ||
        journey.destination_city_name?.toLowerCase().includes(searchLower)
      );
    }

    // Journey status filter
    if (filters.journey_status) {
      filtered = filtered.filter((journey) => journey.journey_status === filters.journey_status);
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
        (journey) => journey.first_event_timestamp && journey.first_event_timestamp >= filters.date_from!
      );
    }

    if (filters.date_to) {
      filtered = filtered.filter(
        (journey) => journey.first_event_timestamp && journey.first_event_timestamp <= filters.date_to!
      );
    }

    setFilteredJourneys(filtered);
  }, [journeys, filters]);

  // Initial fetch
  useEffect(() => {
    fetchJourneys();
  }, [fetchJourneys]);

  // Calculate KPIs
  const kpis = {
    total: filteredJourneys.length,
    on_time: filteredJourneys.filter((j) => j.total_sla_violations === 0).length,
    warning: filteredJourneys.filter((j) => j.total_sla_violations > 0 && j.total_sla_violations <= 2).length,
    critical: filteredJourneys.filter((j) => j.total_sla_violations > 2).length,
    avg_time: filteredJourneys.length > 0
      ? filteredJourneys.reduce((sum, j) => sum + (j.total_adjusted_time_minutes || 0), 0) / filteredJourneys.length
      : 0,
  };

  return {
    journeys: filteredJourneys,
    loading,
    error,
    filters,
    setFilters,
    kpis,
    runAssembly,
    isAssembling,
    refetch: fetchJourneys,
  };
}
