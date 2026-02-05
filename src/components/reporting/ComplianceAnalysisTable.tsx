import React, { useState, useMemo } from 'react';
import { ArrowUpDown, Download } from 'lucide-react';
import { downloadRouteSamples } from '@/utils/downloadRouteSamples';

interface RouteData {
  carrier?: string;
  product?: string;
  origin?: string;
  destination?: string;
  samples?: number;
  standardDays?: number;
  actualDays?: number;
  standardPercentage?: number;
  actualPercentage?: number;
  status?: 'compliant' | 'warning' | 'critical';
}

interface ComplianceAnalysisTableProps {
  data: RouteData[];
  warningThreshold?: number;
  criticalThreshold?: number;
}

export function ComplianceAnalysisTable({ data, warningThreshold = 85, criticalThreshold = 75 }: ComplianceAnalysisTableProps) {
  const [sortField, setSortField] = useState<keyof RouteData>('status');
  const [sortDirection, setSortDirection] = useState<'asc' | 'desc'>('asc');

  const sortedData = useMemo(() => {
    return [...data].sort((a, b) => {
      // Status priority: critical > warning > compliant
      if (sortField === 'status') {
        const statusOrder = { critical: 0, warning: 1, compliant: 2 };
        const aOrder = statusOrder[a.status || 'compliant'];
        const bOrder = statusOrder[b.status || 'compliant'];
        return sortDirection === 'asc' ? aOrder - bOrder : bOrder - aOrder;
      }

      const aVal = a[sortField];
      const bVal = b[sortField];
      
      if (typeof aVal === 'number' && typeof bVal === 'number') {
        return sortDirection === 'asc' ? aVal - bVal : bVal - aVal;
      }
      
      const aStr = String(aVal || '');
      const bStr = String(bVal || '');
      return sortDirection === 'asc' 
        ? aStr.localeCompare(bStr)
        : bStr.localeCompare(aStr);
    });
  }, [data, sortField, sortDirection]);

  const handleSort = (field: keyof RouteData) => {
    if (sortField === field) {
      setSortDirection(sortDirection === 'asc' ? 'desc' : 'asc');
    } else {
      setSortField(field);
      setSortDirection('asc');
    }
  };

  const handleDownloadSamples = async (route: RouteData) => {
    if (!route.origin || !route.destination || !route.carrier || !route.product) return;
    
    try {
      await downloadRouteSamples({
        originCity: route.origin,
        destinationCity: route.destination,
        carrier: route.carrier,
        product: route.product
      });
    } catch (error) {
      console.error('Failed to download samples:', error);
      alert('Failed to download samples. Please try again.');
    }
  };

  return (
    <div className="overflow-x-auto">
      <table className="min-w-full divide-y divide-gray-200">
        <thead className="bg-gray-50 sticky top-0">
          <tr>
            <th 
              onClick={() => handleSort('origin')}
              className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
            >
              <div className="flex items-center gap-1">
                Origin
                <ArrowUpDown className="w-3 h-3" />
              </div>
            </th>
            <th 
              onClick={() => handleSort('destination')}
              className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
            >
              <div className="flex items-center gap-1">
                Destination
                <ArrowUpDown className="w-3 h-3" />
              </div>
            </th>
            <th 
              onClick={() => handleSort('carrier')}
              className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
            >
              <div className="flex items-center gap-1">
                Carrier
                <ArrowUpDown className="w-3 h-3" />
              </div>
            </th>
            <th 
              onClick={() => handleSort('product')}
              className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
            >
              <div className="flex items-center gap-1">
                Product
                <ArrowUpDown className="w-3 h-3" />
              </div>
            </th>
            <th 
              onClick={() => handleSort('samples')}
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
            >
              <div className="flex items-center justify-end gap-1">
                Samples
                <ArrowUpDown className="w-3 h-3" />
              </div>
            </th>
            <th 
              onClick={() => handleSort('standardDays')}
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
            >
              <div className="flex items-center justify-end gap-1">
                J+K STD
                <ArrowUpDown className="w-3 h-3" />
              </div>
            </th>
            <th 
              onClick={() => handleSort('actualDays')}
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
            >
              <div className="flex items-center justify-end gap-1">
                J+K Actual
                <ArrowUpDown className="w-3 h-3" />
              </div>
            </th>
            <th 
              onClick={() => handleSort('standardPercentage')}
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
            >
              <div className="flex items-center justify-end gap-1">
                STD %
                <ArrowUpDown className="w-3 h-3" />
              </div>
            </th>
            <th 
              onClick={() => handleSort('actualPercentage')}
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
            >
              <div className="flex items-center justify-end gap-1">
                Actual %
                <ArrowUpDown className="w-3 h-3" />
              </div>
            </th>
            <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
              Deviation
            </th>
            <th 
              onClick={() => handleSort('status')}
              className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
            >
              <div className="flex items-center gap-1">
                Status
                <ArrowUpDown className="w-3 h-3" />
              </div>
            </th>
            <th className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider">
              Actions
            </th>
          </tr>
        </thead>
        <tbody className="bg-white divide-y divide-gray-200">
          {sortedData.map((row, idx) => {
            const deviation = row.standardPercentage && row.actualPercentage
              ? ((row.actualPercentage - row.standardPercentage) / row.standardPercentage * 100)
              : 0;

            return (
              <tr key={idx} className="hover:bg-gray-50">
                <td className="px-4 py-3 whitespace-nowrap text-sm">{row.origin || '-'}</td>
                <td className="px-4 py-3 whitespace-nowrap text-sm">{row.destination || '-'}</td>
                <td className="px-4 py-3 whitespace-nowrap text-sm">{row.carrier || '-'}</td>
                <td className="px-4 py-3 whitespace-nowrap text-sm">{row.product || '-'}</td>
                <td className="px-4 py-3 whitespace-nowrap text-sm text-right">{row.samples || 0}</td>
                <td className="px-4 py-3 whitespace-nowrap text-sm text-right">{row.standardDays?.toFixed(1) || '-'}</td>
                <td className="px-4 py-3 whitespace-nowrap text-sm text-right">{row.actualDays?.toFixed(1) || '-'}</td>
                <td className="px-4 py-3 whitespace-nowrap text-sm text-right">{row.standardPercentage?.toFixed(1) || '-'}%</td>
                <td className="px-4 py-3 whitespace-nowrap text-sm text-right">{row.actualPercentage?.toFixed(1) || '-'}%</td>
                <td className={`px-4 py-3 whitespace-nowrap text-sm text-right font-medium ${
                  deviation >= 0 ? 'text-green-600' : 'text-red-600'
                }`}>
                  {deviation >= 0 ? '+' : ''}{deviation.toFixed(1)}%
                </td>
                <td className="px-4 py-3 whitespace-nowrap">
                  <span className={`inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-xs font-medium ${
                    row.status === 'compliant' ? 'bg-green-100 text-green-800' :
                    row.status === 'warning' ? 'bg-yellow-100 text-yellow-800' :
                    'bg-red-100 text-red-800'
                  }`}>
                    {row.status === 'compliant' ? '✅' : row.status === 'warning' ? '⚠️' : '🔴'}
                    <span className="capitalize">{row.status}</span>
                  </span>
                </td>
                <td className="px-4 py-3 whitespace-nowrap text-center">
                  <button
                    onClick={() => handleDownloadSamples(row)}
                    className="inline-flex items-center gap-1 px-2 py-1 text-xs bg-blue-600 hover:bg-blue-700 text-white rounded transition-colors"
                    title="Download samples CSV"
                  >
                    <Download className="w-3 h-3" />
                    CSV
                  </button>
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
      {sortedData.length === 0 && (
        <div className="text-center py-8 text-gray-500">
          No compliance data available
        </div>
      )}
    </div>
  );
}
