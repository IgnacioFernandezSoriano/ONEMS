import { useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { useTerritoryEquityData } from '@/hooks/reporting/useTerritoryEquityData';
import { TerritoryEquityTable } from '@/components/reporting/TerritoryEquityTable';
import { RegionalEquityTable } from '@/components/reporting/RegionalEquityTable';
import { InboundOutboundChart } from '@/components/reporting/InboundOutboundChart';
import { RegionalEquityChart } from '@/components/reporting/RegionalEquityChart';
import { CityDetailModal } from '@/components/reporting/CityDetailModal';
import { TerritoryEquityFilters } from '@/components/reporting/TerritoryEquityFilters';
import { TerritoryEquityTreemap } from '@/components/reporting/TerritoryEquityTreemap';
import { useEquityAuditExport } from '@/hooks/reporting/useEquityAuditExport';
import { Info, Download, TrendingUp, Users, AlertTriangle, Award, FileText } from 'lucide-react';
import type { CityEquityData, TerritoryEquityFilters as Filters } from '@/types/reporting';

export default function TerritoryEquity() {
  const { profile } = useAuth();
  const [activeTab, setActiveTab] = useState<'city' | 'regional'>('city');
  const [selectedCity, setSelectedCity] = useState<CityEquityData | null>(null);
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
      'Region',
      'Classification',
      'Population',
      'Total Shipments',
      'Compliant',
      'Standard %',
      'Actual %',
      'Deviation',
      'Status',
      'Inbound %',
      'Outbound %',
      'Direction Gap',
    ];

    const rows = cityData.map((city) => [
      city.cityName,
      city.regionName || '',
      city.classification || '',
      city.population || '',
      city.totalShipments,
      city.compliantShipments,
      city.standardPercentage.toFixed(1),
      city.actualPercentage.toFixed(1),
      city.deviation.toFixed(1),
      city.status,
      city.inboundPercentage.toFixed(1),
      city.outboundPercentage.toFixed(1),
      city.directionGap.toFixed(1),
    ]);

    const csv = [headers, ...rows].map((row) => row.join(',')).join('\n');
    const blob = new Blob([csv], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `territory-equity-report-${new Date().toISOString().split('T')[0]}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  };

  const Tooltip = ({ content }: { content: string }) => (
    <div className="group relative inline-block">
      <Info className="w-4 h-4 text-gray-400 cursor-help" />
      <div className="invisible group-hover:visible absolute z-10 w-64 p-2 mt-1 text-sm text-white bg-gray-900 rounded-lg shadow-lg -left-28">
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
        <div className="flex gap-2">
          <button
            onClick={handleExportAuditReport}
            className="flex items-center gap-2 px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 transition-colors"
          >
            <FileText className="w-4 h-4" />
            Export Audit Report
          </button>
          <button
            onClick={handleExportCSV}
            className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
          >
            <Download className="w-4 h-4" />
            Export CSV
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
        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center justify-between mb-2">
            <h3 className="text-sm font-medium text-gray-600">Service Equity Index</h3>
            <Tooltip content="Measures consistency of service quality across all cities, weighted by population. 100 = perfect equity, 0 = maximum disparity." />
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
            <Tooltip content="Percentage of the population receiving on-time service. This metric reflects the actual impact on citizens." />
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
            <Tooltip content="Number of cities with compliance below critical threshold." />
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

        {/* KPI 4: Top 3 Best Served Cities */}
        <div className="bg-white rounded-lg shadow p-6 col-span-1 md:col-span-2 lg:col-span-1">
          <div className="flex items-center justify-between mb-3">
            <h3 className="text-sm font-medium text-gray-600 flex items-center gap-2">
              <Award className="w-4 h-4 text-green-600" />
              Top 3 Best Served Cities
            </h3>
            <Tooltip content="Three cities with highest positive deviation from standard." />
          </div>
          <div className="space-y-2">
            <div className="grid grid-cols-3 gap-2 text-xs font-medium text-gray-500 border-b pb-1">
              <div className="text-right">Compliance</div>
              <div className="text-right">Deviation</div>
              <div>City</div>
            </div>
            {metrics?.topBestCities.slice(0, 3).map((city, idx) => (
              <div key={idx} className="grid grid-cols-3 gap-2 text-sm">
                <div className="text-right font-semibold text-green-600">
                  {city.actualPercentage.toFixed(1)}%
                </div>
                <div className="text-right text-green-600">
                  +{city.deviation.toFixed(1)}%
                </div>
                <div className="font-medium truncate">{city.cityName}</div>
              </div>
            ))}
            {(!metrics?.topBestCities || metrics.topBestCities.length === 0) && (
              <div className="text-sm text-gray-500 text-center py-2">No data</div>
            )}
          </div>
        </div>

        {/* KPI 5: Citizens Affected */}
        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center justify-between mb-2">
            <h3 className="text-sm font-medium text-gray-600">Citizens Affected</h3>
            <Tooltip content="Total population living in underserved cities (critical status)." />
          </div>
          <div className="text-3xl font-bold text-red-600">
            {metrics?.citizensAffected.toLocaleString() || '0'}
          </div>
          <div className="flex items-center gap-1 mt-1">
            <Users className="w-4 h-4 text-red-500" />
            <span className="text-sm text-gray-500">in critical cities</span>
          </div>
        </div>

        {/* KPI 6: Top 3 Worst Served Cities */}
        <div className="bg-white rounded-lg shadow p-6 col-span-1 md:col-span-2 lg:col-span-1">
          <div className="flex items-center justify-between mb-3">
            <h3 className="text-sm font-medium text-gray-600 flex items-center gap-2">
              <AlertTriangle className="w-4 h-4 text-red-600" />
              Top 3 Worst Served Cities
            </h3>
            <Tooltip content="Three cities with lowest (most negative) deviation from standard." />
          </div>
          <div className="space-y-2">
            <div className="grid grid-cols-3 gap-2 text-xs font-medium text-gray-500 border-b pb-1">
              <div className="text-right">Compliance</div>
              <div className="text-right">Deviation</div>
              <div>City</div>
            </div>
            {metrics?.topWorstCities.slice(0, 3).map((city, idx) => (
              <div key={idx} className="grid grid-cols-3 gap-2 text-sm">
                <div className="text-right font-semibold text-red-600">
                  {city.actualPercentage.toFixed(1)}%
                </div>
                <div className="text-right text-red-600">
                  {city.deviation.toFixed(1)}%
                </div>
                <div className="font-medium truncate">{city.cityName}</div>
              </div>
            ))}
            {(!metrics?.topWorstCities || metrics.topWorstCities.length === 0) && (
              <div className="text-sm text-gray-500 text-center py-2">No data</div>
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
          </div>
        </div>

        <div className="p-6">
          {activeTab === 'city' && (
            <div className="space-y-6">
              {/* Inbound vs Outbound Chart */}
              <div>
                <h3 className="text-lg font-semibold mb-4">
                  Inbound vs Outbound Comparison (Top 10 by Direction Gap)
                </h3>
                <InboundOutboundChart data={cityData} />
              </div>

              {/* Treemap Visualization */}
              <div>
                <TerritoryEquityTreemap data={cityData} />
              </div>

              {/* City Table */}
              <div>
                <h3 className="text-lg font-semibold mb-4">City Equity Details</h3>
                <TerritoryEquityTable data={cityData} onCityClick={setSelectedCity} />
              </div>
            </div>
          )}

          {activeTab === 'regional' && (
            <div className="space-y-6">
              {/* Regional Chart */}
              <div>
                <h3 className="text-lg font-semibold mb-4">Regional Equity Comparison</h3>
                <RegionalEquityChart data={regionData} />
              </div>

              {/* Regional Table */}
              <div>
                <h3 className="text-lg font-semibold mb-4">Regional Equity Details</h3>
                <RegionalEquityTable data={regionData} />
              </div>
            </div>
          )}
        </div>
      </div>

      {/* City Detail Modal */}
      {selectedCity && (
        <CityDetailModal city={selectedCity} onClose={() => setSelectedCity(null)} />
      )}
    </div>
  );
}
