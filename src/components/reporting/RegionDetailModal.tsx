import { X } from 'lucide-react';
import type { RegionEquityData } from '@/types/reporting';
import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';

interface RegionDetailModalProps {
  region: RegionEquityData;
  onClose: () => void;
  accountId: string;
  filters?: {
    carrier?: string;
    product?: string;
  };
}

interface CarrierProductData {
  carrier: string;
  product: string;
  totalShipments: number;
  compliantShipments: number;
  actualPercentage: number;
  standardPercentage: number;
  deviation: number;
}

export function RegionDetailModal({ region, onClose, accountId, filters }: RegionDetailModalProps) {
  const [carrierProductData, setCarrierProductData] = useState<CarrierProductData[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadCarrierProductData();
  }, [region.regionId, accountId, filters]);

  const loadCarrierProductData = async () => {
    try {
      setLoading(true);

      // Build query for shipments in this region
      let query = supabase
        .from('shipments')
        .select(`
          carrier_name,
          product_name,
          on_time_delivery,
          origin_city_name,
          destination_city_name
        `)
        .eq('account_id', accountId)
        .or(`origin_city_name.in.(${await getCitiesInRegion()}),destination_city_name.in.(${await getCitiesInRegion()})`);

      // Apply filters
      if (filters?.carrier) {
        query = query.eq('carrier_name', filters.carrier);
      }
      if (filters?.product) {
        query = query.eq('product_name', filters.product);
      }

      const { data: shipments, error } = await query;

      if (error) throw error;

      // Get delivery standards
      const { data: standards } = await supabase
        .from('delivery_standards')
        .select('carrier_id, product_id, origin_city_id, destination_city_id, success_percentage')
        .eq('account_id', accountId);

      // Group by carrier and product
      const grouped = (shipments || []).reduce((acc: any, shipment: any) => {
        const key = `${shipment.carrier_name}|${shipment.product_name}`;
        if (!acc[key]) {
          acc[key] = {
            carrier: shipment.carrier_name,
            product: shipment.product_name,
            total: 0,
            compliant: 0,
            standardsSum: 0,
            standardsCount: 0,
          };
        }
        acc[key].total++;
        if (shipment.on_time_delivery) acc[key].compliant++;
        return acc;
      }, {});

      // Calculate percentages
      const result: CarrierProductData[] = Object.values(grouped).map((item: any) => {
        const actualPercentage = item.total > 0 ? (item.compliant / item.total) * 100 : 0;
        const standardPercentage = 95; // Default, could be calculated from standards
        const deviation = actualPercentage - standardPercentage;

        return {
          carrier: item.carrier,
          product: item.product,
          totalShipments: item.total,
          compliantShipments: item.compliant,
          actualPercentage,
          standardPercentage,
          deviation,
        };
      });

      // Sort by total shipments descending
      result.sort((a, b) => b.totalShipments - a.totalShipments);

      setCarrierProductData(result);
    } catch (error) {
      console.error('Error loading carrier/product data:', error);
    } finally {
      setLoading(false);
    }
  };

  const getCitiesInRegion = async () => {
    const { data: cities } = await supabase
      .from('cities')
      .select('name')
      .eq('region_id', region.regionId)
      .eq('account_id', accountId);

    return (cities || []).map(c => `"${c.name}"`).join(',');
  };

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

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
      <div className="bg-white rounded-lg shadow-xl max-w-4xl w-full max-h-[85vh] overflow-y-auto">
        {/* Header */}
        <div className="sticky top-0 bg-white border-b px-6 py-4 flex justify-between items-center">
          <h2 className="text-2xl font-bold text-gray-900">Region Details: {region.regionName}</h2>
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
              Regional Summary
            </h3>
            <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
              <div>
                <span className="text-sm text-gray-600">Total Cities:</span>
                <p className="font-medium">{region.totalCities}</p>
              </div>
              <div>
                <span className="text-sm text-gray-600">Total Population:</span>
                <p className="font-medium">
                  {region.totalPopulation ? region.totalPopulation.toLocaleString() : 'N/A'}
                </p>
              </div>
              <div>
                <span className="text-sm text-gray-600">Total Shipments:</span>
                <p className="font-medium">{region.totalShipments}</p>
              </div>
              <div>
                <span className="text-sm text-gray-600">Compliant Shipments:</span>
                <p className="font-medium">
                  {region.compliantShipments} ({(region.actualPercentage || 0).toFixed(1)}%)
                </p>
              </div>
              <div>
                <span className="text-sm text-gray-600">Standard:</span>
                <p className="font-medium">{(region.standardPercentage || 0).toFixed(1)}%</p>
              </div>
              <div>
                <span className="text-sm text-gray-600">Deviation:</span>
                <p
                  className={`font-medium ${
                    region.deviation >= 0 ? 'text-green-600' : 'text-red-600'
                  }`}
                >
                  {(region.deviation || 0) >= 0 ? '+' : ''}
                  {(region.deviation || 0).toFixed(1)}%
                </p>
              </div>
              <div>
                <span className="text-sm text-gray-600">Status:</span>
                <p className="font-medium">
                  {getStatusIcon(region.status)} {region.status}
                </p>
              </div>
            </div>
          </section>

          {/* Directional Analysis */}
          <section>
            <h3 className="text-lg font-semibold text-gray-900 mb-3 border-b pb-2">
              Directional Analysis
            </h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              <div className="p-3 bg-blue-50 rounded">
                <span className="text-sm text-gray-600">Inbound (Arrivals):</span>
                <p className="text-2xl font-bold text-blue-600">
                  {(region.inboundPercentage || 0).toFixed(1)}%
                </p>
              </div>
              <div className="p-3 bg-green-50 rounded">
                <span className="text-sm text-gray-600">Outbound (Departures):</span>
                <p className="text-2xl font-bold text-green-600">
                  {(region.outboundPercentage || 0).toFixed(1)}%
                </p>
              </div>
            </div>
          </section>

          {/* Carrier & Product Breakdown */}
          <section>
            <h3 className="text-lg font-semibold text-gray-900 mb-3 border-b pb-2">
              Carrier & Product Breakdown
              {filters?.carrier && <span className="text-sm font-normal text-gray-500 ml-2">(Filtered by: {filters.carrier})</span>}
              {filters?.product && <span className="text-sm font-normal text-gray-500 ml-2">(Filtered by: {filters.product})</span>}
            </h3>
            {loading ? (
              <div className="text-center py-8 text-gray-500">Loading...</div>
            ) : carrierProductData.length === 0 ? (
              <div className="text-center py-8 text-gray-500">No data available</div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="bg-gray-50 border-b">
                    <tr>
                      <th className="text-left px-3 py-2 font-medium text-gray-600">Carrier</th>
                      <th className="text-left px-3 py-2 font-medium text-gray-600">Product</th>
                      <th className="text-right px-3 py-2 font-medium text-gray-600">Shipments</th>
                      <th className="text-right px-3 py-2 font-medium text-gray-600">Compliant</th>
                      <th className="text-right px-3 py-2 font-medium text-gray-600">Actual %</th>
                      <th className="text-right px-3 py-2 font-medium text-gray-600">Standard %</th>
                      <th className="text-right px-3 py-2 font-medium text-gray-600">Deviation</th>
                    </tr>
                  </thead>
                  <tbody>
                    {carrierProductData.map((item, idx) => (
                      <tr key={idx} className="border-b hover:bg-gray-50">
                        <td className="px-3 py-2 font-medium">{item.carrier}</td>
                        <td className="px-3 py-2">{item.product}</td>
                        <td className="px-3 py-2 text-right">{item.totalShipments}</td>
                        <td className="px-3 py-2 text-right">{item.compliantShipments}</td>
                        <td className="px-3 py-2 text-right font-medium">
                          {item.actualPercentage.toFixed(1)}%
                        </td>
                        <td className="px-3 py-2 text-right text-gray-600">
                          {item.standardPercentage.toFixed(1)}%
                        </td>
                        <td
                          className={`px-3 py-2 text-right font-medium ${
                            item.deviation >= 0 ? 'text-green-600' : 'text-red-600'
                          }`}
                        >
                          {item.deviation >= 0 ? '+' : ''}
                          {item.deviation.toFixed(1)}%
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </section>
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
