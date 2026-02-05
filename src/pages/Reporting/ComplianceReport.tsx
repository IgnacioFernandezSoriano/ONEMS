import React, { useState, useMemo } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { useTerritoryEquityDataV2 as useTerritoryEquityData } from '@/hooks/reporting/useTerritoryEquityDataV2';
import { ComplianceAnalysisTable } from '@/components/reporting/ComplianceAnalysisTable';
import { TerritoryEquityFilters } from '@/components/reporting/TerritoryEquityFilters';
import { Shield, AlertTriangle, CheckCircle, XCircle, Info, FileDown } from 'lucide-react';
import { SmartTooltip } from '@/components/common/SmartTooltip';
import { useTranslation } from '@/hooks/useTranslation';
import type { TerritoryEquityFilters as Filters } from '@/types/reporting';

export default function ComplianceReport() {
  const { t } = useTranslation();
  const { profile } = useAuth();
  const [filtersExpanded, setFiltersExpanded] = useState(true);
  const [filters, setFilters] = useState<Filters>({
    startDate: '',
    endDate: '',
    carrier: '',
    product: '',
    region: '',
    direction: undefined,
    equityStatus: [],
    originCity: undefined,
    destinationCity: undefined,
  });

  const { 
    cityData, 
    regionData, 
    metrics, 
    routeData,
    loading, 
    error, 
    globalWarningThreshold, 
    globalCriticalThreshold,
  } = useTerritoryEquityData(
    profile?.account_id || undefined,
    filters
  );

  const handleExportCSV = () => {
    if (routeData.length === 0) return;

    const headers = [
      'Carrier',
      'Product',
      'Origin',
      'Destination',
      'Samples',
      'J+K STD',
      'J+K Actual',
      'STD %',
      'Actual %',
      'Deviation',
      'Status'
    ];
    
    const rows: string[][] = [headers];
    
    routeData.forEach(route => {
      const deviation = route.standardPercentage > 0 
        ? ((route.actualPercentage - route.standardPercentage) / route.standardPercentage * 100).toFixed(1)
        : '0.0';
      
      const status = route.status === 'compliant' ? 'Compliant' : 
                     route.status === 'warning' ? 'Warning' : 'Critical';
      
      rows.push([
        route.carrier || '',
        route.product || '',
        route.origin || '',
        route.destination || '',
        route.samples?.toString() || '0',
        route.standardDays?.toFixed(1) || '',
        route.actualDays?.toFixed(1) || '',
        route.standardPercentage?.toFixed(1) || '',
        route.actualPercentage?.toFixed(1) || '',
        deviation,
        status
      ]);
    });
    
    const csvContent = rows.map(row => 
      row.map(cell => `"${cell}"`).join(',')
    ).join('\n');
    
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `compliance_report_${new Date().toISOString().split('T')[0]}.csv`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-500">Loading compliance data...</div>
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

  // Calculate KPIs from route data
  const totalRoutes = routeData.length;
  const compliantRoutes = routeData.filter(r => r.status === 'compliant').length;
  const warningRoutes = routeData.filter(r => r.status === 'warning').length;
  const criticalRoutes = routeData.filter(r => r.status === 'critical').length;
  
  const totalSamples = routeData.reduce((sum, r) => sum + (r.samples || 0), 0);
  const overallCompliance = totalRoutes > 0 ? (compliantRoutes / totalRoutes) * 100 : 0;

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Regulatory Compliance Report</h1>
          <p className="text-gray-600 mt-1">Compliance analysis by carrier, product, and route</p>
        </div>
        <div className="flex gap-3">
          <button
            disabled
            className="flex items-center gap-2 px-4 py-2 bg-gray-400 text-white rounded-lg cursor-not-allowed opacity-60"
          >
            <FileDown className="w-5 h-5" />
            <span className="text-sm font-medium">Export Audit Report</span>
          </button>
          <SmartTooltip content="Regulatory Compliance Report: Analyzes compliance rates by Carrier, Product, and Route to identify which carriers, services, or routes are meeting or failing regulatory standards." />
        </div>
      </div>

      <TerritoryEquityFilters
        filters={filters}
        onChange={setFilters}
      />

      <div className="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-5 gap-3">
        <div className="bg-white rounded-lg shadow p-4">
          <div className="flex items-center justify-between mb-2">
            <div className="flex items-center gap-2">
              <Shield className={`w-5 h-5 ${
                compliantRoutes === totalRoutes ? 'text-green-600' : 
                compliantRoutes > criticalRoutes ? 'text-amber-600' : 'text-red-600'
              }`} />
              <span className="text-sm text-gray-600">Overall Compliance</span>
            </div>
            <SmartTooltip content="Percentage of routes meeting their configured compliance standards." />
          </div>
          <div className="text-2xl font-bold">{overallCompliance.toFixed(1)}%</div>
          <div className="text-xs text-gray-500 mt-1">{compliantRoutes}/{totalRoutes} routes</div>
        </div>

        <div className="bg-white rounded-lg shadow p-4">
          <div className="flex items-center justify-between mb-2">
            <div className="flex items-center gap-2">
              <CheckCircle className="w-5 h-5 text-green-600" />
              <span className="text-sm text-gray-600">Compliant Routes</span>
            </div>
            <SmartTooltip content="Number of routes meeting or exceeding their configured compliance standard." />
          </div>
          <div className="text-2xl font-bold text-green-600">{compliantRoutes}</div>
          <div className="text-xs text-gray-500 mt-1">Meeting standard</div>
        </div>

        <div className="bg-white rounded-lg shadow p-4">
          <div className="flex items-center justify-between mb-2">
            <div className="flex items-center gap-2">
              <AlertTriangle className="w-5 h-5 text-amber-600" />
              <span className="text-sm text-gray-600">Warning Routes</span>
            </div>
            <SmartTooltip content="Routes with compliance below standard but above critical threshold." />
          </div>
          <div className="text-2xl font-bold text-amber-600">{warningRoutes}</div>
          <div className="text-xs text-gray-500 mt-1">No penalty</div>
        </div>

        <div className="bg-white rounded-lg shadow p-4">
          <div className="flex items-center justify-between mb-2">
            <div className="flex items-center gap-2">
              <XCircle className="w-5 h-5 text-red-600" />
              <span className="text-sm text-gray-600">Critical Routes</span>
            </div>
            <SmartTooltip content="Routes with compliance below critical threshold requiring immediate action." />
          </div>
          <div className="text-2xl font-bold text-red-600">{criticalRoutes}</div>
          <div className="text-xs text-gray-500 mt-1">With penalty</div>
        </div>

        <div className="bg-white rounded-lg shadow p-4">
          <div className="flex items-center justify-between mb-2">
            <div className="flex items-center gap-2">
              <Info className="w-5 h-5 text-blue-600" />
              <span className="text-sm text-gray-600">Total Routes</span>
            </div>
            <SmartTooltip content="Total number of unique routes with shipment data." />
          </div>
          <div className="text-2xl font-bold text-blue-600">{totalRoutes}</div>
          <div className="text-xs text-gray-500 mt-1">Across all carriers</div>
        </div>
      </div>

      <div className="bg-white rounded-lg shadow p-6">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-semibold text-gray-900">Compliance Analysis</h2>
          <div className="flex items-center gap-3">
            <button
              onClick={handleExportCSV}
              className="flex items-center gap-2 px-3 py-1.5 text-sm bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors"
            >
              <FileDown className="w-4 h-4" />
              Export CSV
            </button>
            <SmartTooltip content="Detailed compliance table showing all routes with their performance metrics and status." />
          </div>
        </div>
        <ComplianceAnalysisTable 
          data={routeData} 
          warningThreshold={globalWarningThreshold}
          criticalThreshold={globalCriticalThreshold}
        />
      </div>
    </div>
  );
}
