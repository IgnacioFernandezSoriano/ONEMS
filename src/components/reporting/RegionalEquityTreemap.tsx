import React from 'react';
import { Treemap, ResponsiveContainer, Tooltip } from 'recharts';
import { formatNumber } from '@/lib/formatNumber';
import type { RegionEquityData } from '@/types/reporting';
import type { ScenarioInfo } from '@/hooks/reporting/useFilterScenario';
import { useTranslation } from '@/hooks/useTranslation';

interface RegionalEquityTreemapProps {
  data: RegionEquityData[];
  scenarioInfo: ScenarioInfo;
  globalWarningThreshold: number;
  globalCriticalThreshold: number;
  scenarioDescription: string;
}

export function RegionalEquityTreemap({ data, scenarioInfo, globalWarningThreshold, globalCriticalThreshold, scenarioDescription }: RegionalEquityTreemapProps) {
  const { t } = useTranslation();
  
  // Determine which metrics to show based on scenario (same logic as table)
  const getMetricsForRegion = (region: RegionEquityData) => {
    if (scenarioInfo.isOriginView) {
      // Origin filtered: show destination regions with INBOUND data
      return {
        actualPercentage: region.inboundPercentage,
        shipments: region.inboundShipments,
      };
    } else if (scenarioInfo.isDestinationView) {
      // Destination filtered: show origin regions with OUTBOUND data
      return {
        actualPercentage: region.outboundPercentage,
        shipments: region.outboundShipments,
      };
    } else {
      // General or route view: show outbound
      return {
        actualPercentage: region.outboundPercentage,
        shipments: region.outboundShipments,
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
    .filter(region => {
      const metrics = getMetricsForRegion(region);
      return metrics.shipments > 0;
    })
    .map((region) => {
      const metrics = getMetricsForRegion(region);
      const status = getStatusForPercentage(metrics.actualPercentage);
      
      return {
        name: region.regionName,
        size: region.totalPopulation || region.totalShipments || 1,
        actualPercentage: metrics.actualPercentage,
        status: status,
        totalPopulation: region.totalPopulation,
        totalShipments: region.totalShipments,
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
    const { x, y, width, height, name, actualPercentage, status, totalPopulation, totalShipments } = props;

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
              fill={textColor}
              fontSize={16}
              fontWeight="bold"
            >
              {name}
            </text>
            <text
              x={x + width / 2}
              y={y + height / 2 + 5}
              textAnchor="middle"
              fill={textColor}
              fontSize={16}
            >
              {(actualPercentage || 0).toFixed(1)}%
            </text>
            {width > 100 && height > 60 && (
              <text
                x={x + width / 2}
                y={y + height / 2 + 25}
                textAnchor="middle"
                fill={textColor}
                fontSize={16}
                opacity={0.9}
              >
                {totalPopulation ? `${(totalPopulation / 1000).toFixed(0)}K pop` : `${totalShipments} shipments`}
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
          {data.totalPopulation && (
            <p className="text-sm text-gray-600">
              Population: <span className="font-medium">{data.totalPopulation.toLocaleString()}</span>
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
              {data.status === 'compliant' ? t('reporting.compliant') :
               data.status === 'warning' ? t('reporting.warning') :
               t('reporting.critical')}
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
