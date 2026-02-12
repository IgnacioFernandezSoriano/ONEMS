import React, { useState, useEffect } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '../../lib/supabase';
import { Building2, TrendingUp, BarChart3, Calendar } from 'lucide-react';

interface CenterPerformance {
  center_id: string;
  center_name: string;
  center_code: string;
  total_segments: number;
  avg_processing_minutes: number;
  min_processing_minutes: number;
  max_processing_minutes: number;
  p95_processing_minutes: number;
  throughput_per_hour: number;
  efficiency_percentage: number;
}

interface CenterComparison {
  center_name: string;
  center_code: string;
  items_processed: number;
  avg_processing_minutes: number;
  efficiency_score: number;
  performance_rank: number;
}

interface CenterTrend {
  period_date: string;
  center_name: string;
  items_count: number;
  avg_processing_minutes: number;
  efficiency_percentage: number;
}

const CenterAnalysis: React.FC = () => {
  const { profile } = useAuth();
  const [activeTab, setActiveTab] = useState<'performance' | 'comparison' | 'trends'>('performance');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Performance tab data
  const [centerPerformance, setCenterPerformance] = useState<CenterPerformance[]>([]);

  // Comparison tab data
  const [centerComparison, setCenterComparison] = useState<CenterComparison[]>([]);

  // Trends tab data
  const [centerTrends, setCenterTrends] = useState<CenterTrend[]>([]);
  const [trendPeriod, setTrendPeriod] = useState<'daily' | 'weekly' | 'monthly'>('weekly');

  useEffect(() => {
    if (activeTab === 'performance') {
      loadCenterPerformance();
    } else if (activeTab === 'comparison') {
      loadCenterComparison();
    } else if (activeTab === 'trends') {
      loadCenterTrends();
    }
  }, [activeTab, profile?.account_id, trendPeriod]);

  const loadCenterPerformance = async () => {
    if (!profile?.account_id) return;

    try {
      setLoading(true);
      setError(null);

      const { data, error: rpcError } = await supabase.rpc('get_center_performance', {
        p_account_id: profile.account_id
      });

      if (rpcError) throw rpcError;
      setCenterPerformance(data || []);
    } catch (err: any) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const loadCenterComparison = async () => {
    if (!profile?.account_id) return;

    try {
      setLoading(true);
      setError(null);

      const { data, error: rpcError } = await supabase.rpc('get_center_comparison', {
        p_account_id: profile.account_id
      });

      if (rpcError) throw rpcError;
      setCenterComparison(data || []);
    } catch (err: any) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const loadCenterTrends = async () => {
    if (!profile?.account_id) return;

    try {
      setLoading(true);
      setError(null);

      const { data, error: rpcError } = await supabase.rpc('get_center_trends', {
        p_account_id: profile.account_id,
        p_period: trendPeriod
      });

      if (rpcError) throw rpcError;
      setCenterTrends(data || []);
    } catch (err: any) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const renderPerformanceTab = () => (
    <div className="space-y-4">
      {loading ? (
        <div className="text-center py-8 text-gray-500">Loading...</div>
      ) : error ? (
        <div className="text-center py-8 text-red-500">Error: {error}</div>
      ) : centerPerformance.length === 0 ? (
        <div className="text-center py-8 text-gray-500">No data available</div>
      ) : (
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">CENTER</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">ITEMS</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">AVG TIME</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">P95 TIME</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">THROUGHPUT</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">EFFICIENCY</th>
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {centerPerformance.map((center) => (
                <tr key={center.center_id}>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className="text-sm font-medium text-gray-900">{center.center_name}</div>
                    <div className="text-sm text-gray-500">{center.center_code}</div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{center.total_segments}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{center.avg_processing_minutes}m</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{center.p95_processing_minutes}m</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{center.throughput_per_hour} items/h</td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${
                      center.efficiency_percentage >= 90 ? 'bg-green-100 text-green-800' :
                      center.efficiency_percentage >= 75 ? 'bg-yellow-100 text-yellow-800' :
                      'bg-red-100 text-red-800'
                    }`}>
                      {center.efficiency_percentage}%
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

  const renderComparisonTab = () => (
    <div className="space-y-4">
      {loading ? (
        <div className="text-center py-8 text-gray-500">Loading...</div>
      ) : error ? (
        <div className="text-center py-8 text-red-500">Error: {error}</div>
      ) : centerComparison.length === 0 ? (
        <div className="text-center py-8 text-gray-500">No data available</div>
      ) : (
        <div className="grid gap-4">
          {centerComparison.map((center) => (
            <div key={center.center_code} className="bg-white border border-gray-200 rounded-lg p-4">
              <div className="flex items-center justify-between mb-3">
                <div>
                  <h3 className="text-lg font-semibold text-gray-900">{center.center_name}</h3>
                  <p className="text-sm text-gray-500">Rank #{center.performance_rank}</p>
                </div>
                <div className="text-right">
                  <div className="text-2xl font-bold text-gray-900">{center.efficiency_score}%</div>
                  <div className="text-sm text-gray-500">Efficiency</div>
                </div>
              </div>
              <div className="grid grid-cols-3 gap-4 text-sm">
                <div>
                  <div className="text-gray-500">Items Processed</div>
                  <div className="font-semibold text-gray-900">{center.items_processed}</div>
                </div>
                <div>
                  <div className="text-gray-500">Avg Time</div>
                  <div className="font-semibold text-gray-900">{center.avg_processing_minutes}m</div>
                </div>
                <div>
                  <div className="text-gray-500">Code</div>
                  <div className="font-semibold text-gray-900">{center.center_code}</div>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );

  const renderTrendsTab = () => {
    // Group trends by center
    const trendsByCenter = centerTrends.reduce((acc, trend) => {
      if (!acc[trend.center_name]) {
        acc[trend.center_name] = [];
      }
      acc[trend.center_name].push(trend);
      return acc;
    }, {} as Record<string, CenterTrend[]>);

    return (
      <div className="space-y-4">
        <div className="flex items-center gap-2 mb-4">
          <label className="text-sm font-medium text-gray-700">Period:</label>
          <select
            value={trendPeriod}
            onChange={(e) => setTrendPeriod(e.target.value as 'daily' | 'weekly' | 'monthly')}
            className="px-3 py-1 border border-gray-300 rounded-md text-sm"
          >
            <option value="daily">Daily</option>
            <option value="weekly">Weekly</option>
            <option value="monthly">Monthly</option>
          </select>
        </div>

        {loading ? (
          <div className="text-center py-8 text-gray-500">Loading...</div>
        ) : error ? (
          <div className="text-center py-8 text-red-500">Error: {error}</div>
        ) : centerTrends.length === 0 ? (
          <div className="text-center py-8 text-gray-500">No data available</div>
        ) : (
          <div className="space-y-6">
            {Object.entries(trendsByCenter).map(([centerName, trends]) => (
              <div key={centerName} className="bg-white border border-gray-200 rounded-lg p-4">
                <h3 className="text-lg font-semibold text-gray-900 mb-3">{centerName}</h3>
                <div className="overflow-x-auto">
                  <table className="min-w-full divide-y divide-gray-200">
                    <thead className="bg-gray-50">
                      <tr>
                        <th className="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">PERIOD</th>
                        <th className="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">ITEMS</th>
                        <th className="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">AVG TIME</th>
                        <th className="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">EFFICIENCY</th>
                      </tr>
                    </thead>
                    <tbody className="bg-white divide-y divide-gray-200">
                      {trends.map((trend, idx) => (
                        <tr key={idx}>
                          <td className="px-4 py-2 whitespace-nowrap text-sm text-gray-900">
                            {new Date(trend.period_date).toLocaleDateString()}
                          </td>
                          <td className="px-4 py-2 whitespace-nowrap text-sm text-gray-900">{trend.items_count}</td>
                          <td className="px-4 py-2 whitespace-nowrap text-sm text-gray-900">{trend.avg_processing_minutes}m</td>
                          <td className="px-4 py-2 whitespace-nowrap">
                            <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${
                              trend.efficiency_percentage >= 90 ? 'bg-green-100 text-green-800' :
                              trend.efficiency_percentage >= 75 ? 'bg-yellow-100 text-yellow-800' :
                              'bg-red-100 text-red-800'
                            }`}>
                              {trend.efficiency_percentage}%
                            </span>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    );
  };

  return (
    <div className="p-6 max-w-7xl mx-auto">
      <div className="mb-6">
        <div className="flex items-center gap-2 mb-2">
          <Building2 className="h-6 w-6 text-blue-600" />
          <h1 className="text-2xl font-bold text-gray-900">Center Analysis</h1>
        </div>
        <p className="text-gray-600">Operational performance analysis by center</p>
      </div>

      {/* Tabs */}
      <div className="border-b border-gray-200 mb-6">
        <nav className="-mb-px flex space-x-8">
          <button
            onClick={() => setActiveTab('performance')}
            className={`flex items-center gap-2 py-4 px-1 border-b-2 font-medium text-sm ${
              activeTab === 'performance'
                ? 'border-blue-500 text-blue-600'
                : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
            }`}
          >
            <TrendingUp className="h-4 w-4" />
            Performance
          </button>
          <button
            onClick={() => setActiveTab('comparison')}
            className={`flex items-center gap-2 py-4 px-1 border-b-2 font-medium text-sm ${
              activeTab === 'comparison'
                ? 'border-blue-500 text-blue-600'
                : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
            }`}
          >
            <BarChart3 className="h-4 w-4" />
            Comparison
          </button>
          <button
            onClick={() => setActiveTab('trends')}
            className={`flex items-center gap-2 py-4 px-1 border-b-2 font-medium text-sm ${
              activeTab === 'trends'
                ? 'border-blue-500 text-blue-600'
                : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
            }`}
          >
            <Calendar className="h-4 w-4" />
            Trends
          </button>
        </nav>
      </div>

      {/* Tab Content */}
      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
        {activeTab === 'performance' && renderPerformanceTab()}
        {activeTab === 'comparison' && renderComparisonTab()}
        {activeTab === 'trends' && renderTrendsTab()}
      </div>
    </div>
  );
};

export default CenterAnalysis;
