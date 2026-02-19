import React, { useState, useMemo } from 'react';
import { ChevronDown, ChevronRight } from 'lucide-react';
import type { JKCityData, JKCarrierData, JKProductBreakdown } from '@/hooks/reporting/useJKPerformance';
import type { ScenarioInfo } from '@/hooks/reporting/useFilterScenario';
import { useTranslation } from '@/hooks/useTranslation';

interface JKHierarchicalTableProps {
  cityData: JKCityData[];
  carrierData: JKCarrierData[];
  productData: any[];
  scenarioInfo: ScenarioInfo;
  scenarioDescription: string;
  globalWarningThreshold: number;
  globalCriticalThreshold: number;
}

export function JKHierarchicalTable({
  cityData,
  carrierData,
  productData,
  scenarioInfo,
  scenarioDescription,
  globalWarningThreshold,
  globalCriticalThreshold,
}: JKHierarchicalTableProps) {
  const { t } = useTranslation();
  const [expandedCities, setExpandedCities] = useState<Set<string>>(new Set());
  const [expandedCarriers, setExpandedCarriers] = useState<Set<string>>(new Set());

  // Filter cities based on direction from scenario
  const filteredCityData = useMemo(() => {
    if (scenarioInfo.isOriginView) {
      return cityData.filter(c => c.direction === 'inbound');
    } else if (scenarioInfo.isDestinationView || scenarioInfo.isGeneralView) {
      return cityData.filter(c => c.direction === 'outbound');
    }
    return cityData;
  }, [cityData, scenarioInfo]);

  const toggleCity = (cityName: string) => {
    const newExpanded = new Set(expandedCities);
    if (newExpanded.has(cityName)) {
      newExpanded.delete(cityName);
    } else {
      newExpanded.add(cityName);
    }
    setExpandedCities(newExpanded);
  };

  const toggleCarrier = (key: string) => {
    const newExpanded = new Set(expandedCarriers);
    if (newExpanded.has(key)) {
      newExpanded.delete(key);
    } else {
      newExpanded.add(key);
    }
    setExpandedCarriers(newExpanded);
  };

  const getStatusColor = (status: 'compliant' | 'warning' | 'critical') => {
    switch (status) {
      case 'compliant':
        return 'bg-green-100 text-green-800';
      case 'warning':
        return 'bg-amber-100 text-amber-800';
      case 'critical':
        return 'bg-red-100 text-red-800';
      default:
        return 'bg-gray-100 text-gray-800';
    }
  };

  const getStatusBadge = (status: 'compliant' | 'warning' | 'critical') => {
    const colorClass = getStatusColor(status);
    return (
      <span className={`px-2 py-1 text-xs font-medium rounded-full ${colorClass}`}>
        {status === 'compliant' ? '✓ Compliant' : status === 'warning' ? '⚠ Warning' : '✕ Critical'}
      </span>
    );
  };

  if (!filteredCityData || filteredCityData.length === 0) {
    return (
      <div className="bg-white rounded-lg shadow p-6">
        <div className="text-center py-8 text-gray-400">
          No J+K performance data available
        </div>
      </div>
    );
  }

  return (
    <div className="bg-white rounded-lg shadow">
      {/* Scenario Description */}
      <div className="p-4 bg-blue-50 border-b border-blue-100 rounded-t-lg">
        <p className="text-sm text-blue-800">{scenarioDescription}</p>
      </div>

      <div className="overflow-x-auto">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                City / Carrier / Product
              </th>
              <th className="px-3 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Routes
              </th>
              <th className="px-3 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Samples
              </th>
              <th className="px-3 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                J+K Std (days)
              </th>
              <th className="px-3 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                J+K Actual (days)
              </th>
              <th className="px-3 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Deviation (days)
              </th>
              <th className="px-3 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                On-Time %
              </th>
              <th className="px-3 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Std %
              </th>
              <th className="px-3 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider">
                Status
              </th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {filteredCityData.map((city) => {
              const isExpanded = expandedCities.has(city.cityName);
              
              // Get carriers for this city
              const cityCarriers = carrierData.filter(carrier => {
                // Filter carriers that have routes in this city
                // This is a simplified approach - you may need to enhance based on actual data structure
                return true; // For now, show all carriers
              });

              return (
                <React.Fragment key={`${city.cityName}-${city.direction}`}>
                  {/* City Row */}
                  <tr className="hover:bg-gray-50 cursor-pointer" onClick={() => toggleCity(city.cityName)}>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="flex items-center">
                        {cityCarriers.length > 0 && (
                          isExpanded ? (
                            <ChevronDown className="w-4 h-4 mr-2 text-gray-400" />
                          ) : (
                            <ChevronRight className="w-4 h-4 mr-2 text-gray-400" />
                          )
                        )}
                        <div>
                          <div className="text-sm font-medium text-gray-900">{city.cityName}</div>
                          <div className="text-xs text-gray-500">{city.regionName}</div>
                        </div>
                      </div>
                    </td>
                    <td className="px-3 py-4 whitespace-nowrap text-right text-sm text-gray-900">
                      {city.routes}
                    </td>
                    <td className="px-3 py-4 whitespace-nowrap text-right text-sm text-gray-900">
                      {(city.totalSamples || 0).toLocaleString()}
                    </td>
                    <td className="px-3 py-4 whitespace-nowrap text-right text-sm text-gray-900">
                      {(city.jkStandard || 0).toFixed(1)}
                    </td>
                    <td className="px-3 py-4 whitespace-nowrap text-right text-sm font-medium text-gray-900">
                      {(city.jkActual || 0).toFixed(1)}
                    </td>
                    <td className={`px-3 py-4 whitespace-nowrap text-right text-sm font-medium ${
                      (city.deviation || 0) > 0 ? 'text-red-600' : 'text-green-600'
                    }`}>
                      {(city.deviation || 0) > 0 ? '+' : ''}{(city.deviation || 0).toFixed(1)}
                    </td>
                    <td className="px-3 py-4 whitespace-nowrap text-right text-sm font-medium text-gray-900">
                      {(city.onTimePercentage || 0).toFixed(1)}%
                    </td>
                    <td className="px-3 py-4 whitespace-nowrap text-right text-sm text-gray-500">
                      {(city.standardPercentage || 0).toFixed(1)}%
                    </td>
                    <td className="px-3 py-4 whitespace-nowrap text-center">
                      {getStatusBadge(city.status)}
                    </td>
                  </tr>

                  {/* Carrier Rows (when city is expanded) */}
                  {isExpanded && cityCarriers.map((carrier) => {
                    const carrierKey = `${city.cityName}-${carrier.carrier}`;
                    const isCarrierExpanded = expandedCarriers.has(carrierKey);

                    return (
                      <React.Fragment key={carrierKey}>
                        {/* Carrier Row */}
                        <tr 
                          className="hover:bg-gray-50 cursor-pointer bg-gray-50"
                          onClick={(e) => {
                            e.stopPropagation();
                            toggleCarrier(carrierKey);
                          }}
                        >
                          <td className="px-6 py-3 whitespace-nowrap">
                            <div className="flex items-center pl-8">
                              {carrier.products && carrier.products.length > 0 && (
                                isCarrierExpanded ? (
                                  <ChevronDown className="w-4 h-4 mr-2 text-gray-400" />
                                ) : (
                                  <ChevronRight className="w-4 h-4 mr-2 text-gray-400" />
                                )
                              )}
                              <span className="text-sm font-medium text-gray-700">{carrier.carrier}</span>
                            </div>
                          </td>
                          <td className="px-3 py-3 whitespace-nowrap text-right text-sm text-gray-700">
                            {carrier.routes}
                          </td>
                          <td className="px-3 py-3 whitespace-nowrap text-right text-sm text-gray-700">
                            {(carrier.totalSamples || 0).toLocaleString()}
                          </td>
                          <td className="px-3 py-3 whitespace-nowrap text-right text-sm text-gray-700">
                            {(carrier.jkStandard || 0).toFixed(1)}
                          </td>
                          <td className="px-3 py-3 whitespace-nowrap text-right text-sm font-medium text-gray-700">
                            {(carrier.jkActual || 0).toFixed(1)}
                          </td>
                          <td className={`px-3 py-3 whitespace-nowrap text-right text-sm font-medium ${
                            (carrier.deviation || 0) > 0 ? 'text-red-600' : 'text-green-600'
                          }`}>
                            {(carrier.deviation || 0) > 0 ? '+' : ''}{(carrier.deviation || 0).toFixed(1)}
                          </td>
                          <td className="px-3 py-3 whitespace-nowrap text-right text-sm font-medium text-gray-700">
                            {(carrier.onTimePercentage || 0).toFixed(1)}%
                          </td>
                          <td className="px-3 py-3 whitespace-nowrap text-right text-sm text-gray-500">
                            {(carrier.standardPercentage || 0).toFixed(1)}%
                          </td>
                          <td className="px-3 py-3 whitespace-nowrap text-center">
                            {getStatusBadge(carrier.status)}
                          </td>
                        </tr>

                        {/* Product Rows (when carrier is expanded) */}
                        {isCarrierExpanded && carrier.products && carrier.products.map((product: JKProductBreakdown) => (
                          <tr key={`${carrierKey}-${product.product}`} className="bg-gray-100">
                            <td className="px-6 py-2 whitespace-nowrap">
                              <div className="flex items-center pl-16">
                                <span className="text-sm text-gray-600">{product.product}</span>
                              </div>
                            </td>
                            <td className="px-3 py-2 whitespace-nowrap text-right text-sm text-gray-600">
                              {product.routes}
                            </td>
                            <td className="px-3 py-2 whitespace-nowrap text-right text-sm text-gray-600">
                              {(product.totalSamples || 0).toLocaleString()}
                            </td>
                            <td className="px-3 py-2 whitespace-nowrap text-right text-sm text-gray-600">
                              {(product.jkStandard || 0).toFixed(1)}
                            </td>
                            <td className="px-3 py-2 whitespace-nowrap text-right text-sm font-medium text-gray-600">
                              {(product.jkActual || 0).toFixed(1)}
                            </td>
                            <td className={`px-3 py-2 whitespace-nowrap text-right text-sm font-medium ${
                              (product.deviation || 0) > 0 ? 'text-red-600' : 'text-green-600'
                            }`}>
                              {(product.deviation || 0) > 0 ? '+' : ''}{(product.deviation || 0).toFixed(1)}
                            </td>
                            <td className="px-3 py-2 whitespace-nowrap text-right text-sm font-medium text-gray-600">
                              {(product.onTimePercentage || 0).toFixed(1)}%
                            </td>
                            <td className="px-3 py-2 whitespace-nowrap text-right text-sm text-gray-500">
                              {(product.standardPercentage || 0).toFixed(1)}%
                            </td>
                            <td className="px-3 py-2 whitespace-nowrap text-center">
                              {getStatusBadge(product.status)}
                            </td>
                          </tr>
                        ))}
                      </React.Fragment>
                    );
                  })}
                </React.Fragment>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
