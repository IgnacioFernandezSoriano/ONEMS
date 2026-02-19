import React from 'react';
import { Treemap, ResponsiveContainer, Tooltip } from 'recharts';
import { formatNumber } from '@/lib/formatNumber';
import type { JKCityData } from '@/hooks/reporting/useJKPerformance';
import type { ScenarioInfo } from '@/hooks/reporting/useFilterScenario';
import { useTranslation } from '@/hooks/useTranslation';

interface JKTreemapProps {
  data: JKCityData[];
  scenarioInfo: ScenarioInfo;
  globalWarningThreshold: number;
  globalCriticalThreshold: number;
  scenarioDescription: string;
}

export function JKTreemap({ 
  data, 
  scenarioInfo, 
  globalWarningThreshold, 
  globalCriticalThreshold, 
  scenarioDescription 
}: JKTreemapProps) {
  const { t } = useTranslation();
  
  // Filter cities based on direction from scenario
  const filteredData = React.useMemo(() => {
    if (scenarioInfo.isOriginView) {
      return data.filter(c => c.direction === 'inbound');
    } else if (scenarioInfo.isDestinationView || scenarioInfo.isGeneralView) {
      return data.filter(c => c.direction === 'outbound');
    }
    return data;
  }, [data, scenarioInfo]);
  
  // Transform data for Recharts Treemap
  const treemapData = filteredData
    .filter(city => city.totalSamples > 0)
    .map((city) => {
      return {
        name: city.cityName,
        size: city.totalSamples,
        onTimePercentage: city.onTimePercentage,
        jkStandard: city.jkStandard,
        jkActual: city.jkActual,
        deviation: city.deviation,
        status: city.status,
        totalSamples: city.totalSamples,
        routes: city.routes,
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
    const { x, y, width, height, name, onTimePercentage, status, totalSamples } = props;

    // Don't render if too small
    if (width < 40 || height < 30) return null;

    const color = getColor(status);

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
              {(onTimePercentage || 0).toFixed(1)}%
            </text>
            {width > 100 && height > 60 && (
              <text
                x={x + width / 2}
                y={y + height / 2 + 25}
                textAnchor="middle"
                fill="#000000"
                fontSize={14}
                fontWeight="bold"
                stroke="#000000"
                strokeWidth={0.5}
                opacity={0.9}
              >
                {(totalSamples || 0).toLocaleString()} samples
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
            On-Time: <span className="font-medium">{(data.onTimePercentage || 0).toFixed(1)}%</span>
          </p>
          <p className="text-sm text-gray-600">
            J+K Std: <span className="font-medium">{(data.jkStandard || 0).toFixed(1)} days</span>
          </p>
          <p className="text-sm text-gray-600">
            J+K Actual: <span className="font-medium">{(data.jkActual || 0).toFixed(1)} days</span>
          </p>
          <p className="text-sm text-gray-600">
            Deviation: <span className={`font-medium ${(data.deviation || 0) > 0 ? 'text-red-600' : 'text-green-600'}`}>
              {(data.deviation || 0) > 0 ? '+' : ''}{(data.deviation || 0).toFixed(1)} days
            </span>
          </p>
          <p className="text-sm text-gray-600">
            Samples: <span className="font-medium">{(data.totalSamples || 0).toLocaleString()}</span>
          </p>
          <p className="text-sm text-gray-600">
            Routes: <span className="font-medium">{data.routes || 0}</span>
          </p>
          <p className="text-sm">
            Status:{' '}
            <span className={`font-medium ${
              data.status === 'compliant' ? 'text-green-600' :
              data.status === 'warning' ? 'text-amber-600' :
              'text-red-600'
            }`}>
              {data.status === 'compliant' ? '✅ Compliant' :
               data.status === 'warning' ? '⚠️ Warning' :
               '🔴 Critical'}
            </span>
          </p>
        </div>
      );
    }
    return null;
  };

  if (!filteredData || filteredData.length === 0) {
    return (
      <div className="flex items-center justify-center h-64 bg-gray-50 rounded-lg">
        <p className="text-gray-500">No J+K data available for treemap</p>
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
          City size represents number of samples. Color indicates J+K performance status.
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
          <span className="text-gray-700">Compliant</span>
        </div>
        <div className="flex items-center gap-2">
          <div className="w-3 h-3 bg-amber-500 rounded-full"></div>
          <span className="text-gray-700">Warning</span>
        </div>
        <div className="flex items-center gap-2">
          <div className="w-3 h-3 bg-red-500 rounded-full"></div>
          <span className="text-gray-700">Critical</span>
        </div>
      </div>
    </div>
  );
}
