import { useState, useEffect, useMemo } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/lib/supabase';
import { useTerritoryEquityDataV2 as useTerritoryEquityData } from '@/hooks/reporting/useTerritoryEquityDataV2';
import { TerritoryEquityTable } from '@/components/reporting/TerritoryEquityTable';
import { RegionalEquityTable } from '@/components/reporting/RegionalEquityTable';
import { InboundOutboundChart } from '@/components/reporting/InboundOutboundChart';
import { RegionalEquityTreemap } from '@/components/reporting/RegionalEquityTreemap';
import { CityDetailModal } from '@/components/reporting/CityDetailModal';
import { RegionDetailModal } from '@/components/reporting/RegionDetailModal';
import { TerritoryEquityFilters } from '@/components/reporting/TerritoryEquityFilters';
import { TerritoryEquityTreemap } from '@/components/reporting/TerritoryEquityTreemap';
import { TerritoryEquityMap } from '@/components/reporting/TerritoryEquityMap';
import { ProductAnalysisTable } from '@/components/reporting/ProductAnalysisTable';
import { useEquityAuditExport } from '@/hooks/reporting/useEquityAuditExport';
import { tooltips } from '@/components/reporting/TerritoryEquityTooltips';
import { Info, Download, TrendingUp, Users, AlertTriangle, Award, FileText, Map, Package } from 'lucide-react';
import { SmartTooltip } from '@/components/common/SmartTooltip';
import type { CityEquityData, RegionEquityData, TerritoryEquityFilters as Filters } from '@/types/reporting';

import { useTranslation } from '@/hooks/useTranslation';
import { useFilterScenario } from '@/hooks/reporting/useFilterScenario';
export default function TerritoryEquity() {
  const { t } = useTranslation();
  const { profile } = useAuth();
  const [activeTab, setActiveTab] = useState<'city' | 'regional' | 'map' | 'product'>('city');
  const [selectedCity, setSelectedCity] = useState<CityEquityData | null>(null);
  const [selectedRegion, setSelectedRegion] = useState<RegionEquityData | null>(null);
  const [availableRegions, setAvailableRegions] = useState<string[]>([]);
  const [filters, setFilters] = useState<Filters>({
    startDate: '',
    endDate: '',
    carrier: '',
    product: '',
    region: '',
    direction: undefined,
    equityStatus: [],
  });

  // Load available regions
  useEffect(() => {
    async function loadRegions() {
      if (!profile?.account_id) return;
      
      try {
        const { data } = await supabase
          .from('regions')
          .select('name')
          .eq('account_id', profile.account_id)
          .order('name');
        
        setAvailableRegions(data?.map(r => r.name) || []);
      } catch (error) {
        console.error('Error loading regions:', error);
      }
    }
    
    loadRegions();
  }, [profile?.account_id]);

  // Prepare filters based on active tab - region filter only applies in Regional Analysis
  const effectiveFilters = useMemo(() => {
    if (activeTab === 'regional') {
      return filters;
    }
    // For City Analysis and Map, exclude region filter
    const { region, ...filtersWithoutRegion } = filters;
    return filtersWithoutRegion;
  }, [filters, activeTab]);

  const { 
    cityData, 
    regionData, 
    metrics, 
    routeData,
    loading, 
    error, 
    globalWarningThreshold, 
    globalCriticalThreshold,
    scenarioDescription,
    scenarioInfo: hookScenarioInfo
  } = useTerritoryEquityData(
    profile?.account_id || undefined,
    effectiveFilters
  );

  const { generateMarkdownReport, downloadMarkdown } = useEquityAuditExport();

  // Detect current filter scenario
  const scenarioInfo = useFilterScenario(filters);

  const handleExportAuditReport = () => {
    if (!metrics || cityData.length === 0) return;

    const markdown = generateMarkdownReport({
      cityData,
      regionData,
      metrics,
      filters,
    });

    downloadMarkdown(markdown, `equity-audit-report-${new Date().toISOString().split('T')[0]}.md`);
  };



  const handleExportCSV = () => {
    if (cityData.length === 0) return;

    const headers = [
      'City',
      'Direction',
      'Region',
      'Classification',
      'Population',
      'Shipments',
      'Compliant',
      'Standard %',
      'Actual %',
      'Deviation',
      'J+K Std',
      'J+K Actual',
      'Status',
      'Carrier',
      'Product',
      'CP Shipments',
      'CP Compliant',
      'CP Standard %',
      'CP Actual %',
      'CP Deviation',
      'CP J+K Std',
      'CP J+K Actual',
    ];

    const rows: string[][] = [];
    cityData.forEach((city) => {
      const hasBreakdown = city.carrierProductBreakdown && city.carrierProductBreakdown.length > 0;
      
      if (hasBreakdown) {
        // Inbound rows with carrier/product breakdown
        const inboundBreakdown = city.carrierProductBreakdown?.filter(cp => cp.inboundPercentage > 0) || [];
        if (inboundBreakdown.length > 0) {
          inboundBreakdown.forEach(cp => {
            rows.push([
              city.cityName,
              'Inbound',
              city.regionName || '',
              city.classification || '',
              city.population?.toString() || '',
              city.inboundShipments.toString(),
              city.inboundCompliant.toString(),
              city.inboundStandardPercentage.toFixed(1),
              city.inboundPercentage.toFixed(1),
              city.inboundDeviation.toFixed(1),
              city.inboundStandardDays.toFixed(1),
              city.inboundActualDays.toFixed(1),
              city.inboundPercentage >= globalWarningThreshold ? 'compliant' : (city.inboundPercentage > globalCriticalThreshold ? 'warning' : 'critical'),
              cp.carrier,
              cp.product,
              cp.totalShipments.toString(),
              cp.compliantShipments.toString(),
              cp.standardPercentage.toFixed(1),
              cp.actualPercentage.toFixed(1),
              cp.deviation.toFixed(1),
              cp.standardDays.toFixed(1),
              cp.actualDays.toFixed(1),
            ]);
          });
        } else {
          // Inbound row without breakdown
          rows.push([
            city.cityName,
            'Inbound',
            city.regionName || '',
            city.classification || '',
            city.population?.toString() || '',
            city.inboundShipments.toString(),
            city.inboundCompliant.toString(),
            city.inboundStandardPercentage.toFixed(1),
            city.inboundPercentage.toFixed(1),
            city.inboundDeviation.toFixed(1),
            city.inboundStandardDays.toFixed(1),
            city.inboundActualDays.toFixed(1),
            city.inboundPercentage >= globalWarningThreshold ? 'compliant' : (city.inboundPercentage > globalCriticalThreshold ? 'warning' : 'critical'),
            '', '', '', '', '', '', '', '', '',
          ]);
        }
        
        // Outbound rows with carrier/product breakdown
        const outboundBreakdown = city.carrierProductBreakdown?.filter(cp => cp.outboundPercentage > 0) || [];
        if (outboundBreakdown.length > 0) {
          outboundBreakdown.forEach(cp => {
            rows.push([
              city.cityName,
              'Outbound',
              city.regionName || '',
              city.classification || '',
              city.population?.toString() || '',
              city.outboundShipments.toString(),
              city.outboundCompliant.toString(),
              city.outboundStandardPercentage.toFixed(1),
              city.outboundPercentage.toFixed(1),
              city.outboundDeviation.toFixed(1),
              city.outboundStandardDays.toFixed(1),
              city.outboundActualDays.toFixed(1),
              city.outboundPercentage >= globalWarningThreshold ? 'compliant' : (city.outboundPercentage > globalCriticalThreshold ? 'warning' : 'critical'),
              cp.carrier,
              cp.product,
              cp.totalShipments.toString(),
              cp.compliantShipments.toString(),
              cp.standardPercentage.toFixed(1),
              cp.actualPercentage.toFixed(1),
              cp.deviation.toFixed(1),
              cp.standardDays.toFixed(1),
              cp.actualDays.toFixed(1),
            ]);
          });
        } else {
          // Outbound row without breakdown
          rows.push([
            city.cityName,
            'Outbound',
            city.regionName || '',
            city.classification || '',
            city.population?.toString() || '',
            city.outboundShipments.toString(),
            city.outboundCompliant.toString(),
            city.outboundStandardPercentage.toFixed(1),
            city.outboundPercentage.toFixed(1),
            city.outboundDeviation.toFixed(1),
            city.outboundStandardDays.toFixed(1),
            city.outboundActualDays.toFixed(1),
            city.outboundPercentage >= globalWarningThreshold ? 'compliant' : (city.outboundPercentage > globalCriticalThreshold ? 'warning' : 'critical'),
            '', '', '', '', '', '', '', '', '',
          ]);
        }
      } else {
        // No breakdown - just inbound and outbound rows
        rows.push([
          city.cityName,
          'Inbound',
          city.regionName || '',
          city.classification || '',
          city.population?.toString() || '',
          city.inboundShipments.toString(),
          city.inboundCompliant.toString(),
          city.inboundStandardPercentage.toFixed(1),
          city.inboundPercentage.toFixed(1),
          city.inboundDeviation.toFixed(1),
          city.inboundStandardDays.toFixed(1),
          city.inboundActualDays.toFixed(1),
          city.inboundPercentage >= globalWarningThreshold ? 'compliant' : (city.inboundPercentage > globalCriticalThreshold ? 'warning' : 'critical'),
          '', '', '', '', '', '', '', '', '',
        ]);
        
        rows.push([
          city.cityName,
          'Outbound',
          city.regionName || '',
          city.classification || '',
          city.population?.toString() || '',
          city.outboundShipments.toString(),
          city.outboundCompliant.toString(),
          city.outboundStandardPercentage.toFixed(1),
          city.outboundPercentage.toFixed(1),
          city.outboundDeviation.toFixed(1),
          city.outboundStandardDays.toFixed(1),
          city.outboundActualDays.toFixed(1),
          city.outboundPercentage >= globalWarningThreshold ? 'compliant' : (city.outboundPercentage > globalCriticalThreshold ? 'warning' : 'critical'),
          '', '', '', '', '', '', '', '', '',
        ]);
      }
    });

    const csv = [headers, ...rows].map((row) => row.join(',')).join('\n');
    const blob = new Blob([csv], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `territory-equity-report-${new Date().toISOString().split('T')[0]}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  };

  const handleExportRegionalCSV = () => {
    if (regionData.length === 0) return;

    const headers = [
      'Region',
      'Direction',
      'Cities',
      'Population',
      'Standard %',
      'Actual %',
      'Deviation',
      'J+K Std',
      'J+K Actual',
      'Status',
      'Underserved Cities',
      'Carrier',
      'Product',
      'CP Shipments',
      'CP Compliant',
      'CP Standard %',
      'CP Actual %',
      'CP Deviation',
      'CP J+K Std',
      'CP J+K Actual',
    ];

    const rows: string[][] = [];
    regionData.forEach((region) => {
      const hasBreakdown = region.carrierProductBreakdown && region.carrierProductBreakdown.length > 0;
      
      if (hasBreakdown) {
        // Inbound rows with carrier/product breakdown
        const inboundBreakdown = region.carrierProductBreakdown?.filter(cp => cp.inboundPercentage > 0) || [];
        if (inboundBreakdown.length > 0) {
          inboundBreakdown.forEach(cp => {
            rows.push([
              region.regionName,
              'Inbound',
              region.totalCities.toString(),
              region.totalPopulation?.toString() || '',
              region.inboundStandardPercentage.toFixed(1),
              region.inboundPercentage.toFixed(1),
              region.inboundDeviation.toFixed(1),
              region.inboundStandardDays.toFixed(1),
              region.inboundActualDays.toFixed(1),
              region.inboundPercentage >= globalWarningThreshold ? 'compliant' : (region.inboundPercentage > globalCriticalThreshold ? 'warning' : 'critical'),
              region.underservedCitiesCount.toString(),
              cp.carrier,
              cp.product,
              cp.totalShipments.toString(),
              cp.compliantShipments.toString(),
              cp.standardPercentage.toFixed(1),
              cp.actualPercentage.toFixed(1),
              cp.deviation.toFixed(1),
              cp.standardDays.toFixed(1),
              cp.actualDays.toFixed(1),
            ]);
          });
        } else {
          rows.push([
            region.regionName,
            'Inbound',
            region.totalCities.toString(),
            region.totalPopulation?.toString() || '',
            region.inboundStandardPercentage.toFixed(1),
            region.inboundPercentage.toFixed(1),
            region.inboundDeviation.toFixed(1),
            region.inboundStandardDays.toFixed(1),
            region.inboundActualDays.toFixed(1),
            region.inboundPercentage >= globalWarningThreshold ? 'compliant' : (region.inboundPercentage > globalCriticalThreshold ? 'warning' : 'critical'),
            region.underservedCitiesCount.toString(),
            '', '', '', '', '', '', '', '', '',
          ]);
        }
        
        // Outbound rows with carrier/product breakdown
        const outboundBreakdown = region.carrierProductBreakdown?.filter(cp => cp.outboundPercentage > 0) || [];
        if (outboundBreakdown.length > 0) {
          outboundBreakdown.forEach(cp => {
            rows.push([
              region.regionName,
              'Outbound',
              region.totalCities.toString(),
              region.totalPopulation?.toString() || '',
              region.outboundStandardPercentage.toFixed(1),
              region.outboundPercentage.toFixed(1),
              region.outboundDeviation.toFixed(1),
              region.outboundStandardDays.toFixed(1),
              region.outboundActualDays.toFixed(1),
              region.outboundPercentage >= globalWarningThreshold ? 'compliant' : (region.outboundPercentage > globalCriticalThreshold ? 'warning' : 'critical'),
              region.underservedCitiesCount.toString(),
              cp.carrier,
              cp.product,
              cp.totalShipments.toString(),
              cp.compliantShipments.toString(),
              cp.standardPercentage.toFixed(1),
              cp.actualPercentage.toFixed(1),
              cp.deviation.toFixed(1),
              cp.standardDays.toFixed(1),
              cp.actualDays.toFixed(1),
            ]);
          });
        } else {
          rows.push([
            region.regionName,
            'Outbound',
            region.totalCities.toString(),
            region.totalPopulation?.toString() || '',
            region.outboundStandardPercentage.toFixed(1),
            region.outboundPercentage.toFixed(1),
            region.outboundDeviation.toFixed(1),
            region.outboundStandardDays.toFixed(1),
            region.outboundActualDays.toFixed(1),
            region.outboundPercentage >= globalWarningThreshold ? 'compliant' : (region.outboundPercentage > globalCriticalThreshold ? 'warning' : 'critical'),
            region.underservedCitiesCount.toString(),
            '', '', '', '', '', '', '', '', '',
          ]);
        }
      } else {
        // No breakdown
        rows.push([
          region.regionName,
          'Inbound',
          region.totalCities.toString(),
          region.totalPopulation?.toString() || '',
          region.inboundStandardPercentage.toFixed(1),
          region.inboundPercentage.toFixed(1),
          region.inboundDeviation.toFixed(1),
          region.inboundStandardDays.toFixed(1),
          region.inboundActualDays.toFixed(1),
          region.inboundPercentage >= globalWarningThreshold ? 'compliant' : (region.inboundPercentage > globalCriticalThreshold ? 'warning' : 'critical'),
          region.underservedCitiesCount.toString(),
          '', '', '', '', '', '', '', '', '',
        ]);
        
        rows.push([
          region.regionName,
          'Outbound',
          region.totalCities.toString(),
          region.totalPopulation?.toString() || '',
          region.outboundStandardPercentage.toFixed(1),
          region.outboundPercentage.toFixed(1),
          region.outboundDeviation.toFixed(1),
          region.outboundStandardDays.toFixed(1),
          region.outboundActualDays.toFixed(1),
          region.outboundPercentage >= globalWarningThreshold ? 'compliant' : (region.outboundPercentage > globalCriticalThreshold ? 'warning' : 'critical'),
          region.underservedCitiesCount.toString(),
          '', '', '', '', '', '', '', '', '',
        ]);
      }
    });

    const csv = [headers, ...rows].map((row) => row.join(',')).join('\n');
    const blob = new Blob([csv], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `regional-equity-report-${new Date().toISOString().split('T')[0]}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  };

  // Tooltip component replaced with SmartTooltip for consistency

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-lg text-gray-600">Loading territory equity data...</div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-lg text-red-600">Error loading data: {error.message}</div>
      </div>
    );
  }

  return (
    <div className="space-y-6 p-6">
      {/* Header */}
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-3xl font-bold text-gray-900">
            {scenarioInfo.isRouteView
              ? `Route Analysis: ${scenarioInfo.originCityName} → ${scenarioInfo.destinationCityName}`
              : scenarioInfo.isOriginView
              ? `Territory Equity Report: Outbound from ${scenarioInfo.originCityName}`
              : scenarioInfo.isDestinationView
              ? `Territory Equity Report: Inbound to ${scenarioInfo.destinationCityName}`
              : t('reporting.territory_equity_report')}
          </h1>
          <p className="text-gray-600 mt-1">
            {scenarioInfo.isRouteView
              ? `Detailed performance analysis for the route from ${scenarioInfo.originCityName} to ${scenarioInfo.destinationCityName}`
              : scenarioInfo.isOriginView
              ? `Analyze outbound service equity from ${scenarioInfo.originCityName} to all destinations`
              : scenarioInfo.isDestinationView
              ? `Analyze inbound service equity to ${scenarioInfo.destinationCityName} from all origins`
              : t('reporting.analyze_service_equity_across_cities_and_regions')}
          </p>
        </div>
        <div className="flex gap-2">
          <button
            onClick={handleExportAuditReport}
            className="flex items-center gap-2 px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 transition-colors"
          >
            <FileText className="w-4 h-4" />
            {t('reporting.export_audit_report')}
          </button>
        </div>
      </div>

      {/* Filters */}
      <TerritoryEquityFilters
        filters={filters}
        onChange={setFilters}
        onReset={() => setFilters({
          startDate: '',
          endDate: '',
          carrier: '',
          product: '',
          region: '',
          direction: undefined,
          equityStatus: [],
        })}
      />

      {/* Scenario Description */}
      <div className="mb-4 px-4 py-3 bg-blue-50 border border-blue-100 rounded-lg">
        <p className="text-sm text-blue-800">{scenarioDescription}</p>
      </div>

      {/* KPIs - Reorganized */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-6 gap-4">
        {/* KPI 1: Service Equity Index + Population-Weighted Compliance (Unified) */}
        <div className="bg-white rounded-lg shadow p-6 col-span-1 md:col-span-1 lg:col-span-1">
          <div className="flex items-center justify-between mb-2">
            <h3 className="text-sm font-medium text-gray-600">
              {scenarioInfo.isGeneralView ? t('reporting.service_equity_index') : 
               scenarioInfo.isRouteView ? 'Route Compliance' : 
               'Compliance Metrics'}
            </h3>
            <SmartTooltip content={scenarioInfo.isGeneralView ? tooltips.serviceEquityIndex : tooltips.populationWeightedCompliance} />
          </div>
          {scenarioInfo.isGeneralView && (
            <>
              <div className="text-3xl font-bold text-gray-900">
                {metrics?.serviceEquityIndex.toFixed(1) || '0.0'}
              </div>
              <div className="flex items-center gap-1 mt-1">
                <TrendingUp className="w-4 h-4 text-gray-500" />
                <span className="text-sm text-gray-500">{t('reporting.population_weighted')}</span>
              </div>
              <div className="border-t mt-3 pt-3">
                <div className="text-sm text-gray-600 mb-1">Population-Weighted Compliance</div>
                <div className="text-2xl font-bold text-blue-600">
                  {metrics?.populationWeightedCompliance.toFixed(1) || '0.0'}%
                </div>
                <div className="flex items-center gap-1 mt-1">
                  <Users className="w-4 h-4 text-gray-500" />
                  <span className="text-xs text-gray-500">
                    {metrics?.totalPopulation.toLocaleString() || '0'} citizens
                  </span>
                </div>
              </div>
              <div className="border-t mt-3 pt-3">
                <div className="text-sm text-gray-600 mb-1">Sample-Weighted Compliance</div>
                <div className="text-2xl font-bold text-green-600">
                  {metrics?.sampleWeightedCompliance.toFixed(1) || '0.0'}%
                </div>
                <div className="flex items-center gap-1 mt-1">
                  <Package className="w-4 h-4 text-gray-500" />
                  <span className="text-xs text-gray-500">
                    {metrics?.totalSamples.toLocaleString() || '0'} samples
                  </span>
                </div>
              </div>
            </>
          )}
          {!scenarioInfo.isGeneralView && (
            <>
              <div className="mb-3">
                <div className="text-sm text-gray-600 mb-1">Population-Weighted</div>
                <div className="text-2xl font-bold text-blue-600">
                  {metrics?.populationWeightedCompliance.toFixed(1) || '0.0'}%
                </div>
                <div className="flex items-center gap-1 mt-1">
                  <Users className="w-4 h-4 text-gray-500" />
                  <span className="text-xs text-gray-500">
                    {metrics?.totalPopulation.toLocaleString() || '0'} citizens
                  </span>
                </div>
              </div>
              <div className="border-t pt-3">
                <div className="text-sm text-gray-600 mb-1">Sample-Weighted</div>
                <div className="text-2xl font-bold text-green-600">
                  {metrics?.sampleWeightedCompliance.toFixed(1) || '0.0'}%
                </div>
                <div className="flex items-center gap-1 mt-1">
                  <Package className="w-4 h-4 text-gray-500" />
                  <span className="text-xs text-gray-500">
                    {metrics?.totalSamples.toLocaleString() || '0'} samples
                  </span>
                </div>
              </div>
            </>
          )}
        </div>

        {/* KPI 2: Underserved Cities + Citizens Affected (Unified) */}
        {scenarioInfo.isGeneralView && (
        <div className="bg-white rounded-lg shadow p-6 col-span-1 md:col-span-1 lg:col-span-1">
          <div className="flex items-center justify-between mb-2">
            <h3 className="text-sm font-medium text-gray-600">{t('reporting.underserved_cities')}</h3>
            <SmartTooltip content={tooltips.underservedCities} />
          </div>
          <div className="text-3xl font-bold text-red-600">
            {metrics?.underservedCitiesCount || 0}
          </div>
          <div className="flex items-center gap-1 mt-1">
            <AlertTriangle className="w-4 h-4 text-red-500" />
            <span className="text-sm text-gray-500">
              of {metrics?.totalCities || 0} cities
            </span>
          </div>
          <div className="border-t mt-3 pt-3">
            <div className="text-sm text-gray-600 mb-1">{t('reporting.citizens_affected')}</div>
            <div className="text-2xl font-bold text-red-600">
              {metrics?.citizensAffected.toLocaleString() || '0'}
            </div>
            <div className="flex items-center gap-1 mt-1">
              <Users className="w-4 h-4 text-red-500" />
              <span className="text-xs text-gray-500">citizens in underserved cities</span>
            </div>
          </div>
        </div>
        )}

        {/* KPI 3: Top 3 Best & Worst Cities (Combined) */}
        {!scenarioInfo.isRouteView && (
        <div className="bg-white rounded-lg shadow p-6 col-span-1 md:col-span-2 lg:col-span-2">
          <div className="flex items-center justify-between mb-3">
            <h3 className="text-sm font-medium text-gray-600">
              Top Cities Performance
            </h3>
            <SmartTooltip content={tooltips.topBestServed} />
          </div>
          
          {/* Best Cities */}
          <div className="mb-3">
            <div className="flex items-center gap-1 mb-2">
              <Award className="w-3 h-3 text-green-600" />
              <span className="text-xs font-medium text-green-600">Best Served</span>
            </div>
            <div className="space-y-1">
              <div className="grid grid-cols-7 gap-1 text-[10px] font-medium text-gray-500 border-b pb-1">
                <div>City</div>
                <div className="text-right">Compl.</div>
                <div className="text-right">Std.</div>
                <div className="text-right">J+K Std</div>
                <div className="text-right">J+K Act</div>
                <div className="text-right">Inb.</div>
                <div className="text-right">Outb.</div>
              </div>
              {metrics?.topBestCities.slice(0, 3).map((city, idx) => {
                const relevantPercentage = hookScenarioInfo.isOriginView 
                  ? city.inboundPercentage 
                  : city.outboundPercentage;
                
                return (
                  <div key={idx} className="grid grid-cols-7 gap-1 text-[10px]">
                    <div className="font-medium truncate">{city.cityName}</div>
                    <div className="text-right font-semibold text-green-600">
                      {relevantPercentage.toFixed(1)}%
                    </div>
                    <div className="text-right text-gray-600">
                      {city.standardPercentage.toFixed(1)}%
                    </div>
                    <div className="text-right text-gray-600">
                      {city.standardDays.toFixed(1)}
                    </div>
                    <div className="text-right text-gray-600">
                      {city.actualDays.toFixed(1)}
                    </div>
                    <div className="text-right text-gray-600">
                      {city.inboundPercentage.toFixed(1)}%
                    </div>
                    <div className="text-right text-gray-600">
                      {city.outboundPercentage.toFixed(1)}%
                    </div>
                  </div>
                );
              })}
            </div>
          </div>

          {/* Worst Cities */}
          <div>
            <div className="flex items-center gap-1 mb-2">
              <AlertTriangle className="w-3 h-3 text-red-600" />
              <span className="text-xs font-medium text-red-600">Worst Served</span>
            </div>
            <div className="space-y-1">
              {metrics?.topWorstCities.filter(c => c.status === 'critical' || c.status === 'warning').slice(0, 3).map((city, idx) => {
                const relevantPercentage = hookScenarioInfo.isOriginView 
                  ? city.inboundPercentage 
                  : city.outboundPercentage;
                
                return (
                  <div key={idx} className="grid grid-cols-7 gap-1 text-[10px]">
                    <div className="font-medium truncate">{city.cityName}</div>
                    <div className="text-right font-semibold text-red-600">
                      {relevantPercentage.toFixed(1)}%
                    </div>
                    <div className="text-right text-gray-600">
                      {city.standardPercentage.toFixed(1)}%
                    </div>
                    <div className="text-right text-gray-600">
                      {city.standardDays.toFixed(1)}
                    </div>
                    <div className="text-right text-gray-600">
                      {city.actualDays.toFixed(1)}
                    </div>
                    <div className="text-right text-gray-600">
                      {city.inboundPercentage.toFixed(1)}%
                    </div>
                    <div className="text-right text-gray-600">
                      {city.outboundPercentage.toFixed(1)}%
                    </div>
                  </div>
                );
              })}
              {(!metrics?.topWorstCities || metrics.topWorstCities.filter(c => c.status === 'critical' || c.status === 'warning').length === 0) && (
                <div className="text-[10px] text-gray-500 text-center py-1">{t('reporting.no_underserved_cities')}</div>
              )}
            </div>
          </div>
        </div>
        )}

        {/* KPI 4: Top 3 Best & Worst Regions (Combined - NEW) */}
        {!scenarioInfo.isRouteView && (
        <div className="bg-white rounded-lg shadow p-6 col-span-1 md:col-span-2 lg:col-span-2">
          <div className="flex items-center justify-between mb-3">
            <h3 className="text-sm font-medium text-gray-600">
              Top Regions Performance
            </h3>
            <SmartTooltip content="Performance ranking of regions based on service equity compliance" />
          </div>
          
          {/* Best Regions */}
          <div className="mb-3">
            <div className="flex items-center gap-1 mb-2">
              <Award className="w-3 h-3 text-green-600" />
              <span className="text-xs font-medium text-green-600">Best Served</span>
            </div>
            <div className="space-y-1">
              <div className="grid grid-cols-7 gap-1 text-[10px] font-medium text-gray-500 border-b pb-1">
                <div>Region</div>
                <div className="text-right">Compl.</div>
                <div className="text-right">Std.</div>
                <div className="text-right">J+K Std</div>
                <div className="text-right">J+K Act</div>
                <div className="text-right">Inb.</div>
                <div className="text-right">Outb.</div>
              </div>
              {metrics?.topBestRegions.slice(0, 3).map((region, idx) => {
                const relevantPercentage = hookScenarioInfo.isOriginView 
                  ? region.inboundPercentage 
                  : region.outboundPercentage;
                
                return (
                  <div key={idx} className="grid grid-cols-7 gap-1 text-[10px]">
                    <div className="font-medium truncate">{region.regionName}</div>
                    <div className="text-right font-semibold text-green-600">
                      {relevantPercentage.toFixed(1)}%
                    </div>
                    <div className="text-right text-gray-600">
                      {region.standardPercentage.toFixed(1)}%
                    </div>
                    <div className="text-right text-gray-600">
                      {region.standardDays.toFixed(1)}
                    </div>
                    <div className="text-right text-gray-600">
                      {region.actualDays.toFixed(1)}
                    </div>
                    <div className="text-right text-gray-600">
                      {region.inboundPercentage.toFixed(1)}%
                    </div>
                    <div className="text-right text-gray-600">
                      {region.outboundPercentage.toFixed(1)}%
                    </div>
                  </div>
                );
              })}
            </div>
          </div>

          {/* Worst Regions */}
          <div>
            <div className="flex items-center gap-1 mb-2">
              <AlertTriangle className="w-3 h-3 text-red-600" />
              <span className="text-xs font-medium text-red-600">Worst Served</span>
            </div>
            <div className="space-y-1">
              {metrics?.topWorstRegions.filter(r => r.status === 'critical' || r.status === 'warning').slice(0, 3).map((region, idx) => {
                const relevantPercentage = hookScenarioInfo.isOriginView 
                  ? region.inboundPercentage 
                  : region.outboundPercentage;
                
                return (
                  <div key={idx} className="grid grid-cols-7 gap-1 text-[10px]">
                    <div className="font-medium truncate">{region.regionName}</div>
                    <div className="text-right font-semibold text-red-600">
                      {relevantPercentage.toFixed(1)}%
                    </div>
                    <div className="text-right text-gray-600">
                      {region.standardPercentage.toFixed(1)}%
                    </div>
                    <div className="text-right text-gray-600">
                      {region.standardDays.toFixed(1)}
                    </div>
                    <div className="text-right text-gray-600">
                      {region.actualDays.toFixed(1)}
                    </div>
                    <div className="text-right text-gray-600">
                      {region.inboundPercentage.toFixed(1)}%
                    </div>
                    <div className="text-right text-gray-600">
                      {region.outboundPercentage.toFixed(1)}%
                    </div>
                  </div>
                );
              })}
              {(!metrics?.topWorstRegions || metrics.topWorstRegions.filter(r => r.status === 'critical' || r.status === 'warning').length === 0) && (
                <div className="text-[10px] text-gray-500 text-center py-1">No underserved regions</div>
              )}
            </div>
          </div>
        </div>
        )}
      </div>

      {/* Tabs */}
      <div className="bg-white rounded-lg shadow">
        <div className="border-b">
          <div className="flex">
            <button
              onClick={() => setActiveTab('city')}
              className={`px-6 py-3 font-medium transition-colors ${
                activeTab === 'city'
                  ? 'border-b-2 border-blue-600 text-blue-600'
                  : 'text-gray-600 hover:text-gray-900'
              }`}
            >
              {t('reporting.city_analysis')}
            </button>
            <button
              onClick={() => setActiveTab('regional')}
                className={`px-6 py-3 font-medium transition-colors ${
                  activeTab === 'regional'
                    ? 'border-b-2 border-blue-600 text-blue-600'
                    : 'text-gray-600 hover:text-gray-900'
                }`}
              >
                {t('reporting.regional_analysis')}
            </button>
            <button
              onClick={() => setActiveTab('map')}
                className={`px-6 py-3 font-medium transition-colors flex items-center gap-2 ${
                  activeTab === 'map'
                    ? 'border-b-2 border-blue-600 text-blue-600'
                    : 'text-gray-600 hover:text-gray-900'
                }`}
              >
                <Map className="w-4 h-4" />
                {t('reporting.geographic_view')}
            </button>
            <button
              onClick={() => setActiveTab('product')}
              className={`px-6 py-3 font-medium transition-colors ${
                activeTab === 'product'
                  ? 'border-b-2 border-blue-600 text-blue-600'
                  : 'text-gray-600 hover:text-gray-900'
              }`}
            >
              Product Analysis
            </button>
          </div>
        </div>

        <div className="p-6">
          {activeTab === 'city' && (
            <div className="space-y-6">
              {/* Treemap Visualization */}
              <div>
                <div className="flex items-center gap-2 mb-4">
                  <h3 className="text-lg font-semibold">{t('reporting.city_service_equity_treemap')}</h3>
                  <SmartTooltip content={tooltips.treemap} />
                </div>
                <TerritoryEquityTreemap 
                  data={cityData} 
                  scenarioInfo={hookScenarioInfo}
                  globalWarningThreshold={globalWarningThreshold}
                  globalCriticalThreshold={globalCriticalThreshold}
                  scenarioDescription={scenarioDescription}
                />
              </div>

              {/* Inbound vs Outbound Chart */}
              <div>
                <div className="flex items-center gap-2 mb-4">
                  <h3 className="text-lg font-semibold">
                    {t('reporting.inbound_vs_outbound_comparison_top_10_by_direction')}
                  </h3>
                  <SmartTooltip content={tooltips.inboundOutboundChart} />
                </div>
                <InboundOutboundChart data={cityData} scenarioDescription={scenarioDescription} />
              </div>

              {/* City Table */}
              <div>
                <div className="flex items-center justify-between mb-4">
                  <div className="flex items-center gap-2">
                    <h3 className="text-lg font-semibold">{t('reporting.city_equity_details')}</h3>
                    <SmartTooltip content={tooltips.cityTable} />
                  </div>
                  <button
                    onClick={handleExportCSV}
                    className="flex items-center gap-2 px-3 py-1.5 text-sm bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors"
                  >
                    <Download className="w-4 h-4" />
                    {t('common.export_csv')}
                  </button>
                </div>
                <TerritoryEquityTable 
                  data={cityData} 
                  onCityClick={setSelectedCity} 
                  globalWarningThreshold={globalWarningThreshold}
                  globalCriticalThreshold={globalCriticalThreshold}
                  scenarioInfo={hookScenarioInfo}
                  scenarioDescription={scenarioDescription}
                  showProductBreakdown={filters.equityStatus && filters.equityStatus.length > 0}
                  equityStatusFilter={filters.equityStatus || []}
                />
              </div>
            </div>
          )}

          {activeTab === 'regional' && (
            <div className="space-y-6">
              {/* Regional Treemap - Always visible */}
              <div>
                <div className="flex items-center gap-2 mb-4">
                  <h3 className="text-lg font-semibold">{t('reporting.regional_service_equity_treemap')}</h3>
                  <SmartTooltip content={tooltips.treemap} />
                </div>
                <RegionalEquityTreemap 
                  data={regionData} 
                  scenarioInfo={hookScenarioInfo}
                  globalWarningThreshold={globalWarningThreshold}
                  globalCriticalThreshold={globalCriticalThreshold}
                  scenarioDescription={scenarioDescription}
                />
              </div>

              {/* Region Filter */}
              <div className="bg-white p-4 rounded-lg border border-gray-200">
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Region - Analyze inbound shipments to cities within a specific region
                </label>
                <select
                  value={filters.region || ''}
                  onChange={(e) => setFilters({ ...filters, region: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                >
                  <option value="">All Regions (Treemap view only)</option>
                  {availableRegions.map(region => (
                    <option key={region} value={region}>{region}</option>
                  ))}
                </select>
              </div>

              {/* City Table - Only when region is selected */}
              {filters.region && (() => {
                const filteredCities = cityData.filter(c => c.regionName === filters.region);
                return (
                <div>
                  <div className="flex items-center justify-between mb-4">
                    <div className="flex items-center gap-2">
                      <h3 className="text-lg font-semibold">
                        Cities in {filters.region} Region - Inbound Analysis
                      </h3>
                      <SmartTooltip content="Detailed breakdown of cities within the selected region, showing inbound shipments and service equity metrics." />
                    </div>
                    <button
                      onClick={handleExportCSV}
                      className="flex items-center gap-2 px-3 py-1.5 text-sm bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors"
                    >
                      <Download className="w-4 h-4" />
                      {t('common.export_csv')}
                    </button>
                  </div>
                  <TerritoryEquityTable 
                    data={filteredCities}
                    onCityClick={setSelectedCity}
                    globalWarningThreshold={globalWarningThreshold}
                    globalCriticalThreshold={globalCriticalThreshold}
                    scenarioInfo={{
                      scenario: 'origin',
                      isOriginView: true,
                      isDestinationView: false,
                      isRouteView: false,
                      isGeneralView: false
                    }}
                    scenarioDescription={`Showing cities in ${filters.region} region with inbound shipment analysis`}
                  />
                </div>
                );
              })()}
            </div>
          )}

          {activeTab === 'map' && (
            <div className="space-y-6">
              <div>
                <div className="mb-4">
                  <h3 className="text-lg font-semibold mb-2">{t('reporting.geographic_distribution')}</h3>
                  {/* Scenario Description */}
                  <div className="mb-3 px-4 py-3 bg-blue-50 border border-blue-100 rounded-lg">
                    <p className="text-sm text-blue-800">{scenarioDescription}</p>
                  </div>
                  <p className="text-sm text-gray-600">
                    {t('reporting.map_interactive_description')}
                  </p>
                </div>
                <TerritoryEquityMap data={cityData} />
              </div>
            </div>
          )}

          {activeTab === 'product' && (
            <div className="space-y-6">
              <div>
                <div className="mb-4">
                  <h3 className="text-lg font-semibold mb-2">Product-Level Route Analysis</h3>
                  <p className="text-sm text-gray-600">
                    Detailed breakdown of all routes by carrier and product. Filter by equity status to identify specific compliance issues.
                  </p>
                </div>
                <ProductAnalysisTable 
                  routeData={routeData}
                  globalWarningThreshold={globalWarningThreshold}
                  globalCriticalThreshold={globalCriticalThreshold}
                />
              </div>
            </div>
          )}
        </div>
      </div>

      {/* City Detail Modal */}
      {selectedCity && (
        <CityDetailModal
          city={selectedCity}
          onClose={() => setSelectedCity(null)}
        />
      )}

      {/* Region Detail Modal */}
      {selectedRegion && (
        <RegionDetailModal
          region={selectedRegion}
          onClose={() => setSelectedRegion(null)}
        />
      )}
    </div>
  );
}
