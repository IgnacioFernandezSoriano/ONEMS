import { useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { useReportingFilters } from '@/contexts/ReportingFiltersContext';
import { useJKPerformance } from '@/hooks/reporting/useJKPerformance';
import { KPICard } from '@/components/reporting/KPICard';
import { ReportFilters } from '@/components/reporting/ReportFilters';
import { Package, Clock, CheckCircle, AlertTriangle, Info } from 'lucide-react';

export default function JKPerformance() {
  const { profile } = useAuth();
  const accountId = profile?.account_id || undefined;
  const { filters, setFilters, resetFilters } = useReportingFilters();
  const [activeTab, setActiveTab] = useState<'route' | 'city' | 'region' | 'carrier' | 'product'>('route');

  const {
    routeData,
    cityData,
    regionData,
    carrierData,
    productData,
    weeklySamples,
    metrics,
    maxDays,
    loading,
    error,
  } = useJKPerformance(accountId, {
    startDate: filters.startDate,
    endDate: filters.endDate,
    originCity: filters.originCity,
    destinationCity: filters.destinationCity,
    carrier: filters.carrier,
    product: filters.product,

  });

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-500">Loading J+K performance data...</div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-red-500">Error loading data: {error.message}</div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">J+K Performance Report</h1>
          <p className="text-gray-600 mt-1">Transit time analysis and delivery performance tracking</p>
        </div>
        <div className="group relative">
          <div className="flex items-center gap-2 px-4 py-2 bg-blue-50 border border-blue-200 rounded-lg cursor-help">
            <Info className="w-5 h-5 text-blue-600" />
            <span className="text-sm font-medium text-blue-900">About this Report</span>
          </div>
          <div className="invisible group-hover:visible absolute z-10 w-96 p-4 bg-white border border-gray-200 rounded-lg shadow-xl text-sm text-gray-700 right-0 top-12">
            <div className="absolute -top-1 right-8 w-2 h-2 bg-white border-l border-t border-gray-200 transform rotate-45"></div>
            <h3 className="font-bold text-gray-900 mb-3">J+K Performance Report</h3>
            <p className="mb-3"><strong>Purpose:</strong> Analyzes actual transit times (J+K Actual) against delivery standards (J+K Std) to identify routes, cities, carriers, or products with systematic delays.</p>
            <p className="mb-3"><strong>What you'll see:</strong> Multi-level analysis showing Route, City, Region, Carrier, and Product performance. Color-coded metrics help identify problematic areas at a glance.</p>
            <p className="mb-3"><strong>J+K Standard:</strong> Expected delivery time in days from delivery_standards table. Automatically converted from hours if needed.</p>
            <p className="mb-3"><strong>J+K Actual:</strong> Average actual transit time in business days from shipment data.</p>
            <p className="mb-3"><strong>Deviation:</strong> Difference between Actual and Standard. Positive values indicate delays.</p>
            <p className="mb-3"><strong>On-Time %:</strong> Percentage of shipments delivered within or before the standard time.</p>
            <p className="mb-3"><strong>Color Coding:</strong> Green (≥95% on-time), Yellow (90-95%), Red (&lt;90%). Use this to prioritize interventions.</p>
          </div>
        </div>
      </div>

      {/* Filters */}
      <ReportFilters filters={filters} onChange={setFilters} onReset={resetFilters} />

      {/* KPIs - Minimalist Design */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-3">
        <KPICard
          title="Total Samples"
          value={metrics.totalSamples.toLocaleString()}
          icon={Package}
          trend="neutral"
          trendValue="Statistical significance"
          color="blue"
          tooltip={{
            description: "Total number of shipments analyzed in the current filter selection.",
            interpretation: "Higher sample sizes provide more reliable statistical insights. Minimum 30 samples recommended per route for significance.",
            utility: "Validates the reliability of performance metrics. Low sample sizes may indicate incomplete data or narrow filters."
          }}
        />
        <KPICard
          title="Avg J+K Actual"
          value={`${metrics.avgJKActual.toFixed(1)} days`}
          icon={Clock}
          trend={metrics.avgJKActual <= metrics.avgJKStandard ? 'up' : 'down'}
          trendValue={`vs Std: ${metrics.avgJKStandard.toFixed(1)} days`}
          color={metrics.avgJKActual <= metrics.avgJKStandard ? 'green' : metrics.avgJKActual <= metrics.avgJKStandard + 1 ? 'amber' : 'red'}
          tooltip={{
            description: "Weighted average of actual transit times across all routes in the selection.",
            interpretation: "Compare against J+K Standard. Values below standard indicate early delivery, above standard indicate delays.",
            utility: "Primary metric for overall network performance. Use to track improvement over time."
          }}
        />
        <KPICard
          title="On-Time %"
          value={`${metrics.onTimePercentage.toFixed(1)}%`}
          icon={CheckCircle}
          trend={metrics.onTimePercentage >= 95 ? 'up' : metrics.onTimePercentage >= 90 ? 'neutral' : 'down'}
          trendValue={`${metrics.onTimeSamples.toLocaleString()} on-time`}
          color={metrics.onTimePercentage >= 95 ? 'green' : metrics.onTimePercentage >= 90 ? 'amber' : 'red'}
          tooltip={{
            description: "Percentage of shipments delivered within or before the standard delivery time.",
            interpretation: "≥95% is excellent, 90-95% is acceptable, <90% requires intervention.",
            utility: "Key performance indicator for service quality. Use to set performance targets and track compliance."
          }}
        />
        <KPICard
          title="Problem Routes"
          value={metrics.problematicRoutes.toString()}
          icon={AlertTriangle}
          trend={metrics.problematicRoutes === 0 ? 'up' : 'down'}
          trendValue="Require intervention"
          color={metrics.problematicRoutes === 0 ? 'green' : metrics.problematicRoutes <= 3 ? 'amber' : 'red'}
          tooltip={{
            description: "Number of routes with on-time performance below 90% (critical threshold).",
            interpretation: "Routes consistently failing to meet delivery standards. Require immediate investigation and corrective action.",
            utility: "Prioritization tool for operational improvements. Focus resources on these routes first."
          }}
        />
      </div>

      {/* Charts Section */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Weekly Samples Chart */}
        <div className="bg-white rounded-lg shadow p-6">
          <h3 className="text-lg font-semibold text-gray-900 mb-4">Weekly Sample Volume</h3>
          <div className="h-64 flex items-center justify-center text-gray-400">
            {weeklySamples.length > 0 ? (
              <div className="w-full">
                <div className="text-sm text-gray-600 mb-2">
                  {weeklySamples.length} weeks of data
                </div>
                <div className="text-xs text-gray-500">
                  Chart implementation pending
                </div>
              </div>
            ) : (
              <div>No weekly data available</div>
            )}
          </div>
        </div>

        {/* Performance Distribution */}
        <div className="bg-white rounded-lg shadow p-6">
          <h3 className="text-lg font-semibold text-gray-900 mb-4">Performance Distribution</h3>
          <div className="h-64 flex items-center justify-center text-gray-400">
            Chart implementation pending
          </div>
        </div>
      </div>

      {/* Tabs */}
      <div className="bg-white rounded-lg shadow">
        <div className="border-b border-gray-200">
          <nav className="flex -mb-px">
            {[
              { id: 'route', label: 'Route Analysis' },
              { id: 'city', label: 'City Analysis' },
              { id: 'region', label: 'Region Analysis' },
              { id: 'carrier', label: 'Carrier Analysis' },
              { id: 'product', label: 'Product Analysis' },
            ].map((tab) => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id as any)}
                className={`px-6 py-3 text-sm font-medium border-b-2 transition-colors ${
                  activeTab === tab.id
                    ? 'border-blue-500 text-blue-600'
                    : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
                }`}
              >
                {tab.label}
              </button>
            ))}
          </nav>
        </div>

        <div className="p-6">
          {activeTab === 'route' && (
            <div>
              <h3 className="text-lg font-semibold text-gray-900 mb-4">
                Route Performance ({routeData.length} routes)
              </h3>
              <div className="overflow-x-auto">
                <table className="min-w-full divide-y divide-gray-200">
                  <thead className="bg-gray-50">
                    <tr>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Route</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Samples</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">J+K Std</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">J+K Actual</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Deviation</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">On-Time %</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
                    </tr>
                  </thead>
                  <tbody className="bg-white divide-y divide-gray-200">
                    {routeData.slice(0, 20).map((route, idx) => {
                      const deviationColor = route.deviation <= 0 ? 'text-green-600' : route.deviation <= 1 ? 'text-yellow-600' : 'text-red-600';
                      const onTimeColor = route.onTimePercentage >= 95 ? 'text-green-600 font-semibold' : route.onTimePercentage >= 90 ? 'text-yellow-600' : 'text-red-600 font-semibold';
                      const statusColor = route.status === 'compliant' ? 'bg-green-500' : route.status === 'warning' ? 'bg-yellow-500' : 'bg-red-500';
                      
                      return (
                        <tr key={idx} className="hover:bg-gray-50">
                          <td className="px-3 py-2 text-sm text-gray-900">
                            {route.originCity} → {route.destinationCity}
                            <div className="text-xs text-gray-500">{route.carrier} · {route.product}</div>
                          </td>
                          <td className="px-3 py-2 text-sm text-gray-900">{route.totalSamples}</td>
                          <td className="px-3 py-2 text-sm text-gray-900">{route.jkStandard.toFixed(1)}</td>
                          <td className="px-3 py-2 text-sm text-gray-900">{route.jkActual.toFixed(1)}</td>
                          <td className={`px-3 py-2 text-sm ${deviationColor}`}>
                            {route.deviation > 0 ? '+' : ''}{route.deviation.toFixed(1)}
                          </td>
                          <td className={`px-3 py-2 text-sm ${onTimeColor}`}>
                            {route.onTimePercentage.toFixed(1)}%
                          </td>
                          <td className="px-3 py-2">
                            <div className={`w-3 h-3 rounded-full ${statusColor}`} />
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {activeTab === 'city' && (
            <div>
              <h3 className="text-lg font-semibold text-gray-900 mb-4">
                City Performance ({cityData.length} entries)
              </h3>
              <div className="overflow-x-auto">
                <table className="min-w-full divide-y divide-gray-200">
                  <thead className="bg-gray-50">
                    <tr>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">City</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Direction</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Region</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Samples</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">J+K Std</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">J+K Actual</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Deviation</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">On-Time %</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
                    </tr>
                  </thead>
                  <tbody className="bg-white divide-y divide-gray-200">
                    {cityData.map((city, idx) => {
                      const deviationColor = city.deviation <= 0 ? 'text-green-600' : city.deviation <= 1 ? 'text-yellow-600' : 'text-red-600';
                      const onTimeColor = city.onTimePercentage >= 95 ? 'text-green-600 font-semibold' : city.onTimePercentage >= 90 ? 'text-yellow-600' : 'text-red-600 font-semibold';
                      const statusColor = city.status === 'compliant' ? 'bg-green-500' : city.status === 'warning' ? 'bg-yellow-500' : 'bg-red-500';
                      const directionIcon = city.direction === 'inbound' ? '🔵 ↓' : '🟢 ↑';
                      
                      return (
                        <tr key={idx} className="hover:bg-gray-50">
                          <td className="px-3 py-2 text-sm text-gray-900">{city.cityName}</td>
                          <td className="px-3 py-2 text-sm">{directionIcon} {city.direction}</td>
                          <td className="px-3 py-2 text-sm text-gray-600">{city.regionName}</td>
                          <td className="px-3 py-2 text-sm text-gray-900">{city.totalSamples}</td>
                          <td className="px-3 py-2 text-sm text-gray-900">{city.jkStandard.toFixed(1)}</td>
                          <td className="px-3 py-2 text-sm text-gray-900">{city.jkActual.toFixed(1)}</td>
                          <td className={`px-3 py-2 text-sm ${deviationColor}`}>
                            {city.deviation > 0 ? '+' : ''}{city.deviation.toFixed(1)}
                          </td>
                          <td className={`px-3 py-2 text-sm ${onTimeColor}`}>
                            {city.onTimePercentage.toFixed(1)}%
                          </td>
                          <td className="px-3 py-2">
                            <div className={`w-3 h-3 rounded-full ${statusColor}`} />
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {activeTab === 'region' && (
            <div>
              <h3 className="text-lg font-semibold text-gray-900 mb-4">
                Region Performance ({regionData.length} entries)
              </h3>
              <div className="overflow-x-auto">
                <table className="min-w-full divide-y divide-gray-200">
                  <thead className="bg-gray-50">
                    <tr>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Region</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Direction</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Cities</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Samples</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">J+K Std</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">J+K Actual</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Deviation</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">On-Time %</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
                    </tr>
                  </thead>
                  <tbody className="bg-white divide-y divide-gray-200">
                    {regionData.map((region, idx) => {
                      const deviationColor = region.deviation <= 0 ? 'text-green-600' : region.deviation <= 1 ? 'text-yellow-600' : 'text-red-600';
                      const onTimeColor = region.onTimePercentage >= 95 ? 'text-green-600 font-semibold' : region.onTimePercentage >= 90 ? 'text-yellow-600' : 'text-red-600 font-semibold';
                      const statusColor = region.status === 'compliant' ? 'bg-green-500' : region.status === 'warning' ? 'bg-yellow-500' : 'bg-red-500';
                      const directionIcon = region.direction === 'inbound' ? '🔵 ↓' : '🟢 ↑';
                      
                      return (
                        <tr key={idx} className="hover:bg-gray-50">
                          <td className="px-3 py-2 text-sm text-gray-900">{region.regionName}</td>
                          <td className="px-3 py-2 text-sm">{directionIcon} {region.direction}</td>
                          <td className="px-3 py-2 text-sm text-gray-600">{region.cities}</td>
                          <td className="px-3 py-2 text-sm text-gray-900">{region.totalSamples}</td>
                          <td className="px-3 py-2 text-sm text-gray-900">{region.jkStandard.toFixed(1)}</td>
                          <td className="px-3 py-2 text-sm text-gray-900">{region.jkActual.toFixed(1)}</td>
                          <td className={`px-3 py-2 text-sm ${deviationColor}`}>
                            {region.deviation > 0 ? '+' : ''}{region.deviation.toFixed(1)}
                          </td>
                          <td className={`px-3 py-2 text-sm ${onTimeColor}`}>
                            {region.onTimePercentage.toFixed(1)}%
                          </td>
                          <td className="px-3 py-2">
                            <div className={`w-3 h-3 rounded-full ${statusColor}`} />
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {activeTab === 'carrier' && (
            <div>
              <h3 className="text-lg font-semibold text-gray-900 mb-4">
                Carrier Performance ({carrierData.length} carriers)
              </h3>
              <div className="overflow-x-auto">
                <table className="min-w-full divide-y divide-gray-200">
                  <thead className="bg-gray-50">
                    <tr>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Carrier</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Routes</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Samples</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">J+K Std</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">J+K Actual</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Deviation</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">On-Time %</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Problem Routes</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
                    </tr>
                  </thead>
                  <tbody className="bg-white divide-y divide-gray-200">
                    {carrierData.map((carrier, idx) => {
                      const deviationColor = carrier.deviation <= 0 ? 'text-green-600' : carrier.deviation <= 1 ? 'text-yellow-600' : 'text-red-600';
                      const onTimeColor = carrier.onTimePercentage >= 95 ? 'text-green-600 font-semibold' : carrier.onTimePercentage >= 90 ? 'text-yellow-600' : 'text-red-600 font-semibold';
                      const statusColor = carrier.status === 'compliant' ? 'bg-green-500' : carrier.status === 'warning' ? 'bg-yellow-500' : 'bg-red-500';
                      
                      return (
                        <tr key={idx} className="hover:bg-gray-50">
                          <td className="px-3 py-2 text-sm font-medium text-gray-900">{carrier.carrier}</td>
                          <td className="px-3 py-2 text-sm text-gray-600">{carrier.routes}</td>
                          <td className="px-3 py-2 text-sm text-gray-900">{carrier.totalSamples}</td>
                          <td className="px-3 py-2 text-sm text-gray-900">{carrier.jkStandard.toFixed(1)}</td>
                          <td className="px-3 py-2 text-sm text-gray-900">{carrier.jkActual.toFixed(1)}</td>
                          <td className={`px-3 py-2 text-sm ${deviationColor}`}>
                            {carrier.deviation > 0 ? '+' : ''}{carrier.deviation.toFixed(1)}
                          </td>
                          <td className={`px-3 py-2 text-sm ${onTimeColor}`}>
                            {carrier.onTimePercentage.toFixed(1)}%
                          </td>
                          <td className="px-3 py-2 text-sm text-red-600 font-semibold">
                            {carrier.problematicRoutes}
                          </td>
                          <td className="px-3 py-2">
                            <div className={`w-3 h-3 rounded-full ${statusColor}`} />
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {activeTab === 'product' && (
            <div>
              <h3 className="text-lg font-semibold text-gray-900 mb-4">
                Product Performance ({productData.length} products)
              </h3>
              <div className="overflow-x-auto">
                <table className="min-w-full divide-y divide-gray-200">
                  <thead className="bg-gray-50">
                    <tr>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Product</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Routes</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Samples</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">J+K Std</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">J+K Actual</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Deviation</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">On-Time %</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Problem Routes</th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
                    </tr>
                  </thead>
                  <tbody className="bg-white divide-y divide-gray-200">
                    {productData.map((product, idx) => {
                      const deviationColor = product.deviation <= 0 ? 'text-green-600' : product.deviation <= 1 ? 'text-yellow-600' : 'text-red-600';
                      const onTimeColor = product.onTimePercentage >= 95 ? 'text-green-600 font-semibold' : product.onTimePercentage >= 90 ? 'text-yellow-600' : 'text-red-600 font-semibold';
                      const statusColor = product.status === 'compliant' ? 'bg-green-500' : product.status === 'warning' ? 'bg-yellow-500' : 'bg-red-500';
                      
                      return (
                        <tr key={idx} className="hover:bg-gray-50">
                          <td className="px-3 py-2 text-sm font-medium text-gray-900">{product.product}</td>
                          <td className="px-3 py-2 text-sm text-gray-600">{product.routes}</td>
                          <td className="px-3 py-2 text-sm text-gray-900">{product.totalSamples}</td>
                          <td className="px-3 py-2 text-sm text-gray-900">{product.jkStandard.toFixed(1)}</td>
                          <td className="px-3 py-2 text-sm text-gray-900">{product.jkActual.toFixed(1)}</td>
                          <td className={`px-3 py-2 text-sm ${deviationColor}`}>
                            {product.deviation > 0 ? '+' : ''}{product.deviation.toFixed(1)}
                          </td>
                          <td className={`px-3 py-2 text-sm ${onTimeColor}`}>
                            {product.onTimePercentage.toFixed(1)}%
                          </td>
                          <td className="px-3 py-2 text-sm text-red-600 font-semibold">
                            {product.problematicRoutes}
                          </td>
                          <td className="px-3 py-2">
                            <div className={`w-3 h-3 rounded-full ${statusColor}`} />
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
