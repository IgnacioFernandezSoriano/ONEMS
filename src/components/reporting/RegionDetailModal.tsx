import { X } from 'lucide-react';
import type { RegionEquityData } from '@/types/reporting';

interface RegionDetailModalProps {
  region: RegionEquityData;
  onClose: () => void;
}

export function RegionDetailModal({ region, onClose }: RegionDetailModalProps) {
  const carrierProductData = region.carrierProductBreakdown || [];

  const getStatusBadge = (status: string) => {
    const styles = {
      compliant: 'bg-green-100 text-green-800',
      warning: 'bg-amber-100 text-amber-800',
      critical: 'bg-red-100 text-red-800',
    };
    return styles[status as keyof typeof styles] || 'bg-gray-100 text-gray-800';
  };

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
      <div className="bg-white rounded-lg shadow-xl max-w-4xl w-full max-h-[90vh] overflow-y-auto">
        <div className="sticky top-0 bg-white border-b border-gray-200 px-6 py-4 flex items-center justify-between">
          <h2 className="text-2xl font-bold text-gray-900">Region Details: {region.regionName}</h2>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-gray-600 transition-colors"
          >
            <X className="w-6 h-6" />
          </button>
        </div>

        <div className="p-6 space-y-6">
          {/* Basic Information */}
          <div>
            <h3 className="text-lg font-semibold text-gray-900 mb-3">Regional Summary</h3>
            <div className="grid grid-cols-3 gap-4">
              <div>
                <p className="text-sm text-gray-500">Total Cities:</p>
                <p className="font-medium text-gray-900">{region.totalCities}</p>
              </div>
              <div>
                <p className="text-sm text-gray-500">Population:</p>
                <p className="font-medium text-gray-900">
                  {region.totalPopulation.toLocaleString()}
                </p>
              </div>
              <div>
                <p className="text-sm text-gray-500">Total Shipments:</p>
                <p className="font-medium text-gray-900">{region.totalShipments}</p>
              </div>
            </div>
          </div>

          {/* Performance Metrics */}
          <div>
            <h3 className="text-lg font-semibold text-gray-900 mb-3">Performance Metrics</h3>
            <div className="grid grid-cols-3 gap-4">
              <div>
                <p className="text-sm text-gray-500">Compliant:</p>
                <p className="font-medium text-gray-900">
                  {region.compliantShipments} ({region.actualPercentage.toFixed(1)}%)
                </p>
              </div>
              <div>
                <p className="text-sm text-gray-500">Standard:</p>
                <p className="font-medium text-gray-900">{region.standardPercentage.toFixed(1)}%</p>
              </div>
              <div>
                <p className="text-sm text-gray-500">Deviation:</p>
                <p
                  className={`font-medium ${
                    region.deviation >= 0 ? 'text-green-600' : 'text-red-600'
                  }`}
                >
                  {region.deviation >= 0 ? '+' : ''}
                  {region.deviation.toFixed(1)}%
                </p>
              </div>
              <div>
                <p className="text-sm text-gray-500">Status:</p>
                <span
                  className={`inline-block px-2 py-1 rounded-full text-xs font-medium ${getStatusBadge(
                    region.status
                  )}`}
                >
                  {region.status === 'compliant' && '✅ compliant'}
                  {region.status === 'warning' && '⚠️ warning'}
                  {region.status === 'critical' && '🔴 critical'}
                </span>
              </div>
              <div>
                <p className="text-sm text-gray-500">Underserved Cities:</p>
                <p className="font-medium text-gray-900">{region.underservedCitiesCount}</p>
              </div>
            </div>
          </div>

          {/* Directional Analysis */}
          <div>
            <h3 className="text-lg font-semibold text-gray-900 mb-3">Directional Analysis</h3>
            <div className="space-y-3">
              <div className="bg-blue-50 p-4 rounded-lg">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-gray-600">Inbound (Arrivals):</p>
                    <p className="text-sm text-gray-700">Compliance for shipments arriving to this region</p>
                  </div>
                  <p className="text-2xl font-bold text-blue-600">
                    {region.inboundPercentage.toFixed(1)}%
                  </p>
                </div>
              </div>

              <div className="bg-green-50 p-4 rounded-lg">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-gray-600">Outbound (Departures):</p>
                    <p className="text-sm text-gray-700">Compliance for shipments departing from this region</p>
                  </div>
                  <p className="text-2xl font-bold text-green-600">
                    {region.outboundPercentage.toFixed(1)}%
                  </p>
                </div>
              </div>

              <div className="bg-gray-50 p-4 rounded-lg">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-gray-600">Direction Gap:</p>
                    <p className="text-xs text-gray-500">
                      {region.directionGap > 5 ? '⚠️ Imbalanced service' : '✅ Balanced service'}
                    </p>
                  </div>
                  <p className="text-2xl font-bold text-gray-700">
                    {region.directionGap.toFixed(1)}%
                  </p>
                </div>
              </div>
            </div>
          </div>

          {/* Carrier & Product Breakdown */}
          <div>
            <h3 className="text-lg font-semibold text-gray-900 mb-3">Carrier & Product Breakdown</h3>
            {carrierProductData.length > 0 ? (
              <div className="overflow-x-auto">
                <table className="min-w-full divide-y divide-gray-200">
                  <thead className="bg-gray-50">
                    <tr>
                      <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        Carrier
                      </th>
                      <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        Product
                      </th>
                      <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">
                        Shipments
                      </th>
                      <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">
                        Compliant
                      </th>
                      <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">
                        Actual %
                      </th>
                      <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">
                        Standard %
                      </th>
                      <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">
                        Deviation
                      </th>
                      <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">
                        Inbound %
                      </th>
                      <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">
                        Outbound %
                      </th>
                    </tr>
                  </thead>
                  <tbody className="bg-white divide-y divide-gray-200">
                    {carrierProductData.map((cp, idx) => (
                      <tr key={idx} className="hover:bg-gray-50">
                        <td className="px-4 py-3 text-sm text-gray-900">{cp.carrier}</td>
                        <td className="px-4 py-3 text-sm text-gray-900">{cp.product}</td>
                        <td className="px-4 py-3 text-sm text-right text-gray-900">
                          {cp.totalShipments}
                        </td>
                        <td className="px-4 py-3 text-sm text-right text-gray-900">
                          {cp.compliantShipments}
                        </td>
                        <td className="px-4 py-3 text-sm text-right text-gray-900">
                          {cp.actualPercentage.toFixed(1)}%
                        </td>
                        <td className="px-4 py-3 text-sm text-right text-gray-900">
                          {cp.standardPercentage.toFixed(1)}%
                        </td>
                        <td
                          className={`px-4 py-3 text-sm text-right font-medium ${
                            cp.deviation >= 0 ? 'text-green-600' : 'text-red-600'
                          }`}
                        >
                          {cp.deviation >= 0 ? '+' : ''}
                          {cp.deviation.toFixed(1)}%
                        </td>
                        <td className="px-4 py-3 text-sm text-right text-blue-600">
                          {cp.inboundPercentage.toFixed(1)}%
                        </td>
                        <td className="px-4 py-3 text-sm text-right text-green-600">
                          {cp.outboundPercentage.toFixed(1)}%
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            ) : (
              <p className="text-center py-8 text-gray-500">No data available</p>
            )}
          </div>
        </div>

        <div className="sticky bottom-0 bg-gray-50 px-6 py-4 border-t border-gray-200">
          <button
            onClick={onClose}
            className="w-full px-4 py-2 bg-gray-600 text-white rounded-lg hover:bg-gray-700 transition-colors"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
}
