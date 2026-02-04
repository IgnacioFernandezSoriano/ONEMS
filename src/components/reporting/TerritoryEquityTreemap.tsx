import React from 'react';
import { Treemap, ResponsiveContainer, Tooltip } from 'recharts';
import { formatNumber } from '@/lib/formatNumber';
import type { CityEquityData } from '@/types/reporting';
import type { ScenarioInfo } from '@/hooks/reporting/useFilterScenario';
import { useTranslation } from '@/hooks/useTranslation';

interface TerritoryEquityTreemapProps {
  data: CityEquityData[];
  scenarioInfo: ScenarioInfo;
  globalWarningThreshold: number;
  globalCriticalThreshold: number;
  scenarioDescription: string;
}

export function TerritoryEquityTreemap({ data, scenarioInfo, globalWarningThreshold, globalCriticalThreshold, scenarioDescription }: TerritoryEquityTreemapProps) {
  const { t } = useTranslation();
  
  // Determine which metrics to show based on scenario (same logic as table)
  const getMetricsForCity = (city: CityEquityData) => {
    if (scenarioInfo.isOriginView) {
      // Origin filtered: show destination cities with INBOUND data
      return {
        actualPercentage: city.inboundPercentage,
        shipments: city.inboundShipments,
      };
    } else if (scenarioInfo.isDestinationView) {
      // Destination filtered: show origin cities with OUTBOUND data
      return {
        actualPercentage: city.outboundPercentage,
        shipments: city.outboundShipments,
      };
    } else {
      // General or route view: show outbound
      return {
        actualPercentage: city.outboundPercentage,
        shipments: city.outboundShipments,
      };
    }
  };
  
  // Calculate status based on relevant percentage
  const getStatusForPercentage = (percentage: number): 'compliant' | 'warning' | 'critical' => {
    if (percentage >= globalWarningThreshold) return 'compliant';
    if (percentage >= globalCriticalThreshold) return 'warning';
    return 'critical';
  };
  
  // Transform data for Recharts Treemap
  const treemapData = data
    .filter(city => {
      const metrics = getMetricsForCity(city);
      return metrics.shipments > 0;
    })
    .map((city) => {
      const metrics = getMetricsForCity(city);
      const status = getStatusForPercentage(metrics.actualPercentage);
      
      return {
        name: city.cityName,
        size: city.population || city.totalShipments || 1,
        actualPercentage: metrics.actualPercentage,
        status: status,
        population: city.population,
        totalShipments: city.totalShipments,
      };
    });

  // Color based on status
  const getColor = (status: string) => {
    switch (status) {
      case 'compliant':
        return '#10b981'; // green-500
      case 'warning':
        return '#f59e0b'; // amber-500
      case 'critical':
        return '#ef4444'; // red-500
      default:
        return '#6b7280'; // gray-500
    }
  };

  const CustomizedContent = (props: any) => {
    const { x, y, width, height, name, actualPercentage, status, population, totalShipments } = props;

    // Don't render if too small
    if (width < 40 || height < 30) return null;

    const color = getColor(status);
    const textColor = '#000000';

    return (
      <g>
        <rect
          x={x}
          y={y}
          width={width}
          height={height}
          style={{
            fill: color,
            stroke: '#fff',
            strokeWidth: 2,
            strokeOpacity: 1,
          }}
        />
        {width > 60 && height > 40 && (
          <>
            <text
              x={x + width / 2}
              y={y + height / 2 - 15}
              textAnchor="middle"
              fill="#000000"
              fontSize={16}
              fontWeight="bold"
              stroke="#000000"
              strokeWidth={0.5}
            >
              {name}
            </text>
            <text
              x={x + width / 2}
              y={y + height / 2 + 5}
              textAnchor="middle"
              fill="#000000"
              fontSize={16}
              fontWeight="bold"
              stroke="#000000"
              strokeWidth={0.5}
            >
              {(actualPercentage || 0).toFixed(1)}%
            </text>
            {width > 100 && height > 60 && (
              <text
                x={x + width / 2}
                y={y + height / 2 + 25}
                textAnchor="middle"
                fill="#000000"
                fontSize={16}
                fontWeight="bold"
                stroke="#000000"
                strokeWidth={0.5}
                opacity={0.9}
              >
                {population ? `${(population / 1000).toFixed(0)}K pop` : `${totalShipments} shipments`}
              </text>
            )}
          </>
        )}
      </g>
    );
  };

  const CustomTooltip = ({ active, payload }: any) => {
    if (active && payload && payload.length) {
      const data = payload[0].payload;
      return (
        <div className="bg-white border border-gray-200 rounded-lg shadow-lg p-3">
          <p className="font-semibold text-gray-900">{data.name}</p>
          <p className="text-sm text-gray-600">
            Compliance: <span className="font-medium">{(data.actualPercentage || 0).toFixed(1)}%</span>
          </p>
          {data.population && (
            <p className="text-sm text-gray-600">
              Population: <span className="font-medium">{data.population.toLocaleString()}</span>
            </p>
          )}
          <p className="text-sm text-gray-600">
            Shipments: <span className="font-medium">{data.totalShipments}</span>
          </p>
          <p className="text-sm">
            Status:{' '}
            <span className={`font-medium ${
              data.status === 'compliant' ? 'text-green-600' :
              data.status === 'warning' ? 'text-amber-600' :
              'text-red-600'
            }`}>
              {data.status === 'compliant' ? `✅ ${t('reporting.compliant')}` :
               data.status === 'warning' ? `⚠️ ${t('reporting.warning')}` :
               `🔴 ${t('reporting.critical')}`}
            </span>
          </p>
        </div>
      );
    }
    return null;
  };

  if (!data || data.length === 0) {
    return (
      <div className="flex items-center justify-center h-64 bg-gray-50 rounded-lg">
        <p className="text-gray-500">No data available for treemap</p>
      </div>
    );
  }

  return (
    <div className="bg-white rounded-lg shadow p-4">
      {/* Scenario Description */}
      <div className="mb-3 px-4 py-3 bg-blue-50 border border-blue-100 rounded-lg">
        <p className="text-sm text-blue-800">{scenarioDescription}</p>
      </div>
      
      <div className="mb-4">
        <p className="text-sm text-gray-600">
          {t('reporting.treemap_size_population_color_compliance')}
        </p>
      </div>

      <div style={{ width: '100%', height: '400px' }}>
        <ResponsiveContainer width="100%" height="100%">
        <Treemap
          data={treemapData}
          dataKey="size"
          aspectRatio={4 / 3}
          stroke="#fff"
          fill="#8884d8"
          content={<CustomizedContent />}
        >
          <Tooltip content={<CustomTooltip />} />
        </Treemap>
        </ResponsiveContainer>
      </div>

      {/* Legend */}
      <div className="mt-4 flex items-center justify-center gap-6 text-sm">
        <div className="flex items-center gap-2">
          <div className="w-3 h-3 bg-green-500 rounded-full"></div>
          <span className="text-gray-700">{t('reporting.compliant')}</span>
        </div>
        <div className="flex items-center gap-2">
          <div className="w-3 h-3 bg-amber-500 rounded-full"></div>
          <span className="text-gray-700">{t('reporting.warning')}</span>
        </div>
        <div className="flex items-center gap-2">
          <div className="w-3 h-3 bg-red-500 rounded-full"></div>
          <span className="text-gray-700">{t('reporting.critical')}</span>
        </div>
      </div>
    </div>
  );
}
