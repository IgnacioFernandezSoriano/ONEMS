import { supabase } from '@/lib/supabase';

interface CarrierData {
  carrierName: string;
  standards: Array<{
    origin: string;
    destination: string;
    product: string;
    allowedDays: number;
  }>;
  performance: Array<{
    origin: string;
    destination: string;
    product: string;
    totalShipments: number;
    compliantShipments: number;
    compliancePercentage: number;
    avgTransitDays: number;
  }>;
}

export async function generateCarrierComplianceReport(
  accountId: string,
  carrierFilter?: string
): Promise<string> {
  // Fetch delivery standards
  let standardsQuery = supabase
    .from('delivery_standards')
    .select('*')
    .eq('account_id', accountId);

  if (carrierFilter) {
    standardsQuery = standardsQuery.eq('carrier_name', carrierFilter);
  }

  const { data: standards } = await standardsQuery;

  // Fetch shipments with pagination
  const allShipments: any[] = []
  const pageSize = 1000
  let start = 0
  let hasMore = true

  while (hasMore) {
    let shipmentsQuery = supabase
      .from('one_db')
      .select('*')
      .eq('account_id', accountId)
      .range(start, start + pageSize - 1)

    if (carrierFilter) {
      shipmentsQuery = shipmentsQuery.eq('carrier_name', carrierFilter)
    }

    const { data } = await shipmentsQuery

    if (data && data.length > 0) {
      allShipments.push(...data)
      hasMore = data.length === pageSize
      start += pageSize
    } else {
      hasMore = false
    }
  }

  const shipments = allShipments

  // Group by carrier
  const carrierMap = new Map<string, CarrierData>();

  // Process standards
  (standards || []).forEach(std => {
    if (!carrierMap.has(std.carrier_name)) {
      carrierMap.set(std.carrier_name, {
        carrierName: std.carrier_name,
        standards: [],
        performance: []
      });
    }
    carrierMap.get(std.carrier_name)!.standards.push({
      origin: std.origin_city_name,
      destination: std.destination_city_name,
      product: std.product_name,
      allowedDays: std.allowed_days
    });
  });

  // Process shipments
  const performanceMap = new Map<string, {
    total: number;
    compliant: number;
    totalDays: number;
  }>();

  (shipments || []).forEach(shipment => {
    const key = `${shipment.carrier_name}|${shipment.origin_city_name}|${shipment.destination_city_name}|${shipment.product_name}`;
    const existing = performanceMap.get(key) || { total: 0, compliant: 0, totalDays: 0 };
    
    performanceMap.set(key, {
      total: existing.total + 1,
      compliant: existing.compliant + (shipment.on_time_delivery ? 1 : 0),
      totalDays: existing.totalDays + (shipment.business_transit_days || 0)
    });

    // Ensure carrier exists in map
    if (!carrierMap.has(shipment.carrier_name)) {
      carrierMap.set(shipment.carrier_name, {
        carrierName: shipment.carrier_name,
        standards: [],
        performance: []
      });
    }
  });

  // Convert performance map to carrier data
  performanceMap.forEach((stats, key) => {
    const [carrier, origin, destination, product] = key.split('|');
    const carrierData = carrierMap.get(carrier);
    if (carrierData) {
      carrierData.performance.push({
        origin,
        destination,
        product,
        totalShipments: stats.total,
        compliantShipments: stats.compliant,
        compliancePercentage: (stats.compliant / stats.total) * 100,
        avgTransitDays: stats.totalDays / stats.total
      });
    }
  });

  // Generate markdown report
  let markdown = '# Carrier Compliance Report\n\n';
  markdown += `**Generated:** ${new Date().toLocaleDateString()}\n\n`;
  markdown += '---\n\n';

  const carriers = Array.from(carrierMap.values()).sort((a, b) => 
    a.carrierName.localeCompare(b.carrierName)
  );

  carriers.forEach((carrier, index) => {
    if (index > 0) markdown += '\n\\pagebreak\n\n';
    
    markdown += `## ${carrier.carrierName}\n\n`;

    // Standards section
    markdown += `### Delivery Standards\n\n`;
    markdown += `| Origin | Destination | Product | Max Allowed Days |\n`;
    markdown += `|--------|-------------|---------|------------------|\n`;
    
    carrier.standards
      .sort((a, b) => a.origin.localeCompare(b.origin))
      .forEach(std => {
        markdown += `| ${std.origin} | ${std.destination} | ${std.product} | ${std.allowedDays} |\n`;
      });

    markdown += `\n`;

    // Performance section
    markdown += `### Actual Performance\n\n`;
    markdown += `| Origin | Destination | Product | Shipments | Compliant | Compliance % | Avg Days |\n`;
    markdown += `|--------|-------------|---------|-----------|-----------|--------------|----------|\n`;
    
    carrier.performance
      .sort((a, b) => a.compliancePercentage - b.compliancePercentage)
      .forEach(perf => {
        const complianceColor = perf.compliancePercentage >= 95 ? '✅' : '❌';
        markdown += `| ${perf.origin} | ${perf.destination} | ${perf.product} | ${perf.totalShipments} | ${perf.compliantShipments} | ${complianceColor} ${perf.compliancePercentage.toFixed(1)}% | ${perf.avgTransitDays.toFixed(1)} |\n`;
      });

    markdown += `\n`;

    // Summary
    const totalShipments = carrier.performance.reduce((sum, p) => sum + p.totalShipments, 0);
    const totalCompliant = carrier.performance.reduce((sum, p) => sum + p.compliantShipments, 0);
    const overallCompliance = totalShipments > 0 ? (totalCompliant / totalShipments) * 100 : 0;

    markdown += `### Summary\n\n`;
    markdown += `- **Total Shipments:** ${totalShipments}\n`;
    markdown += `- **Compliant Shipments:** ${totalCompliant}\n`;
    markdown += `- **Overall Compliance:** ${overallCompliance.toFixed(1)}%\n`;
    markdown += `- **Status:** ${overallCompliance >= 95 ? '✅ Meeting Standards' : '❌ Below Standards'}\n\n`;
  });

  return markdown;
}
