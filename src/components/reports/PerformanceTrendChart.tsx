import React, { useState, useMemo } from 'react';
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from 'recharts';
import { format, startOfWeek, startOfMonth } from 'date-fns';
import { useTimeUnit } from '@/hooks/useTimeUnit';
import { useTranslation } from '@/hooks/useTranslation';
import { formatDuration, toUnit } from '@/lib/accountTime';

interface TrendDataPoint {
  date: string;
  avgHours: number; // tiempo medio en horas (dias*24 si la ruta mide en dias)
  compliancePercent: number;
  standardHours: number; // estandar medio en horas
  standardPercent: number;
}

interface PerformanceTrendChartProps {
  data: TrendDataPoint[];
  title?: string;
}

type TimeScale = 'day' | 'week' | 'month';

export function PerformanceTrendChart({ data, title }: PerformanceTrendChartProps) {
  const { unit } = useTimeUnit();
  const { t } = useTranslation();
  const chartTitle = title ?? t('hc.performance_trend_chart.default_title');
  const [timeScale, setTimeScale] = useState<TimeScale>('week');
  const [visibleLines, setVisibleLines] = useState({
    avgDays: true,
    compliancePercent: true,
  });

  // Aggregate data based on time scale
  const aggregatedData = useMemo(() => {
    if (!data || data.length === 0) return [];

    if (timeScale === 'day') {
      return data.map((point) => ({
        ...point,
        avgDays: toUnit(point.avgHours, unit), // valor dibujado en la unidad del selector
        displayDate: format(new Date(point.date), 'MMM d'),
      }));
    }

    // Group by week or month
    const groupMap = new Map<string, { 
      totalAvgDays: number; 
      totalCompliance: number; 
      totalStandardDays: number;
      totalStandardPercent: number;
      count: number 
    }>();

    data.forEach((point) => {
      const date = new Date(point.date);
      let groupKey: string;

      if (timeScale === 'week') {
        const weekStart = startOfWeek(date, { weekStartsOn: 1 }); // Monday
        groupKey = format(weekStart, 'yyyy-MM-dd');
      } else {
        const monthStart = startOfMonth(date);
        groupKey = format(monthStart, 'yyyy-MM-dd');
      }

      if (!groupMap.has(groupKey)) {
        groupMap.set(groupKey, { 
          totalAvgDays: 0, 
          totalCompliance: 0, 
          totalStandardDays: 0,
          totalStandardPercent: 0,
          count: 0 
        });
      }

      const group = groupMap.get(groupKey)!;
      group.totalAvgDays += point.avgHours;
      group.totalCompliance += point.compliancePercent;
      group.totalStandardDays += point.standardHours;
      group.totalStandardPercent += point.standardPercent;
      group.count++;
    });

    return Array.from(groupMap.entries())
      .map(([dateKey, group]) => ({
        date: dateKey,
        avgHours: group.totalAvgDays / group.count,
        avgDays: toUnit(group.totalAvgDays / group.count, unit), // valor dibujado en la unidad del selector
        compliancePercent: group.totalCompliance / group.count,
        standardHours: group.totalStandardDays / group.count,
        standardPercent: group.totalStandardPercent / group.count,
        displayDate:
          timeScale === 'week'
            ? t('hc.performance_trend_chart.week_of', { date: format(new Date(dateKey), 'MMM d') })
            : format(new Date(dateKey), 'MMM yyyy'),
      }))
      .sort((a, b) => a.date.localeCompare(b.date));
  }, [data, timeScale, unit, t]);

  // Custom tooltip - shows all 4 metrics
  const CustomTooltip = ({ active, payload }: any) => {
    if (active && payload && payload.length) {
      const data = payload[0].payload;
      return (
        <div className="bg-white p-3 border border-gray-300 rounded shadow-lg">
          <p className="font-semibold text-gray-800 mb-2">{data.displayDate}</p>
          <p className="text-blue-600">
            <span className="font-medium">{t('hc.performance_trend_chart.jk_actual')}:</span> {formatDuration(data.avgHours, unit)}
          </p>
          <p className="text-green-600">
            <span className="font-medium">{t('hc.performance_trend_chart.pct_actual')}:</span> {data.compliancePercent.toFixed(1)}%
          </p>
          <p className="text-purple-600">
            <span className="font-medium">{t('hc.performance_trend_chart.jk_std')}:</span> {formatDuration(data.standardHours, unit)}
          </p>
          <p className="text-orange-600">
            <span className="font-medium">{t('hc.performance_trend_chart.pct_std')}:</span> {data.standardPercent.toFixed(1)}%
          </p>
        </div>
      );
    }
    return null;
  };

  if (!data || data.length === 0) {
    return (
      <div className="bg-white p-6 rounded-lg shadow">
        <h3 className="text-lg font-semibold text-gray-800 mb-4">{chartTitle}</h3>
        <p className="text-gray-500">{t('hc.performance_trend_chart.no_data')}</p>
      </div>
    );
  }

  return (
    <div className="bg-white p-6 rounded-lg shadow">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-semibold text-gray-800">{chartTitle}</h3>
        <div className="flex gap-2">
          <button
            onClick={() => setTimeScale('day')}
            className={`px-3 py-1 text-sm rounded transition-colors ${
              timeScale === 'day'
                ? 'bg-blue-600 text-white'
                : 'bg-gray-200 text-gray-700 hover:bg-gray-300'
            }`}
          >
            {t('hc.performance_trend_chart.day')}
          </button>
          <button
            onClick={() => setTimeScale('week')}
            className={`px-3 py-1 text-sm rounded transition-colors ${
              timeScale === 'week'
                ? 'bg-blue-600 text-white'
                : 'bg-gray-200 text-gray-700 hover:bg-gray-300'
            }`}
          >
            {t('hc.performance_trend_chart.week')}
          </button>
          <button
            onClick={() => setTimeScale('month')}
            className={`px-3 py-1 text-sm rounded transition-colors ${
              timeScale === 'month'
                ? 'bg-blue-600 text-white'
                : 'bg-gray-200 text-gray-700 hover:bg-gray-300'
            }`}
          >
            {t('hc.performance_trend_chart.month')}
          </button>
        </div>
      </div>

      {/* Line visibility checkboxes */}
      <div className="flex gap-4 mb-4">
        <label className="flex items-center gap-2 cursor-pointer">
          <input
            type="checkbox"
            checked={visibleLines.avgDays}
            onChange={(e) => setVisibleLines({ ...visibleLines, avgDays: e.target.checked })}
            className="w-4 h-4 text-blue-600 rounded focus:ring-blue-500"
          />
          <span className="text-sm text-gray-700 flex items-center gap-1">
            <span className="w-3 h-0.5 bg-blue-600 inline-block"></span>
            {t('hc.performance_trend_chart.jk_actual')}
          </span>
        </label>
        <label className="flex items-center gap-2 cursor-pointer">
          <input
            type="checkbox"
            checked={visibleLines.compliancePercent}
            onChange={(e) => setVisibleLines({ ...visibleLines, compliancePercent: e.target.checked })}
            className="w-4 h-4 text-green-600 rounded focus:ring-green-500"
          />
          <span className="text-sm text-gray-700 flex items-center gap-1">
            <span className="w-3 h-0.5 bg-green-600 inline-block"></span>
            {t('hc.performance_trend_chart.pct_actual')}
          </span>
        </label>
      </div>

      <ResponsiveContainer width="100%" height={350}>
        <LineChart data={aggregatedData} margin={{ top: 5, right: 30, left: 20, bottom: 5 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
          <XAxis
            dataKey="displayDate"
            stroke="#6b7280"
            style={{ fontSize: '12px' }}
          />
          <YAxis
            yAxisId="left"
            stroke="#3b82f6"
            label={{ value: unit === 'hours' ? t('common.unit_hours') : t('common.unit_days'), angle: -90, position: 'insideLeft', style: { fill: '#3b82f6' } }}
            style={{ fontSize: '12px' }}
          />
          <YAxis
            yAxisId="right"
            orientation="right"
            stroke="#10b981"
            domain={[0, 100]}
            label={{ value: t('hc.performance_trend_chart.percentage'), angle: 90, position: 'insideRight', style: { fill: '#10b981' } }}
            style={{ fontSize: '12px' }}
          />
          <Tooltip content={<CustomTooltip />} />
          <Legend
            wrapperStyle={{ fontSize: '14px', paddingTop: '10px' }}
            iconType="line"
          />
          
          {/* J+K Actual (avgDays) */}
          {visibleLines.avgDays && (
            <Line
              yAxisId="left"
              type="monotone"
              dataKey="avgDays"
              stroke="#3b82f6"
              strokeWidth={2}
              dot={{ fill: '#3b82f6', r: 4 }}
              activeDot={{ r: 6 }}
              name={t('hc.performance_trend_chart.jk_actual')}
            />
          )}
          
          {/* % Actual (compliancePercent) */}
          {visibleLines.compliancePercent && (
            <Line
              yAxisId="right"
              type="monotone"
              dataKey="compliancePercent"
              stroke="#10b981"
              strokeWidth={2}
              dot={{ fill: '#10b981', r: 4 }}
            activeDot={{ r: 6 }}
            name={t('hc.performance_trend_chart.pct_actual')}
          />
          )}
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
