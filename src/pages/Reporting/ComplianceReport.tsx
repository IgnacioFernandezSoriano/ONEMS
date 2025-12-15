import React from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { useReportingFilters } from '@/contexts/ReportingFiltersContext';
import { useComplianceData } from '@/hooks/reporting/useComplianceData';
import { KPICard } from '@/components/reporting/KPICard';
import { ReportFilters } from '@/components/reporting/ReportFilters';
import { ComplianceTable } from '@/components/reporting/ComplianceTable';
import { Shield, AlertTriangle, CheckCircle, XCircle, Info, FileDown } from 'lucide-react';
import { generateComplianceAuditReport } from '@/hooks/reporting/useComplianceAuditExport';
import { useState } from 'react';

export default function ComplianceReport() {
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
  const { data, loading, error } = useComplianceData(accountId, {
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
          <h1 className="text-2xl font-bold text-gray-900">Regulatory Compliance Report</h1>
          <p className="text-gray-600 mt-1">Compliance analysis by Carrier → Product → Route</p>
        </div>
        <div className="flex gap-3">
          <button
            onClick={handleExportPDF}
            disabled={exporting}
            className="flex items-center gap-2 px-4 py-2 bg-green-600 hover:bg-green-700 disabled:bg-gray-400 text-white rounded-lg transition-colors"
          >
            <FileDown className="w-5 h-5" />
            <span className="text-sm font-medium">
              {exporting ? 'Generating...' : 'Export Audit Report'}
            </span>
          </button>
          <div className="group relative">
          <div className="flex items-center gap-2 px-4 py-2 bg-blue-50 border border-blue-200 rounded-lg cursor-help">
            <Info className="w-5 h-5 text-blue-600" />
            <span className="text-sm font-medium text-blue-900">About this Report</span>
          </div>
          <div className="invisible group-hover:visible absolute z-10 w-96 p-4 bg-white border border-gray-200 rounded-lg shadow-xl text-sm text-gray-700 right-0 top-12">
            <div className="absolute -top-1 right-8 w-2 h-2 bg-white border-l border-t border-gray-200 transform rotate-45"></div>
            <h3 className="font-bold text-gray-900 mb-3">Regulatory Compliance Report</h3>
            <p className="mb-3"><strong>Purpose:</strong> Analyzes compliance rates hierarchically by Carrier, Product, and Route to identify which carriers, services, or routes are meeting or failing regulatory standards.</p>
            <p className="mb-3"><strong>What you'll see:</strong> All rows displayed showing carriers, their products, and individual routes. Columns are organized to show Standard → Actual for both days and percentages, followed by Deviation and Status.</p>
            <p className="mb-3"><strong>Weighted Averages:</strong> Carrier and Product level metrics (Standard days, Standard %, Actual days) are weighted averages based on shipment count. Routes with more shipments have proportionally more influence on the average.</p>
            <p className="mb-3"><strong>Dynamic Thresholds:</strong> Each route has configurable warning and critical thresholds (relative or absolute) defined in Delivery Standards. Routes are automatically classified as Compliant (✅ meeting standard), Warning (⚠️ below standard but above critical), or Critical (🔴 below critical threshold with penalty).</p>
            <p className="mb-3"><strong>Regulatory Objective:</strong> Identify systematic compliance failures at carrier, product, or route level. Determine if certain services need adjusted standards or if carriers need targeted interventions. Use as evidence in enforcement proceedings.</p>
          </div>
        </div>
        </div>
      </div>

      <ReportFilters filters={filters} onChange={setFilters} onReset={resetFilters} />

      <div className="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-5 gap-3">
        <KPICard
          title="Overall Compliance"
          value={`${overallCompliance.toFixed(1)}%`}
          icon={Shield}
          trend={compliantRoutes === totalRoutes ? 'up' : compliantRoutes > criticalRoutes ? 'neutral' : 'down'}
          trendValue={`${compliantRoutes} of ${totalRoutes} routes`}
          color={compliantRoutes === totalRoutes ? 'green' : compliantRoutes > criticalRoutes ? 'amber' : 'red'}
          tooltip={{
            description: "Percentage of routes meeting their configured compliance standards (compliant status).",
            interpretation: "Based on dynamic thresholds configured in Delivery Standards. Higher values indicate better overall network performance.",
            utility: "Primary metric for assessing overall carrier performance across all configured standards."
          }}
        />
        <KPICard
          title="Compliant Routes"
          value={compliantRoutes.toString()}
          icon={CheckCircle}
          trend="up"
          trendValue="Meeting standard"
          color="green"
          tooltip={{
            description: "Number of routes meeting or exceeding their configured compliance standard.",
            interpretation: "Routes with actual performance at or above the standard threshold. Higher numbers indicate better overall network performance.",
            utility: "Identifies well-performing routes that can serve as benchmarks for improving problematic routes."
          }}
        />
        <KPICard
          title="Warning Routes"
          value={warningRoutes.toString()}
          icon={AlertTriangle}
          trend={warningRoutes > 0 ? 'down' : 'neutral'}
          trendValue="No penalty"
          color="amber"
          tooltip={{
            description: "Routes with compliance below standard but above critical threshold. Performance is acceptable but needs monitoring.",
            interpretation: "Warning status indicates deviation from target without penalty. These routes should be monitored for trends.",
            utility: "Early warning system to prevent routes from falling into critical status."
          }}
        />
        <KPICard
          title="Critical Routes"
          value={criticalRoutes.toString()}
          icon={XCircle}
          trend={criticalRoutes > 0 ? 'down' : 'neutral'}
          trendValue="With penalty"
          color={criticalRoutes > 0 ? 'red' : 'gray'}
          tooltip={{
            description: "Routes with compliance below critical threshold. These routes incur penalties and require immediate corrective action.",
            interpretation: "Any non-zero value indicates regulatory violations. Prioritize routes with lowest compliance for investigation.",
            utility: "Direct indicator of regulatory violations requiring immediate corrective action, potential fines, or service restrictions."
          }}
        />
        <KPICard
          title="Total Routes"
          value={totalRoutes.toString()}
          icon={AlertTriangle}
          trend="neutral"
          trendValue="Across all carriers"
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
            <div className="group relative">
            <Info className="w-5 h-5 text-gray-400 hover:text-blue-600 cursor-help" />
            <div className="invisible group-hover:visible absolute z-10 w-96 p-4 bg-white border border-gray-200 rounded-lg shadow-lg text-sm text-gray-700 right-0 top-8">
              <div className="absolute -top-1 right-4 w-2 h-2 bg-white border-l border-t border-gray-200 transform rotate-45"></div>
              <p className="font-semibold mb-2">Hierarchical Compliance Table</p>
              <p className="mb-2"><strong>Structure:</strong> Three-level hierarchy showing Carrier (📦), Product (📋), and Route (🛣️). All rows are always visible.</p>
              <p className="mb-2"><strong>Weighted Averages:</strong> Carrier and Product rows show weighted averages for Standard (days), Standard %, and Actual (days). The weighting is proportional to shipment count - routes with more shipments contribute more to the average.</p>
              <p className="mb-2"><strong>Example:</strong> If a product has Route A (100 shipments, 1.0 day standard) and Route B (50 shipments, 2.0 day standard), the product-level Standard (days) = (100×1.0 + 50×2.0) / 150 = 1.33 days.</p>
              <p className="mb-2"><strong>Column Order:</strong> Standard (days) → Actual (days) → Standard % → Actual % → Deviation → Status. This allows easy comparison of standard vs actual for both time and success metrics.</p>
              <p className="mb-2"><strong>Interpretation:</strong> Status indicators show compliance level: ✅ Compliant (meeting standard), ⚠️ Warning (below standard, no penalty), 🔴 Critical (below critical threshold, with penalty). Compare actual transit days against standards to identify systematic delays.</p>
              <p><strong>Regulatory Use:</strong> Evidence for enforcement proceedings. Identifies which carriers, products, or routes need standard adjustments or performance improvements.</p>
            </div>
          </div>
          </div>
        </div>
        <ComplianceTable data={data} />
      </div>
    </div>
  );
}
