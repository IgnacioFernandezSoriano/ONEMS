import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ReferenceLine, ResponsiveContainer, Cell } from 'recharts';
import type { RegionEquityData } from '@/types/reporting';

interface RegionalEquityChartProps {
  data: RegionEquityData[];
}

export function RegionalEquityChart({ data }: RegionalEquityChartProps) {
  const chartData = data.map((region) => ({
    region: region.regionName,
    actual: region.actualPercentage,
    standard: region.standardPercentage,
    standardDays: region.standardDays,
    actualDays: region.actualDays,
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
          <XAxis type="number" domain={[0, 100]} label={{ value: 'Compliance %', position: 'bottom' }} />
          <YAxis type="category" dataKey="region" />
          <Tooltip 
            content={({ active, payload }) => {
              if (active && payload && payload.length) {
                const data = payload[0].payload;
                return (
                  <div className="bg-white p-3 border border-gray-300 rounded shadow-lg">
                    <p className="font-semibold">{data.region}</p>
                    <p className="text-blue-600">Actual: {data.actual.toFixed(1)}%</p>
                    <p className="text-gray-600">Standard: {data.standard.toFixed(1)}%</p>
                    <p className="text-gray-500 text-sm mt-1">J+K Std: {data.standardDays.toFixed(1)} days</p>
                    <p className="text-gray-500 text-sm">J+K Actual: {data.actualDays.toFixed(1)} days</p>
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
            label={{ value: `Avg Standard (${avgStandard.toFixed(1)}%)`, position: 'top' }}
          />
          <Bar dataKey="actual" name="Actual Compliance %">
            {chartData.map((entry, index) => (
              <Cell key={`cell-${index}`} fill={getBarColor(entry.status)} />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
