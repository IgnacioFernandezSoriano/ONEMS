import { useState, useMemo } from 'react';
import { Download, AlertCircle } from 'lucide-react';
import type { CityEquityData } from '@/types/reporting';
import { useTranslation } from '@/hooks/useTranslation';

interface ProductAnalysisTableProps {
  routeData: any[];
  globalWarningThreshold: number;
  globalCriticalThreshold: number;
}

type ProductRow = {
  origin: string;
  destination: string;
  carrier: string;
  product: string;
  totalShipments: number;
  standardDays?: number;
  actualDays?: number;
  standardPercentage: number;
  actualPercentage: number;
  deviation: number;
  status: 'compliant' | 'warning' | 'critical';
};

export function ProductAnalysisTable({
  routeData,
  globalWarningThreshold,
  globalCriticalThreshold,
}: ProductAnalysisTableProps) {
  const { t } = useTranslation();
  const [equityStatusFilter, setEquityStatusFilter] = useState<string[]>(['warning', 'critical']);
  const [sortField, setSortField] = useState<keyof ProductRow>('origin');
  const [sortDirection, setSortDirection] = useState<'asc' | 'desc'>('asc');

  // Use route data directly
  const productRows: ProductRow[] = useMemo(() => {
    return routeData.map(route => ({
      origin: route.origin,
      destination: route.destination,
      carrier: route.carrier,
      product: route.product,
      totalShipments: route.totalShipments,
      standardDays: route.standardDays,
      actualDays: route.actualDays,
      standardPercentage: route.standardPercentage,
      actualPercentage: route.actualPercentage,
      deviation: route.deviation,
      status: route.status,
    }));
  }, [routeData]);

  // Filter by equity status
  const filteredRows = useMemo(() => {
    if (equityStatusFilter.length === 0) return productRows;
    return productRows.filter(row => equityStatusFilter.includes(row.status));
  }, [productRows, equityStatusFilter]);

  // Sort rows
  const sortedRows = useMemo(() => {
    return [...filteredRows].sort((a, b) => {
      const aVal = a[sortField];
      const bVal = b[sortField];
      
      if (typeof aVal === 'number' && typeof bVal === 'number') {
        return sortDirection === 'asc' ? aVal - bVal : bVal - aVal;
      }
      
      const aStr = String(aVal);
      const bStr = String(bVal);
      return sortDirection === 'asc' 
        ? aStr.localeCompare(bStr)
        : bStr.localeCompare(aStr);
    });
  }, [filteredRows, sortField, sortDirection]);

  const handleSort = (field: keyof ProductRow) => {
    if (sortField === field) {
      setSortDirection(sortDirection === 'asc' ? 'desc' : 'asc');
    } else {
      setSortField(field);
      setSortDirection('asc');
    }
  };

  const handleExportCSV = () => {
    const headers = ['Origin', 'Destination', 'Carrier', 'Product', 'Total Shipments', 'J+K STD', 'J+K ACTUAL', 'Standard %', 'Actual %', 'Deviation', 'Status'];
    const csvContent = [
      headers.join(','),
      ...sortedRows.map(row =>
        [
          row.origin,
          row.destination,
          row.carrier,
          row.product,
          row.totalShipments,
          row.standardDays?.toFixed(1) || '-',
          row.actualDays?.toFixed(1) || '-',
          row.standardPercentage.toFixed(1),
          row.actualPercentage.toFixed(1),
          row.deviation.toFixed(1),
          row.status,
        ].join(',')
      ),
    ].join('\n');

    const blob = new Blob([csvContent], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `product-analysis-${new Date().toISOString().split('T')[0]}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  };

  const toggleStatus = (status: string) => {
    setEquityStatusFilter(prev =>
      prev.includes(status)
        ? prev.filter(s => s !== status)
        : [...prev, status]
    );
  };

  return (
    <div className="space-y-4">
      {/* Equity Status Filter */}
      <div className="flex items-center justify-between">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">
            <AlertCircle className="w-4 h-4 inline mr-1" />
            Filter by Equity Status
          </label>
          <div className="flex gap-4">
            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={equityStatusFilter.includes('compliant')}
                onChange={() => toggleStatus('compliant')}
                className="w-4 h-4 text-green-600 rounded"
              />
              <span className="text-sm">✅ Compliant</span>
            </label>
            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={equityStatusFilter.includes('warning')}
                onChange={() => toggleStatus('warning')}
                className="w-4 h-4 text-yellow-600 rounded"
              />
              <span className="text-sm">⚠️ Warning</span>
            </label>
            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={equityStatusFilter.includes('critical')}
                onChange={() => toggleStatus('critical')}
                className="w-4 h-4 text-red-600 rounded"
              />
              <span className="text-sm">🔴 Critical</span>
            </label>
          </div>
        </div>
        <button
          onClick={handleExportCSV}
          className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700"
        >
          <Download className="w-4 h-4" />
          Export CSV
        </button>
      </div>

      {/* Table */}
      <div className="overflow-x-auto border border-gray-200 rounded-lg">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            <tr>
              {[
                { key: 'origin', label: 'Origin' },
                { key: 'destination', label: 'Destination' },
                { key: 'carrier', label: 'Carrier' },
                { key: 'product', label: 'Product' },
                { key: 'totalShipments', label: 'Total' },
                { key: 'standardDays', label: 'J+K STD' },
                { key: 'actualDays', label: 'J+K ACTUAL' },
                { key: 'standardPercentage', label: 'Standard %' },
                { key: 'actualPercentage', label: 'Actual %' },
                { key: 'deviation', label: 'Deviation' },
                { key: 'status', label: 'Status' },
              ].map(({ key, label }) => (
                <th
                  key={key}
                  onClick={() => handleSort(key as keyof ProductRow)}
                  className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
                >
                  {label}
                  {sortField === key && (
                    <span className="ml-1">{sortDirection === 'asc' ? '▲' : '▼'}</span>
                  )}
                </th>
              ))}
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {sortedRows.map((row, idx) => (
              <tr key={idx} className="hover:bg-gray-50">
                <td className="px-6 py-4 whitespace-nowrap text-sm">{row.origin}</td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">{row.destination}</td>
                <td className="px-6 py-4 whitespace-nowrap text-sm">{row.carrier}</td>
                <td className="px-6 py-4 whitespace-nowrap text-sm">{row.product}</td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-right">{row.totalShipments}</td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-right">{row.standardDays?.toFixed(1) || '-'}</td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-right">{row.actualDays?.toFixed(1) || '-'}</td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-right">{row.standardPercentage.toFixed(1)}%</td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-right">{row.actualPercentage.toFixed(1)}%</td>
                <td className={`px-6 py-4 whitespace-nowrap text-sm text-right font-medium ${
                  row.deviation >= 0 ? 'text-green-600' : 'text-red-600'
                }`}>
                  {row.deviation >= 0 ? '+' : ''}{row.deviation.toFixed(1)}%
                </td>
                <td className="px-6 py-4 whitespace-nowrap">
                  <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${
                    row.status === 'compliant' ? 'bg-green-100 text-green-800' :
                    row.status === 'warning' ? 'bg-yellow-100 text-yellow-800' :
                    'bg-red-100 text-red-800'
                  }`}>
                    {row.status === 'compliant' ? '✅' : row.status === 'warning' ? '⚠️' : '🔴'} {row.status}
                  </span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {sortedRows.length === 0 && (
          <div className="text-center py-8 text-gray-500">
            No data available
          </div>
        )}
      </div>
    </div>
  );
}
