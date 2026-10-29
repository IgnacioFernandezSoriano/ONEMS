import React from 'react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import type { GeneralPerformanceData } from '@/types/reporting';
import { toUnit, unitSuffix, type TimeUnit } from '@/lib/accountTime';
import { useTranslation } from '@/hooks/useTranslation';

interface DualLineChartProps {
  data: GeneralPerformanceData[];
  unit?: TimeUnit;
}

export default function DualLineChart({ data, unit = 'hours' }: DualLineChartProps) {
  const { t } = useTranslation();
  const chartData = data.map(d => ({
    date: d.period.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }),
    compliance: d.compliancePercentage,
    businessDays: d.avgBusinessHours == null ? null : Number(toUnit(d.avgBusinessHours, unit).toFixed(2))
  }));

  return (
    <div className="bg-white rounded-lg shadow p-6">
      <h3 className="text-lg font-semibold text-gray-900 mb-4">{t('reporting.performance_trend')}</h3>
      <ResponsiveContainer width="100%" height={300}>
        <LineChart data={chartData}>
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis dataKey="date" />
          <YAxis yAxisId="left" />
          <YAxis yAxisId="right" orientation="right" unit={` ${unitSuffix(unit)}`} />
          <Tooltip
            formatter={(value, _name, item) =>
              item?.dataKey === 'compliance' ? (value ?? '') : `${value ?? ''} ${unitSuffix(unit)}`
            }
          />
          <Legend />
          <Line yAxisId="left" type="monotone" dataKey="compliance" stroke="#10b981" name={t('reporting.compliance_percent')} />
          <Line yAxisId="right" type="monotone" dataKey="businessDays" stroke="#3b82f6" name={`${t('reporting.avg_transit_time')} (${unitSuffix(unit)})`} />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
