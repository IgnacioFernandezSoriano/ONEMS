import React from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { useReportingFilters } from '@/contexts/ReportingFiltersContext';
import { useComplianceData } from '@/hooks/reporting/useComplianceData';
import { KPICard } from '@/components/reporting/KPICard';
import { ReportFilters } from '@/components/reporting/ReportFilters';
import { ComplianceTable } from '@/components/reporting/ComplianceTable';
import { Shield, AlertTriangle, CheckCircle, XCircle, Info, FileDown } from 'lucide-react';
import { SmartTooltip } from '@/components/common/SmartTooltip';
import { generateComplianceAuditReport } from '@/hooks/reporting/useComplianceAuditExport';
import { useState } from 'react';
import { useTranslation } from '@/hooks/useTranslation';

export default function ComplianceReport() {
  const { t } = useTranslation();
  const { profile } = useAuth();
  const accountId = profile?.account_id || undefined;
  const { filters, setFilters, resetFilters } = useReportingFilters();
  const [exporting, setExporting] = useState(false);

  const handleExportPDF = async () => {
    if (!accountId) return;
    
    try {
      setExporting(true);
      const markdown = await generateComplianceAuditReport(accountId, {
        carrier: filters.carrier,
        product: filters.product,
        originCity: filters.originCity,
        destinationCity: filters.destinationCity
      });
      
      // Create blob and download
      const blob = new Blob([markdown], { type: 'text/markdown' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `compliance_audit_report_${new Date().toISOString().split('T')[0]}.md`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    } catch (error) {
      console.error('Export failed:', error);
      alert('Failed to generate report');
    } finally {
      setExporting(false);
    }
  };

  const handleExportCSV = () => {
    // Build CSV content
    const headers = [
      'Level',
      'Carrier',
      'Product',
      'Route',
      'Total Shipments',
      'Compliant',
      'Standard (days)',
      'Actual (days)',
      'Standard %',
      'Actual %',
      'Deviation',
      'Status'
    ];
    
    const rows: string[][] = [headers];
    
    // Add data rows
    data.forEach(carrier => {
      // Carrier row
      rows.push([
        'Carrier',
        carrier.carrier,
        '',
        '',
        carrier.totalShipments.toString(),
        carrier.compliantShipments.toString(),
        carrier.standardDays?.toFixed(1) || '',
        carrier.avgBusinessDays?.toFixed(1) || '',
        carrier.standardPercentage?.toFixed(1) || '',
        carrier.compliancePercentage?.toFixed(1) || '',
        carrier.standardPercentage > 0 ? (carrier.compliancePercentage - carrier.standardPercentage).toFixed(1) : '',
        ''
      ]);
      
      // Product rows
      carrier.products.forEach(product => {
        rows.push([
          'Product',
          carrier.carrier,
          product.product,
          '',
          product.totalShipments.toString(),
          product.compliantShipments.toString(),
          product.standardDays?.toFixed(1) || '',
          product.avgBusinessDays?.toFixed(1) || '',
          product.standardPercentage?.toFixed(1) || '',
          product.compliancePercentage?.toFixed(1) || '',
          product.standardPercentage > 0 ? (product.compliancePercentage - product.standardPercentage).toFixed(1) : '',
          ''
        ]);
        
        // Route rows
        product.routes.forEach(route => {
          rows.push([
            'Route',
            carrier.carrier,
            product.product,
            route.route,
            route.totalShipments.toString(),
            route.compliantShipments.toString(),
            route.standardDays?.toFixed(1) || '',
            route.avgBusinessDays?.toFixed(1) || '',
            route.standardPercentage?.toFixed(1) || '',
            route.compliancePercentage?.toFixed(1) || '',
            route.standardPercentage > 0 ? (route.compliancePercentage - route.standardPercentage).toFixed(1) : '',
            route.complianceStatus === 'compliant' ? 'Compliant' : route.complianceStatus === 'warning' ? 'Warning' : 'Critical'
          ]);
        });
      });
    });
    
    // Convert to CSV string
    const csvContent = rows.map(row => 
      row.map(cell => `"${cell}"`).join(',')
    ).join('\n');
    
    // Download
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
  // DEBUG: Log filters before passing to hook
  console.log("[ComplianceReport] Filters before hook:", {
    startDate: filters.startDate,
    endDate: filters.endDate,
    originCity: filters.originCity,
    destinationCity: filters.destinationCity,
    carrier: filters.carrier,
    product: filters.product,
    complianceStatus: filters.complianceStatus
  });

  const { data, loading, error, globalWarningThreshold, globalCriticalThreshold } = useComplianceData(accountId, {
    startDate: filters.startDate,
    endDate: filters.endDate,
    originCity: filters.originCity,
    destinationCity: filters.destinationCity,
    carrier: filters.carrier,
    product: filters.product,
    complianceStatus: filters.complianceStatus
  });

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

  // Calculate KPIs from hierarchical data
  const totalShipments = data.reduce((sum, carrier) => sum + carrier.totalShipments, 0);
  
  const totalCompliant = data.reduce((sum, carrier) => sum + carrier.compliantShipments, 0);
  
  const overallCompliance = totalShipments > 0 ? (totalCompliant / totalShipments) * 100 : 0;
  
  // Count routes (not carriers or products)
  const allRoutes = data.flatMap(carrier => 
    carrier.products.flatMap(product => product.routes)
  );
  
  const compliantRoutes = allRoutes.filter(r => r.complianceStatus === 'compliant').length;
  const warningRoutes = allRoutes.filter(r => r.complianceStatus === 'warning').length;
  const criticalRoutes = allRoutes.filter(r => r.complianceStatus === 'critical').length;
  const totalRoutes = allRoutes.length;
  
  const totalWarning = data.reduce((sum, carrier) => sum + carrier.warningShipments, 0);
  const totalCritical = data.reduce((sum, carrier) => sum + carrier.criticalShipments, 0);

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">{t('reporting.regulatory_compliance_report')}</h1>
          <p className="text-gray-600 mt-1">{t('reporting.compliance_analysis_by_carrier_product_route')}</p>
        </div>
        <div className="flex gap-3">
          <button
            onClick={handleExportPDF}
            disabled={exporting}
            className="flex items-center gap-2 px-4 py-2 bg-green-600 hover:bg-green-700 disabled:bg-gray-400 text-white rounded-lg transition-colors"
          >
            <FileDown className="w-5 h-5" />
            <span className="text-sm font-medium">
              {exporting ? t('reporting.generating') : t('reporting.export_audit_report')}
            </span>
          </button>
          <SmartTooltip content="Regulatory Compliance Report: Analyzes compliance rates hierarchically by Carrier, Product, and Route to identify which carriers, services, or routes are meeting or failing regulatory standards. Shows all carriers, their products, and individual routes. Columns organized to show Standard → Actual for both days and percentages, followed by Deviation and Status. Carrier and Product metrics are weighted averages based on shipment count. Routes classified as Compliant (✅ meeting standard), Warning (⚠️ below standard), or Critical (🔴 below critical threshold). Use to identify systematic compliance failures and as evidence in enforcement proceedings." />
        </div>
      </div>

      <ReportFilters filters={filters} onChange={setFilters} onReset={resetFilters} />

      <div className="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-5 gap-3">
        <KPICard
          title={t('reporting.overall_compliance')}
          value={`${overallCompliance.toFixed(1)}%`}
          icon={Shield}
          trend={compliantRoutes === totalRoutes ? 'up' : compliantRoutes > criticalRoutes ? 'neutral' : 'down'}
          trendValue={t('reporting.of_routes', { count: totalRoutes, compliant: compliantRoutes })}
          color={compliantRoutes === totalRoutes ? 'green' : compliantRoutes > criticalRoutes ? 'amber' : 'red'}
          tooltip={{
            description: "Percentage of routes meeting their configured compliance standards (compliant status).",
            interpretation: "Based on dynamic thresholds configured in Delivery Standards. Higher values indicate better overall network performance.",
            utility: "Primary metric for assessing overall carrier performance across all configured standards."
          }}
        />
        <KPICard
          title={t('reporting.compliant_routes')}
          value={compliantRoutes.toString()}
          icon={CheckCircle}
          trend="up"
          trendValue={t('reporting.meeting_standard')}
          color="green"
          tooltip={{
            description: "Number of routes meeting or exceeding their configured compliance standard.",
            interpretation: "Routes with actual performance at or above the standard threshold. Higher numbers indicate better overall network performance.",
            utility: "Identifies well-performing routes that can serve as benchmarks for improving problematic routes."
          }}
        />
        <KPICard
          title={t('reporting.warning_routes')}
          value={warningRoutes.toString()}
          icon={AlertTriangle}
          trend="neutral"
          trendValue={t('reporting.no_penalty')}
          color="amber"
          tooltip={{
            description: "Routes with compliance below standard but above critical threshold. Performance is acceptable but needs monitoring.",
            interpretation: "Warning status indicates deviation from target without penalty. These routes should be monitored for trends.",
            utility: "Early warning system to prevent routes from falling into critical status."
          }}
        />
        <KPICard
          title={t('reporting.critical_routes')}
          value={criticalRoutes.toString()}
          icon={XCircle}
          trend="down"
          trendValue={t('reporting.with_penalty')}
          color={criticalRoutes > 0 ? 'red' : 'gray'}
          tooltip={{
            description: "Routes with compliance below critical threshold. These routes incur penalties and require immediate corrective action.",
            interpretation: "Any non-zero value indicates regulatory violations. Prioritize routes with lowest compliance for investigation.",
            utility: "Direct indicator of regulatory violations requiring immediate corrective action, potential fines, or service restrictions."
          }}
        />
        <KPICard
          title={t('reporting.total_routes')}
          value={totalRoutes.toString()}
          icon={Info}
          trend="neutral"
          trendValue={t('reporting.across_all_carriers')}
          color="blue"
          tooltip={{
            description: "Total number of unique routes (carrier + product + city pair) with shipment data.",
            interpretation: "More routes indicate broader network coverage. Missing routes may indicate service gaps.",
            utility: "Ensures comprehensive regulatory oversight across all route types and identifies underserved market segments."
          }}
        />
      </div>

      <div className="bg-white rounded-lg shadow p-6">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-semibold text-gray-900">Compliance by Carrier → Product → Route</h2>
          <div className="flex items-center gap-3">
            <button
              onClick={handleExportCSV}
              className="flex items-center gap-2 px-3 py-1.5 text-sm bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors"
            >
              <FileDown className="w-4 h-4" />
              Export CSV
            </button>
            <SmartTooltip content="Hierarchical Compliance Table: Three-level hierarchy showing Carrier (📦), Product (📋), and Route (🛟️). All rows always visible. Carrier and Product rows show weighted averages for Standard (days), Standard %, and Actual (days), weighted by shipment count. Column order: Standard (days) → Actual (days) → Standard % → Actual % → Deviation → Status. Status indicators: ✅ Compliant (meeting standard), ⚠️ Warning (below standard, no penalty), 🔴 Critical (below critical threshold, with penalty). Use as evidence for enforcement proceedings to identify which carriers, products, or routes need adjustments." />
          </div>
        </div>
        <ComplianceTable data={data} />
      </div>
    </div>
  );
}
