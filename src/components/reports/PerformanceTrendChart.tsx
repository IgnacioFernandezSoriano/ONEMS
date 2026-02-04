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

interface TrendDataPoint {
  date: string;
  avgDays: number;
  compliancePercent: number;
  standardDays: number;
  standardPercent: number;
}

interface PerformanceTrendChartProps {
  data: TrendDataPoint[];
  title?: string;
}

type TimeScale = 'day' | 'week' | 'month';

export function PerformanceTrendChart({ data, title = 'Performance Trend' }: PerformanceTrendChartProps) {
  const [timeScale, setTimeScale] = useState<TimeScale>('day');

  // Aggregate data based on time scale
  const aggregatedData = useMemo(() => {
    if (!data || data.length === 0) return [];

    if (timeScale === 'day') {
      return data.map((point) => ({
        ...point,
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
      group.totalAvgDays += point.avgDays;
      group.totalCompliance += point.compliancePercent;
      group.totalStandardDays += point.standardDays;
      group.totalStandardPercent += point.standardPercent;
      group.count++;
    });

    return Array.from(groupMap.entries())
      .map(([dateKey, group]) => ({
        date: dateKey,
        avgDays: group.totalAvgDays / group.count,
        compliancePercent: group.totalCompliance / group.count,
        standardDays: group.totalStandardDays / group.count,
        standardPercent: group.totalStandardPercent / group.count,
        displayDate:
          timeScale === 'week'
            ? `Week of ${format(new Date(dateKey), 'MMM d')}`
            : format(new Date(dateKey), 'MMM yyyy'),
      }))
      .sort((a, b) => a.date.localeCompare(b.date));
  }, [data, timeScale]);

  // Custom tooltip - shows all 4 metrics
  const CustomTooltip = ({ active, payload }: any) => {
    if (active && payload && payload.length) {
      const data = payload[0].payload;
      return (
        <div className="bg-white p-3 border border-gray-300 rounded shadow-lg">
          <p className="font-semibold text-gray-800 mb-2">{data.displayDate}</p>
          <p className="text-blue-600">
            <span className="font-medium">J+K Actual:</span> {data.avgDays.toFixed(2)} days
          </p>
          <p className="text-green-600">
            <span className="font-medium">% Actual:</span> {data.compliancePercent.toFixed(1)}%
          </p>
          <p className="text-purple-600">
            <span className="font-medium">J+K STD:</span> {data.standardDays.toFixed(2)} days
          </p>
          <p className="text-orange-600">
            <span className="font-medium">% STD:</span> {data.standardPercent.toFixed(1)}%
          </p>
        </div>
      );
    }
    return null;
  };

  if (!data || data.length === 0) {
    return (
      <div className="bg-white p-6 rounded-lg shadow">
        <h3 className="text-lg font-semibold text-gray-800 mb-4">{title}</h3>
        <p className="text-gray-500">No data available for the selected period</p>
      </div>
    );
  }

  return (
    <div className="bg-white p-6 rounded-lg shadow">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-semibold text-gray-800">{title}</h3>
        <div className="flex gap-2">
          <button
            onClick={() => setTimeScale('day')}
            className={`px-3 py-1 text-sm rounded transition-colors ${
              timeScale === 'day'
                ? 'bg-blue-600 text-white'
                : 'bg-gray-200 text-gray-700 hover:bg-gray-300'
            }`}
          >
            Day
          </button>
          <button
            onClick={() => setTimeScale('week')}
            className={`px-3 py-1 text-sm rounded transition-colors ${
              timeScale === 'week'
                ? 'bg-blue-600 text-white'
                : 'bg-gray-200 text-gray-700 hover:bg-gray-300'
            }`}
          >
            Week
          </button>
          <button
            onClick={() => setTimeScale('month')}
            className={`px-3 py-1 text-sm rounded transition-colors ${
              timeScale === 'month'
                ? 'bg-blue-600 text-white'
                : 'bg-gray-200 text-gray-700 hover:bg-gray-300'
            }`}
          >
            Month
          </button>
        </div>
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
            label={{ value: 'Days', angle: -90, position: 'insideLeft', style: { fill: '#3b82f6' } }}
            style={{ fontSize: '12px' }}
          />
          <YAxis
            yAxisId="right"
            orientation="right"
            stroke="#10b981"
            domain={[0, 100]}
            label={{ value: 'Percentage %', angle: 90, position: 'insideRight', style: { fill: '#10b981' } }}
            style={{ fontSize: '12px' }}
          />
          <Tooltip content={<CustomTooltip />} />
          <Legend
            wrapperStyle={{ fontSize: '14px', paddingTop: '10px' }}
            iconType="line"
          />
          
          {/* J+K Actual (avgDays) */}
          <Line
            yAxisId="left"
            type="monotone"
            dataKey="avgDays"
            stroke="#3b82f6"
            strokeWidth={2}
            dot={{ fill: '#3b82f6', r: 4 }}
            activeDot={{ r: 6 }}
            name="J+K Actual"
          />
          
          {/* % Actual (compliancePercent) */}
          <Line
            yAxisId="right"
            type="monotone"
            dataKey="compliancePercent"
            stroke="#10b981"
            strokeWidth={2}
            dot={{ fill: '#10b981', r: 4 }}
            activeDot={{ r: 6 }}
            name="% Actual"
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
