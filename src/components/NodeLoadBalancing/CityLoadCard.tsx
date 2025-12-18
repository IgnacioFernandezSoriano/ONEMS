import React from 'react';
import { NodeLoadData } from '../../hooks/useNodeLoadBalancing';

interface CityLoadCardProps {
  cityName: string;
  cityData: NodeLoadData[];
  onBalance: () => void;
}

export const CityLoadCard: React.FC<CityLoadCardProps> = ({
  cityName,
  cityData,
  onBalance,
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
            <div className="w-10 h-10 bg-blue-100 rounded-full flex items-center justify-center">
              <svg className="w-6 h-6 text-blue-600" fill="currentColor" viewBox="0 0 20 20">
                <path fillRule="evenodd" d="M4 4a2 2 0 012-2h8a2 2 0 012 2v12a1 1 0 110 2h-3a1 1 0 01-1-1v-2a1 1 0 00-1-1H9a1 1 0 00-1 1v2a1 1 0 01-1 1H4a1 1 0 110-2V4zm3 1h2v2H7V5zm2 4H7v2h2V9zm2-4h2v2h-2V5zm2 4h-2v2h2V9z" clipRule="evenodd" />
              </svg>
            </div>
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


          </tbody>
        </table>
      </div>

      {/* Actions */}
      <div className="bg-gray-50 px-6 py-4 border-t border-gray-200 flex items-center gap-3">
        <div className="group relative">
          <button
            onClick={onBalance}
            className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-md text-sm font-medium hover:bg-blue-700 transition-colors"
          >
            <span>⚖️</span>
            Auto-Balance {cityName}
          </button>
        </div>
        <span className="group relative">
          <svg
            className="w-5 h-5 text-gray-400 cursor-help"
            fill="currentColor"
            viewBox="0 0 20 20"
          >
            <path
              fillRule="evenodd"
              d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z"
              clipRule="evenodd"
            />
          </svg>
          <div className="invisible group-hover:visible absolute z-10 w-96 p-3 bg-gray-900 text-white text-sm rounded-lg shadow-lg bottom-full left-0 mb-2">
            <p className="font-semibold mb-2">Auto-Balance Mechanism</p>
            <p className="mb-2">
              <strong>How it works:</strong> The system analyzes shipment distribution across nodes and weeks, identifying overloaded nodes (&gt;150% avg) and underutilized nodes (&lt;80% avg).
            </p>
            <p className="mb-2">
              <strong>Algorithm:</strong> Moves shipments from saturated nodes to nodes with available capacity, prioritizing moves within the same week to maintain temporal distribution.
            </p>
            <p>
              <strong>Result:</strong> Reduces load variance, prevents node saturation, and improves overall system efficiency. Preview shows proposed changes before applying.
            </p>
          </div>
        </span>
      </div>
    </div>
  );
};
