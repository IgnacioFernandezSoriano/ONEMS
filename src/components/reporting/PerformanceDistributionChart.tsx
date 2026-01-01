import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer, Cell } from 'recharts';

interface JKRouteData {
  originCity: string;
  destinationCity: string;
  carrier: string;
  product: string;
  totalSamples: number;
  jkStandard: number;
  jkActual: number;
  onTimeSamples: number;
  beforeStandardSamples: number;
  afterStandardSamples: number;
  onTimePercentage: number;
  deviation: number;
  status: 'compliant' | 'warning' | 'critical';
  routeKey: string;
  distribution: Map<number, number>; // day -> count
}

interface PerformanceDistributionChartProps {
  routeData: JKRouteData[];
  maxDays: number;
}

export function PerformanceDistributionChart({ routeData, maxDays }: PerformanceDistributionChartProps) {
  if (!routeData || routeData.length === 0) {
    return (
      <div className="h-64 flex items-center justify-center text-gray-400">
        No performance data available
      </div>
    );
  }

  // Aggregate by actual transit days from individual shipments
  const distributionMap = new Map<number, { before: number; onTime: number; after: number }>();
  
  routeData.forEach(route => {
    // Use the distribution map from the route data (day -> count)
    route.distribution.forEach((count, days) => {
      if (!distributionMap.has(days)) {
        distributionMap.set(days, { before: 0, onTime: 0, after: 0 });
      }
      const dist = distributionMap.get(days)!;
      
      // Classify based on individual shipment days vs standard
      if (days < route.jkStandard) {
        dist.before += count;
      } else if (days === route.jkStandard) {
        dist.onTime += count;
      } else {
        dist.after += count;
      }
    });
  });

  // Convert to array and sort
  const chartData = Array.from(distributionMap.entries())
    .map(([day, counts]) => ({
      day,
      dayLabel: `${day}d`,
      before: counts.before,
      onTime: counts.onTime,
      after: counts.after,
      total: counts.before + counts.onTime + counts.after,
    }))
    .sort((a, b) => a.day - b.day)
    .slice(0, 15); // Limit to first 15 days for readability

  const CustomTooltip = ({ active, payload, label }: any) => {
    if (active && payload && payload.length) {
      const total = payload.reduce((sum: number, entry: any) => sum + entry.value, 0);
      return (
        <div className="bg-white border border-gray-200 rounded-lg shadow-lg p-3">
          <p className="font-semibold text-gray-900 mb-2">{label}</p>
          {payload.map((entry: any, index: number) => (
            <div key={index} className="flex items-center justify-between gap-4 text-sm">
              <div className="flex items-center gap-2">
                <div 
                  className="w-3 h-3 rounded" 
                  style={{ backgroundColor: entry.color }}
                />
                <span className="text-gray-600">{entry.name}:</span>
              </div>
              <span className="font-medium text-gray-900">
                {entry.value.toLocaleString()} ({((entry.value / total) * 100).toFixed(1)}%)
              </span>
            </div>
          ))}
          <div className="mt-2 pt-2 border-t border-gray-200">
            <div className="flex items-center justify-between text-sm font-semibold">
              <span className="text-gray-600">Total:</span>
              <span className="text-gray-900">{total.toLocaleString()}</span>
            </div>
          </div>
        </div>
      );
    }
    return null;
  };

  return (
    <div className="w-full h-64">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={chartData} margin={{ top: 10, right: 10, left: 0, bottom: 40 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
          <XAxis 
            dataKey="dayLabel" 
            tick={{ fontSize: 12, fill: '#6b7280' }}
            label={{ value: 'Transit Days (J+K)', position: 'insideBottom', offset: -10, style: { fontSize: 12, fill: '#6b7280' } }}
          />
          <YAxis 
            tick={{ fontSize: 12, fill: '#6b7280' }}
            label={{ value: 'Shipments', angle: -90, position: 'insideLeft', style: { fontSize: 12, fill: '#6b7280' } }}
          />
          <Tooltip content={<CustomTooltip />} />
          <Legend 
            wrapperStyle={{ fontSize: '12px', paddingTop: '20px' }}
            iconType="circle"
            verticalAlign="bottom"
          />
          <Bar 
            dataKey="before" 
            stackId="a" 
            fill="#10b981" 
            name="Before Standard"
            radius={[0, 0, 0, 0]}
          />
          <Bar 
            dataKey="onTime" 
            stackId="a" 
            fill="#3b82f6" 
            name="On Standard"
            radius={[0, 0, 0, 0]}
          />
          <Bar 
            dataKey="after" 
            stackId="a" 
            fill="#ef4444" 
            name="After Standard"
            radius={[4, 4, 0, 0]}
          />
        </BarChart>
      </ResponsiveContainer>
      <div className="mt-2 text-xs text-gray-500 text-center">
        Distribution of shipments by actual transit time vs delivery standard
      </div>
    </div>
  );
}
