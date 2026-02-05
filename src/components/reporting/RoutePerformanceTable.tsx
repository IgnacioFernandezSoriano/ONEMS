import { FileDown } from 'lucide-react';
import { ColumnTooltip } from './ColumnTooltip';
import { exportRouteCSV } from '@/utils/jkExportCSV';

interface JKRouteData {
  originCity: string;
  destinationCity: string;
  carrier: string;
  product: string;
  totalSamples: number;
  jkStandard: number;
  jkActual: number;
  onTimeSamples: number;
  beforeStandardSamples: number;
  afterStandardSamples: number;
  onTimePercentage: number;
  deviation: number;
  standardPercentage: number;
  status: 'compliant' | 'warning' | 'critical';
  routeKey: string;
  distribution: Map<number, number>;
  warningThreshold: number;
  criticalThreshold: number;
}

interface RoutePerformanceTableProps {
  routeData: JKRouteData[];
}

export function RoutePerformanceTable({ routeData }: RoutePerformanceTableProps) {
  if (!routeData || routeData.length === 0) {
    return (
      <div className="text-center py-8 text-gray-400">
        No route data available
      </div>
    );
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-semibold text-gray-900">
          Route performance ({routeData.length} routes)
        </h3>
        <button
          onClick={() => exportRouteCSV(routeData)}
          className="flex items-center gap-2 px-3 py-1.5 text-sm bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors"
        >
          <FileDown className="w-4 h-4" />
          Export CSV
        </button>
      </div>
      <div className="max-h-96 overflow-y-auto">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50 sticky top-0 z-20">
            <tr>
              <th className="sticky left-0 z-30 bg-gray-50 px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase border-r border-gray-200">
                <div className="flex items-center gap-1">
                  Route
                  <ColumnTooltip content="Origin city → Destination city. Each route is unique by carrier, product, and city pair." />
                </div>
              </th>
              <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                <div className="flex items-center gap-1">
                  Samples
                  <ColumnTooltip content="Total number of samples for this route in the selected date range." />
                </div>
              </th>
              <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                <div className="flex items-center gap-1">
                  J+K Std
                  <ColumnTooltip content="Expected delivery time in days from delivery_standards table." />
                </div>
              </th>
              <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                <div className="flex items-center gap-1">
                  J+K Actual
                  <ColumnTooltip content="Number of days required to reach the STD % target for this route." />
                </div>
              </th>
              <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                <div className="flex items-center gap-1">
                  Deviation
                  <ColumnTooltip content="Difference between J+K Actual and J+K Std (Actual - Standard)." />
                </div>
              </th>
              <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                <div className="flex items-center gap-1">
                  STD %
                  <ColumnTooltip content="Target on-time percentage defined in delivery_standards for this route." />
                </div>
              </th>
              <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                <div className="flex items-center gap-1">
                  On-Time %
                  <ColumnTooltip content="Percentage of samples delivered within or before J+K Std." />
                </div>
              </th>
              <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                <div className="flex items-center gap-1">
                  Status
                  <ColumnTooltip content="Visual indicator: Green (compliant), Yellow (warning), Red (critical)." />
                </div>
              </th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {[...routeData]
              .sort((a, b) => {
                // Sort problematic routes first
                const aProblematic = a.onTimePercentage <= a.criticalThreshold;
                const bProblematic = b.onTimePercentage <= b.criticalThreshold;
                if (aProblematic && !bProblematic) return -1;
                if (!aProblematic && bProblematic) return 1;
                // Then sort by On-Time % ascending
                return a.onTimePercentage - b.onTimePercentage;
              })
              .map((route, idx) => {
                const deviationColor = route.deviation <= 0 ? 'text-green-600' : route.deviation < 1 ? 'text-yellow-600' : 'text-red-600';
                const onTimeColor = route.onTimePercentage >= route.warningThreshold ? 'text-green-600 font-semibold' : route.onTimePercentage > route.criticalThreshold ? 'text-yellow-600' : 'text-red-600 font-semibold';
                const statusColor = route.status === 'compliant' ? 'bg-green-500' : route.status === 'warning' ? 'bg-yellow-500' : 'bg-red-500';
                
                return (
                  <tr key={idx} className="hover:bg-gray-50">
                    <td className="sticky left-0 z-10 bg-white px-3 py-2 text-sm text-gray-900 border-r border-gray-200">
                      {route.originCity} → {route.destinationCity}
                      <div className="text-xs text-gray-500">{route.carrier} · {route.product}</div>
                    </td>
                    <td className="px-3 py-2 text-sm text-gray-900">{route.totalSamples}</td>
                    <td className="px-3 py-2 text-sm text-gray-900">{route.jkStandard.toFixed(1)}</td>
                    <td className="px-3 py-2 text-sm text-gray-900">{route.jkActual.toFixed(1)}</td>
                    <td className={`px-3 py-2 text-sm ${deviationColor}`}>
                      {route.deviation > 0 ? '+' : ''}{route.deviation.toFixed(1)}
                    </td>
                    <td className="px-3 py-2 text-sm text-gray-900 font-medium">
                      {route.standardPercentage.toFixed(0)}%
                    </td>
                    <td className={`px-3 py-2 text-sm ${onTimeColor}`}>
                      {route.onTimePercentage.toFixed(1)}%
                    </td>
                    <td className="px-3 py-2 text-sm">
                      <div className={`w-3 h-3 rounded-full ${statusColor}`} />
                    </td>
                  </tr>
                );
              })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
