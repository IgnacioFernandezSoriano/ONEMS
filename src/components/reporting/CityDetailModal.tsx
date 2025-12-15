import { X } from 'lucide-react';
import type { CityEquityData } from '@/types/reporting';

interface CityDetailModalProps {
  city: CityEquityData;
  onClose: () => void;
  shipments?: any[];
}

export function CityDetailModal({ city, onClose, shipments = [] }: CityDetailModalProps) {
  // Calculate carrier breakdown from shipments
  const carrierStats = shipments.reduce((acc: any, s: any) => {
    const carrier = s.carrier_name;
    if (!acc[carrier]) {
      acc[carrier] = { total: 0, compliant: 0 };
    }
    acc[carrier].total++;
    if (s.on_time_delivery) acc[carrier].compliant++;
    return acc;
  }, {});

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'compliant':
        return '✅';
      case 'warning':
        return '⚠️';
      case 'critical':
        return '🔴';
      default:
        return '';
    }
  };

  const getDirectionGapStatus = (gap: number) => {
    if (gap < 5) return 'balanced';
    if (gap < 15) return 'moderate';
    return 'significant';
  };

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
      <div className="bg-white rounded-lg shadow-xl max-w-3xl w-full max-h-[85vh] overflow-y-auto">
        {/* Header */}
        <div className="sticky top-0 bg-white border-b px-6 py-4 flex justify-between items-center">
          <h2 className="text-2xl font-bold text-gray-900">City Details: {city.cityName}</h2>
          <button
            onClick={onClose}
            className="text-gray-500 hover:text-gray-700 transition-colors"
          >
            <X className="w-6 h-6" />
          </button>
        </div>

        {/* Content */}
        <div className="p-6 space-y-6">
          {/* Basic Information */}
          <section>
            <h3 className="text-lg font-semibold text-gray-900 mb-3 border-b pb-2">
              Basic Information
            </h3>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <span className="text-sm text-gray-600">Region:</span>
                <p className="font-medium">{city.regionName || 'N/A'}</p>
              </div>
              <div>
                <span className="text-sm text-gray-600">Classification:</span>
                <p className="font-medium capitalize">{city.classification || 'N/A'}</p>
              </div>
              <div>
                <span className="text-sm text-gray-600">Population:</span>
                <p className="font-medium">
                  {city.population ? city.population.toLocaleString() : 'N/A'}
                </p>
              </div>
            </div>
          </section>

          {/* Performance Metrics */}
          <section>
            <h3 className="text-lg font-semibold text-gray-900 mb-3 border-b pb-2">
              Performance Metrics
            </h3>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <span className="text-sm text-gray-600">Total Shipments:</span>
                <p className="font-medium">{city.totalShipments}</p>
              </div>
              <div>
                <span className="text-sm text-gray-600">Compliant:</span>
                <p className="font-medium">
                  {city.compliantShipments} ({(city.actualPercentage || 0).toFixed(1)}%)
                </p>
              </div>
              <div>
                <span className="text-sm text-gray-600">Standard:</span>
                <p className="font-medium">{(city.standardPercentage || 0).toFixed(1)}%</p>
              </div>
              <div>
                <span className="text-sm text-gray-600">Deviation:</span>
                <p
                  className={`font-medium ${
                    city.deviation >= 0 ? 'text-green-600' : 'text-red-600'
                  }`}
                >
                  {(city.deviation || 0) >= 0 ? '+' : ''}
                  {(city.deviation || 0).toFixed(1)}%
                </p>
              </div>
              <div>
                <span className="text-sm text-gray-600">Status:</span>
                <p className="font-medium">
                  {getStatusIcon(city.status)} {city.status}
                </p>
              </div>
            </div>
          </section>

          {/* Directional Analysis */}
          <section>
            <h3 className="text-lg font-semibold text-gray-900 mb-3 border-b pb-2">
              Directional Analysis
            </h3>
            <div className="space-y-3">
              <div className="flex justify-between items-center p-3 bg-blue-50 rounded">
                <div>
                  <span className="text-sm text-gray-600">Inbound (Arrivals):</span>
                  <p className="font-medium">
                    {city.inboundShipments} shipments, {city.inboundCompliant} compliant
                  </p>
                </div>
                <div className="text-2xl font-bold text-blue-600">
                  {(city.inboundPercentage || 0).toFixed(1)}%
                </div>
              </div>
              <div className="flex justify-between items-center p-3 bg-green-50 rounded">
                <div>
                  <span className="text-sm text-gray-600">Outbound (Departures):</span>
                  <p className="font-medium">
                    {city.outboundShipments} shipments, {city.outboundCompliant} compliant
                  </p>
                </div>
                <div className="text-2xl font-bold text-green-600">
                  {(city.outboundPercentage || 0).toFixed(1)}%
                </div>
              </div>
              <div className="flex justify-between items-center p-3 bg-gray-50 rounded">
                <div>
                  <span className="text-sm text-gray-600">Direction Gap:</span>
                  <p className="text-xs text-gray-500">
                    {getDirectionGapStatus(city.directionGap) === 'balanced' && '✅ Balanced service'}
                    {getDirectionGapStatus(city.directionGap) === 'moderate' && '⚠️ Moderate disparity'}
                    {getDirectionGapStatus(city.directionGap) === 'significant' && '🔴 Significant disparity'}
                  </p>
                </div>
                <div
                  className={`text-2xl font-bold ${
                    city.directionGap > 15 ? 'text-amber-600' : 'text-gray-700'
                  }`}
                >
                  {(city.directionGap || 0).toFixed(1)}%
                </div>
              </div>
            </div>
          </section>

          {/* Carrier Breakdown */}
          {Object.keys(carrierStats).length > 0 && (
            <section>
              <h3 className="text-lg font-semibold text-gray-900 mb-3 border-b pb-2">
                Carrier Breakdown
              </h3>
              <div className="space-y-2">
                {Object.entries(carrierStats)
                  .sort(([, a]: any, [, b]: any) => b.total - a.total)
                  .map(([carrier, stats]: [string, any]) => {
                    const compliance = (stats.compliant / stats.total) * 100;
                    return (
                      <div
                        key={carrier}
                        className="flex justify-between items-center p-2 hover:bg-gray-50 rounded"
                      >
                        <span className="font-medium">{carrier}</span>
                        <span className="text-sm text-gray-600">
                          {stats.total} shipments, {(compliance || 0).toFixed(1)}% compliance
                        </span>
                      </div>
                    );
                  })}
              </div>
            </section>
          )}
        </div>

        {/* Footer */}
        <div className="sticky bottom-0 bg-gray-50 border-t px-6 py-4">
          <button
            onClick={onClose}
            className="w-full bg-gray-200 hover:bg-gray-300 text-gray-800 font-medium py-2 px-4 rounded transition-colors"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
}
