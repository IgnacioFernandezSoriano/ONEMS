import type {
  CityEquityData,
  RegionEquityData,
  TerritoryEquityMetrics,
} from '@/types/reporting';

interface EquityAuditExportData {
  cityData: CityEquityData[];
  regionData: RegionEquityData[];
  metrics: TerritoryEquityMetrics | null;
  filters?: {
    startDate?: string;
    endDate?: string;
    carrier?: string;
    product?: string;
    region?: string;
    direction?: string;
    equityStatus?: string[];
  };
}

export const useEquityAuditExport = () => {

  const generateMarkdownReport = (data: EquityAuditExportData): string => {
    const { cityData, regionData, metrics, filters } = data;

    if (!metrics || cityData.length === 0) {
      return '# Equity Audit Report\n\nNo data available for the selected period.';
    }

    // Report Header
    const reportDate = new Date().toLocaleDateString('es-ES', {
      year: 'numeric',
      month: 'long',
      day: 'numeric'
    });

    const filterSummary = filters ? `
### Filters Applied

${filters.startDate ? `- **Period:** ${filters.startDate} to ${filters.endDate || 'present'}` : ''}
${filters.carrier ? `- **Carrier:** ${filters.carrier}` : ''}
${filters.product ? `- **Product:** ${filters.product}` : ''}
${filters.region ? `- **Region:** ${filters.region}` : ''}
${filters.direction ? `- **Direction:** ${filters.direction}` : ''}
${filters.equityStatus && filters.equityStatus.length > 0 ? `- **Equity Status:** ${filters.equityStatus.join(', ')}` : ''}
` : '';

    // 1. Executive Summary
    const executiveSummary = `
## 1. Executive Summary

This report provides a comprehensive analysis of service equity across ${metrics.totalCities} cities and ${metrics.totalRegions} regions, covering a total population of ${metrics.totalPopulation.toLocaleString()} citizens.

**Key Findings:**

- **Service Equity Index:** ${metrics.serviceEquityIndex.toFixed(1)}/100
- **Population-Weighted Compliance:** ${metrics.populationWeightedCompliance.toFixed(1)}%
- **Underserved Cities:** ${metrics.underservedCitiesCount} cities below standards
- **Citizens Affected:** ${metrics.citizensAffected.toLocaleString()} citizens in underserved areas

${filterSummary}
`;

    // 2. Overall Performance Metrics
    const overallPerformance = `
## 2. Overall Performance Metrics

| Metric | Value |
|--------|-------|
| Total Cities Analyzed | ${metrics.totalCities} |
| Total Regions Analyzed | ${metrics.totalRegions} |
| Service Equity Index | ${metrics.serviceEquityIndex.toFixed(1)}/100 |
| Population-Weighted Compliance | ${metrics.populationWeightedCompliance.toFixed(1)}% |
| Total Population Covered | ${metrics.totalPopulation.toLocaleString()} |
| Underserved Cities | ${metrics.underservedCitiesCount} |
| Citizens in Underserved Areas | ${metrics.citizensAffected.toLocaleString()} |
`;

    // 3. Top Performers and Underperformers
    const topPerformers = `
## 3. Top Performers and Underperformers

### Top 3 Best Served Cities

| City | Compliance | Deviation | Status |
|------|------------|-----------|--------|
${metrics.topBestCities.map(city => 
  `| ${city.cityName} | ${city.actualPercentage.toFixed(1)}% | +${city.deviation.toFixed(1)}% | ✅ Excellent |`
).join('\n')}

### Top 3 Worst Served Cities

| City | Compliance | Deviation | Status |
|------|------------|-----------|--------|
${metrics.topWorstCities.map(city => 
  `| ${city.cityName} | ${city.actualPercentage.toFixed(1)}% | ${city.deviation.toFixed(1)}% | ⚠️ Needs Improvement |`
).join('\n')}
`;

    // 4. Regional Analysis
    const regionalAnalysis = `
## 4. Regional Analysis

| Region | Cities | Population | Total Shipments | Compliance | Standard | Deviation | Inbound % | Outbound % | Direction Gap | Status |
|--------|--------|------------|-----------------|------------|----------|-----------|-----------|------------|---------------|--------|
${regionData.map(region => 
  `| ${region.regionName} | ${region.totalCities} | ${region.totalPopulation.toLocaleString()} | ${region.totalShipments} | ${region.actualPercentage.toFixed(1)}% | ${region.standardPercentage.toFixed(1)}% | ${region.deviation.toFixed(1)}% | ${region.inboundPercentage.toFixed(1)}% | ${region.outboundPercentage.toFixed(1)}% | ${region.directionGap.toFixed(1)}% | ${region.status === 'compliant' ? '✅' : region.status === 'warning' ? '⚠️' : '❌'} |`
).join('\n')}

### Regional Summary

${regionData.map(region => `
**${region.regionName}**
- Total Cities: ${region.totalCities}
- Population: ${region.totalPopulation.toLocaleString()}
- Compliance: ${region.actualPercentage.toFixed(1)}% (Standard: ${region.standardPercentage.toFixed(1)}%)
- Underserved Cities: ${region.underservedCitiesCount}
- Direction Gap: ${region.directionGap.toFixed(1)}% (${region.directionGap > 5 ? 'High asymmetry detected' : 'Balanced service'})
`).join('\n')}
`;

    // 5. Directional Analysis
    const citiesWithHighGap = cityData
      .filter(city => city.directionGap > 5)
      .sort((a, b) => b.directionGap - a.directionGap)
      .slice(0, 10);

    const directionalAnalysis = `
## 5. Directional Analysis (Inbound vs Outbound)

### Cities with Significant Directional Gaps (>5%)

${citiesWithHighGap.length > 0 ? `
| City | Region | Inbound % | Outbound % | Direction Gap | Dominant Direction |
|------|--------|-----------|------------|---------------|-------------------|
${citiesWithHighGap.map(city => 
  `| ${city.cityName} | ${city.regionName || 'N/A'} | ${city.inboundPercentage.toFixed(1)}% | ${city.outboundPercentage.toFixed(1)}% | ${city.directionGap.toFixed(1)}% | ${city.inboundPercentage > city.outboundPercentage ? 'Inbound' : 'Outbound'} |`
).join('\n')}

**Analysis:** ${citiesWithHighGap.length} cities show significant asymmetry between inbound and outbound service levels. This may indicate:
- Infrastructure limitations in one direction
- Carrier routing preferences
- Demand imbalances requiring attention
` : `
No cities show significant directional gaps. Service levels are balanced between inbound and outbound shipments.
`}

### Overall Directional Performance

| Direction | Avg. Compliance | Total Shipments |
|-----------|----------------|-----------------|
| Inbound | ${(cityData.reduce((sum, city) => sum + city.inboundPercentage * city.inboundShipments, 0) / cityData.reduce((sum, city) => sum + city.inboundShipments, 0)).toFixed(1)}% | ${cityData.reduce((sum, city) => sum + city.inboundShipments, 0)} |
| Outbound | ${(cityData.reduce((sum, city) => sum + city.outboundPercentage * city.outboundShipments, 0) / cityData.reduce((sum, city) => sum + city.outboundShipments, 0)).toFixed(1)}% | ${cityData.reduce((sum, city) => sum + city.outboundShipments, 0)} |
`;

    // 6. Recommendations
    const underservedCities = cityData.filter(city => city.status !== 'compliant');
    
    const recommendations = `
## 6. Recommendations

Based on the analysis of ${metrics.totalCities} cities and ${metrics.totalRegions} regions, the following actions are recommended:

### Priority 1: Address Underserved Cities

${underservedCities.length > 0 ? `
${underservedCities.slice(0, 5).map((city, idx) => `
${idx + 1}. **${city.cityName}** (${city.regionName || 'N/A'})
   - Current Compliance: ${city.actualPercentage.toFixed(1)}%
   - Standard: ${city.standardPercentage.toFixed(1)}%
   - Gap: ${city.deviation.toFixed(1)}%
   - Population Affected: ${(city.population || 0).toLocaleString()}
   - Recommended Action: ${city.deviation < -10 ? 'Urgent intervention required' : 'Improvement plan needed'}
`).join('\n')}
` : 'All cities meet compliance standards. Continue monitoring to maintain performance.'}

### Priority 2: Balance Directional Service

${citiesWithHighGap.length > 0 ? `
Focus on cities with high directional gaps:
${citiesWithHighGap.slice(0, 3).map((city, idx) => `
${idx + 1}. **${city.cityName}**: ${city.directionGap.toFixed(1)}% gap (${city.inboundPercentage > city.outboundPercentage ? 'Strengthen outbound' : 'Strengthen inbound'} service)
`).join('')}
` : 'Directional service is well-balanced across all cities.'}

### Priority 3: Regional Coordination

${regionData.filter(r => r.underservedCitiesCount > 0).map(region => `
- **${region.regionName}**: ${region.underservedCitiesCount} underserved cities require regional coordination
`).join('\n')}

### Priority 4: Share Best Practices

Learn from top performers:
${metrics.topBestCities.map((city, idx) => `
${idx + 1}. **${city.cityName}**: ${city.actualPercentage.toFixed(1)}% compliance (+${city.deviation.toFixed(1)}% above standard)
`).join('')}
`;

    // 7. Methodology
    const methodology = `
## 7. Methodology

### Data Sources

- **Shipment Data:** one_db table (origin_city_name, destination_city_name, on_time_delivery)
- **City Master:** cities table (name, region_id, population, classification)
- **Standards:** delivery_standards table (carrier, product, classification-specific thresholds)
- **Regional Grouping:** regions table (official regulatory regions)

### Calculations

**Service Equity Index (0-100):**
- Weighted average of city compliance rates
- Population-weighted to reflect citizen impact
- Normalized to 0-100 scale

**Population-Weighted Compliance:**
\`\`\`
Σ (City Compliance × City Population) / Total Population
\`\`\`

**Direction Gap:**
\`\`\`
|Inbound % - Outbound %|
\`\`\`

**Equity Status:**
- ✅ **Compliant:** Compliance ≥ Standard
- ⚠️ **Warning:** Compliance < Standard but ≥ (Standard - 5%)
- ❌ **Critical:** Compliance < (Standard - 5%)

### Period Analyzed

${filters?.startDate ? `From ${filters.startDate} to ${filters.endDate || 'present'}` : 'All available data'}

### Data Quality Notes

- Cities without population data are included in counts but excluded from population-weighted metrics
- Standards are carrier and product-specific, weighted by shipment volume
- Inbound = shipments arriving TO a city (destination)
- Outbound = shipments leaving FROM a city (origin)
`;

    // 8. Appendices
    const appendices = `
## 8. Appendices

### Appendix A: Complete City Data

| City | Region | Population | Shipments | Compliance | Standard | Status | Inbound % | Outbound % | Gap |
|------|--------|------------|-----------|------------|----------|--------|-----------|------------|-----|
${cityData.slice(0, 20).map(city => 
  `| ${city.cityName} | ${city.regionName || 'N/A'} | ${(city.population || 0).toLocaleString()} | ${city.totalShipments} | ${city.actualPercentage.toFixed(1)}% | ${city.standardPercentage.toFixed(1)}% | ${city.status === 'compliant' ? '✅' : city.status === 'warning' ? '⚠️' : '❌'} | ${city.inboundPercentage.toFixed(1)}% | ${city.outboundPercentage.toFixed(1)}% | ${city.directionGap.toFixed(1)}% |`
).join('\n')}
${cityData.length > 20 ? `\n*... and ${cityData.length - 20} more cities*` : ''}

### Appendix B: Glossary

- **Service Equity Index:** Overall measure of service fairness across territories (0-100)
- **Population-Weighted Compliance:** Compliance rate weighted by population impact
- **Underserved Cities:** Cities with compliance below established standards
- **Direction Gap:** Absolute difference between inbound and outbound compliance
- **Inbound:** Shipments arriving TO a city (city as destination)
- **Outbound:** Shipments leaving FROM a city (city as origin)

---

**Report Generated:** ${reportDate}  
**System:** ONEMS (Oficina Nacional de Evaluación y Monitoreo de Servicios)  
**Report Type:** Territory Equity Audit Report
`;

    // Combine all sections
    const markdown = `# Territory Equity Audit Report

**Generated:** ${reportDate}  
**System:** ONEMS - Oficina Nacional de Evaluación y Monitoreo de Servicios
${executiveSummary}
${overallPerformance}
${topPerformers}
${regionalAnalysis}
${directionalAnalysis}
${recommendations}
${methodology}
${appendices}
`;

    return markdown;
  };

  const downloadMarkdown = (markdown: string, filename: string = 'equity-audit-report.md') => {
    const blob = new Blob([markdown], { type: 'text/markdown;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  };

  return {
    generateMarkdownReport,
    downloadMarkdown,
  };
};
