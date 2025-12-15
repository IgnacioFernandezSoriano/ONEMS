import React from 'react';
import { Treemap, ResponsiveContainer, Tooltip } from 'recharts';
import type { LocalityData } from '@/types/reporting';

interface TreemapVisualizationProps {
  data: LocalityData[];
}

export default function TreemapVisualization({ data }: TreemapVisualizationProps) {
  const treemapData = data.map(locality => ({
    name: locality.locality_name,
    size: locality.total_shipments,
    compliance: locality.compliance_percentage,
    region: locality.region_name || 'Sin región'
  }));

  const getColor = (compliance: number) => {
    if (compliance >= 95) return '#10b981'; // green
    if (compliance >= 85) return '#f59e0b'; // yellow
    return '#ef4444'; // red
  };

  const CustomContent = (props: any) => {
    const { x, y, width, height, name, size, compliance } = props;
    
    if (width < 50 || height < 30) return null;

    return (
      <g>
        <rect
          x={x}
          y={y}
          width={width}
          height={height}
          style={{
            fill: getColor(compliance),
            stroke: '#fff',
            strokeWidth: 2
          }}
        />
        <text
          x={x + width / 2}
          y={y + height / 2 - 10}
          textAnchor="middle"
          fill="#fff"
          fontSize={14}
          fontWeight="bold"
        >
          {name}
        </text>
        <text
          x={x + width / 2}
          y={y + height / 2 + 10}
          textAnchor="middle"
          fill="#fff"
          fontSize={12}
        >
          {size} envíos
        </text>
        <text
          x={x + width / 2}
          y={y + height / 2 + 25}
          textAnchor="middle"
          fill="#fff"
          fontSize={12}
        >
          {compliance}%
        </text>
      </g>
    );
  };

  return (
    <div className="bg-white rounded-lg shadow p-6">
      <h3 className="text-lg font-semibold text-gray-900 mb-4">
        Mapa de Localidades (Treemap)
      </h3>
      <ResponsiveContainer width="100%" height={400}>
        <Treemap
          data={treemapData}
          dataKey="size"
          aspectRatio={4 / 3}
          stroke="#fff"
          fill="#8884d8"
          content={<CustomContent />}
        >
          <Tooltip
            content={({ payload }) => {
              if (!payload || !payload[0]) return null;
              const data = payload[0].payload;
              return (
                <div className="bg-white p-3 shadow-lg rounded border">
                  <p className="font-semibold">{data.name}</p>
                  <p className="text-sm">Región: {data.region}</p>
                  <p className="text-sm">Envíos: {data.size}</p>
                  <p className="text-sm">Cumplimiento: {data.compliance}%</p>
                </div>
              );
            }}
          />
        </Treemap>
      </ResponsiveContainer>
      <div className="mt-4 flex items-center gap-4 text-sm">
        <div className="flex items-center gap-2">
          <div className="w-4 h-4 bg-green-500 rounded"></div>
          <span>≥95% (Excelente)</span>
        </div>
        <div className="flex items-center gap-2">
          <div className="w-4 h-4 bg-yellow-500 rounded"></div>
          <span>85-95% (Aceptable)</span>
        </div>
        <div className="flex items-center gap-2">
          <div className="w-4 h-4 bg-red-500 rounded"></div>
          <span>&lt;85% (Crítico)</span>
        </div>
      </div>
    </div>
  );
}
