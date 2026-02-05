import React, { useState, useMemo } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { useTerritoryEquityDataV2 as useTerritoryEquityData } from '@/hooks/reporting/useTerritoryEquityDataV2';
import { TerritoryEquityFilters } from '@/components/reporting/TerritoryEquityFilters';
import { ComplianceCarrierTable } from '@/components/reporting/ComplianceCarrierTable';
import { ComplianceProductTable } from '@/components/reporting/ComplianceProductTable';
import { ComplianceRouteTable } from '@/components/reporting/ComplianceRouteTable';
import { Shield, AlertTriangle, CheckCircle, XCircle, Info, FileDown, TrendingUp, Package, MapPin } from 'lucide-react';
import { SmartTooltip } from '@/components/common/SmartTooltip';
import { useTranslation } from '@/hooks/useTranslation';
import type { TerritoryEquityFilters as Filters } from '@/types/reporting';

export default function ComplianceReport() {
  const { t } = useTranslation();
  const { profile } = useAuth();
  const [activeTab, setActiveTab] = useState<'carrier' | 'product' | 'route'>('carrier');
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

  // Calculate KPIs from route data
  const totalRoutes = routeData.length;
  const compliantRoutes = routeData.filter(r => r.status === 'compliant').length;
  const warningRoutes = routeData.filter(r => r.status === 'warning').length;
  const criticalRoutes = routeData.filter(r => r.status === 'critical').length;
  
  const totalSamples = routeData.reduce((sum, r) => sum + (r.samples || 0), 0);
  const overallCompliance = totalRoutes > 0 ? (compliantRoutes / totalRoutes) * 100 : 0;

  // Aggregate by carrier
  const carrierData = useMemo(() => {
    const carrierMap = new Map();
    routeData.forEach(route => {
      const carrier = route.carrier || 'Unknown';
      if (!carrierMap.has(carrier)) {
        carrierMap.set(carrier, {
          carrier,
          routes: [],
          totalSamples: 0,
          compliantRoutes: 0,
          warningRoutes: 0,
          criticalRoutes: 0,
        });
      }
      const c = carrierMap.get(carrier);
      c.routes.push(route);
      c.totalSamples += route.samples || 0;
      if (route.status === 'compliant') c.compliantRoutes++;
      if (route.status === 'warning') c.warningRoutes++;
      if (route.status === 'critical') c.criticalRoutes++;
    });
    return Array.from(carrierMap.values());
  }, [routeData]);

  // Aggregate by product
  const productData = useMemo(() => {
    const productMap = new Map();
    routeData.forEach(route => {
      const product = route.product || 'Unknown';
      if (!productMap.has(product)) {
        productMap.set(product, {
          product,
          routes: [],
          totalSamples: 0,
          compliantRoutes: 0,
          warningRoutes: 0,
          criticalRoutes: 0,
        });
      }
      const p = productMap.get(product);
      p.routes.push(route);
      p.totalSamples += route.samples || 0;
      if (route.status === 'compliant') p.compliantRoutes++;
      if (route.status === 'warning') p.warningRoutes++;
      if (route.status === 'critical') p.criticalRoutes++;
    });
    return Array.from(productMap.values());
  }, [routeData]);

  const handleExportCSV = () => {
    const headers = ['Carrier', 'Product', 'Origin', 'Destination', 'Samples', 'J+K STD', 'J+K Actual', 'STD %', 'Actual %', 'Deviation', 'Status'];
    const rows: string[][] = [headers];
    
    routeData.forEach(route => {
      const deviation = route.standardPercentage > 0 
        ? ((route.actualPercentage - route.standardPercentage) / route.standardPercentage * 100).toFixed(1)
        : '0.0';
      
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
        route.status || ''
      ]);
    });
    
    const csvContent = rows.map(row => row.map(cell => `"${cell}"`).join(',')).join('\n');
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
          <div className="text-xs text-gray-500 mt-1">Below standard</div>
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
          <div className="text-xs text-gray-500 mt-1">Needs action</div>
        </div>

        <div className="bg-white rounded-lg shadow p-4">
          <div className="flex items-center justify-between mb-2">
            <div className="flex items-center gap-2">
              <Info className="w-5 h-5 text-blue-600" />
              <span className="text-sm text-gray-600">Total Samples</span>
            </div>
            <SmartTooltip content="Total number of shipment samples analyzed across all routes." />
          </div>
          <div className="text-2xl font-bold text-blue-600">{totalSamples}</div>
          <div className="text-xs text-gray-500 mt-1">{totalRoutes} routes</div>
        </div>
      </div>

      <div className="bg-white rounded-lg shadow">
        <div className="border-b border-gray-200">
          <nav className="flex -mb-px">
            <button
              onClick={() => setActiveTab('carrier')}
              className={`flex items-center gap-2 px-6 py-4 text-sm font-medium border-b-2 transition-colors ${
                activeTab === 'carrier'
                  ? 'border-blue-600 text-blue-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
              }`}
            >
              <TrendingUp className="w-4 h-4" />
              Carrier Analysis
            </button>
            <button
              onClick={() => setActiveTab('product')}
              className={`flex items-center gap-2 px-6 py-4 text-sm font-medium border-b-2 transition-colors ${
                activeTab === 'product'
                  ? 'border-blue-600 text-blue-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
              }`}
            >
              <Package className="w-4 h-4" />
              Product Analysis
            </button>
            <button
              onClick={() => setActiveTab('route')}
              className={`flex items-center gap-2 px-6 py-4 text-sm font-medium border-b-2 transition-colors ${
                activeTab === 'route'
                  ? 'border-blue-600 text-blue-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
              }`}
            >
              <MapPin className="w-4 h-4" />
              Route Analysis
            </button>
          </nav>
        </div>

        <div className="p-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-lg font-semibold text-gray-900">
              {activeTab === 'carrier' && 'Carrier Compliance Analysis'}
              {activeTab === 'product' && 'Product Compliance Analysis'}
              {activeTab === 'route' && 'Route Compliance Analysis'}
            </h2>
            <button
              onClick={handleExportCSV}
              className="flex items-center gap-2 px-3 py-1.5 text-sm bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors"
            >
              <FileDown className="w-4 h-4" />
              Export CSV
            </button>
          </div>

          {activeTab === 'carrier' && (
            <ComplianceCarrierTable 
              data={carrierData}
              warningThreshold={globalWarningThreshold}
              criticalThreshold={globalCriticalThreshold}
            />
          )}

          {activeTab === 'product' && (
            <ComplianceProductTable 
              data={productData}
              warningThreshold={globalWarningThreshold}
              criticalThreshold={globalCriticalThreshold}
            />
          )}

          {activeTab === 'route' && (
            <ComplianceRouteTable 
              data={routeData}
              warningThreshold={globalWarningThreshold}
              criticalThreshold={globalCriticalThreshold}
            />
          )}
        </div>
      </div>
    </div>
  );
}
