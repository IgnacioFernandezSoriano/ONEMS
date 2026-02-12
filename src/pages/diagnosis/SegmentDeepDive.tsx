import React, { useState, useEffect } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '../../lib/supabase';
import { Layers, Clock, AlertTriangle, TrendingUp } from 'lucide-react';

interface SegmentOverview {
  segment_type: string;
  total_count: number;
  avg_duration_minutes: number;
  min_duration_minutes: number;
  max_duration_minutes: number;
  p50_duration_minutes: number;
  p95_duration_minutes: number;
  sla_compliance_rate: number;
  on_time_count: number;
  warning_count: number;
  critical_count: number;
  violated_count: number;
}

interface SegmentTimeAnalysis {
  hour_of_day: number;
  segment_count: number;
  avg_duration_minutes: number;
  p50_duration_minutes: number;
  p95_duration_minutes: number;
  outlier_count: number;
  sla_compliance_rate: number;
}

interface SegmentAnomaly {
  segment_id: number;
  tag_id: string;
  segment_type: string;
  center_name: string;
  carrier_name: string;
  entry_timestamp: string;
  exit_timestamp: string;
  actual_duration_minutes: number;
  expected_duration_minutes: number;
  deviation_minutes: number;
  deviation_percentage: number;
  sla_compliance: string;
  anomaly_type: string;
}

const SegmentDeepDive: React.FC = () => {
  const { profile } = useAuth();
  const [activeTab, setActiveTab] = useState<'overview' | 'time' | 'anomalies'>('overview');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Overview tab data
  const [segmentOverview, setSegmentOverview] = useState<SegmentOverview[]>([]);

  // Time Analysis tab data
  const [timeAnalysis, setTimeAnalysis] = useState<SegmentTimeAnalysis[]>([]);
  const [selectedSegmentType, setSelectedSegmentType] = useState<string | null>(null);

  // Anomalies tab data
  const [anomalies, setAnomalies] = useState<SegmentAnomaly[]>([]);

  useEffect(() => {
    if (activeTab === 'overview') {
      loadSegmentOverview();
    } else if (activeTab === 'time') {
      loadTimeAnalysis();
    } else if (activeTab === 'anomalies') {
      loadAnomalies();
    }
  }, [activeTab, profile?.account_id, selectedSegmentType]);

  const loadSegmentOverview = async () => {
    if (!profile?.account_id) return;

    try {
      setLoading(true);
      setError(null);

      const { data, error: rpcError } = await supabase.rpc('get_segment_overview', {
        p_account_id: profile.account_id
      });

      if (rpcError) throw rpcError;
      setSegmentOverview(data || []);
    } catch (err: any) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const loadTimeAnalysis = async () => {
    if (!profile?.account_id) return;

    try {
      setLoading(true);
      setError(null);

      const { data, error: rpcError } = await supabase.rpc('get_segment_time_analysis', {
        p_account_id: profile.account_id,
        p_segment_type: selectedSegmentType
      });

      if (rpcError) throw rpcError;
      setTimeAnalysis(data || []);
    } catch (err: any) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const loadAnomalies = async () => {
    if (!profile?.account_id) return;

    try {
      setLoading(true);
      setError(null);

      const { data, error: rpcError } = await supabase.rpc('get_segment_anomalies', {
        p_account_id: profile.account_id
      });

      if (rpcError) throw rpcError;
      setAnomalies(data || []);
    } catch (err: any) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const getAnomalyBadgeColor = (type: string) => {
    switch (type) {
      case 'sla_violation':
        return 'bg-red-100 text-red-800';
      case 'extremely_slow':
        return 'bg-orange-100 text-orange-800';
      case 'slow':
        return 'bg-yellow-100 text-yellow-800';
      case 'stalled':
        return 'bg-purple-100 text-purple-800';
      default:
        return 'bg-gray-100 text-gray-800';
    }
  };

  const renderOverviewTab = () => (
    <div className="space-y-6">
      {loading ? (
        <div className="text-center py-8 text-gray-500">Loading...</div>
      ) : error ? (
        <div className="text-center py-8 text-red-500">Error: {error}</div>
      ) : segmentOverview.length === 0 ? (
        <div className="text-center py-8 text-gray-500">No data available</div>
      ) : (
        <>
          {/* Summary Cards */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {segmentOverview.map((segment) => (
              <div key={segment.segment_type} className="bg-white border border-gray-200 rounded-lg p-6">
                <div className="flex items-center justify-between mb-4">
                  <h3 className="text-lg font-semibold text-gray-900 capitalize">
                    {segment.segment_type} Segments
                  </h3>
                  <Layers className="h-6 w-6 text-blue-600" />
                </div>
                
                <div className="grid grid-cols-2 gap-4 mb-4">
                  <div>
                    <div className="text-sm text-gray-500">Total Count</div>
                    <div className="text-2xl font-bold text-gray-900">{segment.total_count}</div>
                  </div>
                  <div>
                    <div className="text-sm text-gray-500">SLA Compliance</div>
                    <div className={`text-2xl font-bold ${
                      segment.sla_compliance_rate >= 90 ? 'text-green-600' :
                      segment.sla_compliance_rate >= 75 ? 'text-yellow-600' :
                      'text-red-600'
                    }`}>
                      {segment.sla_compliance_rate}%
                    </div>
                  </div>
                </div>

                <div className="space-y-2 text-sm">
                  <div className="flex justify-between">
                    <span className="text-gray-600">Avg Duration:</span>
                    <span className="font-semibold">{segment.avg_duration_minutes}m</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-600">P50 Duration:</span>
                    <span className="font-semibold">{segment.p50_duration_minutes}m</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-600">P95 Duration:</span>
                    <span className="font-semibold">{segment.p95_duration_minutes}m</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-600">Range:</span>
                    <span className="font-semibold">
                      {segment.min_duration_minutes}m - {segment.max_duration_minutes}m
                    </span>
                  </div>
                </div>

                <div className="mt-4 pt-4 border-t border-gray-200">
                  <div className="grid grid-cols-4 gap-2 text-xs">
                    <div className="text-center">
                      <div className="text-green-600 font-semibold">{segment.on_time_count}</div>
                      <div className="text-gray-500">On Time</div>
                    </div>
                    <div className="text-center">
                      <div className="text-yellow-600 font-semibold">{segment.warning_count}</div>
                      <div className="text-gray-500">Warning</div>
                    </div>
                    <div className="text-center">
                      <div className="text-orange-600 font-semibold">{segment.critical_count}</div>
                      <div className="text-gray-500">Critical</div>
                    </div>
                    <div className="text-center">
                      <div className="text-red-600 font-semibold">{segment.violated_count}</div>
                      <div className="text-gray-500">Violated</div>
                    </div>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </>
      )}
    </div>
  );

  const renderTimeAnalysisTab = () => (
    <div className="space-y-4">
      <div className="flex items-center gap-2 mb-4">
        <label className="text-sm font-medium text-gray-700">Segment Type:</label>
        <select
          value={selectedSegmentType || 'all'}
          onChange={(e) => setSelectedSegmentType(e.target.value === 'all' ? null : e.target.value)}
          className="px-3 py-1 border border-gray-300 rounded-md text-sm"
        >
          <option value="all">All Types</option>
          <option value="operational">Operational</option>
          <option value="distribution">Distribution</option>
        </select>
      </div>

      {loading ? (
        <div className="text-center py-8 text-gray-500">Loading...</div>
      ) : error ? (
        <div className="text-center py-8 text-red-500">Error: {error}</div>
      ) : timeAnalysis.length === 0 ? (
        <div className="text-center py-8 text-gray-500">No data available</div>
      ) : (
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">HOUR</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">SEGMENTS</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">AVG TIME</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">P50 TIME</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">P95 TIME</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">OUTLIERS</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">SLA %</th>
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {timeAnalysis.map((row) => (
                <tr key={row.hour_of_day}>
                  <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                    {row.hour_of_day}:00
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{row.segment_count}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{row.avg_duration_minutes}m</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{row.p50_duration_minutes}m</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{row.p95_duration_minutes}m</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    {row.outlier_count > 0 ? (
                      <span className="text-orange-600 font-semibold">{row.outlier_count}</span>
                    ) : (
                      <span className="text-gray-400">0</span>
                    )}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${
                      row.sla_compliance_rate >= 90 ? 'bg-green-100 text-green-800' :
                      row.sla_compliance_rate >= 75 ? 'bg-yellow-100 text-yellow-800' :
                      'bg-red-100 text-red-800'
                    }`}>
                      {row.sla_compliance_rate}%
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );

  const renderAnomaliesTab = () => (
    <div className="space-y-4">
      {loading ? (
        <div className="text-center py-8 text-gray-500">Loading...</div>
      ) : error ? (
        <div className="text-center py-8 text-red-500">Error: {error}</div>
      ) : anomalies.length === 0 ? (
        <div className="text-center py-8 text-gray-500">No anomalies detected</div>
      ) : (
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">TAG ID</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">TYPE</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">CENTER/CARRIER</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">ACTUAL</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">EXPECTED</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">DEVIATION</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">ANOMALY</th>
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {anomalies.map((anomaly) => (
                <tr key={anomaly.segment_id}>
                  <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                    {anomaly.tag_id}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900 capitalize">
                    {anomaly.segment_type}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    <div>{anomaly.center_name}</div>
                    {anomaly.carrier_name !== 'N/A' && (
                      <div className="text-xs text-gray-500">{anomaly.carrier_name}</div>
                    )}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    {anomaly.actual_duration_minutes}m
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    {anomaly.expected_duration_minutes}m
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm">
                    <div className="text-red-600 font-semibold">+{anomaly.deviation_minutes}m</div>
                    <div className="text-xs text-gray-500">({anomaly.deviation_percentage}%)</div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${getAnomalyBadgeColor(anomaly.anomaly_type)}`}>
                      {anomaly.anomaly_type.replace('_', ' ')}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );

  return (
    <div className="p-6 max-w-7xl mx-auto">
      <div className="mb-6">
        <div className="flex items-center gap-2 mb-2">
          <Layers className="h-6 w-6 text-blue-600" />
          <h1 className="text-2xl font-bold text-gray-900">Segment Deep Dive</h1>
        </div>
        <p className="text-gray-600">Detailed analysis of journey segments by type and performance</p>
      </div>

      {/* Tabs */}
      <div className="border-b border-gray-200 mb-6">
        <nav className="-mb-px flex space-x-8">
          <button
            onClick={() => setActiveTab('overview')}
            className={`flex items-center gap-2 py-4 px-1 border-b-2 font-medium text-sm ${
              activeTab === 'overview'
                ? 'border-blue-500 text-blue-600'
                : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
            }`}
          >
            <TrendingUp className="h-4 w-4" />
            Overview
          </button>
          <button
            onClick={() => setActiveTab('time')}
            className={`flex items-center gap-2 py-4 px-1 border-b-2 font-medium text-sm ${
              activeTab === 'time'
                ? 'border-blue-500 text-blue-600'
                : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
            }`}
          >
            <Clock className="h-4 w-4" />
            Time Analysis
          </button>
          <button
            onClick={() => setActiveTab('anomalies')}
            className={`flex items-center gap-2 py-4 px-1 border-b-2 font-medium text-sm ${
              activeTab === 'anomalies'
                ? 'border-blue-500 text-blue-600'
                : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
            }`}
          >
            <AlertTriangle className="h-4 w-4" />
            Anomalies
          </button>
        </nav>
      </div>

      {/* Tab Content */}
      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
        {activeTab === 'overview' && renderOverviewTab()}
        {activeTab === 'time' && renderTimeAnalysisTab()}
        {activeTab === 'anomalies' && renderAnomaliesTab()}
      </div>
    </div>
  );
};

export default SegmentDeepDive;
