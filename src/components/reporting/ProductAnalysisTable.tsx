import { useState, useMemo } from 'react';
import { Download, AlertCircle } from 'lucide-react';
import { useTranslation } from '@/hooks/useTranslation';
import { useTimeUnit } from '@/hooks/useTimeUnit';
import type { TimeUnit } from '@/lib/accountTime';
import { convertUnit, formatJK, measureOf } from '@/lib/transitMeasure';

interface ProductAnalysisTableProps {
  routeData: any[];
  shipments?: any[];
  globalWarningThreshold: number;
  globalCriticalThreshold: number;
}

type ProductRow = {
  origin: string;
  destination: string;
  carrier: string;
  product: string;
  totalShipments: number;
  unit: TimeUnit; // unidad del estandar de la ruta (la de jkStandard/jkActual)
  jkStandard?: number;
  jkActual?: number;
  jkStandardHours?: number; // solo para ordenar rutas de unidades distintas
  jkActualHours?: number;
  standardPercentage: number;
  actualPercentage: number;
  deviation: number;
  status: 'compliant' | 'warning' | 'critical';
};

export function ProductAnalysisTable({
  routeData,
  shipments = [],
  globalWarningThreshold,
  globalCriticalThreshold,
}: ProductAnalysisTableProps) {
  const { t } = useTranslation();
  const { unit: displayUnit } = useTimeUnit();
  const [equityStatusFilter, setEquityStatusFilter] = useState<string[]>([]);
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
      unit: (route.unit as TimeUnit) || 'hours',
      jkStandard: route.jkStandard,
      jkActual: route.jkActual,
      jkStandardHours: route.jkStandard != null ? convertUnit(route.jkStandard, route.unit || 'hours', 'hours') : undefined,
      jkActualHours: route.jkActual != null ? convertUnit(route.jkActual, route.unit || 'hours', 'hours') : undefined,
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
    // J+K: se ordena por su equivalente en horas (las rutas pueden medir en horas o en dias)
    if (field === 'jkStandard') field = 'jkStandardHours';
    if (field === 'jkActual') field = 'jkActualHours';
    if (sortField === field) {
      setSortDirection(sortDirection === 'asc' ? 'desc' : 'asc');
    } else {
      setSortField(field);
      setSortDirection('asc');
    }
  };

  const handleExportCSV = () => {
    // Filter shipments to match visible routes
    const visibleRoutes = new Set(
      sortedRows.map(row => `${row.origin}|${row.destination}|${row.carrier}|${row.product}`)
    );
    
    const filteredShipments = shipments.filter(s => {
      const routeKey = `${s.origin_city_name}|${s.destination_city_name}|${s.carrier_name}|${s.product_name}`;
      return visibleRoutes.has(routeKey);
    });

    // Export individual samples
    const headers = [
      'Tracking Number',
      'Origin',
      'Destination',
      'Carrier',
      'Product',
      'Sent At',
      'Delivered At',
      'Unit',
      'Business Time',
      'Standard Time',
      'J+K Actual',
      'On Time',
      'Status'
    ];
    
    const csvContent = [
      headers.join(','),
      ...filteredShipments.map(s => {
        // Find standard for this shipment from routeData
        const routeKey = `${s.origin_city_name}|${s.destination_city_name}|${s.carrier_name}|${s.product_name}`;
        const route = sortedRows.find(r => `${r.origin}|${r.destination}|${r.carrier}|${r.product}` === routeKey);
        const unit: TimeUnit = route?.unit || 'hours';
        // Medida en la unidad del estandar de la ruta (vacia si el envio no tiene medida)
        const measure = measureOf(s, unit);
        const standardTime = route?.jkStandard || 0;
        // on_time_delivery nulo (sin estandar / sin medida) -> N/A, no "No"
        const onTime = typeof s.on_time_delivery === 'boolean' ? (s.on_time_delivery ? 'Yes' : 'No') : 'N/A';
        const status = route?.status || '';
        
        return [
          s.tracking_number || '',
          s.origin_city_name || '',
          s.destination_city_name || '',
          s.carrier_name || '',
          s.product_name || '',
          s.sent_at || '',
          s.delivered_at || '',
          unit,
          measure != null ? measure.toFixed(1) : '',
          standardTime.toFixed(1),
          measure != null ? measure.toFixed(1) : '',
          onTime,
          status
        ].join(',');
      }),
    ].join('\n');

    const blob = new Blob([csvContent], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `jk-samples-${new Date().toISOString().split('T')[0]}.csv`;
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
          Export Samples CSV
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
                { key: 'jkStandard', label: 'J+K STD' },
                { key: 'jkActual', label: 'J+K ACTUAL' },
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
                  {(sortField === key || sortField === `${key}Hours`) && (
                    <span className="ml-1">{sortDirection === 'asc' ? '▲' : '▼'}</span>
                  )}
                </th>
              ))}
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {sortedRows.map((row, idx) => (
              <tr 
                key={idx} 
                className="hover:bg-gray-50 cursor-pointer"
                onClick={() => {
                  const url = `/reporting/territory-equity?tab=jk&hideSidebar=true&origin=${encodeURIComponent(row.origin)}&destination=${encodeURIComponent(row.destination)}&carrier=${encodeURIComponent(row.carrier)}&product=${encodeURIComponent(row.product)}`;
                  window.open(url, '_blank');
                }}
              >
                <td className="px-6 py-4 whitespace-nowrap text-sm">{row.origin}</td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">{row.destination}</td>
                <td className="px-6 py-4 whitespace-nowrap text-sm">{row.carrier}</td>
                <td className="px-6 py-4 whitespace-nowrap text-sm">{row.product}</td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-right">{row.totalShipments}</td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-right">{row.jkStandard != null ? formatJK(row.jkStandard, row.unit, displayUnit) : '-'}</td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-right">{row.jkActual != null ? formatJK(row.jkActual, row.unit, displayUnit) : '-'}</td>
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
