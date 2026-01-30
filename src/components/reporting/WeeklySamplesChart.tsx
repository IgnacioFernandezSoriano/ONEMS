import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';

interface WeeklySample {
  weekStart: string;
  samples: number;
}

interface WeeklySamplesChartProps {
  data: WeeklySample[];
}

export function WeeklySamplesChart({ data }: WeeklySamplesChartProps) {
  if (!data || data.length === 0) {
    return (
      <div className="h-64 flex items-center justify-center text-gray-400">
        No weekly data available
      </div>
    );
  }

  // Format date for display with year
  const formattedData = data.map(item => ({
    ...item,
    weekLabel: new Date(item.weekStart).toLocaleDateString('es-ES', { 
      day: 'numeric',
      month: 'short',
      year: 'numeric'
    }),
  }));

  // Calculate average for reference
  const avgSamples = data.reduce((sum, item) => sum + item.samples, 0) / data.length;

  return (
    <div className="w-full h-64">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={formattedData} margin={{ top: 10, right: 10, left: 0, bottom: 20 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
          <XAxis 
            dataKey="weekLabel" 
            tick={{ fontSize: 12, fill: '#6b7280' }}
            angle={-45}
            textAnchor="end"
            height={60}
          />
          <YAxis 
            tick={{ fontSize: 12, fill: '#6b7280' }}
            label={{ value: 'Samples', angle: -90, position: 'insideLeft', style: { fontSize: 12, fill: '#6b7280' } }}
          />
          <Tooltip
            contentStyle={{
              backgroundColor: 'white',
              border: '1px solid #e5e7eb',
              borderRadius: '8px',
              padding: '8px 12px',
            }}
            formatter={(value: any) => typeof value === 'number' ? [value.toLocaleString(), 'Samples'] : ['', '']}
            labelFormatter={(label) => `Week of ${label}`}
          />
          <Bar dataKey="samples" fill="#3b82f6" radius={[4, 4, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
      <div className="mt-2 text-xs text-gray-500 text-center">
        Average: {avgSamples.toFixed(0)} samples/week
      </div>
    </div>
  );
}
