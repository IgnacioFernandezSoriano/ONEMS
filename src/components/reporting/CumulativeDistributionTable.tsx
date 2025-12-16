import { useMemo } from 'react';

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

    // Generate day columns (1 to maxDays, limited to 20 for display)
    const maxDisplayDays = Math.min(maxDays, 20);
    const days = Array.from({ length: maxDisplayDays }, (_, i) => i + 1);

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
    <div className="overflow-x-auto">
      <table className="min-w-full divide-y divide-gray-200">
        <thead className="bg-gray-50">
          <tr>
            <th className="sticky left-0 z-10 bg-gray-50 px-3 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider border-r border-gray-200">
              Route
            </th>
            <th className="px-3 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Carrier
            </th>
            <th className="px-3 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Product
            </th>
            <th className="px-3 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider">
              J+K Std
            </th>
            <th className="px-3 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider">
              Std %
            </th>
            {dayColumns.map(day => {
              // Check if this day matches any route's standard
              const isStandardDay = tableData.some(route => route.jkStandard === day);
              return (
                <th
                  key={day}
                  className={`px-3 py-3 text-center text-xs font-medium uppercase tracking-wider ${
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
              <td className="sticky left-0 z-10 bg-white px-3 py-4 text-sm font-medium text-gray-900 border-r border-gray-200">
                {route.originCity} → {route.destinationCity}
              </td>
              <td className="px-3 py-4 text-sm text-gray-600">
                {route.carrier}
              </td>
              <td className="px-3 py-4 text-sm text-gray-600">
                {route.product}
              </td>
              <td className="px-3 py-4 text-sm text-center text-gray-900">
                {route.jkStandard}
              </td>
              <td className="px-3 py-4 text-sm text-center text-gray-900">
                {route.standardPercentage.toFixed(0)}%
              </td>
              {dayColumns.map(day => {
                const percentage = route.cumulativePercentages[day] || 0;
                const isBeforeOrAtStandard = day <= route.jkStandard;
                const meetsStandard = percentage >= route.standardPercentage;

                return (
                  <td
                    key={day}
                    className={`px-3 py-4 text-sm text-center font-medium ${
                      isBeforeOrAtStandard
                        ? meetsStandard
                          ? 'bg-green-50 text-green-700'
                          : 'bg-green-50 text-green-600'
                        : meetsStandard
                        ? 'bg-red-50 text-red-700'
                        : 'bg-red-50 text-red-600'
                    }`}
                  >
                    {percentage.toFixed(1)}%
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
