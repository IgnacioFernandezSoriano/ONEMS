// TypeScript interfaces for Reporting Module

export interface ReportingFilters {
  dateFrom: Date;
  dateTo: Date;
  carrier?: string;
  product?: string;
  routeClassification?: string;
  locality?: string;
}

export interface KPIMetric {
  label: string;
  value: number | string;
  unit?: string;
  trend?: 'up' | 'down' | 'stable';
  trendValue?: number;
  color?: 'green' | 'yellow' | 'red';
}

export interface GeneralPerformanceData {
  period: Date;
  compliancePercentage: number;
  avgBusinessDays: number;
  totalShipments: number;
}

export interface ComplianceByClassification {
  routeClassification: string;
  totalShipments: number;
  compliantShipments: number;
  compliancePercentage: number;
  avgBusinessDays: number;
  maxTransitDays: number;
  standardPercentage?: number;
  mostCommonRoute: string;
  trend?: 'up' | 'down' | 'stable';
}

export interface LocalityData {
  locality_name: string;
  locality_classification: 'capital' | 'major' | 'minor' | null;
  region_name?: string | null;
  total_shipments: number;
  compliance_percentage: number;
  avg_business_days: number;
  max_transit_days: number;
  primary_carrier: string;
  account_id: string;
}

export interface ShipmentEvent {
  timestamp: Date;
  event: string;
  location: string;
  durationFromPrevious?: number;
  additionalInfo?: Record<string, any>;
}

export interface ShipmentTracking {
  id: string;
  tagId: string;
  planName: string;
  carrierName: string;
  productName: string;
  originCityName: string;
  destinationCityName: string;
  sentAt: Date;
  receivedAt: Date;
  expectedDeliveryAt?: Date;
  totalTransitDays: number;
  businessTransitDays: number;
  onTimeDelivery: boolean;
  delayHours?: number;
  standardDeliveryHours: number;
  timeUnit: string;
  sourceDataSnapshot?: any;
}

export interface ShipmentTrackingData {
  tagId: string;
  planName: string;
  carrierName: string;
  productName: string;
  originCity: string;
  destinationCity: string;
  sentAt: Date;
  receivedAt: Date;
  expectedDeliveryAt: Date;
  totalTransitDays: number;
  businessTransitDays: number;
  onTimeDelivery: boolean;
  delayHours: number;
  standardDeliveryHours: number;
  timeUnit: string;
  events: ShipmentEvent[];
}

export interface ReportingConfig {
  accountId: string;
  complianceThresholdWarning: number;
  complianceThresholdCritical: number;
  defaultReportPeriod: 'week' | 'month' | 'quarter';
  useRegionalGrouping: boolean;
  preferredMapAlternative: 'treemap' | 'heatmap';
}

// Territory Equity Report Types

export interface CityEquityData {
  // Basic Info
  cityId: string;
  cityName: string;
  regionId: string;
  regionName: string | null;
  classification: 'capital' | 'major' | 'minor' | null;
  population: number | null;
  latitude?: number | null;
  longitude?: number | null;
  
  // Overall Metrics
  totalShipments: number;
  compliantShipments: number;
  standardPercentage: number;  // Weighted avg from delivery_standards
  standardDays: number;  // J+K Standard: Weighted avg allowed_days from delivery_standards
  actualDays: number;  // J+K Actual: Weighted avg business_days
  actualPercentage: number;
  deviation: number;
  status: 'compliant' | 'warning' | 'critical';
  aggregatedWarningThreshold: number;
  aggregatedCriticalThreshold: number;
  
  // Inbound (City as Destination)
  inboundShipments: number;
  inboundCompliant: number;
  inboundPercentage: number;
  inboundStandardPercentage: number;
  inboundStandardDays: number;
  inboundActualDays: number;
  inboundDeviation: number;
  
  // Outbound (City as Origin)
  outboundShipments: number;
  outboundCompliant: number;
  outboundPercentage: number;
  outboundStandardPercentage: number;
  outboundStandardDays: number;
  outboundActualDays: number;
  outboundDeviation: number;
  
  // Direction Analysis
  directionGap: number;
  
  // Carrier/Product Breakdown
  carrierProductBreakdown?: Array<{
    carrier: string;
    product: string;
    totalShipments: number;
    compliantShipments: number;
    actualPercentage: number;
    standardPercentage: number;
    standardDays: number;  // J+K Standard
    actualDays: number;  // J+K Actual
    deviation: number;
    inboundPercentage: number;
    outboundPercentage: number;
  }>;
  
  // RLS
  accountId: string;
}

export interface RegionEquityData {
  regionId: string;
  regionName: string;
  totalCities: number;
  totalPopulation: number;
  totalShipments: number;
  compliantShipments: number;
  standardPercentage: number;
  standardDays: number;  // J+K Standard
  actualDays: number;  // J+K Actual
  actualPercentage: number;
  deviation: number;
  status: 'compliant' | 'warning' | 'critical';
  aggregatedWarningThreshold: number;
  aggregatedCriticalThreshold: number;
  underservedCitiesCount: number;
  
  // Inbound metrics
  inboundShipments: number;
  inboundCompliant: number;
  inboundPercentage: number;
  inboundStandardPercentage: number;
  inboundStandardDays: number;
  inboundActualDays: number;
  inboundDeviation: number;
  
  // Outbound metrics
  outboundShipments: number;
  outboundCompliant: number;
  outboundPercentage: number;
  outboundStandardPercentage: number;
  outboundStandardDays: number;
  outboundActualDays: number;
  outboundDeviation: number;
  
  directionGap: number;
  
  // Carrier/Product Breakdown
  carrierProductBreakdown?: Array<{
    carrier: string;
    product: string;
    totalShipments: number;
    compliantShipments: number;
    actualPercentage: number;
    standardPercentage: number;
    standardDays: number;  // J+K Standard
    actualDays: number;  // J+K Actual
    deviation: number;
    inboundPercentage: number;
    outboundPercentage: number;
  }>;
  
  accountId: string;
}

export interface TerritoryEquityMetrics {
  // Main KPIs
  serviceEquityIndex: number;
  populationWeightedCompliance: number;
  sampleWeightedCompliance: number;
  underservedCitiesCount: number;
  citizensAffected: number;
  
  // Top 3 Best/Worst Cities
  topBestCities: Array<{
    cityName: string;
    actualPercentage: number;
    deviation: number;
    standardPercentage: number;
    standardDays: number;
    actualDays: number;
    inboundPercentage: number;
    outboundPercentage: number;
  }>;
  topWorstCities: Array<{
    cityName: string;
    actualPercentage: number;
    deviation: number;
    standardPercentage: number;
    standardDays: number;
    actualDays: number;
    inboundPercentage: number;
    outboundPercentage: number;
    status: 'compliant' | 'warning' | 'critical';
  }>;
  
  // Top 3 Best/Worst Regions
  topBestRegions: Array<{
    regionName: string;
    actualPercentage: number;
    deviation: number;
    standardPercentage: number;
    standardDays: number;
    actualDays: number;
    inboundPercentage: number;
    outboundPercentage: number;
  }>;
  topWorstRegions: Array<{
    regionName: string;
    actualPercentage: number;
    deviation: number;
    standardPercentage: number;
    standardDays: number;
    actualDays: number;
    inboundPercentage: number;
    outboundPercentage: number;
    status: 'compliant' | 'warning' | 'critical';
  }>;
  
  // Totals
  totalCities: number;
  totalPopulation: number;
  totalSamples: number;
  totalRegions: number;
}

export interface TerritoryEquityFilters {
  startDate?: string;
  endDate?: string;
  carrier?: string;
  product?: string;
  originCity?: string;
  destinationCity?: string;
  region?: string;
  direction?: 'inbound' | 'outbound' | 'both';
  equityStatus?: string[];
}
