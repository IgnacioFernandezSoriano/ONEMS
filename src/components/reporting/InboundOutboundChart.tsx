import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ReferenceLine, ResponsiveContainer } from 'recharts';
import type { CityEquityData } from '@/types/reporting';

interface InboundOutboundChartProps {
  data: CityEquityData[];
}

export function InboundOutboundChart({ data }: InboundOutboundChartProps) {
  // Sort by direction gap (descending) and take top 10
  const topCities = [...data]
    .sort((a, b) => b.directionGap - a.directionGap)
    .slice(0, 10);

  const chartData = topCities.map((city) => ({
    city: city.cityName,
    inbound: city.inboundPercentage,
    outbound: city.outboundPercentage,
    standard: city.standardPercentage,
  }));

  // Calculate average standard for reference line
  const avgStandard =
    chartData.length > 0
      ? chartData.reduce((sum, d) => sum + d.standard, 0) / chartData.length
      : 90;

  return (
    <div className="w-full h-96">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={chartData} margin={{ top: 20, right: 30, left: 20, bottom: 60 }}>
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis dataKey="city" angle={-45} textAnchor="end" height={80} />
          <YAxis domain={[0, 100]} label={{ value: 'Compliance %', angle: -90, position: 'insideLeft' }} />
          <Tooltip formatter={(value: number) => `${value.toFixed(1)}%`} />
          <Legend />
          <ReferenceLine
            y={avgStandard}
            stroke="#ef4444"
            strokeDasharray="3 3"
            label={{ value: `Avg Standard (${avgStandard.toFixed(1)}%)`, position: 'right' }}
          />
          <Bar dataKey="inbound" fill="#3b82f6" name="Inbound %" />
          <Bar dataKey="outbound" fill="#10b981" name="Outbound %" />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
