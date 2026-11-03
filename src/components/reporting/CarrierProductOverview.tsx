import React from 'react';
import { ColumnTooltip } from './ColumnTooltip';
import { formatNumber } from '@/lib/formatNumber';
import type { TimeUnit } from '@/lib/accountTime';
import { formatJK } from '@/lib/transitMeasure';
import { useTranslation } from '@/hooks/useTranslation';

interface CarrierProductData {
  carrier: string;
  product: string;
  routes: number;
  totalSamples: number;
  unit: TimeUnit;
  jkStandard: number;
  jkActual: number;
  deviation: number;
  onTimePercentage: number;
  problematicRoutes: number;
  status: 'compliant' | 'warning' | 'critical';
}

interface CarrierProductOverviewProps {
  data: CarrierProductData[];
  loading: boolean;
  globalWarningThreshold: number;
  globalCriticalThreshold: number;
  displayUnit?: TimeUnit;
}

export default function CarrierProductOverview({ data, loading, globalWarningThreshold, globalCriticalThreshold, displayUnit = 'hours' }: CarrierProductOverviewProps) {
  const { t } = useTranslation();

  if (loading) {
    return (
      <div className="text-center text-gray-500 py-8">{t('hc.carrier_product_overview.loading')}</div>
    );
  }

  if (data.length === 0) {
    return (
      <div className="text-center text-gray-500 py-8">{t('hc.carrier_product_overview.no_data')}</div>
    );
  }

  // Sort by compliance (worst first) to highlight problems
  const sortedData = [...data].sort((a, b) => a.onTimePercentage - b.onTimePercentage);

  return (
    <div className="overflow-x-auto">
      <table className="min-w-full divide-y divide-gray-200">
        <thead className="bg-gray-50">
          <tr>
            <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
              <div className="flex items-center gap-1">{t('hc.carrier_product_overview.carrier_product')} <ColumnTooltip content={t('hc.carrier_product_overview.carrier_product_tip')} /></div>
            </th>
            <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
              <div className="flex items-center gap-1">{t('hc.carrier_product_overview.routes')} <ColumnTooltip content={t('hc.carrier_product_overview.routes_tip')} /></div>
            </th>
            <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
              <div className="flex items-center gap-1">{t('hc.carrier_product_overview.samples')} <ColumnTooltip content={t('hc.carrier_product_overview.samples_tip')} /></div>
            </th>
            <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
              <div className="flex items-center gap-1">{t('hc.carrier_product_overview.jk_std')} <ColumnTooltip content={t('hc.carrier_product_overview.jk_std_tip')} /></div>
            </th>
            <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
              <div className="flex items-center gap-1">{t('hc.carrier_product_overview.jk_actual')} <ColumnTooltip content={t('hc.carrier_product_overview.jk_actual_tip')} /></div>
            </th>
            <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
              <div className="flex items-center gap-1">{t('hc.carrier_product_overview.deviation')} <ColumnTooltip content={t('hc.carrier_product_overview.deviation_tip')} /></div>
            </th>
            <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
              <div className="flex items-center gap-1">{t('hc.carrier_product_overview.on_time_pct')} <ColumnTooltip content={t('hc.carrier_product_overview.on_time_pct_tip')} /></div>
            </th>
            <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
              <div className="flex items-center gap-1">{t('hc.carrier_product_overview.problem_routes')} <ColumnTooltip content={t('hc.carrier_product_overview.problem_routes_tip')} /></div>
            </th>
            <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
              <div className="flex items-center gap-1">{t('hc.carrier_product_overview.status')} <ColumnTooltip content={t('hc.carrier_product_overview.status_tip')} /></div>
            </th>
          </tr>
        </thead>
        <tbody className="bg-white divide-y divide-gray-200">
          {sortedData.map((item, index) => {
            const warnDeviation = item.unit === 'days' ? 1 : 24;
            const deviationColor = item.deviation <= 0 ? 'text-green-600' : item.deviation <= warnDeviation ? 'text-yellow-600' : 'text-red-600';
            const onTimeColor = item.onTimePercentage >= globalWarningThreshold ? 'text-green-600 font-semibold' : item.onTimePercentage > globalCriticalThreshold ? 'text-yellow-600' : 'text-red-600 font-semibold';
            const statusColor = item.status === 'compliant' ? 'bg-green-500' : item.status === 'warning' ? 'bg-yellow-500' : 'bg-red-500';
            
            return (
              <tr key={`${item.carrier}-${item.product}-${index}`} className="hover:bg-gray-50">
                <td className="px-3 py-2 text-sm text-gray-900">
                  <div className="font-medium">{item.carrier}</div>
                  <div className="text-xs text-gray-500">↳ {item.product}</div>
                </td>
                <td className="px-3 py-2 text-sm text-gray-700">{item.routes}</td>
                <td className="px-3 py-2 text-sm text-gray-900">{item.totalSamples}</td>
                <td className="px-3 py-2 text-sm text-gray-900">{formatJK(item.jkStandard, item.unit, displayUnit)}</td>
                <td className="px-3 py-2 text-sm text-gray-900">{formatJK(item.jkActual, item.unit, displayUnit)}</td>
                <td className={`px-3 py-2 text-sm ${deviationColor}`}>
                  {formatJK(item.deviation, item.unit, displayUnit, true)}
                </td>
                <td className={`px-3 py-2 text-sm ${onTimeColor}`}>
                  {formatNumber(item.onTimePercentage)}%
                </td>
                <td className="px-3 py-2 text-sm text-red-600 font-semibold">
                  {item.problematicRoutes}
                </td>
                <td className="px-3 py-2">
                  <div className={`w-3 h-3 rounded-full ${statusColor}`} />
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
