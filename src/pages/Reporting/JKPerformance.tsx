import React, { useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { useReportingFilters } from '@/contexts/ReportingFiltersContext';
import { useJKPerformance } from '@/hooks/reporting/useJKPerformance';
import { KPICard } from '@/components/reporting/KPICard';
import { ReportFilters } from '@/components/reporting/ReportFilters';
import { Package, Clock, CheckCircle, AlertTriangle, Info, FileDown } from 'lucide-react';
import { WeeklySamplesChart } from '@/components/reporting/WeeklySamplesChart';
import { PerformanceDistributionChart } from '@/components/reporting/PerformanceDistributionChart';
import { CumulativeDistributionTable } from '@/components/reporting/CumulativeDistributionTable';
import { CumulativeDistributionChart } from '@/components/reporting/CumulativeDistributionChart';
import { exportRouteCSV, exportCityCSV, exportRegionCSV, exportCarrierProductCSV, exportCumulativeCSV } from '@/utils/jkExportCSV';
import { ColumnTooltip } from '@/components/reporting/ColumnTooltip';
import { SmartTooltip } from '@/components/common/SmartTooltip';

export default function JKPerformance() {
  const { profile } = useAuth();
  const accountId = profile?.account_id || undefined;
  const { filters, setFilters, resetFilters } = useReportingFilters();
  const [activeTab, setActiveTab] = useState<'route' | 'city' | 'region' | 'carrier' | 'cumulative'>('route');
  const [cumulativeView, setCumulativeView] = useState<'table' | 'chart'>('chart');

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
        <SmartTooltip content="J+K Performance Report: Analyzes actual transit times (J+K Actual) against delivery standards (J+K Std) to identify routes, cities, carriers, or products with systematic delays. Multi-level analysis showing Route, City, Region, Carrier, and Product performance. J+K Standard is the expected delivery time in days from delivery_standards table. J+K Actual is the average actual transit time in business days. Deviation is the difference between Actual and Standard (positive values indicate delays). On-Time % is the percentage of shipments delivered within or before the standard time. Color coding: Green (≥95%), Yellow (90-95%), Red (<90%)." />
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
            description: "Percentage of shipments delivered within or before the standard delivery time (J+K Std).",
            interpretation: "Thresholds are dynamic and defined in delivery_standards table per route. Green (≥95%), Yellow (90-95%), Red (<90%) are visual guides only.",
            utility: "Key performance indicator for service quality. Compare against route-specific standard percentage (Std %) from delivery_standards."
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
            description: "Number of routes with on-time performance below 90%.",
            interpretation: "Routes failing to meet their delivery standards. Critical threshold (90%) is a general guide; actual standards vary per route in delivery_standards table.",
            utility: "Prioritization tool for operational improvements. Focus resources on these routes first."
          }}
        />
      </div>

      {/* Charts Section */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Weekly Samples Chart */}
        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center gap-2 mb-4">
            <h3 className="text-lg font-semibold text-gray-900">Weekly Sample Volume</h3>
            <SmartTooltip content="Weekly Sample Volume: Shows the number of shipments analyzed per week in the selected date range. Color coding: Green (20% above average), Blue (above average), Yellow (80-100% of average), Red (below 80% of average). Use to identify weeks with low sample sizes that may affect statistical reliability. Minimum 30 samples/week recommended for statistical significance." />
          </div>
          <WeeklySamplesChart data={weeklySamples} />
        </div>

        {/* Performance Distribution */}
        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center gap-2 mb-4">
            <h3 className="text-lg font-semibold text-gray-900">Performance Distribution</h3>
            <SmartTooltip content="Performance Distribution: Shows how shipments are distributed by actual transit time vs. delivery standard (J+K Std). Categories: After Standard (red, delivered AFTER J+K Std = late), Before/On-Time (green, delivered WITHIN J+K Std = on-time), On Standard (blue, delivered EXACTLY on J+K Std day). Use to visualize overall network performance. Large red bars indicate systematic delays requiring investigation." />
          </div>
          <PerformanceDistributionChart routeData={routeData} maxDays={maxDays} />
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
              { id: 'carrier', label: 'Carrier → Product' },
              { id: 'cumulative', label: 'Cumulative Distribution' },
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
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-lg font-semibold text-gray-900">
                  Route Performance ({routeData.length} routes)
                </h3>
                <button
                  onClick={() => exportRouteCSV(routeData)}
                  className="flex items-center gap-2 px-3 py-1.5 text-sm bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors"
                >
                  <FileDown className="w-4 h-4" />
                  Export CSV
                </button>
              </div>
              <div className="overflow-x-auto">
                <table className="min-w-full divide-y divide-gray-200">
                  <thead className="bg-gray-50">
                    <tr>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">
                          Route
                          <ColumnTooltip content="Origin city → Destination city. Each route is unique by carrier, product, and city pair." />
                        </div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">
                          Samples
                          <ColumnTooltip content="Total number of shipments for this route in the selected date range. Minimum 30 samples recommended for statistical significance." />
                        </div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">
                          J+K Std
                          <ColumnTooltip content="Expected delivery time in days from delivery_standards table. Automatically converted from hours if needed (hours/24)." />
                        </div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">
                          J+K Actual
                          <ColumnTooltip content="Average actual transit time in business days for all shipments on this route. Calculated from shipments.business_transit_days field." />
                        </div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">
                          Deviation
                          <ColumnTooltip content="Difference between J+K Actual and J+K Std (Actual - Standard). Positive values indicate delays, negative values indicate early delivery." />
                        </div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">
                          On-Time %
                          <ColumnTooltip content="Percentage of shipments delivered within or before J+K Std. Compare against route-specific Std % from delivery_standards (not shown in this table)." />
                        </div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">
                          Status
                          <ColumnTooltip content="Visual indicator: Green (compliant, ≥95%), Yellow (warning, 90-95%), Red (critical, <90%). These are general guides; actual standards are route-specific." />
                        </div>
                      </th>
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
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-lg font-semibold text-gray-900">
                  City Performance ({cityData.length} entries)
                </h3>
                <button
                  onClick={() => exportCityCSV(cityData)}
                  className="flex items-center gap-2 px-3 py-1.5 text-sm bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors"
                >
                  <FileDown className="w-4 h-4" />
                  Export CSV
                </button>
              </div>
              <div className="overflow-x-auto">
                <table className="min-w-full divide-y divide-gray-200">
                  <thead className="bg-gray-50">
                    <tr>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">City <ColumnTooltip content="City name aggregating all routes where this city is origin or destination." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Direction <ColumnTooltip content="Inbound (city is destination) or Outbound (city is origin). Shows traffic flow direction." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Region <ColumnTooltip content="Geographic region to which this city belongs (from topology.regions table)." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Samples <ColumnTooltip content="Total shipments aggregated across all routes involving this city in the specified direction." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">J+K Std <ColumnTooltip content="Weighted average of J+K standards across all routes involving this city. Routes with more shipments have higher weight." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">J+K Actual <ColumnTooltip content="Weighted average of actual transit times across all routes involving this city." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Deviation <ColumnTooltip content="Weighted average deviation (Actual - Standard) across all routes involving this city." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">On-Time % <ColumnTooltip content="Percentage of all shipments (across all routes) delivered on-time for this city." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Status <ColumnTooltip content="Visual indicator based on on-time percentage: Green (≥95%), Yellow (90-95%), Red (<90%)." /></div>
                      </th>
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
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-lg font-semibold text-gray-900">
                  Region Performance ({regionData.length} entries)
                </h3>
                <button
                  onClick={() => exportRegionCSV(regionData)}
                  className="flex items-center gap-2 px-3 py-1.5 text-sm bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors"
                >
                  <FileDown className="w-4 h-4" />
                  Export CSV
                </button>
              </div>
              <div className="overflow-x-auto">
                <table className="min-w-full divide-y divide-gray-200">
                  <thead className="bg-gray-50">
                    <tr>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Region <ColumnTooltip content="Geographic region aggregating all cities and routes within it (from topology.regions table)." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Direction <ColumnTooltip content="Inbound (region is destination) or Outbound (region is origin). Shows regional traffic flow." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Cities <ColumnTooltip content="Number of unique cities in this region with shipment data in the specified direction." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Samples <ColumnTooltip content="Total shipments aggregated across all routes involving cities in this region." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">J+K Std <ColumnTooltip content="Weighted average of J+K standards across all routes in this region. Routes with more shipments have higher weight." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">J+K Actual <ColumnTooltip content="Weighted average of actual transit times across all routes in this region." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Deviation <ColumnTooltip content="Weighted average deviation (Actual - Standard) across all routes in this region." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">On-Time % <ColumnTooltip content="Percentage of all shipments (across all routes) delivered on-time in this region." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Status <ColumnTooltip content="Visual indicator based on on-time percentage: Green (≥95%), Yellow (90-95%), Red (<90%)." /></div>
                      </th>
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
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-lg font-semibold text-gray-900">
                  Carrier → Product Performance ({carrierData.length} carriers)
                </h3>
                <button
                  onClick={() => exportCarrierProductCSV(carrierData)}
                  className="flex items-center gap-2 px-3 py-1.5 text-sm bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors"
                >
                  <FileDown className="w-4 h-4" />
                  Export CSV
                </button>
              </div>
              <div className="overflow-x-auto">
                <table className="min-w-full divide-y divide-gray-200">
                  <thead className="bg-gray-50">
                    <tr>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Carrier / Product <ColumnTooltip content="Hierarchical view: Carrier rows (blue background) show aggregated metrics. Product rows (indented with ↳) show metrics for each product under that carrier." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Routes <ColumnTooltip content="Number of unique routes (city pairs) served by this carrier or product." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Samples <ColumnTooltip content="Total shipments for this carrier or product across all routes." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">J+K Std <ColumnTooltip content="Weighted average of J+K standards across all routes for this carrier or product." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">J+K Actual <ColumnTooltip content="Weighted average of actual transit times across all routes for this carrier or product." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Deviation <ColumnTooltip content="Weighted average deviation (Actual - Standard) across all routes for this carrier or product." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">On-Time % <ColumnTooltip content="Percentage of all shipments delivered on-time for this carrier or product." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Problem Routes <ColumnTooltip content="Number of routes with on-time performance <90%. Only shown at carrier level (products show '-')." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Status <ColumnTooltip content="Visual indicator: Green (≥95%), Yellow (90-95%), Red (<90%). Shown for both carriers and products." /></div>
                      </th>
                    </tr>
                  </thead>
                  <tbody className="bg-white divide-y divide-gray-200">
                    {carrierData.map((carrier, carrierIdx) => {
                      const carrierDeviationColor = carrier.deviation <= 0 ? 'text-green-600' : carrier.deviation <= 1 ? 'text-yellow-600' : 'text-red-600';
                      const carrierOnTimeColor = carrier.onTimePercentage >= 95 ? 'text-green-600 font-semibold' : carrier.onTimePercentage >= 90 ? 'text-yellow-600' : 'text-red-600 font-semibold';
                      const carrierStatusColor = carrier.status === 'compliant' ? 'bg-green-500' : carrier.status === 'warning' ? 'bg-yellow-500' : 'bg-red-500';
                      
                      return (
                        <React.Fragment key={carrierIdx}>
                          {/* Carrier Row */}
                          <tr className="bg-blue-50 hover:bg-blue-100">
                            <td className="px-3 py-2 text-sm font-bold text-gray-900">{carrier.carrier}</td>
                            <td className="px-3 py-2 text-sm font-semibold text-gray-700">{carrier.routes}</td>
                            <td className="px-3 py-2 text-sm font-semibold text-gray-900">{carrier.totalSamples}</td>
                            <td className="px-3 py-2 text-sm font-semibold text-gray-900">{carrier.jkStandard.toFixed(1)}</td>
                            <td className="px-3 py-2 text-sm font-semibold text-gray-900">{carrier.jkActual.toFixed(1)}</td>
                            <td className={`px-3 py-2 text-sm font-semibold ${carrierDeviationColor}`}>
                              {carrier.deviation > 0 ? '+' : ''}{carrier.deviation.toFixed(1)}
                            </td>
                            <td className={`px-3 py-2 text-sm ${carrierOnTimeColor}`}>
                              {carrier.onTimePercentage.toFixed(1)}%
                            </td>
                            <td className="px-3 py-2 text-sm text-red-600 font-semibold">
                              {carrier.problematicRoutes}
                            </td>
                            <td className="px-3 py-2">
                              <div className={`w-3 h-3 rounded-full ${carrierStatusColor}`} />
                            </td>
                          </tr>
                          {/* Product Rows */}
                          {carrier.products.map((product, productIdx) => {
                            const productDeviationColor = product.deviation <= 0 ? 'text-green-600' : product.deviation <= 1 ? 'text-yellow-600' : 'text-red-600';
                            const productOnTimeColor = product.onTimePercentage >= 95 ? 'text-green-600 font-semibold' : product.onTimePercentage >= 90 ? 'text-yellow-600' : 'text-red-600 font-semibold';
                            const productStatusColor = product.status === 'compliant' ? 'bg-green-500' : product.status === 'warning' ? 'bg-yellow-500' : 'bg-red-500';
                            
                            return (
                              <tr key={`${carrierIdx}-${productIdx}`} className="hover:bg-gray-50">
                                <td className="px-3 py-2 pl-8 text-sm text-gray-700">↳ {product.product}</td>
                                <td className="px-3 py-2 text-sm text-gray-600">{product.routes}</td>
                                <td className="px-3 py-2 text-sm text-gray-900">{product.totalSamples}</td>
                                <td className="px-3 py-2 text-sm text-gray-900">{product.jkStandard.toFixed(1)}</td>
                                <td className="px-3 py-2 text-sm text-gray-900">{product.jkActual.toFixed(1)}</td>
                                <td className={`px-3 py-2 text-sm ${productDeviationColor}`}>
                                  {product.deviation > 0 ? '+' : ''}{product.deviation.toFixed(1)}
                                </td>
                                <td className={`px-3 py-2 text-sm ${productOnTimeColor}`}>
                                  {product.onTimePercentage.toFixed(1)}%
                                </td>
                                <td className="px-3 py-2 text-sm text-gray-400">-</td>
                                <td className="px-3 py-2">
                                  <div className={`w-3 h-3 rounded-full ${productStatusColor}`} />
                                </td>
                              </tr>
                            );
                          })}
                        </React.Fragment>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {activeTab === 'cumulative' && (
            <div>
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-lg font-semibold text-gray-900">
                  Cumulative Distribution Analysis
                </h3>
                <div className="flex gap-2">
                  {cumulativeView === 'table' && (
                    <button
                      onClick={() => exportCumulativeCSV(routeData.map(route => ({
                        routeKey: route.routeKey,
                        originCity: route.originCity,
                        destinationCity: route.destinationCity,
                        carrier: route.carrier,
                        product: route.product,
                        jkStandard: route.jkStandard,
                        standardPercentage: route.standardPercentage,
                        distribution: route.distribution,
                        totalSamples: route.totalSamples,
                      })), maxDays)}
                      className="flex items-center gap-2 px-3 py-1.5 text-sm bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors"
                    >
                      <FileDown className="w-4 h-4" />
                      Export CSV
                    </button>
                  )}
                  <button
                    onClick={() => setCumulativeView('chart')}
                    className={`px-4 py-2 text-sm font-medium rounded-lg transition-colors ${
                      cumulativeView === 'chart'
                        ? 'bg-blue-600 text-white'
                        : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                    }`}
                  >
                    Chart View
                  </button>
                  <button
                    onClick={() => setCumulativeView('table')}
                    className={`px-4 py-2 text-sm font-medium rounded-lg transition-colors ${
                      cumulativeView === 'table'
                        ? 'bg-blue-600 text-white'
                        : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                    }`}
                  >
                    Table View
                  </button>
                </div>
              </div>

              {cumulativeView === 'chart' ? (
                <CumulativeDistributionChart
                  routes={routeData.map(route => ({
                    routeKey: route.routeKey,
                    originCity: route.originCity,
                    destinationCity: route.destinationCity,
                    carrier: route.carrier,
                    product: route.product,
                    jkStandard: route.jkStandard,
                    standardPercentage: route.standardPercentage,
                    distribution: route.distribution,
                    totalSamples: route.totalSamples,
                  }))}
                  maxDays={maxDays}
                />
              ) : (
                <CumulativeDistributionTable
                  routes={routeData.map(route => ({
                    routeKey: route.routeKey,
                    originCity: route.originCity,
                    destinationCity: route.destinationCity,
                    carrier: route.carrier,
                    product: route.product,
                    jkStandard: route.jkStandard,
                    standardPercentage: route.standardPercentage,
                    distribution: route.distribution,
                    totalSamples: route.totalSamples,
                  }))}
                  maxDays={maxDays}
                />
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
