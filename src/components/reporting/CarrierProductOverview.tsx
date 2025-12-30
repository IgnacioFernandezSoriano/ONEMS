import React from 'react';
import { ColumnTooltip } from './ColumnTooltip';

interface CarrierProductData {
  carrier: string;
  product: string;
  routes: number;
  totalSamples: number;
  jkStandard: number;
  jkActual: number;
  deviation: number;
  onTimePercentage: number;
  problematicRoutes: number;
  status: 'compliant' | 'warning' | 'critical';
}

interface CarrierProductOverviewProps {
  data: CarrierProductData[];
  loading: boolean;
  globalWarningThreshold: number;
  globalCriticalThreshold: number;
}

export default function CarrierProductOverview({ data, loading, globalWarningThreshold, globalCriticalThreshold }: CarrierProductOverviewProps) {
  if (loading) {
    return (
      <div className="text-center text-gray-500 py-8">Loading...</div>
    );
  }

  if (data.length === 0) {
    return (
      <div className="text-center text-gray-500 py-8">No data available</div>
    );
  }

  // Sort by compliance (worst first) to highlight problems
  const sortedData = [...data].sort((a, b) => a.onTimePercentage - b.onTimePercentage);

  return (
    <div className="overflow-x-auto">
      <table className="min-w-full divide-y divide-gray-200">
        <thead className="bg-gray-50">
          <tr>
            <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
              <div className="flex items-center gap-1">Carrier / Product <ColumnTooltip content="Carrier and product combination for delivery service." /></div>
            </th>
            <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
              <div className="flex items-center gap-1">Routes <ColumnTooltip content="Number of unique routes (city pairs) served by this carrier-product combination." /></div>
            </th>
            <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
              <div className="flex items-center gap-1">Samples <ColumnTooltip content="Total shipments for this carrier-product combination across all routes." /></div>
            </th>
            <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
              <div className="flex items-center gap-1">J+K Std <ColumnTooltip content="Weighted average of J+K standards across all routes for this carrier-product combination." /></div>
            </th>
            <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
              <div className="flex items-center gap-1">J+K Actual <ColumnTooltip content="Weighted average of actual transit times across all routes for this carrier-product combination." /></div>
            </th>
            <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
              <div className="flex items-center gap-1">Deviation <ColumnTooltip content="Weighted average deviation (Actual - Standard) across all routes for this carrier-product combination." /></div>
            </th>
            <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
              <div className="flex items-center gap-1">On-Time % <ColumnTooltip content="Percentage of all shipments delivered on-time for this carrier-product combination." /></div>
            </th>
            <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
              <div className="flex items-center gap-1">Problem Routes <ColumnTooltip content="Number of routes with on-time performance <90%." /></div>
            </th>
            <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
              <div className="flex items-center gap-1">Status <ColumnTooltip content="Visual indicator: Green (≥95%), Yellow (90-95%), Red (<90%)." /></div>
            </th>
          </tr>
        </thead>
        <tbody className="bg-white divide-y divide-gray-200">
          {sortedData.map((item, index) => {
            const deviationColor = item.deviation <= 0 ? 'text-green-600' : item.deviation <= 1 ? 'text-yellow-600' : 'text-red-600';
            const onTimeColor = item.onTimePercentage >= globalWarningThreshold ? 'text-green-600 font-semibold' : item.onTimePercentage > globalCriticalThreshold ? 'text-yellow-600' : 'text-red-600 font-semibold';
            const statusColor = item.status === 'compliant' ? 'bg-green-500' : item.status === 'warning' ? 'bg-yellow-500' : 'bg-red-500';
            
            return (
              <tr key={`${item.carrier}-${item.product}-${index}`} className="hover:bg-gray-50">
                <td className="px-3 py-2 text-sm text-gray-900">
                  <div className="font-medium">{item.carrier}</div>
                  <div className="text-xs text-gray-500">↳ {item.product}</div>
                </td>
                <td className="px-3 py-2 text-sm text-gray-700">{item.routes}</td>
                <td className="px-3 py-2 text-sm text-gray-900">{item.totalSamples}</td>
                <td className="px-3 py-2 text-sm text-gray-900">{item.jkStandard.toFixed(1)}</td>
                <td className="px-3 py-2 text-sm text-gray-900">{item.jkActual.toFixed(1)}</td>
                <td className={`px-3 py-2 text-sm ${deviationColor}`}>
                  {item.deviation > 0 ? '+' : ''}{item.deviation.toFixed(1)}
                </td>
                <td className={`px-3 py-2 text-sm ${onTimeColor}`}>
                  {item.onTimePercentage.toFixed(1)}%
                </td>
                <td className="px-3 py-2 text-sm text-red-600 font-semibold">
                  {item.problematicRoutes}
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
  );
}
