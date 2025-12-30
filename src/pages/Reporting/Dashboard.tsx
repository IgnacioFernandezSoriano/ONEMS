import React from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { useReportingFilters } from '@/contexts/ReportingFiltersContext';
import { useReportingGeneral } from '@/hooks/reporting/useReportingGeneral';
import { useCarrierProductOverview } from '@/hooks/reporting/useCarrierProductOverview';
import { useComplianceData } from '@/hooks/reporting/useComplianceData';
import { KPICard } from '@/components/reporting/KPICard';
import { ReportFilters } from '@/components/reporting/ReportFilters';
import DualLineChart from '@/components/reporting/DualLineChart';
import CarrierProductOverview from '@/components/reporting/CarrierProductOverview';
import { TrendingUp, Package, Clock, CheckCircle, Info } from 'lucide-react';
import { SmartTooltip } from '@/components/common/SmartTooltip';
export default function Dashboard() {
  const { profile } = useAuth();
  const accountId = profile?.account_id || undefined;
  const { filters, setFilters, resetFilters } = useReportingFilters();
  const { data, loading, error } = useReportingGeneral(accountId, {
    originCity: filters.originCity,
    destinationCity: filters.destinationCity,
    carrier: filters.carrier,
    product: filters.product,
    dateFrom: filters.startDate,
    dateTo: filters.endDate
  });

  const { data: carrierProductData, loading: carrierProductLoading, globalWarningThreshold: cpWarningThreshold, globalCriticalThreshold: cpCriticalThreshold } = useCarrierProductOverview(
    accountId,
    {
      dateFrom: filters.startDate,
      dateTo: filters.endDate,
      originCity: filters.originCity,
      destinationCity: filters.destinationCity,
      carrier: filters.carrier,
      product: filters.product
    }
  );

  // Get global thresholds from compliance data
  const { globalWarningThreshold, globalCriticalThreshold } = useComplianceData(accountId, {
    startDate: filters.startDate,
    endDate: filters.endDate,
  });

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-500">Loading performance data...</div>
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

  const latestData = data[0];
  
  // FIX: Calculate weighted average compliance (not simple average of weekly percentages)
  // This ensures weeks with more shipments have proportional weight
  const totalShipments = data.reduce((sum, d) => sum + d.totalShipments, 0);
  const totalCompliantShipments = data.reduce((sum, d) => {
    const compliantCount = Math.round((d.compliancePercentage / 100) * d.totalShipments);
    return sum + compliantCount;
  }, 0);
  const avgCompliance = totalShipments > 0
    ? (totalCompliantShipments / totalShipments) * 100
    : 0;
  
  // Calculate weighted average transit days
  const totalTransitDays = data.reduce((sum, d) => sum + (d.avgBusinessDays * d.totalShipments), 0);
  const avgTransitDays = totalShipments > 0
    ? totalTransitDays / totalShipments
    : 0;

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">General Performance Dashboard</h1>
          <p className="text-gray-600 mt-1">Overall compliance and transit time metrics</p>
        </div>
        <SmartTooltip content="General Performance Dashboard: Provides a high-level overview of delivery performance across your entire ecosystem. This is the starting point for regulatory analysis. You'll see overall compliance rates, average transit times, shipment volumes, and temporal trends. When no filters are applied, you'll also see a breakdown by carrier and product. Use this dashboard to quickly assess the overall health of the delivery network, identify underperforming carriers, and detect emerging compliance issues before they become systemic problems. Use filters to drill down into specific carriers, products, or routes, and navigate to other reports for detailed analysis." />
      </div>

      <ReportFilters filters={filters} onChange={setFilters} onReset={resetFilters} />

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <KPICard
          title="Overall Compliance"
          value={`${avgCompliance.toFixed(1)}%`}
          icon={CheckCircle}
          trend={avgCompliance >= globalWarningThreshold ? 'up' : 'down'}
          trendValue={`${avgCompliance >= globalWarningThreshold ? 'Above' : 'Below'} target`}
          color={avgCompliance >= globalWarningThreshold ? 'green' : avgCompliance > globalCriticalThreshold ? 'amber' : 'red'}
          tooltip={{
            description: "Percentage of shipments delivered within the legally mandated transit time for their route classification.",
            interpretation: "Values ≥95% indicate good compliance. Values <95% suggest systematic delays requiring investigation.",
            utility: "Identifies carriers or routes requiring regulatory intervention. Compliance below 95% may trigger audits or penalties."
          }}
        />
        <KPICard
          title="Avg Transit Days"
          value={avgTransitDays.toFixed(1)}
          icon={Clock}
          trend="neutral"
          trendValue="Business days"
          color="blue"
          tooltip={{
            description: "Average number of business days from shipment origin to final delivery across all routes.",
            interpretation: "Lower values indicate faster service. Compare against legal standards for each route type to assess performance.",
            utility: "Helps regulators evaluate if carriers are providing efficient service and meeting customer expectations beyond minimum compliance."
          }}
        />
        <KPICard
          title="Total Shipments"
          value={totalShipments.toString()}
          icon={Package}
          trend="up"
          trendValue="Last 12 weeks"
          color="purple"
          tooltip={{
            description: "Total number of shipments processed in the selected time period across all carriers and routes.",
            interpretation: "Higher volumes provide more statistically significant compliance data. Low volumes may indicate data gaps or market issues.",
            utility: "Assesses market activity and data completeness. Helps prioritize regulatory focus on high-volume carriers."
          }}
        />
        <KPICard
          title="Current Week"
          value={latestData ? `${latestData.compliancePercentage.toFixed(1)}%` : 'N/A'}
          icon={TrendingUp}
          trend={latestData && latestData.compliancePercentage >= globalWarningThreshold ? 'up' : 'down'}
          trendValue={latestData ? `${latestData.totalShipments} shipments` : 'No data'}
          color="indigo"
          tooltip={{
            description: "Compliance rate for the most recent week of data, showing current performance trends.",
            interpretation: "Sudden drops may indicate operational issues. Consistent low values suggest systemic problems requiring immediate action.",
            utility: "Enables early detection of emerging compliance issues before they become widespread problems."
          }}
        />
      </div>

      <div className="bg-white rounded-lg shadow p-6">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-semibold text-gray-900">Performance Trend</h2>
          <SmartTooltip content="Performance Trend Over Time: Dual-axis chart showing compliance percentage (green line) and average transit days (blue line) over the selected time period. Upward compliance trend indicates improving service quality. Downward transit days show faster deliveries. Look for correlations between both metrics. Use to identify seasonal patterns, detect performance degradation, and verify if improvement plans are working." />
        </div>
        <DualLineChart data={data} />
      </div>

      {!filters.carrier && !filters.product && (
        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-lg font-semibold text-gray-900">Carrier & Product Overview</h2>
            <SmartTooltip content="Ecosystem Overview Table: Summary showing performance for each carrier-product combination in your ecosystem. Sorted by worst on-time percentage first. Shows Routes (unique city pairs), Samples (total shipments), J+K Std (expected transit days), J+K Actual (real transit days), Deviation (difference), On-Time % (percentage delivered on time), Problem Routes (routes with <90% on-time), and Status (visual indicator). Use for quick identification of non-compliant carriers for investigation and to prioritize enforcement actions." />
          </div>
          <CarrierProductOverview 
            data={carrierProductData} 
            loading={carrierProductLoading}
            globalWarningThreshold={cpWarningThreshold}
            globalCriticalThreshold={cpCriticalThreshold}
          />
        </div>
      )}
    </div>
  );
}
