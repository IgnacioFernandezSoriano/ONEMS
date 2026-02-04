import React from 'react';
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
import { format } from 'date-fns';

interface TrendDataPoint {
  date: string;
  avgDays: number;
  compliancePercent: number;
}

interface PerformanceTrendChartProps {
  data: TrendDataPoint[];
}

export function PerformanceTrendChart({ data }: PerformanceTrendChartProps) {
  // Format data for display
  const formattedData = data.map((point) => ({
    ...point,
    displayDate: format(new Date(point.date), 'MMM d'),
  }));

  // Custom tooltip
  const CustomTooltip = ({ active, payload }: any) => {
    if (active && payload && payload.length) {
      const data = payload[0].payload;
      return (
        <div className="bg-white p-3 border border-gray-300 rounded shadow-lg">
          <p className="font-semibold text-gray-800 mb-2">{data.displayDate}</p>
          <p className="text-blue-600">
            <span className="font-medium">Avg Days:</span> {data.avgDays.toFixed(2)}
          </p>
          <p className="text-green-600">
            <span className="font-medium">Compliance %:</span> {data.compliancePercent.toFixed(1)}
          </p>
        </div>
      );
    }
    return null;
  };

  if (!data || data.length === 0) {
    return (
      <div className="bg-white p-6 rounded-lg shadow">
        <h3 className="text-lg font-semibold text-gray-800 mb-4">Performance Trend</h3>
        <p className="text-gray-500">No data available for the selected period</p>
      </div>
    );
  }

  return (
    <div className="bg-white p-6 rounded-lg shadow">
      <h3 className="text-lg font-semibold text-gray-800 mb-4">Performance Trend</h3>
      <ResponsiveContainer width="100%" height={300}>
        <LineChart data={formattedData} margin={{ top: 5, right: 30, left: 20, bottom: 5 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
          <XAxis
            dataKey="displayDate"
            stroke="#6b7280"
            style={{ fontSize: '12px' }}
          />
          <YAxis
            yAxisId="left"
            stroke="#3b82f6"
            label={{ value: 'Avg Days', angle: -90, position: 'insideLeft', style: { fill: '#3b82f6' } }}
            style={{ fontSize: '12px' }}
          />
          <YAxis
            yAxisId="right"
            orientation="right"
            stroke="#10b981"
            domain={[0, 100]}
            label={{ value: 'Compliance %', angle: 90, position: 'insideRight', style: { fill: '#10b981' } }}
            style={{ fontSize: '12px' }}
          />
          <Tooltip content={<CustomTooltip />} />
          <Legend
            wrapperStyle={{ fontSize: '14px', paddingTop: '10px' }}
            iconType="line"
          />
          <Line
            yAxisId="left"
            type="monotone"
            dataKey="avgDays"
            stroke="#3b82f6"
            strokeWidth={2}
            dot={{ fill: '#3b82f6', r: 4 }}
            activeDot={{ r: 6 }}
            name="Avg Days"
          />
          <Line
            yAxisId="right"
            type="monotone"
            dataKey="compliancePercent"
            stroke="#10b981"
            strokeWidth={2}
            dot={{ fill: '#10b981', r: 4 }}
            activeDot={{ r: 6 }}
            name="Compliance %"
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
