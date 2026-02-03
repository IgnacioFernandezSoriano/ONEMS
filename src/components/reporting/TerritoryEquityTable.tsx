import { useState } from 'react';
import { formatNumber } from '@/lib/formatNumber';
import { ChevronDown, ChevronRight, ChevronsDown, ChevronsUp } from 'lucide-react';
import type { CityEquityData } from '@/types/reporting';
import type { ScenarioInfo } from '@/hooks/reporting/useFilterScenario';
import { useTranslation } from '@/hooks/useTranslation';

interface TerritoryEquityTableProps {
  data: CityEquityData[];
  onCityClick?: (city: CityEquityData) => void;
  globalWarningThreshold: number;
  globalCriticalThreshold: number;
  scenarioInfo: ScenarioInfo;
  scenarioDescription: string;
}

type CityRow = {
  cityId: string;
  cityName: string;
  regionName: string | null;
  classification: string | null;
  population: number | null;
  shipments: number;
  compliant: number;
  standardPercentage: number;
  actualPercentage: number;
  deviation: number;
  standardDays: number;
  actualDays: number;
  status: 'compliant' | 'warning' | 'critical';
  originalCity: CityEquityData;
  carrierBreakdown: CarrierRow[];
};

type CarrierRow = {
  carrier: string;
  shipments: number;
  compliant: number;
  standardPercentage: number;
  actualPercentage: number;
  deviation: number;
  standardDays: number;
  actualDays: number;
  status: 'compliant' | 'warning' | 'critical';
  productBreakdown: ProductRow[];
};

type ProductRow = {
  product: string;
  shipments: number;
  compliant: number;
  standardPercentage: number;
  actualPercentage: number;
  deviation: number;
  standardDays: number;
  actualDays: number;
  status: 'compliant' | 'warning' | 'critical';
};

export function TerritoryEquityTable({ 
  data, 
  onCityClick, 
  globalWarningThreshold, 
  globalCriticalThreshold,
  scenarioInfo,
  scenarioDescription 
}: TerritoryEquityTableProps) {
  const { t } = useTranslation();
  const [sortField, setSortField] = useState<keyof CityRow>('cityName');
  const [sortDirection, setSortDirection] = useState<'asc' | 'desc'>('asc');
  const [expandedCities, setExpandedCities] = useState<Set<string>>(new Set());
  const [expandedCarriers, setExpandedCarriers] = useState<Set<string>>(new Set());
  const [expandAll, setExpandAll] = useState(false);

  // Toggle city expansion (expands/collapses all levels below)
  const toggleCity = (cityId: string) => {
    const newExpanded = new Set(expandedCities);
    const newExpandedCarriers = new Set(expandedCarriers);
    
    if (newExpanded.has(cityId)) {
      // Collapse city and all its carriers
      newExpanded.delete(cityId);
      const carriersToRemove = Array.from(newExpandedCarriers).filter(id => id.startsWith(`${cityId}-`));
      carriersToRemove.forEach(id => newExpandedCarriers.delete(id));
    } else {
      // Expand city and all its carriers
      newExpanded.add(cityId);
      // Find all carriers for this city and expand them
      const cityRow = cityRows.find(c => c.cityId === cityId);
      if (cityRow) {
        cityRow.carrierBreakdown.forEach(carrier => {
          newExpandedCarriers.add(`${cityId}-${carrier.carrier}`);
        });
      }
    }
    
    setExpandedCities(newExpanded);
    setExpandedCarriers(newExpandedCarriers);
  };

  // Toggle carrier expansion
  const toggleCarrier = (carrierId: string) => {
    const newExpanded = new Set(expandedCarriers);
    if (newExpanded.has(carrierId)) {
      newExpanded.delete(carrierId);
    } else {
      newExpanded.add(carrierId);
    }
    setExpandedCarriers(newExpanded);
  };

  // Toggle all cities
  const toggleAll = () => {
    if (expandAll) {
      setExpandedCities(new Set());
      setExpandedCarriers(new Set());
    } else {
      const allCities = new Set(cityRows.map(c => c.cityId));
      const allCarriers = new Set<string>();
      cityRows.forEach(city => {
        city.carrierBreakdown.forEach(carrier => {
          allCarriers.add(`${city.cityId}-${carrier.carrier}`);
        });
      });
      setExpandedCities(allCities);
      setExpandedCarriers(allCarriers);
    }
    setExpandAll(!expandAll);
  };

  // Determine which metrics to show based on scenario
  const getMetricsForCity = (city: CityEquityData) => {
    // Origin view (origin filtered): show destination cities with INBOUND data
    // Destination view (destination filtered): show origin cities with OUTBOUND data
    // General/Route view: show outbound data
    if (scenarioInfo.isOriginView) {
      // When filtering by origin, we see destination cities receiving shipments (INBOUND)
      return {
        shipments: city.inboundShipments,
        compliant: city.inboundCompliant,
        standardPercentage: city.inboundStandardPercentage,
        actualPercentage: city.inboundPercentage,
        deviation: city.inboundDeviation,
        standardDays: city.inboundStandardDays,
        actualDays: city.inboundActualDays,
      };
    } else if (scenarioInfo.isDestinationView) {
      // When filtering by destination, we see origin cities sending shipments (OUTBOUND)
      return {
        shipments: city.outboundShipments,
        compliant: city.outboundCompliant,
        standardPercentage: city.outboundStandardPercentage,
        actualPercentage: city.outboundPercentage,
        deviation: city.outboundDeviation,
        standardDays: city.outboundStandardDays,
        actualDays: city.outboundActualDays,
      };
    } else {
      // General or route view: show outbound
      return {
        shipments: city.outboundShipments,
        compliant: city.outboundCompliant,
        standardPercentage: city.outboundStandardPercentage,
        actualPercentage: city.outboundPercentage,
        deviation: city.outboundDeviation,
        standardDays: city.outboundStandardDays,
        actualDays: city.outboundActualDays,
      };
    }
  };

  // Build city rows with carrier/product hierarchy
  const cityRows: CityRow[] = data
    .filter(city => {
      const metrics = getMetricsForCity(city);
      return metrics.shipments > 0 || metrics.standardDays > 0;
    })
    .map((city) => {
      const metrics = getMetricsForCity(city);
      
      // Build carrier breakdown
      const carrierMap = new Map<string, { 
        carrier: string; 
        products: Map<string, ProductRow>; 
        totalShipments: number; 
        totalCompliant: number; 
        standardSum: number; 
        standardCount: number;
        standardDaysSum: number;
        standardDaysCount: number;
        actualDaysSum: number;
        actualDaysCount: number;
      }>();

      // Group carrier/product breakdown by carrier
      city.carrierProductBreakdown?.forEach(cp => {
        // Filter by direction - check if this carrier/product has data in the relevant direction
        // Origin view: show INBOUND data (destination cities receiving)
        // Destination view: show OUTBOUND data (origin cities sending)
        const hasRelevantData = scenarioInfo.isOriginView
          ? cp.inboundPercentage > 0 || cp.totalShipments > 0  // Origin filtered: show inbound to destinations
          : scenarioInfo.isDestinationView
          ? cp.outboundPercentage > 0 || cp.totalShipments > 0  // Destination filtered: show outbound from origins
          : cp.outboundPercentage > 0 || cp.totalShipments > 0;  // General/route: show outbound

        if (!hasRelevantData) return;

        if (!carrierMap.has(cp.carrier)) {
          carrierMap.set(cp.carrier, {
            carrier: cp.carrier,
            products: new Map(),
            totalShipments: 0,
            totalCompliant: 0,
            standardSum: 0,
            standardCount: 0,
            standardDaysSum: 0,
            standardDaysCount: 0,
            actualDaysSum: 0,
            actualDaysCount: 0,
          });
        }

        const carrierData = carrierMap.get(cp.carrier)!;
        carrierData.totalShipments += cp.totalShipments;
        carrierData.totalCompliant += cp.compliantShipments;
        carrierData.standardSum += cp.standardPercentage * cp.totalShipments;
        carrierData.standardCount += cp.totalShipments;
        carrierData.standardDaysSum += cp.standardDays * cp.totalShipments;
        carrierData.standardDaysCount += cp.totalShipments;
        // Accumulate actual days weighted by shipments
        if (cp.actualDays > 0) {
          carrierData.actualDaysSum += cp.actualDays * cp.totalShipments;
          carrierData.actualDaysCount += cp.totalShipments;
        }
        
        // Determine which percentage to use based on direction
        const relevantPercentage = scenarioInfo.isOriginView
          ? cp.inboundPercentage  // Origin filtered: show inbound percentages
          : scenarioInfo.isDestinationView
          ? cp.outboundPercentage  // Destination filtered: show outbound percentages
          : cp.outboundPercentage;  // General/route: show outbound percentages
        
        // Add product
        const productStatus: 'compliant' | 'warning' | 'critical' = 
          relevantPercentage >= globalWarningThreshold ? 'compliant' :
          relevantPercentage >= globalCriticalThreshold ? 'warning' : 'critical';

        carrierData.products.set(cp.product, {
          product: cp.product,
          shipments: cp.totalShipments,
          compliant: cp.compliantShipments,
          standardPercentage: cp.standardPercentage,
          actualPercentage: relevantPercentage,  // Use direction-specific percentage
          deviation: relevantPercentage - cp.standardPercentage,  // Recalculate deviation
          standardDays: cp.standardDays,
          actualDays: cp.actualDays,
          status: productStatus,
        });
      });

      // Build carrier rows
      const carrierBreakdown: CarrierRow[] = Array.from(carrierMap.values()).map(carrierData => {
        const carrierActualPercentage = carrierData.totalShipments > 0 
          ? (carrierData.totalCompliant / carrierData.totalShipments) * 100 
          : 0;
        const carrierStandardPercentage = carrierData.standardCount > 0
          ? carrierData.standardSum / carrierData.standardCount
          : 95;
        const carrierStandardDays = carrierData.standardDaysCount > 0
          ? carrierData.standardDaysSum / carrierData.standardDaysCount
          : 0;
        
        // Calculate weighted average of actual days
        const carrierActualDays = carrierData.actualDaysCount > 0
          ? carrierData.actualDaysSum / carrierData.actualDaysCount
          : 0;
        
        const carrierStatus: 'compliant' | 'warning' | 'critical' = 
          carrierActualPercentage >= globalWarningThreshold ? 'compliant' :
          carrierActualPercentage >= globalCriticalThreshold ? 'warning' : 'critical';

        return {
          carrier: carrierData.carrier,
          shipments: carrierData.totalShipments,
          compliant: carrierData.totalCompliant,
          standardPercentage: carrierStandardPercentage,
          actualPercentage: carrierActualPercentage,
          deviation: carrierActualPercentage - carrierStandardPercentage,
          standardDays: carrierStandardDays,
          actualDays: carrierActualDays,
          status: carrierStatus,
          productBreakdown: Array.from(carrierData.products.values()),
        };
      });

      return {
        cityId: city.cityId,
        cityName: city.cityName,
        regionName: city.regionName,
        classification: city.classification,
        population: city.population,
        shipments: metrics.shipments,
        compliant: metrics.compliant,
        standardPercentage: metrics.standardPercentage,
        actualPercentage: metrics.actualPercentage,
        deviation: metrics.deviation,
        standardDays: metrics.standardDays,
        actualDays: metrics.actualDays,
        status: city.status,
        originalCity: city,
        carrierBreakdown,
      };
    });

  // Sorting logic
  const handleSort = (field: keyof CityRow) => {
    if (sortField === field) {
      setSortDirection(sortDirection === 'asc' ? 'desc' : 'asc');
    } else {
      setSortField(field);
      setSortDirection('asc');
    }
  };

  const sortedData = [...cityRows].sort((a, b) => {
    let aVal = a[sortField];
    let bVal = b[sortField];

    if (aVal === null || aVal === undefined) aVal = '';
    if (bVal === null || bVal === undefined) bVal = '';

    if (typeof aVal === 'string' && typeof bVal === 'string') {
      return sortDirection === 'asc'
        ? aVal.localeCompare(bVal)
        : bVal.localeCompare(aVal);
    }

    if (typeof aVal === 'number' && typeof bVal === 'number') {
      return sortDirection === 'asc' ? aVal - bVal : bVal - aVal;
    }

    return 0;
  });

  const SortIcon = ({ field }: { field: keyof CityRow }) => {
    if (sortField !== field) return null;
    return sortDirection === 'asc' ? ' ▲' : ' ▼';
  };

  const getStatusIcon = (status: 'compliant' | 'warning' | 'critical') => {
    switch (status) {
      case 'compliant':
        return <span className="text-green-500">●</span>;
      case 'warning':
        return <span className="text-amber-500">●</span>;
      case 'critical':
        return <span className="text-red-500">●</span>;
    }
  };

  return (
    <div className="space-y-4">
      {/* Scenario Description */}
      <div className="flex items-center justify-between bg-blue-50 border border-blue-200 rounded-lg px-4 py-3">
        <div className="flex items-center gap-2">
          <span className="text-sm font-medium text-blue-900">{scenarioDescription}</span>
        </div>
        <button
          onClick={toggleAll}
          className="flex items-center gap-2 px-3 py-1.5 text-sm font-medium text-blue-700 hover:text-blue-900 hover:bg-blue-100 rounded-md transition-colors"
        >
          {expandAll ? (
            <>
              <ChevronsUp className="w-4 h-4" />
              Collapse All
            </>
          ) : (
            <>
              <ChevronsDown className="w-4 h-4" />
              Expand All
            </>
          )}
        </button>
      </div>

      {/* Table */}
      <div className="overflow-x-auto">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider w-10">
                {/* Expand button column */}
              </th>
              <th
                className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
                onClick={() => handleSort('cityName')}
              >
                {t('reporting.city')} <SortIcon field="cityName" />
              </th>
              <th
                className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
                onClick={() => handleSort('regionName')}
              >
                {t('reporting.region')} <SortIcon field="regionName" />
              </th>
              <th
                className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
                onClick={() => handleSort('classification')}
              >
                {t('reporting.class')} <SortIcon field="classification" />
              </th>
              <th
                className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
                onClick={() => handleSort('population')}
              >
                {t('reporting.population')} <SortIcon field="population" />
              </th>
              <th
                className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
                onClick={() => handleSort('shipments')}
              >
                {t('common.total')} <SortIcon field="shipments" />
              </th>
              <th
                className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
                onClick={() => handleSort('standardDays')}
              >
                {t('reporting.jk_std')} <SortIcon field="standardDays" />
              </th>
              <th
                className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
                onClick={() => handleSort('actualDays')}
              >
                {t('reporting.jk_actual')} <SortIcon field="actualDays" />
              </th>
              <th
                className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
                onClick={() => handleSort('standardPercentage')}
              >
                {t('reporting.standard_percent')} <SortIcon field="standardPercentage" />
              </th>
              <th
                className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
                onClick={() => handleSort('actualPercentage')}
              >
                {t('reporting.actual_percent')} <SortIcon field="actualPercentage" />
              </th>
              <th
                className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
                onClick={() => handleSort('deviation')}
              >
                {t('reporting.deviation')} <SortIcon field="deviation" />
              </th>
              <th
                className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
                onClick={() => handleSort('status')}
              >
                {t('common.status')} <SortIcon field="status" />
              </th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {sortedData.map((city) => {
              const isCityExpanded = expandedCities.has(city.cityId);
              const hasCarriers = city.carrierBreakdown.length > 0;
              
              return (
                <>
                  {/* City Row */}
                  <tr key={city.cityId} className="hover:bg-gray-50">
                    <td className="px-4 py-3 whitespace-nowrap text-center">
                      {hasCarriers && (
                        <button
                          onClick={() => toggleCity(city.cityId)}
                          className="text-gray-500 hover:text-gray-700"
                        >
                          {isCityExpanded ? (
                            <ChevronDown className="w-4 h-4" />
                          ) : (
                            <ChevronRight className="w-4 h-4" />
                          )}
                        </button>
                      )}
                    </td>
                    <td className="px-4 py-3 whitespace-nowrap">
                      <button
                        onClick={() => onCityClick?.(city.originalCity)}
                        className="text-blue-600 hover:text-blue-800 hover:underline font-medium text-left"
                      >
                        {city.cityName}
                      </button>
                    </td>
                    <td className="px-4 py-3 whitespace-nowrap text-sm text-gray-500">
                      {city.regionName || '-'}
                    </td>
                    <td className="px-4 py-3 whitespace-nowrap text-sm text-gray-700">
                      {city.classification || '-'}
                    </td>
                    <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                      {city.population ? city.population.toLocaleString() : '-'}
                    </td>
                    <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                      {city.shipments}
                    </td>
                    <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                      {formatNumber(city.standardDays)}
                    </td>
                    <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                      {formatNumber(city.actualDays)}
                    </td>
                    <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                      {formatNumber(city.standardPercentage)}%
                    </td>
                    <td className="px-4 py-3 whitespace-nowrap text-sm text-right text-gray-700">
                      {formatNumber(city.actualPercentage)}%
                    </td>
                    <td
                      className={`px-4 py-3 whitespace-nowrap text-sm text-right font-medium ${
                        city.status === 'compliant' ? 'text-green-600' :
                        city.status === 'warning' ? 'text-amber-600' : 'text-red-600'
                      }`}
                    >
                      {city.deviation >= 0 ? '+' : ''}
                      {formatNumber(city.deviation)}%
                    </td>
                    <td className="px-4 py-3 whitespace-nowrap text-center text-2xl">
                      {getStatusIcon(city.status)}
                    </td>
                  </tr>
                  
                  {/* Carrier Rows */}
                  {isCityExpanded && city.carrierBreakdown.map((carrier) => {
                    const carrierId = `${city.cityId}-${carrier.carrier}`;
                    const isCarrierExpanded = expandedCarriers.has(carrierId);
                    const hasProducts = carrier.productBreakdown.length > 0;
                    
                    return (
                      <>
                        <tr key={carrierId} className="bg-gray-50">
                          <td className="px-4 py-2 whitespace-nowrap text-center">
                            {hasProducts && (
                              <button
                                onClick={() => toggleCarrier(carrierId)}
                                className="text-gray-500 hover:text-gray-700 ml-4"
                              >
                                {isCarrierExpanded ? (
                                  <ChevronDown className="w-3.5 h-3.5" />
                                ) : (
                                  <ChevronRight className="w-3.5 h-3.5" />
                                )}
                              </button>
                            )}
                          </td>
                          <td className="px-4 py-2 whitespace-nowrap text-sm text-gray-700 font-medium pl-12">
                            {carrier.carrier}
                          </td>
                          <td className="px-4 py-2 whitespace-nowrap text-sm text-gray-500">-</td>
                          <td className="px-4 py-2 whitespace-nowrap text-sm text-gray-500">-</td>
                          <td className="px-4 py-2 whitespace-nowrap text-sm text-gray-500">-</td>
                          <td className="px-4 py-2 whitespace-nowrap text-sm text-right text-gray-700">
                            {carrier.shipments}
                          </td>
                          <td className="px-4 py-2 whitespace-nowrap text-sm text-right text-gray-700">
                            {formatNumber(carrier.standardDays)}
                          </td>
                          <td className="px-4 py-2 whitespace-nowrap text-sm text-right text-gray-700">
                            {formatNumber(carrier.actualDays)}
                          </td>
                          <td className="px-4 py-2 whitespace-nowrap text-sm text-right text-gray-700">
                            {formatNumber(carrier.standardPercentage)}%
                          </td>
                          <td className="px-4 py-2 whitespace-nowrap text-sm text-right text-gray-700">
                            {formatNumber(carrier.actualPercentage)}%
                          </td>
                          <td
                            className={`px-4 py-2 whitespace-nowrap text-sm text-right font-medium ${
                              carrier.status === 'compliant' ? 'text-green-600' :
                              carrier.status === 'warning' ? 'text-amber-600' : 'text-red-600'
                            }`}
                          >
                            {carrier.deviation >= 0 ? '+' : ''}
                            {formatNumber(carrier.deviation)}%
                          </td>
                          <td className="px-4 py-2 whitespace-nowrap text-center text-xl">
                            {getStatusIcon(carrier.status)}
                          </td>
                        </tr>
                        
                        {/* Product Rows */}
                        {isCarrierExpanded && carrier.productBreakdown.map((product) => (
                          <tr key={`${carrierId}-${product.product}`} className="bg-gray-100">
                            <td className="px-4 py-2 whitespace-nowrap"></td>
                            <td className="px-4 py-2 whitespace-nowrap text-sm text-gray-600 pl-20">
                              {product.product}
                            </td>
                            <td className="px-4 py-2 whitespace-nowrap text-sm text-gray-500">-</td>
                            <td className="px-4 py-2 whitespace-nowrap text-sm text-gray-500">-</td>
                            <td className="px-4 py-2 whitespace-nowrap text-sm text-gray-500">-</td>
                            <td className="px-4 py-2 whitespace-nowrap text-sm text-right text-gray-700">
                              {product.shipments}
                            </td>
                            <td className="px-4 py-2 whitespace-nowrap text-sm text-right text-gray-700">
                              {formatNumber(product.standardDays)}
                            </td>
                            <td className="px-4 py-2 whitespace-nowrap text-sm text-right text-gray-700">
                              {formatNumber(product.actualDays)}
                            </td>
                            <td className="px-4 py-2 whitespace-nowrap text-sm text-right text-gray-700">
                              {formatNumber(product.standardPercentage)}%
                            </td>
                            <td className="px-4 py-2 whitespace-nowrap text-sm text-right text-gray-700">
                              {formatNumber(product.actualPercentage)}%
                            </td>
                            <td
                              className={`px-4 py-2 whitespace-nowrap text-sm text-right font-medium ${
                                product.status === 'compliant' ? 'text-green-600' :
                                product.status === 'warning' ? 'text-amber-600' : 'text-red-600'
                              }`}
                            >
                              {product.deviation >= 0 ? '+' : ''}
                              {formatNumber(product.deviation)}%
                            </td>
                            <td className="px-4 py-2 whitespace-nowrap text-center text-lg">
                              {getStatusIcon(product.status)}
                            </td>
                          </tr>
                        ))}
                      </>
                    );
                  })}
                </>
              );
            })}
          </tbody>
        </table>
        {sortedData.length === 0 && (
          <div className="text-center py-8 text-gray-500">No data available</div>
        )}
      </div>
    </div>
  );
}
