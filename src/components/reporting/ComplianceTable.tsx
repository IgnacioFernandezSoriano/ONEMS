import React from 'react';
import { CheckCircle, XCircle } from 'lucide-react';
import { SmartTooltip } from '@/components/common/SmartTooltip';
import type { CarrierData, ProductData, RouteData } from '@/hooks/reporting/useComplianceData';

import { useTranslation } from '@/hooks/useTranslation';
interface ComplianceTableProps {
  data: CarrierData[];
}

export function ComplianceTable({ data }: ComplianceTableProps) {
  const { t } = useTranslation();
  if (data.length === 0) {
    return (
      <div className="text-center py-8 text-gray-500">
        No compliance data available
      </div>
    );
  }

  const formatValue = (value: number | undefined, decimals: number = 1): string => {
    if (value === undefined || value === null || isNaN(value)) return '-';
    return value.toFixed(decimals);
  };

  const formatPercentage = (value: number | undefined): string => {
    if (value === undefined || value === null || isNaN(value) || value === 0) return 'N/A';
    return `${value.toFixed(1)}%`;
  };

  const getComplianceIcon = (status: 'compliant' | 'warning' | 'critical') => {
    switch (status) {
      case 'compliant':
        return <CheckCircle className="w-4 h-4 text-green-500 mr-2" />;
      case 'warning':
        return (
          <svg className="w-4 h-4 text-amber-500 mr-2" fill="currentColor" viewBox="0 0 20 20">
            <path fillRule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
          </svg>
        );
      case 'critical':
        return <XCircle className="w-4 h-4 text-red-500 mr-2" />;
    }
  };

  const getComplianceColor = (status: 'compliant' | 'warning' | 'critical') => {
    switch (status) {
      case 'compliant':
        return 'text-green-600 font-medium';
      case 'warning':
        return 'text-amber-600 font-medium';
      case 'critical':
        return 'text-red-600 font-medium';
    }
  };

  return (
    <div className="overflow-x-auto">
      <table className="min-w-full divide-y divide-gray-200">
        <thead className="bg-gray-50">
          <tr>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              {t('reporting.carrier_product_route')}
            </th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              {t('reporting.total_shipments')}
            </th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              {t('reporting.compliant')}
            </th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              <div className="flex items-center gap-1">
                {t('reporting.standard_days')}
                <SmartTooltip content={
                  <>
                    <p className="font-semibold mb-1">Carrier/Product Level:</p>
                    <p className="mb-2">Weighted average by shipment count</p>
                    <p className="font-semibold mb-1">Route Level:</p>
                    <p>Direct value from delivery_standards</p>
                  </>
                } />
              </div>
            </th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              <div className="flex items-center gap-1">
                {t('reporting.actual_days')}
                <SmartTooltip content={
                  <>
                    <p className="font-semibold mb-1">Carrier/Product Level:</p>
                    <p className="mb-2">Weighted average by shipment count</p>
                    <p className="font-semibold mb-1">Route Level:</p>
                    <p>Average business days for all shipments</p>
                  </>
                } />
              </div>
            </th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              <div className="flex items-center gap-1">
                {t('reporting.standard_percent')}
                <SmartTooltip content={
                  <>
                    <p className="font-semibold mb-1">Carrier/Product Level:</p>
                    <p className="mb-2">Weighted average by shipment count</p>
                    <p className="font-semibold mb-1">Route Level:</p>
                    <p>Direct value from delivery_standards</p>
                  </>
                } />
              </div>
            </th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              <div className="flex items-center gap-1">
                {t('reporting.actual_percent')}
                <SmartTooltip content={
                  <>
                    <p className="mb-2">Percentage of shipments delivered successfully</p>
                    <p className="font-semibold mb-1">Carrier/Product Level:</p>
                    <p className="mb-2">Weighted average by shipment count</p>
                    <p className="font-semibold mb-1">Route Level:</p>
                    <p>Compliant shipments / Total shipments × 100%</p>
                  </>
                } />
              </div>
            </th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              <div className="flex items-center gap-1">
                {t('reporting.deviation')}
                <SmartTooltip content={
                  <>
                    <p className="mb-2">Difference between Actual % and Standard %</p>
                    <p className="font-semibold mb-1">Positive:</p>
                    <p className="mb-2">Above standard (good)</p>
                    <p className="font-semibold mb-1">Negative:</p>
                    <p>Below standard (deviation)</p>
                  </>
                } />
              </div>
            </th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              <div className="flex items-center gap-1">
                {t('common.status')}
                <SmartTooltip content={
                  <>
                    <p className="mb-2">Compliance status based on dynamic thresholds:</p>
                    <p className="font-semibold mb-1">✅ Compliant:</p>
                    <p className="mb-2">Actual ≥ Standard %</p>
                    <p className="font-semibold mb-1">⚠️ Warning:</p>
                    <p className="mb-2">Below standard but above critical (no penalty)</p>
                    <p className="font-semibold mb-1">🔴 Critical:</p>
                    <p>Below critical threshold (with penalty)</p>
                  </>
                } />
              </div>
            </th>
          </tr>
        </thead>
        <tbody className="bg-white divide-y divide-gray-200">
          {data.map((carrier) => (
            <React.Fragment key={carrier.carrier}>
              {/* Carrier Row */}
              <tr className="bg-blue-50 font-semibold">
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  <div className="flex items-center">
                    📦 {carrier.carrier}
                  </div>
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {carrier.totalShipments}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {carrier.compliantShipments}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-blue-600">
                  {formatValue(carrier.standardDays)}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {formatValue(carrier.avgBusinessDays)}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-blue-600">
                  {formatPercentage(carrier.standardPercentage)}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm">
                  <span className="text-gray-900">
                    {formatValue(carrier.compliancePercentage)}%
                  </span>
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm font-medium">
                  {carrier.standardPercentage > 0 ? (
                    <span className={carrier.compliancePercentage >= carrier.standardPercentage ? 'text-green-600' : 'text-red-600'}>
                      {carrier.compliancePercentage >= carrier.standardPercentage ? '+' : ''}{formatValue(carrier.compliancePercentage - carrier.standardPercentage)}%
                    </span>
                  ) : '-'}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  -
                </td>
              </tr>

              {/* Product Rows */}
              {carrier.products.map((product) => (
                <React.Fragment key={`${carrier.carrier}|${product.product}`}>
                  <tr className="bg-gray-50">
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      <div className="flex items-center pl-6">
                        📋 {product.product}
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-700">
                      {product.totalShipments}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-700">
                      {product.compliantShipments}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-blue-600">
                      {formatValue(product.standardDays)}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-700">
                      {formatValue(product.avgBusinessDays)}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-blue-600">
                      {formatPercentage(product.standardPercentage)}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm">
                      <span className="text-gray-700">
                        {formatValue(product.compliancePercentage)}%
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium">
                      {product.standardPercentage > 0 ? (
                        <span className={product.compliancePercentage >= product.standardPercentage ? 'text-green-600' : 'text-red-600'}>
                          {product.compliancePercentage >= product.standardPercentage ? '+' : ''}{formatValue(product.compliancePercentage - product.standardPercentage)}%
                        </span>
                      ) : '-'}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      -
                    </td>
                  </tr>

                  {/* Route Rows */}
                  {product.routes.map((route) => (
                    <tr key={`${carrier.carrier}|${product.product}|${route.route}`} className="hover:bg-gray-50">
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                        <div className="pl-12">
                          🛣️ {route.route}
                        </div>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                        {route.totalShipments}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                        {route.compliantShipments}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-blue-600">
                        {formatValue(route.standardDays)}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                        {formatValue(route.avgBusinessDays)}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-blue-600">
                        {formatPercentage(route.standardPercentage)}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm">
                        <div className="flex items-center group relative">
                          {getComplianceIcon(route.complianceStatus)}
                          <span className={getComplianceColor(route.complianceStatus)}>
                            {formatValue(route.compliancePercentage)}%
                          </span>
                          <div className="invisible group-hover:visible absolute z-10 w-72 p-3 bg-gray-900 text-white text-xs rounded shadow-lg left-0 top-8">
                            <div className="space-y-1">
                              <div><span className="font-semibold">Standard:</span> {formatPercentage(route.standardPercentage)}</div>
                              <div><span className="font-semibold">Warning Limit:</span> {formatValue(route.warningLimit)}% ({route.thresholdType === 'relative' ? 'Rel' : 'Abs'})</div>
                              <div><span className="font-semibold">Critical Limit:</span> {formatValue(route.criticalLimit)}% ({route.thresholdType === 'relative' ? 'Rel' : 'Abs'})</div>
                              <div className="pt-1 border-t border-gray-700">
                                <span className="font-semibold">Status:</span> 
                                {route.complianceStatus === 'compliant' && ' ✅ Compliant'}
                                {route.complianceStatus === 'warning' && ' ⚠️ Warning (no penalty)'}
                                {route.complianceStatus === 'critical' && ' 🔴 Critical (penalty)'}
                              </div>
                            </div>
                          </div>
                        </div>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm font-medium">
                        {route.standardPercentage > 0 ? (
                          <span className={route.compliancePercentage >= route.standardPercentage ? 'text-green-600' : 'text-red-600'}>
                            {route.compliancePercentage >= route.standardPercentage ? '+' : ''}{formatValue(route.compliancePercentage - route.standardPercentage)}%
                          </span>
                        ) : '-'}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm">
                        <div className="flex items-center justify-center">
                          <div className={`w-3 h-3 rounded-full ${
                            route.complianceStatus === 'compliant' ? 'bg-green-500' :
                            route.complianceStatus === 'warning' ? 'bg-yellow-500' :
                            'bg-red-500'
                          }`} />
                        </div>
                      </td>
                    </tr>
                  ))}
                </React.Fragment>
              ))}
            </React.Fragment>
          ))}
        </tbody>
      </table>
    </div>
  );
}
