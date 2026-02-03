import { useState } from 'react';
import { formatNumber } from '@/lib/formatNumber';
import { ChevronDown, ChevronRight, ChevronsDown, ChevronsUp } from 'lucide-react';
import type { RegionEquityData } from '@/types/reporting';
import type { ScenarioInfo } from '@/hooks/reporting/useFilterScenario';
import { useTranslation } from '@/hooks/useTranslation';

interface RegionalEquityTableProps {
  data: RegionEquityData[];
  onRegionClick?: (region: RegionEquityData) => void;
  globalWarningThreshold: number;
  globalCriticalThreshold: number;
  scenarioInfo: ScenarioInfo;
  scenarioDescription: string;
}

type RegionRow = {
  regionId: string;
  regionName: string;
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
  originalRegion: RegionEquityData;
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

export function RegionalEquityTable({ 
  data, 
  onRegionClick, 
  globalWarningThreshold, 
  globalCriticalThreshold,
  scenarioInfo,
  scenarioDescription 
}: RegionalEquityTableProps) {
  const { t } = useTranslation();
  const [sortField, setSortField] = useState<keyof RegionRow>('regionName');
  const [sortDirection, setSortDirection] = useState<'asc' | 'desc'>('asc');
  const [expandedRegions, setExpandedRegions] = useState<Set<string>>(new Set());
  const [expandedCarriers, setExpandedCarriers] = useState<Set<string>>(new Set());
  const [expandAll, setExpandAll] = useState(false);

  // Toggle region expansion (expands/collapses all levels below)
  const toggleRegion = (regionId: string) => {
    const newExpanded = new Set(expandedRegions);
    const newExpandedCarriers = new Set(expandedCarriers);
    
    if (newExpanded.has(regionId)) {
      // Collapse region and all its carriers
      newExpanded.delete(regionId);
      const carriersToRemove = Array.from(newExpandedCarriers).filter(id => id.startsWith(`${regionId}-`));
      carriersToRemove.forEach(id => newExpandedCarriers.delete(id));
    } else {
      // Expand region and all its carriers
      newExpanded.add(regionId);
      // Find all carriers for this region and expand them
      const regionRow = regionRows.find(r => r.regionId === regionId);
      if (regionRow) {
        regionRow.carrierBreakdown.forEach(carrier => {
          newExpandedCarriers.add(`${regionId}-${carrier.carrier}`);
        });
      }
    }
    
    setExpandedRegions(newExpanded);
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

  // Toggle all regions
  const toggleAll = () => {
    if (expandAll) {
      setExpandedRegions(new Set());
      setExpandedCarriers(new Set());
    } else {
      const allRegions = new Set(regionRows.map(r => r.regionId));
      const allCarriers = new Set<string>();
      regionRows.forEach(region => {
        region.carrierBreakdown.forEach(carrier => {
          allCarriers.add(`${region.regionId}-${carrier.carrier}`);
        });
      });
      setExpandedRegions(allRegions);
      setExpandedCarriers(allCarriers);
    }
    setExpandAll(!expandAll);
  };

  // Determine which metrics to show based on scenario
  const getMetricsForRegion = (region: RegionEquityData) => {
    if (scenarioInfo.isOriginView) {
      return {
        shipments: region.inboundShipments,
        compliant: region.inboundCompliant,
        standardPercentage: region.inboundStandardPercentage,
        actualPercentage: region.inboundPercentage,
        deviation: region.inboundDeviation,
        standardDays: region.inboundStandardDays,
        actualDays: region.inboundActualDays,
      };
    } else if (scenarioInfo.isDestinationView) {
      return {
        shipments: region.outboundShipments,
        compliant: region.outboundCompliant,
        standardPercentage: region.outboundStandardPercentage,
        actualPercentage: region.outboundPercentage,
        deviation: region.outboundDeviation,
        standardDays: region.outboundStandardDays,
        actualDays: region.outboundActualDays,
      };
    } else {
      return {
        shipments: region.outboundShipments,
        compliant: region.outboundCompliant,
        standardPercentage: region.outboundStandardPercentage,
        actualPercentage: region.outboundPercentage,
        deviation: region.outboundDeviation,
        standardDays: region.outboundStandardDays,
        actualDays: region.outboundActualDays,
      };
    }
  };

  // Build region rows with carrier/product hierarchy
  const regionRows: RegionRow[] = data
    .filter(region => {
      const metrics = getMetricsForRegion(region);
      return metrics.shipments > 0 || metrics.standardDays > 0;
    })
    .map((region) => {
      const metrics = getMetricsForRegion(region);
      
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
      region.carrierProductBreakdown?.forEach(cp => {
        const hasRelevantData = scenarioInfo.isOriginView
          ? cp.inboundPercentage > 0 || cp.totalShipments > 0
          : scenarioInfo.isDestinationView
          ? cp.outboundPercentage > 0 || cp.totalShipments > 0
          : cp.outboundPercentage > 0 || cp.totalShipments > 0;

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
        if (cp.actualDays > 0) {
          carrierData.actualDaysSum += cp.actualDays * cp.totalShipments;
          carrierData.actualDaysCount += cp.totalShipments;
        }
        
        const relevantPercentage = scenarioInfo.isOriginView
          ? cp.inboundPercentage
          : scenarioInfo.isDestinationView
          ? cp.outboundPercentage
          : cp.outboundPercentage;
        
        const productStatus: 'compliant' | 'warning' | 'critical' = 
          relevantPercentage >= globalWarningThreshold ? 'compliant' :
          relevantPercentage >= globalCriticalThreshold ? 'warning' : 'critical';

        carrierData.products.set(cp.product, {
          product: cp.product,
          shipments: cp.totalShipments,
          compliant: cp.compliantShipments,
          standardPercentage: cp.standardPercentage,
          actualPercentage: relevantPercentage,
          deviation: relevantPercentage - cp.standardPercentage,
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

      const regionStatus: 'compliant' | 'warning' | 'critical' = 
        metrics.actualPercentage >= globalWarningThreshold ? 'compliant' :
        metrics.actualPercentage >= globalCriticalThreshold ? 'warning' : 'critical';

      return {
        regionId: region.regionId,
        regionName: region.regionName,
        classification: null,
        population: region.totalPopulation,
        shipments: metrics.shipments,
        compliant: metrics.compliant,
        standardPercentage: metrics.standardPercentage,
        actualPercentage: metrics.actualPercentage,
        deviation: metrics.deviation,
        standardDays: metrics.standardDays,
        actualDays: metrics.actualDays,
        status: regionStatus,
        originalRegion: region,
        carrierBreakdown,
      };
    });

  // Sort regions
  const sortedRegions = [...regionRows].sort((a, b) => {
    const aVal = a[sortField];
    const bVal = b[sortField];
    if (aVal === null || aVal === undefined) return 1;
    if (bVal === null || bVal === undefined) return -1;
    if (typeof aVal === 'string' && typeof bVal === 'string') {
      return sortDirection === 'asc' ? aVal.localeCompare(bVal) : bVal.localeCompare(aVal);
    }
    return sortDirection === 'asc' ? (aVal > bVal ? 1 : -1) : (aVal < bVal ? 1 : -1);
  });

  const handleSort = (field: keyof RegionRow) => {
    if (sortField === field) {
      setSortDirection(sortDirection === 'asc' ? 'desc' : 'asc');
    } else {
      setSortField(field);
      setSortDirection('asc');
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'compliant': return 'text-green-600';
      case 'warning': return 'text-amber-600';
      case 'critical': return 'text-red-600';
      default: return 'text-gray-600';
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'compliant': return <div className="w-4 h-4 rounded-full bg-green-500"></div>;
      case 'warning': return <div className="w-4 h-4 rounded-full bg-amber-500"></div>;
      case 'critical': return <div className="w-4 h-4 rounded-full bg-red-500"></div>;
      default: return <div className="w-4 h-4 rounded-full bg-gray-400"></div>;
    }
  };

  if (!data || data.length === 0) {
    return (
      <div className="bg-white rounded-lg shadow p-6">
        <p className="text-gray-500 text-center">No data available</p>
      </div>
    );
  }

  return (
    <div className="bg-white rounded-lg shadow overflow-hidden">
      {/* Scenario Description */}
      <div className="px-4 py-3 bg-blue-50 border-b border-blue-100">
        <p className="text-sm text-blue-800">{scenarioDescription}</p>
      </div>

      {/* Expand All Button */}
      <div className="px-4 py-2 bg-gray-50 border-b border-gray-200 flex justify-end">
        <button
          onClick={toggleAll}
          className="flex items-center gap-2 text-sm text-blue-600 hover:text-blue-800 transition-colors"
        >
          {expandAll ? <ChevronsUp className="w-4 h-4" /> : <ChevronsDown className="w-4 h-4" />}
          {expandAll ? t('common.collapse_all') : t('common.expand_all')}
        </button>
      </div>

      <div className="overflow-x-auto">
        <table className="w-full">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100" onClick={() => handleSort('regionName')}>
                {t('reporting.region')}
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('reporting.class')}
              </th>
              <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100" onClick={() => handleSort('population')}>
                {t('reporting.population')}
              </th>
              <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100" onClick={() => handleSort('shipments')}>
                {t('reporting.total')}
              </th>
              <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100" onClick={() => handleSort('standardDays')}>
                {t('reporting.jk_std')}
              </th>
              <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100" onClick={() => handleSort('actualDays')}>
                {t('reporting.jk_actual')}
              </th>
              <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100" onClick={() => handleSort('standardPercentage')}>
                {t('reporting.standard_percent')}
              </th>
              <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100" onClick={() => handleSort('actualPercentage')}>
                {t('reporting.actual_percent')}
              </th>
              <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100" onClick={() => handleSort('deviation')}>
                {t('reporting.deviation')}
              </th>
              <th className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('reporting.status')}
              </th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {sortedRegions.map((region) => (
              <>
                {/* Region Row */}
                <tr 
                  key={region.regionId}
                  className="hover:bg-gray-50 cursor-pointer"
                  onClick={() => toggleRegion(region.regionId)}
                >
                  <td className="px-4 py-3 whitespace-nowrap">
                    <div className="flex items-center gap-2">
                      {expandedRegions.has(region.regionId) ? (
                        <ChevronDown className="w-4 h-4 text-gray-400" />
                      ) : (
                        <ChevronRight className="w-4 h-4 text-gray-400" />
                      )}
                      <span className="text-sm font-medium text-gray-900">{region.regionName}</span>
                    </div>
                  </td>
                  <td className="px-4 py-3 whitespace-nowrap text-sm text-gray-500">
                    {region.classification || '-'}
                  </td>
                  <td className="px-4 py-3 whitespace-nowrap text-sm text-gray-900 text-right">
                    {region.population ? formatNumber(region.population) : '-'}
                  </td>
                  <td className="px-4 py-3 whitespace-nowrap text-sm text-gray-900 text-right">
                    {formatNumber(region.shipments)}
                  </td>
                  <td className="px-4 py-3 whitespace-nowrap text-sm text-gray-900 text-right">
                    {formatNumber(region.standardDays)}
                  </td>
                  <td className="px-4 py-3 whitespace-nowrap text-sm text-gray-900 text-right">
                    {formatNumber(region.actualDays)}
                  </td>
                  <td className="px-4 py-3 whitespace-nowrap text-sm text-gray-900 text-right">
                    {formatNumber(region.standardPercentage)}%
                  </td>
                  <td className="px-4 py-3 whitespace-nowrap text-sm text-gray-900 text-right">
                    {formatNumber(region.actualPercentage)}%
                  </td>
                  <td className={`px-4 py-3 whitespace-nowrap text-sm text-right font-medium ${getStatusColor(region.status)}`}>
                    {region.deviation > 0 ? '+' : ''}{formatNumber(region.deviation)}%
                  </td>
                  <td className="px-4 py-3 whitespace-nowrap text-center">
                    {getStatusIcon(region.status)}
                  </td>
                </tr>

                {/* Carrier Rows */}
                {expandedRegions.has(region.regionId) && region.carrierBreakdown.map((carrier) => {
                  const carrierId = `${region.regionId}-${carrier.carrier}`;
                  return (
                    <>
                      <tr 
                        key={carrierId}
                        className="bg-gray-50 hover:bg-gray-100 cursor-pointer"
                        onClick={(e) => { e.stopPropagation(); toggleCarrier(carrierId); }}
                      >
                        <td className="px-4 py-2 whitespace-nowrap">
                          <div className="flex items-center gap-2 pl-8">
                            {expandedCarriers.has(carrierId) ? (
                              <ChevronDown className="w-3 h-3 text-gray-400" />
                            ) : (
                              <ChevronRight className="w-3 h-3 text-gray-400" />
                            )}
                            <span className="text-sm text-gray-700">{carrier.carrier}</span>
                          </div>
                        </td>
                        <td className="px-4 py-2 whitespace-nowrap text-sm text-gray-500">-</td>
                        <td className="px-4 py-2 whitespace-nowrap text-sm text-gray-500 text-right">-</td>
                        <td className="px-4 py-2 whitespace-nowrap text-sm text-gray-700 text-right">
                          {formatNumber(carrier.shipments)}
                        </td>
                        <td className="px-4 py-2 whitespace-nowrap text-sm text-gray-700 text-right">
                          {formatNumber(carrier.standardDays)}
                        </td>
                        <td className="px-4 py-2 whitespace-nowrap text-sm text-gray-700 text-right">
                          {formatNumber(carrier.actualDays)}
                        </td>
                        <td className="px-4 py-2 whitespace-nowrap text-sm text-gray-700 text-right">
                          {formatNumber(carrier.standardPercentage)}%
                        </td>
                        <td className="px-4 py-2 whitespace-nowrap text-sm text-gray-700 text-right">
                          {formatNumber(carrier.actualPercentage)}%
                        </td>
                        <td className={`px-4 py-2 whitespace-nowrap text-sm text-right font-medium ${getStatusColor(carrier.status)}`}>
                          {carrier.deviation > 0 ? '+' : ''}{formatNumber(carrier.deviation)}%
                        </td>
                        <td className="px-4 py-2 whitespace-nowrap text-center">
                          {getStatusIcon(carrier.status)}
                        </td>
                      </tr>

                      {/* Product Rows */}
                      {expandedCarriers.has(carrierId) && carrier.productBreakdown.map((product) => (
                        <tr key={`${carrierId}-${product.product}`} className="bg-blue-50">
                          <td className="px-4 py-2 whitespace-nowrap">
                            <div className="pl-16 text-sm text-gray-600">{product.product}</div>
                          </td>
                          <td className="px-4 py-2 whitespace-nowrap text-sm text-gray-500">-</td>
                          <td className="px-4 py-2 whitespace-nowrap text-sm text-gray-500 text-right">-</td>
                          <td className="px-4 py-2 whitespace-nowrap text-sm text-gray-600 text-right">
                            {formatNumber(product.shipments)}
                          </td>
                          <td className="px-4 py-2 whitespace-nowrap text-sm text-gray-600 text-right">
                            {formatNumber(product.standardDays)}
                          </td>
                          <td className="px-4 py-2 whitespace-nowrap text-sm text-gray-600 text-right">
                            {formatNumber(product.actualDays)}
                          </td>
                          <td className="px-4 py-2 whitespace-nowrap text-sm text-gray-600 text-right">
                            {formatNumber(product.standardPercentage)}%
                          </td>
                          <td className="px-4 py-2 whitespace-nowrap text-sm text-gray-600 text-right">
                            {formatNumber(product.actualPercentage)}%
                          </td>
                          <td className={`px-4 py-2 whitespace-nowrap text-sm text-right font-medium ${getStatusColor(product.status)}`}>
                            {product.deviation > 0 ? '+' : ''}{formatNumber(product.deviation)}%
                          </td>
                          <td className="px-4 py-2 whitespace-nowrap text-center">
                            {getStatusIcon(product.status)}
                          </td>
                        </tr>
                      ))}
                    </>
                  );
                })}
              </>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
