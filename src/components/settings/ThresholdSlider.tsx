import React from 'react';

interface ThresholdSliderProps {
  label: string;
  value: number;
  onChange: (value: number) => void;
  min?: number;
  max?: number;
  step?: number;
  color?: 'green' | 'yellow' | 'red';
  description?: string;
}

export function ThresholdSlider({
  label,
  value,
  onChange,
  min = 0,
  max = 100,
  step = 1,
  color = 'green',
  description
}: ThresholdSliderProps) {
  const colorClasses = {
    green: 'accent-green-600',
    yellow: 'accent-yellow-600',
    red: 'accent-red-600'
  };

  const bgColorClasses = {
    green: 'bg-green-100',
    yellow: 'bg-yellow-100',
    red: 'bg-red-100'
  };

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between">
        <label className="text-sm font-medium text-gray-700">{label}</label>
        <span className={`px-3 py-1 rounded-full text-sm font-semibold ${bgColorClasses[color]}`}>
          {value}%
        </span>
      </div>
      
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(e) => onChange(parseInt(e.target.value))}
        className={`w-full h-2 rounded-lg appearance-none cursor-pointer ${colorClasses[color]}`}
      />
      
      <div className="flex justify-between text-xs text-gray-500">
        <span>{min}%</span>
        <span>{max}%</span>
      </div>
      
      {description && (
        <p className="text-xs text-gray-600">{description}</p>
      )}
    </div>
  );
}
