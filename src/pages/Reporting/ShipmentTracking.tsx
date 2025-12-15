import React, { useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { useReportingFilters } from '@/contexts/ReportingFiltersContext';
import { ReportFilters } from '@/components/reporting/ReportFilters';
import { useShipmentTracking } from '@/hooks/reporting/useShipmentTracking';
import { KPICard } from '@/components/reporting/KPICard';
import { TimelineChart } from '@/components/reporting/TimelineChart';
import { ShipmentsTable } from '@/components/reporting/ShipmentsTable';
import { Package, Clock, CheckCircle, TrendingDown, Info } from 'lucide-react';

export default function ShipmentTracking() {
  const { profile } = useAuth();
  const accountId = profile?.account_id || undefined;
  const { filters, setFilters, resetFilters } = useReportingFilters();
  const [tagIdFilter, setTagIdFilter] = useState('');
  const { data, loading, error } = useShipmentTracking(accountId, tagIdFilter || undefined);

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-500">Loading shipment tracking data...</div>
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

  const totalShipments = data.length;
  const onTimeShipments = data.filter(s => s.onTimeDelivery).length;
  const delayedShipments = data.filter(s => !s.onTimeDelivery).length;
  const avgTransitDays = data.length > 0
    ? data.reduce((sum, s) => sum + s.businessTransitDays, 0) / data.length
    : 0;
  const onTimePercentage = totalShipments > 0 ? (onTimeShipments / totalShipments) * 100 : 0;

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Individual Shipment Tracking</h1>
          <p className="text-gray-600 mt-1">Detailed tracking and performance analysis for individual shipments</p>
        </div>
        <div className="group relative">
          <div className="flex items-center gap-2 px-4 py-2 bg-blue-50 border border-blue-200 rounded-lg cursor-help">
            <Info className="w-5 h-5 text-blue-600" />
            <span className="text-sm font-medium text-blue-900">About this Report</span>
          </div>
          <div className="invisible group-hover:visible absolute z-10 w-96 p-4 bg-white border border-gray-200 rounded-lg shadow-xl text-sm text-gray-700 right-0 top-12">
            <div className="absolute -top-1 right-8 w-2 h-2 bg-white border-l border-t border-gray-200 transform rotate-45"></div>
            <h3 className="font-bold text-gray-900 mb-3">Individual Shipment Tracking</h3>
            <p className="mb-3"><strong>Purpose:</strong> Provides granular tracking of individual shipments for detailed investigation. Essential for responding to customer complaints, verifying specific delivery claims, and building evidence for enforcement cases.</p>
            <p className="mb-3"><strong>What you'll see:</strong> Complete shipment-level data including TAG IDs, routes, carriers, dates, transit times, and compliance status. Filter by TAG ID to investigate specific shipments or use date/route filters for pattern analysis.</p>
            <p className="mb-3"><strong>Regulatory Objective:</strong> Enable investigation of individual customer complaints with full audit trail. Verify carrier claims about specific deliveries. Build case files for enforcement proceedings with shipment-level evidence. Export data for legal proceedings or customer compensation claims.</p>
            <p className="text-xs text-gray-500"><strong>Export:</strong> Use the CSV export button to download filtered data for external analysis or evidence submission.</p>
          </div>
        </div>
      </div>

      <ReportFilters filters={filters} onChange={setFilters} onReset={resetFilters} />

      <div className="bg-white rounded-lg shadow p-4">
        <label className="block text-sm font-medium text-gray-700 mb-2">
          Filter by TAG ID (optional)
        </label>
        <input
          type="text"
          placeholder="Enter TAG ID to filter..."
          value={tagIdFilter}
          onChange={(e) => setTagIdFilter(e.target.value)}
          className="w-full max-w-md px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
        />
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <KPICard
          title="Total Shipments"
          value={totalShipments.toString()}
          icon={Package}
          trend="neutral"
          trendValue="Tracked"
          color="blue"
          tooltip={{
            description: "Number of individual shipments being tracked in the current filter selection.",
            interpretation: "Use TAG ID filter to drill down to specific shipments. Higher volumes provide better pattern analysis.",
            utility: "Enables investigation of specific customer complaints or systematic issues affecting particular routes or time periods."
          }}
        />
        <KPICard
          title="On-Time Delivery"
          value={`${onTimePercentage.toFixed(1)}%`}
          icon={CheckCircle}
          trend={onTimePercentage >= 95 ? 'up' : 'down'}
          trendValue={`${onTimeShipments} shipments`}
          color={onTimePercentage >= 95 ? 'green' : 'red'}
          tooltip={{
            description: "Percentage of tracked shipments delivered within the legal transit time limit for their route.",
            interpretation: "Each shipment is compared against its specific route's allowed days. Below 95% indicates compliance failure.",
            utility: "Provides evidence for enforcement actions. Individual shipment data supports customer compensation claims."
          }}
        />
        <KPICard
          title="Delayed Shipments"
          value={delayedShipments.toString()}
          icon={TrendingDown}
          trend={delayedShipments > 0 ? 'down' : 'neutral'}
          trendValue="Require attention"
          color={delayedShipments > 0 ? 'red' : 'gray'}
          tooltip={{
            description: "Count of shipments that exceeded their allowed transit time, constituting regulatory violations.",
            interpretation: "Each delayed shipment represents a potential customer complaint and regulatory breach.",
            utility: "Identifies specific cases for investigation, customer remediation, and potential fine calculation."
          }}
        />
        <KPICard
          title="Avg Transit Time"
          value={`${avgTransitDays.toFixed(1)} days`}
          icon={Clock}
          trend="neutral"
          trendValue="Business days"
          color="purple"
          tooltip={{
            description: "Mean transit time across all tracked shipments, measured in business days.",
            interpretation: "Compare against route-specific limits. Averages near the limit suggest operational inefficiency.",
            utility: "Assesses service quality beyond binary compliance. Helps identify carriers operating at minimum acceptable levels."
          }}
        />
      </div>

      <div className="bg-white rounded-lg shadow p-6">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-semibold text-gray-900">Transit Time Comparison</h2>
          <div className="group relative">
            <Info className="w-5 h-5 text-gray-400 hover:text-blue-600 cursor-help" />
            <div className="invisible group-hover:visible absolute z-10 w-80 p-4 bg-white border border-gray-200 rounded-lg shadow-lg text-sm text-gray-700 right-0 top-8">
              <div className="absolute -top-1 right-4 w-2 h-2 bg-white border-l border-t border-gray-200 transform rotate-45"></div>
              <p className="font-semibold mb-2">Transit Time Comparison Chart</p>
              <p className="mb-2"><strong>Description:</strong> Visual comparison of actual transit days (blue bars) versus maximum allowed days (gray reference line) for each shipment. Bars exceeding the line indicate delayed shipments.</p>
              <p className="mb-2"><strong>Interpretation:</strong> Clusters of bars near or above the limit indicate systematic delays. Isolated tall bars represent individual problem shipments requiring investigation.</p>
              <p><strong>Regulatory Use:</strong> Visual evidence of compliance patterns. Identify if delays are systematic (requiring carrier intervention) or sporadic (individual case investigation). Use in enforcement presentations to demonstrate non-compliance trends.</p>
            </div>
          </div>
        </div>
        <TimelineChart data={data} />
      </div>

      <div className="bg-white rounded-lg shadow p-6">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-semibold text-gray-900">Shipment Details</h2>
          <div className="group relative">
            <Info className="w-5 h-5 text-gray-400 hover:text-blue-600 cursor-help" />
            <div className="invisible group-hover:visible absolute z-10 w-80 p-4 bg-white border border-gray-200 rounded-lg shadow-lg text-sm text-gray-700 right-0 top-8">
              <div className="absolute -top-1 right-4 w-2 h-2 bg-white border-l border-t border-gray-200 transform rotate-45"></div>
              <p className="font-semibold mb-2">Shipment Details Table</p>
              <p className="mb-2"><strong>Description:</strong> Complete list of individual shipments with TAG IDs, routes, carriers, dates, transit times, and compliance status. Searchable and exportable for detailed analysis.</p>
              <p className="mb-2"><strong>Interpretation:</strong> Use search to find specific TAG IDs for customer complaint investigation. Sort by status to group delayed shipments. Export filtered data for external analysis or legal proceedings.</p>
              <p><strong>Regulatory Use:</strong> Primary evidence source for enforcement cases. Provides audit trail for customer compensation claims. Export to CSV for submission to legal teams or regulatory authorities. Search by TAG ID to respond to specific complaints with complete delivery history.</p>
            </div>
          </div>
        </div>
        <ShipmentsTable data={data} />
      </div>
    </div>
  );
}
