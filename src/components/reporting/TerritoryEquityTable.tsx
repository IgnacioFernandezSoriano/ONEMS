import { useState } from 'react';
import { ChevronDown, ChevronUp, ArrowDown, ArrowUp } from 'lucide-react';
import type { CityEquityData } from '@/types/reporting';

interface TerritoryEquityTableProps {
  data: CityEquityData[];
  onCityClick?: (city: CityEquityData) => void;
}

type DirectionRow = {
  cityId: string;
  cityName: string;
  direction: 'inbound' | 'outbound';
  regionName: string | null;
  classification: string | null;
  population: number | null;
  shipments: number;
  compliant: number;
  standardPercentage: number;
  actualPercentage: number;
  standardDays: number;
  actualDays: number;
  deviation: number;
  status: 'compliant' | 'warning' | 'critical';
  originalCity: CityEquityData;
};

export function TerritoryEquityTable({ data, onCityClick }: TerritoryEquityTableProps) {
  const [sortField, setSortField] = useState<keyof DirectionRow>('deviation');
  const [sortDirection, setSortDirection] = useState<'asc' | 'desc'>('asc');

  // Convert each city into two rows (inbound + outbound)
  const directionRows: DirectionRow[] = data.flatMap((city) => [
    {
      cityId: `${city.cityId}-inbound`,
      cityName: city.cityName,
      direction: 'inbound' as const,
      regionName: city.regionName,
      classification: city.classification,
      population: city.population,
      shipments: city.inboundShipments,
      compliant: city.inboundCompliant,
      standardPercentage: city.inboundStandardPercentage,
      actualPercentage: city.inboundPercentage,
      standardDays: city.inboundStandardDays,
      actualDays: city.inboundActualDays,
      deviation: city.inboundDeviation,
      status: city.inboundDeviation >= 0 ? 'compliant' : (city.inboundPercentage < 80 ? 'critical' : 'warning'),
      originalCity: city,
    },
    {
      cityId: `${city.cityId}-outbound`,
      cityName: city.cityName,
      direction: 'outbound' as const,
      regionName: city.regionName,
      classification: city.classification,
      population: city.population,
      shipments: city.outboundShipments,
      compliant: city.outboundCompliant,
      standardPercentage: city.outboundStandardPercentage,
      actualPercentage: city.outboundPercentage,
      standardDays: city.outboundStandardDays,
      actualDays: city.outboundActualDays,
      deviation: city.outboundDeviation,
      status: city.outboundDeviation >= 0 ? 'compliant' : (city.outboundPercentage < 80 ? 'critical' : 'warning'),
      originalCity: city,
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
              onClick={() => handleSort('cityName')}
            >
              City <SortIcon field="cityName" />
            </th>
            <th
              className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('direction')}
            >
              Direction <SortIcon field="direction" />
            </th>
            <th
              className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('regionName')}
            >
              Region <SortIcon field="regionName" />
            </th>
            <th
              className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('classification')}
            >
              Class <SortIcon field="classification" />
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('population')}
            >
              Population <SortIcon field="population" />
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('shipments')}
            >
                Total <SortIcon field="shipments" />
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
              className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('status')}
            >
                Status <SortIcon field="status" />
            </th>
          </tr>
        </thead>
        <tbody className="bg-white divide-y divide-gray-200">
          {sortedData.map((row) => (
            <tr key={row.cityId} className="hover:bg-gray-50">
              <td className="px-4 py-3 whitespace-nowrap">
                <button
                  onClick={() => onCityClick?.(row.originalCity)}
                  className="text-blue-600 hover:text-blue-800 hover:underline font-medium text-left"
                >
                  {row.cityName}
                </button>
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
              <td className="px-4 py-3 whitespace-nowrap text-sm text-gray-500">
                {row.regionName || '-'}
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-gray-700">
                {row.classification || '-'}
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                {row.population ? row.population.toLocaleString() : '-'}
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                {row.shipments}
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                {row.standardPercentage.toFixed(1)}%
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                {row.actualPercentage.toFixed(1)}%
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                {row.standardDays.toFixed(1)}
              </td>
              <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                {row.actualDays.toFixed(1)}
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
