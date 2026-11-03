import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ReferenceLine, ResponsiveContainer, Cell } from 'recharts';
import type { RegionEquityData } from '@/types/reporting';
import { formatNumber } from '@/lib/formatNumber';
import { useTimeUnit } from '@/hooks/useTimeUnit';
import type { TimeUnit } from '@/lib/accountTime';
import { formatJK } from '@/lib/transitMeasure';
import { useTranslation } from '@/hooks/useTranslation';

interface RegionalEquityChartProps {
  data: RegionEquityData[];
}

export function RegionalEquityChart({ data }: RegionalEquityChartProps) {
  const { t } = useTranslation();
  const { unit: displayUnit } = useTimeUnit();
  // J+K en la unidad de su grupo (sin unidad = horas, regla de medida)
  const jk = (v: number, u?: TimeUnit) => formatJK(v, u ?? 'hours', displayUnit);
  const chartData = data.map((region) => ({
    region: region.regionName,
    actual: region.actualPercentage,
    standard: region.standardPercentage,
    inboundStandardPercentage: region.inboundStandardPercentage,
    inboundPercentage: region.inboundPercentage,
    inboundUnit: region.inboundUnit,
    inboundStandardDays: region.inboundStandardDays,
    inboundActualDays: region.inboundActualDays,
    outboundStandardPercentage: region.outboundStandardPercentage,
    outboundPercentage: region.outboundPercentage,
    outboundUnit: region.outboundUnit,
    outboundStandardDays: region.outboundStandardDays,
    outboundActualDays: region.outboundActualDays,
    status: region.status,
  }));

  // Calculate average standard for reference line
  const avgStandard =
    chartData.length > 0
      ? chartData.reduce((sum, d) => sum + d.standard, 0) / chartData.length
      : 90;

  const getBarColor = (status: string) => {
    switch (status) {
      case 'compliant':
        return '#10b981'; // green
      case 'warning':
        return '#f59e0b'; // amber
      case 'critical':
        return '#ef4444'; // red
      default:
        return '#6b7280'; // gray
    }
  };

  return (
    <div className="w-full h-96">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart
          data={chartData}
          layout="vertical"
          margin={{ top: 20, right: 30, left: 100, bottom: 20 }}
        >
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis type="number" domain={[0, 100]} label={{ value: t('hc.regional_equity_chart.compliance_pct'), position: 'bottom' }} />
          <YAxis type="category" dataKey="region" />
          <Tooltip 
            content={({ active, payload }) => {
              if (active && payload && payload.length) {
                const data = payload[0].payload;
                return (
                  <div className="bg-white p-3 border border-gray-300 rounded shadow-lg">
                    <p className="font-semibold mb-2">{data.region}</p>
                    <div className="mb-2">
                      <p className="text-blue-600 font-medium">{t('hc.regional_equity_chart.inbound')}</p>
                      <p className="text-sm ml-2">{t('hc.regional_equity_chart.std_actual_pct', { std: formatNumber(data.inboundStandardPercentage), actual: formatNumber(data.inboundPercentage) })}</p>
                      <p className="text-sm ml-2">{t('hc.regional_equity_chart.jk_std_actual', { std: jk(data.inboundStandardDays, data.inboundUnit), actual: jk(data.inboundActualDays, data.inboundUnit) })}</p>
                    </div>
                    <div>
                      <p className="text-green-600 font-medium">{t('hc.regional_equity_chart.outbound')}</p>
                      <p className="text-sm ml-2">{t('hc.regional_equity_chart.std_actual_pct', { std: formatNumber(data.outboundStandardPercentage), actual: formatNumber(data.outboundPercentage) })}</p>
                      <p className="text-sm ml-2">{t('hc.regional_equity_chart.jk_std_actual', { std: jk(data.outboundStandardDays, data.outboundUnit), actual: jk(data.outboundActualDays, data.outboundUnit) })}</p>
                    </div>
                  </div>
                );
              }
              return null;
            }}
          />
          <ReferenceLine
            x={avgStandard}
            stroke="#ef4444"
            strokeDasharray="3 3"
            label={{ value: t('hc.regional_equity_chart.avg_standard', { value: formatNumber(avgStandard) }), position: 'top' }}
          />
          <Bar dataKey="actual" name={t('hc.regional_equity_chart.actual_compliance')}>
            {chartData.map((entry, index) => (
              <Cell key={`cell-${index}`} fill={getBarColor(entry.status)} />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
