import React from 'react';
import { Treemap, ResponsiveContainer, Tooltip } from 'recharts';
import type { CityEquityData } from '@/types/reporting';
import { useTranslation } from '@/hooks/useTranslation';

interface TerritoryEquityTreemapProps {
  data: CityEquityData[];
}

export function TerritoryEquityTreemap({ data }: TerritoryEquityTreemapProps) {
  const { t } = useTranslation();
  // Transform data for Recharts Treemap
  // Size by population (fallback to totalShipments if no population)
  const treemapData = data.map((city) => ({
    name: city.cityName,
    size: city.population || city.totalShipments || 1,
    actualPercentage: city.actualPercentage,
    status: city.status,
    population: city.population,
    totalShipments: city.totalShipments,
  }));

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
    const textColor = '#ffffff';

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
              y={y + height / 2 - 10}
              textAnchor="middle"
              fill={textColor}
              fontSize={12}
              fontWeight="bold"
            >
              {name}
            </text>
            <text
              x={x + width / 2}
              y={y + height / 2 + 5}
              textAnchor="middle"
              fill={textColor}
              fontSize={11}
            >
              {(actualPercentage || 0).toFixed(1)}%
            </text>
            {width > 100 && height > 60 && (
              <text
                x={x + width / 2}
                y={y + height / 2 + 20}
                textAnchor="middle"
                fill={textColor}
                fontSize={9}
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
      <div className="mb-4">
        <h3 className="text-lg font-semibold text-gray-900">City Service Equity Treemap</h3>
        <p className="text-sm text-gray-600 mt-1">
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
          <div className="w-4 h-4 bg-green-500 rounded"></div>
          <span className="text-gray-700">✅ {t('reporting.compliant')}</span>
        </div>
        <div className="flex items-center gap-2">
          <div className="w-4 h-4 bg-amber-500 rounded"></div>
          <span className="text-gray-700">⚠️ {t('reporting.warning')}</span>
        </div>
        <div className="flex items-center gap-2">
          <div className="w-4 h-4 bg-red-500 rounded"></div>
          <span className="text-gray-700">🔴 {t('reporting.critical')}</span>
        </div>
      </div>
    </div>
  );
}
