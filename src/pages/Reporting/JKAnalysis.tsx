import React, { useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { useReportingFilters } from '@/contexts/ReportingFiltersContext';
import { useJKAnalysis } from '@/hooks/reporting/useJKAnalysis';
import { ReportFilters } from '@/components/reporting/ReportFilters';
import { BarChart3, Table as TableIcon, Percent, Hash, Info } from 'lucide-react';

export default function JKAnalysis() {
  const { profile } = useAuth();
  const accountId = profile?.account_id || undefined;
  const { filters, setFilters, resetFilters } = useReportingFilters();
  const { data, maxDays, loading, error } = useJKAnalysis(accountId, {
    originCity: filters.originCity,
    destinationCity: filters.destinationCity,
    carrier: filters.carrier,
    product: filters.product
  });

  const [viewMode, setViewMode] = useState<'table' | 'chart'>('table');
  const [displayMode, setDisplayMode] = useState<'percentage' | 'count'>('percentage');

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-500">Loading J+K analysis data...</div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-red-500">Error loading data: {error.message}</div>
      </div>
    );
  }

  // FIX: Generate day columns starting from J+0 (not J+1)
  const dayColumns = Array.from({ length: maxDays + 1 }, (_, i) => i);

  // FIX: Calculate cumulative values correctly (use <= instead of ===)
  const getRowCumulatives = (row: typeof data[0]) => {
    const cumulatives = new Map<number, { count: number; percentage: number }>();
    
    dayColumns.forEach(day => {
      // CORRECTED: Accumulate all shipments delivered UP TO this day (inclusive)
      let cumulativeCount = 0;
      for (let d = 0; d <= day; d++) {
        cumulativeCount += row.distribution.get(d) || 0;
      }
      const cumulativePercentage = (cumulativeCount / row.totalShipments) * 100;
      cumulatives.set(day, { count: cumulativeCount, percentage: cumulativePercentage });
    });
    
    return cumulatives;
  };

  // Find the cell where 95% is reached
  const findComplianceCell = (cumulatives: Map<number, { count: number; percentage: number }>) => {
    for (const [day, { percentage }] of Array.from(cumulatives.entries())) {
      if (percentage >= 95) {
        return day;
      }
    }
    return null;
  };

  const getCellColor = (day: number, standard: number, complianceDay: number | null): string => {
    // Highlight the standard column
    if (day === standard) {
      return 'bg-yellow-100 border-2 border-yellow-500 font-bold';
    }
    // Highlight the compliance cell (where 95% is reached)
    if (day === complianceDay) {
      return 'bg-blue-100 border-2 border-blue-500 font-bold';
    }
    // Before standard
    if (day < standard) {
      return 'bg-green-50';
    }
    // After standard
    return 'bg-red-50';
  };

  const getCellValue = (cumulative: { count: number; percentage: number }): string => {
    if (displayMode === 'percentage') {
      return `${cumulative.percentage.toFixed(1)}%`;
    }
    return cumulative.count.toString();
  };

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">J+K Transit Time Analysis</h1>
          <p className="text-gray-600 mt-1">Cumulative temporal distribution of shipments by delivery day</p>
        </div>
        <div className="group relative">
          <div className="flex items-center gap-2 px-4 py-2 bg-blue-50 border border-blue-200 rounded-lg cursor-help">
            <Info className="w-5 h-5 text-blue-600" />
            <span className="text-sm font-medium text-blue-900">About this Report</span>
          </div>
          <div className="invisible group-hover:visible absolute z-10 w-96 p-4 bg-white border border-gray-200 rounded-lg shadow-xl text-sm text-gray-700 right-0 top-12">
            <div className="absolute -top-1 right-8 w-2 h-2 bg-white border-l border-t border-gray-200 transform rotate-45"></div>
            <h3 className="font-bold text-gray-900 mb-3">J+K Transit Time Analysis</h3>
            <p className="mb-3"><strong>Purpose:</strong> Shows cumulative temporal distribution of shipments - how many arrive at J+0, J+1, J+2, J+3... days. Helps identify delivery patterns and systematic delays.</p>
            <p className="mb-3"><strong>What you'll see:</strong> Table or chart showing cumulative percentages/counts for each day. Yellow column = standard day (J+K). Blue cell = where 95% compliance is reached. Colors indicate early (green), on-time (yellow), or late (red) delivery.</p>
            <p className="mb-3"><strong>Regulatory Objective:</strong> Detect systematic delays (e.g., if most shipments arrive at J+5 when standard is J+3). Verify if carriers consistently meet standards or if patterns show structural problems requiring intervention.</p>
            <p className="text-xs text-gray-500"><strong>Note:</strong> Values are cumulative. Each column shows total % of shipments delivered UP TO that day.</p>
          </div>
        </div>
      </div>

      <ReportFilters filters={filters} onChange={setFilters} onReset={resetFilters} />

      {/* Controls */}
      <div className="bg-white rounded-lg shadow p-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-4">
            <span className="text-sm font-medium text-gray-700">View Mode:</span>
            <div className="flex gap-2">
              <button
                onClick={() => setViewMode('table')}
                className={`flex items-center gap-2 px-4 py-2 rounded-lg transition-colors ${
                  viewMode === 'table'
                    ? 'bg-blue-600 text-white'
                    : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                }`}
              >
                <TableIcon className="w-4 h-4" />
                Table
              </button>
              <button
                onClick={() => setViewMode('chart')}
                className={`flex items-center gap-2 px-4 py-2 rounded-lg transition-colors ${
                  viewMode === 'chart'
                    ? 'bg-blue-600 text-white'
                    : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                }`}
              >
                <BarChart3 className="w-4 h-4" />
                Chart
              </button>
            </div>
          </div>

          <div className="flex items-center gap-4">
            <span className="text-sm font-medium text-gray-700">Display:</span>
            <div className="flex gap-2">
              <button
                onClick={() => setDisplayMode('percentage')}
                className={`flex items-center gap-2 px-4 py-2 rounded-lg transition-colors ${
                  displayMode === 'percentage'
                    ? 'bg-blue-600 text-white'
                    : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                }`}
              >
                <Percent className="w-4 h-4" />
                Percentage
              </button>
              <button
                onClick={() => setDisplayMode('count')}
                className={`flex items-center gap-2 px-4 py-2 rounded-lg transition-colors ${
                  displayMode === 'count'
                    ? 'bg-blue-600 text-white'
                    : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                }`}
              >
                <Hash className="w-4 h-4" />
                Tags
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Legend */}
      <div className="bg-white rounded-lg shadow p-4">
        <h3 className="text-sm font-semibold text-gray-900 mb-3">Color Legend</h3>
        <div className="flex gap-6 flex-wrap">
          <div className="flex items-center gap-2">
            <div className="w-6 h-6 bg-green-50 border border-green-200 rounded"></div>
            <span className="text-sm text-gray-700">Before Standard (Early)</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-6 h-6 bg-yellow-100 border-2 border-yellow-500 rounded"></div>
            <span className="text-sm text-gray-700 font-bold">Standard Day (J+K)</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-6 h-6 bg-blue-100 border-2 border-blue-500 rounded"></div>
            <span className="text-sm text-gray-700 font-bold">95% Compliance Reached</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-6 h-6 bg-red-50 border border-red-200 rounded"></div>
            <span className="text-sm text-gray-700">After Standard (Delayed)</span>
          </div>
        </div>
        <p className="text-xs text-gray-500 mt-2">
          Note: Values are cumulative. Each column shows the total percentage/count of shipments delivered up to that day.
        </p>
      </div>

      {/* Table View */}
      {viewMode === 'table' && (
        <div className="bg-white rounded-lg shadow overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Origin</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Destination</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Carrier</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Product</th>
                <th className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase">Total</th>
                <th className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase">Standard</th>
                {dayColumns.map(day => (
                  <th key={day} className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase">
                    J+{day}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {data.map((row, idx) => {
                const cumulatives = getRowCumulatives(row);
                const complianceDay = findComplianceCell(cumulatives);
                
                return (
                  <tr key={idx} className="hover:bg-gray-50">
                    <td className="px-4 py-3 text-sm text-gray-900">{row.originCity}</td>
                    <td className="px-4 py-3 text-sm text-gray-900">{row.destinationCity}</td>
                    <td className="px-4 py-3 text-sm text-gray-900">{row.carrier}</td>
                    <td className="px-4 py-3 text-sm text-gray-900">{row.product}</td>
                    <td className="px-4 py-3 text-sm text-center font-medium text-gray-900">
                      {row.totalShipments}
                    </td>
                    <td className="px-4 py-3 text-sm text-center font-bold text-yellow-800">
                      J+{row.standard}
                    </td>
                    {dayColumns.map(day => {
                      const cumulative = cumulatives.get(day);
                      if (!cumulative) return <td key={day} className="px-4 py-3 text-sm text-center">-</td>;
                      
                      const cellColor = getCellColor(day, row.standard, complianceDay);
                      return (
                        <td
                          key={day}
                          className={`px-4 py-3 text-sm text-center ${cellColor}`}
                        >
                          {getCellValue(cumulative)}
                        </td>
                      );
                    })}
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {/* Chart View */}
      {viewMode === 'chart' && (
        <div className="bg-white rounded-lg shadow p-6">
          {data.length === 0 ? (
            <div className="text-center py-12 text-gray-500">
              No data available for the selected filters
            </div>
          ) : (
            <div className="space-y-8">
              {data.map((row, idx) => {
                const routeLabel = `${row.originCity} → ${row.destinationCity} (${row.carrier} - ${row.product})`;
                const cumulatives = getRowCumulatives(row);
                const complianceDay = findComplianceCell(cumulatives);
                
                return (
                  <div key={idx} className="space-y-2">
                    <h3 className="text-sm font-semibold text-gray-900">{routeLabel}</h3>
                    <div className="flex items-end gap-1 h-40 border-b border-gray-200">
                      {dayColumns.map(day => {
                        const cumulative = cumulatives.get(day);
                        if (!cumulative) return null;
                        
                        const height = `${cumulative.percentage}%`;
                        const isStandard = day === row.standard;
                        const isCompliance = day === complianceDay;
                        
                        let barColor = 'bg-green-200';
                        if (isStandard) barColor = 'bg-yellow-300 border-2 border-yellow-600';
                        else if (isCompliance) barColor = 'bg-blue-300 border-2 border-blue-600';
                        else if (day > row.standard) barColor = 'bg-red-200';
                        
                        return (
                          <div key={day} className="flex-1 flex flex-col items-center">
                            <div
                              className={`w-full ${barColor} rounded-t transition-all hover:opacity-80`}
                              style={{ height }}
                              title={`J+${day}: ${getCellValue(cumulative)}`}
                            ></div>
                            <span className="text-xs text-gray-600 mt-1">J+{day}</span>
                          </div>
                        );
                      })}
                    </div>
                    <div className="text-xs text-gray-500">
                      Total: {row.totalShipments} shipments | Standard: J+{row.standard} | 
                      {complianceDay !== null && ` 95% reached at: J+${complianceDay}`}
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      )}

      {data.length === 0 && (
        <div className="bg-white rounded-lg shadow p-12 text-center">
          <p className="text-gray-500">No data available for the selected filters</p>
        </div>
      )}
    </div>
  );
}
