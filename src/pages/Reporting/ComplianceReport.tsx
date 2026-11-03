import { useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { useTerritoryEquityDataV2 as useTerritoryEquityData } from '@/hooks/reporting/useTerritoryEquityDataV2';
import { TerritoryEquityFilters } from '@/components/reporting/TerritoryEquityFilters';
import { ComplianceHierarchicalTable } from '@/components/reporting/ComplianceHierarchicalTable';
import { Shield, AlertTriangle, CheckCircle, XCircle, Info, FileDown } from 'lucide-react';
import { SmartTooltip } from '@/components/common/SmartTooltip';
import { useTranslation } from '@/hooks/useTranslation';
import { TimeUnitToggle } from '@/components/common/TimeUnitToggle';
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
    alert(t('hc.compliance_report.export_coming_soon'));
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-lg text-gray-600">{t('hc.compliance_report.loading')}</div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-lg text-red-600">{t('hc.compliance_report.error_loading')}</div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <div className="flex flex-wrap items-center gap-3">
            <h1 className="text-2xl font-bold text-gray-900 flex items-center gap-2">
              <Shield className="w-6 h-6 text-blue-600" />
              {t('reporting.regulatory_compliance_report')}
            </h1>
            <TimeUnitToggle />
          </div>
          <p className="text-gray-600 mt-1">
            {t('reporting.compliance_analysis_description')}
          </p>
        </div>
        <button
          onClick={handleExportAuditReport}
          disabled
          className="flex items-center gap-2 px-4 py-2 bg-gray-300 text-gray-500 rounded-lg cursor-not-allowed"
          title={t('hc.compliance_report.coming_soon')}
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
              {t('hc.compliance_report.overall_compliance')}
              <SmartTooltip content={t('hc.compliance_report.overall_compliance_tip')} />
            </h3>
          </div>
          <div className="flex items-center gap-2">
            <Shield className="w-5 h-5 text-blue-600" />
            <span className="text-3xl font-bold text-gray-900">
              {overallCompliance.toFixed(1)}%
            </span>
          </div>
          <p className="text-sm text-gray-500 mt-1">{t('hc.compliance_report.routes_ratio', { compliant: compliantRoutes, total: totalRoutes })}</p>
        </div>

        {/* Compliant Routes */}
        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center justify-between mb-2">
            <h3 className="text-sm font-medium text-gray-600 flex items-center gap-1">
              <CheckCircle className="w-4 h-4 text-green-600" />
              {t('hc.compliance_report.compliant_routes')}
              <SmartTooltip content={t('hc.compliance_report.compliant_routes_tip')} />
            </h3>
          </div>
          <div className="text-3xl font-bold text-green-600">{compliantRoutes}</div>
          <p className="text-sm text-gray-500 mt-1">{t('hc.compliance_report.meeting_standard')}</p>
        </div>

        {/* Warning Routes */}
        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center justify-between mb-2">
            <h3 className="text-sm font-medium text-gray-600 flex items-center gap-1">
              <AlertTriangle className="w-4 h-4 text-amber-600" />
              {t('hc.compliance_report.warning_routes')}
              <SmartTooltip content={t('hc.compliance_report.warning_routes_tip')} />
            </h3>
          </div>
          <div className="text-3xl font-bold text-amber-600">{warningRoutes}</div>
          <p className="text-sm text-gray-500 mt-1">{t('hc.compliance_report.no_penalty')}</p>
        </div>

        {/* Critical Routes */}
        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center justify-between mb-2">
            <h3 className="text-sm font-medium text-gray-600 flex items-center gap-1">
              <XCircle className="w-4 h-4 text-red-600" />
              {t('hc.compliance_report.critical_routes')}
              <SmartTooltip content={t('hc.compliance_report.critical_routes_tip')} />
            </h3>
          </div>
          <div className="text-3xl font-bold text-red-600">{criticalRoutes}</div>
          <p className="text-sm text-gray-500 mt-1">{t('hc.compliance_report.with_penalty')}</p>
        </div>

        {/* Total Routes */}
        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center justify-between mb-2">
            <h3 className="text-sm font-medium text-gray-600 flex items-center gap-1">
              <Info className="w-4 h-4 text-blue-600" />
              {t('hc.compliance_report.total_routes')}
              <SmartTooltip content={t('hc.compliance_report.total_routes_tip')} />
            </h3>
          </div>
          <div className="text-3xl font-bold text-blue-600">{totalRoutes}</div>
          <p className="text-sm text-gray-500 mt-1">{t('hc.compliance_report.across_carriers')}</p>
        </div>
      </div>

      {/* Compliance Analysis Table */}
      <div className="bg-white rounded-lg shadow">
        <div className="p-6 border-b border-gray-200">
          <div className="flex items-center justify-between">
            <h2 className="text-lg font-semibold">{t('hc.compliance_report.compliance_analysis')}</h2>
            <SmartTooltip content={t('hc.compliance_report.hierarchy_tip')} />
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
