import { useMemo } from 'react';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import type { JKRouteData } from '@/hooks/reporting/useJKPerformance';

interface JKPerformanceDistributionProps {
  routeData: JKRouteData[];
}

export function JKPerformanceDistribution({ routeData }: JKPerformanceDistributionProps) {
  const distributionData = useMemo(() => {
    // Aggregate distribution across all routes
    const dayCountMap = new Map<number, { before: number; on: number; after: number }>();
    
    routeData.forEach(route => {
      const jkStd = Math.round(route.jkStandard);
      
      route.distribution.forEach((count, day) => {
        if (!dayCountMap.has(day)) {
          dayCountMap.set(day, { before: 0, on: 0, after: 0 });
        }
        
        const entry = dayCountMap.get(day)!;
        if (day < jkStd) {
          entry.before += count;
        } else if (day === jkStd) {
          entry.on += count;
        } else {
          entry.after += count;
        }
      });
    });
    
    // Convert to array and sort by day
    const data = Array.from(dayCountMap.entries())
      .map(([day, counts]) => ({
        day,
        'Before Standard': counts.before,
        'On Standard': counts.on,
        'After Standard': counts.after,
      }))
      .sort((a, b) => a.day - b.day);
    
    return data;
  }, [routeData]);

  if (distributionData.length === 0) {
    return (
      <div className="flex items-center justify-center h-64 text-gray-400">
        No distribution data available
      </div>
    );
  }

  return (
    <ResponsiveContainer width="100%" height={300}>
      <BarChart data={distributionData}>
        <CartesianGrid strokeDasharray="3 3" />
        <XAxis 
          dataKey="day" 
          label={{ value: 'Days', position: 'insideBottom', offset: -5 }}
        />
        <YAxis 
          label={{ value: 'Samples', angle: -90, position: 'insideLeft' }}
        />
        <Tooltip />
        <Legend />
        <Bar dataKey="Before Standard" stackId="a" fill="#10b981" />
        <Bar dataKey="On Standard" stackId="a" fill="#3b82f6" />
        <Bar dataKey="After Standard" stackId="a" fill="#ef4444" />
      </BarChart>
    </ResponsiveContainer>
  );
}
