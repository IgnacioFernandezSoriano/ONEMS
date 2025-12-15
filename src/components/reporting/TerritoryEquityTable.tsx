import { useState } from 'react';
import { ChevronDown, ChevronUp, Info } from 'lucide-react';
import type { CityEquityData } from '@/types/reporting';

interface TerritoryEquityTableProps {
  data: CityEquityData[];
  onCityClick?: (city: CityEquityData) => void;
}

export function TerritoryEquityTable({ data, onCityClick }: TerritoryEquityTableProps) {
  const [sortField, setSortField] = useState<keyof CityEquityData>('deviation');
  const [sortDirection, setSortDirection] = useState<'asc' | 'desc'>('asc');
  const [expandedRows, setExpandedRows] = useState<Set<string>>(new Set());

  const toggleRow = (cityId: string) => {
    const newExpanded = new Set(expandedRows);
    if (newExpanded.has(cityId)) {
      newExpanded.delete(cityId);
    } else {
      newExpanded.add(cityId);
    }
    setExpandedRows(newExpanded);
  };

  const handleSort = (field: keyof CityEquityData) => {
    if (sortField === field) {
      setSortDirection(sortDirection === 'asc' ? 'desc' : 'asc');
    } else {
      setSortField(field);
      setSortDirection('asc');
    }
  };

  const sortedData = [...data].sort((a, b) => {
    const aVal = a[sortField];
    const bVal = b[sortField];
    const multiplier = sortDirection === 'asc' ? 1 : -1;

    if (typeof aVal === 'number' && typeof bVal === 'number') {
      return (aVal - bVal) * multiplier;
    }
    return String(aVal || '').localeCompare(String(bVal || '')) * multiplier;
  });

  const SortIcon = ({ field }: { field: keyof CityEquityData }) => {
    if (sortField !== field) return null;
    return sortDirection === 'asc' ? (
      <ChevronUp className="w-4 h-4 inline ml-1" />
    ) : (
      <ChevronDown className="w-4 h-4 inline ml-1" />
    );
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

  const Tooltip = ({ content }: { content: string }) => (
    <div className="group relative inline-block">
      <Info className="w-4 h-4 text-gray-400 cursor-help" />
      <div className="invisible group-hover:visible absolute z-10 w-64 p-2 mt-1 text-sm text-white bg-gray-900 rounded-lg shadow-lg -left-28">
        {content}
      </div>
    </div>
  );

  return (
    <div className="overflow-x-auto">
      <table className="min-w-full divide-y divide-gray-200">
        <thead className="bg-gray-50">
          <tr>
            <th className="px-4 py-3 w-10"></th>
            <th
              className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('cityName')}
            >
              <div className="flex items-center gap-1">
                City <SortIcon field="cityName" />
                <Tooltip content="Click to view city details" />
              </div>
            </th>
            <th
              className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('regionName')}
            >
              <div className="flex items-center gap-1">
                Region <SortIcon field="regionName" />
                <Tooltip content="Regulatory region (official boundaries)" />
              </div>
            </th>
            <th
              className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('classification')}
            >
              <div className="flex items-center gap-1">
                Class <SortIcon field="classification" />
                <Tooltip content="capital = Capital city, major = Major city, minor = Small city" />
              </div>
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('population')}
            >
              <div className="flex items-center justify-end gap-1">
                Population <SortIcon field="population" />
                <Tooltip content="Total population of the city" />
              </div>
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('totalShipments')}
            >
              <div className="flex items-center justify-end gap-1">
                Total <SortIcon field="totalShipments" />
                <Tooltip content="Total shipments (inbound + outbound)" />
              </div>
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('standardPercentage')}
            >
              <div className="flex items-center justify-end gap-1">
                Standard % <SortIcon field="standardPercentage" />
                <Tooltip content="Expected compliance (weighted avg of delivery standards)" />
              </div>
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('actualPercentage')}
            >
              <div className="flex items-center justify-end gap-1">
                Actual % <SortIcon field="actualPercentage" />
                <Tooltip content="Actual compliance (on-time deliveries / total)" />
              </div>
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('deviation')}
            >
              <div className="flex items-center justify-end gap-1">
                Deviation <SortIcon field="deviation" />
                <Tooltip content="Difference: Actual % - Standard %" />
              </div>
            </th>
            <th
              className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('status')}
            >
              <div className="flex items-center justify-center gap-1">
                Status <SortIcon field="status" />
                <Tooltip content="Compliant / Warning / Critical" />
              </div>
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('inboundPercentage')}
            >
              <div className="flex items-center justify-end gap-1">
                Inbound % <SortIcon field="inboundPercentage" />
                <Tooltip content="Compliance for arrivals (city as destination)" />
              </div>
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('outboundPercentage')}
            >
              <div className="flex items-center justify-end gap-1">
                Outbound % <SortIcon field="outboundPercentage" />
                <Tooltip content="Compliance for departures (city as origin)" />
              </div>
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('directionGap')}
            >
              <div className="flex items-center justify-end gap-1">
                Direction Gap <SortIcon field="directionGap" />
                <Tooltip content="Absolute difference: |Inbound % - Outbound %|" />
              </div>
            </th>
          </tr>
        </thead>
        <tbody className="bg-white divide-y divide-gray-200">
          {sortedData.map((city) => (
            <>
            <tr key={city.cityId} className="hover:bg-gray-50">
              <td className="px-4 py-3 whitespace-nowrap text-center">
                {city.carrierProductBreakdown && city.carrierProductBreakdown.length > 0 && (
                  <button
                    onClick={() => toggleRow(city.cityId)}
                    className="text-gray-500 hover:text-gray-700"
                  >
                    {expandedRows.has(city.cityId) ? (
                      <ChevronUp className="w-4 h-4" />
                    ) : (
                      <ChevronDown className="w-4 h-4" />
                    )}
                  </button>
                )}
              </td>
              <td className="px-4 py-3 whitespace-nowrap">
                <button
                  onClick={() => onCityClick?.(city)}
                  className="text-blue-600 hover:text-blue-800 hover:underline font-medium text-left"
                >
                  {city.cityName}
                </button>
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-gray-500">
                {city.regionName || '-'}
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-gray-700">
                {city.classification || '-'}
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                {city.population ? city.population.toLocaleString() : '-'}
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                {city.totalShipments}
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                {city.standardPercentage.toFixed(1)}%
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                {city.actualPercentage.toFixed(1)}%
              </td>
              <td
                className={`px-4 py-3 whitespace-nowrap text-sm text-right font-medium ${
                  city.deviation >= 0 ? 'text-green-600' : 'text-red-600'
                }`}
              >
                {city.deviation >= 0 ? '+' : ''}
                {city.deviation.toFixed(1)}%
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-center text-lg">
                {getStatusIcon(city.status)}
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                {city.inboundPercentage.toFixed(1)}%
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                {city.outboundPercentage.toFixed(1)}%
              </td>
              <td
                className={`px-4 py-3 whitespace-nowrap text-sm text-right ${
                  city.directionGap > 15 ? 'text-amber-600 font-semibold' : 'text-gray-700'
                }`}
              >
                {city.directionGap.toFixed(1)}%
              </td>
            </tr>
            {expandedRows.has(city.cityId) && city.carrierProductBreakdown && city.carrierProductBreakdown.length > 0 && (
              <tr key={`${city.cityId}-breakdown`} className="bg-gray-50">
                <td colSpan={13} className="px-4 py-2">
                  <div className="ml-8">
                    <table className="min-w-full text-sm">
                      <thead>
                        <tr className="text-xs text-gray-500">
                          <th className="text-left py-1 px-2">Carrier</th>
                          <th className="text-left py-1 px-2">Product</th>
                          <th className="text-right py-1 px-2">Shipments</th>
                          <th className="text-right py-1 px-2">Compliant</th>
                          <th className="text-right py-1 px-2">Actual %</th>
                          <th className="text-right py-1 px-2">Standard %</th>
                          <th className="text-right py-1 px-2">Deviation</th>
                          <th className="text-right py-1 px-2">Inbound %</th>
                          <th className="text-right py-1 px-2">Outbound %</th>
                        </tr>
                      </thead>
                      <tbody>
                        {city.carrierProductBreakdown.map((cp, idx) => (
                          <tr key={idx} className="border-t border-gray-200">
                            <td className="py-1 px-2 text-gray-700">{cp.carrier}</td>
                            <td className="py-1 px-2 text-gray-700">{cp.product}</td>
                            <td className="py-1 px-2 text-right text-gray-700">{cp.totalShipments}</td>
                            <td className="py-1 px-2 text-right text-gray-700">{cp.compliantShipments}</td>
                            <td className="py-1 px-2 text-right text-gray-700">{cp.actualPercentage.toFixed(1)}%</td>
                            <td className="py-1 px-2 text-right text-gray-700">{cp.standardPercentage.toFixed(1)}%</td>
                            <td className={`py-1 px-2 text-right font-medium ${
                              cp.deviation >= 0 ? 'text-green-600' : 'text-red-600'
                            }`}>
                              {cp.deviation >= 0 ? '+' : ''}{cp.deviation.toFixed(1)}%
                            </td>
                            <td className="py-1 px-2 text-right text-blue-600">{cp.inboundPercentage.toFixed(1)}%</td>
                            <td className="py-1 px-2 text-right text-green-600">{cp.outboundPercentage.toFixed(1)}%</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </td>
              </tr>
            )}
            </>
          ))}
        </tbody>
      </table>
      {sortedData.length === 0 && (
        <div className="text-center py-8 text-gray-500">No data available</div>
      )}
    </div>
  );
}
