import React, { useMemo } from 'react';
import { ColumnTooltip } from './ColumnTooltip';
import { formatNumber } from '@/lib/formatNumber';

interface RouteDistribution {
  routeKey: string;
  originCity: string;
  destinationCity: string;
  carrier: string;
  product: string;
  jkStandard: number;
  standardPercentage: number; // target percentage (e.g., 85%)
  distribution: Map<number, number>; // day -> count
  totalSamples: number;
}

interface CumulativeDistributionTableProps {
  routes: RouteDistribution[];
  maxDays: number;
}

export function CumulativeDistributionTable({ routes, maxDays }: CumulativeDistributionTableProps) {
  const { tableData, dayColumns } = useMemo(() => {
    if (!routes || routes.length === 0) {
      return { tableData: [], dayColumns: [] };
    }

    // Generate day columns (0 to maxDays, limited to 20 for display)
    const maxDisplayDays = Math.min(maxDays, 20);
    
    // Find the maximum day needed to reach 100% across all routes
    let maxNeededDay = 0;
    routes.forEach(route => {
      let cumulative = 0;
      for (let day = 0; day <= maxDisplayDays; day++) {
        cumulative += route.distribution.get(day) || 0;
        const percentage = route.totalSamples > 0 ? (cumulative / route.totalSamples) * 100 : 0;
        if (percentage >= 99.9) {
          maxNeededDay = Math.max(maxNeededDay, day);
          break;
        }
      }
    });
    
    const days = Array.from({ length: Math.min(maxNeededDay + 1, maxDisplayDays) }, (_, i) => i);

    // Calculate cumulative percentages for each route
    const data = routes.map(route => {
      const cumulativePercentages: { [day: number]: number } = {};
      let cumulativeCount = 0;

      days.forEach(day => {
        const count = route.distribution.get(day) || 0;
        cumulativeCount += count;
        cumulativePercentages[day] = route.totalSamples > 0 
          ? (cumulativeCount / route.totalSamples) * 100 
          : 0;
      });

      return {
        ...route,
        cumulativePercentages,
      };
    });

    return { tableData: data, dayColumns: days };
  }, [routes, maxDays]);

  if (tableData.length === 0) {
    return (
      <div className="text-center py-8 text-gray-400">
        No distribution data available
      </div>
    );
  }

  return (
    <div className="max-h-96 overflow-y-auto overflow-x-auto">
      <table className="min-w-full divide-y divide-gray-200">
        <thead className="bg-gray-50 sticky top-0 z-20">
          <tr>
            <th className="sticky left-0 z-30 bg-gray-50 px-2 py-2 text-left text-xs font-medium text-gray-500 uppercase border-r border-gray-200 min-w-[140px]">
              <div className="flex items-center gap-1">
                Route
                <ColumnTooltip content="Origin → Destination city pair. Each route shows cumulative delivery percentages by day." />
              </div>
            </th>
            <th className="sticky z-20 bg-gray-50 px-2 py-2 text-left text-xs font-medium text-gray-500 uppercase min-w-[100px]" style={{ left: '140px' }}>
              <div className="flex items-center gap-1">
                Carrier
                <ColumnTooltip content="Shipping carrier for this route." />
              </div>
            </th>
            <th className="sticky z-20 bg-gray-50 px-2 py-2 text-left text-xs font-medium text-gray-500 uppercase min-w-[120px]" style={{ left: '240px' }}>
              <div className="flex items-center gap-1">
                Product
                <ColumnTooltip content="Service product (e.g., Express 24 horas) for this route." />
              </div>
            </th>
            <th className="sticky z-20 bg-gray-50 px-1 py-2 text-center text-xs font-medium text-gray-500 uppercase min-w-[70px]" style={{ left: '360px' }}>
              <div className="flex items-center gap-1 justify-center">
                J+K Std
                <ColumnTooltip content="Expected delivery time in days from delivery_standards. Column header turns green when it matches this value." />
              </div>
            </th>
            <th className="sticky z-20 bg-gray-50 px-1 py-2 text-center text-xs font-medium text-gray-500 uppercase min-w-[70px] border-r border-gray-300" style={{ left: '430px' }}>
              <div className="flex items-center gap-1 justify-center">
                Std %
                <ColumnTooltip content="Target success percentage from delivery_standards (e.g., 85%, 95%). This is the threshold the route must meet." />
              </div>
            </th>
            {dayColumns.map(day => {
              // Check if this day matches any route's standard
              const isStandardDay = tableData.some(route => route.jkStandard === day);
              return (
                <th
                  key={day}
                  className={`px-1 py-2 text-center text-xs font-medium uppercase min-w-[50px] ${
                    isStandardDay ? 'text-green-600' : 'text-gray-500'
                  }`}
                >
                  {day}d
                </th>
              );
            })}
          </tr>
        </thead>
        <tbody className="bg-white divide-y divide-gray-200">
          {tableData.map((route, idx) => (
            <tr key={idx} className="hover:bg-gray-50">
              <td className="sticky left-0 z-10 bg-white px-2 py-2 text-xs font-medium text-gray-900 border-r border-gray-200 min-w-[140px]">
                {route.originCity} → {route.destinationCity}
              </td>
              <td className="sticky z-5 bg-white px-2 py-2 text-xs text-gray-600 min-w-[100px]" style={{ left: '140px' }}>
                {route.carrier}
              </td>
              <td className="sticky z-5 bg-white px-2 py-2 text-xs text-gray-600 min-w-[120px]" style={{ left: '240px' }}>
                {route.product}
              </td>
              <td className="sticky z-5 bg-white px-1 py-2 text-xs text-center text-gray-900 min-w-[70px]" style={{ left: '360px' }}>
                {route.jkStandard}
              </td>
              <td className="sticky z-5 bg-white px-1 py-2 text-xs text-center text-gray-900 min-w-[70px] border-r border-gray-300" style={{ left: '430px' }}>
                {route.standardPercentage.toFixed(0)}%
              </td>
              {dayColumns.map(day => {
                const percentage = route.cumulativePercentages[day] || 0;
                const isBeforeOrAtStandard = day <= route.jkStandard;
                const meetsStandard = percentage >= route.standardPercentage;

                return (
                  <td
                    key={day}
                    className={`px-1 py-2 text-xs text-center font-medium min-w-[50px] ${
                      isBeforeOrAtStandard
                        ? meetsStandard
                          ? 'bg-green-50 text-green-700'
                          : 'bg-green-50 text-green-600'
                        : meetsStandard
                        ? 'bg-red-50 text-red-700'
                        : 'bg-red-50 text-red-600'
                    }`}
                  >
                    {formatNumber(percentage)}%
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
