import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, ReferenceLine, Cell, Legend } from 'recharts';
import { useMemo } from 'react';
import { formatNumber } from '@/lib/formatNumber';

interface RouteDistribution {
  routeKey: string;
  originCity: string;
  destinationCity: string;
  carrier: string;
  product: string;
  jkStandard: number;
  standardPercentage: number; // target percentage (e.g., 85%)
  distribution: Map<number, number>; // day -> count
  totalSamples: number;
}

interface CumulativeDistributionChartProps {
  routes: RouteDistribution[];
  maxDays: number;
  selectedRoute?: string; // routeKey to display, if undefined show aggregated
}

export function CumulativeDistributionChart({ routes, maxDays, selectedRoute }: CumulativeDistributionChartProps) {
  const { chartData, standardDay, standardPercentage } = useMemo(() => {
    if (!routes || routes.length === 0) {
      return { chartData: [], standardDay: 0, standardPercentage: 85 };
    }

    // Filter to selected route or aggregate all
    const targetRoutes = selectedRoute 
      ? routes.filter(r => r.routeKey === selectedRoute)
      : routes;

    if (targetRoutes.length === 0) {
      return { chartData: [], standardDay: 0, standardPercentage: 85 };
    }

    // Calculate aggregated distribution
    const aggregatedDistribution = new Map<number, number>();
    let totalSamples = 0;
    let avgStandard = 0;
    let avgStandardPercentage = 0;

    targetRoutes.forEach(route => {
      route.distribution.forEach((count, day) => {
        aggregatedDistribution.set(day, (aggregatedDistribution.get(day) || 0) + count);
      });
      totalSamples += route.totalSamples;
      avgStandard += route.jkStandard * route.totalSamples;
      avgStandardPercentage += route.standardPercentage * route.totalSamples;
    });

    avgStandard = totalSamples > 0 ? avgStandard / totalSamples : 0;
    avgStandardPercentage = totalSamples > 0 ? avgStandardPercentage / totalSamples : 85;

    // Build cumulative chart data
    const maxDisplayDays = Math.min(maxDays, 20);
    const data: any[] = [];
    let cumulativeCount = 0;

    for (let day = 0; day <= maxDisplayDays; day++) {
      const count = aggregatedDistribution.get(day) || 0;
      cumulativeCount += count;
      const cumulativePercentage = totalSamples > 0 ? (cumulativeCount / totalSamples) * 100 : 0;

      data.push({
        day,
        dayLabel: `${day}d`,
        cumulativePercentage,
        isBeforeOrAtStandard: day <= Math.round(avgStandard),
      });

      // Stop when we reach 100%
      if (cumulativePercentage >= 99.9) break;
    }

    return {
      chartData: data,
      standardDay: Math.round(avgStandard),
      standardPercentage: avgStandardPercentage,
    };
  }, [routes, maxDays, selectedRoute]);

  if (chartData.length === 0) {
    return (
      <div className="h-80 flex items-center justify-center text-gray-400">
        No distribution data available
      </div>
    );
  }

  const CustomTooltip = ({ active, payload }: any) => {
    if (active && payload && payload.length) {
      const data = payload[0].payload;
      return (
        <div className="bg-white border border-gray-200 rounded-lg shadow-lg p-3">
          <p className="font-semibold text-gray-900 mb-1">{data.dayLabel}</p>
          <div className="text-sm text-gray-600">
            Cumulative: <span className="font-medium text-gray-900">{formatNumber(data.cumulativePercentage)}%</span>
          </div>
          {data.day === standardDay && (
            <div className="mt-1 text-xs text-green-600 font-medium">
              ← J+K Standard
            </div>
          )}
        </div>
      );
    }
    return null;
  };

  // Calculate chart width based on number of bars
  const chartWidth = Math.max(400, Math.min(800, chartData.length * 80 + 150));

  return (
    <div className="w-full h-80 flex justify-center">
      <div style={{ width: chartWidth, height: '100%' }}>
        <BarChart
          width={chartWidth}
          height={320}
          data={chartData}
          margin={{ top: 20, right: 30, left: 60, bottom: 20 }}
          barSize={40}
        >
          <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
          <XAxis 
            dataKey="dayLabel" 
            tick={{ fontSize: 12, fill: '#6b7280' }}
            label={{ 
              value: 'Transit Days (J+K)', 
              position: 'insideBottom', 
              offset: -15, 
              style: { fontSize: 13, fill: '#374151', fontWeight: 500 } 
            }}
            height={60}
          />
          <YAxis 
            tick={{ fontSize: 12, fill: '#6b7280' }}
            domain={[0, 100]}
            label={{ 
              value: 'Cumulative %', 
              angle: -90, 
              position: 'insideLeft', 
              style: { fontSize: 13, fill: '#374151', fontWeight: 500 } 
            }}
          />
          <Tooltip content={<CustomTooltip />} />

          
          {/* Reference line for standard percentage */}
          <ReferenceLine 
            y={standardPercentage} 
            stroke="#3b82f6" 
            strokeDasharray="5 5" 
            strokeWidth={2}
            label={{ 
              value: `${standardPercentage.toFixed(0)}% Target`, 
              position: 'right',
              fill: '#3b82f6',
              fontSize: 11,
              fontWeight: 600,
            }}
          />

          {/* Reference line for standard day */}
          <ReferenceLine 
            x={standardDay - 1} 
            stroke="#10b981" 
            strokeWidth={2}
            label={{ 
              value: `${standardDay}d Std`, 
              position: 'top',
              fill: '#10b981',
              fontSize: 11,
              fontWeight: 600,
            }}
          />

          <Bar dataKey="cumulativePercentage" radius={[4, 4, 0, 0]} barSize={40}>
            {chartData.map((entry, index) => (
              <Cell 
                key={`cell-${index}`} 
                fill={entry.isBeforeOrAtStandard ? '#10b981' : '#ef4444'} 
              />
            ))}
          </Bar>
        </BarChart>
      </div>
    </div>
  );
}
