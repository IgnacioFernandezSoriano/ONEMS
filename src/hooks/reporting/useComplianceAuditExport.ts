import { supabase } from '@/lib/supabase';

interface RouteData {
  carrier: string;
  product: string;
  origin: string;
  destination: string;
  totalShipments: number;
  compliantShipments: number;
  warningShipments: number;
  criticalShipments: number;
  standardDays: number;
  actualDays: number;
  standardPercentage: number;
  actualPercentage: number;
  deviation: number;
  status: 'compliant' | 'warning' | 'critical';
  warningLimit: number;
  criticalLimit: number;
  thresholdType: string;
}

export async function generateComplianceAuditReport(
  accountId: string,
  filters: {
    carrier?: string;
    product?: string;
    originCity?: string;
    destinationCity?: string;
  }
): Promise<string> {
  // Fetch delivery standards with threshold info
  let standardsQuery = supabase
    .from('delivery_standards')
    .select('*')
    .eq('account_id', accountId);

  const { data: standards } = await standardsQuery;

  // Fetch shipments
  let shipmentsQuery = supabase
    .from('one_db')
    .select('*')
    .eq('account_id', accountId);

  if (filters.carrier) {
    shipmentsQuery = shipmentsQuery.eq('carrier_name', filters.carrier);
  }
  if (filters.product) {
    shipmentsQuery = shipmentsQuery.eq('product_name', filters.product);
  }
  if (filters.originCity) {
    shipmentsQuery = shipmentsQuery.eq('origin_city_name', filters.originCity);
  }
  if (filters.destinationCity) {
    shipmentsQuery = shipmentsQuery.eq('destination_city_name', filters.destinationCity);
  }

  const { data: shipments } = await shipmentsQuery;

  // Fetch lookup tables
  const { data: carriers } = await supabase.from('carriers').select('id, name').eq('account_id', accountId);
  const { data: products } = await supabase.from('products').select('id, description').eq('account_id', accountId);
  const { data: cities } = await supabase.from('cities').select('id, name').eq('account_id', accountId);

  // Create lookup maps
  const carrierMap = new Map(carriers?.map(c => [c.id, c.name]) || []);
  const productMap = new Map(products?.map(p => [p.id, p.description]) || []);
  const cityMap = new Map(cities?.map(c => [c.id, c.name]) || []);

  // Create standards map
  const standardsMap = new Map<string, any>();
  (standards || []).forEach(std => {
    const carrierName = carrierMap.get(std.carrier_id);
    const productName = productMap.get(std.product_id);
    const originName = cityMap.get(std.origin_city_id);
    const destName = cityMap.get(std.destination_city_id);
    
    if (carrierName && productName && originName && destName) {
      const key = `${carrierName}|${productName}|${originName}|${destName}`;
      standardsMap.set(key, std);
    }
  });

  // Process shipments into routes
  const routeMap = new Map<string, RouteData>();
  
  (shipments || []).forEach(shipment => {
    const key = `${shipment.carrier_name}|${shipment.product_name}|${shipment.origin_city_name}|${shipment.destination_city_name}`;
    
    if (!routeMap.has(key)) {
      const standard = standardsMap.get(key);
      const standardPercentage = standard?.success_percentage || 0;
      const warningThreshold = standard?.warning_threshold || 5;
      const criticalThreshold = standard?.critical_threshold || 10;
      const thresholdType = standard?.threshold_type || 'relative';
      
      // Calculate limits
      let warningLimit, criticalLimit;
      if (thresholdType === 'relative') {
        warningLimit = standardPercentage - (standardPercentage * warningThreshold / 100);
        criticalLimit = standardPercentage - (standardPercentage * criticalThreshold / 100);
      } else {
        warningLimit = 100 - warningThreshold;
        criticalLimit = 100 - criticalThreshold;
      }
      
      routeMap.set(key, {
        carrier: shipment.carrier_name,
        product: shipment.product_name,
        origin: shipment.origin_city_name,
        destination: shipment.destination_city_name,
        totalShipments: 0,
        compliantShipments: 0,
        warningShipments: 0,
        criticalShipments: 0,
        standardDays: standard?.standard_time || 0,
        actualDays: 0,
        standardPercentage,
        actualPercentage: 0,
        deviation: 0,
        status: 'compliant',
        warningLimit,
        criticalLimit,
        thresholdType
      });
    }
    
    const route = routeMap.get(key)!;
    route.totalShipments++;
    route.actualDays += shipment.business_transit_days || 0;
    
    if (shipment.on_time_delivery) {
      route.compliantShipments++;
    }
  });

  // Calculate averages and status
  routeMap.forEach(route => {
    route.actualDays = route.actualDays / route.totalShipments;
    route.actualPercentage = (route.compliantShipments / route.totalShipments) * 100;
    route.deviation = route.actualPercentage - route.standardPercentage;
    
    // Determine status
    if (route.actualPercentage >= route.standardPercentage) {
      route.status = 'compliant';
    } else if (route.actualPercentage >= route.criticalLimit) {
      route.status = 'warning';
      route.warningShipments = route.totalShipments - route.compliantShipments;
    } else {
      route.status = 'critical';
      route.criticalShipments = route.totalShipments - route.compliantShipments;
    }
  });

  const routes = Array.from(routeMap.values());
  const compliantRoutes = routes.filter(r => r.status === 'compliant');
  const warningRoutes = routes.filter(r => r.status === 'warning');
  const criticalRoutes = routes.filter(r => r.status === 'critical');

  // Generate comprehensive audit report
  let markdown = '# REGULATORY COMPLIANCE AUDIT REPORT\n\n';
  markdown += `**Report Date:** ${new Date().toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })}\n\n`;
  markdown += `**Account ID:** ${accountId}\n\n`;
  markdown += `**Reporting Period:** ${filters.carrier ? `Carrier: ${filters.carrier}` : 'All Carriers'}`;
  if (filters.product) markdown += ` | Product: ${filters.product}`;
  if (filters.originCity) markdown += ` | Origin: ${filters.originCity}`;
  if (filters.destinationCity) markdown += ` | Destination: ${filters.destinationCity}`;
  markdown += '\n\n';
  markdown += '---\n\n';

  // Executive Summary
  markdown += '## EXECUTIVE SUMMARY\n\n';
  const totalShipments = routes.reduce((sum, r) => sum + r.totalShipments, 0);
  const totalCompliant = routes.reduce((sum, r) => sum + r.compliantShipments, 0);
  const totalWarning = routes.reduce((sum, r) => sum + r.warningShipments, 0);
  const totalCritical = routes.reduce((sum, r) => sum + r.criticalShipments, 0);
  const overallCompliance = totalShipments > 0 ? (totalCompliant / totalShipments) * 100 : 0;

  markdown += `This audit report evaluates compliance with delivery standards across ${routes.length} active routes, covering ${totalShipments} shipments.\n\n`;
  
  markdown += `### Overall Compliance Status\n\n`;
  markdown += `- **Total Routes Evaluated:** ${routes.length}\n`;
  markdown += `- **Total Shipments:** ${totalShipments.toLocaleString()}\n`;
  markdown += `- **Overall Compliance Rate:** ${overallCompliance.toFixed(1)}%\n\n`;
  
  markdown += `### Compliance Breakdown\n\n`;
  markdown += `| Category | Routes | Shipments | Percentage |\n`;
  markdown += `|----------|--------|-----------|------------|\n`;
  markdown += `| ✅ Compliant (Meeting Standard) | ${compliantRoutes.length} | ${totalCompliant.toLocaleString()} | ${((totalCompliant/totalShipments)*100).toFixed(1)}% |\n`;
  markdown += `| ⚠️ Warning (Below Standard, No Penalty) | ${warningRoutes.length} | ${totalWarning.toLocaleString()} | ${((totalWarning/totalShipments)*100).toFixed(1)}% |\n`;
  markdown += `| 🔴 Critical (Below Critical, With Penalty) | ${criticalRoutes.length} | ${totalCritical.toLocaleString()} | ${((totalCritical/totalShipments)*100).toFixed(1)}% |\n\n`;

  markdown += `### Key Findings\n\n`;
  if (criticalRoutes.length > 0) {
    markdown += `- **⚠️ REGULATORY CONCERN:** ${criticalRoutes.length} route(s) operating below critical threshold, affecting ${totalCritical} shipments\n`;
  }
  if (warningRoutes.length > 0) {
    markdown += `- **⚠️ ATTENTION REQUIRED:** ${warningRoutes.length} route(s) below standard but above critical threshold\n`;
  }
  if (compliantRoutes.length === routes.length) {
    markdown += `- **✅ FULL COMPLIANCE:** All routes meeting or exceeding delivery standards\n`;
  }
  markdown += '\n---\n\n';

  // Standards Expected
  markdown += '## DELIVERY STANDARDS (EXPECTED PERFORMANCE)\n\n';
  markdown += `The following standards have been established for the evaluated routes:\n\n`;
  markdown += `| Carrier | Product | Route | Standard Days | Standard % | Warning Limit | Critical Limit | Type |\n`;
  markdown += `|---------|---------|-------|---------------|------------|---------------|----------------|------|\n`;
  
  routes.sort((a, b) => a.carrier.localeCompare(b.carrier) || a.product.localeCompare(b.product))
    .forEach(route => {
      markdown += `| ${route.carrier} | ${route.product} | ${route.origin} → ${route.destination} | ${route.standardDays.toFixed(1)} | ${route.standardPercentage.toFixed(1)}% | ${route.warningLimit.toFixed(1)}% | ${route.criticalLimit.toFixed(1)}% | ${route.thresholdType === 'relative' ? 'Rel' : 'Abs'} |\n`;
    });
  
  markdown += '\n---\n\n';

  // Results Obtained
  markdown += '## ACTUAL PERFORMANCE (RESULTS OBTAINED)\n\n';
  markdown += `Performance data based on ${totalShipments} shipments:\n\n`;
  markdown += `| Carrier | Product | Route | Shipments | Actual Days | Actual % | Deviation | Status |\n`;
  markdown += `|---------|---------|-------|-----------|-------------|----------|-----------|--------|\n`;
  
  routes.sort((a, b) => {
    if (a.status === 'critical' && b.status !== 'critical') return -1;
    if (a.status !== 'critical' && b.status === 'critical') return 1;
    if (a.status === 'warning' && b.status === 'compliant') return -1;
    if (a.status === 'compliant' && b.status === 'warning') return 1;
    return a.deviation - b.deviation;
  }).forEach(route => {
    const statusIcon = route.status === 'compliant' ? '✅' : route.status === 'warning' ? '⚠️' : '🔴';
    const statusText = route.status === 'compliant' ? 'Compliant' : route.status === 'warning' ? 'Warning' : 'CRITICAL';
    const deviationSign = route.deviation >= 0 ? '+' : '';
    markdown += `| ${route.carrier} | ${route.product} | ${route.origin} → ${route.destination} | ${route.totalShipments} | ${route.actualDays.toFixed(1)} | ${route.actualPercentage.toFixed(1)}% | ${deviationSign}${route.deviation.toFixed(1)}% | ${statusIcon} ${statusText} |\n`;
  });
  
  markdown += '\n---\n\n';

  // Critical Points
  markdown += '## CRITICAL POINTS & REGULATORY ACTIONS\n\n';
  
  if (criticalRoutes.length > 0) {
    markdown += `### 🔴 ROUTES REQUIRING IMMEDIATE ACTION (${criticalRoutes.length})\n\n`;
    markdown += `The following routes are operating below critical thresholds and require immediate corrective action:\n\n`;
    
    criticalRoutes.sort((a, b) => a.deviation - b.deviation).forEach((route, index) => {
      markdown += `#### ${index + 1}. ${route.carrier} - ${route.product} (${route.origin} → ${route.destination})\n\n`;
      markdown += `- **Shipments Affected:** ${route.totalShipments}\n`;
      markdown += `- **Standard Required:** ${route.standardPercentage.toFixed(1)}%\n`;
      markdown += `- **Actual Performance:** ${route.actualPercentage.toFixed(1)}%\n`;
      markdown += `- **Deviation:** ${route.deviation.toFixed(1)}%\n`;
      markdown += `- **Critical Threshold:** ${route.criticalLimit.toFixed(1)}%\n`;
      markdown += `- **Recommended Action:** Immediate investigation and corrective measures. Consider service suspension if performance does not improve within 30 days.\n\n`;
    });
  }
  
  if (warningRoutes.length > 0) {
    markdown += `### ⚠️ ROUTES REQUIRING ATTENTION (${warningRoutes.length})\n\n`;
    markdown += `The following routes are below standard but above critical threshold:\n\n`;
    
    markdown += `| Carrier | Product | Route | Actual % | Deviation | Gap to Critical |\n`;
    markdown += `|---------|---------|-------|----------|-----------|------------------|\n`;
    
    warningRoutes.sort((a, b) => a.deviation - b.deviation).forEach(route => {
      const gapToCritical = route.actualPercentage - route.criticalLimit;
      markdown += `| ${route.carrier} | ${route.product} | ${route.origin} → ${route.destination} | ${route.actualPercentage.toFixed(1)}% | ${route.deviation.toFixed(1)}% | ${gapToCritical.toFixed(1)}% |\n`;
    });
    
    markdown += `\n**Recommendation:** Monitor closely. Implement performance improvement plans to bring these routes back to standard within 60 days.\n\n`;
  }
  
  if (compliantRoutes.length === routes.length) {
    markdown += `### ✅ FULL COMPLIANCE ACHIEVED\n\n`;
    markdown += `All evaluated routes are meeting or exceeding delivery standards. No regulatory action required.\n\n`;
    markdown += `**Recommendation:** Continue monitoring to maintain compliance levels.\n\n`;
  }
  
  markdown += '---\n\n';

  // Carrier Summary
  const carrierSummary = new Map<string, { total: number; compliant: number; warning: number; critical: number }>();
  routes.forEach(route => {
    if (!carrierSummary.has(route.carrier)) {
      carrierSummary.set(route.carrier, { total: 0, compliant: 0, warning: 0, critical: 0 });
    }
    const summary = carrierSummary.get(route.carrier)!;
    summary.total += route.totalShipments;
    if (route.status === 'compliant') summary.compliant += route.totalShipments;
    if (route.status === 'warning') summary.warning += route.totalShipments;
    if (route.status === 'critical') summary.critical += route.totalShipments;
  });

  markdown += '## CARRIER PERFORMANCE SUMMARY\n\n';
  markdown += `| Carrier | Total Shipments | Compliant | Warning | Critical | Compliance % |\n`;
  markdown += `|---------|----------------|-----------|---------|----------|-------------|\n`;
  
  Array.from(carrierSummary.entries()).sort((a, b) => {
    const aComp = (a[1].compliant / a[1].total) * 100;
    const bComp = (b[1].compliant / b[1].total) * 100;
    return bComp - aComp;
  }).forEach(([carrier, summary]) => {
    const complianceRate = (summary.compliant / summary.total) * 100;
    markdown += `| ${carrier} | ${summary.total.toLocaleString()} | ${summary.compliant.toLocaleString()} | ${summary.warning.toLocaleString()} | ${summary.critical.toLocaleString()} | ${complianceRate.toFixed(1)}% |\n`;
  });

  markdown += '\n---\n\n';
  markdown += '## AUDIT CERTIFICATION\n\n';
  markdown += `This report has been generated based on actual shipment data and established delivery standards. All data is subject to verification and may be used for regulatory enforcement proceedings.\n\n`;
  markdown += `**Report Generated By:** ONEMS Regulatory Compliance System\n\n`;
  markdown += `**Data Source:** Account ${accountId}\n\n`;
  markdown += `**Methodology:** Dynamic threshold-based compliance evaluation using configurable warning and critical limits.\n\n`;

  return markdown;
}
