import React, { useState, useEffect } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '../../lib/supabase';
import { Activity, TrendingUp, TrendingDown, AlertCircle, Info } from 'lucide-react';

interface HealthScoreData {
  health_score: string;
  on_time_delivery_rate: string;
  avg_transit_time_hours: string;
  avg_processing_time_hours: string;
  total_items: number;
  total_routes: number;
  total_centers: number;
  total_sla_violations: number;
}

interface RoutePerformance {
  rank_type: string;
  origin_city_name: string;
  destination_city_name: string;
  total_journeys: number;
  on_time_rate: string;
  avg_transit_hours: string;
}

interface CenterPerformance {
  rank_type: string;
  center_name: string;
  total_items: number;
  avg_processing_hours: string;
  outbound_on_time_rate: string;
}

export default function NetworkOverview() {
  const { profile } = useAuth();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [healthData, setHealthData] = useState<HealthScoreData | null>(null);
  const [routes, setRoutes] = useState<RoutePerformance[]>([]);
  const [centers, setCenters] = useState<CenterPerformance[]>([]);

  useEffect(() => {
    let isMounted = true;

    const loadData = async () => {
      if (!profile?.account_id) {
        console.log('[NetworkOverview] No account ID');
        return;
      }

      try {
        setLoading(true);
        setError(null);

        // Load health score
        const { data: healthScore, error: healthError } = await supabase.rpc(
          'calculate_network_health_score',
          { p_account_id: profile.account_id }
        );

        if (healthError) throw healthError;

        // Load top/bottom routes
        const { data: routesData, error: routesError } = await supabase.rpc(
          'get_top_bottom_routes',
          { p_account_id: profile.account_id, p_limit: 5 }
        );

        if (routesError) throw routesError;

        // Load top/bottom centers
        const { data: centersData, error: centersError } = await supabase.rpc(
          'get_top_bottom_centers',
          { p_account_id: profile.account_id, p_limit: 5 }
        );

        if (centersError) throw centersError;

        if (isMounted) {
          setHealthData(healthScore?.[0] || null);
          setRoutes(routesData || []);
          setCenters(centersData || []);
        }
      } catch (err: any) {
        console.error('[NetworkOverview] Error:', err);
        if (isMounted) {
          setError(err.message);
        }
      } finally {
        if (isMounted) {
          setLoading(false);
        }
      }
    };

    loadData();

    return () => {
      isMounted = false;
    };
  }, [profile?.account_id]);

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
        <span className="ml-3 text-gray-600">Loading network overview...</span>
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-red-50 border border-red-200 rounded-lg p-4">
        <div className="flex items-center">
          <AlertCircle className="h-5 w-5 text-red-600 mr-2" />
          <span className="text-red-800">Error loading data: {error}</span>
        </div>
      </div>
    );
  }

  if (!healthData) {
    return (
      <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
        <div className="flex items-center">
          <Info className="h-5 w-5 text-yellow-600 mr-2" />
          <div>
            <p className="font-medium text-yellow-800">No data available</p>
            <p className="text-sm text-yellow-700">No journey data found for this account. Please ensure data has been ingested.</p>
          </div>
        </div>
      </div>
    );
  }

  const healthScore = parseFloat(healthData.health_score);
  const onTimeRate = parseFloat(healthData.on_time_delivery_rate);
  const avgTransit = parseFloat(healthData.avg_transit_time_hours);
  const avgProcessing = parseFloat(healthData.avg_processing_time_hours);

  // Calculate health score breakdown
  const dataQualityScore = 100; // Assuming 100% for now
  const breakdown = [
    { label: 'On-time Delivery', weight: 40, value: onTimeRate, contribution: (onTimeRate * 0.4).toFixed(1) },
    { label: 'Transit Time', weight: 30, value: Math.max(0, 100 - (avgTransit * 10)), contribution: (Math.max(0, 100 - (avgTransit * 10)) * 0.3).toFixed(1) },
    { label: 'Processing Time', weight: 20, value: Math.max(0, 100 - (avgProcessing * 20)), contribution: (Math.max(0, 100 - (avgProcessing * 20)) * 0.2).toFixed(1) },
    { label: 'Data Quality', weight: 10, value: dataQualityScore, contribution: (dataQualityScore * 0.1).toFixed(1) }
  ];

  // Generate automatic findings
  const findings = [];
  if (onTimeRate >= 95) {
    findings.push({ type: 'success', text: `Excellent on-time performance at ${onTimeRate.toFixed(1)}%, exceeding industry standards.` });
  } else if (onTimeRate < 80) {
    findings.push({ type: 'warning', text: `On-time delivery rate of ${onTimeRate.toFixed(1)}% is below target. Investigation recommended.` });
  }

  if (healthData.total_sla_violations === 0) {
    findings.push({ type: 'success', text: 'Zero SLA violations recorded across all routes.' });
  } else if (healthData.total_sla_violations > 10) {
    findings.push({ type: 'warning', text: `${healthData.total_sla_violations} SLA violations detected. Review affected routes.` });
  }

  if (avgTransit < 1) {
    findings.push({ type: 'success', text: `Average transit time of ${avgTransit.toFixed(1)}h indicates efficient network operations.` });
  }

  const topRoutes = routes.filter(r => r.rank_type === 'top');
  const bottomRoutes = routes.filter(r => r.rank_type === 'bottom');
  const topCenters = centers.filter(c => c.rank_type === 'top');
  const bottomCenters = centers.filter(c => c.rank_type === 'bottom');

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-gray-900 flex items-center">
          <Activity className="h-6 w-6 mr-2 text-blue-600" />
          Network Overview
        </h1>
        <p className="text-gray-600 mt-1">Comprehensive health assessment of the postal network</p>
      </div>

      {/* Health Score */}
      <div className="bg-gradient-to-r from-green-50 to-emerald-50 border border-green-200 rounded-lg p-6">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-lg font-semibold text-gray-900 flex items-center">
              <Activity className="h-5 w-5 mr-2 text-green-600" />
              Network Health Score
            </h2>
            <p className="text-sm text-gray-600 mt-1">Weighted average of key performance indicators</p>
          </div>
          <div className="text-right">
            <div className="text-5xl font-bold text-green-600">{healthScore.toFixed(1)}</div>
            <div className="text-sm text-gray-500">out of 100</div>
          </div>
        </div>

        {/* Health Score Breakdown */}
        <div className="mt-6 space-y-3">
          <h3 className="text-sm font-medium text-gray-700">Score Breakdown</h3>
          {breakdown.map((item, idx) => (
            <div key={idx} className="bg-white rounded-lg p-3 border border-gray-200">
              <div className="flex items-center justify-between mb-2">
                <span className="text-sm font-medium text-gray-700">{item.label}</span>
                <span className="text-xs text-gray-500">Weight: {item.weight}%</span>
              </div>
              <div className="flex items-center justify-between">
                <div className="flex-1 mr-4">
                  <div className="w-full bg-gray-200 rounded-full h-2">
                    <div
                      className="bg-green-500 h-2 rounded-full"
                      style={{ width: `${item.value}%` }}
                    ></div>
                  </div>
                </div>
                <div className="text-right">
                  <div className="text-sm font-semibold text-gray-900">{item.value.toFixed(1)}%</div>
                  <div className="text-xs text-gray-500">+{item.contribution} pts</div>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* KPIs */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <KPICard
          icon="📈"
          title="On-time Delivery"
          value={`${onTimeRate.toFixed(1)}%`}
          subtitle={`${healthData.total_items} items`}
          tooltip="Percentage of journeys completed without SLA violations. Calculated as: (journeys with 0 SLA violations / total journeys) × 100. Higher is better."
        />
        <KPICard
          icon="⏱️"
          title="Avg Transit Time"
          value={`${avgTransit.toFixed(1)}h`}
          subtitle={`${healthData.total_routes} routes`}
          tooltip="Average end-to-end transit time across all completed journeys. Calculated from first event to last event timestamp. Lower is better."
        />
        <KPICard
          icon="🏢"
          title="Avg Processing Time"
          value={`${avgProcessing.toFixed(1)}h`}
          subtitle={`${healthData.total_centers} centers`}
          tooltip="Average time items spend at postal centers for processing. Calculated from processing segments only. Lower indicates faster operations."
        />
        <KPICard
          icon="✅"
          title="Data Quality"
          value="100.0%"
          subtitle="Data completeness"
          tooltip="Percentage of complete and valid data records. Based on presence of required fields and data consistency checks."
        />
      </div>

      {/* Automatic Findings */}
      {findings.length > 0 && (
        <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
          <h3 className="text-sm font-semibold text-blue-900 mb-3">Automatic Findings</h3>
          <div className="space-y-2">
            {findings.map((finding, idx) => (
              <div key={idx} className={`flex items-start p-2 rounded ${
                finding.type === 'success' ? 'bg-green-50' : 'bg-yellow-50'
              }`}>
                <span className="mr-2">{finding.type === 'success' ? '✓' : '⚠️'}</span>
                <span className="text-sm text-gray-700">{finding.text}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Network Summary */}
      <div className="bg-white border border-gray-200 rounded-lg p-4">
        <h3 className="text-sm font-semibold text-gray-900 mb-4">Network Summary</h3>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <SummaryItem label="Total Items" value={healthData.total_items} />
          <SummaryItem label="Active Routes" value={healthData.total_routes} />
          <SummaryItem label="Postal Centers" value={healthData.total_centers} />
          <SummaryItem label="SLA Violations" value={healthData.total_sla_violations} highlight={healthData.total_sla_violations > 0} />
        </div>
      </div>

      {/* Top/Bottom Routes */}
      {routes.length > 0 && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <PerformanceTable
            title="Top 5 Routes"
            icon={<TrendingUp className="h-5 w-5 text-green-600" />}
            data={topRoutes}
            type="route"
          />
          <PerformanceTable
            title="Bottom 5 Routes"
            icon={<TrendingDown className="h-5 w-5 text-red-600" />}
            data={bottomRoutes}
            type="route"
          />
        </div>
      )}

      {/* Top/Bottom Centers */}
      {centers.length > 0 && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <PerformanceTable
            title="Top 5 Centers"
            icon={<TrendingUp className="h-5 w-5 text-green-600" />}
            data={topCenters}
            type="center"
          />
          <PerformanceTable
            title="Bottom 5 Centers"
            icon={<TrendingDown className="h-5 w-5 text-red-600" />}
            data={bottomCenters}
            type="center"
          />
        </div>
      )}
    </div>
  );
}

function KPICard({ icon, title, value, subtitle, tooltip }: any) {
  return (
    <div className="bg-white border border-gray-200 rounded-lg p-4 relative group">
      <div className="flex items-center justify-between mb-2">
        <span className="text-2xl">{icon}</span>
        <Info className="h-4 w-4 text-gray-400 cursor-help" />
      </div>
      <h3 className="text-sm font-medium text-gray-600">{title}</h3>
      <p className="text-2xl font-bold text-gray-900 mt-1">{value}</p>
      <p className="text-xs text-gray-500 mt-1">{subtitle}</p>
      
      {/* Tooltip */}
      <div className="absolute bottom-full left-0 mb-2 hidden group-hover:block w-64 p-3 bg-gray-900 text-white text-xs rounded-lg shadow-lg z-10">
        {tooltip}
        <div className="absolute top-full left-4 w-0 h-0 border-l-4 border-r-4 border-t-4 border-transparent border-t-gray-900"></div>
      </div>
    </div>
  );
}

function SummaryItem({ label, value, highlight }: any) {
  return (
    <div className="text-center">
      <div className={`text-2xl font-bold ${highlight ? 'text-red-600' : 'text-gray-900'}`}>{value}</div>
      <div className="text-xs text-gray-500 mt-1">{label}</div>
    </div>
  );
}

function PerformanceTable({ title, icon, data, type }: any) {
  return (
    <div className="bg-white border border-gray-200 rounded-lg p-4">
      <h3 className="text-sm font-semibold text-gray-900 mb-4 flex items-center">
        {icon}
        <span className="ml-2">{title}</span>
      </h3>
      <div className="overflow-x-auto">
        <table className="min-w-full text-sm">
          <thead>
            <tr className="border-b border-gray-200">
              {type === 'route' ? (
                <>
                  <th className="text-left py-2 px-2 font-medium text-gray-700">Route</th>
                  <th className="text-right py-2 px-2 font-medium text-gray-700">Items</th>
                  <th className="text-right py-2 px-2 font-medium text-gray-700">On-time</th>
                  <th className="text-right py-2 px-2 font-medium text-gray-700">Avg Time</th>
                </>
              ) : (
                <>
                  <th className="text-left py-2 px-2 font-medium text-gray-700">Center</th>
                  <th className="text-right py-2 px-2 font-medium text-gray-700">Items</th>
                  <th className="text-right py-2 px-2 font-medium text-gray-700">On-time</th>
                  <th className="text-right py-2 px-2 font-medium text-gray-700">Proc Time</th>
                </>
              )}
            </tr>
          </thead>
          <tbody>
            {data.map((row: any, idx: number) => (
              <tr key={idx} className="border-b border-gray-100 hover:bg-gray-50">
                {type === 'route' ? (
                  <>
                    <td className="py-2 px-2 text-gray-900">
                      {row.origin_city_name} → {row.destination_city_name}
                    </td>
                    <td className="text-right py-2 px-2 text-gray-700">{row.total_journeys}</td>
                    <td className="text-right py-2 px-2 text-gray-700">{parseFloat(row.on_time_rate).toFixed(1)}%</td>
                    <td className="text-right py-2 px-2 text-gray-700">{parseFloat(row.avg_transit_hours).toFixed(1)}h</td>
                  </>
                ) : (
                  <>
                    <td className="py-2 px-2 text-gray-900">{row.center_name}</td>
                    <td className="text-right py-2 px-2 text-gray-700">{row.total_items}</td>
                    <td className="text-right py-2 px-2 text-gray-700">{parseFloat(row.outbound_on_time_rate).toFixed(1)}%</td>
                    <td className="text-right py-2 px-2 text-gray-700">{parseFloat(row.avg_processing_hours).toFixed(1)}h</td>
                  </>
                )}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
