import React from 'react';
import { Award, AlertTriangle } from 'lucide-react';
import type { JKCityData } from '@/hooks/reporting/useJKPerformance';
import type { ScenarioInfo } from '@/hooks/reporting/useFilterScenario';

interface TopCitiesJKPerformanceProps {
  data: JKCityData[];
  scenarioInfo: ScenarioInfo;
}

export function TopCitiesJKPerformance({ data, scenarioInfo }: TopCitiesJKPerformanceProps) {
  // Filter cities based on direction from scenario
  const filteredData = React.useMemo(() => {
    if (scenarioInfo.isOriginView) {
      return data.filter(c => c.direction === 'inbound');
    } else if (scenarioInfo.isDestinationView || scenarioInfo.isGeneralView) {
      return data.filter(c => c.direction === 'outbound');
    }
    return data;
  }, [data, scenarioInfo]);

  // Sort by on-time percentage (descending)
  const sortedCities = [...filteredData].sort((a, b) => b.onTimePercentage - a.onTimePercentage);
  
  const topBest = sortedCities.slice(0, 5);
  const topWorst = sortedCities
    .filter(c => c.status === 'critical' || c.status === 'warning')
    .slice(-5)
    .reverse();

  if (filteredData.length === 0) {
    return (
      <div className="bg-white rounded-lg shadow p-6">
        <div className="text-center py-4 text-gray-400">
          No J+K performance data available
        </div>
      </div>
    );
  }

  return (
    <div className="bg-white rounded-lg shadow p-6">
      <h3 className="text-lg font-semibold mb-4">Top Cities J+K Performance</h3>
      
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {/* Best Performing Cities */}
        <div>
          <div className="flex items-center gap-2 mb-3">
            <Award className="w-5 h-5 text-green-600" />
            <h4 className="text-sm font-medium text-green-600">Best Performing</h4>
          </div>
          <div className="space-y-2">
            <div className="grid grid-cols-12 gap-2 text-xs font-medium text-gray-500 border-b pb-2">
              <div className="col-span-4">City</div>
              <div className="col-span-2 text-right">On-Time %</div>
              <div className="col-span-2 text-right">J+K Std</div>
              <div className="col-span-2 text-right">J+K Act</div>
              <div className="col-span-2 text-right">Dev</div>
            </div>
            {topBest.map((city, idx) => (
              <div key={idx} className="grid grid-cols-12 gap-2 text-xs">
                <div className="col-span-4 font-medium truncate" title={city.cityName}>
                  {city.cityName}
                </div>
                <div className="col-span-2 text-right font-semibold text-green-600">
                  {(city.onTimePercentage || 0).toFixed(1)}%
                </div>
                <div className="col-span-2 text-right text-gray-600">
                  {(city.jkStandard || 0).toFixed(1)}d
                </div>
                <div className="col-span-2 text-right text-gray-600">
                  {(city.jkActual || 0).toFixed(1)}d
                </div>
                <div className={`col-span-2 text-right font-medium ${
                  (city.deviation || 0) > 0 ? 'text-red-600' : 'text-green-600'
                }`}>
                  {(city.deviation || 0) > 0 ? '+' : ''}{(city.deviation || 0).toFixed(1)}d
                </div>
              </div>
            ))}
            {topBest.length === 0 && (
              <div className="text-xs text-gray-500 text-center py-2">
                No data available
              </div>
            )}
          </div>
        </div>

        {/* Worst Performing Cities */}
        <div>
          <div className="flex items-center gap-2 mb-3">
            <AlertTriangle className="w-5 h-5 text-red-600" />
            <h4 className="text-sm font-medium text-red-600">Needs Improvement</h4>
          </div>
          <div className="space-y-2">
            <div className="grid grid-cols-12 gap-2 text-xs font-medium text-gray-500 border-b pb-2">
              <div className="col-span-4">City</div>
              <div className="col-span-2 text-right">On-Time %</div>
              <div className="col-span-2 text-right">J+K Std</div>
              <div className="col-span-2 text-right">J+K Act</div>
              <div className="col-span-2 text-right">Dev</div>
            </div>
            {topWorst.map((city, idx) => (
              <div key={idx} className="grid grid-cols-12 gap-2 text-xs">
                <div className="col-span-4 font-medium truncate" title={city.cityName}>
                  {city.cityName}
                </div>
                <div className="col-span-2 text-right font-semibold text-red-600">
                  {(city.onTimePercentage || 0).toFixed(1)}%
                </div>
                <div className="col-span-2 text-right text-gray-600">
                  {(city.jkStandard || 0).toFixed(1)}d
                </div>
                <div className="col-span-2 text-right text-gray-600">
                  {(city.jkActual || 0).toFixed(1)}d
                </div>
                <div className={`col-span-2 text-right font-medium ${
                  (city.deviation || 0) > 0 ? 'text-red-600' : 'text-green-600'
                }`}>
                  {(city.deviation || 0) > 0 ? '+' : ''}{(city.deviation || 0).toFixed(1)}d
                </div>
              </div>
            ))}
            {topWorst.length === 0 && (
              <div className="text-xs text-gray-500 text-center py-2">
                All cities performing well
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
