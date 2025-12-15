import { useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { useTerritoryEquityData } from '@/hooks/reporting/useTerritoryEquityData';
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
import type { CityEquityData, RegionEquityData, TerritoryEquityFilters as Filters } from '@/types/reporting';

export default function TerritoryEquity() {
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

  const { cityData, regionData, metrics, loading, error } = useTerritoryEquityData(
    profile?.account_id || undefined,
    filters
  );

  const { generateMarkdownReport, downloadMarkdown } = useEquityAuditExport();

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
      'J+K Std',
      'J+K Actual',
      'Deviation',
      'Status',
    ];

    const rows: string[][] = [];
    cityData.forEach((city) => {
      // Inbound row
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
        city.inboundStandardDays.toFixed(1),
        city.inboundActualDays.toFixed(1),
        city.inboundDeviation.toFixed(1),
        city.inboundDeviation >= 0 ? 'compliant' : (city.inboundPercentage < 80 ? 'critical' : 'warning'),
      ]);
      
      // Outbound row
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
        city.outboundStandardDays.toFixed(1),
        city.outboundActualDays.toFixed(1),
        city.outboundDeviation.toFixed(1),
        city.outboundDeviation >= 0 ? 'compliant' : (city.outboundPercentage < 80 ? 'critical' : 'warning'),
      ]);
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
      'J+K Std',
      'J+K Actual',
      'Deviation',
      'Status',
      'Underserved Cities',
    ];

    const rows: string[][] = [];
    regionData.forEach((region) => {
      // Inbound row
      rows.push([
        region.regionName,
        'Inbound',
        region.totalCities.toString(),
        region.totalPopulation?.toString() || '',
        region.inboundStandardPercentage.toFixed(1),
        region.inboundPercentage.toFixed(1),
        region.inboundStandardDays.toFixed(1),
        region.inboundActualDays.toFixed(1),
        region.inboundDeviation.toFixed(1),
        region.inboundDeviation >= 0 ? 'compliant' : (region.inboundPercentage < 80 ? 'critical' : 'warning'),
        region.underservedCitiesCount.toString(),
      ]);
      
      // Outbound row
      rows.push([
        region.regionName,
        'Outbound',
        region.totalCities.toString(),
        region.totalPopulation?.toString() || '',
        region.outboundStandardPercentage.toFixed(1),
        region.outboundPercentage.toFixed(1),
        region.outboundStandardDays.toFixed(1),
        region.outboundActualDays.toFixed(1),
        region.outboundDeviation.toFixed(1),
        region.outboundDeviation >= 0 ? 'compliant' : (region.outboundPercentage < 80 ? 'critical' : 'warning'),
        region.underservedCitiesCount.toString(),
      ]);
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

  const Tooltip = ({ content }: { content: string | React.ReactNode }) => (
    <div className="group relative inline-block">
      <Info className="w-4 h-4 text-gray-400 cursor-help" />
      <div className="invisible group-hover:visible absolute z-10 w-80 p-3 mt-1 text-sm text-white bg-gray-900 rounded-lg shadow-lg -left-28">
        {content}
      </div>
    </div>
  );

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
          <h1 className="text-3xl font-bold text-gray-900">Territory Equity Report</h1>
          <p className="text-gray-600 mt-1">
            Analyze service equity across cities and regions
          </p>
        </div>
        <button
          onClick={handleExportAuditReport}
          className="flex items-center gap-2 px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 transition-colors"
        >
          <FileText className="w-4 h-4" />
          Export Audit Report
        </button>
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
        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center justify-between mb-2">
            <h3 className="text-sm font-medium text-gray-600">Service Equity Index</h3>
            <Tooltip content={tooltips.serviceEquityIndex} />
          </div>
          <div className="text-3xl font-bold text-gray-900">
            {metrics?.serviceEquityIndex.toFixed(1) || '0.0'}
          </div>
          <div className="flex items-center gap-1 mt-1">
            <TrendingUp className="w-4 h-4 text-gray-500" />
            <span className="text-sm text-gray-500">Population-weighted</span>
          </div>
        </div>

        {/* KPI 2: Population-Weighted Compliance */}
        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center justify-between mb-2">
            <h3 className="text-sm font-medium text-gray-600">Population-Weighted Compliance</h3>
            <Tooltip content={tooltips.populationWeightedCompliance} />
          </div>
          <div className="text-3xl font-bold text-gray-900">
            {metrics?.populationWeightedCompliance.toFixed(1) || '0.0'}%
          </div>
          <div className="flex items-center gap-1 mt-1">
            <Users className="w-4 h-4 text-gray-500" />
            <span className="text-sm text-gray-500">
              {metrics?.totalPopulation.toLocaleString() || '0'} citizens
            </span>
          </div>
        </div>

        {/* KPI 3: Underserved Cities */}
        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center justify-between mb-2">
            <h3 className="text-sm font-medium text-gray-600">Underserved Cities</h3>
            <Tooltip content={tooltips.underservedCities} />
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
        </div>

        {/* KPI 5: Citizens Affected (moved here to be next to Underserved Cities) */}
        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center justify-between mb-2">
            <h3 className="text-sm font-medium text-gray-600">Citizens Affected</h3>
            <Tooltip content={tooltips.citizensAffected} />
          </div>
          <div className="text-3xl font-bold text-red-600">
            {metrics?.citizensAffected.toLocaleString() || '0'}
          </div>
          <div className="flex items-center gap-1 mt-1">
            <Users className="w-4 h-4 text-red-500" />
            <span className="text-sm text-gray-500">in critical cities</span>
          </div>
        </div>

        {/* KPI 4: Top 3 Best Served Cities */}
        <div className="bg-white rounded-lg shadow p-6 col-span-1 md:col-span-2 lg:col-span-1">
          <div className="flex items-center justify-between mb-3">
            <h3 className="text-sm font-medium text-gray-600 flex items-center gap-2">
              <Award className="w-4 h-4 text-green-600" />
              Top 3 Best Served Cities
            </h3>
            <Tooltip content={tooltips.topBestServed} />
          </div>
          <div className="space-y-2">
            <div className="grid grid-cols-7 gap-1 text-xs font-medium text-gray-500 border-b pb-1">
              <div>City</div>
              <div className="text-right">Compl.</div>
              <div className="text-right">Std.</div>
              <div className="text-right">J+K Std</div>
              <div className="text-right">J+K Actual</div>
              <div className="text-right">Inb.</div>
              <div className="text-right">Outb.</div>
            </div>
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

        {/* KPI 6: Top 3 Worst Served Cities */}
        <div className="bg-white rounded-lg shadow p-6 col-span-1 md:col-span-2 lg:col-span-1">
          <div className="flex items-center justify-between mb-3">
            <h3 className="text-sm font-medium text-gray-600 flex items-center gap-2">
              <AlertTriangle className="w-4 h-4 text-red-600" />
              Top 3 Worst Served Cities
            </h3>
            <Tooltip content={tooltips.topWorstServed} />
          </div>
          <div className="space-y-2">
            <div className="grid grid-cols-7 gap-1 text-xs font-medium text-gray-500 border-b pb-1">
              <div>City</div>
              <div className="text-right">Compl.</div>
              <div className="text-right">Std.</div>
              <div className="text-right">J+K Std</div>
              <div className="text-right">J+K Actual</div>
              <div className="text-right">Inb.</div>
              <div className="text-right">Outb.</div>
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
              <div className="text-sm text-gray-500 text-center py-2">No underserved cities</div>
            )}
          </div>
        </div>
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
              City Analysis
            </button>
            <button
              onClick={() => setActiveTab('regional')}
              className={`px-6 py-3 font-medium transition-colors ${
                activeTab === 'regional'
                  ? 'border-b-2 border-blue-600 text-blue-600'
                  : 'text-gray-600 hover:text-gray-900'
              }`}
            >
              Regional Analysis
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
              Geographic View
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
                    Inbound vs Outbound Comparison (Top 10 by Direction Gap)
                  </h3>
                  <Tooltip content={tooltips.inboundOutboundChart} />
                </div>
                <InboundOutboundChart data={cityData} />
              </div>

              {/* Treemap Visualization */}
              <div>
                <div className="flex items-center gap-2 mb-4">
                  <h3 className="text-lg font-semibold">City Service Equity Treemap</h3>
                  <Tooltip content={tooltips.treemap} />
                </div>
                <TerritoryEquityTreemap data={cityData} />
              </div>

              {/* City Table */}
              <div>
                <div className="flex items-center justify-between mb-4">
                  <div className="flex items-center gap-2">
                    <h3 className="text-lg font-semibold">City Equity Details</h3>
                    <Tooltip content={tooltips.cityTable} />
                  </div>
                  <button
                    onClick={handleExportCSV}
                    className="flex items-center gap-2 px-3 py-1.5 text-sm bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors"
                  >
                    <Download className="w-4 h-4" />
                    Export CSV
                  </button>
                </div>
                <TerritoryEquityTable data={cityData} onCityClick={setSelectedCity} />
              </div>
            </div>
          )}

          {activeTab === 'regional' && (
            <div className="space-y-6">
              {/* Regional Chart */}
              <div>
                <div className="flex items-center gap-2 mb-4">
                  <h3 className="text-lg font-semibold">Regional Equity Comparison</h3>
                  <Tooltip content={tooltips.regionalChart} />
                </div>
                <RegionalEquityChart data={regionData} />
              </div>

              {/* Regional Table */}
              <div>
                <div className="flex items-center justify-between mb-4">
                  <div className="flex items-center gap-2">
                    <h3 className="text-lg font-semibold">Regional Equity Details</h3>
                    <Tooltip content={tooltips.regionalTable} />
                  </div>
                  <button
                    onClick={handleExportRegionalCSV}
                    className="flex items-center gap-2 px-3 py-1.5 text-sm bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors"
                  >
                    <Download className="w-4 h-4" />
                    Export CSV
                  </button>
                </div>
                <RegionalEquityTable data={regionData} onRegionClick={setSelectedRegion} />
              </div>
            </div>
          )}

          {activeTab === 'map' && (
            <div className="space-y-6">
              <div>
                <div className="mb-4">
                  <h3 className="text-lg font-semibold mb-2">Geographic Distribution</h3>
                  <p className="text-sm text-gray-600">
                    Interactive map showing service equity across cities. Circle size represents population, color indicates compliance status.
                    Click on any city marker to view detailed information.
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
