import React from 'react';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer, ReferenceLine } from 'recharts';
import type { ShipmentTracking } from '@/types/reporting';

interface TimelineChartProps {
  data: ShipmentTracking[];
}

export function TimelineChart({ data }: TimelineChartProps) {
  if (data.length === 0) {
    return (
      <div className="text-center py-8 text-gray-500">
        No shipment data available for timeline
      </div>
    );
  }

  const chartData = data.slice(0, 20).map(shipment => ({
    tagId: shipment.tagId,
    businessDays: shipment.businessTransitDays,
    maxAllowed: shipment.standardDeliveryHours / 24,
    onTime: shipment.onTimeDelivery
  }));

  return (
    <div className="w-full h-80">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={chartData} margin={{ top: 20, right: 30, left: 20, bottom: 60 }}>
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis 
            dataKey="tagId" 
            angle={-45} 
            textAnchor="end" 
            height={80}
            tick={{ fontSize: 11 }}
          />
          <YAxis 
            label={{ value: 'Business Days', angle: -90, position: 'insideLeft' }}
          />
          <Tooltip 
            formatter={(value: number | undefined) => value !== undefined ? value.toFixed(1) : ''}
            labelFormatter={(label) => `Shipment: ${label}`}
          />
          <Legend 
            verticalAlign="top" 
            height={36}
          />
          <ReferenceLine y={1} stroke="#22c55e" strokeDasharray="3 3" label="Target: 1 day" />
          <Bar 
            dataKey="businessDays" 
            fill="#3b82f6" 
            name="Actual Transit Days"
          />
          <Bar 
            dataKey="maxAllowed" 
            fill="#94a3b8" 
            name="Max Allowed"
            opacity={0.5}
          />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
