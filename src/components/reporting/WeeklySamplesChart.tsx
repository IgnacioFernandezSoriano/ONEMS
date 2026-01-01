import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Cell } from 'recharts';

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

  // Format date for display
  const formattedData = data.map(item => ({
    ...item,
    weekLabel: new Date(item.weekStart).toLocaleDateString('es-ES', { 
      month: 'short', 
      day: 'numeric' 
    }),
  }));

  // Calculate average for reference line
  const avgSamples = data.reduce((sum, item) => sum + item.samples, 0) / data.length;

  // Color bars based on sample count (green if above average, blue otherwise)
  const getBarColor = (samples: number) => {
    if (samples >= avgSamples * 1.2) return '#10b981'; // green-500
    if (samples >= avgSamples) return '#3b82f6'; // blue-500
    if (samples >= avgSamples * 0.8) return '#f59e0b'; // amber-500
    return '#ef4444'; // red-500
  };

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
          <Bar dataKey="samples" radius={[4, 4, 0, 0]}>
            {formattedData.map((entry, index) => (
              <Cell key={`cell-${index}`} fill={getBarColor(entry.samples)} />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
      <div className="mt-2 space-y-2">
        <div className="text-xs text-gray-500 text-center">
          Average: {avgSamples.toFixed(0)} samples/week
        </div>
        <div className="flex items-center justify-center gap-4 text-xs">
          <div className="flex items-center gap-1.5">
            <div className="w-3 h-3 rounded bg-green-500"></div>
            <span className="text-gray-600">≥120% avg</span>
          </div>
          <div className="flex items-center gap-1.5">
            <div className="w-3 h-3 rounded bg-blue-500"></div>
            <span className="text-gray-600">≥100% avg</span>
          </div>
          <div className="flex items-center gap-1.5">
            <div className="w-3 h-3 rounded bg-amber-500"></div>
            <span className="text-gray-600">80-100% avg</span>
          </div>
          <div className="flex items-center gap-1.5">
            <div className="w-3 h-3 rounded bg-red-500"></div>
            <span className="text-gray-600">&lt;80% avg</span>
          </div>
        </div>
      </div>
    </div>
  );
}
