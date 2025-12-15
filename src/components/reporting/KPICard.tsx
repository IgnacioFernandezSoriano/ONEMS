import React from 'react';
import { LucideIcon } from 'lucide-react';
import { InfoTooltip } from './InfoTooltip';

interface KPICardProps {
  title: string;
  value: string;
  icon: LucideIcon;
  trend: 'up' | 'down' | 'neutral';
  trendValue: string;
  color: 'green' | 'red' | 'blue' | 'purple' | 'indigo' | 'gray' | 'amber';
  tooltip?: {
    description: string;
    interpretation: string;
    utility: string;
  };
}

export function KPICard({ title, value, icon: Icon, trend, trendValue, color, tooltip }: KPICardProps) {
  const colorClasses = {
    green: 'bg-green-50 border-green-500',
    red: 'bg-red-50 border-red-500',
    blue: 'bg-blue-50 border-blue-500',
    purple: 'bg-purple-50 border-purple-500',
    indigo: 'bg-indigo-50 border-indigo-500',
    gray: 'bg-gray-50 border-gray-500',
    amber: 'bg-amber-50 border-amber-500'
  };

  const iconColorClasses = {
    green: 'text-green-600',
    red: 'text-red-600',
    blue: 'text-blue-600',
    purple: 'text-purple-600',
    indigo: 'text-indigo-600',
    gray: 'text-gray-600',
    amber: 'text-amber-600'
  };

  return (
    <div className={`rounded-lg border-l-4 p-3 ${colorClasses[color]}`}>
      <div className="flex items-center justify-between mb-1">
        <div className="flex items-center gap-1">
          <h3 className="text-xs font-medium text-gray-600">{title}</h3>
          {tooltip && (
            <InfoTooltip
              title={title}
              description={tooltip.description}
              interpretation={tooltip.interpretation}
              utility={tooltip.utility}
            />
          )}
        </div>
        <Icon className={`w-4 h-4 ${iconColorClasses[color]}`} />
      </div>
      <div className="flex items-baseline gap-2 mb-0.5">
        <span className="text-2xl font-bold text-gray-900">{value}</span>
      </div>
      <div className="text-xs text-gray-600">
        {trendValue}
      </div>
    </div>
  );
}
