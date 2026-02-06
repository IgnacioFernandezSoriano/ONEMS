import { useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { useTerritoryEquityDataV2 as useTerritoryEquityData } from '@/hooks/reporting/useTerritoryEquityDataV2';
import { TerritoryEquityFilters } from '@/components/reporting/TerritoryEquityFilters';
import { ComplianceHierarchicalTable } from '@/components/reporting/ComplianceHierarchicalTable';
import { Shield, AlertTriangle, CheckCircle, XCircle, Info, FileDown } from 'lucide-react';
import { SmartTooltip } from '@/components/common/SmartTooltip';
import { useTranslation } from '@/hooks/useTranslation';
import type { TerritoryEquityFilters as Filters } from '@/types/reporting';

export default function ComplianceReport() {
  const { t } = useTranslation();
  const { profile } = useAuth();
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
    routeData,
    metrics, 
    loading, 
    error, 
    globalWarningThreshold, 
    globalCriticalThreshold,
  } = useTerritoryEquityData(
    profile?.account_id || undefined,
    filters
  );

  // Calculate KPIs from routeData
  const totalRoutes = routeData.length;
  const compliantRoutes = routeData.filter(r => r.status === 'compliant').length;
  const warningRoutes = routeData.filter(r => r.status === 'warning').length;
  const criticalRoutes = routeData.filter(r => r.status === 'critical').length;
  const totalSamples = routeData.reduce((sum, r) => sum + (r.totalShipments || 0), 0);
  const overallCompliance = totalRoutes > 0 ? (compliantRoutes / totalRoutes) * 100 : 0;

  const handleExportAuditReport = () => {
    alert('Export Audit Report - Coming soon');
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-lg text-gray-600">Loading compliance data...</div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-lg text-red-600">Error loading data</div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900 flex items-center gap-2">
            <Shield className="w-6 h-6 text-blue-600" />
            {t('reporting.regulatory_compliance_report')}
          </h1>
          <p className="text-gray-600 mt-1">
            {t('reporting.compliance_analysis_description')}
          </p>
        </div>
        <button
          onClick={handleExportAuditReport}
          disabled
          className="flex items-center gap-2 px-4 py-2 bg-gray-300 text-gray-500 rounded-lg cursor-not-allowed"
          title="Coming soon"
        >
          <FileDown className="w-4 h-4" />
          {t('reporting.export_audit_report')}
        </button>
      </div>

      {/* Filters */}
      <div className="bg-white rounded-lg shadow">
        <TerritoryEquityFilters 
          filters={filters}
          onChange={setFilters}
        />
      </div>

      {/* KPI Cards */}
      <div className="grid grid-cols-1 md:grid-cols-5 gap-4">
        {/* Overall Compliance */}
        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center justify-between mb-2">
            <h3 className="text-sm font-medium text-gray-600 flex items-center gap-1">
              Overall Compliance
              <SmartTooltip content="Percentage of routes meeting compliance standards" />
            </h3>
          </div>
          <div className="flex items-center gap-2">
            <Shield className="w-5 h-5 text-blue-600" />
            <span className="text-3xl font-bold text-gray-900">
              {overallCompliance.toFixed(1)}%
            </span>
          </div>
          <p className="text-sm text-gray-500 mt-1">{compliantRoutes}/{totalRoutes} routes</p>
        </div>

        {/* Compliant Routes */}
        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center justify-between mb-2">
            <h3 className="text-sm font-medium text-gray-600 flex items-center gap-1">
              <CheckCircle className="w-4 h-4 text-green-600" />
              Compliant Routes
              <SmartTooltip content="Routes meeting standard" />
            </h3>
          </div>
          <div className="text-3xl font-bold text-green-600">{compliantRoutes}</div>
          <p className="text-sm text-gray-500 mt-1">Meeting standard</p>
        </div>

        {/* Warning Routes */}
        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center justify-between mb-2">
            <h3 className="text-sm font-medium text-gray-600 flex items-center gap-1">
              <AlertTriangle className="w-4 h-4 text-amber-600" />
              Warning Routes
              <SmartTooltip content="Routes with minor issues" />
            </h3>
          </div>
          <div className="text-3xl font-bold text-amber-600">{warningRoutes}</div>
          <p className="text-sm text-gray-500 mt-1">No penalty</p>
        </div>

        {/* Critical Routes */}
        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center justify-between mb-2">
            <h3 className="text-sm font-medium text-gray-600 flex items-center gap-1">
              <XCircle className="w-4 h-4 text-red-600" />
              Critical Routes
              <SmartTooltip content="Routes with penalties" />
            </h3>
          </div>
          <div className="text-3xl font-bold text-red-600">{criticalRoutes}</div>
          <p className="text-sm text-gray-500 mt-1">With penalty</p>
        </div>

        {/* Total Routes */}
        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center justify-between mb-2">
            <h3 className="text-sm font-medium text-gray-600 flex items-center gap-1">
              <Info className="w-4 h-4 text-blue-600" />
              Total Routes
              <SmartTooltip content="All routes analyzed" />
            </h3>
          </div>
          <div className="text-3xl font-bold text-blue-600">{totalRoutes}</div>
          <p className="text-sm text-gray-500 mt-1">Across all carriers</p>
        </div>
      </div>

      {/* Compliance Analysis Table */}
      <div className="bg-white rounded-lg shadow">
        <div className="p-6 border-b border-gray-200">
          <div className="flex items-center justify-between">
            <h2 className="text-lg font-semibold">Compliance Analysis</h2>
            <SmartTooltip content="Hierarchical view: Carrier → Product → Route" />
          </div>
        </div>
        <div className="p-6">
          <ComplianceHierarchicalTable 
            data={routeData}
            warningThreshold={globalWarningThreshold}
            criticalThreshold={globalCriticalThreshold}
          />
        </div>
      </div>
    </div>
  );
}
