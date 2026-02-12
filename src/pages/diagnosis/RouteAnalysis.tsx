import React, { useState, useEffect } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '../../lib/supabase';
import { Route, TrendingUp, Users, Calendar } from 'lucide-react';

interface RoutePerformance {
  origin_city_name: string;
  destination_city_name: string;
  total_journeys: number;
  completed_journeys: number;
  on_time_rate: number;
  avg_transit_hours: number;
  median_transit_hours: number;
  p95_transit_hours: number;
  total_sla_violations: number;
  missroute_count: number;
  missroute_rate: number;
}

interface CarrierComparison {
  carrier_name: string;
  total_segments: number;
  on_time_segments: number;
  on_time_rate: number;
  avg_transit_hours: number;
  total_routes: number;
}

interface RouteTrend {
  period_start: string;
  total_journeys: number;
  on_time_rate: number;
  avg_transit_hours: number;
}

const RouteAnalysis: React.FC = () => {
  const { profile } = useAuth();
  const [activeTab, setActiveTab] = useState<'performance' | 'carriers' | 'trends'>('performance');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Performance tab data
  const [routePerformance, setRoutePerformance] = useState<RoutePerformance[]>([]);

  // Carriers tab data
  const [carrierComparison, setCarrierComparison] = useState<CarrierComparison[]>([]);

  // Trends tab data
  const [routeTrends, setRouteTrends] = useState<RouteTrend[]>([]);
  const [selectedRoute, setSelectedRoute] = useState<{origin: string; destination: string} | null>(null);
  const [trendInterval, setTrendInterval] = useState<'day' | 'week' | 'month'>('week');

  useEffect(() => {
    if (activeTab === 'performance') {
      loadRoutePerformance();
    } else if (activeTab === 'carriers') {
      loadCarrierComparison();
    } else if (activeTab === 'trends') {
      loadRouteTrends();
    }
  }, [activeTab, profile?.account_id, selectedRoute, trendInterval]);

  const loadRoutePerformance = async () => {
    if (!profile?.account_id) return;

    try {
      setLoading(true);
      setError(null);

      const { data, error: rpcError } = await supabase.rpc('get_route_performance', {
        p_account_id: profile.account_id
      });

      if (rpcError) throw rpcError;
      setRoutePerformance(data || []);
    } catch (err: any) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const loadCarrierComparison = async () => {
    if (!profile?.account_id) return;

    try {
      setLoading(true);
      setError(null);

      const { data, error: rpcError } = await supabase.rpc('get_carrier_comparison', {
        p_account_id: profile.account_id
      });

      if (rpcError) throw rpcError;
      setCarrierComparison(data || []);
    } catch (err: any) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const loadRouteTrends = async () => {
    if (!profile?.account_id) return;

    try {
      setLoading(true);
      setError(null);

      const { data, error: rpcError } = await supabase.rpc('get_route_trends', {
        p_account_id: profile.account_id,
        p_origin_city: selectedRoute?.origin || null,
        p_destination_city: selectedRoute?.destination || null,
        p_interval: trendInterval
      });

      if (rpcError) throw rpcError;
      setRouteTrends(data || []);
    } catch (err: any) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const renderPerformanceTab = () => (
    <div className="space-y-4">
      <div className="overflow-x-auto">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Route</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Journeys</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">On-time Rate</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Avg Transit</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">P95 Transit</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">SLA Violations</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Missroute Rate</th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {routePerformance.map((route, idx) => (
              <tr key={idx} className="hover:bg-gray-50">
                <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                  {route.origin_city_name} → {route.destination_city_name}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {route.completed_journeys}/{route.total_journeys}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm">
                  <span className={`font-semibold ${route.on_time_rate >= 90 ? 'text-green-600' : route.on_time_rate >= 75 ? 'text-yellow-600' : 'text-red-600'}`}>
                    {route.on_time_rate?.toFixed(1)}%
                  </span>
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {route.avg_transit_hours?.toFixed(1)}h
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {route.p95_transit_hours?.toFixed(1)}h
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {route.total_sla_violations}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm">
                  <span className={`${route.missroute_rate > 5 ? 'text-red-600 font-semibold' : 'text-gray-500'}`}>
                    {route.missroute_rate?.toFixed(1)}%
                  </span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );

  const renderCarriersTab = () => (
    <div className="space-y-4">
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {carrierComparison.map((carrier, idx) => (
          <div key={idx} className="bg-white border border-gray-200 rounded-lg p-6">
            <h3 className="text-lg font-semibold text-gray-900 mb-4">{carrier.carrier_name}</h3>
            <div className="space-y-3">
              <div className="flex justify-between">
                <span className="text-sm text-gray-500">On-time Rate</span>
                <span className={`text-sm font-semibold ${carrier.on_time_rate >= 90 ? 'text-green-600' : carrier.on_time_rate >= 75 ? 'text-yellow-600' : 'text-red-600'}`}>
                  {carrier.on_time_rate?.toFixed(1)}%
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-gray-500">Avg Transit Time</span>
                <span className="text-sm font-medium text-gray-900">{carrier.avg_transit_hours?.toFixed(1)}h</span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-gray-500">Total Segments</span>
                <span className="text-sm font-medium text-gray-900">{carrier.total_segments}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-gray-500">Routes Covered</span>
                <span className="text-sm font-medium text-gray-900">{carrier.total_routes}</span>
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );

  const renderTrendsTab = () => (
    <div className="space-y-4">
      <div className="flex gap-4 items-center mb-4">
        <select
          value={trendInterval}
          onChange={(e) => setTrendInterval(e.target.value as 'day' | 'week' | 'month')}
          className="px-3 py-2 border border-gray-300 rounded-md"
        >
          <option value="day">Daily</option>
          <option value="week">Weekly</option>
          <option value="month">Monthly</option>
        </select>
      </div>

      <div className="overflow-x-auto">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Period</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Journeys</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">On-time Rate</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Avg Transit</th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {routeTrends.map((trend, idx) => (
              <tr key={idx} className="hover:bg-gray-50">
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {new Date(trend.period_start).toLocaleDateString()}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {trend.total_journeys}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm">
                  <span className={`font-semibold ${trend.on_time_rate >= 90 ? 'text-green-600' : trend.on_time_rate >= 75 ? 'text-yellow-600' : 'text-red-600'}`}>
                    {trend.on_time_rate?.toFixed(1)}%
                  </span>
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {trend.avg_transit_hours?.toFixed(1)}h
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );

  return (
    <div className="p-6">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900 flex items-center gap-2">
          <Route className="w-6 h-6" />
          Route Analysis
        </h1>
        <p className="text-gray-600 mt-1">Detailed performance analysis by route and carrier</p>
      </div>

      {/* Tabs */}
      <div className="border-b border-gray-200 mb-6">
        <nav className="-mb-px flex space-x-8">
          <button
            onClick={() => setActiveTab('performance')}
            className={`${
              activeTab === 'performance'
                ? 'border-blue-500 text-blue-600'
                : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
            } whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm flex items-center gap-2`}
          >
            <TrendingUp className="w-4 h-4" />
            Performance
          </button>
          <button
            onClick={() => setActiveTab('carriers')}
            className={`${
              activeTab === 'carriers'
                ? 'border-blue-500 text-blue-600'
                : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
            } whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm flex items-center gap-2`}
          >
            <Users className="w-4 h-4" />
            Carrier Comparison
          </button>
          <button
            onClick={() => setActiveTab('trends')}
            className={`${
              activeTab === 'trends'
                ? 'border-blue-500 text-blue-600'
                : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
            } whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm flex items-center gap-2`}
          >
            <Calendar className="w-4 h-4" />
            Trends
          </button>
        </nav>
      </div>

      {/* Content */}
      {loading ? (
        <div className="flex justify-center items-center h-64">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-500"></div>
        </div>
      ) : error ? (
        <div className="bg-red-50 border border-red-200 rounded-lg p-4">
          <p className="text-red-800">Error: {error}</p>
        </div>
      ) : (
        <>
          {activeTab === 'performance' && renderPerformanceTab()}
          {activeTab === 'carriers' && renderCarriersTab()}
          {activeTab === 'trends' && renderTrendsTab()}
        </>
      )}
    </div>
  );
};

export default RouteAnalysis;
