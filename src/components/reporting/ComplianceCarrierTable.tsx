import React, { useState } from 'react';
import { ArrowUpDown, ChevronDown, ChevronRight } from 'lucide-react';

interface CarrierData {
  carrier: string;
  routes: any[];
  totalSamples: number;
  compliantRoutes: number;
  warningRoutes: number;
  criticalRoutes: number;
}

interface ComplianceCarrierTableProps {
  data: CarrierData[];
  warningThreshold: number;
  criticalThreshold: number;
}

export function ComplianceCarrierTable({ data, warningThreshold, criticalThreshold }: ComplianceCarrierTableProps) {
  const [expandedCarriers, setExpandedCarriers] = useState<Set<string>>(new Set());
  const [sortField, setSortField] = useState<'carrier' | 'totalSamples' | 'compliance'>('carrier');
  const [sortDirection, setSortDirection] = useState<'asc' | 'desc'>('asc');

  const toggleCarrier = (carrier: string) => {
    const newExpanded = new Set(expandedCarriers);
    if (newExpanded.has(carrier)) {
      newExpanded.delete(carrier);
    } else {
      newExpanded.add(carrier);
    }
    setExpandedCarriers(newExpanded);
  };

  const sortedData = [...data].sort((a, b) => {
    let aVal, bVal;
    if (sortField === 'carrier') {
      aVal = a.carrier;
      bVal = b.carrier;
      return sortDirection === 'asc' ? aVal.localeCompare(bVal) : bVal.localeCompare(aVal);
    } else if (sortField === 'totalSamples') {
      aVal = a.totalSamples;
      bVal = b.totalSamples;
    } else {
      aVal = a.routes.length > 0 ? a.compliantRoutes / a.routes.length : 0;
      bVal = b.routes.length > 0 ? b.compliantRoutes / b.routes.length : 0;
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

  return (
    <div className="overflow-x-auto">
      <table className="min-w-full divide-y divide-gray-200">
        <thead className="bg-gray-50">
          <tr>
            <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider w-12"></th>
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
              onClick={() => handleSort('totalSamples')}
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
            >
              <div className="flex items-center justify-end gap-1">
                Total Samples
                <ArrowUpDown className="w-3 h-3" />
              </div>
            </th>
            <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
              Routes
            </th>
            <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
              Compliant
            </th>
            <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
              Warning
            </th>
            <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
              Critical
            </th>
            <th 
              onClick={() => handleSort('compliance')}
              className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
            >
              <div className="flex items-center justify-end gap-1">
                Compliance %
                <ArrowUpDown className="w-3 h-3" />
              </div>
            </th>
          </tr>
        </thead>
        <tbody className="bg-white divide-y divide-gray-200">
          {sortedData.map((carrier) => {
            const isExpanded = expandedCarriers.has(carrier.carrier);
            const complianceRate = carrier.routes.length > 0 
              ? (carrier.compliantRoutes / carrier.routes.length) * 100 
              : 0;

            return (
              <React.Fragment key={carrier.carrier}>
                <tr className="hover:bg-gray-50 cursor-pointer" onClick={() => toggleCarrier(carrier.carrier)}>
                  <td className="px-4 py-3 whitespace-nowrap">
                    {isExpanded ? (
                      <ChevronDown className="w-4 h-4 text-gray-400" />
                    ) : (
                      <ChevronRight className="w-4 h-4 text-gray-400" />
                    )}
                  </td>
                  <td className="px-4 py-3 whitespace-nowrap text-sm font-medium">{carrier.carrier}</td>
                  <td className="px-4 py-3 whitespace-nowrap text-sm text-right">{carrier.totalSamples}</td>
                  <td className="px-4 py-3 whitespace-nowrap text-sm text-right">{carrier.routes.length}</td>
                  <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-green-600">{carrier.compliantRoutes}</td>
                  <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-amber-600">{carrier.warningRoutes}</td>
                  <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-red-600">{carrier.criticalRoutes}</td>
                  <td className={`px-4 py-3 whitespace-nowrap text-sm text-right font-medium ${
                    complianceRate >= warningThreshold ? 'text-green-600' :
                    complianceRate >= criticalThreshold ? 'text-amber-600' : 'text-red-600'
                  }`}>
                    {complianceRate.toFixed(1)}%
                  </td>
                </tr>
                {isExpanded && carrier.routes.map((route, idx) => (
                  <tr key={idx} className="bg-gray-50">
                    <td className="px-4 py-2"></td>
                    <td className="px-4 py-2 text-sm text-gray-600 pl-8">
                      {route.origin} → {route.destination}
                    </td>
                    <td className="px-4 py-2 text-sm text-right text-gray-600">{route.samples || 0}</td>
                    <td className="px-4 py-2 text-sm text-right text-gray-600">{route.product}</td>
                    <td className="px-4 py-2 text-sm text-right text-gray-600">{route.standardDays?.toFixed(1)}</td>
                    <td className="px-4 py-2 text-sm text-right text-gray-600">{route.actualDays?.toFixed(1)}</td>
                    <td className="px-4 py-2 text-sm text-right text-gray-600">{route.actualPercentage?.toFixed(1)}%</td>
                    <td className="px-4 py-2 text-sm text-right">
                      <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${
                        route.status === 'compliant' ? 'bg-green-100 text-green-800' :
                        route.status === 'warning' ? 'bg-yellow-100 text-yellow-800' :
                        'bg-red-100 text-red-800'
                      }`}>
                        {route.status}
                      </span>
                    </td>
                  </tr>
                ))}
              </React.Fragment>
            );
          })}
        </tbody>
      </table>
      {sortedData.length === 0 && (
        <div className="text-center py-8 text-gray-500">
          No carrier data available
        </div>
      )}
    </div>
  );
}
