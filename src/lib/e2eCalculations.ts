/**
 * E2E Calculations Module
 * 
 * Centralized calculation logic for End-to-End performance metrics.
 * This module provides functions to calculate metrics at different hierarchical levels:
 * - Route level (base)
 * - Inbound/Outbound (process level)
 * - City level (topological)
 * - Region level (topological)
 * 
 * All aggregations use weighted averages based on sample counts.
 */

import { supabase } from './supabase';

// ============================================================================
// TYPES
// ============================================================================

export interface Sample {
  id: string;
  originCityId: string;
  destinationCityId: string;
  carrierId: string;
  productId: string;
  businessTransitDays: number;
  isCompliant: boolean;
  shipmentDate: string;
}

export interface SLAStandard {
  originCityId: string;
  destinationCityId: string;
  carrierId: string;
  productId: string;
  standardPercentage: number;
  standardDays: number;
  warningThreshold: number;
  criticalThreshold: number;
}

export interface RouteMetrics {
  originCityId: string;
  destinationCityId: string;
  carrierId: string;
  productId: string;
  
  totalSamples: number;
  compliantSamples: number;
  
  actualPercentage: number;
  actualDays: number;
  jkActual: number;
  
  standardPercentage: number;
  standardDays: number;
  
  deviation: number;
  status: 'compliant' | 'warning' | 'critical';
  
  warningThreshold: number;
  criticalThreshold: number;
}

export interface AggregatedMetrics {
  totalSamples: number;
  compliantSamples: number;
  
  actualPercentage: number;
  actualDays: number;
  jkActual: number;
  
  standardPercentage: number;
  standardDays: number;
  
  deviation: number;
  status: 'compliant' | 'warning' | 'critical';
}

export interface E2EFilters {
  startDate?: string;
  endDate?: string;
  carrierId?: string;
  productId?: string;
  originCityId?: string;
  destinationCityId?: string;
  regionId?: string;
}

// ============================================================================
// CORE CALCULATION FUNCTIONS
// ============================================================================

/**
 * Calculate J+K Actual as the day where cumulative samples reach the target STD %
 */
export function calculateJKActual(
  daysArray: number[],
  standardPercentage: number,
  fallbackDays: number
): number {
  if (daysArray.length === 0 || standardPercentage <= 0) {
    return fallbackDays;
  }

  // Create distribution: day -> count
  const distribution: Record<number, number> = {};
  daysArray.forEach(day => {
    const roundedDay = Math.round(day);
    distribution[roundedDay] = (distribution[roundedDay] || 0) + 1;
  });

  // Sort days ascending
  const sortedDays = Object.keys(distribution)
    .map(Number)
    .sort((a, b) => a - b);

  // Find day where cumulative samples >= target
  let cumulativeSamples = 0;
  const targetSamples = (standardPercentage / 100) * daysArray.length;

  for (const day of sortedDays) {
    cumulativeSamples += distribution[day];
    if (cumulativeSamples >= targetSamples) {
      return day;
    }
  }

  // If we reach here, return the last day
  return sortedDays[sortedDays.length - 1] || fallbackDays;
}

/**
 * Calculate metrics for a single route
 */
export function calculateRouteMetrics(
  samples: Sample[],
  slaStandard: SLAStandard | null,
  globalWarningThreshold: number = 80,
  globalCriticalThreshold: number = 75
): RouteMetrics | null {
  if (samples.length === 0) {
    return null;
  }

  const firstSample = samples[0];
  const totalSamples = samples.length;
  const compliantSamples = samples.filter(s => s.isCompliant).length;
  
  // Actual percentage
  const actualPercentage = (compliantSamples / totalSamples) * 100;
  
  // Actual days (average)
  const actualDays = samples.reduce((sum, s) => sum + s.businessTransitDays, 0) / totalSamples;
  
  // Standard values from SLA
  const standardPercentage = slaStandard?.standardPercentage || 0;
  const standardDays = slaStandard?.standardDays || 0;
  
  // J+K Actual
  const daysArray = samples.map(s => s.businessTransitDays);
  const jkActual = calculateJKActual(daysArray, standardPercentage, standardDays);
  
  // Deviation
  const deviation = actualPercentage - standardPercentage;
  
  // Thresholds
  const warningThreshold = slaStandard?.warningThreshold || globalWarningThreshold;
  const criticalThreshold = slaStandard?.criticalThreshold || globalCriticalThreshold;
  
  // Status
  const status: 'compliant' | 'warning' | 'critical' =
    actualPercentage >= warningThreshold ? 'compliant' :
    actualPercentage >= criticalThreshold ? 'warning' : 'critical';
  
  return {
    originCityId: firstSample.originCityId,
    destinationCityId: firstSample.destinationCityId,
    carrierId: firstSample.carrierId,
    productId: firstSample.productId,
    totalSamples,
    compliantSamples,
    actualPercentage,
    actualDays,
    jkActual,
    standardPercentage,
    standardDays,
    deviation,
    status,
    warningThreshold,
    criticalThreshold,
  };
}

/**
 * Aggregate multiple routes using weighted averages
 */
export function aggregateRoutes(
  routes: RouteMetrics[],
  globalWarningThreshold: number = 80,
  globalCriticalThreshold: number = 75
): AggregatedMetrics | null {
  if (routes.length === 0) {
    return null;
  }

  const totalSamples = routes.reduce((sum, r) => sum + r.totalSamples, 0);
  const compliantSamples = routes.reduce((sum, r) => sum + r.compliantSamples, 0);
  
  if (totalSamples === 0) {
    return null;
  }
  
  // Actual percentage (weighted)
  const actualPercentage = (compliantSamples / totalSamples) * 100;
  
  // Weighted averages for other metrics
  const actualDays = routes.reduce((sum, r) => 
    sum + (r.actualDays * r.totalSamples), 0) / totalSamples;
  
  const standardPercentage = routes.reduce((sum, r) => 
    sum + (r.standardPercentage * r.totalSamples), 0) / totalSamples;
  
  const standardDays = routes.reduce((sum, r) => 
    sum + (r.standardDays * r.totalSamples), 0) / totalSamples;
  
  const jkActual = routes.reduce((sum, r) => 
    sum + (r.jkActual * r.totalSamples), 0) / totalSamples;
  
  // Deviation
  const deviation = actualPercentage - standardPercentage;
  
  // Weighted thresholds
  const warningThreshold = routes.reduce((sum, r) => 
    sum + (r.warningThreshold * r.totalSamples), 0) / totalSamples;
  
  const criticalThreshold = routes.reduce((sum, r) => 
    sum + (r.criticalThreshold * r.totalSamples), 0) / totalSamples;
  
  // Status
  const status: 'compliant' | 'warning' | 'critical' =
    actualPercentage >= warningThreshold ? 'compliant' :
    actualPercentage >= criticalThreshold ? 'warning' : 'critical';
  
  return {
    totalSamples,
    compliantSamples,
    actualPercentage,
    actualDays,
    jkActual,
    standardPercentage,
    standardDays,
    deviation,
    status,
  };
}

// ============================================================================
// DATA LOADING FUNCTIONS
// ============================================================================

/**
 * Load base samples from ONE DB with filters applied
 */
export async function loadSamples(
  accountId: string,
  filters: E2EFilters = {}
): Promise<Sample[]> {
  let query = supabase
    .from('one_db')
    .select('*')
    .eq('account_id', accountId);

  if (filters.startDate) {
    query = query.gte('shipment_date', filters.startDate);
  }
  if (filters.endDate) {
    query = query.lte('shipment_date', filters.endDate);
  }
  if (filters.carrierId) {
    query = query.eq('carrier_id', filters.carrierId);
  }
  if (filters.productId) {
    query = query.eq('product_id', filters.productId);
  }
  if (filters.originCityId) {
    query = query.eq('origin_city_id', filters.originCityId);
  }
  if (filters.destinationCityId) {
    query = query.eq('destination_city_id', filters.destinationCityId);
  }

  const { data, error } = await query;

  if (error) {
    throw error;
  }

  return (data || []).map(row => ({
    id: row.id,
    originCityId: row.origin_city_id,
    destinationCityId: row.destination_city_id,
    carrierId: row.carrier_id,
    productId: row.product_id,
    businessTransitDays: row.business_transit_days,
    isCompliant: row.is_compliant,
    shipmentDate: row.shipment_date,
  }));
}

/**
 * Load SLA standards
 */
export async function loadSLAStandards(
  accountId: string
): Promise<Map<string, SLAStandard>> {
  const { data, error } = await supabase
    .from('delivery_standards')
    .select('*')
    .eq('account_id', accountId);

  if (error) {
    throw error;
  }

  const standardsMap = new Map<string, SLAStandard>();

  (data || []).forEach(row => {
    const key = `${row.origin_city_id}-${row.destination_city_id}-${row.carrier_id}-${row.product_id}`;
    standardsMap.set(key, {
      originCityId: row.origin_city_id,
      destinationCityId: row.destination_city_id,
      carrierId: row.carrier_id,
      productId: row.product_id,
      standardPercentage: row.success_percentage || 0,
      standardDays: row.standard_time || 0,
      warningThreshold: row.warning_threshold || 80,
      criticalThreshold: row.critical_threshold || 75,
    });
  });

  return standardsMap;
}

/**
 * Group samples by route
 */
export function groupSamplesByRoute(samples: Sample[]): Map<string, Sample[]> {
  const routeMap = new Map<string, Sample[]>();

  samples.forEach(sample => {
    const key = `${sample.originCityId}-${sample.destinationCityId}-${sample.carrierId}-${sample.productId}`;
    if (!routeMap.has(key)) {
      routeMap.set(key, []);
    }
    routeMap.get(key)!.push(sample);
  });

  return routeMap;
}

// ============================================================================
// AGGREGATION FUNCTIONS
// ============================================================================

/**
 * Aggregate inbound routes for a city
 */
export function aggregateInbound(
  routes: RouteMetrics[],
  cityId: string,
  globalWarningThreshold: number = 80,
  globalCriticalThreshold: number = 75
): AggregatedMetrics {
  const inboundRoutes = routes.filter(r => r.destinationCityId === cityId);
  const aggregated = aggregateRoutes(inboundRoutes, globalWarningThreshold, globalCriticalThreshold);
  
  if (!aggregated) {
    return {
      totalSamples: 0,
      compliantSamples: 0,
      actualPercentage: 0,
      actualDays: 0,
      jkActual: 0,
      standardPercentage: 0,
      standardDays: 0,
      deviation: 0,
      status: 'critical',
    };
  }
  
  return aggregated;
}

/**
 * Aggregate outbound routes for a city
 */
export function aggregateOutbound(
  routes: RouteMetrics[],
  cityId: string,
  globalWarningThreshold: number = 80,
  globalCriticalThreshold: number = 75
): AggregatedMetrics {
  const outboundRoutes = routes.filter(r => r.originCityId === cityId);
  const aggregated = aggregateRoutes(outboundRoutes, globalWarningThreshold, globalCriticalThreshold);
  
  if (!aggregated) {
    return {
      totalSamples: 0,
      compliantSamples: 0,
      actualPercentage: 0,
      actualDays: 0,
      jkActual: 0,
      standardPercentage: 0,
      standardDays: 0,
      deviation: 0,
      status: 'critical',
    };
  }
  
  return aggregated;
}

/**
 * Aggregate city metrics from inbound and outbound
 */
export function aggregateCity(
  inbound: AggregatedMetrics,
  outbound: AggregatedMetrics,
  globalWarningThreshold: number = 80,
  globalCriticalThreshold: number = 75
): AggregatedMetrics {
  const totalSamples = inbound.totalSamples + outbound.totalSamples;
  const compliantSamples = inbound.compliantSamples + outbound.compliantSamples;
  
  if (totalSamples === 0) {
    return {
      totalSamples: 0,
      compliantSamples: 0,
      actualPercentage: 0,
      actualDays: 0,
      jkActual: 0,
      standardPercentage: 0,
      standardDays: 0,
      deviation: 0,
      status: 'critical',
    };
  }
  
  // Weighted averages
  const actualPercentage = (compliantSamples / totalSamples) * 100;
  
  const actualDays = (
    (inbound.actualDays * inbound.totalSamples) +
    (outbound.actualDays * outbound.totalSamples)
  ) / totalSamples;
  
  const standardPercentage = (
    (inbound.standardPercentage * inbound.totalSamples) +
    (outbound.standardPercentage * outbound.totalSamples)
  ) / totalSamples;
  
  const standardDays = (
    (inbound.standardDays * inbound.totalSamples) +
    (outbound.standardDays * outbound.totalSamples)
  ) / totalSamples;
  
  const jkActual = (
    (inbound.jkActual * inbound.totalSamples) +
    (outbound.jkActual * outbound.totalSamples)
  ) / totalSamples;
  
  const deviation = actualPercentage - standardPercentage;
  
  const status: 'compliant' | 'warning' | 'critical' =
    actualPercentage >= globalWarningThreshold ? 'compliant' :
    actualPercentage >= globalCriticalThreshold ? 'warning' : 'critical';
  
  return {
    totalSamples,
    compliantSamples,
    actualPercentage,
    actualDays,
    jkActual,
    standardPercentage,
    standardDays,
    deviation,
    status,
  };
}

/**
 * Aggregate region metrics from cities
 */
export function aggregateRegion(
  cityMetrics: AggregatedMetrics[],
  globalWarningThreshold: number = 80,
  globalCriticalThreshold: number = 75
): AggregatedMetrics {
  const totalSamples = cityMetrics.reduce((sum, c) => sum + c.totalSamples, 0);
  const compliantSamples = cityMetrics.reduce((sum, c) => sum + c.compliantSamples, 0);
  
  if (totalSamples === 0) {
    return {
      totalSamples: 0,
      compliantSamples: 0,
      actualPercentage: 0,
      actualDays: 0,
      jkActual: 0,
      standardPercentage: 0,
      standardDays: 0,
      deviation: 0,
      status: 'critical',
    };
  }
  
  // Weighted averages
  const actualPercentage = (compliantSamples / totalSamples) * 100;
  
  const actualDays = cityMetrics.reduce((sum, c) => 
    sum + (c.actualDays * c.totalSamples), 0) / totalSamples;
  
  const standardPercentage = cityMetrics.reduce((sum, c) => 
    sum + (c.standardPercentage * c.totalSamples), 0) / totalSamples;
  
  const standardDays = cityMetrics.reduce((sum, c) => 
    sum + (c.standardDays * c.totalSamples), 0) / totalSamples;
  
  const jkActual = cityMetrics.reduce((sum, c) => 
    sum + (c.jkActual * c.totalSamples), 0) / totalSamples;
  
  const deviation = actualPercentage - standardPercentage;
  
  const status: 'compliant' | 'warning' | 'critical' =
    actualPercentage >= globalWarningThreshold ? 'compliant' :
    actualPercentage >= globalCriticalThreshold ? 'warning' : 'critical';
  
  return {
    totalSamples,
    compliantSamples,
    actualPercentage,
    actualDays,
    jkActual,
    standardPercentage,
    standardDays,
    deviation,
    status,
  };
}

// ============================================================================
// HIGH-LEVEL FUNCTION
// ============================================================================

export interface BaseSample extends Sample {
  slaStandard: SLAStandard | null;
}

/**
 * Load base data from ONE DB + SLA standards
 */
export async function loadBaseData(
  accountId: string,
  filters: E2EFilters = {}
): Promise<BaseSample[]> {
  const [samples, slaStandardsMap] = await Promise.all([
    loadSamples(accountId, filters),
    loadSLAStandards(accountId),
  ]);
  
  return samples.map(sample => {
    const key = `${sample.originCityId}-${sample.destinationCityId}-${sample.carrierId}-${sample.productId}`;
    const slaStandard = slaStandardsMap.get(key) || null;
    
    return {
      ...sample,
      slaStandard,
    };
  });
}
