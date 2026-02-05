import { ComposedChart, Bar, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer, ReferenceLine } from 'recharts';
import { formatNumber } from '@/lib/formatNumber';

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
  standardPercentage: number;
  status: 'compliant' | 'warning' | 'critical';
  routeKey: string;
  distribution: Map<number, number>; // day -> count
}

interface PerformanceDistributionChartProps {
  routeData: JKRouteData[];
  maxDays: number;
  carrierFilter?: string;
  productFilter?: string;
}

export function PerformanceDistributionChart({ routeData, maxDays, carrierFilter, productFilter }: PerformanceDistributionChartProps) {
  if (!routeData || routeData.length === 0) {
    return (
      <div className="h-80 flex items-center justify-center text-gray-400">
        No performance data available
      </div>
    );
  }

  // Check if we have a single carrier-product combination
  const isSingleCarrierProduct = !!(carrierFilter && productFilter);
  
  // Get the standard percentage and J+K standard for this carrier-product (weighted average if multiple routes)
  let targetStandardPercentage = 0;
  let targetJKDays = 0;
  
  if (isSingleCarrierProduct && routeData.length > 0) {
    const totalSamples = routeData.reduce((sum, r) => sum + r.totalSamples, 0);
    const weightedStdPercentage = routeData.reduce((sum, r) => sum + r.standardPercentage * r.totalSamples, 0);
    const weightedJKStandard = routeData.reduce((sum, r) => sum + r.jkStandard * r.totalSamples, 0);
    targetStandardPercentage = totalSamples > 0 ? weightedStdPercentage / totalSamples : 0;
    targetJKDays = totalSamples > 0 ? Math.round(weightedJKStandard / totalSamples) : 0;
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

  // Calculate cumulative samples and find day where STD % is reached
  let dayReachingStdPercentage: number | null = null;
  
  if (isSingleCarrierProduct && targetStandardPercentage > 0) {
    let cumulative = 0;
    const totalSamples = chartData.reduce((sum, d) => sum + d.total, 0);
    const targetSamplesCount = (totalSamples * targetStandardPercentage) / 100;
    
    chartData.forEach(item => {
      cumulative += item.total;
      const cumulativePercentage = (cumulative / totalSamples) * 100;
      (item as any).cumulative = cumulative;
      (item as any).cumulativePercentage = cumulativePercentage;
      
      // Mark the day where we reach or exceed the target percentage
      if (dayReachingStdPercentage === null && cumulative >= targetSamplesCount) {
        dayReachingStdPercentage = item.day;
      }
    });
  }

  const CustomTooltip = ({ active, payload, label }: any) => {
    if (active && payload && payload.length) {
      const barPayload = payload.filter((p: any) => p.dataKey !== 'cumulative');
      const cumulativePayload = payload.find((p: any) => p.dataKey === 'cumulative');
      const total = barPayload.reduce((sum: number, entry: any) => sum + entry.value, 0);
      
      // Get cumulative percentage from the data point
      const dataPoint = payload[0]?.payload;
      const cumulativePercentage = dataPoint?.cumulativePercentage;
      
      return (
        <div className="bg-white border border-gray-200 rounded-lg shadow-lg p-3">
          <p className="font-semibold text-gray-900 mb-2">{label}</p>
          
          {/* Cumulative info first */}
          {cumulativePayload && cumulativePercentage !== undefined && (
            <div className="mb-2 pb-2 border-b border-gray-200">
              <div className="flex items-center justify-between text-sm font-semibold text-gray-900">
                <span>Cumulative:</span>
                <span>{cumulativePayload.value.toLocaleString()}</span>
              </div>
              <div className="flex items-center justify-between text-xs text-gray-600 mt-1">
                <span>% of Total:</span>
                <span>{formatNumber(cumulativePercentage)}% (Target: {targetStandardPercentage.toFixed(0)}%)</span>
              </div>
            </div>
          )}
          
          {/* Bar data */}
          {barPayload.map((entry: any, index: number) => (
            <div key={index} className="flex items-center justify-between gap-4 text-sm">
              <div className="flex items-center gap-2">
                <div 
                  className="w-3 h-3 rounded" 
                  style={{ backgroundColor: entry.color }}
                />
                <span className="text-gray-600">{entry.name}:</span>
              </div>
              <span className="font-medium text-gray-900">
                {entry.value.toLocaleString()} ({formatNumber((entry.value / total) * 100)}%)
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
    <div className="w-full h-80">
      <ResponsiveContainer width="100%" height="100%">
        <ComposedChart data={chartData} margin={{ top: 10, right: isSingleCarrierProduct ? 40 : 10, left: 0, bottom: 40 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
          <XAxis 
            dataKey="dayLabel" 
            tick={{ fontSize: 12, fill: '#6b7280' }}
            label={{ value: 'Transit Days (J+K)', position: 'insideBottom', offset: -10, style: { fontSize: 12, fill: '#6b7280' } }}
          />
          <YAxis 
            yAxisId="left"
            tick={{ fontSize: 12, fill: '#6b7280' }}
            label={{ value: 'Shipments', angle: -90, position: 'insideLeft', style: { fontSize: 12, fill: '#6b7280' } }}
          />
          {isSingleCarrierProduct && (
            <YAxis 
              yAxisId="right"
              orientation="right"
              tick={{ fontSize: 12, fill: '#000000' }}
              label={{ value: 'Cumulative Samples', angle: 90, position: 'insideRight', style: { fontSize: 12, fill: '#000000' } }}
            />
          )}
          <Tooltip content={<CustomTooltip />} />

          
          {/* Vertical line at day reaching STD % */}
          {isSingleCarrierProduct && dayReachingStdPercentage !== null && (
            <ReferenceLine 
              x={`${dayReachingStdPercentage}d`} 
              stroke="#000000" 
              strokeWidth={2}
              strokeDasharray="5 5"
              label={{ 
                value: `${targetStandardPercentage.toFixed(0)}% at ${dayReachingStdPercentage}d`, 
                position: 'top',
                fill: '#000000',
                fontSize: 11,
                fontWeight: 'bold'
              }}
            />
          )}
          
          <Bar 
            dataKey="before" 
            stackId="a" 
            fill="#10b981" 
            name="Before Standard"
            radius={[0, 0, 0, 0]}
            yAxisId="left"
          />
          <Bar 
            dataKey="onTime" 
            stackId="a" 
            fill="#3b82f6" 
            name="On Standard"
            radius={[0, 0, 0, 0]}
            yAxisId="left"
          />
          <Bar 
            dataKey="after" 
            stackId="a" 
            fill="#ef4444" 
            name="After Standard"
            radius={[4, 4, 0, 0]}
            yAxisId="left"
          />
          
          {/* Cumulative line in black */}
          {isSingleCarrierProduct && (
            <Line 
              type="monotone"
              dataKey="cumulative"
              stroke="#000000"
              strokeWidth={2}
              dot={{ fill: '#000000', r: 4 }}
              name="Cumulative Samples"
              yAxisId="right"
            />
          )}
        </ComposedChart>
      </ResponsiveContainer>
      <div className="mt-2 text-xs text-gray-500 text-center">
        Distribution of shipments by actual transit time vs delivery standard
        {isSingleCarrierProduct && targetStandardPercentage > 0 && dayReachingStdPercentage !== null && (
          <span className="ml-2 text-gray-900 font-medium">
            • {carrierFilter} - {productFilter}: {targetStandardPercentage.toFixed(0)}% reached at {dayReachingStdPercentage}d (J+K Std: {targetJKDays}d)
          </span>
        )}
      </div>
    </div>
  );
}
