import React, { useState } from 'react';
import { ArrowUpDown, Download } from 'lucide-react';
import { downloadRouteSamples } from '@/utils/downloadRouteSamples';

interface RouteData {
  origin: string;
  destination: string;
  carrier: string;
  product: string;
  samples: number;
  standardDays: number;
  actualDays: number;
  standardPercentage: number;
  actualPercentage: number;
  status: 'compliant' | 'warning' | 'critical';
}

interface ComplianceRouteTableProps {
  data: RouteData[];
  warningThreshold: number;
  criticalThreshold: number;
}

export function ComplianceRouteTable({ data, warningThreshold, criticalThreshold }: ComplianceRouteTableProps) {
  const [sortField, setSortField] = useState<'route' | 'samples' | 'compliance'>('route');
  const [sortDirection, setSortDirection] = useState<'asc' | 'desc'>('asc');

  const sortedData = [...data].sort((a, b) => {
    let aVal, bVal;
    if (sortField === 'route') {
      aVal = `${a.origin}-${a.destination}`;
      bVal = `${b.origin}-${b.destination}`;
      return sortDirection === 'asc' ? aVal.localeCompare(bVal) : bVal.localeCompare(aVal);
    } else if (sortField === 'samples') {
      aVal = a.samples || 0;
      bVal = b.samples || 0;
    } else {
      aVal = a.actualPercentage || 0;
      bVal = b.actualPercentage || 0;
    }
    return sortDirection === 'asc' ? aVal - bVal : bVal - aVal;
  });

  const handleSort = (field: typeof sortField) => {
    if (sortField === field) {
      setSortDirection(sortDirection === 'asc' ? 'desc' : 'asc');
    } else {
      setSortField(field);
      setSortDirection('asc');
    }
  };

  const handleDownloadCSV = (route: RouteData) => {
    downloadRouteSamples({
      originCity: route.origin,
      destinationCity: route.destination,
      carrier: route.carrier,
      product: route.product,
    });
  };

  return (
    <div className="overflow-x-auto">
      <table className="min-w-full divide-y divide-gray-200">
        <thead className="bg-gray-50">
          <tr>
            <th 
              onClick={() => handleSort('route')}
              className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
            >
              <div className="flex items-center gap-1">
                Route
                <ArrowUpDown className="w-3 h-3" />
              </div>
            </th>
            <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Carrier</th>
            <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Product</th>
            <th 
              onClick={() => handleSort('samples')}
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
            >
              <div className="flex items-center justify-end gap-1">
                Samples
                <ArrowUpDown className="w-3 h-3" />
              </div>
            </th>
            <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">J+K STD</th>
            <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">J+K Actual</th>
            <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">STD %</th>
            <th 
              onClick={() => handleSort('compliance')}
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
            >
              <div className="flex items-center justify-end gap-1">
                Actual %
                <ArrowUpDown className="w-3 h-3" />
              </div>
            </th>
            <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Deviation</th>
            <th className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
            <th className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider">Actions</th>
          </tr>
        </thead>
        <tbody className="bg-white divide-y divide-gray-200">
          {sortedData.map((route, idx) => {
            const deviation = route.standardPercentage > 0 
              ? ((route.actualPercentage - route.standardPercentage) / route.standardPercentage * 100).toFixed(1)
              : '0.0';

            return (
              <tr key={idx} className="hover:bg-gray-50">
                <td className="px-4 py-3 whitespace-nowrap text-sm font-medium">
                  {route.origin} → {route.destination}
                </td>
                <td className="px-4 py-3 whitespace-nowrap text-sm text-gray-600">{route.carrier}</td>
                <td className="px-4 py-3 whitespace-nowrap text-sm text-gray-600">{route.product}</td>
                <td className="px-4 py-3 whitespace-nowrap text-sm text-right">{route.samples || 0}</td>
                <td className="px-4 py-3 whitespace-nowrap text-sm text-right">{route.standardDays?.toFixed(1)}</td>
                <td className="px-4 py-3 whitespace-nowrap text-sm text-right">{route.actualDays?.toFixed(1)}</td>
                <td className="px-4 py-3 whitespace-nowrap text-sm text-right">{route.standardPercentage?.toFixed(1)}%</td>
                <td className={`px-4 py-3 whitespace-nowrap text-sm text-right font-medium ${
                  route.status === 'compliant' ? 'text-green-600' :
                  route.status === 'warning' ? 'text-amber-600' : 'text-red-600'
                }`}>
                  {route.actualPercentage?.toFixed(1)}%
                </td>
                <td className={`px-4 py-3 whitespace-nowrap text-sm text-right ${
                  parseFloat(deviation) < 0 ? 'text-red-600' : 'text-gray-600'
                }`}>
                  {deviation}%
                </td>
                <td className="px-4 py-3 whitespace-nowrap text-center">
                  <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${
                    route.status === 'compliant' ? 'bg-green-100 text-green-800' :
                    route.status === 'warning' ? 'bg-yellow-100 text-yellow-800' :
                    'bg-red-100 text-red-800'
                  }`}>
                    {route.status}
                  </span>
                </td>
                <td className="px-4 py-3 whitespace-nowrap text-center">
                  <button
                    onClick={() => handleDownloadCSV(route)}
                    className="text-blue-600 hover:text-blue-800"
                    title="Download samples CSV"
                  >
                    <Download className="w-4 h-4" />
                  </button>
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
      {sortedData.length === 0 && (
        <div className="text-center py-8 text-gray-500">
          No route data available
        </div>
      )}
    </div>
  );
}
