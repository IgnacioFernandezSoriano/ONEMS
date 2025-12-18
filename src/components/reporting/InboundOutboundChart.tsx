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
    inboundStandardPercentage: city.inboundStandardPercentage,
    outboundStandardPercentage: city.outboundStandardPercentage,
    inboundStandardDays: city.inboundStandardDays,
    inboundActualDays: city.inboundActualDays,
    outboundStandardDays: city.outboundStandardDays,
    outboundActualDays: city.outboundActualDays,
  }));

  // Calculate average standard for reference line (using inbound as reference)
  const avgStandard =
    chartData.length > 0
      ? chartData.reduce((sum, d) => sum + d.inboundStandardPercentage, 0) / chartData.length
      : 90;

  return (
    <div className="w-full h-96">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={chartData} margin={{ top: 20, right: 30, left: 20, bottom: 60 }}>
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis dataKey="city" angle={-45} textAnchor="end" height={80} />
          <YAxis domain={[0, 100]} label={{ value: 'Compliance %', angle: -90, position: 'insideLeft' }} />
          <Tooltip 
            formatter={(value: any) => typeof value === 'number' ? `${value.toFixed(1)}%` : ''}
            content={({ active, payload }) => {
              if (active && payload && payload.length) {
                const data = payload[0].payload;
                return (
                  <div className="bg-white p-3 border border-gray-300 rounded shadow-lg">
                    <p className="font-semibold mb-2">{data.city}</p>
                    <div className="mb-2">
                      <p className="text-blue-600 font-medium">Inbound:</p>
                      <p className="text-sm ml-2">Std %: {data.inboundStandardPercentage.toFixed(1)}% | Actual %: {data.inbound.toFixed(1)}%</p>
                      <p className="text-sm ml-2">J+K Std: {data.inboundStandardDays.toFixed(1)} days | J+K Actual: {data.inboundActualDays.toFixed(1)} days</p>
                    </div>
                    <div>
                      <p className="text-green-600 font-medium">Outbound:</p>
                      <p className="text-sm ml-2">Std %: {data.outboundStandardPercentage.toFixed(1)}% | Actual %: {data.outbound.toFixed(1)}%</p>
                      <p className="text-sm ml-2">J+K Std: {data.outboundStandardDays.toFixed(1)} days | J+K Actual: {data.outboundActualDays.toFixed(1)} days</p>
                    </div>
                  </div>
                );
              }
              return null;
            }}
          />
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
