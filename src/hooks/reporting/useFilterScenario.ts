import { useMemo } from 'react';
import type { TerritoryEquityFilters } from '@/types/reporting';

export type FilterScenario = 'general' | 'origin' | 'destination' | 'route';

export interface ScenarioInfo {
  scenario: FilterScenario;
  originCityName?: string;
  destinationCityName?: string;
  isGeneralView: boolean;
  isOriginView: boolean;
  isDestinationView: boolean;
  isRouteView: boolean;
}

/**
 * Hook to detect the current filter scenario based on origin and destination city filters
 * 
 * Scenarios:
 * - general: No origin or destination filter applied
 * - origin: Only origin city is filtered
 * - destination: Only destination city is filtered
 * - route: Both origin and destination cities are filtered
 */
export function useFilterScenario(filters: TerritoryEquityFilters): ScenarioInfo {
  return useMemo(() => {
    const hasOrigin = Boolean(filters.originCity && filters.originCity.trim() !== '');
    const hasDestination = Boolean(filters.destinationCity && filters.destinationCity.trim() !== '');

    let scenario: FilterScenario;
    
    if (hasOrigin && hasDestination) {
      scenario = 'route';
    } else if (hasOrigin && !hasDestination) {
      scenario = 'origin';
    } else if (!hasOrigin && hasDestination) {
      scenario = 'destination';
    } else {
      scenario = 'general';
    }

    return {
      scenario,
      originCityName: filters.originCity,
      destinationCityName: filters.destinationCity,
      isGeneralView: scenario === 'general',
      isOriginView: scenario === 'origin',
      isDestinationView: scenario === 'destination',
      isRouteView: scenario === 'route',
    };
  }, [filters.originCity, filters.destinationCity]);
}
