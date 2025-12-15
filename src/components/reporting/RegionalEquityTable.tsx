import { useState } from 'react';
import { ChevronDown, ChevronUp, ArrowDown, ArrowUp } from 'lucide-react';
import type { RegionEquityData } from '@/types/reporting';

interface RegionalEquityTableProps {
  data: RegionEquityData[];
  onRegionClick?: (region: RegionEquityData) => void;
}

type DirectionRow = {
  regionId: string;
  regionName: string;
  direction: 'inbound' | 'outbound';
  totalCities: number;
  totalPopulation: number;
  shipments: number;
  compliant: number;
  standardPercentage: number;
  actualPercentage: number;
  standardDays: number;
  actualDays: number;
  deviation: number;
  status: 'compliant' | 'warning' | 'critical';
  underservedCitiesCount: number;
  originalRegion: RegionEquityData;
};

export function RegionalEquityTable({ data, onRegionClick }: RegionalEquityTableProps) {
  const [sortField, setSortField] = useState<keyof DirectionRow>('deviation');
  const [sortDirection, setSortDirection] = useState<'asc' | 'desc'>('asc');

  // Convert each region into two rows (inbound + outbound)
  const directionRows: DirectionRow[] = data.flatMap((region) => [
    {
      regionId: `${region.regionId}-inbound`,
      regionName: region.regionName,
      direction: 'inbound' as const,
      totalCities: region.totalCities,
      totalPopulation: region.totalPopulation,
      shipments: Math.round(region.totalShipments * (region.inboundPercentage / 100)), // Approximate
      compliant: region.compliantShipments,
      standardPercentage: region.inboundStandardPercentage,
      actualPercentage: region.inboundPercentage,
      standardDays: region.inboundStandardDays,
      actualDays: region.inboundActualDays,
      deviation: region.inboundDeviation,
      status: region.inboundDeviation >= 0 ? 'compliant' : (region.inboundPercentage < 80 ? 'critical' : 'warning'),
      underservedCitiesCount: region.underservedCitiesCount,
      originalRegion: region,
    },
    {
      regionId: `${region.regionId}-outbound`,
      regionName: region.regionName,
      direction: 'outbound' as const,
      totalCities: region.totalCities,
      totalPopulation: region.totalPopulation,
      shipments: Math.round(region.totalShipments * (region.outboundPercentage / 100)), // Approximate
      compliant: region.compliantShipments,
      standardPercentage: region.outboundStandardPercentage,
      actualPercentage: region.outboundPercentage,
      standardDays: region.outboundStandardDays,
      actualDays: region.outboundActualDays,
      deviation: region.outboundDeviation,
      status: region.outboundDeviation >= 0 ? 'compliant' : (region.outboundPercentage < 80 ? 'critical' : 'warning'),
      underservedCitiesCount: region.underservedCitiesCount,
      originalRegion: region,
    },
  ]);

  const handleSort = (field: keyof DirectionRow) => {
    if (sortField === field) {
      setSortDirection(sortDirection === 'asc' ? 'desc' : 'asc');
    } else {
      setSortField(field);
      setSortDirection('asc');
    }
  };

  const sortedData = [...directionRows].sort((a, b) => {
    const aVal = a[sortField];
    const bVal = b[sortField];
    const multiplier = sortDirection === 'asc' ? 1 : -1;

    if (typeof aVal === 'number' && typeof bVal === 'number') {
      return (aVal - bVal) * multiplier;
    }
    return String(aVal || '').localeCompare(String(bVal || '')) * multiplier;
  });

  const SortIcon = ({ field }: { field: keyof DirectionRow }) => {
    if (sortField !== field) return null;
    return sortDirection === 'asc' ? (
      <ChevronUp className="w-4 h-4 inline ml-1" />
    ) : (
      <ChevronDown className="w-4 h-4 inline ml-1" />
    );
  };

  const getStatusIcon = (status: 'compliant' | 'warning' | 'critical') => {
    switch (status) {
      case 'compliant':
        return <span className="text-green-500">●</span>;
      case 'warning':
        return <span className="text-amber-500">●</span>;
      case 'critical':
        return <span className="text-red-500">●</span>;
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
              className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('direction')}
            >
              Direction <SortIcon field="direction" />
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
              onClick={() => handleSort('shipments')}
            >
              Total Shipments <SortIcon field="shipments" />
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
              onClick={() => handleSort('standardDays')}
            >
              J+K Std <SortIcon field="standardDays" />
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('actualDays')}
            >
              J+K Actual <SortIcon field="actualDays" />
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('deviation')}
            >
              Deviation <SortIcon field="deviation" />
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
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
          {sortedData.map((row) => (
            <tr key={row.regionId} className="hover:bg-gray-50">
              <td className="px-4 py-3 whitespace-nowrap font-medium text-gray-900">
                {onRegionClick ? (
                  <button
                    onClick={() => onRegionClick(row.originalRegion)}
                    className="text-blue-600 hover:text-blue-800 hover:underline cursor-pointer"
                  >
                    {row.regionName}
                  </button>
                ) : (
                  row.regionName
                )}
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm">
                <div className="flex items-center gap-1">
                  {row.direction === 'inbound' ? (
                    <>
                      <ArrowDown className="w-4 h-4 text-blue-600" />
                      <span className="text-blue-600 font-medium">Inbound</span>
                    </>
                  ) : (
                    <>
                      <ArrowUp className="w-4 h-4 text-green-600" />
                      <span className="text-green-600 font-medium">Outbound</span>
                    </>
                  )}
                </div>
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                {row.totalCities}
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                {row.totalPopulation.toLocaleString()}
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                {row.shipments}
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                {(row.standardPercentage || 0).toFixed(1)}%
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                {(row.actualPercentage || 0).toFixed(1)}%
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                {(row.standardDays || 0).toFixed(1)}
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                {(row.actualDays || 0).toFixed(1)}
              </td>
              <td
                className={`px-4 py-3 whitespace-nowrap text-sm text-right font-medium ${
                  row.deviation >= 0 ? 'text-green-600' : 'text-red-600'
                }`}
              >
                {row.deviation >= 0 ? '+' : ''}
                {row.deviation.toFixed(1)}%
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-center text-lg">
                {getStatusIcon(row.status)}
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                {row.underservedCitiesCount}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      {sortedData.length === 0 && (
        <div className="text-center py-8 text-gray-500">No data available</div>
      )}
    </div>
  );
}
