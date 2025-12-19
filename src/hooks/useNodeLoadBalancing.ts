import { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';
import { useEffectiveAccountId } from './useEffectiveAccountId'

export interface NodeLoadData {
  account_id: string;
  node_id: string;
  node_code: string;
  panelist_name?: string;
  city_name: string;
  city_id: string;
  week_number: number;
  week_start_date?: string;
  week_end_date?: string;
  month?: number;
  year?: number;
  shipment_count: number;
  sent_count: number;
  received_count: number;
  pending_count: number;
  city_weekly_avg: number;
  city_weekly_stddev: number;
  city_weekly_total: number;
  city_node_count: number;
  city_monthly_avg?: number;
  city_monthly_stddev?: number;
  city_monthly_total?: number;
  city_period_avg: number;
  city_period_stddev: number;
  city_period_total: number;
  total_weeks_in_period: number;
  saturation_level: 'normal' | 'high' | 'saturated';
  load_percentage: number;
  excess_load: number;
  reference_load: number;
  deviation_threshold: number;
}

export interface CityLoadSummary {
  city_id: string;
  city_name: string;
  total_shipments: number;
  avg_per_node: number;
  monthly_stddev: number;
  node_count: number;
  saturated_nodes: number;
  high_nodes: number;
  normal_nodes: number;
}

export interface MatrixCell {
  node_code: string;
  week_num: number;
  load_count: number;
}

export interface BalanceResult {
  success: boolean;
  movements_count: number;
  stddev_before: number;
  stddev_after: number;
  improvement_percentage: number;
  movements: Array<{
    from_node_id: string;
    from_node_code: string;
    from_week: number;
    to_node_id: string;
    to_node_code: string;
    to_week: number;
    shipment_ids: string[];
    count: number;
  }>;
  matrix_before?: MatrixCell[];
  matrix_after?: MatrixCell[];
  nodes_count?: number;
  avg_load_per_node?: number;
  max_acceptable_load?: number;
  nodes_needed?: number;
  reference_load?: number;
  deviation_percent?: number;
  message: string;
  error?: string;
}

export const useNodeLoadBalancing = (
  accountId: string | undefined, 
  startDate: string, 
  endDate: string,
  referenceLoad: number = 6,
  deviationPercent: number = 20
) => {
  const [loadData, setLoadData] = useState<NodeLoadData[]>([]);
  const [citySummaries, setCitySummaries] = useState<CityLoadSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchLoadData = async () => {
    if (!accountId) {
      console.log('[useNodeLoadBalancing] No accountId provided');
      return;
    }

    try {
      setLoading(true);
      setError(null);

      console.log('[useNodeLoadBalancing] Fetching data with:', { accountId, startDate, endDate, referenceLoad, deviationPercent });

      // Skip if dates are not set
      if (!startDate || !endDate) {
        console.log('[useNodeLoadBalancing] No dates provided, skipping fetch');
        setLoadData([]);
        setCitySummaries([]);
        setLoading(false);
        return;
      }

      const { data, error: fetchError } = await supabase
        .rpc('rpc_get_node_load_by_period', {
          p_account_id: accountId,
          p_start_date: startDate,
          p_end_date: endDate,
          p_reference_load: referenceLoad,
          p_deviation_percent: deviationPercent
        });

      console.log('[useNodeLoadBalancing] Query result:', { 
        dataCount: data?.length || 0, 
        error: fetchError,
        sampleData: data?.[0]
      });

      if (fetchError) throw fetchError;

      setLoadData(data || []);

      // Calculate city summaries
      if (data) {
        const summaries = calculateCitySummaries(data);
        console.log('[useNodeLoadBalancing] City summaries:', summaries);
        setCitySummaries(summaries);
      }
    } catch (err: any) {
      console.error('[useNodeLoadBalancing] Error fetching load data:', err);
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const calculateCitySummaries = (data: NodeLoadData[]): CityLoadSummary[] => {
    const cityMap = new Map<string, NodeLoadData[]>();

    // Group by city
    data.forEach((item) => {
      if (!cityMap.has(item.city_id)) {
        cityMap.set(item.city_id, []);
      }
      cityMap.get(item.city_id)!.push(item);
    });

    // Calculate summaries
    const summaries: CityLoadSummary[] = [];

    cityMap.forEach((cityData, cityId) => {
      const cityName = cityData[0].city_name;
      const totalShipments = cityData.reduce((sum, item) => sum + item.shipment_count, 0);
      const nodeCount = new Set(cityData.map((item) => item.node_id)).size;
      const avgPerNode = totalShipments / nodeCount;
      const monthlyStddev = cityData[0].city_period_stddev || cityData[0].city_monthly_stddev || 0;

      const saturatedNodes = new Set(
        cityData.filter((item) => item.saturation_level === 'saturated').map((item) => item.node_id)
      ).size;

      const highNodes = new Set(
        cityData.filter((item) => item.saturation_level === 'high').map((item) => item.node_id)
      ).size;

      const normalNodes = nodeCount - saturatedNodes - highNodes;

      summaries.push({
        city_id: cityId,
        city_name: cityName,
        total_shipments: totalShipments,
        avg_per_node: avgPerNode,
        monthly_stddev: monthlyStddev,
        node_count: nodeCount,
        saturated_nodes: saturatedNodes,
        high_nodes: highNodes,
        normal_nodes: normalNodes,
      });
    });

    return summaries.sort((a, b) => b.monthly_stddev - a.monthly_stddev);
  };

  const previewBalance = async (cityId: string): Promise<BalanceResult> => {
    try {
      const { data, error: rpcError } = await supabase.rpc('rpc_balance_node_load_by_period', {
        p_city_id: cityId,
        p_start_date: startDate,
        p_end_date: endDate,
        p_apply_changes: false, // Preview only
      });

      if (rpcError) throw rpcError;

      return data as BalanceResult;
    } catch (err: any) {
      console.error('Error previewing balance:', err);
      return {
        success: false,
        movements_count: 0,
        stddev_before: 0,
        stddev_after: 0,
        improvement_percentage: 0,
        movements: [],
        message: '',
        error: err.message,
      };
    }
  };

  const applyBalance = async (cityId: string): Promise<BalanceResult> => {
    try {
      const { data, error: rpcError } = await supabase.rpc('rpc_balance_node_load_by_period', {
        p_city_id: cityId,
        p_start_date: startDate,
        p_end_date: endDate,
        p_apply_changes: true, // Apply changes
      });

      if (rpcError) throw rpcError;

      // Refresh data after balancing
      await fetchLoadData();

      return data as BalanceResult;
    } catch (err: any) {
      console.error('Error applying balance:', err);
      return {
        success: false,
        movements_count: 0,
        stddev_before: 0,
        stddev_after: 0,
        improvement_percentage: 0,
        movements: [],
        message: '',
        error: err.message,
      };
    }
  };

  useEffect(() => {
    fetchLoadData();
  }, [accountId, startDate, endDate, referenceLoad, deviationPercent]);

  return {
    loadData,
    citySummaries,
    loading,
    error,
    refetch: fetchLoadData,
    previewBalance,
    applyBalance,
  };
};
