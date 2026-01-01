import { useState } from 'react';
import { ChevronDown, ChevronUp, ArrowDown, ArrowUp } from 'lucide-react';
import type { RegionEquityData } from '@/types/reporting';

import { useTranslation } from '@/hooks/useTranslation';
interface RegionalEquityTableProps {
  data: RegionEquityData[];
  onRegionClick?: (region: RegionEquityData) => void;
}

type DirectionRow = {
  regionId: string;
  regionName: string;
  direction: 'inbound' | 'outbound';
  totalCities: number;
  totalPopulation: number | null;
  shipments: number;
  compliant: number;
  standardPercentage: number;
  actualPercentage: number;
  deviation: number;
  standardDays: number;
  actualDays: number;
  status: 'compliant' | 'warning' | 'critical';
  underservedCitiesCount: number;
  originalRegion: RegionEquityData;
};

export function RegionalEquityTable({ data, onRegionClick }: RegionalEquityTableProps) {
  const { t } = useTranslation();
  const [sortField, setSortField] = useState<keyof DirectionRow>('regionName');
  const [sortDirection, setSortDirection] = useState<'asc' | 'desc'>('asc');
  const [expandedRows, setExpandedRows] = useState<Set<string>>(new Set());

  const toggleRow = (rowId: string) => {
    const newExpanded = new Set(expandedRows);
    if (newExpanded.has(rowId)) {
      newExpanded.delete(rowId);
    } else {
      newExpanded.add(rowId);
    }
    setExpandedRows(newExpanded);
  };

  // Convert each region into two rows (inbound + outbound)
  const directionRows: DirectionRow[] = data.flatMap((region) => [
    {
      regionId: `${region.regionName}-inbound`,
      regionName: region.regionName,
      direction: 'inbound' as const,
      totalCities: region.totalCities,
      totalPopulation: region.totalPopulation,
      shipments: region.inboundShipments,
      compliant: region.inboundCompliant,
      standardPercentage: region.inboundStandardPercentage,
      actualPercentage: region.inboundPercentage,
      deviation: region.inboundDeviation,
      standardDays: region.inboundStandardDays,
      actualDays: region.inboundActualDays,
      status: region.inboundDeviation >= 0 ? 'compliant' : (region.inboundPercentage < 80 ? 'critical' : 'warning'),
      underservedCitiesCount: region.underservedCitiesCount,
      originalRegion: region,
    },
    {
      regionId: `${region.regionName}-outbound`,
      regionName: region.regionName,
      direction: 'outbound' as const,
      totalCities: region.totalCities,
      totalPopulation: region.totalPopulation,
      shipments: region.outboundShipments,
      compliant: region.outboundCompliant,
      standardPercentage: region.outboundStandardPercentage,
      actualPercentage: region.outboundPercentage,
      deviation: region.outboundDeviation,
      standardDays: region.outboundStandardDays,
      actualDays: region.outboundActualDays,
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
    // First, sort by the selected field
    const aVal = a[sortField];
    const bVal = b[sortField];
    const multiplier = sortDirection === 'asc' ? 1 : -1;

    let comparison = 0;
    if (typeof aVal === 'number' && typeof bVal === 'number') {
      comparison = (aVal - bVal) * multiplier;
    } else {
      comparison = String(aVal || '').localeCompare(String(bVal || '')) * multiplier;
    }

    // If values are equal (especially for regionName), sort by direction (inbound first)
    if (comparison === 0) {
      return a.direction === 'inbound' ? -1 : 1;
    }

    return comparison;
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
            <th className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider">
              {/* Expand button column */}
            </th>
            <th
              className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('regionName')}
            >
              {t('reporting.region')} <SortIcon field="regionName" />
            </th>
            <th
              className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('direction')}
            >
              {t('reporting.direction')} <SortIcon field="direction" />
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('totalCities')}
            >
              {t('reporting.cities')} <SortIcon field="totalCities" />
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('totalPopulation')}
            >
              {t('reporting.population')} <SortIcon field="totalPopulation" />
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('shipments')}
            >
              {t('common.total')} <SortIcon field="shipments" />
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('standardPercentage')}
            >
              {t('reporting.standard_percent')} <SortIcon field="standardPercentage" />
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('actualPercentage')}
            >
              {t('reporting.actual_percent')} <SortIcon field="actualPercentage" />
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('deviation')}
            >
              {t('reporting.deviation')} <SortIcon field="deviation" />
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('standardDays')}
            >
              {t('reporting.jk_std')} <SortIcon field="standardDays" />
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('actualDays')}
            >
              {t('reporting.jk_actual')} <SortIcon field="actualDays" />
            </th>
            <th
              className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('status')}
            >
              {t('common.status')} <SortIcon field="status" />
            </th>
            <th
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
              onClick={() => handleSort('underservedCitiesCount')}
            >
              {t('reporting.underserved')} <SortIcon field="underservedCitiesCount" />
            </th>
          </tr>
        </thead>
        <tbody className="bg-white divide-y divide-gray-200">
          {sortedData.map((row) => {
            const hasBreakdown = row.originalRegion.carrierProductBreakdown && row.originalRegion.carrierProductBreakdown.length > 0;
            const isExpanded = expandedRows.has(row.regionId);
            
            return (
              <>
                <tr key={row.regionId} className="hover:bg-gray-50">
                  <td className="px-4 py-3 whitespace-nowrap text-center">
                    {hasBreakdown && (
                      <button
                        onClick={() => toggleRow(row.regionId)}
                        className="text-gray-500 hover:text-gray-700"
                      >
                        {isExpanded ? (
                          <ChevronUp className="w-4 h-4" />
                        ) : (
                          <ChevronDown className="w-4 h-4" />
                        )}
                      </button>
                    )}
                  </td>
                  <td className="px-4 py-3 whitespace-nowrap">
                    <button
                      onClick={() => onRegionClick?.(row.originalRegion)}
                      className="text-blue-600 hover:text-blue-800 hover:underline font-medium text-left"
                    >
                      {row.regionName}
                    </button>
                  </td>
                  <td className="px-4 py-3 whitespace-nowrap text-sm">
                    <div className="flex items-center gap-1">
                      {row.direction === 'inbound' ? (
                        <>
                          <ArrowDown className="w-4 h-4 text-blue-600" />
                          <span className="text-blue-600 font-medium">{t('reporting.inbound_direction')}</span>
                        </>
                      ) : (
                        <>
                          <ArrowUp className="w-4 h-4 text-green-600" />
                          <span className="text-green-600 font-medium">{t('reporting.outbound_direction')}</span>
                        </>
                      )}
                    </div>
                  </td>
                  <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                    {row.totalCities}
                  </td>
                  <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                    {row.totalPopulation ? row.totalPopulation.toLocaleString() : '-'}
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
                  <td
                    className={`px-4 py-3 whitespace-nowrap text-sm text-right font-medium ${
                      row.deviation >= 0 ? 'text-green-600' : 'text-red-600'
                    }`}
                  >
                    {row.deviation >= 0 ? '+' : ''}
                    {row.deviation.toFixed(1)}%
                  </td>
                  <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                    {row.standardDays.toFixed(1)}
                  </td>
                  <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                    {row.actualDays.toFixed(1)}
                  </td>
                  <td className="px-4 py-3 whitespace-nowrap text-center text-lg">
                    {getStatusIcon(row.status)}
                  </td>
                  <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                    {row.underservedCitiesCount}
                  </td>
                </tr>
                
                {/* Carrier/Product Breakdown Subrows */}
                {isExpanded && hasBreakdown && (
                  <tr key={`${row.regionId}-breakdown`} className="bg-gray-50">
                    <td colSpan={13} className="px-4 py-2">
                      <div className="ml-8">
                        <table className="min-w-full text-sm">
                          <thead>
                            <tr className="text-xs text-gray-500 uppercase">
                              <th className="px-3 py-2 text-left">{t('reporting.carrier')}</th>
                              <th className="px-3 py-2 text-left">{t('reporting.product')}</th>
                              <th className="px-3 py-2 text-right">{t('stock.shipments')}</th>
                              <th className="px-3 py-2 text-right">Compliant</th>
                              <th className="px-3 py-2 text-right">Standard %</th>
                              <th className="px-3 py-2 text-right">Actual %</th>
                              <th className="px-3 py-2 text-right">{t('reporting.deviation')}</th>
                              <th className="px-3 py-2 text-right">J+K Std</th>
                              <th className="px-3 py-2 text-right">J+K Actual</th>
                            </tr>
                          </thead>
                          <tbody>
                            {row.originalRegion.carrierProductBreakdown
                              ?.filter(cp => {
                                // Filter by direction
                                if (row.direction === 'inbound') {
                                  return cp.inboundPercentage > 0;
                                } else {
                                  return cp.outboundPercentage > 0;
                                }
                              })
                              .map((cp, idx) => (
                                <tr key={idx} className="border-t border-gray-200">
                                  <td className="px-3 py-2 text-gray-700">{cp.carrier}</td>
                                  <td className="px-3 py-2 text-gray-700">{cp.product}</td>
                                  <td className="px-3 py-2 text-right text-gray-700">{cp.totalShipments}</td>
                                  <td className="px-3 py-2 text-right text-gray-700">{cp.compliantShipments}</td>
                                  <td className="px-3 py-2 text-right text-gray-700">{cp.standardPercentage.toFixed(1)}%</td>
                                  <td className="px-3 py-2 text-right text-gray-700">{cp.actualPercentage.toFixed(1)}%</td>
                                  <td className={`px-3 py-2 text-right font-medium ${cp.deviation >= 0 ? 'text-green-600' : 'text-red-600'}`}>
                                    {cp.deviation >= 0 ? '+' : ''}{cp.deviation.toFixed(1)}%
                                  </td>
                                  <td className="px-3 py-2 text-right text-gray-700">{cp.standardDays.toFixed(1)}</td>
                                  <td className="px-3 py-2 text-right text-gray-700">{cp.actualDays.toFixed(1)}</td>
                                </tr>
                              ))}
                          </tbody>
                        </table>
                      </div>
                    </td>
                  </tr>
                )}
              </>
            );
          })}
        </tbody>
      </table>
      {sortedData.length === 0 && (
        <div className="text-center py-8 text-gray-500">No data available</div>
      )}
    </div>
  );
}
