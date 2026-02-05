import { useMemo, useState } from 'react';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer, ReferenceLine, Cell } from 'recharts';
import { BarChart3, Table } from 'lucide-react';
import type { JKRouteData } from '@/hooks/reporting/useJKPerformance';

interface JKCumulativeDistributionProps {
  routeData: JKRouteData[];
}

export function JKCumulativeDistribution({ routeData }: JKCumulativeDistributionProps) {
  const [viewMode, setViewMode] = useState<'chart' | 'table'>('chart');

  const { cumulativeData, avgStandard, avgTarget } = useMemo(() => {
    if (routeData.length === 0) {
      return { cumulativeData: [], avgStandard: 0, avgTarget: 0 };
    }

    // Aggregate distribution across all routes
    const dayCountMap = new Map<number, number>();
    let totalSamples = 0;
    let totalStandard = 0;
    let totalTarget = 0;

    routeData.forEach(route => {
      totalStandard += route.jkStandard * route.totalSamples;
      totalTarget += route.standardPercentage * route.totalSamples;
      totalSamples += route.totalSamples;

      route.distribution.forEach((count, day) => {
        dayCountMap.set(day, (dayCountMap.get(day) || 0) + count);
      });
    });

    const avgStd = totalSamples > 0 ? totalStandard / totalSamples : 0;
    const avgTgt = totalSamples > 0 ? totalTarget / totalSamples : 95;

    // Convert to array, sort, and calculate cumulative
    const sortedDays = Array.from(dayCountMap.entries())
      .sort((a, b) => a[0] - b[0]);

    let cumulative = 0;
    const data = sortedDays.map(([day, count]) => {
      cumulative += count;
      const cumulativePercentage = (cumulative / totalSamples) * 100;
      const isBefore = day < Math.round(avgStd);
      const isOn = day === Math.round(avgStd);

      return {
        day,
        count,
        cumulative,
        cumulativePercentage,
        color: isBefore ? '#10b981' : isOn ? '#6b7280' : '#ef4444',
      };
    });

    return { cumulativeData: data, avgStandard: avgStd, avgTarget: avgTgt };
  }, [routeData]);

  if (cumulativeData.length === 0) {
    return (
      <div className="flex items-center justify-center h-64 text-gray-400">
        No cumulative data available
      </div>
    );
  }

  const CustomTooltip = ({ active, payload }: any) => {
    if (active && payload && payload.length) {
      const data = payload[0].payload;
      return (
        <div className="bg-white p-3 border border-gray-200 rounded shadow-lg">
          <p className="font-semibold">{data.day}d</p>
          <p className="text-sm text-gray-600">
            Cumulative: <span className="font-semibold">{data.cumulativePercentage.toFixed(1)}%</span>
          </p>
        </div>
      );
    }
    return null;
  };

  return (
    <div>
      {/* Toggle buttons */}
      <div className="flex justify-end mb-2">
        <div className="inline-flex rounded-lg border border-gray-200 p-1">
          <button
            onClick={() => setViewMode('chart')}
            className={`px-3 py-1 rounded-md text-sm font-medium transition-colors flex items-center gap-1 ${
              viewMode === 'chart'
                ? 'bg-blue-600 text-white'
                : 'text-gray-600 hover:text-gray-900'
            }`}
          >
            <BarChart3 className="w-4 h-4" />
            Chart
          </button>
          <button
            onClick={() => setViewMode('table')}
            className={`px-3 py-1 rounded-md text-sm font-medium transition-colors flex items-center gap-1 ${
              viewMode === 'table'
                ? 'bg-blue-600 text-white'
                : 'text-gray-600 hover:text-gray-900'
            }`}
          >
            <Table className="w-4 h-4" />
            Table
          </button>
        </div>
      </div>

      {viewMode === 'chart' ? (
        <ResponsiveContainer width="100%" height={300}>
          <BarChart data={cumulativeData}>
            <CartesianGrid strokeDasharray="3 3" />
            <XAxis 
              dataKey="day" 
              label={{ value: 'Transit Days (J+K)', position: 'insideBottom', offset: -5 }}
            />
            <YAxis 
              label={{ value: 'Cumulative %', angle: -90, position: 'insideLeft' }}
              domain={[0, 100]}
            />
            <Tooltip content={<CustomTooltip />} />
            <ReferenceLine 
              y={avgTarget} 
              stroke="#3b82f6" 
              strokeDasharray="5 5" 
              strokeWidth={2}
              label={{ value: `${avgTarget.toFixed(0)}%`, position: 'right' }}
            />
            <Bar dataKey="cumulativePercentage">
              {cumulativeData.map((entry, index) => (
                <Cell key={`cell-${index}`} fill={entry.color} />
              ))}
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      ) : (
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200">
            <thead className="bg-gray-50">
              <tr>
                {cumulativeData.map((data) => (
                  <th
                    key={data.day}
                    className="px-3 py-2 text-center text-xs font-medium text-gray-700 uppercase tracking-wider"
                  >
                    {data.day}D
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              <tr>
                {cumulativeData.map((data) => (
                  <td
                    key={data.day}
                    className={`px-3 py-2 text-center text-sm font-medium ${
                      data.cumulativePercentage >= avgTarget
                        ? 'text-green-600'
                        : 'text-red-600'
                    }`}
                  >
                    {data.cumulativePercentage.toFixed(1)}%
                  </td>
                ))}
              </tr>
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
