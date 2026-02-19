import React from 'react';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ReferenceLine, ResponsiveContainer } from 'recharts';
import { formatNumber } from '@/lib/formatNumber';
import type { CityEquityData } from '@/types/reporting';
import { useTranslation } from '@/hooks/useTranslation';

interface InboundOutboundChartProps {
  data: CityEquityData[];
  scenarioDescription: string;
}

export function InboundOutboundChart({ data, scenarioDescription }: InboundOutboundChartProps) {
  const { t } = useTranslation();
  
  // Helper function to calculate metrics from visible carrier/product breakdown
  const calculateMetricsFromBreakdown = (city: CityEquityData) => {
    const breakdown = city.carrierProductBreakdown || [];
    
    if (breakdown.length === 0) {
      // No breakdown, use city-level metrics
      return {
        inbound: city.inboundPercentage,
        outbound: city.outboundPercentage,
        inboundStandardPercentage: city.inboundStandardPercentage,
        outboundStandardPercentage: city.outboundStandardPercentage,
        inboundStandardDays: city.inboundStandardDays,
        inboundActualDays: city.inboundActualDays,
        outboundStandardDays: city.outboundStandardDays,
        outboundActualDays: city.outboundActualDays,
      };
    }
    
    // Calculate inbound metrics from visible breakdown
    const totalInbound = breakdown.reduce((sum, cp) => sum + cp.inboundShipments, 0);
    const compliantInbound = breakdown.reduce((sum, cp) => 
      sum + (cp.inboundShipments * cp.inboundPercentage / 100), 0);
    const inboundPercentage = totalInbound > 0 ? (compliantInbound / totalInbound) * 100 : 0;
    
    // Calculate weighted average for inbound standard percentage
    const inboundStandardPercentage = totalInbound > 0
      ? breakdown.reduce((sum, cp) => sum + (cp.inboundShipments * cp.standardPercentage), 0) / totalInbound
      : 0;
    
    // Calculate weighted average for inbound days
    const inboundStandardDays = totalInbound > 0
      ? breakdown.reduce((sum, cp) => sum + (cp.inboundShipments * cp.standardDays), 0) / totalInbound
      : 0;
    
    const inboundActualDays = totalInbound > 0
      ? breakdown.reduce((sum, cp) => sum + (cp.inboundShipments * cp.actualDays), 0) / totalInbound
      : 0;
    
    // Calculate outbound metrics from visible breakdown
    const totalOutbound = breakdown.reduce((sum, cp) => sum + cp.outboundShipments, 0);
    const compliantOutbound = breakdown.reduce((sum, cp) => 
      sum + (cp.outboundShipments * cp.outboundPercentage / 100), 0);
    const outboundPercentage = totalOutbound > 0 ? (compliantOutbound / totalOutbound) * 100 : 0;
    
    // Calculate weighted average for outbound standard percentage
    const outboundStandardPercentage = totalOutbound > 0
      ? breakdown.reduce((sum, cp) => sum + (cp.outboundShipments * cp.standardPercentage), 0) / totalOutbound
      : 0;
    
    // Calculate weighted average for outbound days
    const outboundStandardDays = totalOutbound > 0
      ? breakdown.reduce((sum, cp) => sum + (cp.outboundShipments * cp.standardDays), 0) / totalOutbound
      : 0;
    
    const outboundActualDays = totalOutbound > 0
      ? breakdown.reduce((sum, cp) => sum + (cp.outboundShipments * cp.actualDays), 0) / totalOutbound
      : 0;
    
    return {
      inbound: inboundPercentage,
      outbound: outboundPercentage,
      inboundStandardPercentage,
      outboundStandardPercentage,
      inboundStandardDays,
      inboundActualDays,
      outboundStandardDays,
      outboundActualDays,
    };
  };
  
  // Filter cities that have at least one valid direction (shipments > 0 or standardDays > 0)
  // Then sort by direction gap (descending) and take top 10
  const topCities = [...data]
    .filter(city => 
      (city.inboundShipments > 0 || city.inboundStandardDays > 0) ||
      (city.outboundShipments > 0 || city.outboundStandardDays > 0)
    )
    .map(city => {
      const metrics = calculateMetricsFromBreakdown(city);
      return {
        city,
        metrics,
        directionGap: Math.abs(metrics.inbound - metrics.outbound),
      };
    })
    .sort((a, b) => b.directionGap - a.directionGap)
    .slice(0, 10);

  const chartData = topCities.map(({ city, metrics }) => ({
    city: city.cityName,
    inbound: metrics.inbound,
    outbound: metrics.outbound,
    inboundStandardPercentage: metrics.inboundStandardPercentage,
    outboundStandardPercentage: metrics.outboundStandardPercentage,
    inboundStandardDays: metrics.inboundStandardDays,
    inboundActualDays: metrics.inboundActualDays,
    outboundStandardDays: metrics.outboundStandardDays,
    outboundActualDays: metrics.outboundActualDays,
  }));

  // Calculate average standard for reference line (using inbound as reference)
  const avgStandard =
    chartData.length > 0
      ? chartData.reduce((sum, d) => sum + d.inboundStandardPercentage, 0) / chartData.length
      : 90;

  return (
    <>
      {/* Scenario Description */}
      <div className="mb-4 px-4 py-3 bg-blue-50 border border-blue-100 rounded-lg">
        <p className="text-sm text-blue-800">{scenarioDescription}</p>
      </div>
      
      <div className="w-full h-96">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={chartData} margin={{ top: 20, right: 30, left: 20, bottom: 60 }}>
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis dataKey="city" angle={-45} textAnchor="end" height={80} />
          <YAxis domain={[0, 100]} label={{ value: t('reporting.compliance_percent'), angle: -90, position: 'insideLeft' }} />
          <Tooltip 
            formatter={(value: any) => typeof value === 'number' ? `${formatNumber(value)}%` : ''}
            content={({ active, payload }) => {
              if (active && payload && payload.length) {
                const data = payload[0].payload;
                return (
                  <div className="bg-white p-3 border border-gray-300 rounded shadow-lg">
                    <p className="font-semibold mb-2">{data.city}</p>
                    <div className="mb-2">
                      <p className="text-blue-600 font-medium">Inbound:</p>
                      <p className="text-sm ml-2">Std %: {formatNumber(data.inboundStandardPercentage)}% | Actual %: {formatNumber(data.inbound)}%</p>
                      <p className="text-sm ml-2">J+K Std: {formatNumber(data.inboundStandardDays)} days | J+K Actual: {formatNumber(data.inboundActualDays)} days</p>
                    </div>
                    <div>
                      <p className="text-green-600 font-medium">Outbound:</p>
                      <p className="text-sm ml-2">Std %: {formatNumber(data.outboundStandardPercentage)}% | Actual %: {formatNumber(data.outbound)}%</p>
                      <p className="text-sm ml-2">J+K Std: {formatNumber(data.outboundStandardDays)} days | J+K Actual: {formatNumber(data.outboundActualDays)} days</p>
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
            label={{ value: t('reporting.avg_standard', { percent: formatNumber(avgStandard) }), position: 'right' }}
          />
          <Bar dataKey="inbound" fill="#3b82f6" name={t('reporting.inbound_percent')} />
          <Bar dataKey="outbound" fill="#10b981" name={t('reporting.outbound_percent')} />
        </BarChart>
      </ResponsiveContainer>
      </div>
    </>
  );
}
