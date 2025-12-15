import { useState } from 'react';
import { ChevronDown, ChevronUp } from 'lucide-react';
import type { RegionEquityData } from '@/types/reporting';

interface RegionalEquityTableProps {
  data: RegionEquityData[];
  onRegionClick?: (region: RegionEquityData) => void;
}

export function RegionalEquityTable({ data, onRegionClick }: RegionalEquityTableProps) {
  const [sortField, setSortField] = useState<keyof RegionEquityData>('deviation');
  const [sortDirection, setSortDirection] = useState<'asc' | 'desc'>('asc');

  const handleSort = (field: keyof RegionEquityData) => {
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

  const SortIcon = ({ field }: { field: keyof RegionEquityData }) => {
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

  return (
    <div className="overflow-x-auto">
      <table className="min-w-full divide-y divide-gray-200">
        <thead className="bg-gray-50">
          <tr>
            <th
              className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('regionName')}
            >
              Region <SortIcon field="regionName" />
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('totalCities')}
            >
              Cities <SortIcon field="totalCities" />
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('totalPopulation')}
            >
              Population <SortIcon field="totalPopulation" />
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('totalShipments')}
            >
              Total Shipments <SortIcon field="totalShipments" />
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('standardPercentage')}
            >
              Standard % <SortIcon field="standardPercentage" />
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('actualPercentage')}
            >
              Actual % <SortIcon field="actualPercentage" />
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('deviation')}
            >
              Deviation <SortIcon field="deviation" />
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('inboundPercentage')}
            >
              Inbound % <SortIcon field="inboundPercentage" />
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('outboundPercentage')}
            >
              Outbound % <SortIcon field="outboundPercentage" />
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('directionGap')}
            >
              Direction Gap <SortIcon field="directionGap" />
            </th>
            <th
              className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('status')}
            >
              Status <SortIcon field="status" />
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('underservedCitiesCount')}
            >
              Underserved Cities <SortIcon field="underservedCitiesCount" />
            </th>
          </tr>
        </thead>
        <tbody className="bg-white divide-y divide-gray-200">
          {sortedData.map((region) => (
            <tr key={region.regionId} className="hover:bg-gray-50">
              <td className="px-4 py-3 whitespace-nowrap font-medium text-gray-900">
                {onRegionClick ? (
                  <button
                    onClick={() => onRegionClick(region)}
                    className="text-blue-600 hover:text-blue-800 hover:underline cursor-pointer"
                  >
                    {region.regionName}
                  </button>
                ) : (
                  region.regionName
                )}
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                {region.totalCities}
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                {region.totalPopulation.toLocaleString()}
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                {region.totalShipments}
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                {(region.standardPercentage || 0).toFixed(1)}%
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                {(region.actualPercentage || 0).toFixed(1)}%
              </td>
              <td
                className={`px-4 py-3 whitespace-nowrap text-sm text-right font-medium ${
                  region.deviation >= 0 ? 'text-green-600' : 'text-red-600'
                }`}
              >
                {(region.deviation || 0) >= 0 ? '+' : ''}
                {(region.deviation || 0).toFixed(1)}%
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                {(region.inboundPercentage || 0).toFixed(1)}%
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                {(region.outboundPercentage || 0).toFixed(1)}%
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                {(region.directionGap || 0).toFixed(1)}%
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-center text-lg">
                {getStatusIcon(region.status)}
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                {region.underservedCitiesCount}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      {sortedData.length === 0 && (
        <div className="text-center py-8 text-gray-500">No regional data available</div>
      )}
    </div>
  );
}
