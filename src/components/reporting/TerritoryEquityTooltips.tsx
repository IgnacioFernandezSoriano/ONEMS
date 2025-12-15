export const tooltips = {
  serviceEquityIndex: (
    <div className="space-y-2">
      <p className="font-semibold">Service Equity Index</p>
      <p><span className="font-medium">Description:</span> Measures consistency of service quality across all cities, weighted by population. Scale from 0-100 where 100 represents perfect equity.</p>
      <p><span className="font-medium">Interpretation:</span> Higher values indicate more uniform service distribution. Values below 80 suggest significant disparities between cities.</p>
      <p><span className="font-medium">Regulatory Use:</span> Demonstrates compliance with universal service obligations. Use in regulatory reports to show equitable service provision across territories.</p>
    </div>
  ),
  
  populationWeightedCompliance: (
    <div className="space-y-2">
      <p className="font-semibold">Population-Weighted Compliance</p>
      <p><span className="font-medium">Description:</span> Percentage of total population receiving on-time service. Calculated by weighting each city's compliance by its population.</p>
      <p><span className="font-medium">Interpretation:</span> Reflects actual impact on citizens rather than geographic coverage. A city with 1M people has more weight than one with 10K.</p>
      <p><span className="font-medium">Regulatory Use:</span> Primary metric for demonstrating citizen-centric service quality. Use to show percentage of population served within standards.</p>
    </div>
  ),
  
  underservedCities: (
    <div className="space-y-2">
      <p className="font-semibold">Underserved Cities</p>
      <p><span className="font-medium">Description:</span> Number of cities with compliance below critical threshold (typically &lt;80%). Indicates service quality failures.</p>
      <p><span className="font-medium">Interpretation:</span> Zero is the target. Any positive number indicates cities requiring immediate intervention.</p>
      <p><span className="font-medium">Regulatory Use:</span> Identifies non-compliant territories for enforcement action. Use to prioritize carrier improvement plans.</p>
    </div>
  ),
  
  citizensAffected: (
    <div className="space-y-2">
      <p className="font-semibold">Citizens Affected</p>
      <p><span className="font-medium">Description:</span> Total population living in underserved cities (critical status). Quantifies human impact of service failures.</p>
      <p><span className="font-medium">Interpretation:</span> Shows scale of service quality problem in human terms. Large numbers indicate widespread impact requiring urgent action.</p>
      <p><span className="font-medium">Regulatory Use:</span> Demonstrates severity of non-compliance in enforcement proceedings. Use to justify penalties or intervention requirements.</p>
    </div>
  ),
  
  topBestServed: (
    <div className="space-y-2">
      <p className="font-semibold">Top 3 Best Served Cities</p>
      <p><span className="font-medium">Description:</span> Cities with highest positive deviation from standard. Shows where service exceeds expectations.</p>
      <p><span className="font-medium">Interpretation:</span> Identifies best practices and successful service models. Large positive deviations may indicate over-servicing.</p>
      <p><span className="font-medium">Regulatory Use:</span> Highlight success stories in regulatory reports. Use to identify transferable best practices for underperforming areas.</p>
    </div>
  ),
  
  topWorstServed: (
    <div className="space-y-2">
      <p className="font-semibold">Top 3 Worst Served Cities</p>
      <p><span className="font-medium">Description:</span> Cities with lowest (most negative) deviation from standard. Only shows cities with critical or warning status.</p>
      <p><span className="font-medium">Interpretation:</span> Identifies priority areas for intervention. Persistent presence indicates systemic issues requiring carrier action.</p>
      <p><span className="font-medium">Regulatory Use:</span> Target enforcement actions and improvement requirements. Use to demonstrate need for carrier intervention or penalties.</p>
    </div>
  ),
  
  inboundOutboundChart: (
    <div className="space-y-2">
      <p className="font-semibold">Inbound vs Outbound Compliance Chart</p>
      <p><span className="font-medium">Description:</span> Shows the 10 cities with largest difference between inbound (arrivals) and outbound (departures) compliance rates.</p>
      <p><span className="font-medium">Interpretation:</span> Large gaps indicate directional service imbalances. May suggest route-specific issues or hub/spoke network problems.</p>
      <p><span className="font-medium">Regulatory Use:</span> Identify systematic directional biases requiring route-level investigation. Use to mandate carrier network improvements.</p>
    </div>
  ),
  
  cityTable: (
    <div className="space-y-2">
      <p className="font-semibold">City Equity Details Table</p>
      <p><span className="font-medium">Description:</span> Complete breakdown of service equity metrics for each city. Click city names for detailed carrier/product performance. Expandable rows show carrier-product breakdown.</p>
      <p><span className="font-medium">Interpretation:</span> Sort by any column to identify patterns. Red status indicates critical non-compliance. Click expand (▼) to see which carriers/products cause issues.</p>
      <p><span className="font-medium">Regulatory Use:</span> Detailed evidence for enforcement proceedings. Export to CSV for formal reports. Use carrier breakdown to assign responsibility.</p>
    </div>
  ),
  
  regionalChart: (
    <div className="space-y-2">
      <p className="font-semibold">Regional Equity Comparison Chart</p>
      <p><span className="font-medium">Description:</span> Visual comparison of actual compliance rates across regions. Bar color indicates status (green=compliant, amber=warning, red=critical). Red dashed line shows average standard threshold.</p>
      <p><span className="font-medium">Interpretation:</span> Bars below the red line indicate non-compliance. Clusters of low bars suggest regional systemic issues.</p>
      <p><span className="font-medium">Regulatory Use:</span> Visual evidence of regional disparities for presentations. Identify if delays are systematic (requiring carrier intervention) or sporadic (individual case investigation).</p>
    </div>
  ),
  
  regionalTable: (
    <div className="space-y-2">
      <p className="font-semibold">Regional Equity Analysis Table</p>
      <p><span className="font-medium">Description:</span> Aggregated service equity metrics by region. Click region names for detailed carrier/product breakdown. Expandable rows show carrier-product performance.</p>
      <p><span className="font-medium">Interpretation:</span> Helps identify geographic patterns in service quality. High underserved city counts indicate regional problems.</p>
      <p><span className="font-medium">Regulatory Use:</span> Demonstrate geographic equity in service provision. Use to justify region-specific interventions or investment requirements.</p>
    </div>
  ),
  
  treemap: (
    <div className="space-y-2">
      <p className="font-semibold">City Service Equity Treemap</p>
      <p><span className="font-medium">Description:</span> Visual representation where rectangle size represents population and color indicates compliance status (green=compliant, amber=warning, red=critical).</p>
      <p><span className="font-medium">Interpretation:</span> Large red rectangles indicate high-population cities with poor service - highest priority for intervention. Small green rectangles show low-impact compliant cities.</p>
      <p><span className="font-medium">Regulatory Use:</span> Visual evidence of compliance patterns. Identify if delays are systematic (requiring carrier intervention) or sporadic (individual case investigation). Use in enforcement presentations to demonstrate non-compliance trends.</p>
    </div>
  ),
};
