import React, { useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/lib/supabase';
import { useTerritoryEquityDataV2 as useTerritoryEquityData } from '@/hooks/reporting/useTerritoryEquityDataV2';
import { TerritoryEquityTable } from '@/components/reporting/TerritoryEquityTable';
import { RegionalEquityTable } from '@/components/reporting/RegionalEquityTable';
import { InboundOutboundChart } from '@/components/reporting/InboundOutboundChart';
import { RegionalEquityChart } from '@/components/reporting/RegionalEquityChart';
import { CityDetailModal } from '@/components/reporting/CityDetailModal';
import { RegionDetailModal } from '@/components/reporting/RegionDetailModal';
import { TerritoryEquityFilters } from '@/components/reporting/TerritoryEquityFilters';
import { TerritoryEquityTreemap } from '@/components/reporting/TerritoryEquityTreemap';
import { TerritoryEquityMap } from '@/components/reporting/TerritoryEquityMap';
import { useEquityAuditExport } from '@/hooks/reporting/useEquityAuditExport';
import { tooltips } from '@/components/reporting/TerritoryEquityTooltips';
import { Info, Download, TrendingUp, Users, AlertTriangle, Award, FileText, Map } from 'lucide-react';
import { SmartTooltip } from '@/components/common/SmartTooltip';
import type { CityEquityData, RegionEquityData, TerritoryEquityFilters as Filters } from '@/types/reporting';

import { useTranslation } from '@/hooks/useTranslation';
export default function TerritoryEquity() {
  const { t } = useTranslation();
  const { profile } = useAuth();
  const [activeTab, setActiveTab] = useState<'city' | 'regional' | 'map'>('city');
  const [selectedCity, setSelectedCity] = useState<CityEquityData | null>(null);
  const [selectedRegion, setSelectedRegion] = useState<RegionEquityData | null>(null);
  const [filters, setFilters] = useState<Filters>({
    startDate: '',
    endDate: '',
    carrier: '',
    product: '',
    region: '',
    direction: undefined,
    equityStatus: [],
  });

  const { 
    cityData, 
    regionData, 
    metrics, 
    loading, 
    error, 
    globalWarningThreshold, 
    globalCriticalThreshold,
    scenarioDescription,
    scenarioInfo: hookScenarioInfo,
    populationWeightedCitizensAffected
  } = useTerritoryEquityData(
    profile?.account_id || undefined,
    filters
  );

  const { generateMarkdownReport, downloadMarkdown } = useEquityAuditExport();

  // Use scenarioInfo from the hook (hookScenarioInfo)
  const scenarioInfo = hookScenarioInfo;

  // Switch to city tab when city filters are applied (regional tab should be hidden)
  React.useEffect(() => {
    if (!scenarioInfo.isGeneralView && activeTab === 'regional') {
      setActiveTab('city');
    }
  }, [scenarioInfo.isGeneralView, activeTab]);

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

  const handleExportRawSamples = async () => {
    if (!profile?.account_id) return;

    try {
      // Build query
      let query = supabase
        .from('one_db')
        .select(`
          id,
          shipment_date,
          origin_city_id,
          destination_city_id,
          carrier_id,
          product_id,
          business_transit_days,
          is_compliant,
          created_at
        `)
        .eq('account_id', profile.account_id);

      // Apply filters
      if (filters.startDate) {
        query = query.gte('shipment_date', filters.startDate);
      }
      if (filters.endDate) {
        query = query.lte('shipment_date', filters.endDate);
      }
      if (filters.carrier) {
        query = query.eq('carrier_id', filters.carrier);
      }
      if (filters.product) {
        query = query.eq('product_id', filters.product);
      }
      if (filters.originCity) {
        query = query.eq('origin_city_id', filters.originCity);
      }
      if (filters.destinationCity) {
        query = query.eq('destination_city_id', filters.destinationCity);
      }

      const { data, error } = await query;

      if (error) throw error;
      if (!data || data.length === 0) {
        alert('No samples found for the selected filters');
        return;
      }

      // Convert to CSV
      const headers = [
        'ID',
        'Shipment Date',
        'Origin City ID',
        'Destination City ID',
        'Carrier ID',
        'Product ID',
        'Business Transit Days',
        'Is Compliant',
        'Created At',
      ];

      const rows = data.map(row => [
        row.id,
        row.shipment_date,
        row.origin_city_id,
        row.destination_city_id,
        row.carrier_id,
        row.product_id,
        row.business_transit_days,
        row.is_compliant ? 'Yes' : 'No',
        row.created_at,
      ]);

      const csv = [headers, ...rows].map(row => row.join(',')).join('\n');
      const blob = new Blob([csv], { type: 'text/csv' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `one-db-samples-${new Date().toISOString().split('T')[0]}.csv`;
      a.click();
      URL.revokeObjectURL(url);
    } catch (err) {
      console.error('Error exporting raw samples:', err);
      alert('Failed to export raw samples');
    }
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
            onClick={handleExportRawSamples}
            className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
            title="Export raw samples from ONE DB (for validation)"
          >
            <Download className="w-4 h-4" />
            Export Raw Data
          </button>
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

      {/* KPIs */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {/* KPI 1: Service Equity Index */}
        {scenarioInfo.isGeneralView && (
        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center justify-between mb-2">
            <h3 className="text-sm font-medium text-gray-600">{t('reporting.service_equity_index')}</h3>
            <SmartTooltip content={tooltips.serviceEquityIndex} />
          </div>
          <div className="text-3xl font-bold text-gray-900">
            {metrics?.serviceEquityIndex.toFixed(1) || '0.0'}
          </div>
          <div className="flex items-center gap-1 mt-1">
            <TrendingUp className="w-4 h-4 text-gray-500" />
            <span className="text-sm text-gray-500">{t('reporting.population_weighted')}</span>
          </div>
        </div>
        )}

        {/* KPI 2: Population-Weighted Compliance */}
        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center justify-between mb-2">
            <h3 className="text-sm font-medium text-gray-600">
              {scenarioInfo.isRouteView ? 'Route Compliance' : t('reporting.population_weighted_compliance')}
            </h3>
            <SmartTooltip content={tooltips.populationWeightedCompliance} />
          </div>
          <div className="text-3xl font-bold text-gray-900">
            {metrics?.populationWeightedCompliance.toFixed(1) || '0.0'}%
          </div>
          <div className="flex items-center gap-1 mt-1">
            <Users className="w-4 h-4 text-gray-500" />
            <span className="text-sm text-gray-500">
              {t('reporting.citizens_count', { count: populationWeightedCitizensAffected?.toLocaleString() || '0' })}
            </span>
          </div>
        </div>

        {/* KPI 3: Underserved Cities */}
        {scenarioInfo.isGeneralView && (
        <div className="bg-white rounded-lg shadow p-6">
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
              {t('reporting.of_cities', { count: metrics?.totalCities || 0 })}
            </span>
          </div>
        </div>
        )}

        {/* KPI 5: Citizens Affected (moved here to be next to Underserved Cities) */}
        {scenarioInfo.isGeneralView && (
        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center justify-between mb-2">
            <h3 className="text-sm font-medium text-gray-600">{t('reporting.citizens_affected')}</h3>
            <SmartTooltip content={tooltips.citizensAffected} />
          </div>
          <div className="text-3xl font-bold text-red-600">
            {metrics?.citizensAffected.toLocaleString() || '0'}
          </div>
          <div className="flex items-center gap-1 mt-1">
            <Users className="w-4 h-4 text-red-500" />
            <span className="text-sm text-gray-500">{t('reporting.in_critical_cities')}</span>
          </div>
        </div>
        )}

        {/* KPI 4: Top 3 Best Served Cities */}
        {!scenarioInfo.isRouteView && (
        <div className="bg-white rounded-lg shadow p-6 col-span-1 md:col-span-2 lg:col-span-1">
          <div className="flex items-center justify-between mb-3">
            <h3 className="text-sm font-medium text-gray-600 flex items-center gap-2">
              <Award className="w-4 h-4 text-green-600" />
              {t('reporting.top_3_best_served_cities')}
            </h3>
            <SmartTooltip content={tooltips.topBestServed} />
          </div>
          <div className="space-y-2">
            <div className="grid grid-cols-7 gap-1 text-xs font-medium text-gray-500 border-b pb-1">
              <div>{t('topology.city')}</div>
              <div className="text-right">{t('reporting.compliant_abbr')}</div>
              <div className="text-right">{t('reporting.std_abbr')}</div>
              <div className="text-right">{t('reporting.jk_std')}</div>
              <div className="text-right">{t('reporting.jk_actual')}</div>
              <div className="text-right">{t('reporting.inbound_abbr')}</div>
              <div className="text-right">{t('reporting.outbound_abbr')}</div>            </div>
            {metrics?.topBestCities.slice(0, 3).map((city, idx) => (
              <div key={idx} className="grid grid-cols-7 gap-1 text-xs">
                <div className="font-medium truncate">{city.cityName}</div>
                <div className="text-right font-semibold text-green-600">
                  {city.actualPercentage.toFixed(1)}%
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
            ))}
            {(!metrics?.topBestCities || metrics.topBestCities.length === 0) && (
              <div className="text-sm text-gray-500 text-center py-2">No data</div>
            )}
          </div>
        </div>
        )}

        {/* KPI 6: Top 3 Worst Served Cities */}
        {!scenarioInfo.isRouteView && (
        <div className="bg-white rounded-lg shadow p-6 col-span-1 md:col-span-2 lg:col-span-1">
          <div className="flex items-center justify-between mb-3">
            <h3 className="text-sm font-medium text-gray-600 flex items-center gap-2">
              <AlertTriangle className="w-4 h-4 text-red-600" />
              {t('reporting.top_3_worst_served_cities')}
            </h3>
            <SmartTooltip content={tooltips.topWorstServed} />
          </div>
          <div className="space-y-2">
            <div className="grid grid-cols-7 gap-1 text-xs font-medium text-gray-500 border-b pb-1">
              <div>{t('topology.city')}</div>
              <div className="text-right">{t('reporting.compliant_abbr')}</div>
              <div className="text-right">{t('reporting.std_abbr')}</div>
              <div className="text-right">{t('reporting.jk_std')}</div>
              <div className="text-right">{t('reporting.jk_actual')}</div>
              <div className="text-right">{t('reporting.inbound_abbr')}</div>
              <div className="text-right">{t('reporting.outbound_abbr')}</div>
            </div>
            {metrics?.topWorstCities.filter(c => c.status === 'critical' || c.status === 'warning').slice(0, 3).map((city, idx) => (
              <div key={idx} className="grid grid-cols-7 gap-1 text-xs">
                <div className="font-medium truncate">{city.cityName}</div>
                <div className="text-right font-semibold text-red-600">
                  {city.actualPercentage.toFixed(1)}%
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
            ))}
            {(!metrics?.topWorstCities || metrics.topWorstCities.filter(c => c.status === 'critical' || c.status === 'warning').length === 0) && (
              <div className="text-sm text-gray-500 text-center py-2">{t('reporting.no_underserved_cities')}</div>
            )}
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
            {scenarioInfo.isGeneralView && (
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
            )}
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
          </div>
        </div>

        <div className="p-6">
          {activeTab === 'city' && (
            <div className="space-y-6">
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
                />
              </div>
            </div>
          )}

          {activeTab === 'regional' && (
            <div className="space-y-6">
              {/* Regional Chart */}
              <div>
                <div className="flex items-center gap-2 mb-4">
                  <h3 className="text-lg font-semibold">{t('reporting.regional_equity_comparison')}</h3>
                  <SmartTooltip content={tooltips.regionalChart} />
                </div>
                <RegionalEquityChart data={regionData} />
              </div>

              {/* Regional Table */}
              <div>
                <div className="flex items-center justify-between mb-4">
                  <div className="flex items-center gap-2">
                    <h3 className="text-lg font-semibold">{t('reporting.regional_equity_details')}</h3>
                    <SmartTooltip content={tooltips.regionalTable} />
                  </div>
                  <button
                    onClick={handleExportRegionalCSV}
                    className="flex items-center gap-2 px-3 py-1.5 text-sm bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors"
                  >
                    <Download className="w-4 h-4" />
                    {t('common.export_csv')}
                  </button>
                </div>
                <RegionalEquityTable 
                  data={regionData} 
                  onRegionClick={setSelectedRegion} 
                  globalWarningThreshold={globalWarningThreshold}
                  globalCriticalThreshold={globalCriticalThreshold}
                  scenarioInfo={hookScenarioInfo}
                  scenarioDescription={scenarioDescription}
                />
              </div>
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
