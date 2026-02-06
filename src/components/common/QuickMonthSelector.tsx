import React from 'react';
import { Calendar } from 'lucide-react';
import { SmartTooltip } from './SmartTooltip';
import { useTranslation } from '@/hooks/useTranslation';

interface QuickMonthSelectorProps {
  selectedYear: number;
  onYearChange: (year: number) => void;
  onMonthSelect: (year: number, month: number) => void;
  onFirstSemesterSelect: () => void;
  onSecondSemesterSelect: () => void;
  onYearSelect: () => void;
  showLabel?: boolean;
  showTooltip?: boolean;
}

export function QuickMonthSelector({
  selectedYear,
  onYearChange,
  onMonthSelect,
  onFirstSemesterSelect,
  onSecondSemesterSelect,
  onYearSelect,
  showLabel = true,
  showTooltip = true,
}: QuickMonthSelectorProps) {
  const { t } = useTranslation();

  const currentYear = new Date().getFullYear();
  const years = Array.from({ length: 10 }, (_, i) => currentYear + i);
  const months = [
    { num: 1, name: 'Jan' },
    { num: 2, name: 'Feb' },
    { num: 3, name: 'Mar' },
    { num: 4, name: 'Apr' },
    { num: 5, name: 'May' },
    { num: 6, name: 'Jun' },
    { num: 7, name: 'Jul' },
    { num: 8, name: 'Aug' },
    { num: 9, name: 'Sep' },
    { num: 10, name: 'Oct' },
    { num: 11, name: 'Nov' },
    { num: 12, name: 'Dec' },
  ];

  return (
    <div>
      {showLabel && (
        <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
          <Calendar className="w-4 h-4" />
          Quick Month Selection
          {showTooltip && (
            <SmartTooltip content="Click any month button to automatically set the start and end dates for that entire month, or use semester/year buttons for longer periods." />
          )}
        </label>
      )}
      <div className="flex items-center gap-2 mb-2">
        <select
          value={selectedYear}
          onChange={(e) => onYearChange(Number(e.target.value))}
          className="px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
        >
          {years.map((year) => (
            <option key={year} value={year}>
              {year}
            </option>
          ))}
        </select>
      </div>
      <div className="flex flex-wrap gap-2">
        {months.map((month) => (
          <button
            key={month.num}
            onClick={() => onMonthSelect(selectedYear, month.num)}
            className="px-3 py-1.5 text-sm font-medium rounded-lg border border-gray-300 hover:bg-blue-50 hover:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-500 transition-colors"
          >
            {month.name}
          </button>
        ))}
        <button
          onClick={onFirstSemesterSelect}
          className="px-3 py-1.5 text-sm font-medium rounded-lg border border-green-300 bg-green-50 hover:bg-green-100 hover:border-green-500 focus:outline-none focus:ring-2 focus:ring-green-500 transition-colors"
        >
          1st Semester
        </button>
        <button
          onClick={onSecondSemesterSelect}
          className="px-3 py-1.5 text-sm font-medium rounded-lg border border-teal-300 bg-teal-50 hover:bg-teal-100 hover:border-teal-500 focus:outline-none focus:ring-2 focus:ring-teal-500 transition-colors"
        >
          2nd Semester
        </button>
        <button
          onClick={onYearSelect}
          className="px-3 py-1.5 text-sm font-medium rounded-lg border border-purple-300 bg-purple-50 hover:bg-purple-100 hover:border-purple-500 focus:outline-none focus:ring-2 focus:ring-purple-500 transition-colors"
        >
          Year
        </button>
      </div>
    </div>
  );
}
