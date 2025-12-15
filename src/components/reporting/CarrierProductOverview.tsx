import React from 'react';
import { TrendingUp, TrendingDown, AlertCircle, CheckCircle } from 'lucide-react';

interface CarrierProductData {
  carrier: string;
  product: string;
  compliancePercentage: number;
  avgBusinessDays: number;
  totalShipments: number;
  trend: 'up' | 'down' | 'stable';
}

interface CarrierProductOverviewProps {
  data: CarrierProductData[];
  loading: boolean;
}

export default function CarrierProductOverview({ data, loading }: CarrierProductOverviewProps) {
  if (loading) {
    return (
      <div className="bg-white rounded-lg shadow p-6">
        <h3 className="text-lg font-semibold text-gray-900 mb-4">Carrier & Product Overview</h3>
        <div className="text-center text-gray-500 py-8">Loading...</div>
      </div>
    );
  }

  if (data.length === 0) {
    return (
      <div className="bg-white rounded-lg shadow p-6">
        <h3 className="text-lg font-semibold text-gray-900 mb-4">Carrier & Product Overview</h3>
        <div className="text-center text-gray-500 py-8">No data available</div>
      </div>
    );
  }

  const getComplianceColor = (compliance: number) => {
    if (compliance >= 95) return 'text-green-600 bg-green-50';
    if (compliance >= 85) return 'text-yellow-600 bg-yellow-50';
    return 'text-red-600 bg-red-50';
  };

  const getComplianceIcon = (compliance: number) => {
    if (compliance >= 95) return <CheckCircle className="w-5 h-5 text-green-600" />;
    if (compliance >= 85) return <AlertCircle className="w-5 h-5 text-yellow-600" />;
    return <AlertCircle className="w-5 h-5 text-red-600" />;
  };

  const getTrendIcon = (trend: 'up' | 'down' | 'stable') => {
    if (trend === 'up') return <TrendingUp className="w-4 h-4 text-green-600" />;
    if (trend === 'down') return <TrendingDown className="w-4 h-4 text-red-600" />;
    return <span className="w-4 h-4 text-gray-400">→</span>;
  };

  // Sort by compliance (worst first) to highlight problems
  const sortedData = [...data].sort((a, b) => a.compliancePercentage - b.compliancePercentage);

  return (
    <div className="bg-white rounded-lg shadow p-6">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-semibold text-gray-900">Carrier & Product Overview</h3>
        <p className="text-sm text-gray-600">
          {data.length} carrier-product combinations
        </p>
      </div>

      <div className="overflow-x-auto">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Carrier
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Product
              </th>
              <th className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider">
                Status
              </th>
              <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Compliance
              </th>
              <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Avg Days
              </th>
              <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Shipments
              </th>
              <th className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider">
                Trend
              </th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {sortedData.map((item, index) => (
              <tr key={`${item.carrier}-${item.product}-${index}`} className="hover:bg-gray-50">
                <td className="px-4 py-3 whitespace-nowrap text-sm font-medium text-gray-900">
                  {item.carrier}
                </td>
                <td className="px-4 py-3 whitespace-nowrap text-sm text-gray-700">
                  {item.product}
                </td>
                <td className="px-4 py-3 whitespace-nowrap text-center">
                  {getComplianceIcon(item.compliancePercentage)}
                </td>
                <td className="px-4 py-3 whitespace-nowrap text-right">
                  <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${getComplianceColor(item.compliancePercentage)}`}>
                    {item.compliancePercentage.toFixed(1)}%
                  </span>
                </td>
                <td className="px-4 py-3 whitespace-nowrap text-right text-sm text-gray-700">
                  {item.avgBusinessDays.toFixed(1)}
                </td>
                <td className="px-4 py-3 whitespace-nowrap text-right text-sm text-gray-700">
                  {item.totalShipments.toLocaleString()}
                </td>
                <td className="px-4 py-3 whitespace-nowrap text-center">
                  {getTrendIcon(item.trend)}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="mt-4 pt-4 border-t border-gray-200">
        <div className="flex items-center gap-6 text-xs text-gray-600">
          <div className="flex items-center gap-2">
            <CheckCircle className="w-4 h-4 text-green-600" />
            <span>≥95% Compliant</span>
          </div>
          <div className="flex items-center gap-2">
            <AlertCircle className="w-4 h-4 text-yellow-600" />
            <span>85-95% Warning</span>
          </div>
          <div className="flex items-center gap-2">
            <AlertCircle className="w-4 h-4 text-red-600" />
            <span>&lt;85% Critical</span>
          </div>
        </div>
      </div>
    </div>
  );
}
