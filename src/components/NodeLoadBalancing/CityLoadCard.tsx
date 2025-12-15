import React from 'react';
import { NodeLoadData } from '../../hooks/useNodeLoadBalancing';

interface CityLoadCardProps {
  cityName: string;
  cityData: NodeLoadData[];
  onBalance: () => void;
  onViewDetails: () => void;
}

export const CityLoadCard: React.FC<CityLoadCardProps> = ({
  cityName,
  cityData,
  onBalance,
  onViewDetails,
}) => {
  // Get unique weeks and nodes
  const weeks = Array.from(new Set(cityData.map((d) => d.week_number))).sort();
  const nodes = Array.from(new Set(cityData.map((d) => d.node_code))).sort();

  // Calculate city stats
  const totalShipments = cityData.reduce((sum, d) => sum + d.shipment_count, 0);
  const avgPerNode = totalShipments / nodes.length;
  const monthlyStddev = cityData[0]?.city_monthly_stddev || 0;

  // Create matrix data structure
  const matrix: { [nodeCode: string]: { [week: number]: NodeLoadData } } = {};
  cityData.forEach((d) => {
    if (!matrix[d.node_code]) {
      matrix[d.node_code] = {};
    }
    matrix[d.node_code][d.week_number] = d;
  });

  // Calculate node averages
  const nodeAverages: { [nodeCode: string]: number } = {};
  nodes.forEach((nodeCode) => {
    const nodeData = cityData.filter((d) => d.node_code === nodeCode);
    const sum = nodeData.reduce((s, d) => s + d.shipment_count, 0);
    nodeAverages[nodeCode] = sum / nodeData.length;
  });

  // Calculate week totals and averages
  const weekTotals: { [week: number]: number } = {};
  const weekAverages: { [week: number]: number } = {};
  const weekStddevs: { [week: number]: number } = {};

  weeks.forEach((week) => {
    const weekData = cityData.filter((d) => d.week_number === week);
    weekTotals[week] = weekData.reduce((sum, d) => sum + d.shipment_count, 0);
    weekAverages[week] = weekTotals[week] / nodes.length;
    weekStddevs[week] = weekData[0]?.city_weekly_stddev || 0;
  });

  const getLoadColor = (count: number, avg: number) => {
    const percentage = (count / avg) * 100;
    if (percentage > 150) return 'text-red-700';
    if (percentage > 120) return 'text-orange-600';
    return 'text-green-700';
  };

  const getLoadIcon = (count: number, avg: number) => {
    const percentage = (count / avg) * 100;
    if (percentage > 150) return '🔴';
    if (percentage > 120) return '🟡';
    return '🟢';
  };

  const getStddevColor = (stddev: number) => {
    if (stddev > 15) return 'text-red-700';
    if (stddev > 10) return 'text-orange-600';
    if (stddev > 5) return 'text-yellow-600';
    return 'text-green-700';
  };

  const getStatusBadge = (nodeCode: string) => {
    const nodeData = cityData.filter((d) => d.node_code === nodeCode);
    const hasSaturated = nodeData.some((d) => d.saturation_level === 'saturated');
    const hasHigh = nodeData.some((d) => d.saturation_level === 'high');

    if (hasSaturated) {
      return (
        <span className="inline-flex items-center gap-1 px-2 py-1 bg-red-100 text-red-700 text-xs font-medium rounded-full">
          SATURATED
        </span>
      );
    }
    if (hasHigh) {
      return (
        <span className="inline-flex items-center gap-1 px-2 py-1 bg-orange-100 text-orange-700 text-xs font-medium rounded-full">
          HIGH
        </span>
      );
    }
    return (
      <span className="inline-flex items-center gap-1 px-2 py-1 bg-green-100 text-green-700 text-xs font-medium rounded-full">
        NORMAL
      </span>
    );
  };

  return (
    <div className="border border-gray-200 rounded-lg overflow-hidden mb-6">
      {/* Header */}
      <div className="bg-gray-50 px-6 py-4 border-b border-gray-200">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <span className="text-2xl">🏙️</span>
            <h3 className="text-lg font-semibold text-gray-900">{cityName}</h3>
          </div>
          <div className="flex items-center gap-6 text-sm">
            <div className="flex items-center gap-2">
              <span className="text-gray-600">Total:</span>
              <strong className="text-gray-900">{totalShipments} shipments</strong>
            </div>
            <div className="flex items-center gap-2">
              <span className="text-gray-600">Avg/Node:</span>
              <strong className="text-gray-900">{avgPerNode.toFixed(1)}</strong>
            </div>
            <div className="flex items-center gap-2">
              <span className="text-gray-600">Std Dev:</span>
              <strong className={getStddevColor(monthlyStddev)}>
                {monthlyStddev.toFixed(1)}
              </strong>
            </div>
          </div>
        </div>
      </div>

      {/* Heat Map Table */}
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                Node
              </th>
              {weeks.map((week) => (
                <th
                  key={week}
                  className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase"
                >
                  Week {week}
                </th>
              ))}
              <th className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase">
                Monthly Avg
              </th>
              <th className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase">
                Status
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200">
            {nodes.map((nodeCode) => (
              <tr key={nodeCode} className="hover:bg-gray-50">
                <td className="px-4 py-3 font-medium text-gray-900">{nodeCode}</td>
                {weeks.map((week) => {
                  const data = matrix[nodeCode]?.[week];
                  if (!data) {
                    return (
                      <td key={week} className="px-4 py-3 text-center text-gray-400">
                        —
                      </td>
                    );
                  }
                  return (
                    <td key={week} className="px-4 py-3 text-center">
                      <span
                        className={`inline-flex items-center gap-1 font-medium ${getLoadColor(
                          data.shipment_count,
                          weekAverages[week]
                        )}`}
                      >
                        <span>{getLoadIcon(data.shipment_count, weekAverages[week])}</span>
                        {data.shipment_count}
                      </span>
                    </td>
                  );
                })}
                <td className="px-4 py-3 text-center font-semibold text-gray-900">
                  {nodeAverages[nodeCode].toFixed(1)}
                </td>
                <td className="px-4 py-3 text-center">{getStatusBadge(nodeCode)}</td>
              </tr>
            ))}

            {/* Totals Row */}
            <tr className="bg-gray-50 font-semibold border-t-2 border-gray-300">
              <td className="px-4 py-3 text-gray-900">TOTAL</td>
              {weeks.map((week) => (
                <td key={week} className="px-4 py-3 text-center text-gray-900">
                  {weekTotals[week]}
                </td>
              ))}
              <td className="px-4 py-3 text-center text-gray-900">
                {(totalShipments / weeks.length).toFixed(1)}
              </td>
              <td></td>
            </tr>

            {/* Average Row */}
            <tr className="bg-gray-50 font-semibold">
              <td className="px-4 py-3 text-gray-900">AVG/NODE</td>
              {weeks.map((week) => (
                <td key={week} className="px-4 py-3 text-center text-gray-900">
                  {weekAverages[week].toFixed(1)}
                </td>
              ))}
              <td className="px-4 py-3 text-center text-gray-900">{avgPerNode.toFixed(1)}</td>
              <td></td>
            </tr>

            {/* Std Dev Row */}
            <tr className="bg-gray-50 font-semibold">
              <td className="px-4 py-3 text-gray-900">STD DEV</td>
              {weeks.map((week) => (
                <td
                  key={week}
                  className={`px-4 py-3 text-center ${getStddevColor(weekStddevs[week])}`}
                >
                  {weekStddevs[week].toFixed(1)}
                </td>
              ))}
              <td className={`px-4 py-3 text-center ${getStddevColor(monthlyStddev)}`}>
                {monthlyStddev.toFixed(1)}
              </td>
              <td></td>
            </tr>
          </tbody>
        </table>
      </div>

      {/* Actions */}
      <div className="bg-gray-50 px-6 py-4 border-t border-gray-200 flex gap-3">
        <button
          onClick={onBalance}
          className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-md text-sm font-medium hover:bg-blue-700 transition-colors"
        >
          <span>⚖️</span>
          Auto-Balance {cityName}
        </button>
        <button
          onClick={onViewDetails}
          className="flex items-center gap-2 px-4 py-2 bg-white border border-gray-300 text-gray-700 rounded-md text-sm font-medium hover:bg-gray-50 transition-colors"
        >
          <span>📊</span>
          View Details
        </button>
      </div>
    </div>
  );
};
